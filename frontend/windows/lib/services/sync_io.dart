import 'dart:async';
import 'dart:convert';
import 'dart:ffi';
import 'dart:io';
import 'dart:isolate';
import 'package:ffi/ffi.dart';
import 'sync_outcome.dart';

typedef _Native = Int32 Function(Pointer<Utf8>);
typedef _Dart = int Function(Pointer<Utf8>);

/// Desktop bridge to backend.dll, Emiliano's Zig backend (backend/ in this
/// repo, the same one the phone app uses). The app does NOT change the
/// backend; it only speaks the backend's own command API, like the phone app:
///   add "song.mp3"   tell the backend about a song so the next sync sends it
///   sync [key]       pair with the other device and exchange songs
///   sync_new_key     make a new key (saved in key.txt)
///   testreset        forget the song table and the pending changes
///
/// The backend works under the current folder (we point it at [dataDir]):
///   testing/app/music/   the songs (this is the app's music folder)
///   testing/app/key.txt  this device's 8-digit key
///   testing/app/changes.txt, musicTable.txt   what the next sync sends
/// Its server address is built in (backend/client.zig).
///
/// The backend reports progress only through stderr (std.debug.print) and its
/// `sync` never returns on its own, so: stderr is pointed at a file that we
/// read while syncing, and a sync is ended by sending TERMINATE to the
/// backend's own UDP socket on 127.0.0.1.
class MusicSync {
  static const supported = true;
  static final _keyRe = RegExp(r'^[0-9]{8}$');
  static const _audio = {'.mp3', '.flac', '.wav', '.m4a', '.aac', '.ogg', '.opus', '.wma'};

  /// Where the backend keeps its files (it uses paths relative to this folder).
  static String get dataDir =>
      Platform.environment['NME_DATA_DIR'] ?? // for tests
      '${Platform.environment['LOCALAPPDATA'] ?? Directory.systemTemp.path}\\NME';

  // "testing/app" while TESTING = true in backend/client.zig, "app" once it's off.
  static const _appFolder = 'testing\\app';
  static String get _appDir => '$dataDir\\$_appFolder';

  /// The music folder: the backend always keeps (and receives) songs here.
  static String defaultFolder() => '$_appDir\\music';

  /// Why the backend can't be used (null when it works).
  static String? unavailableReason;

  static const _codeTerminate = 0x0A; // ClientCode.TERMINATE in backend/server.zig
  static const _firstPort = 32145; // the backend's UDP port; counts up if taken

  // ------------------------------------------------------------ files

  /// True for a relative path with '/' separators that stays inside the folder.
  static bool isSafeRelPath(String p) {
    if (p.isEmpty || p.length > 300 || p.startsWith('/')) return false;
    if (p.contains('\\') || p.contains(':') || p.codeUnits.any((c) => c < 32)) return false;
    return p.split('/').every((s) => s.isNotEmpty && s != '.' && s != '..');
  }

  /// File extensions (no dot) the app treats as songs, for file pickers.
  static List<String> get audioExtensions => [for (final e in _audio) e.substring(1)];

  static bool _isAudio(String p) {
    final dot = p.lastIndexOf('.');
    return dot >= 0 && _audio.contains(p.substring(dot).toLowerCase());
  }

  /// Audio files under [folder], as sorted relative paths with '/' separators.
  static Future<List<String>> scan(String folder) async {
    final dir = Directory(folder.replaceAll(RegExp(r'[\\/]+$'), ''));
    await dir.create(recursive: true);
    final out = <String>[];
    await for (final e in dir.list(recursive: true, followLinks: false)) {
      if (e is! File) continue;
      final rel = e.path.substring(dir.path.length + 1).replaceAll('\\', '/');
      if (_isAudio(rel) && isSafeRelPath(rel)) out.add(rel);
    }
    return out..sort();
  }

  /// Audio files under [dir], as full paths.
  static Future<List<String>> audioFilesIn(String dir) async {
    final out = <String>[];
    await for (final e in Directory(dir).list(recursive: true, followLinks: false)) {
      if (e is File && _isAudio(e.path)) out.add(e.path);
    }
    return out..sort();
  }

