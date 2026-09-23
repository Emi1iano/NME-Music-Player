// The Track class acts as a blueprint for song objects in your Flutter app.
class Track {
  // Properties: Defines the fields every Track must have in app memory.
  // For local files, id is the path inside the Music folder (e.g. "Album/song.mp3"),
  // so it matches on every device and can be used by the backend's
  // "update [path] ..." commands.
  final String id;
  final String title;
  final String artistId;
  final String albumId;
  final String audioUrl; // Local file path or local netowrk URL for audio
  final int durationSeconds;

  // Optional details read from the file's tags.
  final String? artworkPath;    // Cover image cached on disk
  final int? trackNumber;
  final int? discNumber;
  final DateTime? dateAdded;    // Used for "Recently added" sorting

  // Constructor: Creates a new Track instance
  // "required" means Flutter won't let you build a Track missing these values.
  Track({
    required this.id,
    required this.title,
    required this.artistId,
    required this.albumId,
    required this.audioUrl,
    required this.durationSeconds,
    this.artworkPath,
    this.trackNumber,
    this.discNumber,
    this.dateAdded,
  });

  // Factory Constructor: The "Translator"
  // Converts raw key-value data (Map/JSON) from Emiliano's socket into a Dart Track object.
  factory Track.fromMap(Map<String, dynamic> map) {
    return Track(
      // The '??' provides a fallback value if a field is missing or null.
      id: map['id'] ?? '',
      title: map['title'] ?? 'Unknown Track',
      artistId: map['artistId'] ?? '',
      albumId: map['albumId'] ?? '',
      audioUrl: map['audioUrl'] ?? '',
      durationSeconds: map['durationSeconds'] ?? 0,
      trackNumber: map['trackNumber'],
      discNumber: map['discNumber'],
    );
  }

  // The reverse "Translator": turns a Track back into a Map for sending/saving.
  Map<String, dynamic> toMap() => {
        'id': id,
        'title': title,
        'artistId': artistId,
        'albumId': albumId,
        'audioUrl': audioUrl,
        'durationSeconds': durationSeconds,
        'trackNumber': trackNumber,
        'discNumber': discNumber,
      };
}
