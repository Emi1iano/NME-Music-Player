// Picks the real player on desktop and a stand-in on web.
export 'audio_stub.dart' if (dart.library.io) 'audio_io.dart';
