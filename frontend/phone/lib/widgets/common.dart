import 'package:flutter/material.dart';

import '../models/playlist.dart';
import '../models/track.dart';
import '../services/playlists.dart';
import '../theme.dart';

/// The rounded "Play" / "Shuffle" pair from the landing page.
class PlayShuffleButtons extends StatelessWidget {
  final VoidCallback? onPlay;
  final VoidCallback? onShuffle;

  const PlayShuffleButtons({super.key, this.onPlay, this.onShuffle});

  @override
  Widget build(BuildContext context) {
    Widget pill(IconData icon, String label, VoidCallback? onPressed) => Expanded(
          child: OutlinedButton.icon(
            onPressed: onPressed,
            icon: Icon(icon, size: 20),
            label: Text(label),
            style: OutlinedButton.styleFrom(
              foregroundColor: AppColors.accent,
              backgroundColor: AppColors.surface,
              side: const BorderSide(color: AppColors.divider),
              shape: const StadiumBorder(),
              padding: const EdgeInsets.symmetric(vertical: 12),
              textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
            ),
          ),
        );

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
      child: Row(children: [
        pill(Icons.play_arrow_rounded, 'Play', onPlay),
        const SizedBox(width: 12),
        pill(Icons.shuffle_rounded, 'Shuffle', onShuffle),
      ]),
    );
  }
}

/// Rounded search field used at the top of each library tab.
class LibrarySearchBar extends StatelessWidget {
  final TextEditingController controller;
  final String hint;
  final ValueChanged<String> onChanged;

  const LibrarySearchBar({
    super.key,
    required this.controller,
    required this.hint,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
      child: ListenableBuilder(
        listenable: controller,
        builder: (context, _) => SearchBar(
          controller: controller,
          hintText: hint,
          leading: const Icon(Icons.search_rounded),
          trailing: [
            if (controller.text.isNotEmpty)
              IconButton(
                icon: const Icon(Icons.close_rounded),
                onPressed: () {
                  controller.clear();
                  onChanged('');
                },
              ),
          ],
          elevation: const WidgetStatePropertyAll(0),
          backgroundColor: const WidgetStatePropertyAll(AppColors.surface),
          onChanged: onChanged,
        ),
      ),
    );
  }
}

/// Large page title, e.g. "Albums".
class PageTitle extends StatelessWidget {
  final String text;
  final Widget? trailing;
  const PageTitle(this.text, {super.key, this.trailing});

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(20, 12, 4, 8),
        child: Row(children: [
          Expanded(
            child: Text(text, style: const TextStyle(fontSize: 34, fontWeight: FontWeight.w800)),
          ),
          ?trailing,
        ]),
      );
}

Future<String?> askForName(BuildContext context,
    {required String title, String initial = '', String action = 'Create'}) {
  final controller = TextEditingController(text: initial);
  return showDialog<String>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(title),
      content: TextField(
        controller: controller,
        autofocus: true,
        textCapitalization: TextCapitalization.sentences,
        decoration: const InputDecoration(hintText: 'Playlist name'),
        onSubmitted: (v) => Navigator.pop(context, v.trim()),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
        FilledButton(
          onPressed: () => Navigator.pop(context, controller.text.trim()),
          child: Text(action),
        ),
      ],
    ),
  ).then((name) => (name == null || name.isEmpty) ? null : name);
}

/// Bottom sheet that adds [track] to an existing or new playlist.
Future<void> showAddToPlaylist(BuildContext context, Track track) async {
  final messenger = ScaffoldMessenger.of(context);
  final playlists = Playlists.instance;

  final Playlist? chosen = await showModalBottomSheet<Playlist>(
    context: context,
    builder: (sheetContext) => SafeArea(
      child: ListView(
        shrinkWrap: true,
        children: [
          const Padding(
            padding: EdgeInsets.fromLTRB(20, 0, 20, 8),
            child: Text('Add to playlist',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
          ),
          ListTile(
            leading: const Icon(Icons.add_rounded),
            title: const Text('New playlist'),
            onTap: () async {
              final name = await askForName(sheetContext, title: 'New playlist');
              if (name == null) return;
              final playlist = await playlists.create(name);
              if (sheetContext.mounted) Navigator.pop(sheetContext, playlist);
            },
          ),
          for (final playlist in playlists.items)
            ListTile(
              leading: const Icon(Icons.queue_music_rounded),
              title: Text(playlist.name),
              subtitle: Text('${playlist.trackIds.length} songs'),
              onTap: () => Navigator.pop(sheetContext, playlist),
            ),
        ],
      ),
    ),
  );
  if (chosen == null) return;

  final added = await playlists.addTrack(chosen, track.id);
  messenger.showSnackBar(SnackBar(
    content: Text(added ? 'Added to ${chosen.name}' : 'Already in ${chosen.name}'),
  ));
}

/// 0:05, 3:07, 1:02:03
String formatDuration(Duration? d) {
  if (d == null) return '--:--';
  final h = d.inHours;
  final m = d.inMinutes.remainder(60);
  final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
  return h > 0 ? '$h:${m.toString().padLeft(2, '0')}:$s' : '$m:$s';
}

String formatSeconds(int seconds) =>
    seconds > 0 ? formatDuration(Duration(seconds: seconds)) : '--:--';

/// Listening time in words: "45 sec", "12 min", "3 hr 5 min".
String formatListenTime(int seconds) {
  if (seconds < 60) return '$seconds sec';
  final minutes = seconds ~/ 60;
  if (minutes < 60) return '$minutes min';
  final m = minutes % 60;
  return m == 0 ? '${minutes ~/ 60} hr' : '${minutes ~/ 60} hr $m min';
}

String plural(int n, String word) => '$n ${n == 1 ? word : '${word}s'}';
