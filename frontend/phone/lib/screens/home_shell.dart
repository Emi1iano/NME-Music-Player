import 'package:flutter/material.dart';

import '../services/appearance.dart';
import '../widgets/glass.dart';
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
      // Glass style: the screen (and its glow) runs under the frosted bars.
      extendBody: Appearance.instance.glass,
      // IndexedStack keeps all four tabs alive and only shows one, so each tab
      // remembers its scroll position and search text when you switch away.
      body: withGlassGlow(IndexedStack(
        index: _tab,
        children: const [
          SongsScreen(),
          AlbumsScreen(),
          ArtistsScreen(),
          PlaylistsScreen(),
        ],
      )),
      // Bottom area = mini player (only visible while a song is loaded)
      // stacked on top of the tab bar. In Glass style both float as rounded
      // frosted shapes, Apple Music style.
      bottomNavigationBar: Appearance.instance.glass ? _floatingBars() : Frosted(child: Column(
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
      )),
    );
  }

  /// Glass style: the mini player and a rounded tab bar floating above the
  /// bottom edge, with the screen scrolling underneath.
  Widget _floatingBars() {
    return SafeArea(
      top: false,
      minimum: const EdgeInsets.fromLTRB(12, 0, 12, 10),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        const MiniPlayer(),
        GlassPill(
          radius: 32,
          child: NavigationBar(
            height: 64,
            backgroundColor: Colors.transparent, // the pill provides the glass
            selectedIndex: _tab,
            onDestinationSelected: (i) => setState(() => _tab = i),
            destinations: const [
              NavigationDestination(icon: Icon(Icons.music_note_rounded), label: 'Songs'),
              NavigationDestination(icon: Icon(Icons.album_rounded), label: 'Albums'),
              NavigationDestination(icon: Icon(Icons.mic_rounded), label: 'Artists'),
              NavigationDestination(icon: Icon(Icons.queue_music_rounded), label: 'Playlists'),
            ],
          ),
        ),
      ]),
    );
  }
}
