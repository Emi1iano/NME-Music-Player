import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import '../models/models.dart';
import '../services/store.dart';
import '../services/sync_api.dart';
import '../theme/app_theme.dart';
import '../widgets/glass.dart';

class LibraryScreen extends StatelessWidget {
  final Store s;
  const LibraryScreen(this.s, {super.key});

  Future<void> _confirmDelete(BuildContext c, Song song) async {
    final ok = await showDialog<bool>(
      context: c,
      builder: (d) => AlertDialog(
        title: const Text('Delete song?'),
        content: Text('"${song.title}" will be deleted from your music folder and removed from your '
            'playlists and stats. Sync won\'t download it again unless you choose it under '
            '"Get deleted songs back".'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(d, false), child: const Text('Cancel')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.redAccent, foregroundColor: Colors.white),
            onPressed: () => Navigator.pop(d, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (ok == true) s.deleteSong(song);
  }

  /// Lets the user pick song files (or a whole folder) and copies them into
  /// the music folder.
  Future<void> _import(BuildContext c, {required bool wholeFolder}) async {
    final messenger = ScaffoldMessenger.of(c);
    void say(String m) => messenger.showSnackBar(SnackBar(content: Text(m)));
    if (!MusicSync.supported) {
      say('Importing music is only available in the Windows app');
      return;
    }
    final List<String> paths;
    if (wholeFolder) {
      final dir = await FilePicker.getDirectoryPath(dialogTitle: 'Choose a folder with music');
      if (dir == null) return;
      paths = await MusicSync.audioFilesIn(dir);
      if (paths.isEmpty) {
        say('No audio files found in that folder');
        return;
      }
    } else {
      final picked = await FilePicker.pickFiles(
        dialogTitle: 'Choose songs to import',
        type: FileType.custom,
        allowedExtensions: MusicSync.audioExtensions,
      );
      paths = [for (final f in picked) if (f.path != null) f.path!];
      if (paths.isEmpty) return;
    }
    say(await s.importSongs(paths));
  }

  @override
  Widget build(BuildContext c) => Glass(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Expanded(
              child: Text('Library', style: Theme.of(c).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w600)),
            ),
            OutlinedButton.icon(
              onPressed: s.importing ? null : () => _import(c, wholeFolder: true),
              icon: const Icon(Icons.folder_open, size: 18),
              label: const Text('Import folder'),
            ),
            const SizedBox(width: 8),
            FilledButton.icon(
              onPressed: s.importing ? null : () => _import(c, wholeFolder: false),
              icon: const Icon(Icons.library_add, size: 18),
              label: Text(s.importing ? 'Importing...' : 'Import music'),
            ),
          ]),
          const SizedBox(height: 12),
          Expanded(
            child: s.library.isEmpty
                ? Center(
                    child: Text('No songs yet. Use "Import music" above,\nput audio files in ${s.folder},\nor sync with another device.',
                        textAlign: TextAlign.center),
                  )
                : ListView.separated(
              itemCount: s.library.length,
              separatorBuilder: (_, __) => Divider(height: 1, color: Colors.white.withOpacity(.12)),
              itemBuilder: (_, i) {
                final song = s.library[i];
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
                      if (v == '_delete') {
                        _confirmDelete(c, song);
                      } else {
                        s.addToPlaylist(v, song.path);
                      }
                    },
                    itemBuilder: (_) => [
                      for (final name in s.playlists.keys)
                        PopupMenuItem(value: name, child: Text('Add to "$name"')),
                      if (s.playlists.isNotEmpty) const PopupMenuDivider(),
                      const PopupMenuItem(
                        value: '_delete',
                        child: Text('Delete song', style: TextStyle(color: Colors.redAccent)),
                      ),
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
