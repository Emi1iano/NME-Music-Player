import 'dart:io';

import 'package:flutter/material.dart';
import 'package:just_audio/just_audio.dart';

import '../models/track.dart';
import '../services/library.dart';
import '../services/player.dart';
import '../services/stats.dart';
import '../theme.dart';
import '../widgets/artwork.dart';
import '../widgets/common.dart';

/// Opens the full-screen player. Any screen can call this.
void openNowPlaying(BuildContext context) {
  Navigator.of(context).push(MaterialPageRoute(
    fullscreenDialog: true, // slides up from the bottom
    builder: (_) => const NowPlayingScreen(),
  ));
}

/// The Now Playing screen from the sketch, top to bottom:
/// ✕ close, cover art, title/artist + ≡+ and ⋯, seek bar,
/// shuffle / previous / play / next / repeat, then queue and output buttons.
///
/// Each part is its own small widget (_TitleRow, _SeekBar, _Controls,
/// _BottomRow) that listens only to the player data it needs, so e.g. the
/// seek bar updating every moment doesn't redraw the whole screen.
class NowPlayingScreen extends StatelessWidget {
  const NowPlayingScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final player = Player.instance;
    return Scaffold(
      body: SafeArea(
        child: StreamBuilder<Track?>(
          stream: player.currentTrackStream,
          initialData: player.currentTrack,
          builder: (context, snapshot) {
            final track = snapshot.data;
            return LayoutBuilder(builder: (context, constraints) {
              // Keep the art square and leave room for the controls below.
              final artSize = (constraints.maxWidth - 48)
                  .clamp(120.0, constraints.maxHeight - 360)
                  .toDouble();
              return Column(
                children: [
                  Align(
                    alignment: Alignment.centerLeft,
                    child: IconButton(
                      tooltip: 'Close',
                      icon: const Icon(Icons.close_rounded),
                      onPressed: () => Navigator.pop(context),
                    ),
                  ),
                  const Spacer(),
                  Artwork(imagePath: track?.artworkPath, size: artSize, radius: 12),
                  const Spacer(),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 24),
                    child: _TitleRow(track: track),
                  ),
                  const SizedBox(height: 12),
                  const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 12),
                    child: _SeekBar(),
                  ),
                  const SizedBox(height: 4),
                  const _Controls(),
                  const SizedBox(height: 16),
                  const _BottomRow(),
                  const SizedBox(height: 8),
                ],
              );
            });
          },
        ),
      ),
    );
  }
}

/// Song title, artist, the live "N plays • X listened" line, and the
/// add-to-playlist (≡+) and more (⋯) buttons.
class _TitleRow extends StatelessWidget {
  final Track? track;
  const _TitleRow({required this.track});

  @override
  Widget build(BuildContext context) {
    final track = this.track;
    final library = Library.instance;
    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(track?.title ?? 'Not playing',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w700)),
              const SizedBox(height: 2),
              Text(track == null ? '' : library.artistName(track.artistId),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 16, color: AppColors.textSecondary)),
              // Listens to Stats so the play count / time update every second.
              if (track != null)
                ListenableBuilder(
                  listenable: Stats.instance,
                  builder: (context, _) {
                    final s = Stats.instance.of(track.id);
                    return Text(
                      '${plural(s.playCount, 'play')}  •  ${formatListenTime(s.playtimeSeconds)} listened',
                      style: const TextStyle(fontSize: 12, color: AppColors.textSecondary),
                    );
                  },
                ),
            ],
          ),
        ),
        IconButton(
          tooltip: 'Add to playlist',
          icon: const Icon(Icons.playlist_add_rounded),
          onPressed: track == null ? null : () => showAddToPlaylist(context, track),
        ),
        IconButton(
          tooltip: 'More',
          icon: const Icon(Icons.more_horiz_rounded),
          onPressed: track == null ? null : () => _showMore(context, track),
        ),
      ],
    );
  }

  /// The ⋯ menu (a bottom sheet that slides up).
  void _showMore(BuildContext context, Track track) {
    showModalBottomSheet<void>(
      context: context,
      builder: (sheetContext) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          ListTile(
            leading: const Icon(Icons.playlist_add_rounded),
            title: const Text('Add to playlist'),
            onTap: () {
              Navigator.pop(sheetContext);
              showAddToPlaylist(context, track);
            },
          ),
          ListTile(
            leading: const Icon(Icons.info_outline_rounded),
            title: const Text('Song info'),
            onTap: () {
              Navigator.pop(sheetContext);
              _showInfo(context, track);
            },
          ),
        ]),
      ),
    );
  }

  /// "Song info" dialog: tags from the file plus its PlaybackStats.
  void _showInfo(BuildContext context, Track track) {
    final library = Library.instance;
    final stats = Stats.instance.of(track.id);
    final last = stats.lastPlayed;
    Widget row(String label, String value) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(label, style: const TextStyle(color: AppColors.textSecondary, fontSize: 12)),
            Text(value),
          ]),
        );
    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Song info'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              row('Title', track.title),
              row('Artist', library.artistName(track.artistId)),
              row('Album', library.albumTitle(track.albumId)),
              row('Length', formatSeconds(track.durationSeconds)),
              row('Plays', '${stats.playCount}'),
              row('Time listened', formatListenTime(stats.playtimeSeconds)),
              row('Last played', last == null ? 'Never' : _formatDate(last)),
              row('File', track.id),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Close')),
        ],
      ),
    );
  }

  static String _formatDate(DateTime d) {
    final local = d.toLocal();
    String two(int n) => n.toString().padLeft(2, '0');
    return '${local.year}-${two(local.month)}-${two(local.day)} ${two(local.hour)}:${two(local.minute)}';
  }
}

