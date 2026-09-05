#!/usr/bin/env bash
set -euo pipefail

script="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/cfy.sh"
for name in is_ipv6_edge get_edge_ip_version is_valid_edge_address is_valid_ipv4_literal \
    is_valid_ipv6_literal is_valid_optimized_ip_literal normalize_edge_latency \
    decimal_latency_less_than collect_ranked_optimized_pairs get_candidate_group_limit \
    parse_wetest_api_payload get_all_optimized_ips; do
    source <(sed -n "/^${name}() {/,/^}/p" "$script")
done

GREEN=''; YELLOW=''; RED=''; NC=''
CFY_CURL_CONNECT_TIMEOUT=1; CFY_CURL_MAX_TIME=1; IP_VERSION_SCOPE=both
curl() {
    case "${!#}" in
      *address_v4.html)
        cat <<'HTML'
<table><tr><td data-label="线路名称">移动</td><td data-label="优选地址">104.17.99.98</td><td data-label="往返延迟">63 毫秒</td></tr>
<tr><td data-label="线路名称">移动</td><td data-label="优选地址">104.17.218.101</td><td data-label="往返延迟">82 毫秒</td></tr>
<tr><td data-label="线路名称">移动</td><td data-label="优选地址">104.17.0.1</td><td data-label="往返延迟">-1 毫秒</td></tr>
<tr><td data-label="线路名称">移动</td><td data-label="优选地址">104.17.0.2</td><td data-label="往返延迟">0 毫秒</td></tr></table>
HTML
        ;;
      *address_v6.html)
        printf '%s\n' '<tr><td data-label="线路名称">移动</td><td data-label="优选地址">2606:4700:9ae9::7de7:a165</td><td data-label="往返延迟">85 毫秒</td></tr>'
        ;;
      *) return 22 ;;
    esac
}

get_all_optimized_ips >/dev/null || { echo 'FAIL: current WeTest HTML fallback rejected valid Chinese millisecond RTTs' >&2; exit 1; }
[[ "${ip_list[*]}" == '104.17.99.98 104.17.218.101 2606:4700:9ae9::7de7:a165' ]] || {
    echo 'FAIL: HTML fallback lost valid candidates or accepted invalid RTTs' >&2; exit 1;
}
echo 'Chinese millisecond HTML fallback tests passed.'
