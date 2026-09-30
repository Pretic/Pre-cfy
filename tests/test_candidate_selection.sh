#!/usr/bin/env bash
set -euo pipefail
repo=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
source <(sed -n '/^[A-Za-z_][A-Za-z_0-9]*() {/,/^}/p' "$repo/cfy.sh")
d=$(mktemp -d); trap 'rm -rf "$d"' EXIT
printf '# exported candidates\n104.16.0.1\n104.16.0.1\n104.16.0.2:8443#custom\n[2606:4700::1]:443\n2606:4700::2\n' > "$d/ips"
load_edge_candidates_from_file "$d/ips"
[[ "${ip_list[*]}" == '104.16.0.1 104.16.0.2:8443 [2606:4700::1]:443 2606:4700::2' ]]
for bad in 'example.com' '104.16.0.1:0' '104.16.0.1:99999' '[2606:4700::1]:abc'; do
 printf '%s\n' "$bad" > "$d/bad"
 if load_edge_candidates_from_file "$d/bad" >/dev/null 2>&1; then echo 'invalid candidate accepted'; exit 1; fi
done
for i in {1..40}; do printf '104.16.0.%s\n' "$i"; done > "$d/many"
load_edge_candidates_from_file "$d/many"
[[ ${#ip_list[@]} == 30 ]]
# This path needs no provider request or IP-stack detection.
GREEN='' RED='' YELLOW='' NC=''; URL_FILE="$d/nodes"; : > "$URL_FILE"
load_source_urls() { urls=('vless://fixture'); }
select_vless_template() { valid_urls=('vless://fixture'); valid_ps_names=('fixture'); valid_types=('vless'); }
select_vmess_template() { :; }
get_vless_ps() { echo fixture; }
curl() { echo 'unexpected provider request' >&2; return 1; }
screen_edge_candidates() { [[ ${#ip_list[@]} == 4 ]]; }
update_vless_url() { printf 'vless://fixture#%s\n' "$3"; }
finalize_generated_urls() { [[ "$1" == 4 ]]; }
CFY_EDGE_FILE="$d/ips"
printf '\n' > "$d/choice"
main < "$d/choice" > "$d/log"
echo 'Local candidate import, deduplication, bounds and network-free selection tests passed.'
# A failed default cloud fetch returns to the menu with the chosen template
# intact; the user can recover locally in the same run without an env variable.
unset CFY_EDGE_FILE
choose_ip_version_scope() { IP_VERSION_SCOPE=both; }
get_all_optimized_ips() { return 1; }
printf '\n2\n3\n%s\n' "$d/ips" > "$d/fallback-choice"
main < "$d/fallback-choice" > "$d/fallback-log" 2>&1
grep -q '原结果未修改' "$d/fallback-log"
printf '\n0\n' > "$d/cancel-choice"
if main < "$d/cancel-choice" >/dev/null 2>&1; then echo 'cancel accepted'; exit 1; fi
echo 'Cloud failure recovers through visible local-file option; cancel exits.'
