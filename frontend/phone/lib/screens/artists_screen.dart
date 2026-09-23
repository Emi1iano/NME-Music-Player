import 'package:flutter/material.dart';

import '../models/artist.dart';
import '../services/library.dart';
import '../theme.dart';
import '../widgets/artwork.dart';
import '../widgets/common.dart';
import 'collection_screen.dart';

/// List of artists with a round picture and a chevron.
class ArtistsScreen extends StatefulWidget {
  const ArtistsScreen({super.key});

  @override
  State<ArtistsScreen> createState() => _ArtistsScreenState();
}

class _ArtistsScreenState extends State<ArtistsScreen> {
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
          final artists = library.artists
              .where((a) => q.isEmpty || a.name.toLowerCase().contains(q))
              .toList();

          return CustomScrollView(slivers: [
            const SliverToBoxAdapter(child: PageTitle('Artists')),
            SliverToBoxAdapter(
              child: LibrarySearchBar(
                controller: _search,
                hint: 'Search artists',
                onChanged: (v) => setState(() => _query = v),
              ),
            ),
            if (artists.isEmpty)
              SliverFillRemaining(
                hasScrollBody: false,
                child: Center(
                  child: Text(library.artists.isEmpty ? 'No artists yet' : 'No matches',
                      style: const TextStyle(color: AppColors.textSecondary)),
                ),
              )
            else
              SliverList.separated(
                itemCount: artists.length,
                separatorBuilder: (_, _) => const Divider(height: 1, indent: 92),
                itemBuilder: (context, i) => _ArtistTile(artist: artists[i]),
              ),
          ]);
        },
      ),
    );
  }
}

/// Artist.imageUrl if set, otherwise a cover from one of their songs.
String? _artistImage(Artist artist) {
  final library = Library.instance;
  return artist.imageUrl ?? library.coverFor(library.tracksBy(artist))?.artworkPath;
}

/// One row: round picture, name, and a › arrow.
class _ArtistTile extends StatelessWidget {
  final Artist artist;
  const _ArtistTile({required this.artist});

  @override
  Widget build(BuildContext context) {
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      leading: Artwork(imagePath: _artistImage(artist), size: 60, radius: 30),
      title: Text(artist.name,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w500)),
      trailing: const Icon(Icons.chevron_right_rounded, color: AppColors.textSecondary),
      onTap: () => openArtist(context, artist),
    );
  }
}

/// Opens an artist's page with all of their songs.
void openArtist(BuildContext context, Artist artist) {
  final library = Library.instance;
  final tracks = library.tracksBy(artist);
  Navigator.of(context).push(MaterialPageRoute(
    builder: (_) => CollectionScreen(
      title: artist.name,
      subtitle: '${plural(library.albumsBy(artist).length, 'album')}  •  '
          '${plural(tracks.length, 'song')}',
      imagePath: _artistImage(artist),
      tracks: tracks,
      roundArt: true,
    ),
  ));
}
