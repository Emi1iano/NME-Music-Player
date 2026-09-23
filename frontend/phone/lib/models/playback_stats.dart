// Stores listening metrics synced across devices.
class PlaybackStats {
  final String trackId;        // Links these stats to a specific Track
  final int playCount;          // Total number of times played
  final int playtimeSeconds;    // Total seconds listened
  final DateTime? lastPlayed;   // Timestamp of the last play event (optional)

  PlaybackStats({
    required this.trackId,
    required this.playCount,
    this.playtimeSeconds = 0,
    this.lastPlayed,
  });

  // Converts incoming raw JSON map into a PlaybackStats object.
  factory PlaybackStats.fromMap(Map<String, dynamic> map) {
    return PlaybackStats(
      trackId: map['trackId'] ?? '',
      playCount: map['playCount'] ?? 0,
      playtimeSeconds: map['playtimeSeconds'] ?? 0,
      // Safely parses an ISO date string (e.g. "2026-09-16") into a Dart DateTime.
      lastPlayed: map['lastPlayed'] != null
          ? DateTime.tryParse(map['lastPlayed'])
          : null,
    );
  }

  // Converts a PlaybackStats object back into a Map for saving/sending.
  Map<String, dynamic> toMap() => {
        'trackId': trackId,
        'playCount': playCount,
        'playtimeSeconds': playtimeSeconds,
        'lastPlayed': lastPlayed?.toIso8601String(),
      };

  // Fields are final, so updates create a changed copy.
  PlaybackStats copyWith({int? playCount, int? playtimeSeconds, DateTime? lastPlayed}) {
    return PlaybackStats(
      trackId: trackId,
      playCount: playCount ?? this.playCount,
      playtimeSeconds: playtimeSeconds ?? this.playtimeSeconds,
      lastPlayed: lastPlayed ?? this.lastPlayed,
    );
  }
}
