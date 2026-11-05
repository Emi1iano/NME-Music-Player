import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/models.dart';
import 'audio_api.dart';
import 'sync_api.dart';

class Store extends ChangeNotifier {
  final library = <Song>[];
  final counts = <String, int>{};
  final playlists = <String, List<String>>{};

  // The backend keeps a table of songs and the changes the next sync sends.
  // These sets tell which songs it already knows (or got from the other
  // device) and which of them still wait for a sync.
  final _known = <String>{};
  final _pending = <String>{};
  int totalSecs = 0;
  String? key;
  String status = 'Not connected';
  String folder = ''; // the backend's music folder (fixed)
  bool syncing = false;
  bool importing = false;
  Song? playing;
  bool paused = false;
  bool ended = false; // the current song played to its end
  List<Song> queue = const []; // what plays next: the library or a playlist
  Timer? _t;
  SharedPreferences? _p;
  final _audio = AudioEngine();
  StreamSubscription<bool>? _doneSub;
  StreamSubscription<String>? _errSub;
  double _heardSecs = 0; // time actually listened to the current song
  bool _counted = false; // this listen already counted as a play

  Store() {
    _doneSub = _audio.completed.listen((done) {
      if (done) _onFinished();
    });
    _errSub = _audio.errors.listen((e) {
      if (playing == null) return;
      status = 'Can\'t play ${playing!.title}: $e';
      notifyListeners();
    });
  }

  @override
  void dispose() {
    _t?.cancel();
    _doneSub?.cancel();
    _errSub?.cancel();
    _audio.dispose();
    super.dispose();
  }

  Future<void> load() async {
    _p = await SharedPreferences.getInstance();
    final c = _p!.getString('counts');
    if (c != null) (jsonDecode(c) as Map).forEach((k, v) => counts[k] = v as int);
    final pl = _p!.getString('playlists');
    if (pl != null) {
      (jsonDecode(pl) as Map).forEach((k, v) => playlists[k] = List<String>.from(v));
    }
    _known.addAll(_p!.getStringList('known') ?? const []);
    _pending.addAll(_p!.getStringList('pending') ?? const []);
    totalSecs = _p!.getInt('secs') ?? 0;
    final problem = await MusicSync.init();
    if (problem != null) status = problem;
    folder = MusicSync.defaultFolder();
    key = await MusicSync.readKey() ?? await MusicSync.newKey();
    await rescan();
  }

  /// Rebuilds the library from the music folder (demo songs on web), and
  /// tells the backend about songs it hasn't seen yet so the next sync sends them.
  Future<void> rescan() async {
    List<String> paths;
    if (MusicSync.supported) {
      try {
        paths = await MusicSync.scan(folder);
      } catch (e) {
        status = 'Can\'t read music folder: $e';
        paths = [];
      }
    } else {
      paths = [for (final s in demoLibrary) s.path];
    }
    library
      ..clear()
      ..addAll(paths.map(Song.fromPath));
    notifyListeners();
    if (MusicSync.supported && !syncing) await _register(paths);
    _save();
    notifyListeners();
  }

  /// `add`s every song the backend doesn't know yet (not while syncing: the
  /// backend can only do one thing at a time).
  Future<void> _register(List<String> paths) async {
    for (final p in paths) {
      if (_known.contains(p)) continue;
      if (await MusicSync.add(p)) {
        _known.add(p);
        _pending.add(p);
      }
    }
  }

  void _save() {
    _p?.setString('counts', jsonEncode(counts));
    _p?.setString('playlists', jsonEncode(playlists));
    _p?.setStringList('known', _known.toList());
    _p?.setStringList('pending', _pending.toList());
    _p?.setInt('secs', totalSecs);
  }

  // ---- stats
  int get plays => counts.values.fold(0, (a, b) => a + b);
  String get listened => '${totalSecs ~/ 3600}h ${(totalSecs % 3600) ~/ 60}m';
  List<MapEntry<String, int>> get top10 =>
      (counts.entries.toList()..sort((a, b) => b.value.compareTo(a.value))).take(10).toList();
  Song songByPath(String path) =>
      library.firstWhere((s) => s.path == path, orElse: () => Song(path, path));

