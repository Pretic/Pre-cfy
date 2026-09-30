#!/usr/bin/env bash
set -euo pipefail
repo=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
source <(sed -n '/^[A-Za-z_][A-Za-z_0-9]*() {/,/^}/p' "$repo/cfy.sh")
d=$(mktemp -d); trap 'rm -rf "$d"' EXIT
GREEN='' RED='' YELLOW='' NC=''
URL_FILE="$d/url.txt" RESULT_FILE="$d/cfy-url.txt" SUB_FILE="$d/cfy-sub.txt" COMBINED_URL_FILE="$d/all-url.txt" COMBINED_SUB_FILE="$d/all-sub.txt" SERVED_SUB_FILE="$d/sub.txt" SUBSCRIPTION_LOCK_FILE="$d/.subscription.lock" CFY_SOURCE_GENERATION_FILE="$d/cfy-source.generation" RESULT_DIR="$d/history" BASE_SUB_FILE="$d/base-sub.txt" SING_BOX_TRANSACTION_ROOT="$d/transactions"
printf 'vless://base\n' > "$URL_FILE"
load_source_urls
generated_urls=('vless://old'); save_generated_urls >/dev/null
targets=("$RESULT_FILE" "$CFY_SOURCE_GENERATION_FILE" "$BASE_SUB_FILE" "$SUB_FILE" "$COMBINED_URL_FILE" "$COMBINED_SUB_FILE" "$SERVED_SUB_FILE")
mkdir "$d/before"
for i in "${!targets[@]}"; do cp -p "${targets[$i]}" "$d/before/$i"; done
for signal in INT TERM HUP; do
 for target in "${targets[@]}"; do
  rc=0
  (
   trap - EXIT
   fired=0
   mv() {
    command mv "$@" || return $?
    if [[ "$fired" == 0 && "${*: -1}" == "$target" ]]; then
     fired=1; kill -"$signal" "$BASHPID"
     # Model a rename that committed before its process was interrupted.
     return 143
    fi
   }
   generated_urls=('vless://new')
   save_generated_urls >/dev/null
  ) || rc=$?
  if [[ "$signal" == INT ]]; then [[ "$rc" == 130 ]]; else [[ "$rc" == 143 ]]; fi
  for i in "${!targets[@]}"; do cmp "${targets[$i]}" "$d/before/$i"; done
  with_subscription_lock true
 done
done
# A subsequent successful generation is still possible and releases the lock.
generated_urls=('vless://after'); save_generated_urls >/dev/null
grep -qx 'vless://after' "$RESULT_FILE"
echo 'INT/TERM/HUP at all seven commit targets restores the complete old generation and releases locks.'
