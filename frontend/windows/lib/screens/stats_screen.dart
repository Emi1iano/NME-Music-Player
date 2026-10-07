import 'package:flutter/material.dart';
import '../services/store.dart';
import '../theme/app_theme.dart';
import '../widgets/glass.dart';

class StatsScreen extends StatelessWidget {
  final Store s;
  const StatsScreen(this.s, {super.key});

  Widget _tile(String big, String label) => Expanded(
        child: Glass(
          radius: 20,
          pad: const EdgeInsets.all(14),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(big, style: const TextStyle(fontSize: 28, fontWeight: FontWeight.w700)),
            Text(label, style: const TextStyle(fontSize: 12)),
          ]),
        ),
      );

  @override
  Widget build(BuildContext c) {
    final top = s.top10;
    return Glass(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('Listening', style: Theme.of(c).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w600)),
        const SizedBox(height: 12),
        Row(children: [
          _tile('${s.plays}', 'songs played'),
          const SizedBox(width: 12),
          _tile(s.listened, 'time listened'),
        ]),
        const SizedBox(height: 16),
        const Text('Top 10 most played', style: TextStyle(fontWeight: FontWeight.w600)),
        const SizedBox(height: 6),
        Expanded(
          child: top.isEmpty
              ? const Center(child: Text('Play a song to start your chart.'))
              : ListView(children: [
                  for (var i = 0; i < top.length; i++)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 6),
                      child: Row(children: [
                        SizedBox(
                          width: 28,
                          child: Text('${i + 1}', style: const TextStyle(color: accent, fontWeight: FontWeight.w700)),
                        ),
                        Expanded(child: Text(s.songByPath(top[i].key).title, overflow: TextOverflow.ellipsis)),
                        Text('${top[i].value} plays'),
                      ]),
                    ),
                ]),
        ),
      ]),
    );
  }
}
