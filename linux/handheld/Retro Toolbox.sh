#!/bin/bash
# Retro Toolbox — Linux handheld launcher (PortMaster format).
# Layout: ports/Retro Toolbox.sh + ports/retrotoolbox/ (flutter-pi, engine,
# data/flutter_assets, lib/, app/, site-packages/, bundled_libs/).

# In-app updater: the app stages a new port in $1/.update/ (retrotoolbox/ +
# Retro Toolbox.sh), synced, and writes READY last. Swap it in over the port
# folder $1; user data (config/, cache/, data/home/, Documents/, Downloads/,
# log.txt) isn't in the update so it stays. $2 is the ports folder (new
# launcher). Returns 0 when there was nothing to do or it applied; 2 when it
# failed before touching the port (the old one still runs); 1 when it failed
# part-way (the port is mixed: don't start it). Failures leave .update/ and
# READY for a retry next start, plus a FAILED note (the app shows it in About).
# A part-way failure also leaves UPDATE_FAILED.txt in the port folder.
RT_UPDATE_WIPE="bundled_libs xkb data/flutter_assets app site-packages"
# Part-way failure ($1 port folder, $2 reason): note the reason in FAILED, put
# the same plain message in the log and in UPDATE_FAILED.txt, return 1.
rt_fail_partial() {
  local msg
  msg="Retro Toolbox: the update could not be completed.
The app was only partly updated, so it was not started.
Reason: $2
Fix that (free some space on the card?) and start Retro Toolbox again to retry,
or reinstall Retro Toolbox from the release zip."
  echo "$2" > "$1/.update/FAILED"
  echo "$msg"
  echo "$msg" > "$1/UPDATE_FAILED.txt"
  return 1
}
rt_apply_update() {
  local game="$1" ports="$2" up="$1/.update" d
  if [ ! -d "$up" ]; then rm -f "$game/UPDATE_FAILED.txt"; return 0; fi
  if [ ! -f "$up/READY" ]; then
    echo "Update: incomplete, removing $up"
    rm -rf "$up"
    return 0
  fi
  echo "Update: applying"
  rm -f "$up/FAILED"
  if [ ! -f "$up/retrotoolbox/flutter-pi" ] || [ ! -d "$up/retrotoolbox/data/flutter_assets" ]; then
    echo "Update: staged files incomplete, keeping the current version"
    echo "staged files incomplete" > "$up/FAILED"
    return 2
  fi
  # Wiped folders free their space before the copy; the rest is overwritten.
  local need avail
  need=$(du -sk "$up/retrotoolbox" | awk '{print $1}')
  for d in $RT_UPDATE_WIPE; do
    [ -d "$game/$d" ] && need=$((need - $(du -sk "$game/$d" | awk '{print $1}')))
  done
  avail=$(df -Pk "$game" 2>/dev/null | awk 'NR==2{print $4}')
  if [ -n "$avail" ] && [ "$avail" -lt "$need" ]; then
    echo "Update: not enough space (need ${need} KB, ${avail} KB free), keeping the current version"
    echo "not enough space: need ${need} KB, ${avail} KB free" > "$up/FAILED"
    return 2
  fi
  for d in $RT_UPDATE_WIPE; do
    [ -d "$up/retrotoolbox/$d" ] || continue
    echo "Update: replacing $d"
    rm -rf "${game:?}/$d" || { rt_fail_partial "$game" "copy failed: rm $d"; return 1; }
  done
  echo "Update: copying files"
  cp -rf "$up/retrotoolbox/." "$game/" || { rt_fail_partial "$game" "copy failed"; return 1; }
  if [ -f "$up/Retro Toolbox.sh" ]; then
    echo "Update: replacing launcher"
    # Copy then rename: this script is the one running, and bash reads it as
    # it goes — overwriting it in place would corrupt the rest of this run.
    { cp -f "$up/Retro Toolbox.sh" "$ports/.Retro Toolbox.sh.new" &&
      mv -f "$ports/.Retro Toolbox.sh.new" "$ports/Retro Toolbox.sh"; } ||
      { rt_fail_partial "$game" "launcher copy failed"; return 1; }
    chmod +x "$ports/Retro Toolbox.sh" 2>/dev/null || true
  fi
  chmod +x "$game/flutter-pi" "$game"/bin/* 2>/dev/null || true
  # Flush the copy before dropping READY, and READY before the staged tree:
  # a power cut must never leave READY next to a half-deleted .update/.
  sync
  rm -f "$up/READY"
  sync
  rm -rf "$up"
  rm -f "$game/UPDATE_FAILED.txt"
  echo "Update: done"
}
# Don't start a port that a part-way failure left mixed: rc 1 now, or rc 2
# (this start's check failed) while an earlier part-way failure's note remains.
rt_must_stop() { [ "$1" -eq 1 ] || { [ "$1" -eq 2 ] && [ -f "$2/UPDATE_FAILED.txt" ]; }; }
# test_update_swap.sh sources this file for the functions alone.
[ -n "$RT_UPDATE_FUNCTION_ONLY" ] && return 0

XDG_DATA_HOME=${XDG_DATA_HOME:-$HOME/.local/share}
if [ -d "/opt/system/Tools/PortMaster/" ]; then controlfolder="/opt/system/Tools/PortMaster"
elif [ -d "/opt/tools/PortMaster/" ]; then controlfolder="/opt/tools/PortMaster"
elif [ -d "$XDG_DATA_HOME/PortMaster/" ]; then controlfolder="$XDG_DATA_HOME/PortMaster"
else controlfolder="/roms/ports/PortMaster"; fi
source "$controlfolder/control.txt"
[ -f "${controlfolder}/mod_${CFW_NAME}.txt" ] && source "${controlfolder}/mod_${CFW_NAME}.txt"
get_controls

GAMEDIR="/$directory/ports/retrotoolbox"
cd "$GAMEDIR" || exit 1
exec > >(tee "$GAMEDIR/log.txt") 2>&1
echo "--- Retro Toolbox --- $(date)"
rt_apply_update "$GAMEDIR" "/$directory/ports"
if rt_must_stop $? "$GAMEDIR"; then
  echo "Update failed part-way; not starting. Free some space and start Retro Toolbox again to retry."
  # pm_message lives in PortMaster's funcs.txt (sourced by control.txt).
  type pm_message >/dev/null 2>&1 &&
    pm_message "Update failed part-way. See UPDATE_FAILED.txt in the retrotoolbox folder, then start again."
  pm_finish
  exit 1
fi

# Bundled libraries only where the firmware lacks them.
mkdir -p "$GAMEDIR/runtime_libs"; rm -f "$GAMEDIR/runtime_libs"/*
for lib in "$GAMEDIR"/bundled_libs/*; do
  name=$(basename "$lib")
  found=""
  for d in /usr/lib /usr/lib64 /lib /lib64 /usr/lib/aarch64-linux-gnu /usr/local/lib; do
    [ -e "$d/$name" ] && found=1 && break
  done
  [ -z "$found" ] && cp "$lib" "$GAMEDIR/runtime_libs/$name"
done
export LD_LIBRARY_PATH="$GAMEDIR/runtime_libs:$GAMEDIR/lib:$GAMEDIR:$LD_LIBRARY_PATH"

# Keep every file the app writes inside the port folder.
export HOME="$GAMEDIR"
export XDG_DATA_HOME="$GAMEDIR/data/home"
export XDG_CONFIG_HOME="$GAMEDIR/config"
export XDG_CACHE_HOME="$GAMEDIR/cache"
mkdir -p "$XDG_DATA_HOME" "$XDG_CONFIG_HOME" "$XDG_CACHE_HOME" "$GAMEDIR/Documents" "$GAMEDIR/Downloads"
printf 'XDG_DOCUMENTS_DIR="$HOME/Documents"\nXDG_DOWNLOAD_DIR="$HOME/Downloads"\n' > "$XDG_CONFIG_HOME/user-dirs.dirs"

export RETRO_TOOLBOX_HANDHELD=1
# path_provider asks `xdg-user-dir`, which these firmwares lack.
export PATH="$GAMEDIR/bin:$PATH"
# Keyboard layouts for xkbcommon (gptokeyb sends key events).
export XKB_CONFIG_ROOT="$GAMEDIR/xkb"
# No X11 locale data either: without a Compose file flutter-pi drops all
# keyboard input. An (almost) empty one is enough — it can't be zero bytes.
export XCOMPOSEFILE="$GAMEDIR/xkb/Compose"
[ -s "$XCOMPOSEFILE" ] || echo "# No compose sequences." > "$XCOMPOSEFILE"

MODE_ARGS=""
FB=/sys/class/graphics/fb0
FB_VIRTUAL=""
if ls /dev/dri/card* >/dev/null 2>&1; then
  echo "Display: DRM/KMS"
else
  echo "Display: framebuffer"
  export RETRO_TOOLBOX_FBDEV=1
  MODE_ARGS="--fbdev"
  # flutter-pi draws into the first page only; a double-height (page
  # flipping) framebuffer would alternate with the frontend's old frame.
  if [ -w "$FB/virtual_size" ]; then
    FB_VIRTUAL=$(cat "$FB/virtual_size")
    W=$(cut -d, -f1 "$FB/virtual_size")
    H=$(cat "$FB/modes" 2>/dev/null | head -1 | sed -n 's/.*:\([0-9]*\)x\([0-9]*\).*/\2/p')
    [ -z "$H" ] && H=$(( $(cut -d, -f2 "$FB/virtual_size") / 2 ))
    echo "$W,$H" > "$FB/virtual_size" 2>/dev/null
    echo "0,0" > "$FB/pan" 2>/dev/null
  fi
fi

# Physical size (mm) drives flutter-pi's pixel ratio (10*px / (mm*38)).
# Default: ~1.2x, whatever the panel resolution. RT_DISPLAY_MM overrides.
# The panel's resolution: the connected DRM mode on DRM firmwares (fb0 may
# be missing or double height there), else the framebuffer's current mode.
PX=""
if [ -z "$RETRO_TOOLBOX_FBDEV" ]; then
  for c in /sys/class/drm/card*-*; do
    [ "$(cat "$c/status" 2>/dev/null)" = connected ] || continue
    PX=$(head -1 "$c/modes" 2>/dev/null | grep -o '^[0-9]*x[0-9]*')
    [ -n "$PX" ] && break
  done
fi
[ -z "$PX" ] && PX=$(head -1 "$FB/modes" 2>/dev/null | grep -o '[0-9]*x[0-9]*' | head -1)
[ -z "$PX" ] && [ -r "$FB/virtual_size" ] && PX=$(tr ',' x < "$FB/virtual_size")
if [ -z "$RT_DISPLAY_MM" ] && [ -n "$PX" ]; then
  PX_W=${PX%x*}; PX_H=${PX#*x}
  RT_DISPLAY_MM="$(( PX_W * 10 / 46 )),$(( PX_H * 10 / 46 ))"
fi
echo "Display: ${PX:-unknown} px"
echo "Display mm: ${RT_DISPLAY_MM:-71,53}"

chmod +x ./flutter-pi
$GPTOKEYB "flutter-pi" -c "$GAMEDIR/retrotoolbox.gptk" &
pm_platform_helper "$GAMEDIR/flutter-pi"
# Something in the stack writes to a closed pipe at startup; ignore SIGPIPE
# (the write then fails with EPIPE instead of killing flutter-pi).
trap '' PIPE
# Memory every 30 s, so a kill (exit 137) shows what filled it.
( while sleep 30 && pgrep flutter-pi >/dev/null; do
    echo "mem: $(awk '/^(MemAvailable|Dirty|SwapFree):/{printf "%s %d MB  ", $1, $2/1024}' /proc/meminfo)flutter-pi $(awk '/^VmRSS:/{printf "%d MB", $2/1024}' /proc/$(pgrep -o flutter-pi)/status 2>/dev/null)"
  done ) &
MEMLOG=$!
./flutter-pi --release $MODE_ARGS -d "${RT_DISPLAY_MM:-71,53}" ./data/flutter_assets
RC=$?
kill $MEMLOG 2>/dev/null
echo "flutter-pi exited with $RC"
[ $RC -eq 137 ] && { echo "Kernel log:"; dmesg 2>/dev/null | grep -iE "out of memory|oom|killed process" | tail -15; }
[ -n "$FB_VIRTUAL" ] && echo "$FB_VIRTUAL" > "$FB/virtual_size" 2>/dev/null
pm_finish
