import 'package:flutter/material.dart';

import '../services/library.dart';
import '../services/stats.dart';
import '../theme.dart';
import '../widgets/artwork.dart';
import '../widgets/common.dart';

/// Totals plus the most-played songs, from PlaybackStats.
class StatsScreen extends StatelessWidget {
  const StatsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final stats = Stats.instance;
    final library = Library.instance;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Listening stats'),
        actions: [
          IconButton(
            tooltip: 'Reset stats',
            icon: const Icon(Icons.restart_alt_rounded),
            onPressed: () async {
              final ok = await showDialog<bool>(
                context: context,
                builder: (c) => AlertDialog(
                  title: const Text('Reset listening stats?'),
                  content: const Text('Play counts and listening time go back to zero.'),
                  actions: [
                    TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Cancel')),
                    FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('Reset')),
                  ],
                ),
              );
              if (ok == true) await stats.reset();
            },
          ),
        ],
      ),
      body: ListenableBuilder(
        listenable: Listenable.merge([stats, library]),
        builder: (context, _) {
          // Only show songs that are still in the Music folder.
          final top = stats.top(50).where((s) => library.trackById(s.trackId) != null).toList();
          return ListView(
            padding: const EdgeInsets.only(bottom: 16),
            children: [
              Padding(
                padding: const EdgeInsets.all(16),
                child: Row(children: [
                  Expanded(child: _StatCard(label: 'Total plays', value: '${stats.totalPlays}')),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _StatCard(
                        label: 'Time listened', value: formatListenTime(stats.totalSeconds)),
                  ),
                ]),
              ),
              const Padding(
                padding: EdgeInsets.fromLTRB(20, 8, 20, 4),
                child: Text('Most played',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
              ),
              if (top.isEmpty)
                const Padding(
                  padding: EdgeInsets.all(32),
                  child: Text(
                    'Nothing yet. A play counts after 30 seconds of listening '
                    '(or half of a short song).',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: AppColors.textSecondary),
                  ),
                ),
              for (final (i, s) in top.indexed)
                Builder(builder: (context) {
                  final track = library.trackById(s.trackId)!;
                  return ListTile(
                    leading: Row(mainAxisSize: MainAxisSize.min, children: [
                      SizedBox(
                        width: 28,
                        child: Text('${i + 1}',
                            textAlign: TextAlign.center,
                            style: const TextStyle(
                                color: AppColors.textSecondary, fontWeight: FontWeight.w700)),
                      ),
                      const SizedBox(width: 8),
                      Artwork(imagePath: track.artworkPath, size: 44),
                    ]),
                    title: Text(track.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontWeight: FontWeight.w600)),
                    subtitle: Text(library.artistName(track.artistId),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(color: AppColors.textSecondary)),
                    trailing: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Text(plural(s.playCount, 'play'),
                            style: const TextStyle(fontWeight: FontWeight.w600)),
                        Text(formatListenTime(s.playtimeSeconds),
                            style: const TextStyle(color: AppColors.textSecondary, fontSize: 12)),
                      ],
                    ),
                  );
                }),
            ],
          );
        },
      ),
    );
  }
}

class _StatCard extends StatelessWidget {
  final String label;
  final String value;
  const _StatCard({required this.label, required this.value});

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(label, style: const TextStyle(color: AppColors.textSecondary, fontSize: 13)),
          const SizedBox(height: 6),
          Text(value, style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w800)),
        ]),
      );
}
