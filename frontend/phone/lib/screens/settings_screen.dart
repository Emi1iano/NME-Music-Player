import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../services/app_log.dart';
import '../services/backend.dart';
import '../services/library.dart';
import '../theme.dart';
import '../widgets/common.dart';
import '../widgets/sync_sheet.dart';
import 'debug_log_screen.dart';
import 'stats_screen.dart';

/// Instructions for adding songs, different on iPhone vs Android.
String howToAddMusic() {
  if (Platform.isIOS) {
    return 'Open the Files app → On My iPhone → NME Music → app → music, and put your '
        'songs there. You can also drag files in from a computer with Finder or iTunes.';
  }
  // Show the folder the way it looks from a PC, e.g. Android/data/<id>/files/app/music
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
            const _Header('Sync'),
            const _SyncSection(),
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

/// Settings → Sync: this device's key and the backend's status.
/// Pairing with another device ("sync") comes once the backend supports
/// being called from an app; for now: key, key regeneration, tracked songs.
class _SyncSection extends StatelessWidget {
  const _SyncSection();

  Future<void> _newKey(BuildContext context) async {
    final backend = Backend.instance;
    final messenger = ScaffoldMessenger.of(context);
    // Changing the key is like changing a password: warn first.
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Generate a new key?'),
        content: const Text(
            'Other devices will need the new key to sync with this phone.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('Generate')),
        ],
      ),
    );
    if (ok != true) return;
    final before = backend.key;
    final key = await backend.generateNewKey();
    messenger.showSnackBar(SnackBar(
      content: Text(key != null && key != before
          ? 'New key: $key'
          : 'Could not make a new key. See Debug log'),
    ));
  }

  @override
  Widget build(BuildContext context) {
    final backend = Backend.instance;
    return ListenableBuilder(
      listenable: backend,
      builder: (context, _) {
        if (!backend.available) {
          return ListTile(
            leading: const Icon(Icons.sync_disabled_rounded),
            title: const Text('Sync not available'),
            subtitle: Text(backend.unavailableReason ?? 'Backend not loaded',
                style: const TextStyle(color: AppColors.textSecondary)),
          );
        }
        final key = backend.key;
        return Column(children: [
          ListTile(
            leading: const Icon(Icons.key_rounded),
            title: const Text('Your sync key'),
            // Shown as "1234 5678" so it's easy to read out to someone.
            subtitle: Text(
              key == null ? 'No key yet' : '${key.substring(0, 4)} ${key.substring(4)}',
              style: const TextStyle(
                  fontFamily: 'monospace', fontSize: 20, letterSpacing: 2,
                  color: AppColors.textPrimary),
            ),
            trailing: key == null
                ? null
                : IconButton(
                    tooltip: 'Copy key',
                    icon: const Icon(Icons.copy_rounded, size: 20),
                    onPressed: () {
                      Clipboard.setData(ClipboardData(text: key));
                      ScaffoldMessenger.of(context)
                          .showSnackBar(const SnackBar(content: Text('Key copied')));
                    },
                  ),
          ),
          ListTile(
            leading: const Icon(Icons.autorenew_rounded),
            title: const Text('Generate new key'),
            subtitle: const Text('Like changing a password',
                style: TextStyle(color: AppColors.textSecondary)),
            onTap: () => _newKey(context),
          ),
          ListTile(
            leading: const Icon(Icons.library_add_check_rounded),
            title: const Text('Songs tracked for syncing'),
            subtitle: Text(
              '${backend.tracked.length} of ${Library.instance.tracks.length} songs. '
              'Tap to register new ones',
              style: const TextStyle(color: AppColors.textSecondary),
            ),
            onTap: () => backend.registerNew(Library.instance.tracks.map((t) => t.id)),
          ),
          ListTile(
            leading: const Icon(Icons.devices_rounded),
            title: const Text('Sync with another device'),
            subtitle: const Text('Experimental: pair two devices that use the same key',
                style: TextStyle(color: AppColors.textSecondary)),
            trailing: const Icon(Icons.chevron_right_rounded),
            onTap: () => showSyncSheet(context),
          ),
        ]);
      },
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
