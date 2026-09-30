# Native backend libraries (Emiliano's Zig client)

`libbackend.so` is the Zig sync/library client from `backend/client` on the
**backend** branch, compiled for Android. The app calls its single exported
function through Dart FFI (see `lib/services/backend.dart`):

```c
int32_t clientAPI(const char* command); // 0 = ok, -1 = error
```

| Folder | Phones |
|---|---|
| `arm64-v8a/` | almost all modern phones |
| `armeabi-v7a/` | older 32-bit phones |
| `x86_64/` | the Android emulator |

**Built from:** backend branch commit `d408db0` (2026-09-30) with Zig 0.16.0,
compiled by `tool/build_backend.sh` (the backend's own source, unmodified).

## Updating after backend changes

From `frontend/phone`:

```bash
bash tool/build_backend.sh            # latest origin/backend
bash tool/build_backend.sh 1a2b3c4    # or a specific commit
```

The script checks the backend branch out into a temporary folder (it never
changes that branch), builds all three libraries and copies them here.

**Why not the backend's `zig build all`?** Its Android targets aren't linked
against Android's C library, so phones refuse to load them
(`dlopen failed: cannot locate symbol "__tls_get_addr"`). The script passes the
NDK's libc (`-lc --libc ...`). Libraries need **Android 10+** (API 29) for the
same reason; on older phones the app works but Sync shows as unavailable.
