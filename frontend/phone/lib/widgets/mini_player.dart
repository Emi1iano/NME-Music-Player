import 'package:flutter/material.dart';

import '../models/track.dart';
import '../screens/now_playing_screen.dart';
import '../services/library.dart';
import '../services/player.dart';
import '../theme.dart';
import 'artwork.dart';

/// Small bar above the tabs so you can get back to Now Playing.
class MiniPlayer extends StatelessWidget {
  const MiniPlayer({super.key});

  @override
  Widget build(BuildContext context) {
    final player = Player.instance;
    return StreamBuilder<Track?>(
      stream: player.currentTrackStream,
      initialData: player.currentTrack,
      builder: (context, snapshot) {
        final track = snapshot.data;
        if (track == null) return const SizedBox.shrink();
        return Material(
          color: AppColors.surfaceHigh,
          child: InkWell(
            onTap: () => openNowPlaying(context),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 4, 8),
              child: Row(children: [
                Artwork(imagePath: track.artworkPath, size: 40, radius: 4),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(track.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontWeight: FontWeight.w600)),
                      Text(Library.instance.artistName(track.artistId),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(color: AppColors.textSecondary, fontSize: 13)),
                    ],
                  ),
                ),
                StreamBuilder<bool>(
                  stream: player.audio.playingStream,
                  initialData: player.audio.playing,
                  builder: (context, snap) => IconButton(
                    iconSize: 32,
                    onPressed: player.togglePlay,
                    icon: Icon(snap.data! ? Icons.pause_rounded : Icons.play_arrow_rounded),
                  ),
                ),
                IconButton(
                  onPressed: player.next,
                  icon: const Icon(Icons.skip_next_rounded),
                ),
              ]),
            ),
          ),
        );
      },
    );
  }
}
