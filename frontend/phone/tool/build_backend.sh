#!/usr/bin/env bash
# Builds Emiliano's Zig backend (backend/client on the `backend` branch) into
# the Android libraries this app loads: android/app/src/main/jniLibs/<abi>/libbackend.so
#
# It does NOT change the backend branch: it checks the branch out into a
# temporary folder (git worktree), compiles backend/client/src/api.zig, copies
# the results here, and deletes the temporary folder.
#
# Why not just `zig build all` from the backend's build.zig? Its Android
# targets aren't linked against Android's C library (libc.so), so phones refuse
# to load the result ("cannot locate symbol __tls_get_addr"). Here we pass the
# Android NDK's libc with `-lc --libc`. Once build.zig does the same, this
# script can go back to `zig build all`.
#
# Needs: git, Zig 0.16.0 (ZIG=path/to/zig to override), Android NDK.
# Usage (from frontend/phone):  bash tool/build_backend.sh [branch-or-commit]
set -euo pipefail

REF="${1:-origin/backend}"
ZIG="${ZIG:-$HOME/.zvm/0.16.0/zig.exe}"
[ -x "$ZIG" ] || ZIG="$(command -v zig)"
API=29   # Android 10+: first version whose libc has __tls_get_addr

APP_DIR="$(cd "$(dirname "$0")/.." && pwd)"
REPO="$(git -C "$APP_DIR" rev-parse --show-toplevel)"
SDK="${ANDROID_HOME:-${LOCALAPPDATA:-$HOME}/Android/Sdk}"
NDK="$(ls -d "$SDK"/ndk/* | sort -V | tail -1)"
SYSROOT="$(ls -d "$NDK"/toolchains/llvm/prebuilt/*/sysroot | head -1)"
command -v cygpath >/dev/null && SYSROOT="$(cygpath -m "$SYSROOT")"

WORK="$(mktemp -d)/backend-src"
git -C "$REPO" fetch -q origin
git -C "$REPO" worktree add -q --detach "$WORK" "$REF"
trap 'git -C "$REPO" worktree remove --force "$WORK"; git -C "$REPO" worktree prune' EXIT
COMMIT="$(git -C "$WORK" rev-parse --short HEAD)"
echo "Building backend from $REF ($COMMIT) with $("$ZIG" version)"

#        jniLibs folder   zig target              NDK lib folder
for row in "arm64-v8a       aarch64-linux-android   aarch64-linux-android" \
           "armeabi-v7a     arm-linux-androideabi   arm-linux-androideabi" \
           "x86_64          x86_64-linux-android    x86_64-linux-android"; do
  read -r ABI TARGET NDKLIB <<<"$row"
  LIBC_FILE="$WORK/libc-$ABI.txt"
  cat > "$LIBC_FILE" <<EOF
include_dir=$SYSROOT/usr/include
sys_include_dir=$SYSROOT/usr/include/$NDKLIB
crt_dir=$SYSROOT/usr/lib/$NDKLIB/$API
msvc_lib_dir=
kernel32_lib_dir=
gcc_dir=
EOF
  OUT="$APP_DIR/android/app/src/main/jniLibs/$ABI"
  mkdir -p "$OUT"
  (cd "$WORK/backend/client" && "$ZIG" build-lib src/api.zig -dynamic -OReleaseFast \
      -target "$TARGET" -lc --libc "$LIBC_FILE" --name backend \
      -femit-bin="$OUT/libbackend.so")
  rm -f "$OUT"/*.o "$OUT"/*.pdb
  echo "  $ABI: $(wc -c < "$OUT/libbackend.so") bytes"
done

sed -i "s/^\*\*Built from:\*\*.*/**Built from:** backend branch commit \`$COMMIT\` ($(date +%Y-%m-%d)) with Zig $("$ZIG" version),/" \
  "$APP_DIR/android/app/src/main/jniLibs/README.md"
echo "Done. Rebuild the app to include the new libraries."
