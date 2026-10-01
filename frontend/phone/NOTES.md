# NME Music: mobile app notes

Flutter app for Android (iOS-ready, not built yet) in `frontend/phone`, branch
`feat/mobile-ui-setup`. Version 1.2.0. Owner: Nedved (mobile). Backend: Emiliano
(Zig, branch `backend`). Windows app: Mariano (`feat/window-ui-setup`).

## What the app does
- **Library:** Songs, Albums, Artists and Playlists tabs, built from song tags
  (title, artist, album, year, track number, cover art). Search and sort.
- **Playback:** Now Playing (seek, shuffle, repeat, queue), a mini player, and
  background playback with lock-screen and notification controls.
- **Import songs (+):** pick audio files from the phone and copy them into the
  library. The library also rescans by itself: at startup, when you come back
  to the app, and after imports.
- **Listening stats:** play count, time listened and last played per song,
  using the `PlaybackStats` model. A play counts after 30 s, or half of a short
  song.
- **Sync (button at the top right of Songs):** shows this phone's key; Sync now,
  Cancel sync, and Use another device's key.
- **Debug log (Settings → Debug log):** app events, errors, crashes and the
  backend's own messages. Share/Copy buttons, plus a terminal icon to run any
  backend command.

## Code map (`lib/`)
| Folder | What's there |
|---|---|
| `models/` | Track, Album, Artist, Playlist, PlaybackStats (with `fromMap`/`toMap`) |
| `services/library.dart` | scans the music folder, reads tags, builds the models |
| `services/player.dart` | playback and play-count/playtime tracking |
| `services/backend.dart` | **bridge to Emiliano's `libbackend.so`** (Dart FFI) |
| `services/stats.dart`, `playlists.dart` | saved to JSON on the phone |
| `services/importer.dart` | Import songs |
| `services/app_log.dart` | Debug log |
| `screens/`, `widgets/` | UI (`widgets/sync_sheet.dart` is the Sync panel) |

## Run / build
```bash
cd frontend/phone
flutter pub get
flutter emulators --launch Pixel_Test
flutter run -d emulator-5554                  # r = hot reload, q = quit
flutter analyze
flutter test
flutter build apk --release --split-per-abi   # arm64 APK is the one for phones
```
- **Emulator `Pixel_Test`:** x86_64, Android 15. It can also run arm64 apps.
  - If it won't start ("exited with code 1"), close it and delete the stale
    lock files: `~/.android/avd/Pixel_Test.avd/*.lock`.
  - Emulator audio plays too fast, so songs end early. That's the emulator, not
    the app.
- **Debug vs release builds:** `flutter run` installs a debug build. A release
  APK can't install over it (different signing key) without uninstalling first.
- **Release signing:** the key is in `C:\Users\nedve\.nme-music-keys\` and
  `android/key.properties`. Both are deliberately **not in git**; there's a
  backup in Documents. Without them, release builds use the debug key.

## The backend (Emiliano's Zig code)
- **The app calls one C function:** `int32_t clientAPI(const char* command)`,
  which returns 0 or -1.
  - `sync_new_key`: works.
  - `sync [key]`: works, but is experimental; see below.
  - `add [path]` and `rename [path] [newname]`: the app calls them as
    specified. The backend still prints "not implemented".
- **Source:** `backend/NetworksButBetter/backend/src/` (merged from `backend`).
- **Rebuild the Android libraries** after merging new backend work:
  ```bash
  git fetch origin && git merge origin/backend
  cd frontend/phone && bash tool/build_backend.sh     # needs Zig 0.16.0
  ```
  The script links the NDK's libc. **The backend's own builds don't, so they
  fail on Android** with `dlopen failed: cannot locate symbol "__tls_get_addr"`.
  Android 10+ is required.
- **Folders the backend uses on the phone**
  (`Android/data/com.example.phone/files/`):
  - `music/`: the songs.
  - `testing/app/key.txt`: the sync key (it becomes `app/key.txt` when the
    backend's `TESTING` flag is turned off).

### How sync works in the app
- **Sync runs in its own background isolate,** because the backend's `sync`
  never returns.
- **Its stdin is a pipe that stays open,** so the backend's input loop waits
  instead of spinning.
- **Other commands are skipped while syncing.** Every command replaces the
  backend's shared `clientState` and closes its socket, which would cut the
  sync.
- **"Use another device's key"** writes the key file itself, because the
  backend's `sync [key]` doesn't apply the key yet.
- **Cancel sync** (the backend has no stop call) uses the backend's own
  disconnect path:
  1. Find its UDP socket (port 32145 and up) with `getsockname`.
  2. If it's still waiting for the server, send it a pairing message pointing
     at a local socket, and ACK its punching.
  3. Write `EXIT` to its stdin, and send `EXIT` packets until `sync` returns.

### Known backend issues (for Emiliano)
1. **Android builds need libc linked** (`-lc` plus an NDK libc file in
   `build.zig`).
2. **`add` and `rename` aren't implemented** in the new client.
3. **Commands are split on spaces,** so file names with spaces can't be used.
   The app skips those files.
4. **`sync [key]` ignores the key** it's given.
5. **The global `clientState` is replaced on every command,** and
   `ClientState.init` uses `catch unreachable` (a crash in release builds).
6. **The server keeps stale registrations,** and pairs a client with its own old
   session.
7. **The client accepts the pairing message from any sender.**
8. **There's no stop command for `sync`;** a `sync_stop` would be cleaner.

## Next steps
- Real two-device sync test with the server running.
- Wire up `add`/`rename` results once the backend implements them, and send
  play counts (`update [path] playcount/playtime`) once those exist.
- iPhone: needs an iOS backend build and the teammate with the Mac.
- Shared models/bridge with Mariano's Windows app.