/// The progress slider with elapsed / total time underneath.
class _SeekBar extends StatefulWidget {
  const _SeekBar();

  @override
  State<_SeekBar> createState() => _SeekBarState();
}

class _SeekBarState extends State<_SeekBar> {
  double? _dragValue; // ms, while the user is dragging

  @override
  Widget build(BuildContext context) {
    final audio = Player.instance.audio;
    return StreamBuilder<Duration?>(
      stream: audio.durationStream,
      initialData: audio.duration,
      builder: (context, durSnap) {
        final duration = durSnap.data ?? Duration.zero;
        return StreamBuilder<Duration>(
          stream: audio.positionStream,
          initialData: audio.position,
          builder: (context, posSnap) {
            final max = duration.inMilliseconds.toDouble();
            final pos = (_dragValue ?? posSnap.data!.inMilliseconds.toDouble())
                .clamp(0.0, max > 0 ? max : 0.0);
            return Column(children: [
              Slider(
                value: pos,
                max: max > 0 ? max : 1,
                onChanged: max > 0 ? (v) => setState(() => _dragValue = v) : null,
                // While dragging we only move the slider (_dragValue); the
                // actual seek happens once, when the finger lets go.
                onChangeEnd: (v) {
                  audio.seek(Duration(milliseconds: v.round()));
                  setState(() => _dragValue = null);
                },
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(formatDuration(Duration(milliseconds: pos.round())),
                        style: _timeStyle),
                    Text(formatDuration(duration), style: _timeStyle),
                  ],
                ),
              ),
            ]);
          },
        );
      },
    );
  }

  static const _timeStyle = TextStyle(
    color: AppColors.textSecondary,
    fontSize: 12,
    fontFeatures: [FontFeature.tabularFigures()],
  );
}

/// Shuffle, previous, play/pause, next, repeat. Each button listens to its
/// own player stream so its icon/color always matches the real state.
class _Controls extends StatelessWidget {
  const _Controls();

