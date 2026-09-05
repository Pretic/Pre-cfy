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
source <(extract_function validate_websocket_probe_headers)
source <(printf '%s\n' "${probe_source}")

tmp_root=$(mktemp -d)
trap 'rm -rf "$tmp_root"' EXIT
fail() { printf 'FAIL: %s\n' "$*" >&2; exit 1; }

template='vless://00000000-0000-0000-0000-000000000000@old.example:443?encryption=none&security=tls&sni=tunnel.example.com&type=ws&host=tunnel.example.com&path=%2Fvless-argo#template'
CFY_HEALTH_PROBE_ATTEMPTS=2
CFY_HEALTH_MIN_SUCCESS=2
CFY_HEALTH_CONNECT_TIMEOUT=1
CFY_HEALTH_MAX_TIME=2

curl() {
    printf '400|0.125'
}
if probe_vless_edge_candidate "${template}" '104.17.0.1'; then
    fail 'ordinary HTTP 400 was accepted without a WebSocket handshake'
fi

# The fake transport validates the actual request and returns a nonce-bound
# handshake, including curl's expected timeout after a successful upgrade.
fixture=valid
curl_rc=28
expected_resolve='tunnel.example.com:443:104.17.0.1'
: > "$tmp_root/nonces"
curl() {
    local headers='' key='' connection='' upgrade='' version='' host='' resolve='' url=''
    local no_proxy='' retry='' protocols=''
    [[ "${1:-}" == -q ]] || fail 'probe inherited curlrc options'
    while [ "$#" -gt 0 ]; do
        case "$1" in
            --dump-header) headers="$2"; shift ;;
            --resolve) resolve="$2"; shift ;;
            --noproxy) no_proxy="$2"; shift ;;
            --retry) retry="$2"; shift ;;
            --proto) protocols="$2"; shift ;;
            --header)
                case "$2" in
                    'Sec-WebSocket-Key: '*) key="${2#*: }" ;;
                    'Connection: '*) connection="${2#*: }" ;;
                    'Upgrade: '*) upgrade="${2#*: }" ;;
                    'Sec-WebSocket-Version: '*) version="${2#*: }" ;;
                    'Host: '*) host="${2#*: }" ;;
                esac
                shift ;;
            --insecure|-k) fail 'probe disabled TLS verification' ;;
            https://*) url="$1" ;;
        esac
        shift
    done
    [[ "$connection" == Upgrade && "$upgrade" == websocket && "$version" == 13 ]] || fail 'missing upgrade request headers'
    [[ "$no_proxy" == '*' && "$retry" == 0 && "$protocols" == '=https' ]] || fail 'probe did not isolate the candidate connection'
    [[ "$resolve" == "$expected_resolve" && "$host" == tunnel.example.com ]] || fail 'wrong candidate address or HTTP Host'
    [[ "$url" == https://tunnel.example.com:443/vless-argo ]] || fail 'wrong TLS name or decoded path'
    [[ "$key" =~ ^[A-Za-z0-9+/]{22}==$ ]] || fail 'invalid handshake nonce'
    printf '%s\n' "$key" >> "$tmp_root/nonces"
    local accept
    accept=$(printf '%s' "${key}258EAFA5-E914-47DA-95CA-C5AB0DC85B11" | openssl dgst -sha1 -binary | openssl base64 -A)
    [ "$fixture" != wrong_accept ] || accept='incorrect'
    if [ "$fixture" != empty ]; then
        printf 'HTTP/1.1 200 Connection established\r\n\r\nHTTP/1.1 101 Switching Protocols\r\n' > "$headers"
        [ "$fixture" = missing_upgrade ] || printf 'uPgRaDe: WebSocket\r\n' >> "$headers"
        [ "$fixture" = missing_connection ] || printf 'Connection: keep-alive, Upgrade\r\n' >> "$headers"
        printf 'Sec-WebSocket-Accept: %s\r\n' "$accept" >> "$headers"
        [ "$fixture" != unrequested_extension ] || printf 'Sec-WebSocket-Extensions: permessage-deflate\r\n' >> "$headers"
        [ "$fixture" != duplicate_accept ] || printf 'Sec-WebSocket-Accept: %s\r\n' "$accept" >> "$headers"
        [ "$fixture" = incomplete ] || printf '\r\n' >> "$headers"
    fi
    printf '%s' "${http_code:-101}"
    return "$curl_rc"
}
probe_vless_edge_candidate "$template" '104.17.0.1' || fail 'valid upgraded connection ending at the time limit was rejected'
[[ "$(sort -u "$tmp_root/nonces" | wc -l)" -eq 2 ]] || fail 'attempts reused a nonce'
for fixture in wrong_accept missing_upgrade missing_connection duplicate_accept incomplete empty unrequested_extension; do
    if probe_vless_edge_candidate "$template" '104.17.0.1'; then fail "accepted $fixture handshake"; fi
done
fixture=valid
for http_code in 400 404 200 000; do
    if probe_vless_edge_candidate "$template" '104.17.0.1'; then fail "accepted HTTP $http_code"; fi
done
http_code=101
curl_rc=60
if probe_vless_edge_candidate "$template" '104.17.0.1'; then fail 'accepted a TLS verification failure'; fi
curl_rc=0
expected_resolve='tunnel.example.com:443:[2606:4700::1]'
probe_vless_edge_candidate "$template" '[2606:4700::1]' || fail 'IPv6 formatting fixture failed'

echo 'Edge health probe tests passed.'
