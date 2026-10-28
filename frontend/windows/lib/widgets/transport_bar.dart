import 'package:flutter/material.dart';
import '../services/store.dart';
import 'glass.dart';

class TransportBar extends StatefulWidget {
  final Store s;
  const TransportBar(this.s, {super.key});

  @override
  State<TransportBar> createState() => _TransportBarState();
}

class _TransportBarState extends State<TransportBar> {
  double? _drag; // slider position (seconds) while the user is dragging it

  static String _fmt(Duration d) {
    final m = d.inMinutes;
    final s = (d.inSeconds % 60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  @override
  Widget build(BuildContext c) {
    final s = widget.s;
    final song = s.playing;
    if (song == null) return const SizedBox.shrink();

    final total = s.duration.inMilliseconds / 1000;
    final pos = (_drag ?? s.position.inMilliseconds / 1000).clamp(0.0, total > 0 ? total : 1.0);
    final shown = Duration(milliseconds: (pos * 1000).round());

    return Glass(
      radius: 24,
      pad: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      child: Row(children: [
        Expanded(flex: 3, child: Text(song.title, overflow: TextOverflow.ellipsis)),
        IconButton(tooltip: 'Previous', icon: const Icon(Icons.skip_previous), onPressed: s.previous),
        IconButton(
          tooltip: s.ended ? 'Play again' : (s.paused ? 'Play' : 'Pause'),
          icon: Icon(s.ended ? Icons.replay : (s.paused ? Icons.play_arrow : Icons.pause)),
          onPressed: s.togglePause,
        ),
        IconButton(tooltip: 'Next', icon: const Icon(Icons.skip_next), onPressed: s.next),
        Text(_fmt(shown), style: const TextStyle(fontSize: 12)),
        Expanded(
          flex: 4,
          child: Slider(
            value: pos,
            max: total > 0 ? total : 1.0,
            onChanged: total > 0 ? (v) => setState(() => _drag = v) : null,
            onChangeEnd: (v) {
              s.seek(Duration(milliseconds: (v * 1000).round()));
              setState(() => _drag = null);
            },
          ),
        ),
        Text(_fmt(s.duration), style: const TextStyle(fontSize: 12)),
      ]),
    );
  }
}
