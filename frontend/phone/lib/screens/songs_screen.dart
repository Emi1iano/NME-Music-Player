import 'package:flutter/material.dart';

import '../models/track.dart';
import '../services/appearance.dart';
import '../services/backend.dart';
import '../services/library.dart';
import '../services/player.dart';
import '../services/stats.dart';
import '../theme.dart';
import '../widgets/artwork.dart';
import '../widgets/common.dart';
import '../widgets/sync_sheet.dart';
import '../widgets/track_tile.dart';
import 'now_playing_screen.dart';
import 'settings_screen.dart';

/// Landing page: settings, refresh, sort, search, Play / Shuffle, song list.
class SongsScreen extends StatefulWidget {
  const SongsScreen({super.key});

  @override
  State<SongsScreen> createState() => _SongsScreenState();
}

class _SongsScreenState extends State<SongsScreen> {
  final _search = TextEditingController(); // holds the search box text
  String _query = '';
  final _scroll = ScrollController();      // the song list (for the A–Z scroller)
  final _headerKey = GlobalKey();          // the "Recently added/played" rows above the songs

  // Every song row is exactly this tall (row + 1 divider), so the A–Z
  // scroller can work out where a letter starts without building every row.
  double get _rowExtent => Appearance.instance.compactRows ? 61 : 73;

  /// Songs whose title, artist or album contains the search text.
  List<Track> _filtered(Library library) {
    final q = _query.trim().toLowerCase();
    if (q.isEmpty) return library.tracks;
    return library.tracks
        .where((t) =>
            t.title.toLowerCase().contains(q) ||
            library.artistName(t.artistId).toLowerCase().contains(q) ||
            library.albumTitle(t.albumId).toLowerCase().contains(q))
        .toList();
  }

