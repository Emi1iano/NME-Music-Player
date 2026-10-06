import 'dart:async';
import 'dart:ffi';
import 'dart:io';
import 'dart:isolate';

import 'package:ffi/ffi.dart';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';

import 'app_log.dart';

// The C function exported by Emiliano's Zig library
// (backend/NetworksButBetter/backend/src/api.zig):
//   int32_t clientAPI(const char* command);   0 = ok, -1 = error
typedef _ClientApiC = Int32 Function(Pointer<Utf8> command);
typedef _ClientApiDart = int Function(Pointer<Utf8> command);

/// Where a sync is at, for the Sync panel.
enum SyncState {
  idle,        // not started this session
  connecting,  // key sent to the server, waiting for another device
  paired,      // connected to the other device (directly or via the server)
  cancelling,  // Cancel pressed: asking the backend to stop
  cancelled,   // stopped by Cancel
  noPartner,   // the server found no device with this key in time (it waits 20 s)
  finished,    // the backend's sync returned 0
  failed,      // the backend's sync returned an error
}

/// The bridge between the Flutter app and the Zig backend (libbackend.so).
///
/// The backend is a command-line style API: we send it a text command like
/// "add Album/song.mp3" and it works with files under the current working
/// folder (the app's data folder):
///   music/               the songs (this is also the app's Music folder)
///   testing/app/key.txt  this device's 8-digit sync key
///                        (app/key.txt once the backend's TESTING flag is off)
///
/// Commands: add [path], rename [path] [newname], sync [key], sync_new_key.
/// `sync` never returns (it keeps the connection open), so it runs in its own
/// isolate; see startSync.
class Backend extends ChangeNotifier {
  // Singleton: one bridge for the whole app (Backend.instance).
  Backend._();
  static final Backend instance = Backend._();

  static const _libName = 'libbackend.so';
  static const _addedPrefsKey = 'backend_added_paths';

  bool available = false;   // true once libbackend.so loaded on this device
  String? unavailableReason;
  late String baseDir;      // the backend's working folder
  String? key;              // this device's sync key, once known
  Set<String> added = {};   // song paths already sent to the backend with `add`

  // Calls go through this chain so only one runs at a time (the backend
  // shares files between commands, so two at once could corrupt them).
  Future<void> _queue = Future.value();

  String get musicPath => p.join(baseDir, 'music');

  // Where the backend keeps the key: testing/app/ while its TESTING flag is
  // on, app/ otherwise. The old backend used app/cache/.
  List<File> get _keyFiles => [
        File(p.join(baseDir, 'testing', 'app', 'key.txt')),
        File(p.join(baseDir, 'app', 'key.txt')),
      ];
  File get _oldKeyFile => File(p.join(baseDir, 'app', 'cache', 'key.txt'));

  /// The key file the backend is using (the first that exists).
  File get _activeKeyFile =>
      _keyFiles.firstWhere((f) => f.existsSync(), orElse: () => _keyFiles.first);

  /// Called at startup with the folder that holds the app's data.
  Future<void> init(String baseDir) async {
    this.baseDir = baseDir;
    await Directory(musicPath).create(recursive: true);
    added = (await SharedPreferences.getInstance()).getStringList(_addedPrefsKey)?.toSet() ?? {};

    if (!Platform.isAndroid) {
      // Only Android libraries are built so far.
      unavailableReason = 'The backend library is only built for Android so far.';
      AppLog.instance.info('Backend: not available on ${Platform.operatingSystem}');
      notifyListeners();
      return;
    }
    try {
      DynamicLibrary.open(_libName).lookupFunction<_ClientApiC, _ClientApiDart>('clientAPI');
      available = true;
    } catch (e, st) {
      unavailableReason = 'Could not load $_libName: $e';
      AppLog.instance.error('Backend: could not load $_libName', e, st);
      notifyListeners();
      return;
    }

    // The backend uses paths relative to the current folder, and an app's
    // current folder starts as "/" (not writable). Point it at our data folder.
    Directory.current = baseDir;
    _captureStderr();
    _blockStdin();
    AppLog.instance.info('Backend: loaded $_libName, working folder $baseDir');

    // Keep the phone's existing key when moving from the old backend layout.
    if (!_keyFiles.any((f) => f.existsSync()) && _oldKeyFile.existsSync()) {
      final old = (await _oldKeyFile.readAsString()).trim();
      if (RegExp(r'^\d{8}$').hasMatch(old)) {
        await _writeKey(old);
        AppLog.instance.info('Backend: kept the existing sync key for the new backend');
      }
    }

    key = await readKey();
    if (key == null) {
      // Emiliano's design: a device gets a key the first time the app runs,
      // then reuses it from the key file.
      AppLog.instance.info('Backend: no sync key yet, generating one');
      key = await generateNewKey();
    } else {
      AppLog.instance.info('Backend: using saved sync key');
    }
    notifyListeners();
  }

