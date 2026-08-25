#!/usr/bin/env bash

set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cfy_script="${repo_root}/cfy.sh"

extract_function() {
    local function_name="$1"
    sed -n "/^${function_name}() {/,/^}/p" "${cfy_script}"
}

source <(extract_function is_ipv6_edge)
source <(extract_function get_edge_ip_version)
source <(extract_function is_valid_edge_address)
source <(extract_function normalize_edge_latency)
source <(extract_function decimal_latency_less_than)
source <(extract_function collect_ranked_optimized_pairs)

fixture="$(mktemp)"
rank_stderr="$(mktemp)"
trap 'rm -f "${fixture}" "${rank_stderr}"' EXIT
cat > "${fixture}" <<'EOF'
104.17.0.1|Mobile|-1
104.17.0.2|Mobile|
104.17.0.3|Mobile|timeout
104.17.0.4|Mobile|0
104.17.0.5|Mobile|45
104.17.0.6|Mobile|20
104.17.0.7|Mobile|1000000
104.17.0.8|Mobile|1000001
104.17.0.9|Mobile|999999999999999999999999999999
104.17.0.10|Mobile|15
104.17.0.11|Mobile|00000017
2606:4700::1|Mobile|-1
2606:4700::2|Mobile|
2606:4700::3|Mobile|timed_out
2606:4700::4|Mobile|0
2606:4700::5|Mobile|50
2606:4700::6|Mobile|30
2606:4700::7|Mobile|1000000
2606:4700::8|Mobile|1000001
2606:4700::9|Mobile|999999999999999999999999999998
2606:4700::10|Mobile|25
2606:4700::11|Mobile|00000027
EOF

collect_ranked_optimized_pairs "${fixture}" 10 both 2>"${rank_stderr}"

if [[ -s "${rank_stderr}" ]]; then
    echo "FAIL: large decimal RTT comparison wrote to stderr: $(<"${rank_stderr}")" >&2
    exit 1
fi

expected_ips="104.17.0.10 104.17.0.11 104.17.0.6 104.17.0.5 104.17.0.7 104.17.0.8 104.17.0.9 2606:4700::10 2606:4700::11 2606:4700::6 2606:4700::5 2606:4700::7 2606:4700::8 2606:4700::9"
if [[ "${ip_list[*]}" != "${expected_ips}" ]]; then
    echo "FAIL: valid decimal RTT candidates were not filtered and ranked correctly: ${ip_list[*]}" >&2
    exit 1
fi

if [[ "${#ip_list[@]}" -ne 14 ]]; then
    echo "FAIL: sparse quality results must not be padded to the per-group limit" >&2
    exit 1
fi

source <(extract_function get_candidate_group_limit)
source <(extract_function get_all_optimized_ips)

GREEN=''
YELLOW=''
RED=''
NC=''
CFY_CURL_CONNECT_TIMEOUT=1
CFY_CURL_MAX_TIME=1
CFY_PER_ISP_LIMIT=5
IP_VERSION_SCOPE=both

curl() {
    local url="${!#}"
    case "${url}" in
        *address_v4.html)
            printf '%s\n' \
                '<tr><td data-label="优选地址">104.18.0.1</td><td data-label="线路名称">Mobile</td><td data-label="往返延迟">-1 ms</td></tr>' \
                '<tr><td data-label="优选地址">104.18.0.2</td><td data-label="线路名称">Mobile</td><td data-label="往返延迟"></td></tr>' \
                '<tr><td data-label="优选地址">104.18.0.3</td><td data-label="线路名称">Mobile</td><td data-label="往返延迟">timeout</td></tr>' \
                '<tr><td data-label="优选地址">104.18.0.4</td><td data-label="线路名称">Mobile</td><td data-label="往返延迟">N/A</td></tr>' \
                '<tr><td data-label="优选地址">104.18.0.5</td><td data-label="线路名称">Mobile</td><td data-label="往返延迟">0 ms</td></tr>' \
                '<tr><td data-label="优选地址">104.18.0.6</td><td data-label="线路名称">Mobile</td><td data-label="往返延迟">45 ms</td></tr>' \
                '<tr><td data-label="优选地址">104.18.0.7</td><td data-label="线路名称">Mobile</td><td data-label="往返延迟">20</td></tr>'
            ;;
        *address_v6.html)
            printf '%s\n' \
                '<tr><td data-label="优选地址">2606:4700:1::1</td><td data-label="线路名称">Mobile</td><td data-label="往返延迟">-1 ms</td></tr>' \
                '<tr><td data-label="优选地址">2606:4700:1::2</td><td data-label="线路名称">Mobile</td><td data-label="往返延迟"></td></tr>' \
                '<tr><td data-label="优选地址">2606:4700:1::3</td><td data-label="线路名称">Mobile</td><td data-label="往返延迟">timed out</td></tr>' \
                '<tr><td data-label="优选地址">2606:4700:1::4</td><td data-label="线路名称">Mobile</td><td data-label="往返延迟">unknown</td></tr>' \
                '<tr><td data-label="优选地址">2606:4700:1::5</td><td data-label="线路名称">Mobile</td><td data-label="往返延迟">0</td></tr>' \
                '<tr><td data-label="优选地址">2606:4700:1::6</td><td data-label="线路名称">Mobile</td><td data-label="往返延迟">50 ms</td></tr>' \
                '<tr><td data-label="优选地址">2606:4700:1::7</td><td data-label="线路名称">Mobile</td><td data-label="往返延迟">30</td></tr>'
            ;;
        *)
            return 1
            ;;
    esac
}

get_all_optimized_ips >/dev/null
expected_ips="104.18.0.7 104.18.0.6 2606:4700:1::7 2606:4700:1::6"
if [[ "${ip_list[*]}" != "${expected_ips}" ]]; then
    echo "FAIL: HTML parsing admitted invalid RTT candidates: ${ip_list[*]}" >&2
    exit 1
fi

echo 'Invalid candidate RTT filtering tests passed.'
