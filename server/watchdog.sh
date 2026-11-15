#!/bin/bash
# In-container supervisor: runs the app, restarts it if it dies, and restarts it
# when RSS stays above the limit while idle. Usage: watchdog.sh /path/to/app
# Knobs: WATCHDOG_INTERVAL (RSS check, 60), WATCHDOG_POLL (liveness, 2), WATCHDOG_STRIKES (3),
# WATCHDOG_BACKOFF_MIN (5), WATCHDOG_KILL_GRACE (20); tests: WATCHDOG_ONCE=1, WATCHDOG_RSS_KB.

# wd_decide <rss_kb> <limit_mb> <strikes_so_far> <busy:0|1> -> ok|strike|wait-busy|restart
wd_decide() {
  local rss_kb=$1 limit_mb=$2 strikes=$3 busy=$4
  if [ "$rss_kb" -le $((limit_mb * 1024)) ]; then echo ok
  elif [ "$strikes" -lt $((${WATCHDOG_STRIKES:-3} - 1)) ]; then echo strike
  elif [ "$busy" = 1 ]; then echo wait-busy
  else echo restart
  fi
}

# wd_backoff <previous_s> -> next delay: 5, 10, 20 ... capped at 300
wd_backoff() {
  local min=${WATCHDOG_BACKOFF_MIN:-5} n=$(($1 * 2))
  [ "$n" -lt "$min" ] && n=$min
  [ "$n" -gt 300 ] && n=300
  echo "$n"
}

if [ -n "${WATCHDOG_FUNCTION_ONLY:-}" ]; then return 0 2>/dev/null || exit 0; fi

APP=${1:?usage: watchdog.sh /path/to/app}
LIMIT_MB=${RETRO_TOOLBOX_MEMORY_LIMIT_MB:-2048}
case $LIMIT_MB in
  ''|*[!0-9]*) echo "RETRO_TOOLBOX_MEMORY_LIMIT_MB must be a whole number of MB" >&2; exit 1 ;;
esac
INTERVAL=${WATCHDOG_INTERVAL:-60}
POLL=${WATCHDOG_POLL:-2}
GRACE=${WATCHDOG_KILL_GRACE:-20}
STRIKES_MAX=${WATCHDOG_STRIKES:-3}
BUSY_FILE=${RETRO_TOOLBOX_BUSY_FILE:-}   # unset = never busy

log() { echo "watchdog: $1 rss=$((${rss_kb:-0} / 1024))MB limit=${LIMIT_MB}MB"; }
nap() { sleep "$1" & wait $!; }   # interruptible by the TERM trap

start_app() { "$APP" & pid=$!; started=$SECONDS; }

stop_app() {
  kill -TERM "$pid" 2>/dev/null
  local i=0
  while kill -0 "$pid" 2>/dev/null && [ $i -lt "$GRACE" ]; do nap 1; i=$((i + 1)); done
  kill -KILL "$pid" 2>/dev/null
  wait "$pid" 2>/dev/null
}

trap 'kill -TERM "$pid" 2>/dev/null; wait "$pid" 2>/dev/null; exit 0' TERM INT

pid=0 started=0 strikes=0 delay=0 rss_kb=0
start_app
last=$SECONDS
while :; do
  nap "$POLL"
  if ! kill -0 "$pid" 2>/dev/null; then
    wait "$pid" 2>/dev/null
    [ $((SECONDS - started)) -ge 600 ] && delay=0
    delay=$(wd_backoff "$delay")
    log "exited, restarting in ${delay}s"
    nap "$delay"
    strikes=0
    start_app; last=$SECONDS
    [ -n "${WATCHDOG_ONCE:-}" ] && { stop_app; exit 0; }
  elif [ $((SECONDS - last)) -ge "$INTERVAL" ]; then
    last=$SECONDS
    rss_kb=${WATCHDOG_RSS_KB:-$(awk '/^VmRSS:/ {print $2}' "/proc/$pid/status" 2>/dev/null)}
    rss_kb=${rss_kb:-0}
    busy=0
    [ -n "$BUSY_FILE" ] && [ -e "$BUSY_FILE" ] && busy=1
    case $(wd_decide "$rss_kb" "$LIMIT_MB" "$strikes" "$busy") in
      ok) strikes=0 ;;
      strike) strikes=$((strikes + 1)); log "strike $strikes/$STRIKES_MAX" ;;
      wait-busy) log "wait-busy" ;;
      restart) log "restart"; stop_app; strikes=0; start_app ;;
    esac
    [ -n "${WATCHDOG_ONCE:-}" ] && { stop_app; exit 0; }
  fi
done
