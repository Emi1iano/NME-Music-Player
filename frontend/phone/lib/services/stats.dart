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
  Stats._();
  static final Stats instance = Stats._();

  late File _file;
  final _byTrack = <String, PlaybackStats>{};
  Timer? _saveTimer;

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

  PlaybackStats of(String trackId) =>
      _byTrack[trackId] ?? PlaybackStats(trackId: trackId, playCount: 0);

  Iterable<PlaybackStats> get all => _byTrack.values;

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

  void addPlaytime(String trackId, int seconds) {
    final s = of(trackId);
    _byTrack[trackId] = s.copyWith(
      playtimeSeconds: s.playtimeSeconds + seconds,
      lastPlayed: DateTime.now(),
    );
    _changed();
  }

  void recordPlay(String trackId) {
    final s = of(trackId);
    _byTrack[trackId] = s.copyWith(playCount: s.playCount + 1, lastPlayed: DateTime.now());
    _changed();
  }

  Future<void> reset() async {
    _byTrack.clear();
    _changed();
    await flush();
  }

  void _changed() {
    notifyListeners();
    // Playtime ticks every second; batch the disk writes.
    _saveTimer ??= Timer(const Duration(seconds: 10), flush);
  }

  Future<void> flush() async {
    _saveTimer?.cancel();
    _saveTimer = null;
    await _file.writeAsString(jsonEncode([for (final s in all) s.toMap()]));
  }
}
