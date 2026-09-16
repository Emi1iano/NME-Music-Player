import 'package:flutter/material.dart';
import 'data/mock_data.dart';

// 1. The entry point of your Flutter application
void main() {
  runApp(const NmeMusicApp());
}

// 2. The root widget of your app setting up basic configuration/theming
class NmeMusicApp extends StatelessWidget {
  const NmeMusicApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'NME Music Player',
      debugShowCheckedModeBanner: false,
      theme: ThemeData.dark(), // Dark theme for a modern music player look
      home: const HomeScreen(),
    );
  }
}

// 3. A basic starting screen to render your mock tracks
class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    // Accessing your mock tracks from lib/data/mock_data.dart
    final tracks = MockData.tracks;

    return Scaffold(
      appBar: AppBar(
        title: const Text('NME Library'),
      ),
      body: ListView.builder(
        itemCount: tracks.length,
        itemBuilder: (context, index) {
          final track = tracks[index];
          final stats = MockData.stats[track.id];

          return ListTile(
            leading: const Icon(Icons.music_note),
            title: Text(track.title),
            subtitle: Text('Duration: ${track.durationSeconds}s'),
            trailing: Text('Plays: ${stats?.playCount ?? 0}'),
            onTap: () {
              // Playback control logic will go here later
            },
          );
        },
      ),
    );
  }
}