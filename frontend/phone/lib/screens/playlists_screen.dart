import 'package:flutter/material.dart';

import '../models/playlist.dart';
import '../models/track.dart';
import '../services/library.dart';
import '../services/player.dart';
import '../services/playlists.dart';
import '../theme.dart';
import '../widgets/artwork.dart';
import '../widgets/common.dart';
import 'now_playing_screen.dart';

class PlaylistsScreen extends StatelessWidget {
  const PlaylistsScreen({super.key});

  Future<void> _create(BuildContext context) async {
    final name = await askForName(context, title: 'New playlist');
    if (name != null) await Playlists.instance.create(name);
  }

  @override
  Widget build(BuildContext context) {
    final playlists = Playlists.instance;
    return SafeArea(
      bottom: false,
      child: ListenableBuilder(
        listenable: Listenable.merge([playlists, Library.instance]),
        builder: (context, _) => Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            PageTitle(
              'Playlists',
              trailing: IconButton(
                tooltip: 'New playlist',
                icon: const Icon(Icons.add_rounded),
                onPressed: () => _create(context),
              ),
            ),
            Expanded(
              child: playlists.items.isEmpty
                  ? Center(
                      child: Column(mainAxisSize: MainAxisSize.min, children: [
                        const Icon(Icons.queue_music_rounded,
                            size: 64, color: AppColors.textSecondary),
                        const SizedBox(height: 12),
                        const Text('No playlists yet',
                            style: TextStyle(color: AppColors.textSecondary)),
                        const SizedBox(height: 16),
                        FilledButton.tonalIcon(
                          onPressed: () => _create(context),
                          icon: const Icon(Icons.add_rounded),
                          label: const Text('New playlist'),
                        ),
                      ]),
                    )
                  : ListView.builder(
                      itemCount: playlists.items.length,
                      itemBuilder: (context, i) {
                        final playlist = playlists.items[i];
                        final tracks = tracksIn(playlist);
                        return ListTile(
                          contentPadding: const EdgeInsets.symmetric(horizontal: 16),
                          leading: Artwork(
                              imagePath: Library.instance.coverFor(tracks)?.artworkPath,
                              size: 56),
                          title: Text(playlist.name,
                              style: const TextStyle(fontWeight: FontWeight.w600)),
                          subtitle: Text(plural(tracks.length, 'song'),
                              style: const TextStyle(color: AppColors.textSecondary)),
                          trailing: const Icon(Icons.chevron_right_rounded),
                          onTap: () => Navigator.of(context).push(MaterialPageRoute(
                            builder: (_) => PlaylistDetailScreen(playlistId: playlist.id),
                          )),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Tracks in a playlist that still exist in the Music folder.
List<Track> tracksIn(Playlist playlist) =>
    playlist.trackIds.map(Library.instance.trackById).nonNulls.toList();

class PlaylistDetailScreen extends StatelessWidget {
  // Playlist objects are replaced on every edit, so look it up by id.
  final String playlistId;
  const PlaylistDetailScreen({super.key, required this.playlistId});

  @override
  Widget build(BuildContext context) {
    final playlists = Playlists.instance;
    final player = Player.instance;

    return ListenableBuilder(
      listenable: Listenable.merge([playlists, Library.instance]),
      builder: (context, _) {
        final playlist = playlists.byId(playlistId);
        if (playlist == null) return const Scaffold();
        final tracks = tracksIn(playlist);
        return Scaffold(
          appBar: AppBar(
            title: Text(playlist.name),
            actions: [
              PopupMenuButton<String>(
                onSelected: (action) async {
                  if (action == 'rename') {
                    final name = await askForName(context,
                        title: 'Rename playlist', initial: playlist.name, action: 'Rename');
                    if (name != null) await playlists.rename(playlist, name);
                  } else if (action == 'delete') {
                    final ok = await showDialog<bool>(
                      context: context,
                      builder: (c) => AlertDialog(
                        title: Text('Delete "${playlist.name}"?'),
                        content: const Text('Your song files are not affected.'),
                        actions: [
                          TextButton(
                              onPressed: () => Navigator.pop(c, false), child: const Text('Cancel')),
                          FilledButton(
                              onPressed: () => Navigator.pop(c, true), child: const Text('Delete')),
                        ],
                      ),
                    );
                    if (ok == true && context.mounted) {
                      Navigator.pop(context);
                      await playlists.delete(playlist);
                    }
                  }
                },
                itemBuilder: (_) => const [
                  PopupMenuItem(value: 'rename', child: Text('Rename')),
                  PopupMenuItem(value: 'delete', child: Text('Delete playlist')),
                ],
              ),
            ],
          ),
          body: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              PlayShuffleButtons(
                onPlay: tracks.isEmpty
                    ? null
                    : () => player.playTracks(tracks, index: 0, shuffle: false),
                onShuffle: tracks.isEmpty ? null : () => player.playTracks(tracks, shuffle: true),
              ),
              Expanded(
                child: tracks.isEmpty
                    ? const Center(
                        child: Padding(
                          padding: EdgeInsets.all(32),
                          child: Text(
                            'Long-press a song in your library, or tap ≡+ on the '
                            'Now Playing screen, to add it here.',
                            textAlign: TextAlign.center,
                            style: TextStyle(color: AppColors.textSecondary),
                          ),
                        ),
                      )
                    : _PlaylistTracks(playlist: playlist, tracks: tracks),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _PlaylistTracks extends StatelessWidget {
  final Playlist playlist;
  final List<Track> tracks;
  const _PlaylistTracks({required this.playlist, required this.tracks});

  @override
  Widget build(BuildContext context) {
    final playlists = Playlists.instance;
    final library = Library.instance;
    return ReorderableListView.builder(
      itemCount: tracks.length,
      buildDefaultDragHandles: false,
      onReorderItem: (oldIndex, newIndex) {
        // Map visible positions back to stored ids (missing files are hidden).
        final from = playlist.trackIds.indexOf(tracks[oldIndex].id);
        final to = playlist.trackIds.indexOf(tracks[newIndex].id);
        playlists.moveTrack(playlist, from, to);
      },
      itemBuilder: (context, i) {
        final track = tracks[i];
        return Dismissible(
          key: ValueKey(track.id),
          direction: DismissDirection.endToStart,
          background: Container(
            color: Colors.red.shade700,
            alignment: Alignment.centerRight,
            padding: const EdgeInsets.only(right: 24),
            child: const Icon(Icons.delete_rounded),
          ),
          onDismissed: (_) => playlists.removeTrack(playlist, track.id),
          child: ListTile(
            contentPadding: const EdgeInsets.only(left: 16, right: 4),
            leading: Artwork(imagePath: track.artworkPath, size: 48),
            title: Text(track.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontWeight: FontWeight.w600)),
            subtitle: Text(library.artistName(track.artistId),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(color: AppColors.textSecondary)),
            trailing: ReorderableDragStartListener(
              index: i,
              child: const Padding(
                padding: EdgeInsets.all(12),
                child: Icon(Icons.drag_handle_rounded, color: AppColors.textSecondary),
              ),
            ),
            onTap: () {
              Player.instance.playTracks(tracks, index: i);
              openNowPlaying(context);
            },
          ),
        );
      },
    );
  }
}