  // ---- playback
  Duration get position => _audio.position;
  Duration get duration => _audio.duration;

  /// Plays [s]; [queue] is what follows it (defaults to the whole library).
  /// A play only counts once at least half the song has really been heard.
  void play(Song s, {List<Song>? queue}) {
    this.queue = queue ?? List.of(library);
    playing = s;
    paused = false;
    ended = false;
    _heardSecs = 0;
    _counted = false;
    _t?.cancel();
    _t = Timer.periodic(const Duration(seconds: 1), (_) => _tick());
    _audio.open('$folder/${s.path}').catchError((Object e) {
      status = 'Can\'t play ${s.title}: $e';
      notifyListeners();
    });
    notifyListeners();
  }

  /// Once a second: counts time that was actually played (not paused, not
  /// skipped over with the slider) and counts the play at the halfway point.
  void _tick() {
    if (paused || ended || !_audio.playing) return;
    totalSecs++;
    _heardSecs++;
    final total = _audio.duration.inMilliseconds / 1000;
    final song = playing;
    if (!_counted && song != null && total > 0 && _heardSecs >= total / 2) {
      _counted = true;
      counts[song.path] = (counts[song.path] ?? 0) + 1;
      _save();
    } else if (totalSecs % 10 == 0) {
      _save();
    }
    notifyListeners();
  }

  void _onFinished() {
    final song = playing;
    if (song == null) return;
    final i = queue.indexOf(song);
    if (i >= 0 && i + 1 < queue.length) {
      play(queue[i + 1], queue: queue);
    } else {
      ended = true;
      paused = true;
      notifyListeners();
    }
  }

  void togglePause() {
    final song = playing;
    if (song == null) return;
    if (ended) {
      play(song, queue: queue); // the song finished: play it again
      return;
    }
    paused = !paused;
    paused ? _audio.pause() : _audio.resume();
    _save();
    notifyListeners();
  }

  void next() {
    final i = queue.indexOf(playing ?? const Song('', ''));
    if (i >= 0 && i + 1 < queue.length) play(queue[i + 1], queue: queue);
  }

  /// Restarts the song if it's been playing for a few seconds, else goes back one.
  void previous() {
    final song = playing;
    if (song == null) return;
    final i = queue.indexOf(song);
    if (_audio.position > const Duration(seconds: 3) || i <= 0) {
      play(song, queue: queue);
    } else {
      play(queue[i - 1], queue: queue);
    }
  }

  void seek(Duration to) {
    _audio.seek(to);
    notifyListeners();
  }

  // ---- import
  /// Copies the song files at [paths] into the music folder and refreshes the
  /// library. Returns a one-line summary for the user.
  Future<String> importSongs(List<String> paths) async {
    if (importing) return 'Already importing';
    if (syncing) return 'Wait for the sync to finish, then import';
    importing = true;
    status = 'Importing ${paths.length} file(s)...';
    notifyListeners();
    String msg;
    try {
      final r = await MusicSync.importFiles(folder, paths);
      msg = [
        r.added == 1 ? 'Imported 1 song' : 'Imported ${r.added} songs',
        if (r.existing > 0) '${r.existing} already in your library',
        if (r.unsupported > 0) '${r.unsupported} not a supported audio file',
        if (r.failed > 0) '${r.failed} could not be copied',
      ].join(' - ');
    } catch (e) {
      msg = 'Could not import: $e';
    }
    importing = false;
    status = msg;
    await rescan();
    return msg;
  }

