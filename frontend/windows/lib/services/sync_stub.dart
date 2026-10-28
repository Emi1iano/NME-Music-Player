// Web build: browsers can't open raw UDP sockets or the local disk, so sync
// isn't available here. Point these at an HTTP/WebSocket backend later.
class MusicSync {
  static const _msg = 'Web: sync is only available in the Windows app';
  static const supported = false;
  static const audioExtensions = <String>[];
  static String defaultFolder() => '';
  static Future<List<String>> audioFilesIn(String dir) async => [];
  static Future<({int added, int existing, int unsupported, int failed})> importFiles(
          String folder, List<String> sources) async =>
      (added: 0, existing: 0, unsupported: 0, failed: 0);
  static Future<List<String>> scan(String folder) async => [];
  static Future<void> deleteFile(String folder, String path) async {}
  static Future<String?> readKey() async => null;
  static Future<void> cancel() async {}
  static Future<String> sync({
    required String key,
    required String folder,
    required String server,
    Set<String> skip = const {},
    void Function(String)? onStatus,
  }) async =>
      _msg;
}
