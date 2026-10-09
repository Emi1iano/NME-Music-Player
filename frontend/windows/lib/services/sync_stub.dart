// Web build: browsers can't open raw UDP sockets or the local disk, so sync
// isn't available here. Point these at an HTTP/WebSocket backend later.
class MusicSync {
  static const _msg = 'Web: sync is only available in the Windows app';
  static const supported = false;
  static String defaultFolder() => '';
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
