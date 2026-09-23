import 'package:flutter/material.dart';

import '../models/track.dart';
import '../services/library.dart';
import '../services/player.dart';
import '../services/stats.dart';
import '../theme.dart';
import '../widgets/common.dart';
import '../widgets/track_tile.dart';
import 'now_playing_screen.dart';
import 'settings_screen.dart';

/// Landing page: settings, refresh, sort, search, Play / Shuffle, song list.
class SongsScreen extends StatefulWidget {
  const SongsScreen({super.key});

  @override
  State<SongsScreen> createState() => _SongsScreenState();
}

class _SongsScreenState extends State<SongsScreen> {
  final _search = TextEditingController(); // holds the search box text
  String _query = '';

  /// Songs whose title, artist or album contains the search text.
  List<Track> _filtered(Library library) {
    final q = _query.trim().toLowerCase();
    if (q.isEmpty) return library.tracks;
    return library.tracks
        .where((t) =>
            t.title.toLowerCase().contains(q) ||
            library.artistName(t.artistId).toLowerCase().contains(q) ||
            library.albumTitle(t.albumId).toLowerCase().contains(q))
        .toList();
  }

  // Controllers must be disposed when the screen goes away to free memory.
  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final library = Library.instance;
    final player = Player.instance;

    // SafeArea keeps content out from under the notch/status bar.
    return SafeArea(
      bottom: false,
      // Rebuilds this whole screen whenever the Library changes
      // (scan finished, sort changed, ...).
      child: ListenableBuilder(
        listenable: library,
        builder: (context, _) {
          final tracks = _filtered(library);
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _TopBar(library: library),
              LibrarySearchBar(
                controller: _search,
                hint: 'Search songs, artists, albums',
                onChanged: (v) => setState(() => _query = v),
              ),
              PlayShuffleButtons(
                onPlay: tracks.isEmpty
                    ? null
                    : () => player.playTracks(tracks, index: 0, shuffle: false),
                onShuffle: tracks.isEmpty ? null : () => player.playTracks(tracks, shuffle: true),
              ),
              Expanded(child: _buildList(context, library, tracks)),
            ],
          );
        },
      ),
    );
  }

  /// The song list, or a spinner / empty message / "No matches" instead.
  Widget _buildList(BuildContext context, Library library, List<Track> tracks) {
    if (library.scanning && library.tracks.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }
    if (library.tracks.isEmpty) return _EmptyLibrary(library: library);
    if (tracks.isEmpty) {
      return const Center(
        child: Text('No matches', style: TextStyle(color: AppColors.textSecondary)),
      );
    }

    final player = Player.instance;
    final showPlays = library.sortMode == SortMode.mostPlayed;
    // RefreshIndicator = pull down to rescan the Music folder.
    return RefreshIndicator(
      onRefresh: library.scan,
      // StreamBuilder rebuilds when the current song changes, so the playing
      // song is highlighted in the list.
      child: StreamBuilder<Track?>(
        stream: player.currentTrackStream,
        initialData: player.currentTrack,
        // ListView.separated only builds the rows that are on screen, so it
        // stays fast even with thousands of songs.
        builder: (context, snapshot) => ListView.separated(
          padding: const EdgeInsets.only(bottom: 8),
          itemCount: tracks.length,
          separatorBuilder: (_, _) => const Divider(height: 1, indent: 80, endIndent: 16),
          itemBuilder: (context, i) {
            final track = tracks[i];
            return TrackTile(
              track: track,
              isCurrent: snapshot.data?.id == track.id,
              trailing: showPlays
                  ? Text(plural(Stats.instance.of(track.id).playCount, 'play'),
                      style: const TextStyle(color: AppColors.textSecondary))
                  : null,
              // Tap: play the list starting at this song and open Now Playing.
              onTap: () {
                player.playTracks(tracks, index: i);
                openNowPlaying(context);
              },
              // Long-press: add to a playlist.
              onLongPress: () => showAddToPlaylist(context, track),
            );
          },
        ),
      ),
    );
  }
}

/// Settings button on the left; refresh and sort buttons on the right.
class _TopBar extends StatelessWidget {
  final Library library;
  const _TopBar({required this.library});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: Row(
        children: [
          IconButton(
            tooltip: 'Settings',
            icon: const Icon(Icons.settings_rounded),
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const SettingsScreen()),
            ),
          ),
          const Spacer(),
          IconButton(
            tooltip: 'Rescan music folder',
            icon: library.scanning
                ? const SizedBox(
                    width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.refresh_rounded),
            onPressed: library.scanning ? null : library.scan,
          ),
          PopupMenuButton<SortMode>(
            tooltip: 'Sort',
            icon: const Icon(Icons.swap_vert_rounded),
            initialValue: library.sortMode,
            onSelected: library.setSortMode,
            itemBuilder: (_) => [
              for (final mode in SortMode.values)
                CheckedPopupMenuItem(
                  value: mode,
                  checked: mode == library.sortMode,
                  child: Text(mode.label),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Shown when the Music folder has no songs yet: explains how to add some.
class _EmptyLibrary extends StatelessWidget {
  final Library library;
  const _EmptyLibrary({required this.library});

  @override
  Widget build(BuildContext context) {
    return RefreshIndicator(
      onRefresh: library.scan,
      child: ListView(
        padding: const EdgeInsets.all(32),
        children: [
          const SizedBox(height: 40),
          const Icon(Icons.library_music_rounded, size: 64, color: AppColors.textSecondary),
          const SizedBox(height: 16),
          const Text('No music yet',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700)),
          const SizedBox(height: 8),
          Text(
            howToAddMusic(),
            textAlign: TextAlign.center,
            style: const TextStyle(color: AppColors.textSecondary, height: 1.4),
          ),
          const SizedBox(height: 24),
          Center(
            child: FilledButton.tonalIcon(
              onPressed: library.scan,
              icon: const Icon(Icons.refresh_rounded),
              label: const Text('Scan again'),
            ),
          ),
        ],
      ),
    );
  }
}
