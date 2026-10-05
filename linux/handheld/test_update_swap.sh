#!/bin/bash
# Exercises rt_apply_update from "Retro Toolbox.sh" on a fake port tree.
# Run: bash linux/handheld/test_update_swap.sh
set -u
HERE="$(cd "$(dirname "$0")" && pwd)"
RT_UPDATE_FUNCTION_ONLY=1 source "$HERE/Retro Toolbox.sh"

T=$(mktemp -d); trap 'rm -rf "$T"' EXIT
fails=0
check() { if eval "$2"; then echo "ok   $1"; else echo "FAIL $1"; fails=$((fails + 1)); fi; }

# --- staged update is applied ---
P="$T/ports"; G="$P/retrotoolbox"
mkdir -p "$G"/{config,cache,data/home,data/flutter_assets,Documents,Downloads,bundled_libs,xkb,lib,bin}
echo user > "$G/config/settings"; echo cached > "$G/cache/c"; echo home > "$G/data/home/h"
echo doc > "$G/Documents/d"; echo dl > "$G/Downloads/f"; echo log > "$G/log.txt"
echo old > "$G/flutter-pi"; echo old > "$G/lib/libapp.so"; echo stale > "$G/lib/only_old.so"
echo stale > "$G/bundled_libs/libgone.so"; echo stale > "$G/xkb/gone"; echo stale > "$G/data/flutter_assets/gone"
echo "old launcher" > "$P/Retro Toolbox.sh"

U="$G/.update"; N="$U/retrotoolbox"
mkdir -p "$N"/{data/flutter_assets,bundled_libs,xkb,lib,bin}
echo new > "$N/flutter-pi"; echo new > "$N/lib/libapp.so"; echo new > "$N/bundled_libs/libnew.so"
echo new > "$N/xkb/Compose"; echo new > "$N/data/flutter_assets/app.so"; echo new > "$N/bin/xdg-user-dir"
echo "new launcher" > "$U/Retro Toolbox.sh"; touch "$U/READY"

out=$(rt_apply_update "$G" "$P")
check "binary replaced" '[ "$(cat "$G/flutter-pi")" = new ]'
check "lib replaced" '[ "$(cat "$G/lib/libapp.so")" = new ]'
check "files outside replaced dirs kept" '[ -f "$G/lib/only_old.so" ]'
check "bundled_libs wiped then copied" '[ ! -e "$G/bundled_libs/libgone.so" ] && [ -f "$G/bundled_libs/libnew.so" ]'
check "xkb wiped then copied" '[ ! -e "$G/xkb/gone" ] && [ -f "$G/xkb/Compose" ]'
check "flutter_assets wiped then copied" '[ ! -e "$G/data/flutter_assets/gone" ] && [ -f "$G/data/flutter_assets/app.so" ]'
check "config kept" '[ "$(cat "$G/config/settings")" = user ]'
check "cache kept" '[ -f "$G/cache/c" ]'
check "data/home kept" '[ "$(cat "$G/data/home/h")" = home ]'
check "Documents kept" '[ -f "$G/Documents/d" ]'
check "Downloads kept" '[ -f "$G/Downloads/f" ]'
check "log kept" '[ -f "$G/log.txt" ]'
check "launcher replaced" '[ "$(cat "$P/Retro Toolbox.sh")" = "new launcher" ]'
check "launcher executable" '[ -x "$P/Retro Toolbox.sh" ]'
check "no temp launcher left" '[ ! -e "$P/.Retro Toolbox.sh.new" ]'
check "flutter-pi executable" '[ -x "$G/flutter-pi" ]'
check "bin executable" '[ -x "$G/bin/xdg-user-dir" ]'
check ".update removed" '[ ! -e "$U" ]'
check "steps logged" 'echo "$out" | grep -q "Update: done"'

# --- interrupted download (no READY) is discarded ---
mkdir -p "$U/retrotoolbox"; echo partial > "$U/retrotoolbox/flutter-pi"
rt_apply_update "$G" "$P" >/dev/null
check "incomplete update removed" '[ ! -e "$U" ]'
check "incomplete update not applied" '[ "$(cat "$G/flutter-pi")" = new ]'

# --- nothing staged: no-op ---
check "no update is a no-op" 'rt_apply_update "$G" "$P" >/dev/null && [ "$(cat "$G/flutter-pi")" = new ]'

[ "$fails" -eq 0 ] && echo "all passed" || { echo "$fails failed"; exit 1; }
