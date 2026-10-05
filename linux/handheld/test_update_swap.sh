#!/bin/bash
# Exercises rt_apply_update from "Retro Toolbox.sh" on fake port trees.
# Run: bash linux/handheld/test_update_swap.sh
set -u
HERE="$(cd "$(dirname "$0")" && pwd)"
RT_UPDATE_FUNCTION_ONLY=1 source "$HERE/Retro Toolbox.sh"

T=$(mktemp -d); trap 'chmod -R u+w "$T"; rm -rf "$T"' EXIT
fails=0
check() { if eval "$2"; then echo "ok   $1"; else echo "FAIL $1"; fails=$((fails + 1)); fi; }

# A fresh installed port ($G under $P) with user data, and a staged update ($U).
setup() {
  rm -rf "$T/ports"
  P="$T/ports"; G="$P/retrotoolbox"; U="$G/.update"; N="$U/retrotoolbox"
  mkdir -p "$G"/{config,cache,data/home,data/flutter_assets,Documents,Downloads,bundled_libs,xkb,lib,bin,app,site-packages/oldmod}
  echo user > "$G/config/settings"; echo cached > "$G/cache/c"; echo home > "$G/data/home/h"
  echo doc > "$G/Documents/d"; echo dl > "$G/Downloads/f"; echo log > "$G/log.txt"
  echo old > "$G/flutter-pi"; echo old > "$G/lib/libapp.so"; echo stale > "$G/lib/only_old.so"
  echo stale > "$G/bundled_libs/libgone.so"; echo stale > "$G/xkb/gone"; echo stale > "$G/data/flutter_assets/gone"
  echo stale > "$G/app/gone.py"; echo stale > "$G/site-packages/oldmod/x.py"
  echo "old launcher" > "$P/Retro Toolbox.sh"
  # Other ports and the PortMaster folder share ports/: they must never be touched.
  mkdir -p "$P/otherport/data" "$P/PortMaster"; echo other > "$P/otherport/data/save"
  echo "other launcher" > "$P/Other Port.sh"; echo pm > "$P/PortMaster/control.txt"

  mkdir -p "$N"/{data/flutter_assets,bundled_libs,xkb,lib,bin,app,site-packages/newmod}
  echo new > "$N/flutter-pi"; echo new > "$N/lib/libapp.so"; echo new > "$N/bundled_libs/libnew.so"
  echo new > "$N/xkb/Compose"; echo new > "$N/data/flutter_assets/app.so"; echo new > "$N/bin/xdg-user-dir"
  echo new > "$N/app/main.py"; echo new > "$N/site-packages/newmod/x.py"
  echo "new launcher" > "$U/Retro Toolbox.sh"; touch "$U/READY"
}

# --- staged update is applied ---
setup
out=$(rt_apply_update "$G" "$P"); rc=$?
check "applied returns 0" '[ $rc -eq 0 ]'
check "binary replaced" '[ "$(cat "$G/flutter-pi")" = new ]'
check "lib replaced" '[ "$(cat "$G/lib/libapp.so")" = new ]'
check "files outside wiped dirs kept" '[ -f "$G/lib/only_old.so" ]'
check "bundled_libs wiped then copied" '[ ! -e "$G/bundled_libs/libgone.so" ] && [ -f "$G/bundled_libs/libnew.so" ]'
check "xkb wiped then copied" '[ ! -e "$G/xkb/gone" ] && [ -f "$G/xkb/Compose" ]'
check "flutter_assets wiped then copied" '[ ! -e "$G/data/flutter_assets/gone" ] && [ -f "$G/data/flutter_assets/app.so" ]'
check "app wiped then copied" '[ ! -e "$G/app/gone.py" ] && [ -f "$G/app/main.py" ]'
check "site-packages wiped then copied" '[ ! -e "$G/site-packages/oldmod" ] && [ -f "$G/site-packages/newmod/x.py" ]'
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
check "other port untouched" '[ "$(cat "$P/otherport/data/save")" = other ]'
check "other launcher untouched" '[ "$(cat "$P/Other Port.sh")" = "other launcher" ]'
check "PortMaster untouched" '[ "$(cat "$P/PortMaster/control.txt")" = pm ]'
check "ports/ holds nothing new" '[ "$(ls -A "$P" | sort | tr "\n" " ")" = "Other Port.sh PortMaster Retro Toolbox.sh otherport retrotoolbox " ]'

# --- interrupted download, or a power cut after READY was dropped ---
setup; rm "$U/READY"; rm -rf "$N/bundled_libs"
rt_apply_update "$G" "$P" >/dev/null; rc=$?
check "no READY returns 0" '[ $rc -eq 0 ]'
check "no READY: .update removed" '[ ! -e "$U" ]'
check "no READY: nothing applied" '[ "$(cat "$G/flutter-pi")" = old ] && [ -f "$G/bundled_libs/libgone.so" ]'

# --- staged tree incomplete: keep running the old version ---
setup; rm "$N/flutter-pi"
rt_apply_update "$G" "$P" >/dev/null; rc=$?
check "incomplete staged tree returns 2" '[ $rc -eq 2 ]'
check "incomplete staged tree: old port untouched" '[ -f "$G/bundled_libs/libgone.so" ] && [ "$(cat "$G/lib/libapp.so")" = old ]'
check "incomplete staged tree: .update kept with READY and FAILED" '[ -f "$U/READY" ] && [ -f "$U/FAILED" ]'

# --- not enough space: keep running the old version ---
setup
df() { printf 'Filesystem 1024-blocks Used Available Capacity Mounted\nfake 100 100 0 100%% /\n'; }
rt_apply_update "$G" "$P" >/dev/null; rc=$?
unset -f df
check "no space returns 2" '[ $rc -eq 2 ]'
check "no space: old port untouched" '[ -f "$G/bundled_libs/libgone.so" ] && [ "$(cat "$G/flutter-pi")" = old ]'
check "no space: FAILED says why" 'grep -q "not enough space" "$U/FAILED" && [ -f "$U/READY" ]'

# --- copy fails part-way: stop, keep everything for a retry ---
if [ "$(id -u)" != 0 ]; then
  setup; chmod a-w "$G/bin"
  out=$(rt_apply_update "$G" "$P" 2>&1); rc=$?
  check "failed copy returns 1" '[ $rc -eq 1 ]'
  check "failed copy: .update, READY and FAILED kept" '[ -f "$U/READY" ] && [ -f "$U/FAILED" ] && [ -f "$N/flutter-pi" ]'
  check "failed copy: launcher not replaced" '[ "$(cat "$P/Retro Toolbox.sh")" = "old launcher" ]'
  check "failed copy logged" 'echo "$out" | grep -q "copy failed"'
  chmod u+w "$G/bin"
  rt_apply_update "$G" "$P" >/dev/null; rc=$?
  check "retry after a failed copy applies" '[ $rc -eq 0 ] && [ "$(cat "$G/flutter-pi")" = new ] && [ ! -e "$U" ]'
else
  echo "skip failed-copy cases (root ignores permissions)"
fi

# --- nothing staged: no-op ---
check "no update is a no-op" 'rt_apply_update "$G" "$P" >/dev/null && [ "$(cat "$G/flutter-pi")" = new ]'

[ "$fails" -eq 0 ] && echo "all passed" || { echo "$fails failed"; exit 1; }
