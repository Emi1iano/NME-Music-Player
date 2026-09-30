import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';

import '../services/app_log.dart';
import '../services/backend.dart';
import '../theme.dart';

/// Settings → Debug log: everything AppLog recorded, newest at the bottom.
/// Testers tap Share to send it to the team (text message, email, Discord...).
class DebugLogScreen extends StatelessWidget {
  const DebugLogScreen({super.key});

  Future<void> _share(BuildContext context) async {
    // On iPad the share sheet needs to know where to point its popup.
    final box = context.findRenderObject() as RenderBox?;
    await SharePlus.instance.share(ShareParams(
      text: AppLog.instance.export(),
      subject: 'NME Music debug log',
      sharePositionOrigin: box == null ? null : box.localToGlobal(Offset.zero) & box.size,
    ));
  }

  /// Developer tool: type a backend command (add, rename, sync_new_key...)
  /// and run it; the result and the backend's messages appear in this log.
  Future<void> _runCommand(BuildContext context) async {
    final backend = Backend.instance;
    final messenger = ScaffoldMessenger.of(context);
    if (!backend.available) {
      messenger.showSnackBar(SnackBar(content: Text(backend.unavailableReason ?? 'Backend not loaded')));
      return;
    }
    final controller = TextEditingController();
    final command = await showDialog<String>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Run backend command'),
        content: TextField(
          controller: controller,
          autofocus: true,
          autocorrect: false,
          style: const TextStyle(fontFamily: 'monospace'),
          decoration: const InputDecoration(hintText: 'e.g. add song.mp3'),
          onSubmitted: (v) => Navigator.pop(c, v),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(c, controller.text), child: const Text('Run')),
        ],
      ),
    );
    if (command == null || command.trim().isEmpty) return;
    final code = await backend.runCommand(command);
    messenger.showSnackBar(SnackBar(content: Text('"$command" → exit code $code')));
  }

  @override
  Widget build(BuildContext context) {
    final log = AppLog.instance;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Debug log'),
        actions: [
          IconButton(
            tooltip: 'Run backend command',
            icon: const Icon(Icons.terminal_rounded),
            onPressed: () => _runCommand(context),
          ),
          IconButton(
            tooltip: 'Copy',
            icon: const Icon(Icons.copy_rounded),
            onPressed: () {
              Clipboard.setData(ClipboardData(text: log.export()));
              ScaffoldMessenger.of(context)
                  .showSnackBar(const SnackBar(content: Text('Log copied')));
            },
          ),
          IconButton(
            tooltip: 'Clear',
            icon: const Icon(Icons.delete_outline_rounded),
            onPressed: log.clear,
          ),
        ],
      ),
      // Share button at the bottom, easy to reach with a thumb.
      floatingActionButton: Builder(
        builder: (context) => FloatingActionButton.extended(
          onPressed: () => _share(context),
          icon: const Icon(Icons.ios_share_rounded),
          label: const Text('Share log'),
        ),
      ),
      body: ListenableBuilder(
        listenable: log,
        builder: (context, _) {
          final entries = log.entries;
          return ListView(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 96),
            children: [
              if (log.previousRun.isNotEmpty) ...[
                // The last run, e.g. from just before a crash.
                ExpansionTile(
                  title: Text('Previous run (${log.previousRun.length} lines)'),
                  subtitle: const Text('Saved from the last time the app was open',
                      style: TextStyle(color: AppColors.textSecondary)),
                  children: [
                    for (final line in log.previousRun) _LogLine(text: line, color: _colorFor(line)),
                  ],
                ),
                const Divider(),
              ],
              for (final e in entries.reversed) // newest first
                _LogLine(text: e.format(), color: _levelColor(e.level)),
            ],
          );
        },
      ),
    );
  }

  static Color _levelColor(LogLevel level) => switch (level) {
        LogLevel.info => AppColors.textSecondary,
        LogLevel.warning => Colors.amber,
        LogLevel.error => Colors.redAccent,
      };

  // Old lines are plain text, so find the level from the tag in the line.
  static Color _colorFor(String line) => line.contains(' ERROR ')
      ? Colors.redAccent
      : line.contains(' WARN ')
          ? Colors.amber
          : AppColors.textSecondary;
}

/// One log line in a monospace font; long-press to select and copy.
class _LogLine extends StatelessWidget {
  final String text;
  final Color color;
  const _LogLine({required this.text, required this.color});

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 3),
        child: SelectableText(
          text,
          style: TextStyle(fontFamily: 'monospace', fontSize: 12, color: color, height: 1.3),
        ),
      );
}
