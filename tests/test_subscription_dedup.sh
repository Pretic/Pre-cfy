#!/usr/bin/env bash

set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cfy_script="${repo_root}/cfy.sh"

extract_function() {
    local function_name="$1"
    sed -n "/^${function_name}() {/,/^}/p" "${cfy_script}"
}

# Deduplication is a pure publication test.  Stable/legacy lock semantics have
# their own focused regression suite; use an isolated held-lock scope here.
with_subscription_lock() {
    local SUBSCRIPTION_LOCK_HELD=1
    "$@"
}
source <(extract_function get_subscription_source_generation)
source <(extract_function read_strict_subscription_generation_file)
source <(extract_function read_cfy_source_generation_file)
source <(extract_function select_existing_cfy_subscription_source_locked)
source <(extract_function encode_subscription_source)
source <(extract_function publish_subscriptions_locked)
source <(extract_function sync_combined_subscription)

fixture_dir="$(mktemp -d)"
trap 'rm -rf "${fixture_dir}"' EXIT

URL_FILE="${fixture_dir}/url.txt"
RESULT_FILE="${fixture_dir}/cfy-url.txt"
SUB_FILE="${fixture_dir}/cfy-sub.txt"
COMBINED_URL_FILE="${fixture_dir}/all-url.txt"
COMBINED_SUB_FILE="${fixture_dir}/all-sub.txt"
SERVED_SUB_FILE="${fixture_dir}/sub.txt"
CFY_SOURCE_GENERATION_FILE="${fixture_dir}/cfy-source.generation"

printf '%s\n' \
    'vless://base-a' \
    'vless://shared' \
    '' \
    'vless://same-fields#remark-one' > "${URL_FILE}"

printf '%s\r\n' \
    'vless://shared' \
    'vless://result-b' \
    'vless://same-fields#remark-two' \
    'vless://result-b' > "${RESULT_FILE}"
printf '%s\n' "$(get_subscription_source_generation "$URL_FILE")" > "$CFY_SOURCE_GENERATION_FILE"
chmod 600 "$CFY_SOURCE_GENERATION_FILE"

sync_combined_subscription

expected=$'vless://base-a\nvless://shared\nvless://same-fields#remark-one\nvless://result-b\nvless://same-fields#remark-two'
actual="$(cat "${COMBINED_URL_FILE}")"

if [[ "${actual}" != "${expected}" ]]; then
    printf 'FAIL: combined subscription was not deduplicated in first-occurrence order\nExpected:\n%s\nActual:\n%s\n' "${expected}" "${actual}" >&2
    exit 1
fi

echo 'Combined subscription deduplication tests passed.'
