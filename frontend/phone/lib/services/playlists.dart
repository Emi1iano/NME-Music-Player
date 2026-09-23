import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../models/playlist.dart';

/// Playlists are saved as JSON in the app's private support folder.
class Playlists extends ChangeNotifier {
  Playlists._();
  static final Playlists instance = Playlists._();

  late File _file;
  List<Playlist> _items = [];

  List<Playlist> get items => _items;

  Playlist? byId(String id) => _items.where((pl) => pl.id == id).firstOrNull;

  Future<void> init() async {
    final dir = await getApplicationSupportDirectory();
    _file = File(p.join(dir.path, 'playlists.json'));
    if (await _file.exists()) {
      try {
        final data = jsonDecode(await _file.readAsString()) as List;
        _items = data.map((e) => Playlist.fromMap(e as Map<String, dynamic>)).toList();
      } catch (_) {
        _items = [];
      }
    }
  }

  Future<Playlist> create(String name) async {
    final playlist = Playlist(
      id: 'pl_${DateTime.now().microsecondsSinceEpoch}',
      name: name,
      trackIds: [],
    );
    _items.add(playlist);
    await _save();
    return playlist;
  }

  Future<void> rename(Playlist playlist, String name) =>
      _replace(playlist, playlist.copyWith(name: name));

  Future<void> delete(Playlist playlist) async {
    _items.removeWhere((pl) => pl.id == playlist.id);
    await _save();
  }

  /// Returns false if the track was already in the playlist.
  Future<bool> addTrack(Playlist playlist, String trackId) async {
    final current = byId(playlist.id) ?? playlist;
    if (current.trackIds.contains(trackId)) return false;
    await _replace(current, current.copyWith(trackIds: [...current.trackIds, trackId]));
    return true;
  }

  Future<void> removeTrack(Playlist playlist, String trackId) {
    final current = byId(playlist.id) ?? playlist;
    return _replace(current,
        current.copyWith(trackIds: current.trackIds.where((id) => id != trackId).toList()));
  }

  Future<void> moveTrack(Playlist playlist, int from, int to) {
    final current = byId(playlist.id) ?? playlist;
    final ids = List.of(current.trackIds);
    ids.insert(to, ids.removeAt(from));
    return _replace(current, current.copyWith(trackIds: ids));
  }

  Future<void> _replace(Playlist old, Playlist updated) async {
    final i = _items.indexWhere((pl) => pl.id == old.id);
    if (i >= 0) _items[i] = updated;
    await _save();
  }

  Future<void> _save() async {
    notifyListeners();
    await _file.writeAsString(jsonEncode(_items.map((e) => e.toMap()).toList()));
  }
}