  // ---------------------------------------------------------------- commands

  /// `add [path]`: tells the backend to track a song so it gets synced.
  /// [trackPath] is relative to the Music folder, e.g. "Album/song.mp3".
  Future<bool> add(String trackPath) async {
    if (!_checkArg(trackPath, 'add')) return false;
    final code = await _run('add $trackPath');
    if (code != 0) return false;
    added.add(trackPath);
    await _saveAdded();
    notifyListeners();
    return true;
  }

  /// `rename [path] [newname]`: renames a song file (it stays in the same
  /// folder). [newName] is just the file name. Returns true only if the file
  /// really has the new name afterwards, so the app never moves a song's
  /// stats to a name that doesn't exist.
  Future<bool> rename(String trackPath, String newName) async {
    if (!_checkArg(trackPath, 'rename') || !_checkArg(newName, 'rename')) return false;
    if (newName.contains('/') || newName.contains(r'\')) {
      AppLog.instance.warning('Backend: new name "$newName" must not contain a folder');
      return false;
    }
    final code = await _run('rename $trackPath $newName');
    final folder = p.posix.dirname(trackPath);
    final newPath = folder == '.' ? newName : '$folder/$newName';
    final moved = File(p.join(musicPath, newPath)).existsSync() &&
        !File(p.join(musicPath, trackPath)).existsSync();
    if (code != 0 || !moved) {
      AppLog.instance.warning('Backend: rename "$trackPath" -> "$newName" did not rename '
          'the file (code $code)');
      return false;
    }
    if (added.remove(trackPath)) {
      added.add(newPath);
      await _saveAdded();
    }
    notifyListeners();
    return true;
  }

  /// `sync_new_key`: makes a new 8-digit key and saves it in the key file
  /// (the backend doesn't return it, so we read the file afterwards).
  Future<String?> generateNewKey() async {
    final code = await _run('sync_new_key');
    final newKey = await readKey();
    if (code != 0 || newKey == null) {
      AppLog.instance.warning('Backend: sync_new_key failed (code $code)');
      return key;
    }
    key = newKey;
    AppLog.instance.info('Backend: new sync key generated');
    notifyListeners();
    return newKey;
  }

  // ------------------------------------------------------------------ sync

  SyncState syncState = SyncState.idle;
  bool get isSyncing =>
      syncState == SyncState.connecting ||
      syncState == SyncState.paired ||
      syncState == SyncState.cancelling;
  String? syncPeer;              // "1.2.3.4:5678" once the server pairs us
  String? syncMode;              // "direct" or "through the server"
  DateTime? syncStartedAt;
  final List<String> syncLines = []; // the backend's messages during this sync
  Timer? _syncPoll;

  /// `sync`: sends this phone's key to the pairing server and waits for
  /// another device with the same key, then connects to it directly.
  ///
  /// The backend's sync doesn't return (it keeps the connection open), so it
  /// runs in its OWN background isolate instead of the command queue; add,
  /// rename and sync_new_key keep working meanwhile. Its messages are read
  /// every second and shown in the Sync panel and the debug log.
  ///
  /// [withKey]: another device's key, to pair with that device. It's saved
  /// as this phone's key first, because the backend's `sync [key]` currently
  /// checks the key but then uses the saved one.
  Future<void> startSync({String? withKey}) async {
    if (!available || isSyncing) return;
    if (withKey != null && !RegExp(r'^\d{8}$').hasMatch(withKey)) return;
    final command = withKey == null ? 'sync' : 'sync $withKey';
    if (withKey != null) {
      await _queue; // let any running command finish before changing the key
      await _writeKey(withKey);
      key = withKey;
    }
    syncState = SyncState.connecting;
    syncPeer = null;
    syncMode = null;
    _punchingDone = false;
    syncLines.clear();
    syncStartedAt = DateTime.now();
    notifyListeners();
    _logBackendOutput(); // skip older output so the panel only shows this sync

    AppLog.instance.info('Backend > $command');
    await AppLog.instance.flush();

    final done = ReceivePort();
    done.listen((message) {
      done.close();
      _syncPoll?.cancel();
      _readSyncOutput();
      final code = message is int ? message : -1;
      AppLog.instance.info('Backend < $command = $code');
      final wasCancelling = syncState == SyncState.cancelling;
      _stopCancelling();
      // The server sends "Disconnected" (TERMINATE) to a device that waited
      // 20 s without another device using the same key.
      final nobodyCame = syncPeer == null && !_punchingDone && syncMode == 'disconnected';
      syncState = wasCancelling
          ? SyncState.cancelled
          : nobodyCame
              ? SyncState.noPartner
              : (code == 0 ? SyncState.finished : SyncState.failed);
      if (wasCancelling) AppLog.instance.info('Backend: sync cancelled');
      notifyListeners();
    });
    try {
      await Isolate.spawn(_syncEntry, (command, done.sendPort),
          onError: done.sendPort, debugName: 'backend-sync');
    } catch (e, st) {
      done.close();
      AppLog.instance.error('Backend: could not start sync', e, st);
      syncState = SyncState.failed;
      notifyListeners();
      return;
    }
    _syncPoll = Timer.periodic(const Duration(seconds: 1), (_) => _readSyncOutput());
  }

  /// Background isolate entry point: runs the (long) sync command, then
  /// reports its exit code back to the app.
  static void _syncEntry((String, SendPort) args) {
    final (command, done) = args;
    done.send(_callNative(command));
  }

  /// Copies new backend output into the panel and works out the status from
  /// the backend's own messages (e.g. "Connecting with 1.2.3.4:5678").
  void _readSyncOutput() {
    final lines = _logBackendOutput();
    if (lines.isEmpty) return;
    syncLines.addAll(lines);
    if (syncLines.length > 200) syncLines.removeRange(0, syncLines.length - 200);
    for (final line in lines) {
      // The server matched us with another device using the same key.
      final m = RegExp(r'Other Client Public IP: (\S+)').firstMatch(line);
      if (m != null) syncPeer = m.group(1);
      // Connected: directly ("Done Punching", "USE LOCAL/PUBLIC IP") or, if a
      // direct connection fails, relayed through the server.
      final cancelling = syncState == SyncState.cancelling;
      if (line.contains('Done Punching') || line.startsWith('USE ')) {
        _punchingDone = true;
        if (!cancelling) {
          syncState = SyncState.paired;
          syncMode = 'direct';
        }
      } else if (line.contains('Switching to relay')) {
        _punchingDone = true;
        if (!cancelling) {
          syncState = SyncState.paired;
          syncMode = 'through the server';
        }
      } else if (line.startsWith('Disconnected')) {
        // The other device or the server (after 60 s of relaying) hung up.
        syncMode = 'disconnected';
      }
    }
    notifyListeners();
  }

  // --------------------------------------------------------- cancelling sync

  bool _punchingDone = false;        // the backend finished its connection attempts
  RawDatagramSocket? _cancelSocket;  // used to send the backend its stop message
  Timer? _cancelTimer;
  DateTime? _cancelStarted;

  // The backend's "disconnect" message code (ClientCode.TERMINATE in
  // backend/NetworksButBetter/backend/src/server.zig).
  static const _codeTerminate = 0x0A;

  /// Stops a running sync without closing the app.
  ///
  /// The backend's sync ends when its listener receives a TERMINATE message
  /// (the same one the server or the other device sends to disconnect). Its
  /// UDP socket listens on this phone, so we send it TERMINATE on 127.0.0.1.
  /// That works whether it's still waiting for the server or connected.
  /// If connected, we first "type" EXIT into its input so it tells the other
  /// device it's leaving.
  Future<void> cancelSync() async {
    if (!isSyncing || syncState == SyncState.cancelling) return;
    final before = syncState;
    syncState = SyncState.cancelling;
    _cancelStarted = DateTime.now();
    notifyListeners();
    AppLog.instance.info('Backend: cancelling sync');

    final backendPort = _findBackendPort();
    if (backendPort == null) {
      // The sync is still running: say so instead of pretending it stopped.
      AppLog.instance.warning('Backend: could not find the sync socket to stop it');
      syncState = before;
      notifyListeners();
      return;
    }
    final socket = await RawDatagramSocket.bind(InternetAddress.loopbackIPv4, 0);
    _cancelSocket = socket;
    final backend = InternetAddress.loopbackIPv4;

    // Connected: EXIT makes the backend send TERMINATE to the other device.
    // (Only when connected; otherwise the EXIT would sit in its input and end
    // the NEXT sync immediately.)
    if (before == SyncState.paired) _typeToBackend('EXIT\n');

    // Stop its listener; repeat every half second until sync returns (UDP
    // messages can get lost), for up to 15 seconds.
    void stop() => socket.send([_codeTerminate], backend, backendPort);
    stop();
    _cancelTimer = Timer.periodic(const Duration(milliseconds: 500), (_) {
      _readSyncOutput();
      stop();
      if (DateTime.now().difference(_cancelStarted!) > const Duration(seconds: 15)) {
        // Still running: show it as running again so the user can retry.
        AppLog.instance.warning('Backend: sync did not stop yet; try Cancel again '
            'or close and reopen the app');
        _stopCancelling();
        syncState = _punchingDone ? SyncState.paired : before;
        notifyListeners();
      }
    });
  }

  void _stopCancelling() {
    _cancelTimer?.cancel();
    _cancelTimer = null;
    _cancelSocket?.close();
    _cancelSocket = null;
  }

  /// The UDP port the backend's sync is using. It starts at 32145 and counts
  /// up if that's taken. Apps can't read /proc/net/udp on Android 10+, and
  /// listing /proc/self/fd fails now and then (the backend opens and closes
  /// sockets while it runs), so simply ask the system about each possible
  /// file descriptor number with getsockname(); non-sockets just fail.
  int? _findBackendPort() {
    try {
      final getsockname = DynamicLibrary.process().lookupFunction<
          Int32 Function(Int32, Pointer<Uint8>, Pointer<Uint32>),
          int Function(int, Pointer<Uint8>, Pointer<Uint32>)>('getsockname');
      final addr = malloc<Uint8>(128);
      final len = malloc<Uint32>(1);
      try {
        for (var fd = 3; fd < 1024; fd++) {
          len.value = 128;
          if (getsockname(fd, addr, len) != 0) continue; // not an open socket
          // sockaddr_in / sockaddr_in6: 2-byte family, then the port (big-endian).
          final family = addr[0] | (addr[1] << 8);
          if (family != 2 && family != 10) continue; // AF_INET, AF_INET6
          final port = (addr[2] << 8) | addr[3];
          if (port >= 32145 && port < 32145 + 100) return port;
        }
      } finally {
        malloc.free(addr);
        malloc.free(len);
      }
    } catch (e) {
      AppLog.instance.warning('Backend: could not look up the sync socket', e);
    }
    return null;
  }

  /// Sends a text message to the connected device. The backend's sync reads
  /// typed lines from stdin and sends each one to the other side (which
  /// prints "recieved: ..."), so we "type" the message into its stdin pipe.
  /// Returns false if not connected or the message isn't allowed.
  bool sendSyncMessage(String text) {
    final message = text.replaceAll(RegExp(r'[\r\n]+'), ' ').trim();
    if (syncState != SyncState.paired || message.isEmpty) return false;
    // "EXIT" is the backend's disconnect command: use Cancel sync for that.
    if (message.toUpperCase() == 'EXIT') return false;
    // The backend reads input into a 256-byte buffer.
    final clipped = message.length > 200 ? message.substring(0, 200) : message;
    _typeToBackend('$clipped\n');
    syncLines.add('you: $clipped');
    AppLog.instance.info('Backend: sent message "$clipped"');
    notifyListeners();
    return true;
  }

  /// Writes [text] into the backend's stdin, as if typed on a keyboard.
  void _typeToBackend(String text) {
    final fd = _stdinWriteFd;
    if (fd == null) return;
    final write = DynamicLibrary.process()
        .lookupFunction<IntPtr Function(Int32, Pointer<Uint8>, IntPtr), int Function(int, Pointer<Uint8>, int)>('write');
    final bytes = text.codeUnits;
    final buf = malloc<Uint8>(bytes.length);
    try {
      buf.asTypedList(bytes.length).setAll(0, bytes);
      write(fd, buf, bytes.length);
    } finally {
      malloc.free(buf);
    }
  }

  /// Developer tool (Debug log → Run backend command): sends any command as
  /// typed, e.g. "rename album1/a.mp3 b.mp3", and returns the exit code.
  Future<int> runCommand(String command) async {
    if (!available) return -1;
    final code = await _run(command.trim());
    key = await readKey() ?? key;
    notifyListeners();
    return code;
  }

  /// Calls `add` for every song not sent to the backend yet (after each
  /// library scan). Songs with spaces in their path are skipped for now.
  Future<void> registerNew(Iterable<String> trackPaths) async {
    if (!available || isSyncing) return;
    final missing = trackPaths.where((t) => !added.contains(t)).toList();
    if (missing.isEmpty) return;
    final withSpaces = missing.where((t) => t.contains(' ')).length;
    var ok = 0, failed = 0;
    for (final path in missing.where((t) => !t.contains(' '))) {
      if (await add(path)) {
        ok++;
      } else {
        failed++;
      }
    }
    AppLog.instance.info('Backend: added $ok new song(s)'
        '${failed > 0 ? ', $failed failed' : ''}'
        '${withSpaces > 0 ? ', $withSpaces skipped (spaces in file name)' : ''}');
  }

  Future<void> _saveAdded() async =>
      (await SharedPreferences.getInstance()).setStringList(_addedPrefsKey, added.toList());

  // ---------------------------------------------------------- its key file

  /// The 8-digit key from the backend's key file, or null if there isn't one.
  Future<String?> readKey() async {
    for (final f in _keyFiles) {
      try {
        final text = (await f.readAsString()).trim();
        if (RegExp(r'^\d{8}$').hasMatch(text)) return text;
      } catch (_) {
        // missing: try the next location
      }
    }
    return null;
  }

  /// Saves [newKey] where the backend reads it: exactly 8 digits, no newline
  /// (its key reader rejects anything that isn't 8 bytes long).
  Future<void> _writeKey(String newKey) async {
    final file = _activeKeyFile;
    await file.parent.create(recursive: true);
    await file.writeAsString(newKey, flush: true);
  }

  // ------------------------------------------------------------- internals

  /// The backend splits commands on spaces, so a path or name with a space
  /// would be read as two separate arguments. Refuse instead of sending a
  /// command that would do the wrong thing.
  bool _checkArg(String value, String command) {
    if (!available) return false;
    if (value.trim().isEmpty || value.contains(' ')) {
      AppLog.instance.warning('Backend: can\'t $command "$value": the backend '
          'doesn\'t support spaces in file names yet');
      return false;
    }
    return true;
  }

  /// Runs one command in a background isolate (so the UI never freezes) and
  /// returns the backend's exit code. Commands run one at a time.
  Future<int> _run(String command) {
    // The backend keeps its connection state in one shared global that EVERY
    // command replaces (and then closes its socket). Running a command during
    // a sync would cut the sync's connection, so wait until it's over.
    if (isSyncing) {
      AppLog.instance.warning('Backend: "$command" skipped while a sync is running');
      return Future.value(-1);
    }
    final result = Completer<int>();
    _queue = _queue.then((_) async {
      // Breadcrumb saved to disk BEFORE calling native code: if the backend
      // ever crashes the app, the debug log still shows what it was doing.
      AppLog.instance.info('Backend > $command');
      await AppLog.instance.flush();
      try {
        final code = await _runInIsolate(command);
        AppLog.instance.info('Backend < $command = $code');
        _logBackendOutput();
        result.complete(code);
      } catch (e, st) {
        AppLog.instance.error('Backend: "$command" threw', e, st);
        result.complete(-1);
      }
    });
    return result.future;
  }

  // ------------------------------------------------ backend's own messages

  File get _stderrFile => File(p.join(baseDir, 'app', 'cache', 'backend_output.txt'));
  int _stderrRead = 0;

  /// The backend reports problems with std.debug.print, which goes to
  /// "stderr". Apps have no console, so those messages would be lost.
  /// Point stderr at a file instead (C functions creat + dup2), and after each
  /// command copy anything new into the debug log.
  void _captureStderr() {
    try {
      final libc = DynamicLibrary.process();
      final creat = libc.lookupFunction<Int32 Function(Pointer<Utf8>, Uint32),
          int Function(Pointer<Utf8>, int)>('creat');
      final dup2 = libc.lookupFunction<Int32 Function(Int32, Int32), int Function(int, int)>('dup2');
      _stderrFile.parent.createSync(recursive: true);
      final path = _stderrFile.path.toNativeUtf8();
      try {
        final fd = creat(path, 420); // 420 = 0644 permissions; starts empty
        if (fd < 0 || dup2(fd, 2) < 0) {
          AppLog.instance.warning('Backend: could not capture its messages');
        }
      } finally {
        malloc.free(path);
      }
      _stderrRead = 0;
    } catch (e) {
      AppLog.instance.warning('Backend: could not capture its messages', e);
    }
  }

  /// Copies new lines the backend printed into the debug log, and returns them.
  List<String> _logBackendOutput() {
    final lines = <String>[];
    try {
      final bytes = _stderrFile.readAsBytesSync();
      if (bytes.length <= _stderrRead) return lines;
      final text = String.fromCharCodes(bytes.sublist(_stderrRead)).trim();
      _stderrRead = bytes.length;
      for (final line in text.split('\n')) {
        // Skip noise the Android emulator's graphics driver writes to stderr.
        if (line.trim().isEmpty || line.startsWith('s_gl')) continue;
        AppLog.instance.info('Backend says: ${line.trim()}');
        lines.add(line.trim());
      }
    } catch (_) {
      // No output file yet: nothing to copy.
    }
    return lines;
  }

  /// After pairing, the backend's sync reads typed messages from "stdin"
  /// (cin) in an endless loop and sends each line to the other device. An app
  /// has no keyboard: stdin is empty, so every read returns instantly and the
  /// loop would flood the other device with packets. Give stdin a pipe that
  /// we keep open but never write to, so that read simply waits instead.
  int? _stdinWriteFd; // our end of the backend's stdin pipe

  void _blockStdin() {
    try {
      final libc = DynamicLibrary.process();
      final pipe = libc.lookupFunction<Int32 Function(Pointer<Int32>), int Function(Pointer<Int32>)>('pipe');
      final dup2 = libc.lookupFunction<Int32 Function(Int32, Int32), int Function(int, int)>('dup2');
      final fds = malloc<Int32>(2);
      try {
        if (pipe(fds) != 0 || dup2(fds[0], 0) < 0) {
          AppLog.instance.warning('Backend: could not set up stdin for sync');
        } else {
          _stdinWriteFd = fds[1];
        }
        // fds[1] (the write end) is deliberately left open for the app's
        // lifetime: while it's open, reads from stdin wait instead of ending,
        // and cancelSync() writes "EXIT" into it.
      } finally {
        malloc.free(fds);
      }
    } catch (e) {
      AppLog.instance.warning('Backend: could not set up stdin for sync', e);
    }
  }

  /// Creates the isolate closure in a static method so it captures ONLY the
  /// command string. (A closure made inside _run would also capture things
  /// like the Completer, which can't be sent to another isolate.)
  static Future<int> _runInIsolate(String command) =>
      Isolate.run(() => _callNative(command));

  /// Runs inside the background isolate: open the library, convert the Dart
  /// string to a C string, call clientAPI, free the C string.
  static int _callNative(String command) {
    final clientApi =
        DynamicLibrary.open(_libName).lookupFunction<_ClientApiC, _ClientApiDart>('clientAPI');
    final cString = command.toNativeUtf8();
    try {
      return clientApi(cString);
    } finally {
      malloc.free(cString);
    }
  }
}
