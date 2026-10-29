import 'dart:io';

import 'package:flutter/material.dart';

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
