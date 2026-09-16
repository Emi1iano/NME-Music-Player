// The Playlist class holds a grouped list of tracks.
class Playlist {
  final String id;
  final String name;
  final List<String> trackIds;  // A list of Track IDs contained in this playlist

  Playlist({
    required this.id,
    required this.name,
    required this.trackIds,
  });

  // Converts incoming raw JSON map into a Playlist object.
  factory Playlist.fromMap(Map<String, dynamic> map) {
    return Playlist(
      id: map['id'] ?? '',
      name: map['name'] ?? 'Untitled Playlist',
      // Converts dynamic list values from JSON into a typed List<String>.
      trackIds: List<String>.from(map['trackIds'] ?? []),
    );
  }
}