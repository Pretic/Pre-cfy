#!/usr/bin/env bash
# Baseline batch scheduler for isolated regression comparisons.
screen_edge_candidates_v1() {
        local kind="$1" template="$2" json='' dir='' pid start index end reason
        local concurrency="${CFY_HEALTH_CONCURRENCY:-3}" total=${#ip_list[@]}
        local -a pids=()
        [[ "$concurrency" =~ ^[1-6]$ ]] || concurrency=3
        umask 077
        dir=$(mktemp -d) || exit 1
        trap 'for pid in "${pids[@]}"; do kill "$pid" 2>/dev/null || :; done; for pid in "${pids[@]}"; do wait "$pid" 2>/dev/null || :; done; rm -rf -- "$dir"' EXIT
        trap 'exit 130' INT
        trap 'exit 143' TERM HUP
        if [ "$kind" = vmess ]; then json=$(decode_vmess_template "$template") || exit 1; fi
        printf '正在检查 %s 个入口（最多 %s 个并行）...\n' "$total" "$concurrency" >&2
        for ((start=0; start<total; start+=concurrency)); do
            end=$((start + concurrency)); [ "$end" -le "$total" ] || end=$total
            pids=()
            for ((index=start; index<end; index++)); do
                (
                    local worker_pid='' worker_rc=0
                    trap '[ -z "$worker_pid" ] || { kill "$worker_pid" 2>/dev/null || :; wait "$worker_pid" 2>/dev/null || :; }' EXIT
                    trap 'exit 130' INT
                    trap 'exit 143' TERM HUP
                    CFY_PROBE_RESULT_FILE="$dir/$index.reason"
                    if [ "$kind" = vless ]; then
                        probe_vless_edge_candidate "$template" "${ip_list[$index]}" &
                    else probe_vmess_edge_candidate "$json" "${ip_list[$index]}" & fi
                    worker_pid=$!
                    wait "$worker_pid" || worker_rc=$?
                    worker_pid=''
                    if [ "$worker_rc" = 0 ]; then
                        : > "$dir/$index.ok"; reason=ok
                    else
                        reason=network
                        [ ! -s "$CFY_PROBE_RESULT_FILE" ] || read -r reason < "$CFY_PROBE_RESULT_FILE"
                    fi
                    printf '[%s/%s] %s：%s\n' "$((index+1))" "$total" "${ip_list[$index]}" "$(cfy_probe_reason "$reason")" >&2
                ) &
                pids+=("$!")
            done
            for pid in "${pids[@]}"; do wait "$pid" || exit 1; done
            pids=()
        done
        for ((index=0; index<total; index++)); do
            if [ -f "$dir/$index.ok" ]; then printf '%s\n' "$index"; fi
        done
}
