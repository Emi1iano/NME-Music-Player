import 'dart:async';
import 'dart:math';

import 'package:audio_session/audio_session.dart';
import 'package:flutter/foundation.dart' show ValueNotifier;
import 'package:just_audio/just_audio.dart';
import 'package:just_audio_background/just_audio_background.dart';

import '../models/track.dart';
import 'app_log.dart';
import 'library.dart';
import 'stats.dart';

/// The single audio player for the whole app. Also records play counts and
/// listening time into [Stats].
class Player {
  // Singleton: one player for the whole app (Player.instance).
  Player._();
  static final Player instance = Player._();

  // just_audio's player does the actual decoding and playback.
  // Screens listen to its "streams" (playingStream, positionStream, ...) to
  // update the play button, seek bar, etc. in real time.
  final AudioPlayer audio = AudioPlayer();

  /// The tracks currently loaded, in original (unshuffled) order.
  List<Track> _queue = [];

  // Listening-stats bookkeeping for the current "listen" of a track.
  Timer? _ticker;                 // fires once per second
  int _listenedThisPlay = 0;      // seconds heard since this listen started
  bool _countedThisPlay = false;  // so one listen only adds ONE to playCount

  // Sleep timer: pause at [sleepAt], or when the current song ends.
  // ValueNotifiers so Now Playing can show the time left.
  final sleepAt = ValueNotifier<DateTime?>(null);
  final sleepAfterSong = ValueNotifier<bool>(false);
  Timer? _sleepTimer;

