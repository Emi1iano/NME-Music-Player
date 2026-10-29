import 'package:flutter/material.dart' show Color;
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show HapticFeedback;
import 'package:shared_preferences/shared_preferences.dart';

/// The look-and-feel switches in Settings → Appearance. Each one is saved on
/// the phone, and screens showing that part rebuild as soon as it's flipped.
class Appearance extends ChangeNotifier {
  // Singleton: one shared set of choices (Appearance.instance).
  Appearance._();
  static final Appearance instance = Appearance._();

  SharedPreferences? _prefs;

  /// The app's main color choices (Settings → Appearance → Accent color).
  /// All are light enough to stand out on the dark background.
  static const accentChoices = <(String, Color)>[
    ('Purple', Color(0xFF8B7CFF)),
    ('Blue', Color(0xFF5B9DFF)),
    ('Teal', Color(0xFF2EC4B6)),
    ('Green', Color(0xFF4CC36B)),
    ('Orange', Color(0xFFFF8A3D)),
    ('Pink', Color(0xFFFF6FAE)),
    ('Red', Color(0xFFFF5C5C)),
  ];

  /// The app's main color (buttons, highlights, the playing song...).
  Color get accent => Color(_prefs?.getInt('appearance_accent') ?? accentChoices.first.$2.toARGB32());
  set accent(Color color) {
    _prefs?.setInt('appearance_accent', color.toARGB32());
    notifyListeners();
  }

  /// Now Playing's background takes the color of the song's cover.
  bool get coverColors => _get('coverColors');
  set coverColors(bool on) => _set('coverColors', on);

  /// The mini player's cover grows into Now Playing's when it opens.
  bool get coverAnimation => _get('coverAnimation');
  set coverAnimation(bool on) => _set('coverAnimation', on);

  /// Playlist pictures are a 2x2 grid of their first four songs' covers.
  bool get playlistGrid => _get('playlistGrid');
  set playlistGrid(bool on) => _set('playlistGrid', on);

  /// "Recently added" / "Recently played" rows at the top of the Songs tab.
  bool get recentRows => _get('recentRows');
  set recentRows(bool on) => _set('recentRows', on);

  /// The A–Z strip on the right edge of the Songs tab.
  bool get letterScroller => _get('letterScroller');
  set letterScroller(bool on) => _set('letterScroller', on);

  /// Songs without cover art get a colored tile with their first letter
  /// (off: a plain grey music note).
  bool get letterTiles => _get('letterTiles');
  set letterTiles(bool on) => _set('letterTiles', on);

  /// Swipe a song row: right for Play next, left for Delete.
  bool get swipeActions => _get('swipeActions');
  set swipeActions(bool on) => _set('swipeActions', on);

  /// "NEW" tags on songs that arrived by sync and haven't been played.
  bool get newTags => _get('newTags');
  set newTags(bool on) => _set('newTags', on);

  /// Light vibration on long-press, swipes, delete and sync complete.
  bool get vibration => _get('vibration');
  set vibration(bool on) => _set('vibration', on);

  /// Smaller song rows (more songs on screen). Off by default.
  bool get compactRows => _get('compactRows', fallback: false);
  set compactRows(bool on) => _set('compactRows', on);

  /// Loads the saved choices at startup (everything except compact rows is
  /// on until changed).
  Future<void> init() async {
    _prefs = await SharedPreferences.getInstance();
  }

  /// A light vibration, if "Vibration" is on. [tick] is the tiny one used
  /// while dragging along the A–Z scroller.
  void vibrate({bool tick = false}) {
    if (!vibration) return;
    tick ? HapticFeedback.selectionClick() : HapticFeedback.mediumImpact();
  }

  bool _get(String name, {bool fallback = true}) =>
      _prefs?.getBool('appearance_$name') ?? fallback;

  void _set(String name, bool on) {
    _prefs?.setBool('appearance_$name', on);
    notifyListeners();
  }
}