  @override
  Widget build(BuildContext context) {
    final player = Player.instance;
    final audio = player.audio;
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      children: [
        StreamBuilder<bool>(
          stream: audio.shuffleModeEnabledStream,
          initialData: audio.shuffleModeEnabled,
          builder: (context, snap) => IconButton(
            tooltip: 'Shuffle',
            icon: const Icon(Icons.shuffle_rounded),
            color: snap.data! ? AppColors.accent : AppColors.textSecondary,
            onPressed: player.toggleShuffle,
          ),
        ),
        IconButton(
          tooltip: 'Previous',
          iconSize: 40,
          icon: const Icon(Icons.skip_previous_rounded),
          onPressed: player.previous,
        ),
        StreamBuilder<PlayerState>(
          stream: audio.playerStateStream,
          initialData: audio.playerState,
          builder: (context, snap) {
            final state = snap.data!;
            final loading = state.processingState == ProcessingState.loading ||
                state.processingState == ProcessingState.buffering;
            return SizedBox(
              width: 72,
              height: 72,
              child: IconButton.filled(
                tooltip: state.playing ? 'Pause' : 'Play',
                style: IconButton.styleFrom(
                  backgroundColor: AppColors.textPrimary,
                  foregroundColor: AppColors.background,
                ),
                iconSize: 44,
                onPressed: player.togglePlay,
                icon: loading && state.playing
                    ? const SizedBox(
                        width: 28,
                        height: 28,
                        child: CircularProgressIndicator(
                            strokeWidth: 3, color: AppColors.background))
                    : Icon(state.playing
                        ? Icons.pause_rounded
                        : Icons.play_arrow_rounded),
              ),
            );
          },
        ),
        IconButton(
          tooltip: 'Next',
          iconSize: 40,
          icon: const Icon(Icons.skip_next_rounded),
          onPressed: player.next,
        ),
        StreamBuilder<LoopMode>(
          stream: audio.loopModeStream,
          initialData: audio.loopMode,
          builder: (context, snap) {
            final mode = snap.data!;
            return IconButton(
              tooltip: switch (mode) {
                LoopMode.off => 'Repeat off',
                LoopMode.all => 'Repeat all',
                LoopMode.one => 'Repeat one',
              },
              icon: Icon(mode == LoopMode.one
                  ? Icons.repeat_one_rounded
                  : Icons.repeat_rounded),
              color: mode == LoopMode.off ? AppColors.textSecondary : AppColors.accent,
              onPressed: player.cycleRepeat,
            );
          },
        ),
      ],
    );
  }
}

/// Queue (≡) and output-device buttons at the very bottom.
class _BottomRow extends StatelessWidget {
  const _BottomRow();

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      children: [
        IconButton(
          tooltip: 'Up next',
          icon: const Icon(Icons.format_list_bulleted_rounded),
          onPressed: () => _showQueue(context),
        ),
        // Placeholder: Flutter can't open the AirPlay/Bluetooth picker without
        // an extra plugin, so for now this just tells the user where to find it.
        IconButton(
          tooltip: 'Output device',
          icon: Icon(Platform.isIOS ? Icons.airplay_rounded : Icons.speaker_group_rounded),
          onPressed: () => ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text(Platform.isIOS
                ? 'Pick AirPlay or Bluetooth speakers from Control Center.'
                : 'Pick a Bluetooth or cast device from the media panel in Quick Settings.'),
          )),
        ),
      ],
    );
  }

  /// "Up next" sheet: the queue in play order (shuffled order if shuffle is
  /// on). Tap a song to jump to it.
  void _showQueue(BuildContext context) {
    final player = Player.instance;
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (sheetContext) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.6,
        maxChildSize: 0.95,
        builder: (context, scrollController) => StreamBuilder<SequenceState?>(
          stream: player.audio.sequenceStateStream,
          initialData: player.audio.sequenceState,
          builder: (context, _) {
            final order = player.audio.effectiveIndices;
            final current = player.audio.currentIndex;
            return ListView.builder(
              controller: scrollController,
              itemCount: order.length + 1,
              itemBuilder: (context, i) {
                if (i == 0) {
                  return const Padding(
                    padding: EdgeInsets.fromLTRB(20, 0, 20, 8),
                    child: Text('Up next',
                        style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
                  );
                }
                final index = order[i - 1];
                final track = player.queue[index];
                final isCurrent = index == current;
                return ListTile(
                  leading: Artwork(imagePath: track.artworkPath, size: 40, radius: 4),
                  title: Text(track.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                          color: isCurrent ? AppColors.accent : null,
                          fontWeight: FontWeight.w600)),
                  subtitle: Text(Library.instance.artistName(track.artistId),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(color: AppColors.textSecondary)),
                  trailing: isCurrent
                      ? const Icon(Icons.graphic_eq_rounded, color: AppColors.accent)
                      : null,
                  onTap: () => player.jumpTo(index),
                );
              },
            );
          },
        ),
      ),
    );
  }
}
