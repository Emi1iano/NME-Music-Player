import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../models/playback_stats.dart';

/// Play counts and listening time per track, saved as JSON.
///
/// Keyed by Track.id (the path inside the Music folder), which is what the
/// backend's `update [path] playcount` / `update [path] playtime` commands use.
class Stats extends ChangeNotifier {
  // Singleton: one shared stats store (Stats.instance).
  Stats._();
  static final Stats instance = Stats._();

  late File _file;                              // playback_stats.json on the phone
  final _byTrack = <String, PlaybackStats>{};   // trackId -> its stats
  Timer? _saveTimer;                            // pending "save to disk" (see _changed)

  /// Loads saved stats from disk at startup.
  Future<void> init() async {
    final dir = await getApplicationSupportDirectory();
    _file = File(p.join(dir.path, 'playback_stats.json'));
    if (!await _file.exists()) return;
    try {
      final data = jsonDecode(await _file.readAsString()) as List;
      for (final e in data) {
        final stats = PlaybackStats.fromMap(e as Map<String, dynamic>);
        _byTrack[stats.trackId] = stats;
      }
    } catch (_) {
      // Corrupt file: start fresh rather than crash.
    }
  }

  /// Stats for one track. Songs never played get an all-zero object
  /// instead of null, so screens don't need null checks.
  PlaybackStats of(String trackId) =>
      _byTrack[trackId] ?? PlaybackStats(trackId: trackId, playCount: 0);

  Iterable<PlaybackStats> get all => _byTrack.values;

  // Totals for the Listening Stats screen. "fold" adds up a value across
  // every item in the list, starting from 0.
  int get totalPlays => all.fold(0, (sum, s) => sum + s.playCount);
  int get totalSeconds => all.fold(0, (sum, s) => sum + s.playtimeSeconds);

  /// Most-played first.
  List<PlaybackStats> top(int count) {
    final list = all.where((s) => s.playCount > 0).toList()
      ..sort((a, b) {
        final c = b.playCount.compareTo(a.playCount);
        return c != 0 ? c : b.playtimeSeconds.compareTo(a.playtimeSeconds);
      });
    return list.take(count).toList();
  }

  /// Adds listening time to a track (the player calls this every second).
  /// PlaybackStats fields are final, so we store an updated copy.
  void addPlaytime(String trackId, int seconds) {
    final s = of(trackId);
    _byTrack[trackId] = s.copyWith(
      playtimeSeconds: s.playtimeSeconds + seconds,
      lastPlayed: DateTime.now(),
    );
    _changed();
  }

  /// Adds one play to a track (the player decides when a listen counts).
  void recordPlay(String trackId) {
    final s = of(trackId);
    _byTrack[trackId] = s.copyWith(playCount: s.playCount + 1, lastPlayed: DateTime.now());
    _changed();
  }

  /// Clears everything (the reset button on the Listening Stats screen).
  Future<void> reset() async {
    _byTrack.clear();
    _changed();
    await flush();
  }

  void _changed() {
    notifyListeners(); // screens showing stats redraw right away
    // Playtime ticks every second; batch the disk writes.
    // "??=" only starts a timer if one isn't already waiting, so we save at
    // most once every 10 seconds instead of every second.
    _saveTimer ??= Timer(const Duration(seconds: 10), flush);
  }

  /// Writes all stats to disk now (also called when the app goes to the
  /// background, so nothing is lost if the phone kills the app).
  Future<void> flush() async {
    _saveTimer?.cancel();
    _saveTimer = null;
    await _file.writeAsString(jsonEncode([for (final s in all) s.toMap()]));
  }
}