  // Controllers must be disposed when the screen goes away to free memory.
  @override
  void dispose() {
    _search.dispose();
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final library = Library.instance;
    final player = Player.instance;

    // SafeArea keeps content out from under the notch/status bar.
    return SafeArea(
      bottom: false,
      // Rebuilds this whole screen whenever the Library changes
      // (scan finished, sort changed, ...).
      child: ListenableBuilder(
        // Also rebuild when an Appearance switch changes.
        listenable: Listenable.merge([library, Appearance.instance]),
        builder: (context, _) {
          final tracks = _filtered(library);
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _TopBar(library: library),
              LibrarySearchBar(
                controller: _search,
                hint: 'Search songs, artists, albums',
                onChanged: (v) => setState(() => _query = v),
              ),
              PlayShuffleButtons(
                onPlay: tracks.isEmpty
                    ? null
                    : () => player.playTracks(tracks, index: 0, shuffle: false),
                onShuffle: tracks.isEmpty ? null : () => player.playTracks(tracks, shuffle: true),
              ),
              // "24 songs • 1 hr 32 min" for the list below (or the matches).
              if (tracks.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 4),
                  child: Text(
                    _countLine(tracks),
                    style: const TextStyle(color: AppColors.textSecondary, fontSize: 13),
                  ),
                ),
              Expanded(child: _buildList(context, library, tracks)),
            ],
          );
        },
      ),
    );
  }

  /// "24 songs • 1 hr 32 min" (length left out if no song knows its length).
  String _countLine(List<Track> tracks) {
    final seconds = tracks.fold(0, (sum, t) => sum + t.durationSeconds);
    final count = plural(tracks.length, 'song');
    return seconds > 0 ? '$count  •  ${formatListenTime(seconds)}' : count;
  }

  /// The song list, or a spinner / empty message / "No matches" instead.
  Widget _buildList(BuildContext context, Library library, List<Track> tracks) {
    if (library.scanning && library.tracks.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }
    if (library.tracks.isEmpty) return _EmptyLibrary(library: library);
    if (tracks.isEmpty) {
      return const Center(
        child: Text('No matches', style: TextStyle(color: AppColors.textSecondary)),
      );
    }

    final player = Player.instance;
    final showPlays = library.sortMode == SortMode.mostPlayed;
    final searching = _query.trim().isNotEmpty;
    // The A–Z scroller only makes sense for alphabetical lists of some size.
    final alphabetical =
        library.sortMode == SortMode.title || library.sortMode == SortMode.artist;
    final appearance = Appearance.instance;
    final showScroller =
        appearance.letterScroller && alphabetical && !searching && tracks.length >= 12;

    // RefreshIndicator = pull down to rescan the Music folder.
    final list = RefreshIndicator(
      onRefresh: library.scan,
      // StreamBuilder rebuilds when the current song changes, so the playing
      // song is highlighted in the list.
      child: StreamBuilder<Track?>(
        stream: player.currentTrackStream,
        initialData: player.currentTrack,
        builder: (context, snapshot) => CustomScrollView(
          controller: _scroll,
          slivers: [
            if (!searching && appearance.recentRows)
              SliverToBoxAdapter(child: _RecentRows(key: _headerKey, library: library)),
            // Fixed-height rows: only the ones on screen are built, so it
            // stays fast even with thousands of songs.
            SliverFixedExtentList(
              itemExtent: _rowExtent,
              delegate: SliverChildBuilderDelegate(
                childCount: tracks.length,
                (context, i) {
                  final track = tracks[i];
                  return Column(children: [
                    SizedBox(
                      height: _rowExtent - 1,
                      child: _SwipeActions(
                        track: track,
                        child: TrackTile(
                          track: track,
                          isCurrent: snapshot.data?.id == track.id,
                          trailing: showPlays
                              ? Text(plural(Stats.instance.of(track.id).playCount, 'play'),
                                  style: const TextStyle(color: AppColors.textSecondary))
                              : null,
                          // Tap: play the list starting at this song and open Now Playing.
                          onTap: () {
                            player.playTracks(tracks, index: i);
                            openNowPlaying(context);
                          },
                          // Long-press: Play next / Add to queue / ... / Delete.
                          onLongPress: () => showSongActions(context, track),
                        ),
                      ),
                    ),
                    const Divider(height: 1, indent: 80, endIndent: 16),
                  ]);
                },
              ),
            ),
            const SliverToBoxAdapter(child: SizedBox(height: 8)),
          ],
        ),
      ),
    );
    if (!showScroller) return list;

    // First row of each letter (by title, or by artist when sorted by artist).
    final starts = <String, int>{};
    for (final (i, t) in tracks.indexed) {
      final name = library.sortMode == SortMode.artist ? library.artistName(t.artistId) : t.title;
      starts.putIfAbsent(_letterOf(name), () => i);
    }
    return Stack(children: [
      list,
      Positioned(
        right: 0,
        top: 0,
        bottom: 0,
        child: _LetterScroller(
          letters: starts.keys.toList(),
          onLetter: (letter) {
            final header = (_headerKey.currentContext?.findRenderObject() as RenderBox?)?.size.height ?? 0;
            final target = header + starts[letter]! * _rowExtent;
            _scroll.jumpTo(target.clamp(0, _scroll.position.maxScrollExtent));
          },
        ),
      ),
    ]);
  }

  /// "A".."Z" for a name starting with a letter (accents dropped by
  /// uppercasing only), "#" for anything else.
  static String _letterOf(String name) {
    final t = name.trim();
    if (t.isEmpty) return '#';
    final c = t[0].toUpperCase();
    return RegExp(r'[A-Z]').hasMatch(c) ? c : '#';
  }
}

/// Swipe a song row: right = Play next, left = Delete (with Undo).
/// The row snaps back either way; a deleted song disappears from the list
/// by itself.
class _SwipeActions extends StatelessWidget {
  final Track track;
  final Widget child;
  const _SwipeActions({required this.track, required this.child});

  @override
  Widget build(BuildContext context) {
    if (!Appearance.instance.swipeActions) return child; // turned off in Settings
    Widget background(
            Alignment align, Color color, Color ink, IconData icon, String label) =>
        Container(
          color: color,
          alignment: align,
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Icon(icon, color: ink),
            const SizedBox(width: 8),
            Text(label, style: TextStyle(color: ink, fontWeight: FontWeight.w600)),
          ]),
        );
    return Dismissible(
      key: ValueKey('swipe:${track.id}'),
      background: background(Alignment.centerLeft, AppColors.accent, AppColors.onAccent,
          Icons.queue_play_next_rounded, 'Play next'),
      secondaryBackground: background(Alignment.centerRight, Colors.redAccent, Colors.white,
          Icons.delete_outline_rounded, 'Delete'),
      confirmDismiss: (direction) async {
        Appearance.instance.vibrate();
        if (direction == DismissDirection.startToEnd) {
          Player.instance.playNext(track);
          ScaffoldMessenger.of(context)
              .showSnackBar(SnackBar(content: Text('${track.title} plays next')));
        } else {
          deleteSong(context, track); // hides it right away, Undo for 5 s
        }
        return false; // snap back; the library updates the list
      },
      child: child,
    );
  }
}

