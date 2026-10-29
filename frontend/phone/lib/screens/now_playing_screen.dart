import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:just_audio/just_audio.dart';

import '../models/track.dart';
import '../services/appearance.dart';
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
      body: _Backdrop(
        child: SafeArea(
        // Swipe down (quickly) anywhere to close, like the ✕ button.
        child: GestureDetector(
          behavior: HitTestBehavior.translucent,
          onVerticalDragEnd: (details) {
            if ((details.primaryVelocity ?? 0) > 700) Navigator.pop(context);
          },
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
                  // Same Hero tag as the mini player's cover, so the small
                  // cover grows into this one when Now Playing opens.
                  CoverHero(
                    child: Artwork(
                        imagePath: track?.artworkPath, size: artSize, radius: 12, name: track?.title),
                  ),
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
      ),
      ),
    );
  }
}

/// Hero tag shared by the mini player's cover and Now Playing's big cover.
const nowPlayingArtTag = 'now-playing-art';

/// Wraps a cover in the shared Hero (so it animates between the mini player
/// and Now Playing), unless "Cover animation" is off in Settings.
class CoverHero extends StatelessWidget {
  final Widget child;
  const CoverHero({super.key, required this.child});

  @override
  Widget build(BuildContext context) => ListenableBuilder(
        listenable: Appearance.instance,
        builder: (context, _) => Appearance.instance.coverAnimation
            ? Hero(tag: nowPlayingArtTag, child: child)
            : child,
      );
}

/// Now Playing's background: the main color of the song's cover (or of its
/// placeholder tile), fading into the app's background. Changes smoothly
/// when the song changes.
class _Backdrop extends StatelessWidget {
  final Widget child;
  const _Backdrop({required this.child});

  @override
  Widget build(BuildContext context) {
    final player = Player.instance;
    return ListenableBuilder(
      listenable: Appearance.instance,
      builder: (context, _) => Appearance.instance.coverColors
          ? _tinted(player)
          : ColoredBox(color: AppColors.background, child: child), // "Cover colors" off
    );
  }

  Widget _tinted(Player player) {
    return StreamBuilder<Track?>(
      stream: player.currentTrackStream,
      initialData: player.currentTrack,
      builder: (context, snap) {
        final track = snap.data;
        return FutureBuilder<Color>(
          // Keyed by song so the previous color isn't reused for a new song.
          key: ValueKey(track?.id),
          future: track == null
              ? Future.value(AppColors.surfaceHigh)
              : coverColor(imagePath: track.artworkPath, name: track.title),
          builder: (context, colorSnap) {
            final color = _tone(colorSnap.data ?? AppColors.surfaceHigh);
            return TweenAnimationBuilder<Color?>(
              tween: ColorTween(end: color),
              duration: const Duration(milliseconds: 600),
              builder: (context, c, _) => DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [c ?? color, AppColors.background],
                    stops: const [0.0, 0.85],
                  ),
                ),
                child: child,
              ),
            );
          },
        );
      },
    );
  }

  /// A darker, calmer version of [c], so white text stays readable on it.
  static Color _tone(Color c) {
    final hsl = HSLColor.fromColor(c);
    return hsl
        .withLightness(hsl.lightness.clamp(0.18, 0.30))
        .withSaturation(hsl.saturation.clamp(0.0, 0.55))
        .toColor();
  }
}

/// Text that slowly scrolls sideways when it's too long to fit (pausing at
/// the start), instead of being cut off with "…".
class _Marquee extends StatefulWidget {
  final String text;
  final TextStyle style;
  const _Marquee({required this.text, required this.style});

  @override
  State<_Marquee> createState() => _MarqueeState();
}

class _MarqueeState extends State<_Marquee> with SingleTickerProviderStateMixin {
  late final _controller = AnimationController(vsync: this);
  static const _gap = 48.0;           // space between the end and the repeat
  static const _speed = 30.0;         // pixels per second
  static const _pause = Duration(seconds: 2);
  Timer? _restart;
  double _scroll = 0;                 // how far one loop scrolls (0: fits, no scrolling)

