import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// The look-and-feel switches in Settings → Appearance. Each one is saved on
/// the phone, and screens showing that part rebuild as soon as it's flipped.
class Appearance extends ChangeNotifier {
  // Singleton: one shared set of choices (Appearance.instance).
  Appearance._();
  static final Appearance instance = Appearance._();

  SharedPreferences? _prefs;

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

  /// Loads the saved choices at startup (everything is on until changed).
  Future<void> init() async {
    _prefs = await SharedPreferences.getInstance();
  }

  bool _get(String name) => _prefs?.getBool('appearance_$name') ?? true;

  void _set(String name, bool on) {
    _prefs?.setBool('appearance_$name', on);
    notifyListeners();
  }
}
