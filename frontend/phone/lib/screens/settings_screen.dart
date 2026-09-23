import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../services/library.dart';
import '../theme.dart';
import 'stats_screen.dart';

String howToAddMusic() {
  if (Platform.isIOS) {
    return 'Open the Files app → On My iPhone → NME Music → Music, and put your '
        'songs there. You can also drag files in from a computer with Finder or iTunes.';
  }
  // Show the folder the way it looks from a PC, e.g. Android/data/<id>/files/Music
  final path = Library.instance.musicDir.path;
  final i = path.indexOf('Android/data');
  return 'Connect your phone to a computer over USB and copy songs into\n'
      '${i >= 0 ? path.substring(i) : path}';
}

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final library = Library.instance;
    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: ListenableBuilder(
        listenable: library,
        builder: (context, _) => ListView(
          children: [
            const _Header('Library'),
            ListTile(
              leading: const Icon(Icons.folder_rounded),
              title: const Text('Music folder'),
              subtitle: Text(library.musicDir.path,
                  style: const TextStyle(color: AppColors.textSecondary)),
              trailing: const Icon(Icons.copy_rounded, size: 20),
              onTap: () {
                Clipboard.setData(ClipboardData(text: library.musicDir.path));
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Folder path copied')),
                );
              },
            ),
            ListTile(
              leading: const Icon(Icons.help_outline_rounded),
              title: const Text('How to add music'),
              subtitle: Text(howToAddMusic(),
                  style: const TextStyle(color: AppColors.textSecondary)),
            ),
            ListTile(
              leading: const Icon(Icons.refresh_rounded),
              title: const Text('Rescan music folder'),
              subtitle: Text(
                library.scanning ? 'Scanning…' : '${library.tracks.length} songs found',
                style: const TextStyle(color: AppColors.textSecondary),
              ),
              onTap: library.scanning ? null : library.scan,
            ),
            const _Header('Listening'),
            ListTile(
              leading: const Icon(Icons.bar_chart_rounded),
              title: const Text('Listening stats'),
              subtitle: const Text('Play counts and time listened',
                  style: TextStyle(color: AppColors.textSecondary)),
              trailing: const Icon(Icons.chevron_right_rounded),
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const StatsScreen()),
              ),
            ),
            const _Header('About'),
            const ListTile(
              leading: Icon(Icons.info_outline_rounded),
              title: Text('NME Music Player'),
              subtitle: Text('Version 1.0.0', style: TextStyle(color: AppColors.textSecondary)),
            ),
          ],
        ),
      ),
    );
  }
}

class _Header extends StatelessWidget {
  final String text;
  const _Header(this.text);

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 20, 16, 4),
        child: Text(text.toUpperCase(),
            style: const TextStyle(
                color: AppColors.accent,
                fontSize: 12,
                fontWeight: FontWeight.w700,
                letterSpacing: 1)),
      );
}
