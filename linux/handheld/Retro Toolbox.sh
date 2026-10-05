#!/bin/bash
# Retro Toolbox — Linux handheld launcher (PortMaster format).
# Layout: ports/Retro Toolbox.sh + ports/retrotoolbox/ (flutter-pi, engine,
# data/flutter_assets, lib/, app/, site-packages/, bundled_libs/).

# In-app updater: the app stages a new port in $1/.update/ (retrotoolbox/ +
# Retro Toolbox.sh) and writes READY last. Swap it in over the port folder $1;
# user data (config/, cache/, data/home/, Documents/, Downloads/, log.txt)
# isn't in the update so it stays. $2 is the ports folder (new launcher).
rt_apply_update() {
  local game="$1" ports="$2" up="$1/.update"
  [ -d "$up" ] || return 0
  if [ ! -f "$up/READY" ]; then
    echo "Update: incomplete, removing $up"
    rm -rf "$up"
    return 0
  fi
  echo "Update: applying"
  local d
  for d in bundled_libs xkb data/flutter_assets; do
    [ -d "$up/retrotoolbox/$d" ] || continue
    echo "Update: replacing $d"
    rm -rf "${game:?}/$d"
  done
  echo "Update: copying files"
  # READY stays on failure, so the next start retries.
  cp -rf "$up/retrotoolbox/." "$game/" || { echo "Update: copy failed"; return 1; }
  if [ -f "$up/Retro Toolbox.sh" ]; then
    echo "Update: replacing launcher"
    # Copy then rename: this script is the one running, and bash reads it as
    # it goes — overwriting it in place would corrupt the rest of this run.
    cp -f "$up/Retro Toolbox.sh" "$ports/.Retro Toolbox.sh.new" &&
      mv -f "$ports/.Retro Toolbox.sh.new" "$ports/Retro Toolbox.sh" &&
      chmod +x "$ports/Retro Toolbox.sh"
  fi
  chmod +x "$game/flutter-pi" "$game"/bin/* 2>/dev/null
  rm -rf "$up"
  echo "Update: done"
}
# test_update_swap.sh sources this file for the function alone.
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
./flutter-pi --release $MODE_ARGS -d "${RT_DISPLAY_MM:-71,53}" ./data/flutter_assets
echo "flutter-pi exited with $?"
[ -n "$FB_VIRTUAL" ] && echo "$FB_VIRTUAL" > "$FB/virtual_size" 2>/dev/null
pm_finish
