import 'package:flutter/material.dart';
import '../models/track.dart';
import '../screens/library_screen.dart';
import '../screens/playlists_screen.dart';
import '../screens/sync_settings_screen.dart';
import '../widgets/app_sidebar.dart';
import '../widgets/glass.dart';
import '../widgets/transport_bar.dart';

/// Top-level layout: sidebar + active screen + persistent transport bar,
/// all floating as frosted-glass panels over a blurred ambient backdrop -
/// the iOS-style "glass" look instead of flat opaque surfaces.
class AppShell extends StatefulWidget {
  const AppShell({super.key});

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  NmeSection section = NmeSection.library;
  Track? nowPlaying;
  bool isPlaying = false;

  void _selectTrack(Track track) {
    setState(() {
      nowPlaying = track;
      isPlaying = true;
    });
  }

  void _togglePlayPause() {
    if (nowPlaying == null) return;
    setState(() => isPlaying = !isPlaying);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          // Blurred color blobs behind everything - this is what the glass
          // panels are actually refracting. Without it, glass just looks gray.
          const Positioned.fill(child: AmbientBackground()),

          SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                children: [
                  Expanded(
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        AppSidebar(selected: section, onSelect: (s) => setState(() => section = s)),
                        const SizedBox(width: 14),
                        Expanded(
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(20),
                            child: Glass(
                              borderRadius: BorderRadius.circular(20),
                              blur: 30,
                              tintOpacity: 0.05,
                              child: AnimatedSwitcher(
                                duration: const Duration(milliseconds: 220),
                                switchInCurve: Curves.easeOut,
                                switchOutCurve: Curves.easeIn,
                                transitionBuilder: (child, animation) {
                                  final slide = Tween<Offset>(
                                    begin: const Offset(0, 0.02),
                                    end: Offset.zero,
                                  ).animate(animation);
                                  return FadeTransition(
                                    opacity: animation,
                                    child: SlideTransition(position: slide, child: child),
                                  );
                                },
                                // Keying by section ensures AnimatedSwitcher treats each
                                // screen as a distinct child and actually cross-fades.
                                child: KeyedSubtree(key: ValueKey(section), child: _buildScreen()),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 14),
                  TransportBar(nowPlaying: nowPlaying, isPlaying: isPlaying, onPlayPause: _togglePlayPause),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildScreen() {
    switch (section) {
      case NmeSection.library:
        return LibraryScreen(onTrackSelected: _selectTrack, nowPlaying: nowPlaying);
      case NmeSection.playlists:
        return PlaylistsScreen(onTrackSelected: _selectTrack, nowPlaying: nowPlaying);
      case NmeSection.sync:
        return const SyncSettingsScreen();
    }
  }
}
