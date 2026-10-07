import 'package:flutter/material.dart';
import '../services/store.dart';
import 'glass.dart';

class TransportBar extends StatelessWidget {
  final Store s;
  const TransportBar(this.s, {super.key});
  @override
  Widget build(BuildContext c) {
    final song = s.playing;
    if (song == null) return const SizedBox.shrink();
    return Glass(
      radius: 24,
      pad: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      child: Row(children: [
        const Icon(Icons.graphic_eq),
        const SizedBox(width: 12),
        Expanded(child: Text(song.title, overflow: TextOverflow.ellipsis)),
        IconButton(icon: Icon(s.paused ? Icons.play_arrow : Icons.pause), onPressed: s.togglePause),
      ]),
    );
  }
}
