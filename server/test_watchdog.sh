#!/bin/bash
# Exercises wd_decide from watchdog.sh. Run: bash server/test_watchdog.sh
set -u
HERE="$(cd "$(dirname "$0")" && pwd)"
WATCHDOG_FUNCTION_ONLY=1 source "$HERE/watchdog.sh"

fails=0
check() { if eval "$2"; then echo "ok   $1"; else echo "FAIL $1"; fails=$((fails + 1)); fi; }

# wd_decide <rss_kb> <limit_mb> <strikes_so_far> <busy>
check "below limit -> ok" '[ "$(wd_decide 1024000 2048 0 0)" = ok ]'
check "at limit -> ok" '[ "$(wd_decide 2097152 2048 0 0)" = ok ]'
check "above, 0 strikes -> strike" '[ "$(wd_decide 3000000 2048 0 0)" = strike ]'
check "above, 1 strike -> strike" '[ "$(wd_decide 3000000 2048 1 0)" = strike ]'
check "above, 2 strikes, idle -> restart" '[ "$(wd_decide 3000000 2048 2 0)" = restart ]'
check "above, 2 strikes, busy -> wait-busy" '[ "$(wd_decide 3000000 2048 2 1)" = wait-busy ]'
check "back below after strikes -> ok" '[ "$(wd_decide 1000000 2048 2 0)" = ok ]'
check "busy but below -> ok" '[ "$(wd_decide 1000000 2048 2 1)" = ok ]'

# wd_backoff <previous_s>: 5 -> 10 -> ... capped at 300
check "backoff first" '[ "$(wd_backoff 0)" = 5 ]'
check "backoff doubles" '[ "$(wd_backoff 5)" = 10 ]'
check "backoff caps" '[ "$(wd_backoff 200)" = 300 ]'
check "backoff stays capped" '[ "$(wd_backoff 300)" = 300 ]'

# --- loop behaviour, with a fake app (fast knobs) ---
T=$(mktemp -d); trap 'rm -rf "$T"' EXIT
export WATCHDOG_POLL=1 WATCHDOG_INTERVAL=1 WATCHDOG_BACKOFF_MIN=1 WATCHDOG_KILL_GRACE=1
unset RETRO_TOOLBOX_BUSY_FILE
printf '#!/bin/bash\necho start >> "%s/starts"\nsleep 30\n' "$T" > "$T/app"
printf '#!/bin/bash\necho start >> "%s/starts"\ntrap "" TERM\nwhile :; do sleep 1; done\n' "$T" > "$T/stubborn"
printf '#!/bin/bash\necho start >> "%s/starts"\nexit 0\n' "$T" > "$T/dies"
chmod +x "$T/app" "$T/stubborn" "$T/dies"
starts() { wc -l < "$T/starts" 2>/dev/null | tr -d ' '; }
W="$HERE/watchdog.sh"
RSS_BIG=3000000 LIM=100

# dead app is restarted within poll + backoff, not a full interval
rm -f "$T/starts"; WATCHDOG_INTERVAL=60 bash "$W" "$T/dies" > "$T/out" 2>&1 & p=$!
sleep 4; kill -TERM $p; wait $p 2>/dev/null
check "dead app restarted fast (even with long interval)" '[ "$(starts)" -ge 2 ]'
check "exit logged" 'grep -q "exited, restarting" "$T/out"'

# over limit for N strikes, idle -> restart
rm -f "$T/starts"; WATCHDOG_RSS_KB=$RSS_BIG RETRO_TOOLBOX_MEMORY_LIMIT_MB=$LIM \
  bash "$W" "$T/app" > "$T/out" 2>&1 & p=$!
sleep 6; kill -TERM $p; wait $p 2>/dev/null
check "strikes then restart" 'grep -q "strike 2/3" "$T/out" && grep -q "watchdog: restart" "$T/out" && [ "$(starts)" -ge 2 ]'

# busy file blocks the restart
rm -f "$T/starts"; touch "$T/busy"
WATCHDOG_RSS_KB=$RSS_BIG RETRO_TOOLBOX_MEMORY_LIMIT_MB=$LIM RETRO_TOOLBOX_BUSY_FILE="$T/busy" \
  bash "$W" "$T/app" > "$T/out" 2>&1 & p=$!
sleep 6; kill -TERM $p; wait $p 2>/dev/null
check "busy blocks restart" 'grep -q wait-busy "$T/out" && ! grep -q "watchdog: restart" "$T/out" && [ "$(starts)" = 1 ]'

# TERM->KILL escalation on a stubborn app
rm -f "$T/starts"
WATCHDOG_RSS_KB=$RSS_BIG RETRO_TOOLBOX_MEMORY_LIMIT_MB=$LIM WATCHDOG_ONCE=1 WATCHDOG_STRIKES=1 \
  bash "$W" "$T/stubborn" > "$T/out" 2>&1; rc=$?
check "ONCE: restart decision, exits 0" 'grep -q "watchdog: restart" "$T/out" && [ $rc -eq 0 ]'
check "stubborn app killed" '! ps ax | grep -v grep | grep -q "$T/stubborn"'

# TERM on the watchdog exits 0 and takes the app down, no restart
rm -f "$T/starts"; bash "$W" "$T/app" > "$T/out" 2>&1 & p=$!
sleep 1; kill -TERM $p; wait $p; rc=$?
sleep 0.3
check "TERM exits 0" '[ $rc -eq 0 ]'
check "TERM: app gone, not restarted" '[ "$(starts)" = 1 ] && ! ps ax | grep -v grep | grep -q "$T/app"'

# a non-numeric limit is refused at startup, before the app starts
for bad in 2G abc; do
  rm -f "$T/starts"; RETRO_TOOLBOX_MEMORY_LIMIT_MB=$bad bash "$W" "$T/app" > "$T/out" 2>&1; rc=$?
  check "limit '$bad' refused" '[ $rc -eq 1 ] && grep -q "whole number" "$T/out" && [ ! -e "$T/starts" ]'
done

[ "$fails" -eq 0 ] || { echo "$fails failed"; exit 1; }
