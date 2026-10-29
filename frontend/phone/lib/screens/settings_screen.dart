import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../services/app_log.dart';
import '../services/appearance.dart';
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
    return 'Open the Files app → On My iPhone → NME Music → music, and put your '
        'songs there. You can also drag files in from a computer with Finder or iTunes.';
  }
  // Show the folder the way it looks from a PC, e.g. Android/data/<id>/files/music
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
            const _Header('Appearance'),
            const _AppearanceSection(),
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
            ListenableBuilder(
              listenable: Backend.instance,
              builder: (context, _) {
                final backend = Backend.instance;
                return ListTile(
                  leading: const Icon(Icons.restart_alt_rounded),
                  title: const Text('Reset sync data (testing)'),
                  subtitle: Text(
                    !backend.available
                        ? 'Backend not loaded'
                        : backend.isSyncing
                            ? 'Not while a sync is running'
                            : "Clears the backend's song table and pending changes, "
                                'then adds every song again. Songs and key are kept',
                    style: const TextStyle(color: AppColors.textSecondary),
                  ),
                  enabled: backend.available && !backend.isSyncing,
                  onTap: () => _confirmTestReset(context),
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

/// "Reset sync data (testing)": runs the backend's `testreset`, then adds
/// every song in the library to the backend again.
Future<void> _confirmTestReset(BuildContext context) async {
  final messenger = ScaffoldMessenger.of(context);
  final ok = await showDialog<bool>(
    context: context,
    builder: (c) => AlertDialog(
      title: const Text('Reset sync data?'),
      content: const Text(
          "For testing: empties the backend's song table, changes.txt and music "
          'folder list, then adds every song again. Pending changes (like deletes '
          'not synced yet) are lost. Your songs and sync key are kept.'),
      actions: [
        TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Cancel')),
        FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('Reset')),
      ],
    ),
  );
  if (ok != true) return;
  if (!await Backend.instance.testReset()) {
    messenger.showSnackBar(
        const SnackBar(content: Text('Reset failed. See Debug log')));
    return;
  }
  await Backend.instance.registerNew(Library.instance.tracks.map((t) => t.id));
  messenger.showSnackBar(SnackBar(
      content: Text('Sync data reset: ${plural(Backend.instance.added.length, 'song')} added again')));
}

/// Settings → Sync: this device's key, songs sent to the backend, and the
/// Sync panel for pairing with another device.
class _SyncSection extends StatelessWidget {
  const _SyncSection();

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
            subtitle: Text(
                backend.isSyncing ? 'Not while a sync is running' : 'Like changing a password',
                style: const TextStyle(color: AppColors.textSecondary)),
            enabled: !backend.isSyncing,
            onTap: () => confirmNewKey(context),
          ),
          ListTile(
            leading: const Icon(Icons.library_add_check_rounded),
            title: const Text('Songs added to sync'),
            subtitle: Text(
              '${backend.added.length} of ${Library.instance.tracks.length} songs sent to the '
              'backend. Tap to add new ones',
              style: const TextStyle(color: AppColors.textSecondary),
            ),
            onTap: () => backend.registerNew(Library.instance.tracks.map((t) => t.id)),
          ),
          ListTile(
            leading: const Icon(Icons.devices_rounded),
            title: const Text('Sync with another device'),
            subtitle: Text(syncSummary(backend),
                style: const TextStyle(color: AppColors.textSecondary)),
            trailing: const Icon(Icons.chevron_right_rounded),
            onTap: () => showSyncSheet(context),
          ),
        ]);
      },
    );
  }
}

/// Settings → Appearance: turn individual visual extras on or off.
class _AppearanceSection extends StatelessWidget {
  const _AppearanceSection();

  @override
  Widget build(BuildContext context) {
    final a = Appearance.instance;
    Widget toggle(IconData icon, String title, String subtitle, bool value,
            ValueChanged<bool> onChanged) =>
        SwitchListTile(
          secondary: Icon(icon),
          title: Text(title),
          subtitle: Text(subtitle, style: const TextStyle(color: AppColors.textSecondary)),
          value: value,
          onChanged: onChanged,
        );
    return ListenableBuilder(
      listenable: a,
      builder: (context, _) => Column(children: [
        toggle(Icons.palette_outlined, 'Cover colors in Now Playing',
            "Tint the background with the song's cover", a.coverColors,
            (v) => a.coverColors = v),
        toggle(Icons.open_in_full_rounded, 'Cover animation',
            'The mini player cover grows into Now Playing', a.coverAnimation,
            (v) => a.coverAnimation = v),
        toggle(Icons.grid_view_rounded, 'Playlist cover grid',
            "Show four songs' covers on each playlist", a.playlistGrid,
            (v) => a.playlistGrid = v),
        toggle(Icons.view_carousel_outlined, 'Recently added & played',
            'Rows of covers at the top of Songs', a.recentRows, (v) => a.recentRows = v),
        toggle(Icons.sort_by_alpha_rounded, 'A–Z scroller',
            'Jump to a letter in long song lists', a.letterScroller,
            (v) => a.letterScroller = v),
      ]),
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
