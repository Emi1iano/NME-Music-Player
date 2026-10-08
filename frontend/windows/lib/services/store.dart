import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/models.dart';
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
  Song? playing;
  bool paused = false;
  Timer? _t;
  SharedPreferences? _p;

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
  void play(Song s) {
    playing = s;
    paused = false;
    counts[s.path] = (counts[s.path] ?? 0) + 1;
    _t?.cancel();
    _t = Timer.periodic(const Duration(seconds: 1), (_) {
      if (paused) return;
      totalSecs++;
      if (totalSecs % 10 == 0) _save();
      notifyListeners();
    });
    _save();
    notifyListeners();
  }

  void togglePause() {
    paused = !paused;
    _save();
    notifyListeners();
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
    if (l != null && l.isNotEmpty) play(songByPath(l.first));
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

  /// Syncs again, this time also downloading the deleted songs in [restore].
  Future<void> resync(Set<String> restore) async {
    deleted.removeAll(restore);
    _save();
    notifyListeners();
    await connect('');
  }
}
