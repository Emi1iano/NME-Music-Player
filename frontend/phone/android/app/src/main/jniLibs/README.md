# Native backend libraries (Emiliano's Zig client)

`libbackend.so` is Emiliano's Zig client (`backend/NetworksButBetter/backend/src`,
merged in from his **backend** branch), compiled for Android. The app calls its single exported
function through Dart FFI (see `lib/services/backend.dart`):

```c
int32_t clientAPI(const char* command); // 0 = ok, -1 = error
```

| Folder | Phones |
|---|---|
| `arm64-v8a/` | almost all modern phones |
| `armeabi-v7a/` | older 32-bit phones |
| `x86_64/` | the Android emulator |

**Built from:** `backend/NetworksButBetter/backend/src` in this branch (last source change `1b35d86`) on 2026-10-06 with Zig 0.16.0,

## Updating after backend changes

The backend source lives in this branch at `backend/NetworksButBetter/backend/src`
(set `BACKEND_SRC=backend/client/src` to build the older client). To get
Emiliano's latest work and rebuild, from the repo root:

```bash
git fetch origin && git merge origin/backend
cd frontend/phone && bash tool/build_backend.sh
```

**Why not the backend's `zig build all`?** Its Android targets aren't linked
against Android's C library, so phones refuse to load them
(`dlopen failed: cannot locate symbol "__tls_get_addr"`). The script passes the
NDK's libc (`-lc --libc ...`). Libraries need **Android 10+** (API 29) for the
same reason; on older phones the app works but Sync shows as unavailable.