  /// Copies the song files in [sources] into [folder] (the library's top
  /// level). A song that's already there is left alone. Each copy goes to
  /// "<name>.part" first so a half-copied song never shows up.
  static Future<({int added, int existing, int unsupported, int failed})> importFiles(
      String folder, List<String> sources) async {
    final dir = Directory(folder.replaceAll(RegExp(r'[\\/]+$'), ''));
    await dir.create(recursive: true);
    var added = 0, existing = 0, unsupported = 0, failed = 0;
    for (final src in sources) {
      final name = src.split(RegExp(r'[\\/]')).last;
      if (!_isAudio(name) || !isSafeRelPath(name)) {
        unsupported++;
        continue;
      }
      final dest = File('${dir.path}\\$name');
      if (await dest.exists()) {
        existing++;
        continue;
      }
      final part = File('${dest.path}.part');
      try {
        await File(src).copy(part.path);
        await part.rename(dest.path);
        added++;
      } on FileSystemException {
        failed++;
        try {
          if (await part.exists()) await part.delete();
        } on FileSystemException {
          // Nothing more to clean up.
        }
      }
    }
    return (added: added, existing: existing, unsupported: unsupported, failed: failed);
  }

  static Future<void> deleteFile(String folder, String path) async {
    if (!isSafeRelPath(path)) throw ArgumentError('Path must be relative to the music folder.');
    final f = File('$folder/$path');
    if (await f.exists()) await f.delete();
  }

  /// Opens the folder in Explorer.
  static Future<void> openFolder(String folder) async {
    await Directory(folder).create(recursive: true);
    await Process.start('explorer.exe', [folder], mode: ProcessStartMode.detached);
  }

  // ------------------------------------------------------------ start-up

  static bool _ready = false;

  /// Points the backend at [dataDir], captures its messages and hides the
  /// console its `ipconfig` helper would otherwise flash. Returns a message
  /// if the backend can't be used.
  static Future<String?> init() async {
    if (_ready) return unavailableReason;
    _ready = true;
    try {
      await Directory(defaultFolder()).create(recursive: true);
      DynamicLibrary.open('backend.dll').lookupFunction<_Native, _Dart>('clientAPI');
    } catch (e) {
      return unavailableReason = 'Could not load backend.dll: $e';
    }
    // The backend uses paths relative to the current folder.
    Directory.current = dataDir;
    _hideConsole();
    _captureStderr();
    return null;
  }

  static DynamicLibrary get _kernel32 => DynamicLibrary.open('kernel32.dll');

  /// The backend runs `ipconfig` to find this PC's address. A window-less app
  /// has no console, so Windows would pop one up for it every time. Giving the
  /// app a hidden console of its own stops that.
  static void _hideConsole() {
    try {
      final k = _kernel32;
      final alloc = k.lookupFunction<Int32 Function(), int Function()>('AllocConsole');
      if (alloc() == 0) return; // already has one (started from a terminal)
      final getWindow = k.lookupFunction<IntPtr Function(), int Function()>('GetConsoleWindow');
      final showWindow = DynamicLibrary.open('user32.dll')
          .lookupFunction<Int32 Function(IntPtr, Int32), int Function(int, int)>('ShowWindow');
      final hwnd = getWindow();
      if (hwnd != 0) showWindow(hwnd, 0); // SW_HIDE
    } catch (_) {
      // Worst case a console flashes during a sync.
    }
  }

  static String get _stderrPath => '$dataDir\\backend_output.txt';
  static int _stderrRead = 0;

  /// The backend prints its progress with std.debug.print (stderr), which a
  /// window-less app doesn't have: point stderr at a file we can read.
  static void _captureStderr() {
    try {
      final k = _kernel32;
      final createFile = k.lookupFunction<
          IntPtr Function(Pointer<Utf16>, Uint32, Uint32, Pointer<Void>, Uint32, Uint32, IntPtr),
          int Function(Pointer<Utf16>, int, int, Pointer<Void>, int, int, int)>('CreateFileW');
      final setStdHandle =
          k.lookupFunction<Int32 Function(Uint32, IntPtr), int Function(int, int)>('SetStdHandle');
      final path = _stderrPath.toNativeUtf16();
      try {
        // GENERIC_WRITE, share read+write, CREATE_ALWAYS (starts empty).
        final h = createFile(path, 0x40000000, 3, nullptr, 2, 0x80, 0);
        if (h == -1 || setStdHandle(0xFFFFFFF4, h) == 0) {
          unavailableReason = 'Could not capture the backend\'s messages.';
        }
      } finally {
        calloc.free(path);
      }
      _stderrRead = 0;
    } catch (e) {
      unavailableReason = 'Could not capture the backend\'s messages: $e';
    }
  }

