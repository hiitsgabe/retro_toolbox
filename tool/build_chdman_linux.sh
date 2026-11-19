#!/usr/bin/env bash
# Builds assets/chdman/linux/chdman: chdman (MAME's CHD tool, BSD-3-Clause) as a
# stripped x86_64 executable with static libstdc++/libgcc, depending only on
# glibc. Same source and patch as tool/build_chdman_android.sh.
#
#   tool/build_chdman_linux.sh [work-dir]      (default: $TMPDIR/chdman-linux)
#
# Needs git, cmake, ninja and g++. Run it on Ubuntu 24.04 (the release's
# build-linux runner): the binary needs the glibc it was built against or newer.
#
# Distro mame-tools links chdman against SDL2, so shipping that one drags in
# ~50 libs (PulseAudio, X11, Wayland) and a 119 MB apt install on every release.
set -euo pipefail

SRC_REPO=https://github.com/charlesthobe/chdman.git
SRC_COMMIT=64e7213902c24e02f44ff9c3cf66ac8c4a8fdc05   # 0.238-CBT_edition (mame0238), 2025-06-16

ROOT=$(cd "$(dirname "$0")/.." && pwd)
DEST=$ROOT/assets/chdman/linux
WORK=${1:-${TMPDIR:-/tmp}/chdman-linux}

mkdir -p "$WORK"
[ -d "$WORK/chdman/.git" ] || git clone "$SRC_REPO" "$WORK/chdman"
git -C "$WORK/chdman" checkout --quiet "$SRC_COMMIT"
# MAME 0.238 predates createdvd/extractdvd (MAME 0.256), which ChdService runs
# for .iso (PS2/PSP). Backport them onto a clean tree.
git -C "$WORK/chdman" reset --quiet --hard
git -C "$WORK/chdman" apply "$ROOT/tool/chdman-createdvd.patch"

# The fork's CMake never defines LSB_FIRST, so without it MAME code assumes
# big-endian and upstream `chdman verify` rejects every CHD made here.
cmake -S "$WORK/chdman" -B "$WORK/build" -G Ninja \
  -DCMAKE_BUILD_TYPE=Release \
  -DCMAKE_C_FLAGS=-DLSB_FIRST -DCMAKE_CXX_FLAGS=-DLSB_FIRST \
  -DCMAKE_EXE_LINKER_FLAGS="-static-libstdc++ -static-libgcc"
cmake --build "$WORK/build" --target chdman

rm -f "$DEST"/*
mkdir -p "$DEST"
strip -o "$DEST/chdman" "$WORK/build/chdman"
echo chdman > "$DEST/manifest.txt"

ls -l "$DEST"
readelf -d "$DEST/chdman" | grep NEEDED
if readelf -d "$DEST/chdman" | grep NEEDED | grep -vqE '\[(libc|libm|libpthread|libdl|librt|libutil)\.so\.[0-9]+\]|\[ld-linux-x86-64\.so\.2\]'; then
  echo "ERROR: unexpected NEEDED library (only glibc is allowed)" >&2; exit 1
fi
echo "glibc symbols needed up to: $(objdump -T "$DEST/chdman" | grep -oE 'GLIBC_[0-9.]+' | sort -uV | tail -1)"
echo "OK: $DEST/chdman"
