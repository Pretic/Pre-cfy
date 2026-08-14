#!/usr/bin/env bash

set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cfy_script="${repo_root}/cfy.sh"

function_source="$(sed -n '/^resolve_ip_version_scope() {/,/^}/p' "${cfy_script}")"
if [[ -z "${function_source}" ]]; then
    echo 'FAIL: resolve_ip_version_scope is not implemented' >&2
    exit 1
fi
source <(printf '%s\n' "${function_source}")
selector_source="$(sed -n '/^choose_ip_version_scope() {/,/^}/p' "${cfy_script}")"
source <(printf '%s\n' "${selector_source}")

[[ "$(resolve_ip_version_scope '' 1 1)" == 'both' ]] || exit 1
[[ "$(resolve_ip_version_scope '' 1 0)" == 'ipv4' ]] || exit 1
[[ "$(resolve_ip_version_scope '' 0 1)" == 'ipv6' ]] || exit 1
[[ "$(resolve_ip_version_scope 'ipv6' 1 1)" == 'ipv6' ]] || exit 1
[[ "$(resolve_ip_version_scope '' 0 0)" == 'ipv4' ]] || exit 1

GREEN=''
YELLOW=''
NC=''
CFY_IP_VERSION_SCOPE=''
curl() {
    [[ "${1:-}" == '-4' ]]
}
IP_VERSION_SCOPE=''
choose_ip_version_scope >/dev/null
[[ "${IP_VERSION_SCOPE}" == 'ipv4' ]] || {
    echo 'FAIL: IPv4 outbound-only NAT must be detected as IPv4 single stack' >&2
    exit 1
}

echo 'IP scope detection tests passed.'
