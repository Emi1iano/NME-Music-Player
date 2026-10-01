import 'dart:ffi';
import 'dart:io';
import 'package:ffi/ffi.dart';

typedef _Native = Int32 Function(Pointer<Utf8>);
typedef _Dart = int Function(Pointer<Utf8>);

/// Desktop (Windows) wrapper. Replace 'execute' with the DLL's real export name.
class MusicSync {
  static _Dart? _fn;
  static final _keyRe = RegExp(r'^[0-9]{8}$');

  static _Dart? _load() {
    if (_fn != null || !Platform.isWindows) return _fn;
    try {
      _fn = DynamicLibrary.open('musicsync.dll')
          .lookupFunction<_Native, _Dart>('execute');
    } catch (_) {}
    return _fn;
  }

  static String _path(String p) {
    if (p.startsWith('/') || p.startsWith('\\') || p.contains(':') || p.contains('..')) {
      throw ArgumentError('Path must be relative to the music folder.');
    }
    return p;
  }

  static Future<String> _run(String cmd) async {
    final f = _load();
    if (f == null) return 'musicsync.dll not loaded';
    final ptr = cmd.toNativeUtf8();
    try {
      final rc = f(ptr);
      return rc == 0 ? 'ok' : 'error $rc';
    } finally {
      malloc.free(ptr);
    }
  }

  static Future<String> add(String path) => _run('add ${_path(path)}');
  static Future<String> rename(String path) => _run('rename ${_path(path)}');
  static Future<String> syncNewKey() => _run('sync_new_key');
  static Future<String> sync([String? key]) {
    if (key == null) return _run('sync');
    if (!_keyRe.hasMatch(key)) throw ArgumentError('Key must be 8 digits (0-9).');
    return _run('sync $key');
  }
}
