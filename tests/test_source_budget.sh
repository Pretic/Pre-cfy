#!/usr/bin/env bash
set -euo pipefail
repo=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
source <(sed -n '/^[A-Za-z_][A-Za-z_0-9]*() {/,/^}/p' "$repo/cfy.sh")
d=$(mktemp -d); trap 'rm -rf "$d"' EXIT
GREEN='' YELLOW='' RED='' NC=''
CFY_SOURCE_MAX_TIME=004 CFY_CURL_MAX_TIME=99 CFY_CURL_CONNECT_TIMEOUT=99
CFY_OPTIMIZED_IP_API_KEY=fixture-key
IP_VERSION_SCOPE=both
curl() {
 local timeout='' connect='' args=" $* "
 while [ "$#" -gt 0 ]; do
  case "$1" in --max-time) timeout=$2; shift ;; --connect-timeout) connect=$2; shift ;; esac
  shift
 done
 [[ "$timeout" == 1 && "$connect" == 1 ]] || return 99
 printf '%s\n' "$args" >> "$d/attempts"
 sleep "$timeout"
 return 28
}
start=$(date +%s)
if get_all_optimized_ips > "$d/log" 2>&1; then echo 'accepted unavailable providers'; exit 1; fi
elapsed=$(( $(date +%s) - start ))
[[ "$elapsed" -le 5 ]]
[[ $(wc -l < "$d/attempts") -le 4 ]]
grep -q 'type=v4' "$d/attempts"
grep -q 'type=v6' "$d/attempts"
grep -q '总等待预算 4 秒' "$d/log"
# No per-request caller timeout can defeat the global default budget.
[[ $(grep -c -- '--max-time 1' "$d/attempts") == "$(wc -l < "$d/attempts" | tr -d ' ')" ]]
printf 'Provider failure bounded to %s seconds; both families received attempts.\n' "$elapsed"
# The default public-page path does not depend on a shared API key and reserves
# one fair request per family without probing this VPS's own IP connectivity.
CFY_OPTIMIZED_IP_API_KEY=''
: > "$d/attempts"
curl() {
 local args=" $* "
 [[ "$args" == *'--max-time 2 '* && "$args" != *'key='* ]] || return 99
 printf '%s\n' "$args" >> "$d/attempts"
 return 28
}
if get_all_optimized_ips > "$d/log" 2>&1; then exit 1; fi
[[ $(wc -l < "$d/attempts") == 2 ]]
grep -q 'cloudflare/address_v4.html' "$d/attempts"
grep -q 'cloudflare/address_v6.html' "$d/attempts"
echo 'Public pages remain available without an API key.'
