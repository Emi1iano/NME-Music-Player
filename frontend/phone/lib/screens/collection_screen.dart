import 'package:flutter/material.dart';

import '../models/track.dart';
import '../services/player.dart';
import '../theme.dart';
import '../widgets/artwork.dart';
import '../widgets/common.dart';
import '../widgets/track_tile.dart';
import 'now_playing_screen.dart';

/// Detail page for an album or artist: big art, title, Play / Shuffle, songs.
/// One reusable screen for both — the Albums and Artists tabs just pass in
/// different titles, pictures and track lists.
class CollectionScreen extends StatelessWidget {
  final String title;
  final String subtitle;
  final String? imagePath;
  final List<Track> tracks;
  final bool roundArt;
  final bool showTrackNumbers;

  const CollectionScreen({
    super.key,
    required this.title,
    required this.subtitle,
    required this.imagePath,
    required this.tracks,
    this.roundArt = false,
    this.showTrackNumbers = false,
  });

  @override
  Widget build(BuildContext context) {
    final player = Player.instance;
    final artSize = MediaQuery.sizeOf(context).width * 0.55;

    return Scaffold(
      appBar: AppBar(),
      body: StreamBuilder<Track?>(
        stream: player.currentTrackStream,
        initialData: player.currentTrack,
        builder: (context, snapshot) => ListView.builder(
          padding: const EdgeInsets.only(bottom: 16),
          // +1 because row 0 is the header (art, title, buttons), then the songs.
          itemCount: tracks.length + 1,
          itemBuilder: (context, i) {
            if (i == 0) {
              return Column(children: [
                Artwork(imagePath: imagePath, size: artSize, radius: roundArt ? artSize / 2 : 12),
                const SizedBox(height: 16),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 24),
                  child: Text(title,
                      textAlign: TextAlign.center,
                      style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w800)),
                ),
                const SizedBox(height: 4),
                Text(subtitle,
                    style: const TextStyle(color: AppColors.textSecondary, fontSize: 15)),
                const SizedBox(height: 16),
                PlayShuffleButtons(
                  onPlay: () => player.playTracks(tracks, index: 0, shuffle: false),
                  onShuffle: () => player.playTracks(tracks, shuffle: true),
                ),
              ]);
            }
            final track = tracks[i - 1];
            final isCurrent = snapshot.data?.id == track.id;
            void play() {
              player.playTracks(tracks, index: i - 1);
              openNowPlaying(context);
            }

            // Album pages show "1  Song title  3:07" like a track listing;
            // artist pages use the normal row with cover art.
            if (showTrackNumbers) {
              return ListTile(
                onTap: play,
                onLongPress: () => showAddToPlaylist(context, track),
                leading: SizedBox(
                  width: 28,
                  child: Text('${track.trackNumber ?? i}',
                      textAlign: TextAlign.center,
                      style: const TextStyle(color: AppColors.textSecondary)),
                ),
                title: Text(track.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontWeight: FontWeight.w600,
                      color: isCurrent ? AppColors.accent : AppColors.textPrimary,
                    )),
                trailing: Text(formatSeconds(track.durationSeconds),
                    style: const TextStyle(color: AppColors.textSecondary)),
              );
            }
            return TrackTile(
              track: track,
              isCurrent: isCurrent,
              onTap: play,
              onLongPress: () => showAddToPlaylist(context, track),
            );
          },
        ),
      ),
    );
  }
}
