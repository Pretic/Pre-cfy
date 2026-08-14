#!/usr/bin/env bash

set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cfy_script="${repo_root}/cfy.sh"

extract_function() {
    local function_name="$1"
    sed -n "/^${function_name}() {/,/^}/p" "${cfy_script}"
}

ranker_source="$(extract_function collect_ranked_optimized_pairs)"
if [[ -z "${ranker_source}" ]]; then
    echo "FAIL: collect_ranked_optimized_pairs is not implemented" >&2
    exit 1
fi

source <(extract_function is_ipv6_edge)
source <(extract_function get_edge_ip_version)
source <(extract_function is_valid_edge_address)
source <(printf '%s\n' "${ranker_source}")

fixture="$(mktemp)"
trap 'rm -f "${fixture}"' EXIT
cat > "${fixture}" <<'EOF'
104.17.0.1|Mobile|120
104.17.0.2|Mobile|80
104.17.0.3|Mobile|90
104.17.0.4|Mobile|150
104.17.0.5|Mobile|70
104.18.0.1|Unicom|200
104.18.0.2|Unicom|180
104.18.0.3|Unicom|190
104.18.0.4|Unicom|170
104.17.0.2|Mobile|40
2606:4700::1|Mobile|100
2606:4700::2|Mobile|90
2606:4700::3|Mobile|110
2606:4700::4|Mobile|80
EOF

collect_ranked_optimized_pairs "${fixture}" 3

expected_ips="104.17.0.5 104.17.0.2 104.17.0.3 104.18.0.4 104.18.0.2 104.18.0.3 2606:4700::4 2606:4700::2 2606:4700::1"
expected_isps="Mobile Mobile Mobile Unicom Unicom Unicom Mobile Mobile Mobile"

if [[ "${ip_list[*]}" != "${expected_ips}" ]]; then
    echo "FAIL: candidates were not ranked by RTT and limited per ISP/family: ${ip_list[*]}" >&2
    exit 1
fi

if [[ "${isp_list[*]}" != "${expected_isps}" ]]; then
    echo "FAIL: ISP labels changed while ranking: ${isp_list[*]}" >&2
    exit 1
fi

echo "Candidate quality ranking tests passed."
