import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../models/playlist.dart';

/// Playlists are saved as JSON in the app's private support folder.
///
/// Playlist objects are immutable (final fields), so every edit builds an
/// updated copy with copyWith() and swaps it into the list (see _replace).
class Playlists extends ChangeNotifier {
  // Singleton: one shared playlist store (Playlists.instance).
  Playlists._();
  static final Playlists instance = Playlists._();

  late File _file;            // playlists.json on the phone
  List<Playlist> _items = [];

  List<Playlist> get items => _items;

  /// Finds a playlist by id (null if it was deleted).
  Playlist? byId(String id) => _items.where((pl) => pl.id == id).firstOrNull;

  /// Loads saved playlists from disk at startup.
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
      // The current time in microseconds makes a unique id (same "pl_" style
      // as the mock data).
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

  /// Drag-to-reorder: take the track out at [from] and put it back at [to].
  Future<void> moveTrack(Playlist playlist, int from, int to) {
    final current = byId(playlist.id) ?? playlist;
    final ids = List.of(current.trackIds);
    ids.insert(to, ids.removeAt(from));
    return _replace(current, current.copyWith(trackIds: ids));
  }

  // Swap the old version of a playlist for its updated copy, then save.
  Future<void> _replace(Playlist old, Playlist updated) async {
    final i = _items.indexWhere((pl) => pl.id == old.id);
    if (i >= 0) _items[i] = updated;
    await _save();
  }

  // Redraw any screens showing playlists, then write them all to disk as
  // JSON using each playlist's toMap().
  Future<void> _save() async {
    notifyListeners();
    await _file.writeAsString(jsonEncode(_items.map((e) => e.toMap()).toList()));
  }
}
