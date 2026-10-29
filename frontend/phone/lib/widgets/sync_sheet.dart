import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../screens/debug_log_screen.dart';
import '../screens/now_playing_screen.dart';
import '../services/backend.dart';
import '../services/library.dart';
import '../services/player.dart';
import '../theme.dart';
import 'common.dart';

/// The Sync panel (top-right sync button, or Settings → Sync with another
/// device). Shows this phone's key, starts the backend's `sync`, and shows
/// the backend's own messages live so the connection can be tested.
Future<void> showSyncSheet(BuildContext context) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    builder: (_) => const _SyncSheet(),
  );
}

/// "Generate new key" (Sync panel and Settings). Changing the key is like
/// changing a password, so ask first.
Future<void> confirmNewKey(BuildContext context) async {
  final backend = Backend.instance;
  final messenger = ScaffoldMessenger.of(context);
  final ok = await showDialog<bool>(
    context: context,
    builder: (c) => AlertDialog(
      title: const Text('Generate a new key?'),
      content: const Text('Other devices will need the new key to sync with this phone.'),
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
        ? 'New key: ${key.substring(0, 4)} ${key.substring(4)}'
        : 'Could not make a new key. See Debug log'),
  ));
}

class _SyncSheet extends StatefulWidget {
  const _SyncSheet();

  @override
  State<_SyncSheet> createState() => _SyncSheetState();
}

class _SyncSheetState extends State<_SyncSheet> {
  final _message = TextEditingController(); // "Send test message" box
  bool _showDetails = false; // the backend's raw messages, hidden by default

  @override
  void dispose() {
    _message.dispose();
    super.dispose();
  }

  void _send() {
    final text = _message.text;
    if (text.trim().toUpperCase() == 'EXIT') {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Use Cancel sync to disconnect')));
      return;
    }
    if (Backend.instance.sendSyncMessage(text)) _message.clear();
  }

