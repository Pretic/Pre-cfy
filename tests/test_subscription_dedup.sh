#!/usr/bin/env bash

set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cfy_script="${repo_root}/cfy.sh"

extract_function() {
    local function_name="$1"
    sed -n "/^${function_name}() {/,/^}/p" "${cfy_script}"
}

source <(extract_function sync_combined_subscription)

fixture_dir="$(mktemp -d)"
trap 'rm -rf "${fixture_dir}"' EXIT

URL_FILE="${fixture_dir}/url.txt"
RESULT_FILE="${fixture_dir}/cfy-url.txt"
COMBINED_URL_FILE="${fixture_dir}/all-url.txt"
COMBINED_SUB_FILE="${fixture_dir}/all-sub.txt"
SERVED_SUB_FILE="${fixture_dir}/sub.txt"

write_base64_file() { return 0; }

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

sync_combined_subscription

expected=$'vless://base-a\nvless://shared\nvless://same-fields#remark-one\nvless://result-b\nvless://same-fields#remark-two'
actual="$(cat "${COMBINED_URL_FILE}")"

if [[ "${actual}" != "${expected}" ]]; then
    printf 'FAIL: combined subscription was not deduplicated in first-occurrence order\nExpected:\n%s\nActual:\n%s\n' "${expected}" "${actual}" >&2
    exit 1
fi

echo 'Combined subscription deduplication tests passed.'
