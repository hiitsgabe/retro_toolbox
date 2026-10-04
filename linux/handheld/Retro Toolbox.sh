#!/bin/bash
# Retro Toolbox — Linux handheld launcher (PortMaster format).
# Layout: ports/Retro Toolbox.sh + ports/retrotoolbox/ (flutter-pi, engine,
# data/flutter_assets, lib/, app/, site-packages/, bundled_libs/).

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
MODE_ARGS=""
if ls /dev/dri/card* >/dev/null 2>&1; then
  echo "Display: DRM/KMS"
else
  echo "Display: framebuffer"
  export RETRO_TOOLBOX_FBDEV=1
  MODE_ARGS="--fbdev"
fi

chmod +x ./flutter-pi
$GPTOKEYB "flutter-pi" -c "$GAMEDIR/retrotoolbox.gptk" &
pm_platform_helper "$GAMEDIR/flutter-pi"
# -d: physical size in mm so flutter-pi computes a sane pixel ratio on ~3.5" screens.
./flutter-pi --release $MODE_ARGS -d "${RT_DISPLAY_MM:-71,53}" ./data/flutter_assets
echo "flutter-pi exited with $?"
pm_finish