  /// "Use another device's key": both devices need the SAME key to pair.
  Future<void> _syncWithKey(BuildContext context) async {
    final controller = TextEditingController();
    final key = await showDialog<String>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text("Other device's key"),
        content: TextField(
          controller: controller,
          autofocus: true,
          keyboardType: TextInputType.number,
          maxLength: 8,
          style: const TextStyle(fontFamily: 'monospace', fontSize: 22, letterSpacing: 4),
          decoration: const InputDecoration(hintText: '12345678', counterText: ''),
          onSubmitted: (v) => Navigator.pop(c, v.trim()),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c), child: const Text('Cancel')),
          FilledButton(
              onPressed: () => Navigator.pop(c, controller.text.trim()),
              child: const Text('Sync')),
        ],
      ),
    );
    if (key == null) return;
    if (!RegExp(r'^\d{8}$').hasMatch(key)) {
      if (context.mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('A key is exactly 8 digits')));
      }
      return;
    }
    await Backend.instance.startSync(withKey: key);
  }

  @override
  Widget build(BuildContext context) {
    final backend = Backend.instance;
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
        child: ListenableBuilder(
          listenable: backend,
          builder: (context, _) {
            if (!backend.available) {
              return Padding(
                padding: const EdgeInsets.symmetric(vertical: 24),
                child: Text(backend.unavailableReason ?? 'Sync is not available',
                    style: const TextStyle(color: AppColors.textSecondary)),
              );
            }
            final key = backend.key;
            final busy = backend.isSyncing;
            final cancelling = backend.syncState == SyncState.cancelling;
            return Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(children: [
                  const Expanded(
                    child: Text('Sync',
                        style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800)),
                  ),
                  // Less common actions live here so the panel stays simple.
                  PopupMenuButton<_MoreAction>(
                    tooltip: 'More options',
                    icon: const Icon(Icons.more_horiz_rounded),
                    onSelected: (action) => switch (action) {
                      _MoreAction.otherKey => _syncWithKey(context),
                      _MoreAction.newKey => confirmNewKey(context),
                      _MoreAction.debugLog => Navigator.of(context).push(
                          MaterialPageRoute(builder: (_) => const DebugLogScreen())),
                    },
                    itemBuilder: (_) => [
                      PopupMenuItem(
                        value: _MoreAction.otherKey,
                        enabled: !busy,
                        child: const ListTile(
                          leading: Icon(Icons.key_rounded),
                          title: Text("Use another device's key"),
                          contentPadding: EdgeInsets.zero,
                        ),
                      ),
                      PopupMenuItem(
                        value: _MoreAction.newKey,
                        enabled: !busy,
                        child: const ListTile(
                          leading: Icon(Icons.autorenew_rounded),
                          title: Text('Generate new key'),
                          contentPadding: EdgeInsets.zero,
                        ),
                      ),
                      const PopupMenuItem(
                        value: _MoreAction.debugLog,
                        child: ListTile(
                          leading: Icon(Icons.bug_report_outlined),
                          title: Text('Open Debug log'),
                          contentPadding: EdgeInsets.zero,
                        ),
                      ),
                    ],
                  ),
                ]),
                const SizedBox(height: 8),
                // This phone's key, big enough to read out to someone.
                Row(children: [
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      const Text('Your sync key',
                          style: TextStyle(color: AppColors.textSecondary, fontSize: 13)),
                      Text(
                        key == null ? '--------' : '${key.substring(0, 4)} ${key.substring(4)}',
                        style: const TextStyle(
                            fontFamily: 'monospace', fontSize: 30, letterSpacing: 3),
                      ),
                    ]),
                  ),
                  if (key != null)
                    IconButton(
                      tooltip: 'Copy key',
                      icon: const Icon(Icons.copy_rounded),
                      onPressed: () => Clipboard.setData(ClipboardData(text: key)),
                    ),
                ]),
                const SizedBox(height: 4),
                Text(syncSummary(backend),
                    style: const TextStyle(color: AppColors.textSecondary, fontSize: 13)),
                const SizedBox(height: 16),
                _StatusRow(backend: backend),
                if (_progress(backend) case final progress?) ...[
                  const SizedBox(height: 8),
                  Text(progress, style: const TextStyle(color: AppColors.textSecondary)),
                ],
                if (backend.finishingIn case final seconds?) ...[
                  const SizedBox(height: 12),
                  _FinishingCard(backend: backend, seconds: seconds),
                ],
                if (backend.receivedSongs.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  _ReceivedSongs(names: backend.receivedSongs),
                ],
                if (backend.syncLines.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: TextButton.icon(
                      onPressed: () => setState(() => _showDetails = !_showDetails),
                      icon: Icon(_showDetails
                          ? Icons.expand_less_rounded
                          : Icons.expand_more_rounded),
                      label: Text(_showDetails ? 'Hide details' : 'Show details'),
                    ),
                  ),
                ],
                if (_showDetails && backend.syncLines.isNotEmpty) ...[
                  // The backend's own messages for this sync, newest last.
                  Container(
                    constraints: const BoxConstraints(maxHeight: 160),
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: AppColors.background,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: SingleChildScrollView(
                      reverse: true,
                      child: Text(
                        backend.syncLines.join('\n'),
                        style: const TextStyle(
                            fontFamily: 'monospace', fontSize: 12, color: AppColors.textSecondary),
                      ),
                    ),
                  ),
                ],
                // Send a text message to the connected device (the backend
                // sends each typed line to the other side).
                if (Backend.chatMode && backend.syncState == SyncState.paired) ...[
                  const SizedBox(height: 12),
                  Row(children: [
                    Expanded(
                      child: TextField(
                        controller: _message,
                        textInputAction: TextInputAction.send,
                        onSubmitted: (_) => _send(),
                        decoration: const InputDecoration(
                          hintText: 'Send a test message',
                          isDense: true,
                          border: OutlineInputBorder(),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    IconButton.filled(
                      tooltip: 'Send',
                      onPressed: _send,
                      icon: const Icon(Icons.send_rounded),
                    ),
                  ]),
                ],
                const SizedBox(height: 16),
                // While syncing, the main button becomes "Cancel sync".
                if (busy)
                  OutlinedButton.icon(
                    onPressed: cancelling ? null : backend.cancelSync,
                    icon: cancelling
                        ? const SizedBox(
                            width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                        : const Icon(Icons.stop_circle_outlined),
                    label: Text(cancelling ? 'Stopping…' : 'Cancel sync'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.redAccent,
                      side: const BorderSide(color: Colors.redAccent),
                      padding: const EdgeInsets.symmetric(vertical: 14),
                    ),
                  )
                else
                  FilledButton.icon(
                    onPressed: backend.startSync,
                    icon: const Icon(Icons.sync_rounded),
                    label: const Text('Sync now'),
                    style: FilledButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 14)),
                  ),
                const SizedBox(height: 12),
                const Text(
                  'Both devices tap Sync now with the same key. Once connected, each '
                  'side sends its new, renamed and deleted songs, and the connection '
                  'closes by itself when both are done.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: AppColors.textSecondary, fontSize: 12),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

/// "Sent 3 songs • Received 2 songs" for the current sync, or null if
/// nothing has moved yet.
String? _progress(Backend b) {
  String songs(int n) => n == 1 ? '1 song' : '$n songs';
  final parts = [
    if (b.songsSent > 0) 'Sent ${songs(b.songsSent)}',
    if (b.songsReceived > 0) 'Received ${songs(b.songsReceived)}',
    if (b.songsRenamed > 0) '${songs(b.songsRenamed)} renamed',
    if (b.songsDeleted > 0) '${songs(b.songsDeleted)} deleted',
  ];
  if (b.doneSending && b.isSyncing) {
    parts.add(b.songsSent == 0 ? 'Nothing new to send' : 'All sent');
  }
  return parts.isEmpty ? null : parts.join('  •  ');
}

/// The ⋯ menu in the Sync panel.
enum _MoreAction { otherKey, newKey, debugLog }

/// Under the key: "3 changes waiting to sync  •  Last synced 5 min ago".
/// Also used in Settings.
String syncSummary(Backend b) {
  final pending = b.pendingChanges == 0
      ? 'Everything synced'
      : '${b.pendingChanges} ${b.pendingChanges == 1 ? 'change' : 'changes'} waiting to sync';
  final last = b.lastSyncedAt == null ? 'Never synced' : 'Last synced ${formatAgo(b.lastSyncedAt!)}';
  return '$pending  •  $last';
}

/// "Sync complete: received 3 songs, sent 2." (+ a warning about songs that
/// arrived incomplete).
String _completeText(Backend b) {
  String songs(int n) => n == 1 ? '1 song' : '$n songs';
  final parts = [
    if (b.songsReceived > 0) 'received ${songs(b.songsReceived)}',
    if (b.songsSent > 0) 'sent ${songs(b.songsSent)}',
    if (b.songsRenamed > 0) '${songs(b.songsRenamed)} renamed',
    if (b.songsDeleted > 0) '${songs(b.songsDeleted)} deleted',
  ];
  final summary = parts.isEmpty ? 'Sync complete: everything was already up to date.'
      : 'Sync complete: ${parts.join(', ')}.';
  if (b.songsIncomplete == 0) return summary;
  return '$summary ${songs(b.songsIncomplete)} arrived incomplete; sync again to fix.';
}

/// "Everything is synced. Closing the connection in 7 s" with Stay connected /
/// Finish now. Shown once all our songs are confirmed and the other device
/// has gone quiet.
class _FinishingCard extends StatelessWidget {
  final Backend backend;
  final int seconds;
  const _FinishingCard({required this.backend, required this.seconds});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 12, 4, 4),
      decoration: BoxDecoration(
        color: AppColors.surfaceHigh,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          const Icon(Icons.done_all_rounded, color: Colors.greenAccent),
          const SizedBox(width: 12),
          Expanded(child: Text('All done. Closing the connection in $seconds s')),
        ]),
        Row(mainAxisAlignment: MainAxisAlignment.end, children: [
          TextButton(onPressed: backend.keepConnected, child: const Text('Stay connected')),
          TextButton(onPressed: backend.finishSync, child: const Text('Finish now')),
        ]),
      ]),
    );
  }
}

