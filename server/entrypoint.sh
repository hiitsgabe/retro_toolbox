#!/bin/bash
# Container entrypoint (under tini): KasmVNC display + web client, window manager, then the app
# under the memory watchdog. Env: RETRO_TOOLBOX_PASSWORD (required), RETRO_TOOLBOX_PORT (8444).
set -e

if [ -z "${RETRO_TOOLBOX_PASSWORD:-}" ]; then
  echo "RETRO_TOOLBOX_PASSWORD is required: set it to the password for the web page." >&2
  exit 1
fi
if [ ${#RETRO_TOOLBOX_PASSWORD} -lt 6 ]; then   # kasmvncpasswd's minimum
  echo "RETRO_TOOLBOX_PASSWORD must be at least 6 characters." >&2
  exit 1
fi

# Display :20, not :0/:1: with network_mode host the X abstract socket is shared with the host.
DISPLAY_NUM=20
mkdir -p "$HOME/.vnc" "$HOME/.kasmvnc"

# Self-signed certificate on first boot; kasmvnc.yaml points at these paths.
if [ ! -s "$HOME/.kasmvnc/cert.pem" ]; then
  openssl req -x509 -newkey rsa:2048 -nodes -days 3650 -subj "/CN=retro-toolbox" \
    -keyout "$HOME/.kasmvnc/key.pem" -out "$HOME/.kasmvnc/cert.pem" 2>/dev/null
fi

# Web login is user "retro"; rewritten every boot so a new password takes effect.
rm -f "$HOME/.kasmpasswd"
printf '%s\n%s\n' "$RETRO_TOOLBOX_PASSWORD" "$RETRO_TOOLBOX_PASSWORD" | kasmvncpasswd -u retro -wo >/dev/null
unset RETRO_TOOLBOX_PASSWORD   # the app never needs it

# Skip the interactive desktop-environment prompt; we start our own WM below.
touch "$HOME/.vnc/.de-was-selected"
# Leftovers from a previous run of this container (docker restart keeps /tmp and /data).
rm -f "/tmp/.X$DISPLAY_NUM-lock" "/tmp/.X11-unix/X$DISPLAY_NUM" "$HOME"/.vnc/*:"$DISPLAY_NUM".pid

vncserver ":$DISPLAY_NUM" -websocketPort "${RETRO_TOOLBOX_PORT:-8444}" -noxstartup
export DISPLAY=":$DISPLAY_NUM"
matchbox-window-manager -use_titlebar no &
wm_pid=$!
xvnc_pid=$(cat "$HOME"/.vnc/*:"$DISPLAY_NUM".pid)

# vncserver daemonizes, so nothing would notice Xvnc (or the WM) dying: the app would crash-loop on a
# dead display while Docker still shows the container up. Stop the container instead (TERM to tini ->
# watchdog stops the app and exits) so the restart policy brings the whole stack back.
(
  while kill -0 "$xvnc_pid" 2>/dev/null && kill -0 "$wm_pid" 2>/dev/null; do sleep 10; done
  echo "entrypoint: display or window manager died; stopping the container" >&2
  kill -TERM 1
) &

exec /opt/server/watchdog.sh /opt/retro_toolbox/retro_toolbox
