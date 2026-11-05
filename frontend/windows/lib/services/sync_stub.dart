import 'sync_outcome.dart';

// Web build: browsers can't open raw UDP sockets or the local disk, so sync
// isn't available here. Point these at an HTTP/WebSocket backend later.
class MusicSync {
  static const _msg = 'Web: sync is only available in the Windows app';
  static const supported = false;
  static const audioExtensions = <String>[];
  static String? unavailableReason = _msg;
  static String defaultFolder() => '';
  static Future<String?> init() async => _msg;
  static Future<List<String>> scan(String folder) async => [];
  static Future<List<String>> audioFilesIn(String dir) async => [];
  static Future<({int added, int existing, int unsupported, int failed})> importFiles(
          String folder, List<String> sources) async =>
      (added: 0, existing: 0, unsupported: 0, failed: 0);
  static Future<void> deleteFile(String folder, String path) async {}
  static Future<void> openFolder(String folder) async {}
  static Future<bool> add(String rel) async => false;
  static Future<bool> resetIndex() async => false;
  static Future<String?> readKey() async => null;
  static Future<String?> newKey() async => null;
  static int pendingAdds() => 0;
  static Future<void> cancel() async {}
  static Future<SyncOutcome> sync({required String key, void Function(String)? onStatus}) async =>
      const SyncOutcome(message: _msg);
}