/// The A–Z strip on the right edge of the Songs list: tap or drag along it to
/// jump to a letter. Shows a bubble with the letter while dragging.
class _LetterScroller extends StatefulWidget {
  final List<String> letters;
  final ValueChanged<String> onLetter;
  const _LetterScroller({required this.letters, required this.onLetter});

  @override
  State<_LetterScroller> createState() => _LetterScrollerState();
}

class _LetterScrollerState extends State<_LetterScroller> {
  String? _active; // letter under the finger (null: not touching)

  void _pick(double dy, double height) {
    final letters = widget.letters;
    final i = (dy / height * letters.length).floor().clamp(0, letters.length - 1);
    if (letters[i] == _active) return;
    Appearance.instance.vibrate(tick: true);
    setState(() => _active = letters[i]);
    widget.onLetter(letters[i]);
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, constraints) {
      final height = constraints.maxHeight;
      return Row(mainAxisSize: MainAxisSize.min, children: [
        // The bubble next to the strip while dragging.
        if (_active != null)
          Container(
            width: 56,
            height: 56,
            margin: const EdgeInsets.only(right: 8),
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: AppColors.accent,
              borderRadius: BorderRadius.circular(28),
            ),
            child: Text(_active!,
                style: TextStyle(
                    color: AppColors.onAccent, fontSize: 26, fontWeight: FontWeight.w800)),
          ),
        GestureDetector(
          behavior: HitTestBehavior.opaque,
          onVerticalDragStart: (d) => _pick(d.localPosition.dy, height),
          onVerticalDragUpdate: (d) => _pick(d.localPosition.dy, height),
          onVerticalDragEnd: (_) => setState(() => _active = null),
          onTapDown: (d) => _pick(d.localPosition.dy, height),
          onTapUp: (_) => setState(() => _active = null),
          child: SizedBox(
            width: 24,
            child: Column(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                for (final l in widget.letters)
                  Text(l,
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: l == _active ? AppColors.accent : AppColors.textSecondary,
                      )),
              ],
            ),
          ),
        ),
      ]);
    });
  }
}

/// "Recently added" and "Recently played": rows of covers you scroll
/// sideways, above the song list. Tap to play, hold for the song menu.
class _RecentRows extends StatelessWidget {
  final Library library;
  const _RecentRows({super.key, required this.library});

  @override
  Widget build(BuildContext context) {
    final added = [...library.tracks]
      ..sort((a, b) => (b.dateAdded ?? DateTime(0)).compareTo(a.dateAdded ?? DateTime(0)));
    final played = [
      for (final s in Stats.instance.all.where((s) => s.lastPlayed != null).toList()
        ..sort((a, b) => b.lastPlayed!.compareTo(a.lastPlayed!)))
        ?library.trackById(s.trackId), // skip songs no longer in the library
    ];
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      _CoverRow(title: 'Recently added', tracks: added.take(10).toList()),
      if (played.isNotEmpty) _CoverRow(title: 'Recently played', tracks: played.take(10).toList()),
      const Padding(
        padding: EdgeInsets.fromLTRB(16, 8, 16, 0),
        child: Text('All songs', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
      ),
    ]);
  }
}

class _CoverRow extends StatelessWidget {
  final String title;
  final List<Track> tracks;
  const _CoverRow({required this.title, required this.tracks});

  static const _art = 120.0;

  @override
  Widget build(BuildContext context) {
    final library = Library.instance;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
        child: Text(title, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
      ),
      SizedBox(
        height: _art + 44,
        child: ListView.separated(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 16),
          itemCount: tracks.length,
          separatorBuilder: (_, _) => const SizedBox(width: 12),
          itemBuilder: (context, i) {
            final track = tracks[i];
            return GestureDetector(
              onTap: () {
                Player.instance.playTracks(tracks, index: i, shuffle: false);
                openNowPlaying(context);
              },
              onLongPress: () => showSongActions(context, track),
              child: SizedBox(
                width: _art,
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Stack(children: [
                    Artwork(imagePath: track.artworkPath, size: _art, radius: 8, name: track.title),
                    if (library.isNew(track.id) && Appearance.instance.newTags)
                      const Positioned(left: 6, top: 6, child: NewTag()),
                  ]),
                  const SizedBox(height: 6),
                  Text(track.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
                  Text(library.artistName(track.artistId),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(color: AppColors.textSecondary, fontSize: 12)),
                ]),
              ),
            );
          },
        ),
      ),
    ]);
  }
}

