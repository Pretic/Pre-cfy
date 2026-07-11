#!/usr/bin/env bash

set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cfy_script="${repo_root}/cfy.sh"

extract_function() {
    local function_name="$1"
    sed -n "/^${function_name}() {/,/^}/p" "${cfy_script}"
}

collector_source="$(extract_function collect_unique_optimized_pairs)"
if [[ -z "${collector_source}" ]]; then
    echo "FAIL: collect_unique_optimized_pairs is not implemented" >&2
    exit 1
fi

source <(printf '%s\n' "${collector_source}")

fixture="$(mktemp)"
trap 'rm -f "${fixture}"' EXIT
cat > "${fixture}" <<'EOF'
198.41.223.37 Telecom
162.159.48.183 Telecom
198.41.223.37 Unicom
2606:4700:5a::fdad:1074 Unicom
162.159.48.183 Mobile
EOF

collect_unique_optimized_pairs "${fixture}"

expected_ips="198.41.223.37 162.159.48.183 2606:4700:5a::fdad:1074"
expected_isps="Telecom Telecom Unicom"

if [[ "${ip_list[*]}" != "${expected_ips}" ]]; then
    echo "FAIL: candidate IP order or deduplication changed: ${ip_list[*]}" >&2
    exit 1
fi

if [[ "${isp_list[*]}" != "${expected_isps}" ]]; then
    echo "FAIL: the first ISP label was not preserved: ${isp_list[*]}" >&2
    exit 1
fi

selector_source="$(extract_function choose_ip_version_scope)"
source <(printf '%s\n' "${selector_source}")

YELLOW=''
RED=''
NC=''

CFY_IP_VERSION_SCOPE=''
IP_VERSION_SCOPE=''
choose_ip_version_scope <<< '' >/dev/null
[[ "${IP_VERSION_SCOPE}" == 'ipv4' ]] || { echo 'FAIL: Enter must default to IPv4' >&2; exit 1; }

CFY_IP_VERSION_SCOPE=''
IP_VERSION_SCOPE=''
choose_ip_version_scope <<< '2' >/dev/null
[[ "${IP_VERSION_SCOPE}" == 'both' ]] || { echo 'FAIL: option 2 must select dual stack' >&2; exit 1; }

CFY_IP_VERSION_SCOPE=''
IP_VERSION_SCOPE=''
choose_ip_version_scope <<< '3' >/dev/null
[[ "${IP_VERSION_SCOPE}" == 'ipv6' ]] || { echo 'FAIL: option 3 must select IPv6' >&2; exit 1; }

echo 'Candidate selection tests passed.'
