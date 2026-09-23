import 'package:flutter_test/flutter_test.dart';
import 'package:phone/data/mock_data.dart';
import 'package:phone/models/playback_stats.dart';
import 'package:phone/models/playlist.dart';
import 'package:phone/models/track.dart';
import 'package:phone/widgets/common.dart';

void main() {
  test('Track survives a toMap/fromMap round trip', () {
    final track = MockData.tracks.first;
    final copy = Track.fromMap(track.toMap());
    expect(copy.id, track.id);
    expect(copy.title, track.title);
    expect(copy.durationSeconds, track.durationSeconds);
  });

  test('PlaybackStats keeps play count, playtime and last played', () {
    final stats = PlaybackStats(
      trackId: 'Album/song.mp3',
      playCount: 3,
      playtimeSeconds: 125,
      lastPlayed: DateTime.utc(2026, 9, 23, 14, 30),
    );
    final copy = PlaybackStats.fromMap(stats.toMap());
    expect(copy.playCount, 3);
    expect(copy.playtimeSeconds, 125);
    expect(copy.lastPlayed, stats.lastPlayed);

    final updated = stats.copyWith(playCount: stats.playCount + 1);
    expect(updated.playCount, 4);
    expect(updated.playtimeSeconds, 125);
  });

  test('Old PlaybackStats data without playtime still loads', () {
    final stats = PlaybackStats.fromMap({'trackId': 'trk_1', 'playCount': 14});
    expect(stats.playtimeSeconds, 0);
    expect(stats.lastPlayed, isNull);
  });

  test('Playlist copyWith does not change the original', () {
    final playlist = MockData.playlists.first;
    final renamed = playlist.copyWith(name: 'Road trip', trackIds: ['trk_2']);
    expect(renamed.id, playlist.id);
    expect(renamed.name, 'Road trip');
    expect(playlist.trackIds, ['trk_1', 'trk_2']);
    expect(Playlist.fromMap(renamed.toMap()).trackIds, ['trk_2']);
  });

  test('time formatting', () {
    expect(formatDuration(const Duration(minutes: 3, seconds: 7)), '3:07');
    expect(formatSeconds(0), '--:--');
    expect(formatListenTime(45), '45 sec');
    expect(formatListenTime(12 * 60), '12 min');
    expect(formatListenTime(3 * 3600 + 5 * 60), '3 hr 5 min');
    expect(plural(1, 'play'), '1 play');
    expect(plural(4, 'play'), '4 plays');
  });
}
