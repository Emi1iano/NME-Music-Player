import 'dart:io';

import 'package:flutter/material.dart';

import '../theme.dart';

/// Cover art from an image file on disk, or a music-note placeholder.
/// Used everywhere a picture appears: song rows, album grid, Now Playing...
/// Pass a big [radius] (half the size) to make it a circle, like on Artists.
class Artwork extends StatelessWidget {
  final String? imagePath;
  final double size;
  final double radius;

  const Artwork({super.key, required this.imagePath, required this.size, this.radius = 6});

  @override
  Widget build(BuildContext context) {
    final path = imagePath;
    final placeholder = Container(
      width: size,
      height: size,
      color: AppColors.surfaceHigh,
      child: Icon(Icons.music_note_rounded, size: size * 0.45, color: AppColors.textSecondary),
    );

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
