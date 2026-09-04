#!/usr/bin/env bash

set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cfy_script="${repo_root}/cfy.sh"

extract_function() {
    local function_name="$1"
    sed -n "/^${function_name}() {/,/^}/p" "${cfy_script}"
}

for function_name in \
    is_valid_edge_address is_valid_ipv4_literal is_valid_ipv6_literal \
    is_valid_optimized_ip_literal normalize_edge_latency decimal_latency_less_than is_ipv6_edge \
    collect_ranked_optimized_pairs get_candidate_group_limit get_edge_ip_version \
    parse_wetest_api_payload get_all_optimized_ips; do
    function_source="$(extract_function "${function_name}")"
    if [[ -z "${function_source}" ]]; then
        echo "FAIL: ${function_name} is not implemented" >&2
        exit 1
    fi
source <(printf '%s\n' "${function_source}")
done

# GitHub runners and supported VPS installations provide jq. Git for Windows
# does not, so keep the local regression runnable with a fixture-only JSON
# adapter; CI still exercises the production jq filter.
if ! command -v jq >/dev/null 2>&1; then
    jq() {
        py -3 -c '
import json
import sys

payload = json.load(sys.stdin)
if payload.get("status") is not True or str(payload.get("code")) != "200":
    raise SystemExit(0)
info = payload.get("info")
if isinstance(info, dict):
    grouped_values = ((group, info.get(group, [])) for group in ("CM", "CU", "CT"))
elif isinstance(info, list):
    grouped_values = (("CF", info),)
else:
    grouped_values = ()
for group, values in grouped_values:
    if isinstance(values, list):
        for item in values:
            if not isinstance(item, dict):
                continue
            latency = item.get("rtt_avg", item.get("latency", ""))
            if isinstance(latency, (int, float)) and not isinstance(latency, bool):
                latency = int(latency * 1000 + 0.5)
            fields = (
                item.get("ip", ""),
                item.get("line_name", item.get("line", group)),
                latency,
            )
            print("\t".join(str(field) for field in fields))
'
    }
fi

for valid_ip in 0.0.0.0 104.17.0.1 255.255.255.255 :: ::1 1:: 2001:db8::1 2001:db8:0:0:0:0:2:1; do
    is_valid_optimized_ip_literal "${valid_ip}" both || {
        echo "FAIL: valid IP literal was rejected: ${valid_ip}" >&2
        exit 1
    }
done
for invalid_ip in 256.0.0.1 999.999.999.999 example.com : 1: :1 1::2: :1::2 1:::2 1::2::3 2001:db8:0:0:0:0:0::1; do
    if is_valid_optimized_ip_literal "${invalid_ip}" both; then
        echo "FAIL: malformed IP literal was accepted: ${invalid_ip}" >&2
        exit 1
    fi
done

GREEN=''
YELLOW=''
RED=''
NC=''
CFY_CURL_CONNECT_TIMEOUT=1
CFY_CURL_MAX_TIME=1
CFY_OPTIMIZED_IP_API_URL='https://www.wetest.vip/api/cf2dns/get_cloudflare_ip'
CFY_OPTIMIZED_IP_API_KEY='fixture-key'
CFY_PER_ISP_LIMIT=2
IP_VERSION_SCOPE=both
fixture_schema=object

curl() {
    local args=" $* "

    [[ "${args}" == *" ${CFY_OPTIMIZED_IP_API_URL} "* ]] || return 22
    if [[ "${args}" == *" type=v4 "* ]]; then
        if [[ "${fixture_schema}" == object ]]; then
            cat <<'JSON'
{"status":true,"code":200,"msg":"ok","info":{"CM":[{"ip":"999.999.999.999","line_name":"移动","rtt_avg":1},{"ip":"2606:4700::99","line_name":"移动","rtt_avg":2},{"ip":"104.17.0.1","line":"cm","line_name":"移动","rtt_avg":82.9},{"ip":"104.17.0.2","line":"cm","line_name":"移动","rtt_avg":82.1}],"CU":[{"ip":"104.18.0.3","line":"cu","line_name":"联通","rtt_avg":137}]}}
JSON
        else
            cat <<'JSON'
{"status":true,"code":200,"msg":"ok","info":[{"ip":"104.19.0.1","colo":"SJC","latency":31.9},{"ip":"104.19.0.2","colo":"LAX","latency":31.1}]}
JSON
        fi
    elif [[ "${args}" == *" type=v6 "* ]]; then
        if [[ "${fixture_schema}" == object ]]; then
            cat <<'JSON'
{"status":true,"code":200,"msg":"ok","info":{"CM":[{"ip":"2001:::1","line_name":"移动","rtt_avg":1},{"ip":"1::2:","line_name":"移动","rtt_avg":1},{"ip":":1::2","line_name":"移动","rtt_avg":1},{"ip":"104.17.0.99","line_name":"移动","rtt_avg":2},{"ip":"2606:4700::1","line":"cm","line_name":"移动","rtt_avg":85.9},{"ip":"2606:4700::2","line":"cm","line_name":"移动","rtt_avg":85.1}],"CT":[{"ip":"2a06:98c1::3","line":"ct","line_name":"电信","rtt_avg":65}]}}
JSON
        else
            cat <<'JSON'
{"status":true,"code":200,"msg":"ok","info":[{"ip":"2606:4700:10::1","colo":"HKG","latency":44.5}]}
JSON
        fi
    else
        return 22
    fi
}

output_file="$(mktemp)"
trap 'rm -f "${output_file}"' EXIT

if ! get_all_optimized_ips >"${output_file}"; then
    echo 'FAIL: documented WeTest JSON API payload was not accepted' >&2
    cat "${output_file}" >&2
    exit 1
fi

expected_ips='104.17.0.2 104.17.0.1 104.18.0.3 2606:4700::2 2606:4700::1 2a06:98c1::3'
if [[ "${ip_list[*]}" != "${expected_ips}" ]]; then
    echo "FAIL: API candidates were not validated and ranked correctly: ${ip_list[*]}" >&2
    exit 1
fi

expected_isps='移动 移动 联通 移动 移动 电信'
if [[ "${isp_list[*]}" != "${expected_isps}" ]]; then
    echo "FAIL: API carrier labels were not preserved: ${isp_list[*]}" >&2
    exit 1
fi

fixture_schema=array
if ! get_all_optimized_ips >"${output_file}"; then
    echo 'FAIL: documented array-shaped WeTest API payload was not accepted' >&2
    cat "${output_file}" >&2
    exit 1
fi

expected_ips='104.19.0.2 104.19.0.1 2606:4700:10::1'
if [[ "${ip_list[*]}" != "${expected_ips}" ]]; then
    echo "FAIL: documented array API candidates were not ranked correctly: ${ip_list[*]}" >&2
    exit 1
fi

expected_isps='CF CF CF'
if [[ "${isp_list[*]}" != "${expected_isps}" ]]; then
    echo "FAIL: generic labels for array API candidates changed: ${isp_list[*]}" >&2
    exit 1
fi

echo 'WeTest optimized-IP API parsing tests passed.'
