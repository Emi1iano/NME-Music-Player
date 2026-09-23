# NME — Flutter client scaffold

This is the shared Flutter/Dart client for NME, targeting Windows first
(and later iOS/Android from the same codebase, per the project proposal).

## Getting this running

1. Install the Flutter SDK (stable channel) and make sure `flutter doctor`
   is happy — on Windows it needs Visual Studio with the "Desktop
   development with C++" workload, since that's what actually compiles
   the native Windows shell around your Dart code.
2. Unzip this into your repo (or copy `lib/` and `pubspec.yaml` into an
   existing `flutter create` project).
3. Enable the Windows desktop target and generate platform folders:
   ```
   flutter config --enable-windows-desktop
   flutter create --platforms=windows .
   ```
   (This second command adds a `windows/` folder with the native runner —
   it's generated, don't hand-edit it unless you need custom window
   behavior like a frameless title bar later.)
4. Install dependencies:
   ```
   flutter pub get
   ```
5. Run it:
   ```
   flutter run -d windows
   ```

## What's here vs. what's next

Everything currently renders from **hard-coded sample data**
(`lib/data/sample_data.dart`) so you can build and demo the UI before the
Zig server + sync protocol exist. Structure:

- `lib/theme/` — colors/type tokens, ported from the HTML mockup
- `lib/models/` — `Track`, `Playlist`
- `lib/widgets/` — reusable pieces: sidebar nav, transport/player bar
- `lib/screens/` — Library, Playlists, Sync & Settings
- `lib/shell/app_shell.dart` — owns navigation + now-playing state

To wire up real data, add an `lib/data/nme_api_client.dart` that talks to
your Zig server (probably over WebSocket for live sync events, or REST for
one-off requests — see `pubspec.yaml` for suggested packages), and swap
`sampleTracks` / `samplePlaylists` for real fetched data. Keep that as its
own layer so the mobile app can reuse the same client class later.

## Team workflow note

Since this is one shared codebase for both Windows and (eventually)
mobile, agree on a branching convention before multiple people start
editing `lib/` at once — e.g. one feature branch per screen or per sync
feature, merged via PR, so two people aren't fighting over the same
widget files.
