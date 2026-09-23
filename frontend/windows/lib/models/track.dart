/// A single song. Replace [id] with whatever primary key your Zig server
/// hands out once the sync protocol is defined.
class Track {
  final String id;
  final String title;
  final String artist;
  final String album;
  final Duration duration;
  final bool downloadedOffline;

  const Track({
    required this.id,
    required this.title,
    required this.artist,
    required this.album,
    required this.duration,
    required this.downloadedOffline,
  });

  String get durationLabel {
    final m = duration.inMinutes;
    final s = duration.inSeconds % 60;
    return '$m:${s.toString().padLeft(2, '0')}';
  }
}
