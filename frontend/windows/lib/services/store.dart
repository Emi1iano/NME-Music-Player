import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/models.dart';
import 'sync_api.dart';

class Store extends ChangeNotifier {
  final counts = <String, int>{};
  final playlists = <String, List<String>>{};
  int totalSecs = 0;
  String? key;
  String status = 'Not connected';
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
    totalSecs = _p!.getInt('secs') ?? 0;
    key = _p!.getString('key');
    notifyListeners();
  }

  void _save() {
    _p?.setString('counts', jsonEncode(counts));
    _p?.setString('playlists', jsonEncode(playlists));
    _p?.setInt('secs', totalSecs);
    if (key != null) _p?.setString('key', key!);
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

  Future<void> newKey() async {
    key = _newKey();
    _save();
    status = await MusicSync.syncNewKey();
    notifyListeners();
  }

  Future<void> connect(String typed) async {
    try {
      if (typed.isNotEmpty) {
        key = typed;
      } else {
        key ??= _newKey();
      }
      _save();
      status = await MusicSync.sync(key);
    } on ArgumentError catch (e) {
      status = e.message.toString();
    }
    notifyListeners();
  }

  Future<void> addFile(Song s) async {
    status = await MusicSync.add(s.path);
    notifyListeners();
  }
}
