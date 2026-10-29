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
    // Rebuilds whenever the song changes.
    return StreamBuilder<Track?>(
      stream: player.currentTrackStream,
      initialData: player.currentTrack,
      builder: (context, snapshot) {
        final track = snapshot.data;
        // Nothing loaded yet -> take up no space at all.
        if (track == null) return const SizedBox.shrink();
        return Material(
          color: AppColors.surfaceHigh,
          child: InkWell(
            onTap: () => openNowPlaying(context),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              // Thin bar along the top: how far into the song we are.
              StreamBuilder<Duration>(
                stream: player.audio.positionStream,
                builder: (context, snap) {
                  final total = player.audio.duration ?? Duration.zero;
                  final pos = snap.data ?? Duration.zero;
                  final value = total.inMilliseconds > 0
                      ? (pos.inMilliseconds / total.inMilliseconds).clamp(0.0, 1.0)
                      : 0.0;
                  return LinearProgressIndicator(
                    value: value,
                    minHeight: 2,
                    backgroundColor: Colors.transparent,
                    color: AppColors.accent,
                  );
                },
              ),
              Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 4, 8),
              child: Row(children: [
                Hero(
                  tag: nowPlayingArtTag, // grows into Now Playing's cover
                  child: Artwork(imagePath: track.artworkPath, size: 40, radius: 4, name: track.title),
                ),
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
                // Play/pause icon follows whether audio is actually playing.
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
            ]),
          ),
        );
      },
    );
  }
}
