#!/usr/bin/env bash

set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cfy_script="${repo_root}/cfy.sh"

function_source="$(sed -n '/^get_candidate_group_limit() {/,/^}/p' "${cfy_script}")"
if [[ -z "${function_source}" ]]; then
    echo 'FAIL: get_candidate_group_limit is not implemented' >&2
    exit 1
fi
source <(printf '%s\n' "${function_source}")

unset CFY_PER_ISP_LIMIT
[[ "$(get_candidate_group_limit both)" == '3' ]] || {
    echo 'FAIL: dual-stack limit must be 3 per ISP/family' >&2
    exit 1
}
[[ "$(get_candidate_group_limit ipv4)" == '5' ]] || {
    echo 'FAIL: IPv4-only limit must be 5 per ISP' >&2
    exit 1
}
[[ "$(get_candidate_group_limit ipv6)" == '5' ]] || {
    echo 'FAIL: IPv6-only limit must be 5 per ISP' >&2
    exit 1
}

CFY_PER_ISP_LIMIT=4
[[ "$(get_candidate_group_limit both)" == '4' ]] || {
    echo 'FAIL: an explicit limit override must be preserved' >&2
    exit 1
}

echo 'Candidate stack-aware limit tests passed.'
