import 'dart:async';

// Web build: no local files to play, so this only pretends. It keeps the demo
// library usable: every "song" is 3 minutes long and plays in real time.
class AudioEngine {
  static const _length = Duration(minutes: 3);

  final _clock = Stopwatch();
  Duration _base = Duration.zero;
  bool _playing = false;

  Duration get position {
    final p = _base + _clock.elapsed;
    return p > _length ? _length : p;
  }

  Duration get duration => _length;
  bool get playing => _playing;
  Stream<bool> get completed => const Stream.empty();
  Stream<String> get errors => const Stream.empty();

  Future<void> open(String path) async {
    _base = Duration.zero;
    _clock
      ..reset()
      ..start();
    _playing = true;
  }

  Future<void> pause() async {
    _base = position;
    _clock
      ..stop()
      ..reset();
    _playing = false;
  }

  Future<void> resume() async {
    _clock.start();
    _playing = true;
  }

  Future<void> seek(Duration to) async {
    _base = to;
    _clock.reset();
  }

  Future<void> stop() async {
    _base = Duration.zero;
    _clock
      ..stop()
      ..reset();
    _playing = false;
  }

  Future<void> dispose() async {}
}