/// The songs that arrived from the other device; tap one to play it.
class _ReceivedSongs extends StatelessWidget {
  final List<String> names;
  const _ReceivedSongs({required this.names});

  static const _shown = 5;

  void _play(BuildContext context, String name) {
    final library = Library.instance;
    final track = library.trackById(name);
    if (track == null) {
      // The library rescans a couple of seconds after a song arrives.
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Still adding it to your library, try again in a moment')));
      return;
    }
    // Grab the navigator first: this context goes away with the Sync panel.
    final navigator = Navigator.of(context);
    navigator.pop(); // close the Sync panel
    Player.instance.playTracks(library.tracks, index: library.tracks.indexOf(track));
    navigator.push(MaterialPageRoute(
      fullscreenDialog: true,
      builder: (_) => const NowPlayingScreen(),
    ));
  }

  @override
  Widget build(BuildContext context) {
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      const Text('New from the other device',
          style: TextStyle(color: AppColors.textSecondary, fontSize: 13)),
      for (final name in names.take(_shown))
        ListTile(
          dense: true,
          contentPadding: EdgeInsets.zero,
          leading: const Icon(Icons.music_note_rounded),
          title: Text(name, maxLines: 1, overflow: TextOverflow.ellipsis),
          trailing: const Icon(Icons.play_arrow_rounded),
          onTap: () => _play(context, name),
        ),
      if (names.length > _shown)
        Text('and ${names.length - _shown} more',
            style: const TextStyle(color: AppColors.textSecondary, fontSize: 13)),
    ]);
  }
}

