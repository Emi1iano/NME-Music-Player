import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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

  @override
  Widget build(BuildContext c) {
    final s = widget.s;
    return Glass(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
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
          decoration: InputDecoration(
            hintText: 'Enter an 8-digit key, or leave empty',
            filled: true,
            fillColor: Colors.white.withOpacity(.12),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide.none),
          ),
        ),
        const SizedBox(height: 14),
        Wrap(spacing: 10, runSpacing: 10, children: [
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: accent, foregroundColor: Colors.white),
            onPressed: () => s.connect(ctl.text),
            child: const Text('Connect'),
          ),
          OutlinedButton(
            onPressed: () async {
              await s.newKey();
              ctl.clear();
            },
            child: const Text('New key'),
          ),
        ]),
        const Spacer(),
        Text(s.status, style: const TextStyle(fontSize: 12)),
      ]),
    );
  }
}
