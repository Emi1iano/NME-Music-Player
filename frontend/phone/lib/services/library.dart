import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'package:audio_metadata_reader/audio_metadata_reader.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/album.dart';
import '../models/artist.dart';
import '../models/track.dart';
import 'stats.dart';

enum SortMode { title, artist, recentlyAdded, mostPlayed }

extension SortModeLabel on SortMode {
  String get label => switch (this) {
        SortMode.title => 'Title',
        SortMode.artist => 'Artist',
        SortMode.recentlyAdded => 'Recently added',
        SortMode.mostPlayed => 'Most played',
      };
}

const audioExtensions = {
  '.mp3', '.m4a', '.aac', '.wav', '.flac', '.ogg', '.opus', //
};

/// Finds every song in the app's Music folder and turns it into
/// [Track], [Album] and [Artist] objects.
class Library extends ChangeNotifier {
  Library._();
  static final Library instance = Library._();

  late Directory musicDir;
  late Directory _artDir;

  List<Track> _tracks = [];
  List<Album> _albums = [];
  List<Artist> _artists = [];
  final _trackById = <String, Track>{};
  final _albumById = <String, Album>{};
  final _albumTracks = <String, List<Track>>{};
  final _artistTracks = <String, List<Track>>{};
  final _artistNames = <String, String>{};

  SortMode _sortMode = SortMode.title;
  bool scanning = true;
  bool _scanInProgress = false;

  List<Track> get tracks => _tracks;
  List<Album> get albums => _albums;
  List<Artist> get artists => _artists;
  SortMode get sortMode => _sortMode;

  Track? trackById(String id) => _trackById[id];
  Album? albumById(String id) => _albumById[id];
  String artistName(String artistId) => _artistNames[artistId] ?? 'Unknown Artist';
  String albumTitle(String albumId) => _albumById[albumId]?.title ?? 'Unknown Album';

  /// Songs on an album, in disc/track order.
  List<Track> tracksOf(Album album) => _albumTracks[album.id] ?? const [];

  /// Songs by an artist, A–Z.
  List<Track> tracksBy(Artist artist) => _artistTracks[artist.id] ?? const [];

  /// Albums that contain at least one song by [artist].
  List<Album> albumsBy(Artist artist) {
    final ids = tracksBy(artist).map((t) => t.albumId).toSet();
    return _albums.where((a) => ids.contains(a.id)).toList();
  }

  /// A track with cover art to stand in for an album/artist picture.
  Track? coverFor(List<Track> tracks) =>
      tracks.where((t) => t.artworkPath != null).firstOrNull ?? tracks.firstOrNull;

  Future<void> init() async {
    // Android: /storage/emulated/0/Android/data/<app id>/files/Music
    //   (reachable from a PC over USB).
    // iOS: <app>/Documents/Music (visible in the Files app).
    final base = Platform.isAndroid
        ? (await getExternalStorageDirectory() ??
            await getApplicationDocumentsDirectory())
        : await getApplicationDocumentsDirectory();
    musicDir = Directory(p.join(base.path, 'Music'));
    await musicDir.create(recursive: true);

    _artDir = Directory(p.join((await getApplicationCacheDirectory()).path, 'art'));
    await _artDir.create(recursive: true);

    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getInt('sortMode') ?? 0;
    _sortMode = SortMode.values[saved.clamp(0, SortMode.values.length - 1)];
  }

  Future<void> scan() async {
    if (_scanInProgress) return;
    _scanInProgress = true;
    scanning = true;
    notifyListeners();
    try {
      final musicPath = musicDir.path;
      final artPath = _artDir.path;
      final files = await Isolate.run(() => _scanFolder(musicPath, artPath));
      _build(files);
      _sort();
    } finally {
      _scanInProgress = false;
      scanning = false;
      notifyListeners();
    }
  }

  Future<void> setSortMode(SortMode mode) async {
    _sortMode = mode;
    _sort();
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('sortMode', mode.index);
  }

  /// Re-sorts after play counts change (only matters for "Most played").
  void refreshSort() {
    if (_sortMode != SortMode.mostPlayed) return;
    _sort();
    notifyListeners();
  }

  void _build(List<_ScannedFile> files) {
    _trackById.clear();
    _albumById.clear();
    _albumTracks.clear();
    _artistTracks.clear();
    _artistNames.clear();

    String artistIdFor(String name) {
      final id = 'artist:${name.toLowerCase()}';
      _artistNames.putIfAbsent(id, () => name);
      return id;
    }

    // Same album name + album artist tag is one album. Without that tag, fall
    // back to the folder, so tracks with featured artists stay together.
    final byAlbum = <String, List<_ScannedFile>>{};
    for (final f in files) {
      final owner = f.albumArtist?.toLowerCase() ?? p.dirname(f.relativePath);
      (byAlbum['album:${f.album.toLowerCase()}|$owner'] ??= []).add(f);
    }

    final tracks = <Track>[];
    final albums = <Album>[];
    byAlbum.forEach((albumId, group) {
      final artistNames = group.map((f) => f.artist.toLowerCase()).toSet();
      final albumArtist = group.map((f) => f.albumArtist).nonNulls.firstOrNull ??
          (artistNames.length == 1 ? group.first.artist : 'Various Artists');
      final cover = group.map((f) => f.artPath).nonNulls.firstOrNull;

      final album = Album(
        id: albumId,
        title: group.first.album,
        artistId: artistIdFor(albumArtist),
        artworkUrl: cover,
        releaseYear: group.map((f) => f.year).nonNulls.firstOrNull ?? 0,
      );
      albums.add(album);
      _albumById[albumId] = album;

      for (final f in group) {
        final track = Track(
          id: f.relativePath,
          title: f.title,
          artistId: artistIdFor(f.artist),
          albumId: albumId,
          audioUrl: f.path,
          durationSeconds: f.durationSeconds,
          artworkPath: f.artPath,
          trackNumber: f.trackNumber,
          discNumber: f.discNumber,
          dateAdded: f.modified,
        );
        tracks.add(track);
        _trackById[track.id] = track;
        (_albumTracks[albumId] ??= []).add(track);
        (_artistTracks[track.artistId] ??= []).add(track);
      }
    });

    int trackOrder(Track a, Track b) {
      final disc = (a.discNumber ?? 1).compareTo(b.discNumber ?? 1);
      if (disc != 0) return disc;
      final n = (a.trackNumber ?? 9999).compareTo(b.trackNumber ?? 9999);
      return n != 0 ? n : _cmp(a.title, b.title);
    }

    for (final list in _albumTracks.values) {
      list.sort(trackOrder);
    }
    for (final list in _artistTracks.values) {
      list.sort((a, b) => _cmp(a.title, b.title));
    }

    _tracks = tracks;
    _albums = albums..sort((a, b) => _cmp(a.title, b.title));
    _artists = [
      for (final id in _artistTracks.keys) Artist(id: id, name: _artistNames[id]!),
    ]..sort((a, b) => _cmp(a.name, b.name));
  }

