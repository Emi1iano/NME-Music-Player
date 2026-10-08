import 'dart:async';
import 'dart:io';
import 'sync_engine.dart';

/// Desktop wrapper around the UDP sync engine.
class MusicSync {
  static final _keyRe = RegExp(r'^[0-9]{8}$');
  static const supported = true;

  static String defaultFolder() =>
      '${Platform.environment['USERPROFILE'] ?? Directory.current.path}\\Music\\NME';

  static Future<List<String>> scan(String folder) async {
    await Directory(folder).create(recursive: true);
    return scanFolder(folder);
  }

  static Future<void> deleteFile(String folder, String path) async {
    if (!isSafeRelPath(path)) throw ArgumentError('Path must be relative to the music folder.');
    final f = File('$folder/$path');
    if (await f.exists()) await f.delete();
  }

  /// Reads a saved key from key.txt, if one exists and is valid.
  static Future<String?> readKey() async {
    for (final p in ['testing/app/key.txt', 'app/key.txt']) {
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
    final i = server.lastIndexOf(':');
    final port = i < 0 ? null : int.tryParse(server.substring(i + 1));
    if (port == null) throw ArgumentError('Server must look like host:port.');
    try {
      final addrs = await InternetAddress.lookup(server.substring(0, i), type: InternetAddressType.IPv4);
      await Directory(folder).create(recursive: true);
      return await SyncSession(
        folder: folder,
        key: key,
        server: addrs.first,
        serverPort: port,
        skip: skip,
        onStatus: onStatus,
      ).run();
    } on TimeoutException catch (e) {
      return 'Sync failed: ${e.message}';
    } on Exception catch (e) {
      return 'Sync failed: $e';
    }
  }
}