  /// New complete lines the backend printed since the last call.
  static List<String> _newOutput() {
    try {
      final f = File(_stderrPath).openSync();
      try {
        final len = f.lengthSync();
        if (len <= _stderrRead) return const [];
        f.setPositionSync(_stderrRead);
        final bytes = f.readSync(len - _stderrRead);
        final end = bytes.lastIndexOf(10) + 1; // only whole lines
        if (end == 0) return const [];
        _stderrRead += end;
        final text = utf8.decode(bytes.sublist(0, end), allowMalformed: true);
        return [
          for (final l in text.split('\n'))
            if (l.replaceAll(_ansi, '').trim().isNotEmpty) l.replaceAll(_ansi, '').trim()
        ];
      } finally {
        f.closeSync();
      }
    } on FileSystemException {
      return const [];
    }
  }

  static final _ansi = RegExp(r'\x1B\[[0-9;]*m');

  // ------------------------------------------------------------ commands

  static Future<void> _queue = Future.value();
  static bool _syncing = false;

  /// Quotes one argument so the backend reads a path with spaces as one.
  static String _quote(String v) => '"${v.replaceAll('"', r'\"')}"';

  /// Runs one backend command off the UI thread, one at a time. The backend
  /// keeps its connection in one global that every command replaces, so a
  /// command during a sync would cut the sync: those are refused (-1).
  static Future<int> _run(String command) {
    if (_syncing || unavailableReason != null) return Future.value(-1);
    final result = Completer<int>();
    _queue = _queue.then((_) async {
      try {
        result.complete(await _runInIsolate(command));
      } catch (_) {
        result.complete(-1);
      }
      _newOutput(); // keep the sync's output clean
    });
    return result.future;
  }

  /// The closure is made here, so it captures only [command] (anything else
  /// in scope, like a Completer, can't be sent to an isolate).
  static Future<int> _runInIsolate(String command) => Isolate.run(() => _call(command));

  static int _call(String command) {
    final f = DynamicLibrary.open('backend.dll').lookupFunction<_Native, _Dart>('clientAPI');
    final ptr = command.toNativeUtf8();
    try {
      return f(ptr);
    } finally {
      malloc.free(ptr);
    }
  }

  /// Tells the backend about a song ([rel] is relative to the music folder).
  static Future<bool> add(String rel) async {
    if (!isSafeRelPath(rel)) return false;
    return await _run('add ${_quote(rel)}') == 0;
  }

  /// Forgets the backend's song table and pending changes (not the songs or the key).
  static Future<bool> resetIndex() async => await _run('testreset') == 0;

  /// The saved key, if any.
  static Future<String?> readKey() async {
    for (final p in ['$dataDir\\testing\\app\\key.txt', '$dataDir\\app\\key.txt']) {
      final f = File(p);
      if (await f.exists()) {
        final k = (await f.readAsString()).trim();
        if (_keyRe.hasMatch(k)) return k;
      }
    }
    return null;
  }

  /// Makes a new key (the backend saves it; we read it back).
  static Future<String?> newKey() async {
    await _run('sync_new_key');
    return readKey();
  }

  /// How many songs the next sync will send (the "add" lines in changes.txt).
  static int pendingAdds() {
    try {
      return File('$_appDir\\changes.txt')
          .readAsLinesSync()
          .where((l) => l.trim().startsWith('add'))
          .length;
    } on FileSystemException {
      return 0;
    }
  }

  // ------------------------------------------------------------ sync

  /// Pairs with the other device (press Sync on both with the same [key]; the
  /// server waits about 20 s) and exchanges songs. Ends by itself once
  /// everything we had to send is confirmed and nothing more is arriving.
  static Future<SyncOutcome> sync({required String key, void Function(String)? onStatus}) async {
    if (unavailableReason != null) return SyncOutcome(message: unavailableReason!);
    if (!_keyRe.hasMatch(key)) throw ArgumentError('Key must be 8 digits (0-9).');
    if (_syncing) return const SyncOutcome(message: 'A sync is already running');
    await _queue; // let a running command finish first
    _syncing = true;
    try {
      _unloadBackend();
      return await _SyncRun(key, onStatus).run();
    } finally {
      _syncing = false;
    }
  }

  /// Unloads backend.dll (it's loaded again by the next call) so its global
  /// state starts fresh. The backend remembers the number of the last transfer
  /// it received (backend/client.zig, Reliable.Rx.last_done) and treats a new
  /// transfer with the same number as a repeat and drops it. Numbers restart
  /// at 1 whenever the other app restarts, so without this a song can be
  /// skipped in a later sync.
  static void _unloadBackend() {
    try {
      final k = _kernel32;
      final getModule = k.lookupFunction<IntPtr Function(Pointer<Utf16>), int Function(Pointer<Utf16>)>(
          'GetModuleHandleW');
      final free = k.lookupFunction<Int32 Function(IntPtr), int Function(int)>('FreeLibrary');
      final name = 'backend.dll'.toNativeUtf16();
      try {
        // Every call that loaded it added a reference: release them all.
        for (var i = 0; i < 10000; i++) {
          final h = getModule(name);
          if (h == 0) break;
          free(h);
        }
      } finally {
        calloc.free(name);
      }
    } catch (_) {
      // Worst case a song is skipped; the next sync gets it.
    }
  }