  @override
  void didUpdateWidget(_Marquee old) {
    super.didUpdateWidget(old);
    if (old.text != widget.text) {
      _restart?.cancel();
      _controller.stop();
      _controller.value = 0;
      _scroll = 0;
    }
  }

  @override
  void dispose() {
    _restart?.cancel();
    _controller.dispose();
    super.dispose();
  }

  void _start(double scroll) {
    if (scroll == _scroll) return;
    _scroll = scroll;
    _restart?.cancel();
    _controller.stop();
    _controller.value = 0;
    if (scroll <= 0) return;
    _controller.duration = Duration(milliseconds: (scroll / _speed * 1000).round());
    void loop() {
      _restart = Timer(_pause, () {
        if (!mounted) return;
        _controller.forward(from: 0).whenComplete(() {
          if (mounted) loop();
        });
      });
    }
    loop();
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, constraints) {
      final painter = TextPainter(
        text: TextSpan(text: widget.text, style: widget.style),
        maxLines: 1,
        textDirection: TextDirection.ltr,
      )..layout();
      final textWidth = painter.width;
      final fits = textWidth <= constraints.maxWidth;
      // Start/stop after this frame (can't change animations mid-build).
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _start(fits ? 0 : textWidth + _gap);
      });
      final text = Text(widget.text, style: widget.style, maxLines: 1, softWrap: false);
      if (fits) return text;
      return SizedBox(
        height: painter.height,
        child: ClipRect(
          child: AnimatedBuilder(
            animation: _controller,
            builder: (context, child) => OverflowBox(
              alignment: Alignment.centerLeft,
              maxWidth: double.infinity,
              child: Transform.translate(
                offset: Offset(-_controller.value * (textWidth + _gap), 0),
                child: child,
              ),
            ),
            // The text twice in a row, so it wraps around seamlessly.
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              text,
              const SizedBox(width: _gap),
              text,
            ]),
          ),
        ),
      );
    });
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
              _Marquee(
                  text: track?.title ?? 'Not playing',
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
            leading: const Icon(Icons.drive_file_rename_outline_rounded),
            title: const Text('Rename file'),
            onTap: () {
              Navigator.pop(sheetContext);
              renameSongFile(context, track);
            },
          ),
          ListTile(
            leading: const Icon(Icons.bedtime_outlined),
            title: const Text('Sleep timer'),
            subtitle: Text(_sleepTimerText(),
                style: const TextStyle(color: AppColors.textSecondary)),
            onTap: () {
              Navigator.pop(sheetContext);
              showSleepTimer(context);
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
          ListTile(
            leading: const Icon(Icons.delete_outline_rounded, color: Colors.redAccent),
            title: const Text('Delete song', style: TextStyle(color: Colors.redAccent)),
            onTap: () {
              Navigator.pop(sheetContext);
              deleteSong(context, track);
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
        // Moon: the sleep timer. Lit up (with the minutes left) when it's on.
        ListenableBuilder(
          listenable: Listenable.merge([Player.instance.sleepAt, Player.instance.sleepAfterSong]),
          builder: (context, _) {
            final on = Player.instance.sleepAt.value != null ||
                Player.instance.sleepAfterSong.value;
            return TextButton.icon(
              onPressed: () => showSleepTimer(context),
              icon: Icon(on ? Icons.bedtime_rounded : Icons.bedtime_outlined,
                  color: on ? AppColors.accent : AppColors.textPrimary),
              label: on
                  ? Text(_sleepTimerText(short: true),
                      style: TextStyle(color: AppColors.accent))
                  : const SizedBox.shrink(),
            );
          },
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
  /// on). Tap a song to jump to it, drag the handle to reorder (shuffle off),
  /// swipe left to remove it from the queue.
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
            final shuffled = player.audio.shuffleModeEnabled;
            final order = player.audio.effectiveIndices;
            final current = player.audio.currentIndex;
            return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  const Text('Up next',
                      style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
                  Text(
                    shuffled
                        ? 'Swipe left to remove. Turn shuffle off to reorder.'
                        : 'Drag ≡ to reorder, swipe left to remove.',
                    style: const TextStyle(color: AppColors.textSecondary, fontSize: 12),
                  ),
                ]),
              ),
              Expanded(
                child: ReorderableListView.builder(
                  scrollController: scrollController,
                  buildDefaultDragHandles: false,
                  itemCount: order.length,
                  onReorderItem: (from, to) => player.moveInQueue(order[from], order[to]),
                  itemBuilder: (context, i) {
                    final index = order[i];
                    final track = player.queue[index];
                    final isCurrent = index == current;
                    return Dismissible(
                      // Position + song: a song can be in the queue twice.
                      key: ValueKey('$index:${track.id}'),
                      direction: DismissDirection.endToStart,
                      background: Container(
                        color: Colors.redAccent.withValues(alpha: 0.25),
                        alignment: Alignment.centerRight,
                        padding: const EdgeInsets.only(right: 24),
                        child: const Icon(Icons.remove_circle_outline_rounded),
                      ),
                      onDismissed: (_) => player.removeFromQueue(index),
                      child: _queueTile(player, track, isCurrent, index, i, shuffled),
                    );
                  },
                ),
              ),
            ]);
          },
        ),
      ),
    );
  }

  /// One row of the "Up next" sheet.
  Widget _queueTile(
      Player player, Track track, bool isCurrent, int index, int position, bool shuffled) {
                return ListTile(
                  leading: Artwork(imagePath: track.artworkPath, size: 40, radius: 4, name: track.title),
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
                  trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                    if (isCurrent) Icon(Icons.graphic_eq_rounded, color: AppColors.accent),
                    if (!shuffled)
                      ReorderableDragStartListener(
                        index: position,
                        child: const Padding(
                          padding: EdgeInsets.all(8),
                          child: Icon(Icons.drag_handle_rounded, color: AppColors.textSecondary),
                        ),
                      ),
                  ]),
                  onTap: () => player.jumpTo(index),
                );
  }
}

