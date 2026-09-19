#!/usr/bin/env bash
set -euo pipefail
repo=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
# Import function definitions only. Never run the installer or use real services.
source <(sed -n '/^[A-Za-z_][A-Za-z_0-9]*() {/,/^}/p' "$repo/cfy.sh")
d=$(mktemp -d); trap 'rm -rf "$d"' EXIT
GREEN='' YELLOW='' RED='' NC=''
CFY_EXTERNAL_ROOT="$d/external"
unset SING_BOX_TRANSACTION_GROUP
v='vless://00000000-0000-4000-8000-000000000001@cdn.example.com:443?security=tls&type=ws&path=%2Fsocket%3Fed%3D2048#external'
normalized=$(normalize_vless_template "$v")
[[ "$(get_vless_query_param "$normalized" host)" == cdn.example.com ]]
[[ "$(get_vless_query_param "$normalized" sni)" == cdn.example.com ]]
[[ "$(get_vless_query_param "$normalized" path)" == '/socket?ed=2048' ]]
[[ "$(normalize_vless_template "$normalized")" == "$normalized" ]]
for bad in "${v/security=tls/security=reality}" "${v/type=ws/type=tcp}" "${v/&path=/&flow=xtls-rprx-vision&path=}" 'vless://id@1.2.3.4:443?security=tls&type=ws'; do
 if normalize_vless_template "$bad" >/dev/null 2>&1; then echo 'accepted incompatible VLESS'; exit 1; fi
done
j='{"v":"2","ps":"external-vmess","add":"workers.example.com","port":"443","id":"00000000-0000-4000-8000-000000000002","aid":"0","net":"ws","tls":"tls","path":"/socket?ed=2048","alpn":"http/1.1","fp":"chrome"}'
m="vmess://$(printf '%s' "$j" | base64 | tr -d '\n')"
mj=$(normalize_vmess_template "$m")
jq -e '.host=="workers.example.com" and .sni=="workers.example.com" and .fp=="chrome"' <<< "$mj" >/dev/null
murl="vmess://$(printf '%s' "$j" | base64 | tr -d '\n=' | tr '/+' '_-')"
[[ "$(normalize_vmess_template "$murl")" == "$mj" ]]
for key in '.net="tcp"' '.tls=""'; do
 bad="vmess://$(jq -c "$key" <<< "$j" | base64 | tr -d '\n')"
 if normalize_vmess_template "$bad" >/dev/null 2>&1; then echo 'accepted incompatible VMess'; exit 1; fi
done
urls=("$v" "$m" "${v/security=tls/security=reality}")
valid_urls=(); valid_ps_names=(); valid_types=()
select_vless_template; select_vmess_template
[[ ${#valid_urls[@]} == 2 && "${valid_types[*]}" == 'vless vmess' ]]
updated=$(update_vmess_url "$mj" '[2606:4700::1111]:8443' candidate)
uj=$(decode_vmess_template "$updated")
jq -e '.add=="2606:4700::1111" and .port=="8443" and .host=="workers.example.com" and .sni=="workers.example.com" and .path=="/socket?ed=2048" and .fp=="chrome"' <<< "$uj" >/dev/null
probe_vless_edge_candidate() {
 [[ "$(get_vless_query_param "$1" host)" == workers.example.com ]]
 [[ "$(get_vless_query_param "$1" path)" == '/socket?ed=2048' ]]
 [[ "$2" == '[2606:4700::1111]:8443' ]]
}
probe_vmess_edge_candidate "$mj" '[2606:4700::1111]:8443'
# Use the real isolated lock/publication functions for independent source modes.
configure_external_workspace manual "$normalized"
[[ "$URL_FILE" == "$d/external/manual/source.txt" ]]
load_source_urls
[[ ${#urls[@]} == 1 ]]
generated_urls=("$(update_vless_url "$normalized" 104.16.0.1 candidate)")
save_generated_urls >/dev/null
[[ -s "$RESULT_FILE" && -s "$SERVED_SUB_FILE" ]]
[[ "$(stat -c %a "$URL_FILE")" == 600 ]]
manual_result=$RESULT_FILE; manual_digest=$(sha256sum "$RESULT_FILE")
printf '%s\n%s\n' "$v" "$m" | base64 > "$d/import.txt"
source_digest=$(sha256sum "$d/import.txt")
configure_external_workspace file "$d/import.txt"
load_source_urls
[[ ${#urls[@]} == 2 && "$URL_FILE" == "$d/import.txt" ]]
[[ "$RESULT_FILE" != "$manual_result" && "$RESULT_FILE" == "$d/external/"* ]]
generated_urls=("$updated"); save_generated_urls >/dev/null
[[ "$(sha256sum "$d/import.txt")" == "$source_digest" ]]
[[ "$(sha256sum "$manual_result")" == "$manual_digest" ]]
# A concurrent source change still prevents stale publication in external mode.
printf '%s\n' "$v" >> "$d/import.txt"
result_digest=$(sha256sum "$RESULT_FILE")
if save_generated_urls >/dev/null 2>&1; then echo 'stale external source published'; exit 1; fi
[[ "$(sha256sum "$RESULT_FILE")" == "$result_digest" ]]
ln -s "$d/import.txt" "$d/link.txt"
if configure_external_workspace file "$d/link.txt" >/dev/null 2>&1; then exit 1; fi
# Validate manual EOF and reprompt without ever echoing supplied credentials.
printf '%s\n%s\n' "${v/security=tls/security=reality}" "$v" > "$d/input"
read_manual_template < "$d/input" >/dev/null 2>&1
[[ "$MANUAL_TEMPLATE" == "$normalized" ]]
if read_manual_template < /dev/null >/dev/null 2>&1; then exit 1; fi
# Main must offer both protocols in the same selection list.
(
 CFY_FORCE_MANUAL=0; CFY_TEMPLATE_FILE=''; CFY_CURL_CONNECT_TIMEOUT=1; CFY_CURL_MAX_TIME=1
 CFY_HEALTH_PROBE=1
 URL_FILE="$d/mixed.txt"; printf '%s\n%s\n' "$v" "$m" > "$URL_FILE"
 curl() { printf '104.16.0.0/13\n'; }
 probe_vmess_edge_candidate() { printf 'checked\n' > "$d/vmess-probed"; }
 finalize_generated_urls() { printf '%s\n' "${generated_urls[@]}" > "$d/generated"; }
 printf '2\n1\n1\n' > "$d/options"
 main < "$d/options" > "$d/main-log" 2>&1
 [[ -s "$d/vmess-probed" && "$(cat "$d/generated")" == vmess://* ]]
)
echo 'External template, mixed protocols, WS/TLS validation and isolated publication tests passed.'