  void _sort() {
    switch (_sortMode) {
      case SortMode.title:
        _tracks.sort((a, b) => _cmp(a.title, b.title));
      case SortMode.artist:
        _tracks.sort((a, b) {
          final c = _cmp(artistName(a.artistId), artistName(b.artistId));
          return c != 0 ? c : _cmp(a.title, b.title);
        });
      case SortMode.recentlyAdded:
        _tracks.sort((a, b) => (b.dateAdded ?? DateTime(0))
            .compareTo(a.dateAdded ?? DateTime(0)));
      case SortMode.mostPlayed:
        final stats = Stats.instance;
        _tracks.sort((a, b) {
          final c = stats.of(b.id).playCount.compareTo(stats.of(a.id).playCount);
          return c != 0 ? c : _cmp(a.title, b.title);
        });
    }
  }

  static int _cmp(String a, String b) => a.toLowerCase().compareTo(b.toLowerCase());
}

/// What the background scan reads from one file.
class _ScannedFile {
  final String path;
  final String relativePath;
  final String title;
  final String artist;
  final String album;
  final String? albumArtist;
  final int? year;
  final int? trackNumber;
  final int? discNumber;
  final int durationSeconds;
  final String? artPath;
  final DateTime modified;

  _ScannedFile({
    required this.path,
    required this.relativePath,
    required this.title,
    required this.artist,
    required this.album,
    required this.albumArtist,
    required this.year,
    required this.trackNumber,
    required this.discNumber,
    required this.durationSeconds,
    required this.artPath,
    required this.modified,
  });
}

/// Runs in a background isolate so large folders don't freeze the UI.
List<_ScannedFile> _scanFolder(String musicPath, String artPath) {
  final results = <_ScannedFile>[];
  final files = Directory(musicPath)
      .listSync(recursive: true, followLinks: false)
      .whereType<File>()
      .where((f) => audioExtensions.contains(p.extension(f.path).toLowerCase()));

  for (final file in files) {
    final modified = file.lastModifiedSync();
    String? title, artist, album, albumArtist, cover;
    int? year, trackNumber, discNumber;
    Duration? duration;

    try {
      final meta = readMetadata(file, getImage: true);
      title = meta.title;
      artist = meta.artist;
      album = meta.album;
      albumArtist = meta.albumArtist;
      final y = meta.year?.year;
      year = (y != null && y > 0) ? y : null;
      trackNumber = meta.trackNumber;
      discNumber = meta.discNumber;
      duration = meta.duration;
      cover = _saveCover(meta.pictures, file.path, modified, artPath);
    } catch (_) {
      // Unreadable or untagged file: fall back to the file name.
    }

    results.add(_ScannedFile(
      path: file.path,
      // Forward slashes on every platform so ids match across devices.
      relativePath: p.posix.joinAll(p.split(p.relative(file.path, from: musicPath))),
      title: _orElse(title, p.basenameWithoutExtension(file.path)),
      artist: _orElse(artist, 'Unknown Artist'),
      album: _orElse(album, 'Unknown Album'),
      albumArtist: (albumArtist == null || albumArtist.trim().isEmpty)
          ? null
          : albumArtist.trim(),
      year: year,
      trackNumber: trackNumber,
      discNumber: discNumber,
      durationSeconds: duration?.inSeconds ?? 0,
      artPath: cover,
      modified: modified,
    ));
  }
  return results;
}

String _orElse(String? value, String fallback) =>
    (value == null || value.trim().isEmpty) ? fallback : value.trim();

/// Writes the song's cover to the cache so both the UI and the lock screen
/// can load it from a file.
String? _saveCover(
    List<Picture> pictures, String songPath, DateTime modified, String artPath) {
  if (pictures.isEmpty) return null;
  final picture = pictures.firstWhere(
    (pic) => pic.pictureType == PictureType.coverFront,
    orElse: () => pictures.first,
  );
  final ext = picture.mimetype.contains('png') ? 'png' : 'jpg';
  final name = md5.convert(utf8.encode(songPath)).toString();
  final out = File(p.join(artPath, '$name.$ext'));
  if (!out.existsSync() || out.lastModifiedSync().isBefore(modified)) {
    out.writeAsBytesSync(picture.bytes);
  }
  return out.path;
}
