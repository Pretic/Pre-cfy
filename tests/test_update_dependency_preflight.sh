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
    grep -Fq "${missing_dependency}" "${case_dir}/output" || {
        echo "FAIL: missing ${missing_dependency} diagnostic named the wrong dependency" >&2
        return 1
    }
)

run_missing_dependency_case flock
run_missing_dependency_case sha256sum
run_missing_dependency_case stat

# getent is needed only when an administrator selects a named trusted group.
command() {
    if [[ "${1:-}" == '-v' && "${2:-}" == getent ]]; then
        return 1
    fi
    builtin command "$@"
}
unset SING_BOX_TRANSACTION_GROUP
check_update_dependencies || {
    echo 'FAIL: getent was required without a trusted group' >&2
    exit 1
}
SING_BOX_TRANSACTION_GROUP="$(id -g)"
check_update_dependencies || {
    echo 'FAIL: getent was required for a numeric trusted group' >&2
    exit 1
}
SING_BOX_TRANSACTION_GROUP='cfy-named-test-group'
if check_update_dependencies >/dev/null 2>&1; then
    echo 'FAIL: named trusted group did not require getent' >&2
    exit 1
fi
unset SING_BOX_TRANSACTION_GROUP
unset -f command

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

bash_env="${test_dir}/entry-bash-env"
cat > "${bash_env}" <<'EOF'
command() {
    if [[ "${1:-}" == '-v' && -n "${MISSING_DEPENDENCY:-}" && "${2:-}" == "${MISSING_DEPENDENCY}" ]]; then
        return 1
    fi
    builtin command "$@"
}
id() {
    if [[ "${1:-}" == '-u' ]]; then
        printf '0\n'
    else
        /usr/bin/id "$@"
    fi
}
curl() {
    local output_file=''
    while [[ "$#" -gt 0 ]]; do
        if [[ "$1" == '-o' ]]; then
            shift
            output_file="$1"
        fi
        shift
    done
    : > "${ENTRY_CURL_MARKER}"
    /bin/cp "${ENTRY_SCRIPT_FIXTURE}" "${output_file}"
}
cp() {
    : > "${ENTRY_CP_MARKER}"
    /bin/cp "$@"
}
install() {
    : > "${ENTRY_INSTALL_MARKER}"
    /usr/bin/install "$@"
}
EOF

run_real_entry_case() {
    local mode="$1" missing_dependency="$2" expect_success="$3"
    local case_name="${mode}-${missing_dependency:-complete}"
    local case_dir="${test_dir}/entry-${case_name}"
    local entry_script installed_script status
    mkdir -p "${case_dir}"
    entry_script="${case_dir}/cfy-entry.sh"
    installed_script="${case_dir}/installed-cfy"
    sed "s|^INSTALL_PATH=\"/usr/local/bin/cfy\"|INSTALL_PATH=\"${installed_script}\"|" \
        "${cfy_script}" > "${entry_script}"
    chmod +x "${entry_script}"
    printf '%s\n' 'existing-entry-version' > "${installed_script}"

    export MISSING_DEPENDENCY="${missing_dependency}"
    export ENTRY_SCRIPT_FIXTURE="${entry_script}"
    export ENTRY_CURL_MARKER="${case_dir}/curl-started"
    export ENTRY_CP_MARKER="${case_dir}/cp-started"
    export ENTRY_INSTALL_MARKER="${case_dir}/install-started"
    export SERVED_SUB_FILE="${case_dir}/served-sub.txt"

    set +e
    if [[ "${mode}" == 'process' ]]; then
        BASH_ENV="${bash_env}" bash <(cat "${entry_script}") --update >"${case_dir}/output" 2>&1
    else
        BASH_ENV="${bash_env}" bash "${entry_script}" --update >"${case_dir}/output" 2>&1
    fi
    status=$?
    set -e

    if [[ "${expect_success}" == 'no' ]]; then
        [[ ! -e "${ENTRY_CURL_MARKER}" ]] || {
            echo "FAIL: ${mode} entry update download started without ${missing_dependency}" >&2
            return 1
        }
        [[ ! -e "${ENTRY_CP_MARKER}" ]] || {
            echo "FAIL: ${mode} entry update copy started without ${missing_dependency}" >&2
            return 1
        }
        [[ ! -e "${ENTRY_INSTALL_MARKER}" ]] || {
            echo "FAIL: ${mode} entry update install started without ${missing_dependency}" >&2
            return 1
        }
        [[ "${status}" -ne 0 ]] || {
            echo "FAIL: ${mode} entry update succeeded without ${missing_dependency}" >&2
            return 1
        }
        [[ "$(<"${installed_script}")" == 'existing-entry-version' ]] || {
            echo "FAIL: ${mode} entry update replaced the installed script without ${missing_dependency}" >&2
            return 1
        }
        return 0
    fi

    [[ "${status}" -eq 0 ]] || {
        echo "FAIL: dependency-complete ${mode} entry update failed" >&2
        return 1
    }
    [[ -e "${ENTRY_CP_MARKER}" ]] || {
        echo "FAIL: dependency-complete ${mode} entry update skipped its copy step" >&2
        return 1
    }
    if [[ "${mode}" == 'process' ]]; then
        [[ -e "${ENTRY_CURL_MARKER}" ]] || {
            echo 'FAIL: dependency-complete process entry update skipped its download step' >&2
            return 1
        }
    fi
    grep -q '^REMOTE_URL=' "${installed_script}" || {
        echo "FAIL: dependency-complete ${mode} entry update did not replace the installed script" >&2
        return 1
    }
}

for dependency in flock sha256sum stat; do
    run_real_entry_case file "${dependency}" no
    run_real_entry_case process "${dependency}" no
done
run_real_entry_case file '' yes
run_real_entry_case process '' yes

echo 'Update dependency preflight tests passed.'