/// One line saying where the sync is at, with an icon or spinner.
class _StatusRow extends StatelessWidget {
  final Backend backend;
  const _StatusRow({required this.backend});

  @override
  Widget build(BuildContext context) {
    final (Widget icon, String text) = switch (backend.syncState) {
      SyncState.idle => (
          const Icon(Icons.sync_rounded, color: AppColors.textSecondary),
          'Ready to sync'
        ),
      SyncState.connecting => (
          const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2.5)),
          backend.syncPeer == null
              ? 'Waiting for another device with this key…'
              : 'Found ${backend.syncPeer}, connecting…'
        ),
      SyncState.paired => (
          Icon(Icons.link_rounded, color: AppColors.accent),
          'Connected to ${backend.syncPeer ?? "the other device"}'
              '${backend.syncMode == null ? '' : ' (${backend.syncMode})'}'
        ),
      SyncState.cancelling => (
          const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2.5)),
          'Stopping sync…'
        ),
      SyncState.cancelled => (
          const Icon(Icons.stop_circle_outlined, color: AppColors.textSecondary),
          'Sync cancelled'
        ),
      SyncState.noPartner => (
          const Icon(Icons.person_search_rounded, color: Colors.amber),
          'No device with this key found. The server waits 20 seconds, so start '
              'sync on both devices at about the same time.'
        ),
      SyncState.finished => (
          const Icon(Icons.check_circle_rounded, color: Colors.greenAccent),
          _completeText(backend)
        ),
      SyncState.failed => (
          const Icon(Icons.error_outline_rounded, color: Colors.redAccent),
          'Sync stopped with an error (see Debug log)'
        ),
    };
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.surfaceHigh,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(children: [
        icon,
        const SizedBox(width: 12),
        Expanded(child: Text(text)),
      ]),
    );
  }
}
