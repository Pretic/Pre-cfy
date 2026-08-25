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
sparse_fixture="$(mktemp)"
trap 'rm -f "${fixture}" "${sparse_fixture}"' EXIT
for family in ipv6 ipv4; do
    for isp in Mobile Unicom; do
        for index in 1 2 3 4 5 6; do
            if [[ "${family}" == 'ipv6' ]]; then
                printf '2606:4700:%s::%s|%s|%s\n' "$([[ "${isp}" == Mobile ]] && echo 1 || echo 2)" "${index}" "${isp}" "$((60 + index))" >> "${fixture}"
            else
                printf '104.%s.0.%s|%s|%s\n' "$([[ "${isp}" == Mobile ]] && echo 17 || echo 18)" "${index}" "${isp}" "$((70 + index))" >> "${fixture}"
            fi
        done
    done
done

collect_ranked_optimized_pairs "${fixture}" 3 both
[[ "${#ip_list[@]}" -eq 12 ]] || {
    echo "FAIL: dual stack must select 12 candidates for two ISPs, got ${#ip_list[@]}" >&2
    exit 1
}
for index in 0 1 2 3 4 5; do
    [[ "$(get_edge_ip_version "${ip_list[$index]}")" == 'ipv4' ]] || {
        echo 'FAIL: all IPv4 candidates must be ordered before IPv6 candidates' >&2
        exit 1
    }
done

collect_ranked_optimized_pairs "${fixture}" 5 ipv4
[[ "${#ip_list[@]}" -eq 10 ]] || {
    echo "FAIL: IPv4-only mode must select five candidates per ISP" >&2
    exit 1
}
for edge in "${ip_list[@]}"; do
    [[ "$(get_edge_ip_version "${edge}")" == 'ipv4' ]] || exit 1
done

collect_ranked_optimized_pairs "${fixture}" 5 ipv6
[[ "${#ip_list[@]}" -eq 10 ]] || {
    echo "FAIL: IPv6-only mode must select five candidates per ISP" >&2
    exit 1
}
for edge in "${ip_list[@]}"; do
    [[ "$(get_edge_ip_version "${edge}")" == 'ipv6' ]] || exit 1
done

cat > "${sparse_fixture}" <<'EOF'
104.17.0.1|Mobile|70
104.17.0.2|Mobile|80
104.17.0.3|Mobile|90
2606:4700::1|Mobile|60
EOF
collect_ranked_optimized_pairs "${sparse_fixture}" 3 both
[[ "${#ip_list[@]}" -eq 4 ]] || {
    echo 'FAIL: a sparse family/group must not be padded with candidates from another group' >&2
    exit 1
}

echo 'Candidate stack layout tests passed.'
