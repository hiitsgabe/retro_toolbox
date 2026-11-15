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

[ "$fails" -eq 0 ] || { echo "$fails failed"; exit 1; }
