import 'dart:async';
import 'dart:ffi';
import 'dart:io';
import 'dart:isolate';

import 'package:ffi/ffi.dart';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;

import 'app_log.dart';

// The C function exported by Emiliano's Zig library (backend/client/src/api.zig):
//   int32_t clientAPI(const char* command);   0 = ok, -1 = error
typedef _ClientApiC = Int32 Function(Pointer<Utf8> command);
typedef _ClientApiDart = int Function(Pointer<Utf8> command);

/// The bridge between the Flutter app and the Zig backend (libbackend.so).
///
/// The backend is a command-line style API: we send it a text command like
/// "add Album/song.mp3" and it reads/writes files under the current working
/// folder:
///   app/music/          the songs (this is also the app's Music folder)
///   app/state/table.txt tracked songs, one "id path" per line
///   app/state/history.txt changes waiting to be synced
///   app/cache/key.txt   this device's 8-digit sync key
///
/// Supported for now: add, rename, sync_new_key. ("sync" itself still waits
/// for keyboard input, so it can't be called from an app yet.)
class Backend extends ChangeNotifier {
  // Singleton: one bridge for the whole app (Backend.instance).
  Backend._();
  static final Backend instance = Backend._();

  static const _libName = 'libbackend.so';

  bool available = false;   // true once libbackend.so loaded on this device
  String? unavailableReason;
  late String baseDir;      // the backend's working folder (contains app/)
  String? key;              // this device's sync key, once known
  Set<String> tracked = {}; // song paths the backend has recorded

  // Calls go through this chain so only one runs at a time (the backend
  // shares files between commands, so two at once could corrupt them).
  Future<void> _queue = Future.value();

  String get musicPath => p.join(baseDir, 'app', 'music');
  File get _keyFile => File(p.join(baseDir, 'app', 'cache', 'key.txt'));
  File get _tableFile => File(p.join(baseDir, 'app', 'state', 'table.txt'));

