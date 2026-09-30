#!/usr/bin/env bash
set -euo pipefail
repo=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
source <(sed -n '/^[A-Za-z_][A-Za-z_0-9]*() {/,/^}/p' "$repo/cfy.sh")
d=$(mktemp -d); trap 'rm -rf "$d"' EXIT
GREEN='' RED='' YELLOW='' NC=''; CFY_EXTERNAL_ROOT="$d/external"
v='vless://id@cdn.example.com:443?security=tls&type=ws&host=cdn.example.com&sni=cdn.example.com#Hong%20Kong%2B1'
for encoding in padded unpadded urlsafe; do
 printf '%s' "$v" | base64 -w0 > "$d/import"
 case "$encoding" in
 unpadded) tr -d '=' < "$d/import" > "$d/encoded" ;;
 urlsafe) tr '/+' '_-' < "$d/import" | tr -d '=' > "$d/encoded" ;;
 *) cp "$d/import" "$d/encoded" ;;
 esac
 urls=(); SOURCE_BASE_URLS=()
 load_urls_from_base64_file "$d/encoded"
 [[ ${#urls[@]} == 1 && "${urls[0]}" == "$v" ]]
done
printf '!' >> "$d/encoded"
urls=(); SOURCE_BASE_URLS=()
if load_urls_from_base64_file "$d/encoded"; then echo 'malformed Base64 accepted'; exit 1; fi
[[ ${#urls[@]} == 0 ]]
configure_external_workspace file "$d/encoded"
if load_source_urls 2>/dev/null; then echo 'invalid import accepted'; exit 1; fi
[[ ! -e "$RESULT_FILE" ]]
[[ "$(get_vless_ps "$v")" == 'Hong Kong+1' ]]
[[ "$(get_vless_ps "${v%#*}#Hong+Kong")" == 'Hong+Kong' ]]
updated=$(update_vless_url "$v" 104.16.0.1 "$(get_vless_ps "$v")-CF1")
[[ "$updated" == *'#Hong%20Kong%2B1-CF1' ]]
printf '%s\n' "$v" 'hysteria2://fixture@hy.example.com:443#HY2' 'tuic://id:secret@tuic.example.com:443#TUIC' > "$d/raw"
base64 < "$d/raw" > "$d/mixed"
configure_external_workspace file "$d/mixed"
load_source_urls
[[ ${#urls[@]} == 1 && ${#SOURCE_BASE_URLS[@]} == 3 ]]
generated_urls=("$updated"); save_generated_urls >/dev/null
base64 -d "$BASE_SUB_FILE" > "$d/base"
cmp "$d/raw" "$d/base"
printf 'Base64 normalization/failure, mixed-protocol preservation and fragment roundtrip passed.\n'
