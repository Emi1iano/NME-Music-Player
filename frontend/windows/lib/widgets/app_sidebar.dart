import 'package:flutter/material.dart';
import '../services/store.dart';
import '../theme/app_theme.dart';
import 'glass.dart';

const navIcons = [
  Icons.library_music_rounded,
  Icons.queue_music_rounded,
  Icons.bar_chart_rounded,
  Icons.sync_rounded,
];
const navLabels = ['Library', 'Playlists', 'Stats', 'Sync'];

/// Wide layouts (desktop / web).
class AppSidebar extends StatelessWidget {
  final int index;
  final ValueChanged<int> onTap;
  final Store store;
  const AppSidebar({super.key, required this.index, required this.onTap, required this.store});

  @override
  Widget build(BuildContext c) => Glass(
        pad: const EdgeInsets.all(14),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Padding(
            padding: EdgeInsets.fromLTRB(10, 8, 10, 18),
            child: Text('Music', style: TextStyle(fontSize: 24, fontWeight: FontWeight.w700)),
          ),
          for (var i = 0; i < navLabels.length; i++)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 3),
              child: InkWell(
                borderRadius: BorderRadius.circular(16),
                onTap: () => onTap(i),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 180),
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(16),
                    color: i == index ? accent : Colors.transparent,
                  ),
                  child: Row(children: [
                    Icon(navIcons[i], size: 20),
                    const SizedBox(width: 12),
                    Text(navLabels[i], style: TextStyle(fontWeight: i == index ? FontWeight.w700 : FontWeight.w400)),
                  ]),
                ),
              ),
            ),
          const Spacer(),
          Padding(
            padding: const EdgeInsets.all(10),
            child: Text('${store.listened} listened\n${store.plays} plays',
                style: const TextStyle(fontSize: 12, height: 1.5)),
          ),
        ]),
      );
}

/// Narrow layouts (phones / small windows).
class AppDock extends StatelessWidget {
  final int index;
  final ValueChanged<int> onTap;
  const AppDock({super.key, required this.index, required this.onTap});

  @override
  Widget build(BuildContext c) => Glass(
        radius: 40,
        pad: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          for (var i = 0; i < navIcons.length; i++)
            GestureDetector(
              onTap: () => onTap(i),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                margin: const EdgeInsets.symmetric(horizontal: 5),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: i == index ? accent : Colors.white.withOpacity(.12),
                ),
                child: Icon(navIcons[i], color: Colors.white),
              ),
            ),
        ]),
      );
}
