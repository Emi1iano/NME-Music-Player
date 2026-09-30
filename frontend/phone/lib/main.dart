import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:just_audio_background/just_audio_background.dart';

import 'screens/home_shell.dart';
import 'services/app_log.dart';
import 'services/backend.dart';
import 'services/library.dart';
import 'services/player.dart';
import 'services/playlists.dart';
import 'services/stats.dart';
import 'theme.dart';

// 1. The entry point of your Flutter application
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Start the debug log first so it can record problems during startup.
  await AppLog.instance.init();

  // Send every uncaught error to the debug log (Settings → Debug log).
  // FlutterError.onError = errors while drawing widgets.
  FlutterError.onError = (details) {
    FlutterError.presentError(details); // still show it in the console
    AppLog.instance.error('UI error', details.exception, details.stack);
  };
  // PlatformDispatcher.onError = any other uncaught error (async code, plugins).
  PlatformDispatcher.instance.onError = (error, stack) {
    AppLog.instance.error('Uncaught error', error, stack);
    return true; // handled: don't crash the app
  };

  // Background playback + lock screen / notification controls.
  await JustAudioBackground.init(
    androidNotificationChannelId: 'com.example.phone.audio',
    androidNotificationChannelName: 'Music playback',
    androidNotificationOngoing: true,
  );

  // Load everything saved on the phone before showing the first screen.
  // Stats first, because the player writes into it as soon as music plays.
  await Stats.instance.init();
  await Player.instance.init();
  await Playlists.instance.init();
  await Library.instance.init();
  // Load Emiliano's backend library (libbackend.so) and point it at our data
  // folder. Must run after Library.init, which decides where that folder is.
  await Backend.instance.init(Library.instance.baseDir);
  // Don't block startup on the folder scan; the list fills in when it's done.
  Library.instance.scan();

  runApp(const NmeMusicApp());
}

// 2. The root widget of your app setting up basic configuration/theming.
// It's Stateful only so it can watch the app lifecycle (foreground/background).
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
      onPause: () {
        AppLog.instance.info('App went to background');
        Stats.instance.flush();
      },
      onResume: () => AppLog.instance.info('App came back to foreground'),
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
      home: const HomeShell(), // 3. The tabbed home screen (Songs/Albums/Artists/Playlists)
    );
  }
}
