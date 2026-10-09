import 'dart:async';
import 'dart:ffi';
import 'dart:io';
import 'dart:isolate';
import 'package:ffi/ffi.dart';

typedef _Native = Int32 Function(Pointer<Utf8>);
typedef _Dart = int Function(Pointer<Utf8>);

/// Desktop wrapper around backend.dll, the Zig backend in
/// backend/NetworksButBetter (the same one the phone app uses).
///
/// The backend works in the current directory: before a sync we write
/// musicDir.txt, skip.txt and server.txt there, and while it runs it writes
/// its progress to status.txt and its UDP port to port.txt (for cancel).
class MusicSync {
  static const supported = true;
  static final _keyRe = RegExp(r'^[0-9]{8}$');
  static const _audio = {'.mp3', '.flac', '.wav', '.m4a', '.aac', '.ogg', '.opus', '.wma'};

  static String defaultFolder() => '${Platform.environment['USERPROFILE'] ?? _dataDir}\\Music\\NME';

  /// Where the backend keeps its key, state and config files.
  static String get _dataDir =>
      '${Platform.environment['LOCALAPPDATA'] ?? Directory.systemTemp.path}\\NME';

  /// True for a relative path with '/' separators that stays inside the folder.
  static bool isSafeRelPath(String p) {
    if (p.isEmpty || p.length > 300 || p.startsWith('/')) return false;
    if (p.contains('\\') || p.contains(':') || p.codeUnits.any((c) => c < 32)) return false;
    return p.split('/').every((s) => s.isNotEmpty && s != '.' && s != '..');
  }

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

  static Future<void> deleteFile(String folder, String path) async {
    if (!isSafeRelPath(path)) throw ArgumentError('Path must be relative to the music folder.');
    final f = File('$folder/$path');
    if (await f.exists()) await f.delete();
  }

  /// The key the backend saved last time, if any.
  static Future<String?> readKey() async {
    for (final p in ['$_dataDir\\testing\\app\\key.txt', '$_dataDir\\app\\key.txt']) {
      final f = File(p);
      if (await f.exists()) {
        final k = (await f.readAsString()).trim();
        if (_keyRe.hasMatch(k)) return k;
      }
    }
    return null;
  }

  /// Pairs with the other device through [server] ("host:port") and
  /// exchanges songs. Songs in [skip] are not downloaded.
  static Future<String> sync({
    required String key,
    required String folder,
    required String server,
    Set<String> skip = const {},
    void Function(String)? onStatus,
  }) async {
    if (!_keyRe.hasMatch(key)) throw ArgumentError('Key must be 8 digits (0-9).');
    final serverIp = await _resolve(server);

    final dir = Directory(_dataDir)..createSync(recursive: true);
    Directory.current = dir.path;
    File('musicDir.txt').writeAsStringSync(folder);
    File('skip.txt').writeAsStringSync(skip.join('\n'));
    File('server.txt').writeAsStringSync(serverIp);
    for (final f in ['status.txt', 'port.txt']) {
      if (File(f).existsSync()) File(f).deleteSync();
    }

    var last = '';
    final poll = Timer.periodic(const Duration(milliseconds: 400), (_) {
      final s = _read('status.txt');
      if (s != null && s != last) onStatus?.call(last = s);
    });
    try {
      final rc = await Isolate.run(() => _call('sync $key'));
      final s = _read('status.txt') ?? '';
      if (rc == 0) return s;
      return s.isEmpty ? 'Sync failed (backend error $rc)' : s;
    } catch (e) {
      return 'Sync failed: $e';
    } finally {
      poll.cancel();
    }
  }

  /// Stops a running sync: the backend quits when its socket gets TERMINATE.
  static Future<void> cancel() async {
    final port = int.tryParse(_read('$_dataDir\\port.txt') ?? '');
    if (port == null) return;
    final s = await RawDatagramSocket.bind(InternetAddress.loopbackIPv4, 0);
    s.send([0x0A], InternetAddress.loopbackIPv4, port);
    s.close();
  }

  /// "host:port" -> "a.b.c.d:port" (the backend only parses IPv4 literals).
  static Future<String> _resolve(String server) async {
    final i = server.lastIndexOf(':');
    final port = i < 0 ? null : int.tryParse(server.substring(i + 1));
    if (port == null) throw ArgumentError('Server must look like host:port.');
    try {
      final addrs = await InternetAddress.lookup(server.substring(0, i), type: InternetAddressType.IPv4);
      return '${addrs.first.address}:$port';
    } on SocketException {
      throw ArgumentError('Can\'t find server ${server.substring(0, i)}.');
    }
  }

  static String? _read(String path) {
    try {
      return File(path).readAsStringSync().trim();
    } on FileSystemException {
      return null;
    }
  }

  static int _call(String command) {
    final f = DynamicLibrary.open('backend.dll').lookupFunction<_Native, _Dart>('clientAPI');
    final ptr = command.toNativeUtf8();
    try {
      return f(ptr);
    } finally {
      malloc.free(ptr);
    }
  }
}
