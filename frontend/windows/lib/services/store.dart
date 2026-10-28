import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/models.dart';
import 'audio_api.dart';
import 'sync_api.dart';

class Store extends ChangeNotifier {
  static const defaultServer = '24.243.26.72:5252';

  final library = <Song>[];
  final deleted = <String>{}; // songs the user deleted; sync skips them until resync
  final counts = <String, int>{};
  final playlists = <String, List<String>>{};
  int totalSecs = 0;
  String? key;
  String status = 'Not connected';
  String folder = '';
  String server = defaultServer;
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
    deleted.addAll(_p!.getStringList('deleted') ?? const []);
    totalSecs = _p!.getInt('secs') ?? 0;
    key = _p!.getString('key') ?? await MusicSync.readKey();
    folder = _p!.getString('folder') ?? MusicSync.defaultFolder();
    server = _p!.getString('server') ?? defaultServer;
    await rescan();
  }

  /// Rebuilds the library from the music folder (demo songs on web).
  Future<void> rescan() async {
    List<String> paths;
    if (MusicSync.supported) {
      try {
        paths = await MusicSync.scan(folder);
      } catch (e) {
        status = 'Can\'t read music folder: $e';
        paths = [];
      }
      // A file that's on disk again (restored by resync) is no longer deleted.
      deleted.removeAll(paths);
    } else {
      paths = [for (final s in demoLibrary) if (!deleted.contains(s.path)) s.path];
    }
    library
      ..clear()
      ..addAll(paths.map(Song.fromPath));
    _save();
    notifyListeners();
  }

  void _save() {
    _p?.setString('counts', jsonEncode(counts));
    _p?.setString('playlists', jsonEncode(playlists));
    _p?.setStringList('deleted', deleted.toList());
    _p?.setInt('secs', totalSecs);
    if (key != null) _p?.setString('key', key!);
    _p?.setString('folder', folder);
    _p?.setString('server', server);
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
  /// library, playlists and stats. Sync won't download it again until resync.
  Future<void> deleteSong(Song s) async {
    library.remove(s);
    deleted.add(s.path);
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
    notifyListeners();
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
  String _newKey() {
    final r = Random.secure();
    return List.generate(8, (_) => r.nextInt(10)).join();
  }

  void newKey() {
    key = _newKey();
    _save();
    status = 'New key - enter it on your other device, then press Sync on both';
    notifyListeners();
  }

  void setFolder(String f) {
    folder = f.trim();
    rescan();
  }

  void setServer(String s) {
    server = s.trim();
    _save();
    notifyListeners();
  }

  /// Pairs with the other device using [typed] (or the saved key) and
  /// downloads every song it has that this device doesn't.
  /// Deleted songs are skipped; use [resync] to get them back.
  Future<void> connect(String typed) async {
    if (syncing) return;
    if (typed.isNotEmpty) key = typed;
    key ??= _newKey();
    _save();
    syncing = true;
    notifyListeners();
    try {
      status = await MusicSync.sync(
        key: key!,
        folder: folder,
        server: server,
        skip: deleted,
        onStatus: (m) {
          status = m;
          notifyListeners();
        },
      );
    } on ArgumentError catch (e) {
      status = e.message.toString();
    }
    syncing = false;
    await rescan();
  }

  Future<void> cancelSync() => MusicSync.cancel();

  /// Syncs again, this time also downloading the deleted songs in [restore].
  Future<void> resync(Set<String> restore) async {
    deleted.removeAll(restore);
    _save();
    notifyListeners();
    await connect('');
  }
}
