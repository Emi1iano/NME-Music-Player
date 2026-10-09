import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../models/models.dart';
import '../services/store.dart';
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
  final folderCtl = TextEditingController();
  final serverCtl = TextEditingController();
  final restore = <String>{};

  @override
  void dispose() {
    ctl.dispose();
    folderCtl.dispose();
    serverCtl.dispose();
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
    // The store loads after this screen is built, so fill the fields once it has.
    if (folderCtl.text.isEmpty && s.folder.isNotEmpty) folderCtl.text = s.folder;
    if (serverCtl.text.isEmpty) serverCtl.text = s.server;
    restore.retainAll(s.deleted);
    final deleted = s.deleted.toList()..sort();

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
            onPressed: s.syncing ? null : () => s.connect(ctl.text),
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
        const Text(
          'Press Sync on both devices with the same key within 2 minutes. '
          'Each device downloads the songs it is missing.',
          style: TextStyle(fontSize: 12, color: Colors.white70),
        ),
        const Divider(height: 32),
        const Text('Get deleted songs back', style: TextStyle(fontWeight: FontWeight.w600)),
        const SizedBox(height: 4),
        const Text(
          'Songs you deleted are skipped when syncing. Pick the ones you want again and resync '
          'to download them from your other device.',
          style: TextStyle(fontSize: 12, color: Colors.white70),
        ),
        const SizedBox(height: 8),
        if (deleted.isEmpty)
          const Text('No deleted songs.', style: TextStyle(fontSize: 12))
        else ...[
          for (final p in deleted)
            CheckboxListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              value: restore.contains(p),
              title: Text(Song.fromPath(p).title),
              subtitle: Text(p, style: const TextStyle(fontSize: 11)),
              onChanged: (v) => setState(() => v == true ? restore.add(p) : restore.remove(p)),
            ),
          Wrap(spacing: 10, runSpacing: 10, children: [
            TextButton(
              onPressed: () => setState(() => restore.length == deleted.length
                  ? restore.clear()
                  : restore.addAll(deleted)),
              child: Text(restore.length == deleted.length ? 'Select none' : 'Select all'),
            ),
            FilledButton.icon(
              style: FilledButton.styleFrom(backgroundColor: accent, foregroundColor: Colors.white),
              onPressed: s.syncing || restore.isEmpty ? null : () => s.resync({...restore}),
              icon: const Icon(Icons.restore),
              label: Text('Resync ${restore.length} song(s)'),
            ),
          ]),
        ],
        const Divider(height: 32),
        const Text('Settings', style: TextStyle(fontWeight: FontWeight.w600)),
        const SizedBox(height: 8),
        const Text('Music folder', style: TextStyle(fontSize: 12)),
        const SizedBox(height: 4),
        TextField(
          controller: folderCtl,
          decoration: _field('Folder with your songs'),
          onSubmitted: s.setFolder,
        ),
        const SizedBox(height: 10),
        const Text('Pairing server (host:port)', style: TextStyle(fontSize: 12)),
        const SizedBox(height: 4),
        TextField(
          controller: serverCtl,
          decoration: _field('24.243.26.72:5252'),
          onSubmitted: s.setServer,
        ),
        const SizedBox(height: 4),
        const Text('Press Enter to save.', style: TextStyle(fontSize: 11, color: Colors.white70)),
      ]),
    );
  }
}
