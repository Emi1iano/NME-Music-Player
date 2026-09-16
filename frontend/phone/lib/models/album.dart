// The Album class organizes track collections and visual artwork.
class Album {
  final String id;
  final String title;
  final String artistId;
  final String? artworkUrl;     // The '?' means artwork is optional (can be null).
  final int releaseYear;

  Album({
    required this.id,
    required this.title,
    required this.artistId,
    this.artworkUrl,            // Not required because some albums may lack cover art.
    required this.releaseYear,
  });

  // Converts incoming raw JSON map into an Album object.
  factory Album.fromMap(Map<String, dynamic> map) {
    return Album(
      id: map['id'] ?? '',
      title: map['title'] ?? 'Unknown Album',
      artistId: map['artistId'] ?? '',
      artworkUrl: map['artworkUrl'],
      releaseYear: map['releaseYear'] ?? 0,
    );
  }
}