/// Settings button on the left; refresh and sort buttons on the right.
class _TopBar extends StatelessWidget {
  final Library library;
  const _TopBar({required this.library});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: Row(
        children: [
          IconButton(
            tooltip: 'Settings',
            icon: const Icon(Icons.settings_rounded),
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const SettingsScreen()),
            ),
          ),
          const Spacer(),
          IconButton(
            tooltip: 'Import songs',
            icon: const Icon(Icons.add_rounded),
            onPressed: () => importSongs(context),
          ),
          // Sync with another device (the library rescans by itself: at
          // startup, when you come back to the app, and after imports).
          ListenableBuilder(
            listenable: Backend.instance,
            builder: (context, _) {
              final backend = Backend.instance;
              final busy = backend.isSyncing;
              // The badge counts changes the next sync will send.
              final pending = backend.pendingChanges;
              return IconButton(
                tooltip: busy
                    ? 'Syncing…'
                    : pending > 0
                        ? 'Sync ($pending waiting)'
                        : 'Sync',
                icon: Badge(
                  isLabelVisible: pending > 0 && !busy,
                  label: Text(pending > 99 ? '99+' : '$pending'),
                  backgroundColor: AppColors.accent,
                  textColor: AppColors.onAccent,
                  child: _SyncIcon(spinning: busy),
                ),
                onPressed: () => showSyncSheet(context),
              );
            },
          ),
          PopupMenuButton<SortMode>(
            tooltip: 'Sort',
            icon: const Icon(Icons.swap_vert_rounded),
            initialValue: library.sortMode,
            onSelected: library.setSortMode,
            itemBuilder: (_) => [
              for (final mode in SortMode.values)
                CheckedPopupMenuItem(
                  value: mode,
                  checked: mode == library.sortMode,
                  child: Text(mode.label),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

/// The sync arrows; they turn while a sync is running.
class _SyncIcon extends StatefulWidget {
  final bool spinning;
  const _SyncIcon({required this.spinning});

  @override
  State<_SyncIcon> createState() => _SyncIconState();
}

class _SyncIconState extends State<_SyncIcon> with SingleTickerProviderStateMixin {
  late final _turn = AnimationController(vsync: this, duration: const Duration(milliseconds: 1200));

  @override
  void initState() {
    super.initState();
    if (widget.spinning) _turn.repeat();
  }

  @override
  void didUpdateWidget(_SyncIcon old) {
    super.didUpdateWidget(old);
    if (widget.spinning && !_turn.isAnimating) {
      _turn.repeat();
    } else if (!widget.spinning && _turn.isAnimating) {
      // Finish the current turn so the arrows don't stop at an odd angle.
      _turn.forward().then((_) => _turn.reset());
    }
  }

  @override
  void dispose() {
    _turn.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return RotationTransition(
      turns: Tween(begin: 0.0, end: -1.0).animate(_turn),
      child: Icon(Icons.sync_rounded, color: widget.spinning ? AppColors.accent : null),
    );
  }
}

/// Shown when the Music folder has no songs yet: explains how to add some.
class _EmptyLibrary extends StatelessWidget {
  final Library library;
  const _EmptyLibrary({required this.library});

  @override
  Widget build(BuildContext context) {
    return RefreshIndicator(
      onRefresh: library.scan,
      child: ListView(
        padding: const EdgeInsets.all(32),
        children: [
          const SizedBox(height: 40),
          const Icon(Icons.library_music_rounded, size: 64, color: AppColors.textSecondary),
          const SizedBox(height: 16),
          const Text('No music yet',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700)),
          const SizedBox(height: 8),
          const Text(
            'Import songs from your phone (Downloads, Drive, Files...) '
            'and they\'ll show up here.',
            textAlign: TextAlign.center,
            style: TextStyle(color: AppColors.textSecondary, height: 1.4),
          ),
          const SizedBox(height: 24),
          // The main way to add music: no computer needed.
          Center(
            child: FilledButton.icon(
              onPressed: () => importSongs(context),
              icon: const Icon(Icons.add_rounded),
              label: const Text('Import songs'),
            ),
          ),
          const SizedBox(height: 32),
          // The old way still works, for people copying from a computer.
          Text(
            'Or: ${howToAddMusic()}',
            textAlign: TextAlign.center,
            style: const TextStyle(color: AppColors.textSecondary, fontSize: 12, height: 1.4),
          ),
          const SizedBox(height: 8),
          Center(
            child: TextButton.icon(
              onPressed: library.scan,
              icon: const Icon(Icons.refresh_rounded),
              label: const Text('Scan again'),
            ),
          ),
        ],
      ),
    );
  }
}
