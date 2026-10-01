import 'package:flutter/material.dart';
import '../models/models.dart';
import '../services/store.dart';
import '../theme/app_theme.dart';
import '../widgets/glass.dart';

class LibraryScreen extends StatelessWidget {
  final Store s;
  const LibraryScreen(this.s, {super.key});

  @override
  Widget build(BuildContext c) => Glass(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('Library', style: Theme.of(c).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w600)),
          const SizedBox(height: 12),
          Expanded(
            child: ListView.separated(
              itemCount: library.length,
              separatorBuilder: (_, __) => Divider(height: 1, color: Colors.white.withOpacity(.12)),
              itemBuilder: (_, i) {
                final song = library[i];
                final on = s.playing == song;
                return ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(song.title, style: TextStyle(fontWeight: on ? FontWeight.w700 : FontWeight.w400)),
                  subtitle: Text('${s.counts[song.path] ?? 0} plays', style: const TextStyle(fontSize: 12)),
                  leading: CircleAvatar(
                    backgroundColor: on ? accent : Colors.white.withOpacity(.15),
                    child: Icon(on && !s.paused ? Icons.graphic_eq : Icons.play_arrow, color: Colors.white),
                  ),
                  trailing: PopupMenuButton<String>(
                    icon: const Icon(Icons.more_vert),
                    onSelected: (v) {
                      if (v == '_sync') {
                        s.addFile(song);
                      } else {
                        s.addToPlaylist(v, song.path);
                      }
                    },
                    itemBuilder: (_) => [
                      const PopupMenuItem(value: '_sync', child: Text('Add to synced library')),
                      for (final name in s.playlists.keys)
                        PopupMenuItem(value: name, child: Text('Add to "$name"')),
                    ],
                  ),
                  onTap: () => s.play(song),
                );
              },
            ),
          ),
        ]),
      );
}
