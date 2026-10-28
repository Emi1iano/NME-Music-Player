import 'dart:async';
import 'package:media_kit/media_kit.dart';

/// Plays one song at a time (media_kit / libmpv, so mp3, flac, opus, ogg,
/// m4a, wav, aac and wma all work). The Store drives it.
class AudioEngine {
  AudioEngine() {
    MediaKit.ensureInitialized();
    _p = Player();
  }

  late final Player _p;

  Duration get position => _p.state.position;
  Duration get duration => _p.state.duration;
  bool get playing => _p.state.playing;

  /// Emits true when the song reaches its end.
  Stream<bool> get completed => _p.stream.completed;

  /// Emits a message when a song can't be played (missing or unreadable file).
  Stream<String> get errors => _p.stream.error;

  /// [path] is a full path to the song file.
  Future<void> open(String path) => _p.open(Media(path.replaceAll('/', '\\')));
  Future<void> pause() => _p.pause();
  Future<void> resume() => _p.play();
  Future<void> seek(Duration to) => _p.seek(to);

  /// Stops playing and lets go of the file, so it can be deleted.
  Future<void> stop() => _p.stop();

  Future<void> dispose() => _p.dispose();
}
