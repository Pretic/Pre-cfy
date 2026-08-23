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
source <(extract_function encode_subscription_source)
source <(extract_function write_base64_file)
source <(extract_function repair_served_subscription_file)

test_dir="$(mktemp -d)"
trap 'rm -rf "${test_dir}"' EXIT

plain_file="${test_dir}/url.txt"
source_file="${test_dir}/source.txt"
base64_file="${test_dir}/sub.txt"
served_file="${test_dir}/served-sub.txt"
migration_file="${test_dir}/existing-served-sub.txt"

write_text_file "${plain_file}" 'vless://secret@example.test'
printf '%s\n' 'subscription-secret' > "${source_file}"
write_base64_file "${source_file}" "${base64_file}"
write_base64_file "${source_file}" "${served_file}" 644
printf '%s\n' 'existing-subscription' > "${migration_file}"
chmod 600 "${migration_file}" 2>/dev/null || true
SERVED_SUB_FILE="${migration_file}"
repair_served_subscription_file

text_writer_source="$(extract_function write_text_file)"
grep -q 'atomic_write_file.*600' <<< "${text_writer_source}" || {
    echo 'FAIL: plaintext subscription writer must request mode 600' >&2
    exit 1
}
base64_writer_source="$(extract_function write_base64_file)"
grep -q 'output_mode=.*3:-600' <<< "${base64_writer_source}" || {
    echo 'FAIL: encoded subscription writer must default to mode 600' >&2
    exit 1
}
grep -q 'chmod.*output_mode.*tmp_file' <<< "${base64_writer_source}" || {
    echo 'FAIL: encoded subscription writer must apply the requested mode' >&2
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
        [[ "$(stat -c '%a' "${served_file}")" == '644' ]] || {
            echo 'FAIL: Nginx-served subscription output must use mode 644' >&2
            exit 1
        }
        [[ "$(stat -c '%a' "${migration_file}")" == '644' ]] || {
            echo 'FAIL: an existing served subscription must be repaired to mode 644' >&2
            exit 1
        }
        ;;
esac
grep -q '^umask 077$' "${cfy_script}" || {
    echo 'FAIL: cfy must set a restrictive process umask' >&2
    exit 1
}

combined_source="$(extract_function publish_subscriptions_locked)"
grep -q 'chmod 600.*tmp_base_sub.*tmp_cfy_sub.*tmp_all_url.*tmp_all_sub' <<< "${combined_source}" || {
    echo 'FAIL: combined plaintext subscription output must use mode 600' >&2
    exit 1
}
grep -q 'chmod 644.*tmp_sub' <<< "${combined_source}" || {
    echo 'FAIL: Nginx-served subscription must explicitly request mode 644' >&2
    exit 1
}

finish_install_source="$(extract_function finish_install)"
grep -q 'repair_served_subscription_file' <<< "${finish_install_source}" || {
    echo 'FAIL: remote install/update must repair an existing served subscription' >&2
    exit 1
}

update_source="$(extract_function update_self)"
grep -q 'repair_served_subscription_file' <<< "${update_source}" || {
    echo 'FAIL: installed cfy --update must repair an existing served subscription' >&2
    exit 1
}

echo 'Secure output permission tests passed.'
