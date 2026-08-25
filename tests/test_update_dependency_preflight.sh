#!/usr/bin/env bash

set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cfy_script="${repo_root}/cfy.sh"

extract_function() {
    local function_name="$1"
    sed -n "/^${function_name}() {/,/^}/p" "${cfy_script}"
}

source <(extract_function repair_served_subscription_file)
source <(extract_function show_update_done)
source <(extract_function check_update_dependencies)
source <(extract_function update_self)

test_dir="$(mktemp -d)"
trap 'rm -rf "${test_dir}"' EXIT

GREEN=''
YELLOW=''
RED=''
NC=''
REMOTE_URL='https://example.invalid/cfy.sh'
SERVED_SUB_FILE="${test_dir}/served-sub.txt"

id() {
    printf '0\n'
}

run_missing_dependency_case() (
    local missing_dependency="$1"
    local case_dir="${test_dir}/missing-${missing_dependency}"
    mkdir -p "${case_dir}"
    INSTALL_PATH="${case_dir}/cfy"
    printf '%s\n' 'existing-version' > "${INSTALL_PATH}"
    download_marker="${case_dir}/download-started"
    install_marker="${case_dir}/install-started"

    command() {
        if [[ "${1:-}" == '-v' && "${2:-}" == "${missing_dependency}" ]]; then
            return 1
        fi
        builtin command "$@"
    }
    curl() {
        : > "${download_marker}"
        return 1
    }
    install() {
        : > "${install_marker}"
        return 1
    }

    set +e
    ( update_self ) >"${case_dir}/output" 2>&1
    local status=$?
    set -e

    [[ "${status}" -ne 0 ]] || {
        echo "FAIL: update succeeded without ${missing_dependency}" >&2
        return 1
    }
    [[ ! -e "${download_marker}" ]] || {
        echo "FAIL: update download started without ${missing_dependency}" >&2
        return 1
    }
    [[ ! -e "${install_marker}" ]] || {
        echo "FAIL: installed cfy was replaced without ${missing_dependency}" >&2
        return 1
    }
    [[ "$(<"${INSTALL_PATH}")" == 'existing-version' ]] || {
        echo "FAIL: installed cfy content changed without ${missing_dependency}" >&2
        return 1
    }
)

run_missing_dependency_case flock
run_missing_dependency_case sha256sum

success_dir="${test_dir}/success"
mkdir -p "${success_dir}"
INSTALL_PATH="${success_dir}/cfy"
printf '%s\n' 'existing-version' > "${INSTALL_PATH}"
download_marker="${success_dir}/download-started"
install_marker="${success_dir}/install-started"

curl() {
    local output_file=''
    while [[ "$#" -gt 0 ]]; do
        if [[ "$1" == '-o' ]]; then
            shift
            output_file="$1"
        fi
        shift
    done
    : > "${download_marker}"
    printf '%s\n' \
        '#!/usr/bin/env bash' \
        'INSTALL_PATH="/usr/local/bin/cfy"' \
        'printf "%s\\n" updated-version' > "${output_file}"
}

install() {
    local source_file="${@: -2:1}"
    local target_file="${@: -1}"
    : > "${install_marker}"
    cp "${source_file}" "${target_file}"
}

update_self >"${success_dir}/output" 2>&1
[[ -e "${download_marker}" ]] || {
    echo 'FAIL: dependency-complete update did not retain the download step' >&2
    exit 1
}
[[ -e "${install_marker}" ]] || {
    echo 'FAIL: dependency-complete update did not retain the install step' >&2
    exit 1
}
grep -q 'updated-version' "${INSTALL_PATH}" || {
    echo 'FAIL: dependency-complete update did not replace the installed script' >&2
    exit 1
}

echo 'Update dependency preflight tests passed.'
