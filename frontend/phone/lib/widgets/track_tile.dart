import 'package:flutter/material.dart';

import '../models/track.dart';
import '../services/library.dart';
import '../theme.dart';
import 'artwork.dart';

/// One song row: cover, title, artist. Reused by the Songs tab, artist
/// pages, and anywhere else a list of songs is shown.
class TrackTile extends StatelessWidget {
  final Track track;
  final bool isCurrent;            // highlights the title if this song is playing
  final VoidCallback onTap;
  final VoidCallback? onLongPress;
  final Widget? trailing;          // optional thing on the right, e.g. "3 plays"

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
      // Track only stores artistId, so look up the name to display.
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
