// The Artist class stores artist metadata for filtering or display.
class Artist {
  final String id;
  final String name;
  final String? imageUrl;       // Optional profile image URL

  Artist({
    required this.id,
    required this.name,
    this.imageUrl,
  });

  // Converts incoming raw JSON map into an Artist object.
  factory Artist.fromMap(Map<String, dynamic> map) {
    return Artist(
      id: map['id'] ?? '',
      name: map['name'] ?? 'Unknown Artist',
      imageUrl: map['imageUrl'],
    );
  }
}