// Import your data models so this file can create instances of them.
import '../models/track.dart';
import '../models/album.dart';
import '../models/artist.dart';
import '../models/playlist.dart';
import '../models/playback_stats.dart';

// MockData provides dummy information so you can design UI screens
// before Emiliano completes the socket backend.
class MockData {
  // Static lists allow you to access data anywhere (e.g., MockData.tracks).

  static final List<Artist> artists = [
    Artist(id: 'art_1', name: 'NME Band'),
    Artist(id: 'art_2', name: 'Zig Synth Wave'),
  ];

  static final List<Album> albums = [
    Album(id: 'alb_1', title: 'First Draft', artistId: 'art_1', releaseYear: 2026),
    Album(id: 'alb_2', title: 'UDP Beats', artistId: 'art_2', releaseYear: 2026),
  ];

  static final List<Track> tracks = [
    Track(
      id: 'trk_1',
      title: 'Local Audio Stream',
      artistId: 'art_1',
      albumId: 'alb_1',
      // Sample MP3 URL to test real audio playback in Flutter
      audioUrl: 'https://www.soundhelix.com/examples/mp3/SoundHelix-Song-1.mp3',
      durationSeconds: 372,
    ),
    Track(
      id: 'trk_2',
      title: 'Zig Socket Groove',
      artistId: 'art_2',
      albumId: 'alb_2',
      audioUrl: 'https://www.soundhelix.com/examples/mp3/SoundHelix-Song-2.mp3',
      durationSeconds: 423,
    ),
  ];

  static final List<Playlist> playlists = [
    // Groups trk_1 and trk_2 into a single playlist
    Playlist(id: 'pl_1', name: 'Favorites', trackIds: ['trk_1', 'trk_2']),
  ];

  // Map pairing each trackId with its respective stats
  static final Map<String, PlaybackStats> stats = {
    'trk_1': PlaybackStats(
      trackId: 'trk_1', 
      playCount: 14, 
      lastPlayed: DateTime.now(),
    ),
    'trk_2': PlaybackStats(
      trackId: 'trk_2', 
      playCount: 3, 
      lastPlayed: DateTime.now().subtract(const Duration(hours: 5)),
    ),
  };
}