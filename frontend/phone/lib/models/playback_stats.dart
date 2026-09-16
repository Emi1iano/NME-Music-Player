// Stores listening metrics synced across devices.
class PlaybackStats {
  final String trackId;        // Links these stats to a specific Track
  final int playCount;          // Total number of times played
  final DateTime? lastPlayed;   // Timestamp of the last play event (optional)

  PlaybackStats({
    required this.trackId,
    required this.playCount,
    this.lastPlayed,
  });

  // Converts incoming raw JSON map into a PlaybackStats object.
  factory PlaybackStats.fromMap(Map<String, dynamic> map) {
    return PlaybackStats(
      trackId: map['trackId'] ?? '',
      playCount: map['playCount'] ?? 0,
      // Safely parses an ISO date string (e.g. "2026-09-16") into a Dart DateTime.
      lastPlayed: map['lastPlayed'] != null 
          ? DateTime.tryParse(map['lastPlayed']) 
          : null,
    );
  }
}