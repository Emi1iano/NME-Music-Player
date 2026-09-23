import 'package:flutter/material.dart';
import '../data/sample_data.dart';
import '../models/track.dart';
import '../theme/app_theme.dart';

class LibraryScreen extends StatelessWidget {
  final ValueChanged<Track> onTrackSelected;
  final Track? nowPlaying;

  const LibraryScreen({super.key, required this.onTrackSelected, required this.nowPlaying});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(28, 22, 28, 16),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Library', style: AppText.ui(size: 20, weight: FontWeight.w600)),
                  const SizedBox(height: 4),
                  Text(
                    '${sampleTracks.length} tracks · ${sampleTracks.where((t) => t.downloadedOffline).length} downloaded for offline',
                    style: AppText.ui(size: 12.5, color: AppColors.textSecondary),
                  ),
                ],
              ),
              Container(
                width: 220,
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.04),
                  border: Border.all(color: Colors.white.withOpacity(0.16)),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: TextField(
                  style: AppText.ui(size: 12.5),
                  decoration: InputDecoration(
                    border: InputBorder.none,
                    hintText: 'Search library',
                    hintStyle: AppText.ui(size: 12.5, color: AppColors.textTertiary),
                    isDense: true,
                  ),
                ),
              ),
            ],
          ),
        ),
        Divider(height: 1, color: Colors.white.withOpacity(0.08)),
        Expanded(
          child: ListView.builder(
            padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 6),
            itemCount: sampleTracks.length,
            itemBuilder: (context, i) {
              final track = sampleTracks[i];
              final playing = nowPlaying?.id == track.id;
              return _TrackRow(index: i + 1, track: track, playing: playing, onTap: () => onTrackSelected(track));
            },
          ),
        ),
      ],
    );
  }
}

class _TrackRow extends StatefulWidget {
  final int index;
  final Track track;
  final bool playing;
  final VoidCallback onTap;

  const _TrackRow({required this.index, required this.track, required this.playing, required this.onTap});

  @override
  State<_TrackRow> createState() => _TrackRowState();
}

class _TrackRowState extends State<_TrackRow> {
  bool hovering = false;
  int get index => widget.index;
  Track get track => widget.track;
  bool get playing => widget.playing;

  @override
  Widget build(BuildContext context) {
    final bg = playing
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
            SizedBox(width: 24, child: Text('$index', textAlign: TextAlign.right, style: AppText.mono(size: 11))),
            const SizedBox(width: 10),
            Container(
              width: 32,
              height: 32,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.white.withOpacity(0.16)),
                gradient: const LinearGradient(
                  colors: [Color(0xFF3A352C), Color(0xFF201D18)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              flex: 3,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(track.title, overflow: TextOverflow.ellipsis, style: AppText.ui(size: 13)),
                  const SizedBox(height: 2),
                  Text(track.artist, overflow: TextOverflow.ellipsis, style: AppText.ui(size: 11.5, color: AppColors.textSecondary)),
                ],
              ),
            ),
            Expanded(
              flex: 2,
              child: Text(track.album, overflow: TextOverflow.ellipsis, style: AppText.ui(size: 13, color: AppColors.textSecondary)),
            ),
            Text(track.durationLabel, style: AppText.mono(size: 11.5, color: AppColors.textSecondary)),
            const SizedBox(width: 14),
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 200),
              transitionBuilder: (child, anim) => ScaleTransition(scale: anim, child: child),
              child: Icon(
                track.downloadedOffline ? Icons.check_circle_outline : Icons.file_download_outlined,
                key: ValueKey(track.downloadedOffline),
                size: 14,
                color: track.downloadedOffline ? AppColors.vu : AppColors.textTertiary,
              ),
            ),
          ],
        ),
      ),
      ),
    );
  }
}
