#!/usr/bin/env bash
set -euo pipefail
repo=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
source <(sed -n '/^[A-Za-z_][A-Za-z_0-9]*() {/,/^}/p' "$repo/cfy.sh")
d=$(mktemp -d); trap 'rm -rf "$d"' EXIT
CFY_HEALTH_PROBE=1 CFY_HEALTH_CONCURRENCY=3
: > "$d/state"; printf '0 0\n' > "$d/count"
probe_vless_edge_candidate() {
 local active peak
 (
 flock 9; read -r active peak < "$d/count"; active=$((active+1))
 [ "$active" -le "$peak" ] || peak=$active
 printf '%s %s\n' "$active" "$peak" > "$d/count"
 ) 9> "$d/state"
 sleep 0.2
 (
 flock 9; read -r active peak < "$d/count"; printf '%s %s\n' "$((active-1))" "$peak" > "$d/count"
 ) 9> "$d/state"
 if [[ "$2" == *.2 || "${ALL_FAIL:-0}" == 1 ]]; then printf 'timeout\n' > "$CFY_PROBE_RESULT_FILE"; return 1; fi
}
ip_list=(192.0.2.1 192.0.2.2 192.0.2.3 192.0.2.4 192.0.2.5 192.0.2.6)
isp_list=(A B C D E F)
start=$(date +%s%N)
screen_edge_candidates vless fixture 2> "$d/progress"
end=$(date +%s%N)
read -r active peak < "$d/count"
[[ "$active" == 0 && "$peak" == 3 ]]
[[ "${ip_list[*]}" == '192.0.2.1 192.0.2.3 192.0.2.4 192.0.2.5 192.0.2.6' ]]
[[ "${isp_list[*]}" == 'A C D E F' ]]
grep -q '本机检查超时' "$d/progress"
[ $(( (end-start)/1000000 )) -lt 1600 ]
ALL_FAIL=1
if screen_edge_candidates vless fixture 2>/dev/null; then echo 'all-failed screening accepted'; exit 1; fi
[[ ${#ip_list[@]} == 0 ]]
# Disabling the optional check remains explicit and never labels candidates verified.
CFY_HEALTH_PROBE=0
ip_list=(192.0.2.9); isp_list=(fixture)
screen_edge_candidates vless fixture 2> "$d/skipped"
[[ "${ip_list[*]}" == 192.0.2.9 ]]
grep -q '未检查握手' "$d/skipped"
echo 'Parallel cap, ordered results, transient failure labels and empty-result tests passed.'
