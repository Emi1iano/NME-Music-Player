import 'package:flutter/material.dart';

import '../models/track.dart';
import '../services/library.dart';
import '../theme.dart';
import 'artwork.dart';

class TrackTile extends StatelessWidget {
  final Track track;
  final bool isCurrent;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;
  final Widget? trailing;

  const TrackTile({
    super.key,
    required this.track,
    required this.onTap,
    this.isCurrent = false,
    this.onLongPress,
    this.trailing,
  });

  @override
  Widget build(BuildContext context) {
    return ListTile(
      onTap: onTap,
      onLongPress: onLongPress,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16),
      leading: Artwork(imagePath: track.artworkPath, size: 48),
      title: Text(
        track.title,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          fontWeight: FontWeight.w600,
          color: isCurrent ? AppColors.accent : AppColors.textPrimary,
        ),
      ),
      subtitle: Text(
        Library.instance.artistName(track.artistId),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(color: AppColors.textSecondary),
      ),
      trailing: trailing,
    );
  }
}
