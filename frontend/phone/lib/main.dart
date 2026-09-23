import 'package:flutter/material.dart';
import 'package:just_audio_background/just_audio_background.dart';

import 'screens/home_shell.dart';
import 'services/library.dart';
import 'services/player.dart';
import 'services/playlists.dart';
import 'services/stats.dart';
import 'theme.dart';

// 1. The entry point of your Flutter application
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Background playback + lock screen / notification controls.
  await JustAudioBackground.init(
    androidNotificationChannelId: 'com.example.phone.audio',
    androidNotificationChannelName: 'Music playback',
    androidNotificationOngoing: true,
  );

  await Stats.instance.init();
  await Player.instance.init();
  await Playlists.instance.init();
  await Library.instance.init();
  // Don't block startup on the folder scan; the list fills in when it's done.
  Library.instance.scan();

  runApp(const NmeMusicApp());
}

// 2. The root widget of your app setting up basic configuration/theming
class NmeMusicApp extends StatefulWidget {
  const NmeMusicApp({super.key});

  @override
  State<NmeMusicApp> createState() => _NmeMusicAppState();
}

class _NmeMusicAppState extends State<NmeMusicApp> {
  late final AppLifecycleListener _lifecycle;

  @override
  void initState() {
    super.initState();
    // Save listening stats right away when the app goes to the background.
    _lifecycle = AppLifecycleListener(
      onPause: Stats.instance.flush,
      onDetach: Stats.instance.flush,
    );
  }

  @override
  void dispose() {
    _lifecycle.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'NME Music Player',
      debugShowCheckedModeBanner: false,
      theme: buildDarkTheme(), // Dark theme for a modern music player look
      themeMode: ThemeMode.dark,
      home: const HomeShell(),
    );
  }
}
