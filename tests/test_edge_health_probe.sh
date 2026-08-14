#!/usr/bin/env bash

set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cfy_script="${repo_root}/cfy.sh"

extract_function() {
    local function_name="$1"
    sed -n "/^${function_name}() {/,/^}/p" "${cfy_script}"
}

probe_source="$(extract_function probe_vless_edge_candidate)"
if [[ -z "${probe_source}" ]]; then
    echo "FAIL: probe_vless_edge_candidate is not implemented" >&2
    exit 1
fi

source <(extract_function url_decode)
source <(extract_function get_vless_query_param)
source <(extract_function extract_vless_port)
source <(extract_function normalize_edge_input)
source <(extract_function is_ipv6_edge)
source <(printf '%s\n' "${probe_source}")

template='vless://00000000-0000-0000-0000-000000000000@old.example:443?encryption=none&security=tls&sni=tunnel.example.com&type=ws&host=tunnel.example.com&path=%2Fvless-argo#template'
CFY_HEALTH_PROBE_ATTEMPTS=2
CFY_HEALTH_MIN_SUCCESS=2
CFY_HEALTH_CONNECT_TIMEOUT=1
CFY_HEALTH_MAX_TIME=2

curl() {
    printf '400|0.125'
}
probe_vless_edge_candidate "${template}" '104.17.0.1'

curl() {
    printf '404|0.125'
}
if probe_vless_edge_candidate "${template}" '104.17.0.2'; then
    echo 'FAIL: a Cloudflare 404 was accepted as a healthy sing-box WS origin' >&2
    exit 1
fi

echo 'Edge health probe tests passed.'
