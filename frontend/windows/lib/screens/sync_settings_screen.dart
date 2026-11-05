import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../services/store.dart';
import '../services/sync_api.dart';
import '../theme/app_theme.dart';
import '../widgets/glass.dart';

class SyncSettingsScreen extends StatefulWidget {
  final Store s;
  const SyncSettingsScreen(this.s, {super.key});
  @override
  State<SyncSettingsScreen> createState() => _SyncSettingsScreenState();
}

class _SyncSettingsScreenState extends State<SyncSettingsScreen> {
  final ctl = TextEditingController();

  @override
  void dispose() {
    ctl.dispose();
    super.dispose();
  }

  InputDecoration _field(String hint) => InputDecoration(
        hintText: hint,
        filled: true,
        fillColor: Colors.white.withOpacity(.12),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide.none),
      );

  @override
  Widget build(BuildContext c) {
    final s = widget.s;
    final waiting = s.pendingSongs;

    return Glass(
      child: ListView(children: [
        Text('Sync', style: Theme.of(c).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w600)),
        const SizedBox(height: 16),
        const Text('Your key'),
        Row(children: [
          SelectableText(s.key ?? 'none yet',
              style: const TextStyle(fontSize: 28, letterSpacing: 6, fontWeight: FontWeight.w700)),
          if (s.key != null)
            IconButton(
              tooltip: 'Copy key',
              icon: const Icon(Icons.copy, size: 18),
              onPressed: () => Clipboard.setData(ClipboardData(text: s.key!)),
            ),
        ]),
        const SizedBox(height: 14),
        TextField(
          controller: ctl,
          keyboardType: TextInputType.number,
          inputFormatters: [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(8)],
          decoration: _field('Enter the other device\'s 8-digit key, or leave empty to use yours'),
        ),
        const SizedBox(height: 14),
        Wrap(spacing: 10, runSpacing: 10, children: [
          FilledButton.icon(
            style: FilledButton.styleFrom(backgroundColor: accent, foregroundColor: Colors.white),
            onPressed: s.syncing || !MusicSync.supported ? null : () => s.connect(ctl.text),
            icon: const Icon(Icons.sync),
            label: const Text('Sync'),
          ),
          if (s.syncing)
            OutlinedButton(onPressed: s.cancelSync, child: const Text('Cancel'))
          else
            OutlinedButton(
              onPressed: () {
                s.newKey();
                ctl.clear();
              },
              child: const Text('New key'),
            ),
        ]),
        const SizedBox(height: 12),
        Row(children: [
          if (s.syncing) ...[
            const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2)),
            const SizedBox(width: 10),
          ],
          Expanded(child: Text(s.status, style: const TextStyle(fontSize: 12))),
        ]),
        const SizedBox(height: 4),
        const Text(
          'Press Sync on both devices with the same key within 20 seconds. Each device sends '
          'the songs added since the last sync and receives the ones it is missing.',
          style: TextStyle(fontSize: 12, color: Colors.white70),
        ),
        const Divider(height: 32),
        const Text('Your songs', style: TextStyle(fontWeight: FontWeight.w600)),
        const SizedBox(height: 4),
        SelectableText(s.folder, style: const TextStyle(fontSize: 12)),
        const SizedBox(height: 8),
        Wrap(spacing: 10, runSpacing: 10, children: [
          OutlinedButton.icon(
            onPressed: MusicSync.supported ? s.openMusicFolder : null,
            icon: const Icon(Icons.folder_open, size: 18),
            label: const Text('Open folder'),
          ),
          OutlinedButton.icon(
            onPressed: s.syncing || s.library.isEmpty ? null : s.sendAllAgain,
            icon: const Icon(Icons.upload, size: 18),
            label: const Text('Send all my songs again'),
          ),
        ]),
        const SizedBox(height: 8),
        Text(
          '$waiting song(s) waiting to be sent. Songs are only sent once; use "Send all my songs again" '
          'to give another device the whole library. Songs received from the other device and songs '
          'you import or drop into this folder all appear in your library.',
          style: const TextStyle(fontSize: 12, color: Colors.white70),
        ),
        const SizedBox(height: 14),
        const Text(
          'The pairing server address is built into the sync backend.',
          style: TextStyle(fontSize: 11, color: Colors.white70),
        ),
      ]),
    );
  }
}
