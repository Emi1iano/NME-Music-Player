import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../models/track.dart';
import '../theme.dart';

/// Cover art from an image file on disk (the picture embedded in the song,
/// pulled out during the library scan). Without one, a colored gradient tile
/// with the first letter of [name], like streaming apps show for songs
/// without art. The colors come from the name, so a song always gets the same
/// tile. Used everywhere a picture appears: song rows, album grid, Now Playing...
/// Pass a big [radius] (half the size) to make it a circle, like on Artists.
class Artwork extends StatelessWidget {
  final String? imagePath;
  final double size;
  final double radius;
  final String? name; // song / album / artist / playlist name for the placeholder

  const Artwork({
    super.key,
    required this.imagePath,
    required this.size,
    this.radius = 6,
    this.name,
  });

  @override
  Widget build(BuildContext context) {
    final path = imagePath;
    final placeholder = _Placeholder(name: name, size: size);

    // ClipRRect rounds the corners of whatever is inside it.
    return ClipRRect(
      borderRadius: BorderRadius.circular(radius),
      child: path == null
          ? placeholder
          : Image.file(
              File(path),
              width: size,
              height: size,
              fit: BoxFit.cover,
              // Decode at display size so big covers don't eat memory.
              cacheWidth: (size * MediaQuery.devicePixelRatioOf(context)).round(),
              gaplessPlayback: true, // keep the old image until the new one loads (no flicker)
              errorBuilder: (_, _, _) => placeholder, // file missing/corrupt -> placeholder
            ),
    );
  }
}

/// A playlist's picture: a 2x2 grid of its first four songs' covers (or
/// their letter tiles). With fewer than four songs, the first cover (or a
/// tile for the playlist's name).
class PlaylistCover extends StatelessWidget {
  final List<Track> tracks;
  final String name;
  final double size;
  final double radius;
  const PlaylistCover({
    super.key,
    required this.tracks,
    required this.name,
    required this.size,
    this.radius = 6,
  });

  @override
  Widget build(BuildContext context) {
    // Four different songs (a playlist can't hold one twice, but be safe).
    final four = {for (final t in tracks) t.id: t}.values.take(4).toList();
    if (four.length < 4) {
      final cover = tracks.where((t) => t.artworkPath != null).firstOrNull;
      return Artwork(imagePath: cover?.artworkPath, size: size, radius: radius, name: name);
    }
    final half = size / 2;
    Widget cell(Track t) => Artwork(imagePath: t.artworkPath, size: half, radius: 0, name: t.title);
    return ClipRRect(
      borderRadius: BorderRadius.circular(radius),
      child: SizedBox(
        width: size,
        height: size,
        child: Column(children: [
          Row(children: [cell(four[0]), cell(four[1])]),
          Row(children: [cell(four[2]), cell(four[3])]),
        ]),
      ),
    );
  }
}

/// The gradient tile with an initial (or a music note when there's no name).
class _Placeholder extends StatelessWidget {
  final String? name;
  final double size;
  const _Placeholder({required this.name, required this.size});

  @override
  Widget build(BuildContext context) {
    final letter = placeholderLetter(name);
    if (letter == null) {
      return Container(
        width: size,
        height: size,
        color: AppColors.surfaceHigh,
        child: Icon(Icons.music_note_rounded, size: size * 0.45, color: AppColors.textSecondary),
      );
    }
    final (from, to) = placeholderColors(name!);
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [from, to],
        ),
      ),
      child: Text(
        letter,
        style: TextStyle(
          color: Colors.white.withValues(alpha: 0.92),
          fontSize: size * 0.42,
          fontWeight: FontWeight.w700,
          height: 1,
        ),
      ),
    );
  }
}

/// The first letter or digit of [name], uppercased ("the weeknd" -> "T"),
/// or null if it has none.
String? placeholderLetter(String? name) {
  if (name == null) return null;
  for (final rune in name.runes) {
    final c = String.fromCharCode(rune);
    if (RegExp(r'[\p{L}\p{N}]', unicode: true).hasMatch(c)) return c.toUpperCase();
  }
  return null;
}

/// Two colors for the gradient, picked from [name] so the same name always
/// gets the same tile. Deep, slightly muted shades that suit the dark theme.
(Color, Color) placeholderColors(String name) {
  // A simple, stable hash (String.hashCode can differ between app runs).
  var hash = 0;
  for (final unit in name.toLowerCase().codeUnits) {
    hash = (hash * 31 + unit) & 0x7fffffff;
  }
  final hue = (hash % 360).toDouble();
  final from = HSLColor.fromAHSL(1, hue, 0.55, 0.42).toColor();
  final to = HSLColor.fromAHSL(1, (hue + 40) % 360, 0.60, 0.26).toColor();
  return (from, to);
}

/// The main color of a song's look, for tinting Now Playing: the most
/// colorful part of its cover art, or (no art) its placeholder color.
/// Results are kept in memory, so each cover is only read once.
Future<Color> coverColor({required String? imagePath, required String name}) async {
  if (imagePath == null) return placeholderColors(name).$1;
  final cached = _coverColors[imagePath];
  if (cached != null) return cached;
  Color result;
  try {
    // A tiny 24x24 copy of the image is plenty to find its main color.
    final bytes = await File(imagePath).readAsBytes();
    final codec = await ui.instantiateImageCodec(bytes, targetWidth: 24, targetHeight: 24);
    final image = (await codec.getNextFrame()).image;
    final data = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
    image.dispose();
    result = data == null ? placeholderColors(name).$1 : _vividAverage(data);
  } catch (_) {
    result = placeholderColors(name).$1; // unreadable image
  }
  _coverColors[imagePath] = result;
  return result;
}

final _coverColors = <String, Color>{};

/// Average of the pixels, weighted toward colorful ones, so a blue cover with
/// a black border comes out blue rather than grey.
Color _vividAverage(ByteData rgba) {
  double r = 0, g = 0, b = 0, total = 0;
  for (var i = 0; i + 3 < rgba.lengthInBytes; i += 4) {
    final pr = rgba.getUint8(i), pg = rgba.getUint8(i + 1), pb = rgba.getUint8(i + 2);
    final hi = [pr, pg, pb].reduce((a, c) => a > c ? a : c);
    final lo = [pr, pg, pb].reduce((a, c) => a < c ? a : c);
    final weight = 1 + (hi - lo); // chroma: grey pixels count a little, colorful ones a lot
    r += pr * weight;
    g += pg * weight;
    b += pb * weight;
    total += weight;
  }
  if (total == 0) return AppColors.surfaceHigh;
  return Color.fromARGB(255, (r / total).round(), (g / total).round(), (b / total).round());
}
