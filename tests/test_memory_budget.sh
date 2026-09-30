#!/usr/bin/env bash
set -euo pipefail
repo=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
source <(sed -n '/^[A-Za-z_][A-Za-z_0-9]*() {/,/^}/p' "$repo/cfy.sh")
d=$(mktemp -d); trap 'rm -rf "$d"' EXIT
mkdir -p "$d/cgroup/team/job" "$d/v1/memory/box"
printf 'MemTotal: 4194304 kB\nMemAvailable: 3145728 kB\n' > "$d/meminfo"
printf '0::/team/job\n' > "$d/member"
printf 'max\n' > "$d/cgroup/memory.max"
printf 'max\n' > "$d/cgroup/team/job/memory.max"
printf '134217728\n' > "$d/cgroup/team/memory.max"
printf '33554432\n' > "$d/cgroup/team/memory.current"
get_cfy_memory_budget "$d/meminfo" "$d/cgroup" "$d/member"
[[ "$CFY_EFFECTIVE_TOTAL_KB" == 131072 && "$CFY_EFFECTIVE_AVAILABLE_KB" == 98304 ]]
# Same detector handles v1 limits and ignores huge unlimited sentinels.
printf '5:cpu,memory:/box\n' > "$d/member-v1"
printf '9223372036854771712\n' > "$d/v1/memory/memory.limit_in_bytes"
printf '268435456\n' > "$d/v1/memory/box/memory.limit_in_bytes"
printf '67108864\n' > "$d/v1/memory/box/memory.usage_in_bytes"
get_cfy_memory_budget "$d/meminfo" "$d/v1" "$d/member-v1"
[[ "$CFY_EFFECTIVE_TOTAL_KB" == 262144 && "$CFY_EFFECTIVE_AVAILABLE_KB" == 196608 ]]
# Subtree mounts must strip mount root before joining membership to mountpoint.
mkdir -p "$d/subtree/child"
printf '134217728\n' > "$d/subtree/child/memory.max"
printf '16777216\n' > "$d/subtree/child/memory.current"
printf '0::/host/container/child\n' > "$d/member-subtree"
printf '29 23 0:26 /host/container %s rw - cgroup2 cgroup rw\n' "$d/subtree" > "$d/mountinfo"
get_cfy_memory_budget "$d/meminfo" "$d/subtree" "$d/member-subtree" "$d/mountinfo"
[[ "$CFY_EFFECTIVE_TOTAL_KB" == 131072 && "$CFY_EFFECTIVE_AVAILABLE_KB" == 114688 ]]
printf '0::/child\n' > "$d/member-subtree"
get_cfy_memory_budget "$d/meminfo" "$d/subtree" "$d/member-subtree" "$d/mountinfo"
[[ "$CFY_EFFECTIVE_TOTAL_KB" == 131072 ]]
# Unmapped child accounting must not accidentally inherit a large host budget.
printf '0::/missing\n' > "$d/member-subtree"
get_cfy_memory_budget "$d/meminfo" "$d/subtree" "$d/member-subtree" "$d/mountinfo"
[[ "$CFY_EFFECTIVE_TOTAL_KB" == 0 ]]
# Readable but empty/malformed leaf limits are unknown, not host-sized.
printf '0::/child\n' > "$d/member-subtree"
for invalid in '' broken 0; do
 printf '%s\n' "$invalid" > "$d/subtree/child/memory.max"
 get_cfy_memory_budget "$d/meminfo" "$d/subtree" "$d/member-subtree" "$d/mountinfo"
 [[ "$CFY_EFFECTIVE_TOTAL_KB" == 0 ]]
done
# Only substitute input observation, not the policy under test.
eval 'get_cfy_memory_budget() { :; }'
unset CFY_HEALTH_CONCURRENCY
for tuple in '32768 8192 1' '131072 98304 1' '262144 196608 2' '1048576 524288 3' '1048576 65536 1' '1048576 131072 2' '0 0 1'; do
 read -r CFY_EFFECTIVE_TOTAL_KB CFY_EFFECTIVE_AVAILABLE_KB expected <<< "$tuple"
 [[ "$(get_cfy_probe_concurrency)" == "$expected" ]]
done
CFY_HEALTH_CONCURRENCY=6
[[ "$(get_cfy_probe_concurrency)" == 6 ]]
CFY_HEALTH_CONCURRENCY=0
[[ "$(get_cfy_probe_concurrency)" == 1 ]]
echo 'Host/cgroup v1/v2/ancestor/headroom budgets, 32/128/256MiB tiers and overrides passed.'
