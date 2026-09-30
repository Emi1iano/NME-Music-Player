import 'package:flutter/material.dart';

import '../models/playlist.dart';
import '../models/track.dart';
import 'package:path/path.dart' as p;

import '../services/backend.dart';
import '../services/importer.dart';
import '../services/library.dart';
import '../services/playlists.dart';
import '../services/stats.dart';
import '../theme.dart';

// Small building blocks shared by several screens, so they look and behave
// the same everywhere.

/// The rounded "Play" / "Shuffle" pair from the landing page.
/// Pass null for a callback to show the button greyed out (e.g. no songs).
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
      // Rebuild as the user types so the ✕ clear button appears/disappears.
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

/// Pop-up with a text box, used to name/rename playlists.
/// Returns the typed name, or null if cancelled or left empty.
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
/// Used by the ≡+ button and long-pressing a song.
Future<void> showAddToPlaylist(BuildContext context, Track track) async {
  // Grab the messenger now: the sheet closes before we show the
  // "Added to ..." message, and we still need a valid place to show it.
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

/// The "Import songs" button action: opens the file picker, shows a spinner
/// while copying, then a message like "Imported 3 songs".
Future<void> importSongs(BuildContext context) async {
  final messenger = ScaffoldMessenger.of(context);
  final navigator = Navigator.of(context);
  var spinnerShown = false;

  final result = await Importer.pickAndImport(
    // Called after the user picks files, right before copying starts: show a
    // spinner that can't be dismissed, so they don't leave mid-copy.
    onCopyStart: (count) {
      if (!context.mounted) return; // screen closed while the picker was open
      spinnerShown = true;
      showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (_) => PopScope(
          canPop: false,
          child: AlertDialog(
            content: Row(children: [
              const CircularProgressIndicator(),
              const SizedBox(width: 20),
              Expanded(child: Text('Importing ${plural(count, 'song')}…')),
            ]),
          ),
        ),
      );
    },
  );
  if (spinnerShown) navigator.pop(); // close the spinner

  if (result.cancelled) return;
  final parts = [
    if (result.imported > 0) 'Imported ${plural(result.imported, 'song')}',
    if (result.skipped > 0) '${result.skipped} already in library',
    if (result.failed > 0) '${result.failed} failed (see Debug log)',
  ];
  messenger.showSnackBar(SnackBar(content: Text(parts.join(' • '))));
}

/// "Rename file" (Now Playing ⋯ menu): renames the song's file through the
/// backend's `rename` command, then moves its stats/playlist entries to the
/// new name and rescans.
Future<void> renameSongFile(BuildContext context, Track track) async {
  final messenger = ScaffoldMessenger.of(context);
  final backend = Backend.instance;
  if (!backend.available) {
    messenger.showSnackBar(SnackBar(
        content: Text(backend.unavailableReason ?? 'Backend not available')));
    return;
  }
  // The backend splits commands on spaces, so these files can't be renamed yet.
  if (track.id.contains(' ')) {
    messenger.showSnackBar(const SnackBar(
        content: Text("Can't rename files with spaces in the name yet (backend limitation)")));
    return;
  }

  final oldName = p.posix.basename(track.id);
  final ext = p.extension(oldName);
  final controller = TextEditingController(text: oldName);
  final newName = await showDialog<String>(
    context: context,
    builder: (c) => AlertDialog(
      title: const Text('Rename file'),
      content: Column(mainAxisSize: MainAxisSize.min, children: [
        TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(
            helperText: 'No spaces (use - or _). Stays in the same folder.',
          ),
          onSubmitted: (v) => Navigator.pop(c, v.trim()),
        ),
      ]),
      actions: [
        TextButton(onPressed: () => Navigator.pop(c), child: const Text('Cancel')),
        FilledButton(
            onPressed: () => Navigator.pop(c, controller.text.trim()),
            child: const Text('Rename')),
      ],
    ),
  );
  if (newName == null || newName.isEmpty || newName == oldName) return;

  // Keep the song's extension, or the library would stop seeing it as music.
  final finalName =
      p.extension(newName).toLowerCase() == ext.toLowerCase() ? newName : '$newName$ext';
  if (finalName.contains(' ') || finalName.contains('/')) {
    messenger.showSnackBar(
        const SnackBar(content: Text('Use a name without spaces or slashes')));
    return;
  }

  final ok = await backend.rename(track.id, finalName);
  if (!ok) {
    messenger.showSnackBar(
        const SnackBar(content: Text('Rename failed. See Settings → Debug log')));
    return;
  }
  final folder = p.posix.dirname(track.id);
  final newId = folder == '.' ? finalName : '$folder/$finalName';
  Stats.instance.renameTrack(track.id, newId);
  await Playlists.instance.renameTrack(track.id, newId);
  await Library.instance.scan();
  messenger.showSnackBar(SnackBar(content: Text('Renamed to $finalName')));
}

// ---- Text formatting helpers (covered by tests in test/widget_test.dart) ----

/// 0:05, 3:07, 1:02:03
String formatDuration(Duration? d) {
  if (d == null) return '--:--';
  final h = d.inHours;
  final m = d.inMinutes.remainder(60);
  final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
  return h > 0 ? '$h:${m.toString().padLeft(2, '0')}:$s' : '$m:$s';
}

/// Same as formatDuration but from whole seconds (Track.durationSeconds).
/// 0 means "unknown length".
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

/// "1 play" / "4 plays", "1 song" / "12 songs".
String plural(int n, String word) => '$n ${n == 1 ? word : '${word}s'}';