  static bool _stopRequested = false;

  /// Stops a running sync.
  static Future<void> cancel() async {
    _stopRequested = true;
  }

  /// The backend's UDP port: found by asking Windows which UDP ports this
  /// process has open (the backend counts up from 32145 if it's taken).
  static int? _findBackendPort() {
    try {
      final get = DynamicLibrary.open('iphlpapi.dll').lookupFunction<
          Uint32 Function(Pointer<Void>, Pointer<Uint32>, Int32, Uint32, Int32, Uint32),
          int Function(Pointer<Void>, Pointer<Uint32>, int, int, int, int)>('GetExtendedUdpTable');
      final size = calloc<Uint32>();
      Pointer<Uint8>? buf;
      try {
        get(nullptr, size, 0, 2, 1, 0); // AF_INET, UDP_TABLE_OWNER_PID: ask for the size
        buf = calloc<Uint8>(size.value + 64);
        size.value += 64;
        if (get(buf.cast(), size, 0, 2, 1, 0) != 0) return null;
        final entries = buf.cast<Uint32>()[0];
        for (var i = 0; i < entries; i++) {
          final localPort = buf.cast<Uint32>()[2 + i * 3];
          final owner = buf.cast<Uint32>()[3 + i * 3];
          final port = ((localPort & 0xFF) << 8) | ((localPort >> 8) & 0xFF); // network order
          if (owner == pid && port >= _firstPort && port < _firstPort + 100) return port;
        }
      } finally {
        if (buf != null) calloc.free(buf);
        calloc.free(size);
      }
    } catch (_) {
      // Falls through: caller reports it couldn't stop the sync.
    }
    return null;
  }

  /// Datagrams this PC has received and sent so far (all programs): used to
  /// tell that a song is still being transferred while the backend is quiet.
  static int _udpDatagrams() {
    try {
      final get = DynamicLibrary.open('iphlpapi.dll')
          .lookupFunction<Uint32 Function(Pointer<Uint32>), int Function(Pointer<Uint32>)>('GetUdpStatistics');
      final s = calloc<Uint32>(5);
      try {
        if (get(s) != 0) return 0;
        return s[0] + s[3]; // dwInDatagrams + dwOutDatagrams
      } finally {
        calloc.free(s);
      }
    } catch (_) {
      return 0;
    }
  }
}

/// One `sync` call: runs it, follows its messages and ends it when done.
class _SyncRun {
  _SyncRun(this.key, this.onStatus);

  final String key;
  final void Function(String)? onStatus;

  // How long to wait before deciding the sync is over.
  static const _noPartner = Duration(seconds: 30); // the server itself gives up after ~20 s
  static const _quiet = Duration(seconds: 8); // all sent, nothing more happening
  static const _stuck = Duration(seconds: 90); // nothing happening at all
  static const _busyRate = 30; // datagrams per second that mean "a song is moving"

  bool paired = false;
  bool peerLeft = false;
  int sent = 0, confirmed = 0, incomplete = 0, errors = 0;
  final received = <String>[];
  late final int toSend;
  late DateTime lastActivity;
  DateTime lastBusy = DateTime.fromMillisecondsSinceEpoch(0);
  int lastDatagrams = 0;
  DateTime lastSample = DateTime.now();
  DateTime? stopStarted;
  String stopReason = '';
  DateTime lastStopTry = DateTime.fromMillisecondsSinceEpoch(0);
  String lastLine = '';

  void say(String m) => onStatus?.call(m);

