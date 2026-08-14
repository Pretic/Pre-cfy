#!/usr/bin/env bash

set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cfy_script="${repo_root}/cfy.sh"

extract_function() {
    local function_name="$1"
    sed -n "/^${function_name}() {/,/^}/p" "${cfy_script}"
}

source <(extract_function atomic_write_file)
source <(extract_function write_text_file)
source <(extract_function write_base64_file)

test_dir="$(mktemp -d)"
trap 'rm -rf "${test_dir}"' EXIT

plain_file="${test_dir}/url.txt"
source_file="${test_dir}/source.txt"
base64_file="${test_dir}/sub.txt"

write_text_file "${plain_file}" 'vless://secret@example.test'
printf '%s\n' 'subscription-secret' > "${source_file}"
write_base64_file "${source_file}" "${base64_file}"

text_writer_source="$(extract_function write_text_file)"
grep -q 'atomic_write_file.*600' <<< "${text_writer_source}" || {
    echo 'FAIL: plaintext subscription writer must request mode 600' >&2
    exit 1
}
base64_writer_source="$(extract_function write_base64_file)"
grep -q 'chmod 600.*tmp_file' <<< "${base64_writer_source}" || {
    echo 'FAIL: encoded subscription writer must request mode 600' >&2
    exit 1
}

case "$(uname -s)" in
    MINGW*|MSYS*|CYGWIN*) ;;
    *)
        [[ "$(stat -c '%a' "${plain_file}")" == '600' ]] || {
            echo 'FAIL: plaintext subscription output must use mode 600' >&2
            exit 1
        }
        [[ "$(stat -c '%a' "${base64_file}")" == '600' ]] || {
            echo 'FAIL: encoded subscription output must use mode 600' >&2
            exit 1
        }
        ;;
esac
grep -q '^umask 077$' "${cfy_script}" || {
    echo 'FAIL: cfy must set a restrictive process umask' >&2
    exit 1
}

combined_source="$(extract_function sync_combined_subscription)"
grep -q 'chmod 600.*COMBINED_URL_FILE\|chmod 600.*tmp_file' <<< "${combined_source}" || {
    echo 'FAIL: combined plaintext subscription output must use mode 600' >&2
    exit 1
}

echo 'Secure output permission tests passed.'
