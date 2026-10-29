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
      // Listenable.merge = rebuild when EITHER the stats or the library change,
      // so the numbers update live while a song plays.
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
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                child: _WeekChart(days: stats.lastDays(7)),
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
              // ".indexed" gives (position, item) pairs so we can show 1, 2, 3...
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
                      Artwork(imagePath: track.artworkPath, size: 44, name: track.title),
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

/// "This week": minutes listened per day for the last 7 days, as bars.
/// One series, so one color (the accent) and no legend; tap a bar to see that
/// day's time. Days with no listening show only the baseline.
class _WeekChart extends StatefulWidget {
  final List<(DateTime, int)> days; // oldest first, ending today
  const _WeekChart({required this.days});

  @override
  State<_WeekChart> createState() => _WeekChartState();
}

class _WeekChartState extends State<_WeekChart> {
  int? _selected; // index of the tapped bar (null: today)

  static const _weekdays = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
  static const _chartHeight = 120.0;

  @override
  Widget build(BuildContext context) {
    final days = widget.days;
    final total = days.fold(0, (sum, d) => sum + d.$2);
    final most = days.fold(0, (m, d) => d.$2 > m ? d.$2 : m);
    final shown = _selected ?? days.length - 1;
    final (shownDay, shownSeconds) = days[shown];
    final shownLabel = shown == days.length - 1 ? 'Today' : _weekdays[shownDay.weekday - 1];

    return Container(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Text('This week', style: TextStyle(color: AppColors.textSecondary, fontSize: 13)),
        const SizedBox(height: 6),
        Text(formatListenTime(total), style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w800)),
        // The tapped day's value (text color, not the bar color).
        Text('$shownLabel: ${formatListenTime(shownSeconds)}',
            style: const TextStyle(color: AppColors.textSecondary, fontSize: 13)),
        const SizedBox(height: 16),
        Semantics(
          label: 'Minutes listened per day this week: '
              '${days.map((d) => '${_weekdays[d.$1.weekday - 1]} ${d.$2 ~/ 60}').join(', ')}',
          child: SizedBox(
            height: _chartHeight,
            child: Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
              for (final (i, (_, seconds)) in days.indexed)
                Expanded(
                  // The whole column is the tap target, not just the bar.
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: () => setState(() => _selected = i),
                    child: Align(
                      alignment: Alignment.bottomCenter,
                      child: FractionallySizedBox(
                        widthFactor: 0.5,
                        child: Container(
                          height: most == 0 || seconds == 0
                              ? 0
                              : (seconds / most * _chartHeight).clamp(4.0, _chartHeight),
                          decoration: BoxDecoration(
                            color: AppColors.accent.withValues(alpha: i == shown ? 1 : 0.75),
                            // Rounded top, flat on the baseline.
                            borderRadius: const BorderRadius.vertical(top: Radius.circular(4)),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
            ]),
          ),
        ),
        // Baseline.
        Container(height: 1, color: AppColors.divider),
        const SizedBox(height: 6),
        Row(children: [
          for (final (i, (day, _)) in days.indexed)
            Expanded(
              child: Text(
                i == days.length - 1 ? 'Today' : _weekdays[day.weekday - 1],
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: i == shown ? AppColors.textPrimary : AppColors.textSecondary,
                  fontSize: 11,
                  fontWeight: i == shown ? FontWeight.w700 : FontWeight.w400,
                ),
              ),
            ),
        ]),
      ]),
    );
  }
}

/// One of the two big number boxes at the top ("Total plays", "Time listened").
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
