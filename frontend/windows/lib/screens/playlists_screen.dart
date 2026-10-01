import 'package:flutter/material.dart';
import '../models/models.dart';
import '../services/store.dart';
import '../theme/app_theme.dart';
import '../widgets/glass.dart';

class PlaylistsScreen extends StatefulWidget {
  final Store s;
  const PlaylistsScreen(this.s, {super.key});
  @override
  State<PlaylistsScreen> createState() => _PlaylistsScreenState();
}

class _PlaylistsScreenState extends State<PlaylistsScreen> {
  String? sel;

  Future<void> _create() async {
    final ctl = TextEditingController();
    final name = await showDialog<String>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('New playlist'),
        content: TextField(
          controller: ctl,
          autofocus: true,
          decoration: const InputDecoration(hintText: 'Playlist name'),
          onSubmitted: (v) => Navigator.pop(c, v),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(c, ctl.text), child: const Text('Create')),
        ],
      ),
    );
    if (name != null && name.trim().isNotEmpty) {
      widget.s.createPlaylist(name.trim());
      setState(() => sel = name.trim());
    }
  }

  Future<void> _pickSongs(String pl) => showDialog(
        context: context,
        builder: (c) => StatefulBuilder(
          builder: (c, set) => AlertDialog(
            title: Text('Songs in "$pl"'),
            content: SizedBox(
              width: 360,
              height: 400,
              child: ListView(children: [
                for (final song in library)
                  CheckboxListTile(
                    value: widget.s.playlists[pl]?.contains(song.path) ?? false,
                    title: Text(song.title),
                    onChanged: (v) {
                      v == true
                          ? widget.s.addToPlaylist(pl, song.path)
                          : widget.s.removeFromPlaylist(pl, song.path);
                      set(() {});
                    },
                  ),
              ]),
            ),
            actions: [TextButton(onPressed: () => Navigator.pop(c), child: const Text('Done'))],
          ),
        ),
      );

  @override
  Widget build(BuildContext c) {
    final s = widget.s;
    final names = s.playlists.keys.toList();
    final cur = names.contains(sel) ? sel : (names.isEmpty ? null : names.first);
    final tracks = cur == null ? <String>[] : s.playlists[cur]!;

    return Glass(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('Playlists', style: Theme.of(c).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w600)),
        const SizedBox(height: 12),
        Wrap(spacing: 8, runSpacing: 8, children: [
          for (final n in names)
            ChoiceChip(
              label: Text(n),
              selected: n == cur,
              selectedColor: accent,
              onSelected: (_) => setState(() => sel = n),
            ),
          ActionChip(avatar: const Icon(Icons.add, size: 18), label: const Text('New'), onPressed: _create),
        ]),
        const SizedBox(height: 14),
        if (cur == null)
          const Expanded(child: Center(child: Text('Create a playlist to get started.')))
        else ...[
          Row(children: [
            FilledButton.icon(
              style: FilledButton.styleFrom(backgroundColor: accent, foregroundColor: Colors.white),
              onPressed: tracks.isEmpty ? null : () => s.playPlaylist(cur),
              icon: const Icon(Icons.play_arrow),
              label: const Text('Play'),
            ),
            const SizedBox(width: 10),
            OutlinedButton(onPressed: () => _pickSongs(cur), child: const Text('Add songs')),
            const Spacer(),
            IconButton(
              tooltip: 'Delete playlist',
              icon: const Icon(Icons.delete_outline),
              onPressed: () => s.deletePlaylist(cur),
            ),
          ]),
          const SizedBox(height: 8),
          Expanded(
            child: tracks.isEmpty
                ? const Center(child: Text('No songs yet. Use "Add songs".'))
                : ListView(children: [
                    for (final p in tracks)
                      ListTile(
                        contentPadding: EdgeInsets.zero,
                        title: Text(s.songByPath(p).title),
                        onTap: () => s.play(s.songByPath(p)),
                        trailing: IconButton(
                          icon: const Icon(Icons.close),
                          onPressed: () => s.removeFromPlaylist(cur, p),
                        ),
                      ),
                  ]),
          ),
        ],
      ]),
    );
  }
}
