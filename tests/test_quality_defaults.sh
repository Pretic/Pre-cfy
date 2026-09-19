#!/usr/bin/env bash
set -euo pipefail
script="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/cfy.sh"
d=$(mktemp -d); trap 'rm -rf "$d"' EXIT
unset CFY_HEALTH_PROBE
source <(grep '^CFY_HEALTH_PROBE=' "$script")
[[ "$CFY_HEALTH_PROBE" == 1 ]]
for f in main screen_edge_candidates screen_edge_candidates_impl cfy_probe_reason; do
 source <(sed -n "/^${f}() {/,/^}/p" "$script")
done
URL_FILE="$d/input"; touch "$URL_FILE"; GREEN=''; RED=''; YELLOW=''; NC=''
CFY_CURL_CONNECT_TIMEOUT=1; CFY_CURL_MAX_TIME=1
load_source_urls() { urls=('vless://fixture'); }
select_vless_template() { valid_urls=('vless://fixture'); valid_ps_names=('fixture'); valid_types=('vless'); }
select_vmess_template() { :; }
get_vless_ps() { echo fixture; }
curl() { echo 104.16.0.0/13; }
cidr_to_usable_ip() { echo 104.16.0.1; }
probe_vless_edge_candidate() { return "${PROBE_RC:-0}"; }
update_vless_url() { echo "vless://fixture#$3"; }
finalize_generated_urls() { echo "$1" > "$d/published"; }
printf '1\n1\n3\n' > "$d/choices"
(main < "$d/choices") > "$d/log" 2>&1
[[ "$(cat "$d/published")" == 3 ]]
rm "$d/published"
PROBE_RC=1
if (main < "$d/choices") > "$d/log" 2>&1; then exit 1; fi
[[ ! -e "$d/published" ]]
if (main </dev/null) > "$d/log" 2>&1; then exit 1; fi
# Run only the CLI dispatcher with a failing updater, not the bootstrap.
printf 'update_self() { return 42; }\n' > "$d/dispatch.sh"
sed -n '/^case /,/^esac/p' "$script" >> "$d/dispatch.sh"
rc=0
bash "$d/dispatch.sh" --update || rc=$?
[[ "$rc" == 42 ]]
echo 'Default health checks, no-empty-publication, EOF and update status tests passed.'
