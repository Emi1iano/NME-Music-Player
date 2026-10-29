import 'package:flutter/material.dart';

import '../models/track.dart';
import '../services/appearance.dart';
import '../services/library.dart';
import '../theme.dart';
import 'artwork.dart';
import 'common.dart';

/// One song row: cover, title, artist, length. Reused by the Songs tab,
/// artist pages, and anywhere else a list of songs is shown. Songs that
/// arrived from another device and haven't been played get a "NEW" tag.
class TrackTile extends StatelessWidget {
  final Track track;
  final bool isCurrent;            // highlights the title if this song is playing
  final VoidCallback onTap;
  final VoidCallback? onLongPress;
  final Widget? trailing;          // replaces the song length, e.g. "3 plays"

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
    final appearance = Appearance.instance;
    final isNew = appearance.newTags && Library.instance.isNew(track.id);
    final compact = appearance.compactRows; // Settings → Appearance → Compact song rows
    return ListTile(
      onTap: onTap,
      onLongPress: onLongPress,
      dense: compact,
      visualDensity: compact ? VisualDensity.compact : null,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16),
      leading: Artwork(imagePath: track.artworkPath, size: compact ? 40 : 48, name: track.title),
      title: Row(children: [
        Flexible(
          child: Text(
            track.title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontWeight: FontWeight.w600,
              color: isCurrent ? AppColors.accent : AppColors.textPrimary,
            ),
          ),
        ),
        if (isNew) ...[const SizedBox(width: 8), const NewTag()],
      ]),
      // Track only stores artistId, so look up the name to display.
      subtitle: Text(
        Library.instance.artistName(track.artistId),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(color: AppColors.textSecondary),
      ),
      trailing: trailing ??
          (track.durationSeconds > 0
              ? Text(formatSeconds(track.durationSeconds),
                  style: const TextStyle(color: AppColors.textSecondary, fontSize: 13))
              : null),
    );
  }
}

/// The small "NEW" pill next to a song that came from a sync.
class NewTag extends StatelessWidget {
  const NewTag({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: AppColors.accent,
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text('NEW',
          style: TextStyle(
              color: AppColors.onAccent,
              fontSize: 10,
              fontWeight: FontWeight.w800,
              letterSpacing: 0.5)),
    );
  }
}
