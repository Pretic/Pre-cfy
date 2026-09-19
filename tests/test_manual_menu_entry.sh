#!/usr/bin/env bash
set -euo pipefail
repo=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
source <(sed -n '/^[A-Za-z_][A-Za-z_0-9]*() {/,/^}/p' "$repo/cfy.sh")
d=$(mktemp -d); trap 'rm -rf "$d"' EXIT
GREEN='' YELLOW='' RED='' NC=''
CFY_CURL_CONNECT_TIMEOUT=1 CFY_CURL_MAX_TIME=1 CFY_HEALTH_PROBE=1
CFY_EXTERNAL_ROOT="$d/external"; unset SING_BOX_TRANSACTION_GROUP
URL_FILE="$d/source.txt"
v='vless://00000000-0000-4000-8000-000000000001@cdn.example.com:443?security=tls&type=ws&path=%2Fsocket#local'
manual='vless://00000000-0000-4000-8000-000000000002@other.example.com:443?security=tls&type=ws&path=%2Fmanual#manual'
printf '%s\n' "$v" > "$URL_FILE"
RESULT_FILE="$d/sb-result"; SUB_FILE="$d/sb-sub"; COMBINED_URL_FILE="$d/sb-all"
COMBINED_SUB_FILE="$d/sb-allsub"; SERVED_SUB_FILE="$d/sb-served"
RESULT_DIR="$d/history"; SUBSCRIPTION_LOCK_FILE="$d/sub.lock"
CFY_SOURCE_GENERATION_FILE="$d/generation"; SING_BOX_TRANSACTION_ROOT="$d/transactions"
printf 'unchanged\n' > "$RESULT_FILE"; saved=$(sha256sum "$RESULT_FILE")
curl() { printf '104.16.0.0/13\n'; }
probe_vless_edge_candidate() { return 0; }
# Exactly ONE local node must still offer a manual option.
printf '0\n%s\n1\n1\n' "$manual" > "$d/input"
main < "$d/input" > "$d/log" 2>&1
[[ $(sha256sum "$d/sb-result") == "$saved" ]]
grep -q '0) 手动粘贴' "$d/log"
grep -q 'sni=other.example.com' "$RESULT_FILE"
[[ "$RESULT_FILE" == "$d/external/manual/cfy-url.txt" ]]
[[ $(cat "$d/source.txt") == "$v" ]]
# --manual still starts by asking for a link, without an extra selection prompt.
(
 CFY_FORCE_MANUAL=1; CFY_TEMPLATE_FILE=''; MANUAL_TEMPLATE=''
 printf '%s\n1\n1\n' "$manual" > "$d/direct-input"
 main < "$d/direct-input" > "$d/direct-log" 2>&1
 if grep -q '请选择节点' "$d/direct-log"; then exit 1; fi
)
# EOF at the visible menu exits rather than accepting an unrelated default.
(
 CFY_FORCE_MANUAL=0; CFY_TEMPLATE_FILE=''; URL_FILE="$d/source.txt"
 if main </dev/null >/dev/null 2>&1; then exit 1; fi
)
echo 'Visible manual entry with existing node, independent output, direct manual and EOF tests passed.'
