#!/usr/bin/env bash
set -euo pipefail
repo=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
source <(sed -n '/^[A-Za-z_][A-Za-z_0-9]*() {/,/^}/p' "$repo/cfy.sh")
d=$(mktemp -d); trap 'rm -rf "$d"' EXIT
GREEN='' RED='' YELLOW='' NC=''; IP_VERSION_SCOPE=ipv4
CFY_SOURCE_MAX_TIME=4 CFY_CURL_MAX_TIME=1 CFY_CURL_CONNECT_TIMEOUT=1
# A provider without Content-Length is still bounded by the stream cap.
curl() {
 [[ " $* " == *' --max-filesize 1048576 '* ]] || return 99
 head -c 3145728 /dev/zero | tr '\0' A
}
if get_all_optimized_ips > "$d/log" 2>&1; then echo 'oversized provider accepted'; exit 1; fi
! grep -q '取得 .* 个候选' "$d/log"
echo 'Oversized/chunked provider responses are rejected before candidate parsing.'
