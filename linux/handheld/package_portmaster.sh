#!/bin/bash
# Builds the PortMaster zip from the port that handheld.yml assembles in
# dist/ports/. Unzip it into the device's ports/ folder (or drop it in
# PortMaster's autoinstall/):
#   Retro Toolbox.sh
#   retrotoolbox/  (the app + port.json, README.md, gameinfo.xml,
#                   screenshot.png, licenses/)
# Never ships a catalog. Needs dpkg (Debian/Ubuntu): the bundled libraries'
# licenses come from the packages they were copied from.
# Usage: package_portmaster.sh <ports dir> <out.zip> <flutter-pi source dir>
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/../.." && pwd)
SRC=$(cd "$1" && pwd)
OUT=$(cd "$(dirname "$2")" && pwd)/$(basename "$2")
FPI=$3
META="$ROOT/linux/handheld/portmaster"
STAGE=$(mktemp -d)
trap 'rm -rf "$STAGE"' EXIT

cp -R "$SRC/." "$STAGE/"
P="$STAGE/retrotoolbox"
[ -f "$STAGE/Retro Toolbox.sh" ] && [ -f "$P/flutter-pi" ] || { echo "not a built port: $SRC" >&2; exit 1; }
cp "$META/port.json" "$META/README.md" "$META/gameinfo.xml" "$META/screenshot.png" "$P/"
C="$P/data/flutter_assets/assets/catalog/consoles.json"
[ -f "$C" ] && echo '[]' > "$C"

L="$P/licenses"
mkdir -p "$L"
cp "$ROOT/LICENSE" "$L/retrotoolbox.LICENSE"
cp "$ROOT/third_party/smb_connect/LICENSE" "$L/smb_connect.LICENSE"
cp "$ROOT/third_party/ftpconnect/LICENSE" "$L/ftpconnect.LICENSE"
cp "$FPI/LICENSE" "$L/flutter-pi.LICENSE"
# Flutter's engine, framework and Dart packages: data/flutter_assets/NOTICES.Z.
for d in "$P"/site-packages/*.dist-info; do
  n=$(basename "$d" .dist-info)
  find "$d" -type f \( -iname 'LICEN[CS]E*' -o -iname 'COPYING*' \) -exec sh -c 'cp "$1" "$2.$(basename "$1")"' _ {} "$L/${n%%-[0-9]*}" \;
done
# The bundled CPython's license, else the build host's (same PSF text).
PY=$(find "$P" -name LICENSE.txt -path '*python3*' | head -1)
[ -n "$PY" ] || PY=$(ls /usr/lib/python3*/LICENSE.txt 2>/dev/null | head -1)
[ -n "$PY" ] || { echo "no Python LICENSE.txt found" >&2; exit 1; }
cp "$PY" "$L/python.LICENSE"
for lib in "$P"/bundled_libs/*; do
  name=$(basename "$lib")
  pkg=$(dpkg -S "/usr/lib/aarch64-linux-gnu/$name" "/lib/aarch64-linux-gnu/$name" 2>/dev/null | head -1 | cut -d: -f1 || true)
  [ -n "$pkg" ] && [ -e "/usr/share/doc/$pkg/copyright" ] || { echo "no license found for $name" >&2; exit 1; }
  cp -L "/usr/share/doc/$pkg/copyright" "$L/$pkg.copyright"
done

chmod +x "$STAGE/Retro Toolbox.sh" "$P/flutter-pi" "$P"/bin/*
rm -f "$OUT"
(cd "$STAGE" && zip -qr -X "$OUT" .)
ls -lh "$OUT"
# PortMaster-New wants files over 90 MB split (tools/build_data.py there).
find "$STAGE" -type f -size +90M -exec ls -lh {} \;
