import 'package:flutter/material.dart';
import '../data/sample_data.dart';
import '../models/playlist.dart';
import '../models/track.dart';
import '../theme/app_theme.dart';

class PlaylistsScreen extends StatefulWidget {
  final ValueChanged<Track> onTrackSelected;
  final Track? nowPlaying;

  const PlaylistsScreen({super.key, required this.onTrackSelected, required this.nowPlaying});

  @override
  State<PlaylistsScreen> createState() => _PlaylistsScreenState();
}

class _PlaylistsScreenState extends State<PlaylistsScreen> {
  late Playlist selected = samplePlaylists.first;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(28, 22, 28, 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Playlists', style: AppText.ui(size: 20, weight: FontWeight.w600)),
              const SizedBox(height: 4),
              Text('${samplePlaylists.length} playlists', style: AppText.ui(size: 12.5, color: AppColors.textSecondary)),
            ],
          ),
        ),
        Divider(height: 1, color: Colors.white.withOpacity(0.08)),
        Expanded(
          child: Row(
            children: [
              SizedBox(
                width: 240,
                child: Container(
                  decoration: BoxDecoration(border: Border(right: BorderSide(color: Colors.white.withOpacity(0.08)))),
                  child: ListView.builder(
                    padding: const EdgeInsets.all(10),
                    itemCount: samplePlaylists.length,
                    itemBuilder: (context, i) {
                      final pl = samplePlaylists[i];
                      final active = pl.id == selected.id;
                      return _PlaylistListItem(
                        playlist: pl,
                        active: active,
                        onTap: () => setState(() => selected = pl),
                      );
                    },
                  ),
                ),
              ),
              Expanded(
                child: AnimatedSwitcher(
                  duration: const Duration(milliseconds: 200),
                  transitionBuilder: (child, anim) => FadeTransition(opacity: anim, child: child),
                  child: KeyedSubtree(
                    key: ValueKey(selected.id),
                    child: _PlaylistDetail(playlist: selected, onTrackSelected: widget.onTrackSelected, nowPlaying: widget.nowPlaying),
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _PlaylistListItem extends StatefulWidget {
  final Playlist playlist;
  final bool active;
  final VoidCallback onTap;

  const _PlaylistListItem({required this.playlist, required this.active, required this.onTap});

  @override
  State<_PlaylistListItem> createState() => _PlaylistListItemState();
}

class _PlaylistListItemState extends State<_PlaylistListItem> {
  bool hovering = false;
  Playlist get playlist => widget.playlist;
  bool get active => widget.active;

  @override
  Widget build(BuildContext context) {
    final bg = active
        ? Colors.white.withOpacity(0.08)
        : hovering
            ? Colors.white.withOpacity(0.08).withOpacity(0.6)
            : Colors.transparent;

    return MouseRegion(
      onEnter: (_) => setState(() => hovering = true),
      onExit: (_) => setState(() => hovering = false),
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          curve: Curves.easeOut,
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: bg,
            border: Border.all(color: active ? Colors.white.withOpacity(0.16) : Colors.transparent),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Row(
            children: [
              AnimatedScale(
                duration: const Duration(milliseconds: 150),
                scale: hovering ? 1.05 : 1,
                child: Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(10),
                    gradient: LinearGradient(
                      colors: [playlist.coverStart, playlist.coverEnd],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 11),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(playlist.name, overflow: TextOverflow.ellipsis, style: AppText.ui(size: 12.5)),
                    const SizedBox(height: 2),
                    Text('${playlist.trackCount} tracks', style: AppText.ui(size: 11, color: AppColors.textTertiary)),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PlaylistDetail extends StatelessWidget {
  final Playlist playlist;
  final ValueChanged<Track> onTrackSelected;
  final Track? nowPlaying;

  const _PlaylistDetail({required this.playlist, required this.onTrackSelected, required this.nowPlaying});

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(28),
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Container(
              width: 96,
              height: 96,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: Colors.white.withOpacity(0.16)),
                gradient: LinearGradient(
                  colors: [playlist.coverStart, playlist.coverEnd],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
              ),
            ),
            const SizedBox(width: 18),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(playlist.name, style: AppText.ui(size: 22, weight: FontWeight.w600)),
                const SizedBox(height: 4),
                Text('${playlist.trackCount} tracks', style: AppText.ui(size: 12.5, color: AppColors.textSecondary)),
              ],
            ),
          ],
        ),
        const SizedBox(height: 22),
        for (int i = 0; i < playlist.tracks.length; i++)
          _DetailTrackRow(
            index: i + 1,
            track: playlist.tracks[i],
            playing: nowPlaying?.id == playlist.tracks[i].id,
            onTap: () => onTrackSelected(playlist.tracks[i]),
          ),
      ],
    );
  }
}

class _DetailTrackRow extends StatefulWidget {
  final int index;
  final dynamic track;
  final bool playing;
  final VoidCallback onTap;

  const _DetailTrackRow({required this.index, required this.track, required this.playing, required this.onTap});

  @override
  State<_DetailTrackRow> createState() => _DetailTrackRowState();
}

class _DetailTrackRowState extends State<_DetailTrackRow> {
  bool hovering = false;

  @override
  Widget build(BuildContext context) {
    final bg = widget.playing
        ? AppColors.accent.withOpacity(0.14)
        : hovering
            ? Colors.white.withOpacity(0.08)
            : null;

    return MouseRegion(
      onEnter: (_) => setState(() => hovering = true),
      onExit: (_) => setState(() => hovering = false),
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 140),
          curve: Curves.easeOut,
          decoration: BoxDecoration(
            color: bg,
            border: Border(bottom: BorderSide(color: Colors.white.withOpacity(0.08))),
          ),
          padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 6),
          child: Row(
            children: [
              SizedBox(width: 24, child: Text('${widget.index}', textAlign: TextAlign.right, style: AppText.mono(size: 11))),
              const SizedBox(width: 10),
              Expanded(child: Text(widget.track.title, style: AppText.ui(size: 13))),
              Text(widget.track.durationLabel, style: AppText.mono(size: 11.5, color: AppColors.textSecondary)),
            ],
          ),
        ),
      ),
    );
  }
}
