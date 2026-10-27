#!/usr/bin/env bash
# Builds android/app/src/main/jniLibs/arm64-v8a/libchdman.so: chdman (MAME's CHD
# tool, BSD-3-Clause) as a stripped, position-independent aarch64 executable with
# 16 KB page alignment and static libc++, depending only on libc/libm/libdl.
# ChdService execs it from the app's nativeLibraryDir.
#
#   tool/build_chdman_android.sh [work-dir]      (default: $TMPDIR/chdman-android)
#
# Needs git, cmake, ninja and the pinned NDK under $ANDROID_HOME
# (default ~/Library/Android/sdk): sdkmanager "ndk;28.2.13676358".
set -euo pipefail

SRC_REPO=https://github.com/charlesthobe/chdman.git
SRC_COMMIT=64e7213902c24e02f44ff9c3cf66ac8c4a8fdc05   # 0.238-CBT_edition (mame0238), 2025-06-16
NDK_VERSION=28.2.13676358                               # r28c; its lld already defaults to 16 KB pages
API=24                                                  # flutter.minSdkVersion

ROOT=$(cd "$(dirname "$0")/.." && pwd)
OUT=$ROOT/android/app/src/main/jniLibs/arm64-v8a/libchdman.so
WORK=${1:-${TMPDIR:-/tmp}/chdman-android}
SDK=${ANDROID_HOME:-${ANDROID_SDK_ROOT:-$HOME/Library/Android/sdk}}
NDK=$SDK/ndk/$NDK_VERSION
BIN=$(echo "$NDK"/toolchains/llvm/prebuilt/*/bin)
[ -x "$BIN/clang" ] || { echo "NDK $NDK_VERSION not found at $NDK" >&2; exit 1; }

mkdir -p "$WORK"
[ -d "$WORK/chdman/.git" ] || git clone "$SRC_REPO" "$WORK/chdman"
git -C "$WORK/chdman" checkout --quiet "$SRC_COMMIT"

# The project links -lpthread -lutil on UNIX. bionic has both inside libc and
# the NDK ships neither archive, so empty ones stand in.
mkdir -p "$WORK/stubs"
for lib in pthread util; do
  [ -f "$WORK/stubs/lib$lib.a" ] || "$BIN/llvm-ar" rc "$WORK/stubs/lib$lib.a"
done

cmake -S "$WORK/chdman" -B "$WORK/build" -G Ninja \
  -DCMAKE_TOOLCHAIN_FILE="$NDK/build/cmake/android.toolchain.cmake" \
  -DANDROID_ABI=arm64-v8a \
  -DANDROID_PLATFORM=android-$API \
  -DANDROID_STL=c++_static \
  -DCMAKE_BUILD_TYPE=Release \
  -DCMAKE_EXE_LINKER_FLAGS="-L$WORK/stubs -Wl,-z,max-page-size=16384"
cmake --build "$WORK/build" --target chdman
"$BIN/llvm-strip" -o "$OUT" "$WORK/build/chdman"

# What Play (16 KB pages) and ChdService (PIE, bionic-only deps) require.
ls -l "$OUT"
"$BIN/llvm-readelf" -hlWd "$OUT" | grep -E 'Class:|Type:|Machine:|^ *LOAD|NEEDED'
if "$BIN/llvm-readelf" -lW "$OUT" | grep -E '^ *LOAD' | grep -qvE ' 0x([4-9a-f][0-9a-f]{3}|[0-9a-f]{5,})$'; then
  echo "ERROR: a PT_LOAD segment is aligned below 16 KB" >&2; exit 1
fi
if "$BIN/llvm-readelf" -d "$OUT" | grep NEEDED | grep -vqE '\[lib(c|m|dl)\.so\]'; then
  echo "ERROR: unexpected NEEDED library (only libc/libm/libdl are allowed)" >&2; exit 1
fi
echo "OK: $OUT"
