import 'dart:async';
import 'dart:math';

import 'package:audio_session/audio_session.dart';
import 'package:just_audio/just_audio.dart';
import 'package:just_audio_background/just_audio_background.dart';

import '../models/track.dart';
import 'library.dart';
import 'stats.dart';

/// The single audio player for the whole app. Also records play counts and
/// listening time into [Stats].
class Player {
  Player._();
  static final Player instance = Player._();

  final AudioPlayer audio = AudioPlayer();

  /// The tracks currently loaded, in original (unshuffled) order.
  List<Track> _queue = [];

  // Listening-stats bookkeeping for the current "listen" of a track.
  Timer? _ticker;
  int _listenedThisPlay = 0;
  bool _countedThisPlay = false;

  Future<void> init() async {
    final session = await AudioSession.instance;
    await session.configure(const AudioSessionConfiguration.music());

    // A new track (or the same one looping) starts a new listen.
    audio.currentIndexStream.listen((_) => _startNewListen());
    audio.positionDiscontinuityStream.listen((d) {
      final restarted = d.reason == PositionDiscontinuityReason.seek &&
          d.event.updatePosition < const Duration(seconds: 2) &&
          d.previousEvent.currentIndex == d.event.currentIndex;
      if (d.reason == PositionDiscontinuityReason.autoAdvance || restarted) {
        _startNewListen();
      }
    });
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) => _tick());
  }

  void dispose() => _ticker?.cancel();

  List<Track> get queue => _queue;

  Stream<Track?> get currentTrackStream =>
      audio.sequenceStateStream.map((_) => currentTrack);

  Track? get currentTrack {
    final index = audio.currentIndex;
    if (index == null || index >= _queue.length) return null;
    return _queue[index];
  }

  /// Loads [tracks] and starts playing at [index].
  /// With [shuffle] and no [index], a random track plays first.
  Future<void> playTracks(List<Track> tracks, {int? index, bool? shuffle}) async {
    if (tracks.isEmpty) return;
    final library = Library.instance;
    final useShuffle = shuffle ?? audio.shuffleModeEnabled;
    final start = index ?? (useShuffle ? Random().nextInt(tracks.length) : 0);

    _queue = List.of(tracks);
    await audio.setAudioSources(
      [
        for (final track in _queue)
          AudioSource.file(
            track.audioUrl,
            tag: MediaItem(
              id: track.id,
              title: track.title,
              artist: library.artistName(track.artistId),
              album: library.albumTitle(track.albumId),
              duration: track.durationSeconds > 0
                  ? Duration(seconds: track.durationSeconds)
                  : null,
              artUri: track.artworkPath == null ? null : Uri.file(track.artworkPath!),
            ),
          ),
      ],
      initialIndex: start,
    );
    if (useShuffle) await audio.shuffle();
    await audio.setShuffleModeEnabled(useShuffle);
    _startNewListen();
    audio.play();
  }

  /// Jumps to a track already in the queue (by its original index).
  Future<void> jumpTo(int index) async {
    await audio.seek(Duration.zero, index: index);
    audio.play();
  }

  Future<void> togglePlay() async => audio.playing ? audio.pause() : audio.play();

  /// Like most players: restart the song if we're past 3 seconds.
  Future<void> previous() async {
    if (audio.position > const Duration(seconds: 3) || !audio.hasPrevious) {
      await audio.seek(Duration.zero);
    } else {
      await audio.seekToPrevious();
    }
  }

  Future<void> next() => audio.seekToNext();

  Future<void> toggleShuffle() async {
    final enable = !audio.shuffleModeEnabled;
    if (enable) await audio.shuffle();
    await audio.setShuffleModeEnabled(enable);
  }

  /// off → all → one → off
  Future<void> cycleRepeat() => audio.setLoopMode(switch (audio.loopMode) {
        LoopMode.off => LoopMode.all,
        LoopMode.all => LoopMode.one,
        LoopMode.one => LoopMode.off,
      });

  void _startNewListen() {
    _listenedThisPlay = 0;
    _countedThisPlay = false;
  }

  /// Called every second: adds listening time while audio is actually playing,
  /// and counts one play once you've heard 30 seconds (or half of a short song).
  void _tick() {
    final track = currentTrack;
    if (track == null ||
        !audio.playing ||
        audio.processingState != ProcessingState.ready) {
      return;
    }
    final stats = Stats.instance;
    stats.addPlaytime(track.id, 1);
    _listenedThisPlay++;

    final length = track.durationSeconds > 0
        ? track.durationSeconds
        : (audio.duration?.inSeconds ?? 0);
    final needed = length > 0 ? min(30, (length / 2).ceil()) : 30;
    if (!_countedThisPlay && _listenedThisPlay >= needed) {
      _countedThisPlay = true;
      stats.recordPlay(track.id);
      Library.instance.refreshSort();
    }
  }
}
