import 'dart:math';

import 'package:flutter/material.dart';

import '../models/album.dart';
import '../services/library.dart';
import '../services/player.dart';
import '../theme.dart';
import '../widgets/artwork.dart';
import '../widgets/common.dart';
import 'collection_screen.dart';

/// Grid of albums with cover art, name and "artist • year".
class AlbumsScreen extends StatefulWidget {
  const AlbumsScreen({super.key});

  @override
  State<AlbumsScreen> createState() => _AlbumsScreenState();
}

class _AlbumsScreenState extends State<AlbumsScreen> {
  final _search = TextEditingController();
  String _query = '';

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final library = Library.instance;
    return SafeArea(
      bottom: false,
      child: ListenableBuilder(
        listenable: library,
        builder: (context, _) {
          final q = _query.trim().toLowerCase();
          final albums = library.albums
              .where((a) =>
                  q.isEmpty ||
                  a.title.toLowerCase().contains(q) ||
                  library.artistName(a.artistId).toLowerCase().contains(q))
              .toList();
          // Every song from the visible albums, for the Play / Shuffle buttons.
          final allTracks = [for (final a in albums) ...library.tracksOf(a)];

          // CustomScrollView + "slivers" lets the title, search bar, buttons
          // and grid all scroll together as one page.
          return CustomScrollView(slivers: [
            const SliverToBoxAdapter(child: PageTitle('Albums')),
            SliverToBoxAdapter(
              child: LibrarySearchBar(
                controller: _search,
                hint: 'Search albums',
                onChanged: (v) => setState(() => _query = v),
              ),
            ),
            SliverToBoxAdapter(
              child: PlayShuffleButtons(
                onPlay: allTracks.isEmpty
                    ? null
                    : () => Player.instance.playTracks(allTracks, index: 0, shuffle: false),
                onShuffle: allTracks.isEmpty
                    ? null
                    : () => Player.instance.playTracks(allTracks, shuffle: true),
              ),
            ),
            if (albums.isEmpty)
              SliverFillRemaining(
                hasScrollBody: false,
                child: Center(
                  child: Text(library.albums.isEmpty ? 'No albums yet' : 'No matches',
                      style: const TextStyle(color: AppColors.textSecondary)),
                ),
              )
            else
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                sliver: SliverGrid.builder(
                  // Cards are at most 220px wide: 2 columns on a phone,
                  // more on a tablet, automatically.
                  gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                    maxCrossAxisExtent: 220,
                    mainAxisSpacing: 20,
                    crossAxisSpacing: 16,
                    childAspectRatio: 0.74,
                  ),
                  itemCount: albums.length,
                  itemBuilder: (context, i) => _AlbumCard(album: albums[i]),
                ),
              ),
          ]);
        },
      ),
    );
  }
}

// "Artist  •  2021" (year left out when unknown, i.e. releaseYear == 0).
String _albumLine(Album album) {
  final artist = Library.instance.artistName(album.artistId);
  return album.releaseYear > 0 ? '$artist  •  ${album.releaseYear}' : artist;
}

/// One square in the grid: cover, album name, artist • year.
class _AlbumCard extends StatelessWidget {
  final Album album;
  const _AlbumCard({required this.album});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => openAlbum(context, album),
      // LayoutBuilder tells us how wide the grid cell is, so the cover can
      // be a perfect square that fills it.
      child: LayoutBuilder(
        builder: (context, constraints) => Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Artwork(imagePath: album.artworkUrl, size: constraints.maxWidth, radius: 10),
            const SizedBox(height: 8),
            Text(album.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
            Text(_albumLine(album),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(color: AppColors.textSecondary, fontSize: 14)),
          ],
        ),
      ),
    );
  }
}

/// Opens an album's page with its songs in track order.
void openAlbum(BuildContext context, Album album) {
  final tracks = Library.instance.tracksOf(album);
  final totalSeconds = tracks.fold(0, (sum, t) => sum + t.durationSeconds);
  Navigator.of(context).push(MaterialPageRoute(
    builder: (_) => CollectionScreen(
      title: album.title,
      subtitle: [
        _albumLine(album),
        plural(tracks.length, 'song'),
        if (totalSeconds > 0) '${max(1, totalSeconds ~/ 60)} min',
      ].join('  •  '),
      imagePath: album.artworkUrl,
      tracks: tracks,
      showTrackNumbers: true,
    ),
  ));
}
