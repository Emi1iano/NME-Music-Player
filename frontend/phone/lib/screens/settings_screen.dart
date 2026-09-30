import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../services/app_log.dart';
import '../services/library.dart';
import '../theme.dart';
import '../widgets/common.dart';
import 'debug_log_screen.dart';
import 'stats_screen.dart';

/// Instructions for adding songs, different on iPhone vs Android.
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

/// Opened from the ⚙ button: music folder info, rescan, and listening stats.
/// (The Sync section for pairing devices will go here next.)
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
              leading: const Icon(Icons.add_rounded),
              title: const Text('Import songs'),
              subtitle: const Text('Copy songs from your phone into the library',
                  style: TextStyle(color: AppColors.textSecondary)),
              onTap: () => importSongs(context),
            ),
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
            const _Header('Troubleshooting'),
            ListenableBuilder(
              listenable: AppLog.instance,
              builder: (context, _) {
                final errors = AppLog.instance.errorCount;
                return ListTile(
                  leading: Icon(Icons.bug_report_rounded,
                      color: errors > 0 ? Colors.redAccent : null),
                  title: const Text('Debug log'),
                  subtitle: Text(
                    errors > 0
                        ? '${errors == 1 ? '1 error' : '$errors errors'} this session — tap to view & share'
                        : 'What the app is doing, to share when something goes wrong',
                    style: const TextStyle(color: AppColors.textSecondary),
                  ),
                  trailing: const Icon(Icons.chevron_right_rounded),
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => const DebugLogScreen()),
                  ),
                );
              },
            ),
            const _Header('About'),
            // Version comes from pubspec.yaml (version: x.y.z+build).
            FutureBuilder<PackageInfo>(
              future: PackageInfo.fromPlatform(),
              builder: (context, snap) => ListTile(
                leading: const Icon(Icons.info_outline_rounded),
                title: const Text('NME Music Player'),
                subtitle: Text(
                  snap.hasData
                      ? 'Version ${snap.data!.version} (build ${snap.data!.buildNumber})'
                      : 'Version …',
                  style: const TextStyle(color: AppColors.textSecondary),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Small colored section title, e.g. "LIBRARY".
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