  Future<SyncOutcome> run() async {
    MusicSync._stopRequested = false;
    toSend = MusicSync.pendingAdds();
    MusicSync._newOutput(); // skip older output
    final started = DateTime.now();
    lastActivity = started;
    lastDatagrams = MusicSync._udpDatagrams();
    say('Waiting for your other device to sync with key $key...');

    var finished = false;
    var rc = -1;
    // `sync` doesn't return until the backend is told to stop.
    MusicSync._runInIsolate('sync $key').then((v) {
      rc = v;
      finished = true;
    }, onError: (Object _) {
      finished = true;
    });

    while (!finished) {
      await Future<void>.delayed(const Duration(milliseconds: 400));
      for (final line in MusicSync._newOutput()) {
        _onLine(line);
      }
      _sampleTraffic();
      if (stopStarted == null) _decide(started);
      if (stopStarted != null) _keepStopping();
    }
    for (final line in MusicSync._newOutput()) {
      _onLine(line);
    }

    final completed = paired && confirmed >= toSend && stopReason == 'done';
    return SyncOutcome(
      message: _message(rc, completed),
      paired: paired,
      completed: completed,
      sent: sent,
      received: received,
      incomplete: incomplete,
    );
  }

  void _onLine(String line) {
    lastLine = line;
    if (paired) lastActivity = DateTime.now();
    if (line.contains('Other Client Public IP')) {
      say('Found your other device, connecting...');
    } else if (line.contains('Done Punching') || line.startsWith('USE ')) {
      if (!paired) lastActivity = DateTime.now();
      paired = true;
      say('Connected to your other device');
    } else if (line.contains('Switching to relay')) {
      if (!paired) lastActivity = DateTime.now();
      paired = true;
      say('Connected through the server');
    } else if (line.startsWith('Sending file ')) {
      sent++;
      say('Sending ${line.substring('Sending file '.length)} ($sent of $toSend)');
    } else if (line.startsWith('Done sending')) {
      confirmed++;
    } else if (line.startsWith('Successfully recieved song ')) {
      final name = line.substring('Successfully recieved song '.length).trim();
      if (name.isNotEmpty) received.add(name);
      say('Received $name');
    } else if (line.startsWith('Hashes dont match')) {
      incomplete++;
    } else if (line.startsWith('Error recieving')) {
      errors++;
    } else if (line.startsWith('Disconnected')) {
      peerLeft = true;
    }
  }

  void _sampleTraffic() {
    final now = DateTime.now();
    final secs = now.difference(lastSample).inMilliseconds / 1000;
    if (secs < 0.3) return;
    final d = MusicSync._udpDatagrams();
    if ((d - lastDatagrams) / secs >= _busyRate) lastBusy = now;
    lastDatagrams = d;
    lastSample = now;
  }

  bool get _busy => DateTime.now().difference(lastBusy) < const Duration(seconds: 3);

  /// Decides whether to end the sync now.
  void _decide(DateTime started) {
    final now = DateTime.now();
    final quiet = now.difference(lastActivity);
    if (MusicSync._stopRequested) {
      _stop('cancelled');
    } else if (!paired && now.difference(started) > _noPartner) {
      _stop('nobody');
    } else if (paired && confirmed >= toSend && quiet > _quiet && !_busy) {
      // Everything we had to send is confirmed and nothing is arriving.
      _stop('done');
    } else if (paired && quiet > _stuck && !_busy) {
      _stop('stuck');
    }
  }

  void _stop(String reason) {
    stopReason = reason;
    stopStarted = DateTime.now();
    say(reason == 'done' ? 'Finishing up...' : 'Stopping...');
  }

  /// The backend ends its sync when its listener gets a TERMINATE message, so
  /// send one to its UDP port (repeated, UDP can lose it) until it returns.
  void _keepStopping() {
    final now = DateTime.now();
    if (now.difference(lastStopTry) < const Duration(milliseconds: 500)) return;
    lastStopTry = now;
    final port = MusicSync._findBackendPort();
    if (port == null) return;
    RawDatagramSocket.bind(InternetAddress.loopbackIPv4, 0).then((s) {
      s.send([MusicSync._codeTerminate], InternetAddress.loopbackIPv4, port);
      s.close();
    });
  }

  String _message(int rc, bool completed) {
    if (stopReason == 'cancelled') return 'Sync stopped';
    if (!paired) {
      if (stopReason == 'nobody' || peerLeft) {
        return 'No other device synced with key $key. Press Sync on both devices '
            'within 20 seconds (and check the pairing server is reachable).';
      }
      return rc == 0 ? 'Sync ended before connecting' : 'Sync failed (backend error $rc)';
    }
    if (stopReason == 'stuck') return 'The other device stopped responding';
    if (rc != 0 && stopReason.isEmpty) {
      return lastLine.isEmpty ? 'Sync failed (backend error $rc)' : 'Sync failed: $lastLine';
    }
    final parts = <String>[
      'Synced: received ${received.length} song(s), sent $sent',
      if (incomplete > 0) '$incomplete arrived incomplete - send them again',
      if (errors > 0) '$errors error(s)',
    ];
    return parts.join(' - ');
  }
}