  Future<void> init() async {
    // Tell the phone we're a music app (pauses for calls, ducks for
    // navigation voice, etc.).
    final session = await AudioSession.instance;
    await session.configure(const AudioSessionConfiguration.music());

    // A new track (or the same one looping) starts a new listen.
    audio.currentIndexStream.listen((_) => _startNewListen());
    // "End of song" sleep timer: pause when the next song starts.
    audio.positionDiscontinuityStream.listen((d) {
      if (sleepAfterSong.value && d.reason == PositionDiscontinuityReason.autoAdvance) {
        audio.pause();
        cancelSleepTimer();
      }
    });
    // "Discontinuity" = the position jumped: the song auto-advanced
    // (including repeat-one looping) or the user seeked back to the start.
    audio.positionDiscontinuityStream.listen((d) {
      final restarted = d.reason == PositionDiscontinuityReason.seek &&
          d.event.updatePosition < const Duration(seconds: 2) &&
          d.previousEvent.currentIndex == d.event.currentIndex;
      if (d.reason == PositionDiscontinuityReason.autoAdvance || restarted) {
        _startNewListen();
      }
    });
    // Check every second whether music is playing, and record it.
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) => _tick());

    // Playback errors (corrupt file, unsupported format...) go to the debug log.
    audio.playbackEventStream.listen(
      (_) {},
      onError: (Object e, StackTrace st) {
        AppLog.instance.error('Playback error on "${currentTrack?.id ?? 'unknown'}"', e, st);
      },
    );
  }

  void dispose() => _ticker?.cancel();

  List<Track> get queue => _queue;

  /// Emits the new current track whenever the song changes, so screens like
  /// Now Playing and the mini player can update.
  Stream<Track?> get currentTrackStream =>
      audio.sequenceStateStream.map((_) => currentTrack);

  /// The track that's playing right now (or null if nothing is loaded).
  Track? get currentTrack {
    final index = audio.currentIndex;
    if (index == null || index >= _queue.length) return null;
    return _queue[index];
  }

  /// Loads [tracks] and starts playing at [index].
  /// With [shuffle] and no [index], a random track plays first.
  Future<void> playTracks(List<Track> tracks, {int? index, bool? shuffle}) async {
    if (tracks.isEmpty) return;
    final useShuffle = shuffle ?? audio.shuffleModeEnabled;
    final start = index ?? (useShuffle ? Random().nextInt(tracks.length) : 0);

    _queue = List.of(tracks);
    AppLog.instance.info('Play "${tracks[start].id}" '
        '(${tracks.length} in queue${useShuffle ? ', shuffled' : ''})');
    try {
      await _load(start);
    } catch (e, st) {
      // e.g. the file was deleted since the last scan
      AppLog.instance.error('Could not load "${tracks[start].id}"', e, st);
      return;
    }
    if (useShuffle) await audio.shuffle();
    await audio.setShuffleModeEnabled(useShuffle);
    _startNewListen();
    audio.play();
  }

  /// Hands the whole queue to just_audio, starting at [start].
  Future<void> _load(int start) async {
    await audio.setAudioSources(
      [for (final track in _queue) _sourceFor(track)],
      initialIndex: start,
    );
  }

  /// One song for just_audio. The MediaItem "tag" is the title/artist/art
  /// shown on the lock screen and in the notification.
  AudioSource _sourceFor(Track track) {
    final library = Library.instance;
    return AudioSource.file(
      track.audioUrl,
      tag: MediaItem(
        id: track.id,
        title: track.title,
        artist: library.artistName(track.artistId),
        album: library.albumTitle(track.albumId),
        duration: track.durationSeconds > 0 ? Duration(seconds: track.durationSeconds) : null,
        artUri: track.artworkPath == null ? null : Uri.file(track.artworkPath!),
      ),
    );
  }

  /// "Play next": puts [track] right after the current song. Plays it now
  /// if nothing is loaded. (With shuffle on, just_audio picks where it lands
  /// in the shuffled order.)
  Future<void> playNext(Track track) async {
    final current = audio.currentIndex;
    if (_queue.isEmpty || current == null) {
      await playTracks([track], index: 0, shuffle: false);
      return;
    }
    _queue.insert(current + 1, track);
    await audio.insertAudioSource(current + 1, _sourceFor(track));
  }

  /// "Add to queue": puts [track] at the end of the queue. Plays it now if
  /// nothing is loaded.
  Future<void> addToQueue(Track track) async {
    if (_queue.isEmpty || audio.currentIndex == null) {
      await playTracks([track], index: 0, shuffle: false);
      return;
    }
    _queue.add(track);
    await audio.addAudioSource(_sourceFor(track));
  }

  /// Jumps to a track already in the queue (by its original index).
  Future<void> jumpTo(int index) async {
    await audio.seek(Duration.zero, index: index);
    audio.play();
  }

  /// Takes a deleted song out of the queue (it skips ahead if it was
  /// playing). Stops the player if nothing is left.
  Future<void> removeTrack(String trackId) async {
    for (var i = _queue.length - 1; i >= 0; i--) {
      if (_queue[i].id != trackId) continue;
      _queue.removeAt(i);
      await audio.removeAudioSourceAt(i);
    }
    if (_queue.isEmpty) await audio.stop();
  }

  /// Drag-to-reorder in "Up next": moves the song at [from] to [to]
  /// (positions in the unshuffled queue).
  Future<void> moveInQueue(int from, int to) async {
    if (from == to || from < 0 || from >= _queue.length) return;
    _queue.insert(to, _queue.removeAt(from));
    await audio.moveAudioSource(from, to);
  }

  /// Swipe away a song in "Up next" (skips ahead if it's the one playing).
  Future<void> removeFromQueue(int index) async {
    if (index < 0 || index >= _queue.length) return;
    _queue.removeAt(index);
    await audio.removeAudioSourceAt(index);
    if (_queue.isEmpty) await audio.stop();
  }

  /// Sleep timer: pause after [duration], or (null) at the end of the
  /// current song.
  void setSleepTimer(Duration? duration) {
    cancelSleepTimer();
    if (duration == null) {
      sleepAfterSong.value = true;
      return;
    }
    sleepAt.value = DateTime.now().add(duration);
    _sleepTimer = Timer(duration, () {
      audio.pause();
      cancelSleepTimer();
    });
  }

  void cancelSleepTimer() {
    _sleepTimer?.cancel();
    _sleepTimer = null;
    sleepAt.value = null;
    sleepAfterSong.value = false;
  }

  /// The big play/pause button.
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

  /// Turns shuffle on/off. Turning it on makes a fresh random order
  /// (the current song stays first).
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

  /// Resets the per-listen counters when a song starts (again).
  void _startNewListen() {
    _listenedThisPlay = 0;
    _countedThisPlay = false;
    // Playing a song that came from a sync clears its "NEW" tag.
    final track = currentTrack;
    if (track != null) Library.instance.clearNew(track.id);
  }

  /// Called every second: adds listening time while audio is actually playing,
  /// and counts one play once you've heard 30 seconds (or half of a short song).
  void _tick() {
    final track = currentTrack;
    // Only count time when sound is actually coming out
    // (not paused, not still loading/buffering).
    if (track == null ||
        !audio.playing ||
        audio.processingState != ProcessingState.ready) {
      return;
    }
    // 1) Playtime: every second of listening adds 1 second.
    final stats = Stats.instance;
    stats.addPlaytime(track.id, 1);
    _listenedThisPlay++;

    // 2) Play count: a "play" counts after 30 seconds, or half the song if
    //    it's shorter than a minute (similar to how Spotify counts streams).
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
