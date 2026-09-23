import 'package:flutter/material.dart';

import '../widgets/mini_player.dart';
import 'albums_screen.dart';
import 'artists_screen.dart';
import 'playlists_screen.dart';
import 'songs_screen.dart';

/// Bottom tabs: Songs, Albums, Artists, Playlists.
class HomeShell extends StatefulWidget {
  const HomeShell({super.key});

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  int _tab = 0; // which bottom tab is selected

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      // IndexedStack keeps all four tabs alive and only shows one, so each tab
      // remembers its scroll position and search text when you switch away.
      body: IndexedStack(
        index: _tab,
        children: const [
          SongsScreen(),
          AlbumsScreen(),
          ArtistsScreen(),
          PlaylistsScreen(),
        ],
      ),
      // Bottom area = mini player (only visible while a song is loaded)
      // stacked on top of the tab bar.
      bottomNavigationBar: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const MiniPlayer(),
          NavigationBar(
            selectedIndex: _tab,
            // setState() tells Flutter to rebuild this widget with the new tab.
            onDestinationSelected: (i) => setState(() => _tab = i),
            destinations: const [
              NavigationDestination(icon: Icon(Icons.music_note_rounded), label: 'Songs'),
              NavigationDestination(icon: Icon(Icons.album_rounded), label: 'Albums'),
              NavigationDestination(icon: Icon(Icons.mic_rounded), label: 'Artists'),
              NavigationDestination(icon: Icon(Icons.queue_music_rounded), label: 'Playlists'),
            ],
          ),
        ],
      ),
    );
  }
}
