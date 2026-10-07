// Web build: browsers can't load a native .dll.
// Point these at your own backend (HTTP/WebSocket) that wraps the DLL.
class MusicSync {
  static const _msg = 'Web: native DLL unavailable - connect via backend';
  static Future<String> add(String path) async => _msg;
  static Future<String> rename(String path) async => _msg;
  static Future<String> sync([String? key]) async => _msg;
  static Future<String> syncNewKey() async => _msg;
}
