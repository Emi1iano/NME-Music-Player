import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../screens/debug_log_screen.dart';
import '../services/backend.dart';
import '../theme.dart';

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

class _SyncSheet extends StatelessWidget {
  const _SyncSheet();

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
            final busy = backend.syncState == SyncState.connecting ||
                backend.syncState == SyncState.paired;
            return Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text('Sync', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800)),
                const SizedBox(height: 16),
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
                const SizedBox(height: 16),
                _StatusRow(backend: backend),
                if (backend.syncLines.isNotEmpty) ...[
                  const SizedBox(height: 12),
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
                const SizedBox(height: 16),
                FilledButton.icon(
                  onPressed: busy ? null : backend.startSync,
                  icon: const Icon(Icons.sync_rounded),
                  label: Text(busy ? 'Syncing…' : 'Sync now'),
                  style: FilledButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 14)),
                ),
                const SizedBox(height: 8),
                OutlinedButton.icon(
                  onPressed: busy ? null : () => _syncWithKey(context),
                  icon: const Icon(Icons.key_rounded),
                  label: const Text("Use another device's key"),
                ),
                const SizedBox(height: 4),
                TextButton.icon(
                  onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => const DebugLogScreen()),
                  ),
                  icon: const Icon(Icons.bug_report_outlined, size: 18),
                  label: const Text('Open Debug log'),
                ),
                const Text(
                  'Experimental: both devices tap Sync now with the same key. '
                  'The backend keeps the connection open, so close and reopen '
                  'the app to stop it.',
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

/// One line saying where the sync is at, with an icon or spinner.
class _StatusRow extends StatelessWidget {
  final Backend backend;
  const _StatusRow({required this.backend});

  @override
  Widget build(BuildContext context) {
    final (Widget icon, String text) = switch (backend.syncState) {
      SyncState.idle => (
          const Icon(Icons.sync_rounded, color: AppColors.textSecondary),
          'Not synced yet this session'
        ),
      SyncState.connecting => (
          const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2.5)),
          'Waiting for another device with this key…'
        ),
      SyncState.paired => (
          const Icon(Icons.link_rounded, color: AppColors.accent),
          'Connected to ${backend.syncPeer ?? "the other device"}'
        ),
      SyncState.finished => (
          const Icon(Icons.check_circle_rounded, color: Colors.greenAccent),
          'Sync finished'
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
