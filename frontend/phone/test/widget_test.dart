import 'package:flutter_test/flutter_test.dart';
import 'package:phone/data/mock_data.dart';
import 'package:phone/models/playback_stats.dart';
import 'package:phone/models/playlist.dart';
import 'package:phone/models/track.dart';
import 'package:phone/services/library.dart';
import 'package:phone/services/stats.dart';
import 'package:phone/widgets/artwork.dart';
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

  test('"last synced" wording', () {
    final now = DateTime(2026, 10, 28, 18, 0);
    expect(formatAgo(now.subtract(const Duration(seconds: 20)), now: now), 'just now');
    expect(formatAgo(now.subtract(const Duration(minutes: 5)), now: now), '5 min ago');
    expect(formatAgo(now.subtract(const Duration(hours: 3)), now: now), '3 hr ago');
    expect(formatAgo(now.subtract(const Duration(hours: 30)), now: now), 'yesterday');
    expect(formatAgo(now.subtract(const Duration(days: 4)), now: now), '4 days ago');
  });

  test('artist and title from a file name', () {
    var g = guessFromFileName('Ellie Goulding - Burn');
    expect((g.artist, g.title), ('Ellie Goulding', 'Burn'));
    g = guessFromFileName('03 - Daft Punk - Get Lucky (Official Video)');
    expect((g.artist, g.title), ('Daft Punk', 'Get Lucky'));
    g = guessFromFileName('Cry for you');
    expect((g.artist, g.title), (null, 'Cry for you'));
    g = guessFromFileName('The_Weeknd_-_Blinding_Lights [Lyrics]');
    expect((g.artist, g.title), ('The Weeknd', 'Blinding Lights'));
    // Brackets that aren't extras stay.
    g = guessFromFileName('Artist - Song (Remix)');
    expect((g.artist, g.title), ('Artist', 'Song (Remix)'));
  });

  test('placeholder art letter and colors', () {
    expect(placeholderLetter('the weeknd'), 'T');
    expect(placeholderLetter('  (Remix) song'), 'R');
    expect(placeholderLetter('99 Problems'), '9');
    expect(placeholderLetter('***'), isNull);
    expect(placeholderLetter(null), isNull);
    // Same name, same colors, every time.
    expect(placeholderColors('Burn'), placeholderColors('Burn'));
    expect(placeholderColors('Burn'), isNot(placeholderColors('Cry for you')));
  });

  test('weekly chart days', () {
    expect(Stats.dayKey(DateTime(2026, 3, 7, 23, 59)), '2026-03-07');
    final week = Stats.instance.lastDays(7, now: DateTime(2026, 10, 28, 18));
    expect(week.length, 7);
    expect(week.first.$1, DateTime(2026, 10, 22)); // oldest first
    expect(week.last.$1, DateTime(2026, 10, 28)); // ends today
  });
}
