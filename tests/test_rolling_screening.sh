#!/usr/bin/env bash
set -euo pipefail
repo=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
source <(sed -n '/^[A-Za-z_][A-Za-z_0-9]*() {/,/^}/p' "$repo/cfy.sh")
# Frozen v1 scheduler only, never the installer.
source "$repo/tests/fixtures/screen_edge_candidates_v1.sh"
d=$(mktemp -d); trap 'rc=$?; if [ "$rc" != 0 ]; then cat "$d/"*.log >&2 || :; fi; rm -rf "$d"' EXIT
CFY_HEALTH_CONCURRENCY=3
ip_list=(192.0.2.1 192.0.2.2 192.0.2.3 192.0.2.4 192.0.2.5 192.0.2.6 192.0.2.7 192.0.2.8 192.0.2.9)
isp_list=(A B C A B C A B C)
probe_vless_edge_candidate() {
 local delay=0.2 failure=0 active peak
 if [[ "$scenario" == mixed ]]; then
  case "$2" in *.1|*.4|*.7) delay=0.6; failure=1 ;; *) delay=0.05 ;; esac
 elif [[ "$scenario" == failed ]]; then failure=1; fi
 (
 flock 9; read -r active peak < "$d/count"; active=$((active+1))
 [ "$active" -le "$peak" ] || peak=$active
 printf '%s %s\n' "$active" "$peak" > "$d/count"
 ) 9> "$d/lock"
 sleep "$delay"
 (
 flock 9; read -r active peak < "$d/count"; printf '%s %s\n' "$((active-1))" "$peak" > "$d/count"
 ) 9> "$d/lock"
 [ "$failure" == 0 ] || { printf 'timeout\n' > "$CFY_PROBE_RESULT_FILE"; return 1; }
}
for scenario in success mixed failed; do
 for scheduler in v1 impl; do
  printf '0 0\n' > "$d/count"
  start=$(date +%s%N)
  "screen_edge_candidates_$scheduler" vless fixture > "$d/$scheduler.out" 2> "$d/$scheduler.log" &
  scheduler_pid=$!; wait "$scheduler_pid"
  elapsed=$(( ($(date +%s%N)-start)/1000000 ))
  read -r active peak < "$d/count"
  [[ "$active" == 0 && "$peak" -le 3 ]]
  if [[ "$scheduler" == v1 ]]; then old_ms=$elapsed; else new_ms=$elapsed; fi
 done
 cmp "$d/v1.out" "$d/impl.out"
 printf 'Scheduler benchmark %s (9 candidates, cap 3): batches=%sms rolling=%sms\n' "$scenario" "$old_ms" "$new_ms"
 if [[ "$scenario" == mixed ]]; then [[ "$new_ms" -lt $((old_ms*80/100)) ]]; fi
 if [[ "$scenario" == failed ]]; then [[ ! -s "$d/impl.out" ]]; fi
done