  // ---- delete
  /// Deletes the song's file from the music folder and removes it from the
  /// library, playlists and stats.
  Future<void> deleteSong(Song s) async {
    if (syncing) {
      status = 'Wait for the sync to finish before deleting songs';
      notifyListeners();
      return;
    }
    library.remove(s);
    counts.remove(s.path);
    for (final l in playlists.values) {
      l.remove(s.path);
    }
    if (playing == s) {
      _t?.cancel();
      playing = null;
      paused = false;
      ended = false;
      // Windows can't delete a file the player still has open.
      await _audio.stop();
    }
    _save();
    notifyListeners();
    try {
      await MusicSync.deleteFile(folder, s.path);
      status = 'Deleted ${s.title}';
    } catch (e) {
      status = 'Couldn\'t delete ${s.title}: $e';
    }
    _known.remove(s.path);
    // A song still waiting to be sent sits in the backend's table by number;
    // taking one out would leave the changes pointing at the wrong songs, so
    // rebuild the table from the songs that are still pending.
    if (_pending.remove(s.path)) await _rebuildIndex();
    _save();
    notifyListeners();
  }

  /// Forgets the backend's table and changes, then adds the pending songs again.
  Future<void> _rebuildIndex() async {
    await MusicSync.resetIndex();
    final still = <String>{};
    for (final p in _pending) {
      if (await MusicSync.add(p)) still.add(p);
    }
    _pending
      ..clear()
      ..addAll(still);
  }

  // ---- playlists
  void createPlaylist(String name) {
    playlists.putIfAbsent(name, () => []);
    _save();
    notifyListeners();
  }

  void deletePlaylist(String name) {
    playlists.remove(name);
    _save();
    notifyListeners();
  }

  void addToPlaylist(String name, String path) {
    final l = playlists[name];
    if (l != null && !l.contains(path)) l.add(path);
    _save();
    notifyListeners();
  }

  void removeFromPlaylist(String name, String path) {
    playlists[name]?.remove(path);
    _save();
    notifyListeners();
  }

  void playPlaylist(String name) {
    final l = playlists[name];
    if (l != null && l.isNotEmpty) play(songByPath(l.first), queue: [for (final p in l) songByPath(p)]);
  }

  // ---- sync
  /// Makes a new key for this device (the backend saves it).
  Future<void> newKey() async {
    if (syncing) return;
    key = await MusicSync.newKey() ?? key;
    status = 'New key - enter it on your other device, then press Sync on both';
    notifyListeners();
  }

  /// Pairs with the other device using [typed] (or the saved key), sends the
  /// songs added since the last sync and downloads the ones it has.
  Future<void> connect(String typed) async {
    if (syncing) return;
    if (typed.isNotEmpty) key = typed;
    if (key == null) {
      await newKey();
      if (key == null) return;
    }
    syncing = true;
    status = 'Starting...';
    notifyListeners();
    // The backend's changes must match what we think is pending, or a sync
    // could send the wrong songs (or stop on a song that's gone).
    if (MusicSync.pendingAdds() != _pending.length) await _rebuildIndex();
    var outcome = const SyncOutcome(message: '');
    try {
      outcome = await MusicSync.sync(
        key: key!,
        onStatus: (m) {
          status = m;
          notifyListeners();
        },
      );
    } on ArgumentError catch (e) {
      outcome = SyncOutcome(message: e.message.toString());
    }
    // Songs that arrived are the other device's: don't send them back.
    _known.addAll(outcome.received);
    if (outcome.completed && _pending.isNotEmpty) {
      _pending.clear();
      await MusicSync.resetIndex(); // everything pending has been delivered
    }
    status = outcome.message;
    syncing = false;
    await rescan();
  }

  Future<void> cancelSync() => MusicSync.cancel();

  /// Sends every song in the library on the next sync (e.g. to a new device).
  Future<void> sendAllAgain() async {
    if (syncing) return;
    _pending
      ..clear()
      ..addAll(library.map((s) => s.path));
    await _rebuildIndex();
    _save();
    status = '${_pending.length} song(s) will be sent on the next sync';
    notifyListeners();
  }

  /// How many songs wait for the next sync.
  int get pendingSongs => _pending.length;

  Future<void> openMusicFolder() => MusicSync.openFolder(folder);
}