/// "Sleep in 23 min" / "At the end of this song" / "Off" (or "23 min" /
/// "End of song" for the small label next to the moon).
String _sleepTimerText({bool short = false}) {
  final player = Player.instance;
  if (player.sleepAfterSong.value) return short ? 'End of song' : 'At the end of this song';
  final at = player.sleepAt.value;
  if (at == null) return 'Off';
  final minutes = (at.difference(DateTime.now()).inSeconds / 60).ceil().clamp(1, 999);
  return short ? '$minutes min' : 'Stops in $minutes min';
}

/// Sleep timer choices: pause after 15/30/45/60 minutes or at the end of the
/// current song.
void showSleepTimer(BuildContext context) {
  final player = Player.instance;
  final on = player.sleepAt.value != null || player.sleepAfterSong.value;
  void pick(BuildContext sheetContext, Duration? duration, String label) {
    Navigator.pop(sheetContext);
    player.setSleepTimer(duration);
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Sleep timer: $label')));
  }

  showModalBottomSheet<void>(
    context: context,
    builder: (sheetContext) => SafeArea(
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
          child: Row(children: [
            const Expanded(
              child: Text('Sleep timer',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
            ),
            Text(_sleepTimerText(), style: const TextStyle(color: AppColors.textSecondary)),
          ]),
        ),
        for (final minutes in const [15, 30, 45, 60])
          ListTile(
            leading: const Icon(Icons.timer_outlined),
            title: Text('$minutes minutes'),
            onTap: () => pick(sheetContext, Duration(minutes: minutes), '$minutes minutes'),
          ),
        ListTile(
          leading: const Icon(Icons.music_off_outlined),
          title: const Text('End of this song'),
          onTap: () => pick(sheetContext, null, 'end of this song'),
        ),
        if (on)
          ListTile(
            leading: const Icon(Icons.close_rounded),
            title: const Text('Turn off'),
            onTap: () {
              Navigator.pop(sheetContext);
              player.cancelSleepTimer();
            },
          ),
      ]),
    ),
  );
}