  /// Called at startup with the folder that holds the app's data.
  Future<void> init(String baseDir) async {
    this.baseDir = baseDir;
    await Directory(musicPath).create(recursive: true);

    if (!Platform.isAndroid) {
      // Only Android libraries are built so far (iOS targets are commented
      // out in the backend's build.zig).
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
    AppLog.instance.info('Backend: loaded $_libName, working folder $baseDir');

    key = await readKey();
    if (key == null) {
      // Emiliano's design: a device gets a key the first time the app runs,
      // then reuses it from the cache file.
      AppLog.instance.info('Backend: no sync key yet, generating one');
      key = await generateNewKey();
    } else {
      AppLog.instance.info('Backend: using saved sync key');
    }
    tracked = await readTracked();
    notifyListeners();
  }

  // ---------------------------------------------------------------- commands

  /// `add [path]`: tells the backend to track a song so it gets synced.
  /// [trackPath] is relative to the Music folder, e.g. "Album/song.mp3".
  /// Returns true if the backend recorded it in table.txt.
  Future<bool> add(String trackPath) async {
    if (!_checkArg(trackPath, 'add')) return false;
    final code = await _run('add $trackPath');
    tracked = await readTracked();
    notifyListeners();
    final recorded = tracked.contains(trackPath);
    if (code == 0 && !recorded) {
      // Seen during testing: the backend's add checks that the file exists
      // relative to its working folder, not the music folder, so it returns
      // "ok" without recording anything.
      AppLog.instance.warning('Backend: "add $trackPath" returned ok but the song '
          'was not recorded in table.txt');
    }
    return recorded;
  }

  /// `rename [path] [newname]`: renames a song file (it stays in the same
  /// folder) and updates the backend's table. [newName] is just the file name.
  Future<bool> rename(String trackPath, String newName) async {
    if (!_checkArg(trackPath, 'rename') || !_checkArg(newName, 'rename')) return false;
    if (newName.contains('/') || newName.contains(r'\')) {
      AppLog.instance.warning('Backend: new name "$newName" must not contain a folder');
      return false;
    }
    // WORKAROUND: for a song at the top of the music folder, the backend
    // opens its folder as "" (empty), which works on Windows but fails on
    // Android/Linux. "./song.mp3" is the same file but gives it "." instead.
    // (Its table.txt update compares the path text, so it won't match "./"
    // entries; that only matters once `add` can record songs.)
    final pathArg = trackPath.contains('/') ? trackPath : './$trackPath';
    final code = await _run('rename $pathArg $newName');
    final folder = p.posix.dirname(trackPath);
    final newPath = folder == '.' ? newName : '$folder/$newName';
    final moved = File(p.join(musicPath, newPath)).existsSync() &&
        !File(p.join(musicPath, trackPath)).existsSync();
    tracked = await readTracked();
    notifyListeners();
    if (code != 0 || !moved) {
      AppLog.instance.warning('Backend: rename "$trackPath" -> "$newName" failed (code $code)');
      return false;
    }
    return true;
  }

  /// `sync_new_key`: makes a new 8-digit key and saves it in app/cache/key.txt
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

  /// Developer tool (Debug log → Run backend command): sends any command as
  /// typed, e.g. "rename album1/a.mp3 b.mp3", and returns the exit code.
  Future<int> runCommand(String command) async {
    if (!available) return -1;
    final code = await _run(command.trim());
    tracked = await readTracked();
    key = await readKey() ?? key;
    notifyListeners();
    return code;
  }

  /// Calls `add` for every song the backend isn't tracking yet (after each
  /// library scan). Songs with spaces in their path are skipped for now.
  Future<void> registerNew(Iterable<String> trackPaths) async {
    if (!available) return;
    tracked = await readTracked();
    final missing = trackPaths.where((t) => !tracked.contains(t)).toList();
    if (missing.isEmpty) return;
    final withSpaces = missing.where((t) => t.contains(' ')).length;
    var added = 0, notRecorded = 0;
    for (final path in missing.where((t) => !t.contains(' '))) {
      if (await add(path)) {
        added++;
      } else {
        notRecorded++;
      }
    }
    AppLog.instance.info('Backend: registered $added new song(s)'
        '${notRecorded > 0 ? ', $notRecorded not recorded' : ''}'
        '${withSpaces > 0 ? ', $withSpaces skipped (spaces in file name)' : ''}');
  }

  // ------------------------------------------------------- reading its files

  /// The 8-digit key from app/cache/key.txt, or null if there isn't a valid one.
  Future<String?> readKey() async {
    try {
      final text = (await _keyFile.readAsString()).trim();
      return RegExp(r'^\d{8}$').hasMatch(text) ? text : null;
    } catch (_) {
      return null;
    }
  }

  /// Song paths listed in app/state/table.txt. Format: first line is the
  /// last id used, then one "id path" line per tracked song.
  Future<Set<String>> readTracked() async {
    try {
      final lines = await _tableFile.readAsLines();
      return {
        for (final line in lines.skip(1))
          if (line.contains(' ')) line.substring(line.indexOf(' ') + 1).trim(),
      }..remove('');
    } catch (_) {
      return {};
    }
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

  /// Copies new lines the backend printed into the debug log.
  void _logBackendOutput() {
    try {
      final bytes = _stderrFile.readAsBytesSync();
      if (bytes.length <= _stderrRead) return;
      final text = String.fromCharCodes(bytes.sublist(_stderrRead)).trim();
      _stderrRead = bytes.length;
      for (final line in text.split('\n')) {
        // Skip noise the Android emulator's graphics driver writes to stderr.
        if (line.trim().isEmpty || line.startsWith('s_gl')) continue;
        AppLog.instance.info('Backend says: ${line.trim()}');
      }
    } catch (_) {
      // No output file yet: nothing to copy.
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
