#!/usr/bin/env bash
set -euo pipefail
script="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/cfy.sh"
tmp_root=$(mktemp -d)
trap 'rm -rf "$tmp_root"' EXIT
fail() { printf 'FAIL: %s\n' "$*" >&2; exit 1; }
for name in show_saved_results show_saved_results_locked get_subscription_source_generation \
    read_cfy_source_generation_file read_strict_subscription_generation_file; do
    source /dev/stdin <<< "$(sed -n "/^${name}() {/,/^}/p" "$script")"
done
GREEN=''; YELLOW=''; NC=''
URL_FILE="$tmp_root/url.txt"
RESULT_FILE="$tmp_root/cfy-url.txt"
CFY_SOURCE_GENERATION_FILE="$tmp_root/cfy-source.generation"
SUB_FILE="$tmp_root/cfy-sub.txt"
COMBINED_SUB_FILE="$tmp_root/all-sub.txt"
SERVED_SUB_FILE="$tmp_root/sub.txt"
RESULT_DIR="$tmp_root"
with_subscription_lock() { local SUBSCRIPTION_LOCK_HELD=1; "$@"; }
show_source_templates() { printf 'current-template\n'; }
old='vless://fixture@192.0.2.1:443?host=old.example.com&path=%2Fvless-argo'
printf '%s\n' "$old" > "$URL_FILE"
get_subscription_source_generation > "$CFY_SOURCE_GENERATION_FILE"
chmod 600 "$CFY_SOURCE_GENERATION_FILE"
printf '%s\n' "$old" > "$RESULT_FILE"
printf 'new base\n' > "$URL_FILE"
before=$(sha256sum "$RESULT_FILE" "$CFY_SOURCE_GENERATION_FILE")
output=$(show_saved_results) || true
[[ "$output" != *"$old"* ]] || fail 'cfy -c printed an obsolete optimized URL'
[[ "$output" == *过期* && "$output" == *cfy* ]] || fail 'missing regeneration instruction'
[[ "$before" = "$(sha256sum "$RESULT_FILE" "$CFY_SOURCE_GENERATION_FILE")" ]] || fail 'display modified results'
get_subscription_source_generation > "$CFY_SOURCE_GENERATION_FILE"
output=$(show_saved_results)
[[ "$output" == *"$old"* ]] || fail 'matching generation was not displayed'
rm "$CFY_SOURCE_GENERATION_FILE"
output=$(show_saved_results) || true
[[ "$output" != *"$old"* ]] || fail 'missing generation exposed unverified links'
get_subscription_source_generation > "$CFY_SOURCE_GENERATION_FILE"
chmod 600 "$CFY_SOURCE_GENERATION_FILE"
mv "$RESULT_FILE" "$tmp_root/history.txt"
ln -s "$tmp_root/history.txt" "$RESULT_FILE"
output=$(show_saved_results) || true
[[ "$output" != *"$old"* ]] || fail 'symlink result was displayed'
rm "$RESULT_FILE"
output=$(show_saved_results)
[[ "$output" == *current-template* ]] || fail 'missing results no longer show templates'
printf 'Current cfy display tests passed.\n'
