from pathlib import Path
import hashlib
p=Path('cfy.sh'); s=p.read_text()
assert hashlib.sha256(p.read_bytes()).hexdigest() == '33a059c58439bbfaa164e8f47018ba3d1bb46a39bab2cd18566b35dda7544b68'
s=s.replace('CFY_HEALTH_PROBE="${CFY_HEALTH_PROBE:-0}"','CFY_HEALTH_PROBE="${CFY_HEALTH_PROBE:-1}"')
s=s.replace('    echo "  -h, --help    显示帮助"','    echo "  -h, --help    显示帮助"\n    echo "VLESS 默认逐个验证 TLS/WebSocket 握手；这不是客户端线路测速。"')
s=s.replace('  1) Cloudflare 官方 (手动优选)','  1) Cloudflare 官方网段候选（非测速优选）')
s=s.replace('请输入您想生成的 URL 数量: ', '请输入候选检查数量 (1-30): ')
s=s.replace('[[ "$num_to_generate" =~ ^[0-9]+$ ]] && [ "$num_to_generate" -gt 0 ]','[[ "$num_to_generate" =~ ^[0-9]{1,2}$ ]] && [ "$num_to_generate" -gt 0 ] && [ "$num_to_generate" -le 30 ]')
s=s.replace('            if [ "$selected_type" = "vless" ]; then\n                generated_url=$(update_vless_url "$selected_url" "$ip_from_range" "$new_ps")','''            if [ "$selected_type" = "vless" ]; then
                if [ "$CFY_HEALTH_PROBE" != "0" ] && ! probe_vless_edge_candidate "$selected_url" "$ip_from_range"; then
                    echo -e "${YELLOW}跳过未通过握手验证的官方网段候选。${NC}" >&2
                    continue
                fi
                generated_url=$(update_vless_url "$selected_url" "$ip_from_range" "$new_ps")''')
s=s.replace('    finalize_generated_urls "$num_to_generate" || return $?','''    num_to_generate=${#generated_urls[@]}
    if [ "$num_to_generate" -eq 0 ]; then
        echo -e "${RED}没有通过检查的节点，保留原订阅。${NC}" >&2
        return 1
    fi
    finalize_generated_urls "$num_to_generate" || return $?''')
s=s.replace('        update_self\n        exit 0','        update_self\n        exit $?')
# All interactive reads below occur within main; EOF must not spin forever.
s='\n'.join(line+' || return 1' if line.lstrip().startswith('read -p ') else line for line in s.split('\n'))
# Bootstrap downloads get bounded transport and parse checks as well.
s=s.replace('    if ! curl -fsSL "$REMOTE_URL" -o "$tmp_file"; then','    if ! curl -q -fsSL --proto \'=https\' --proto-redir \'=https\' --connect-timeout 10 --max-time 60 "$REMOTE_URL" -o "$tmp_file"; then')
s=s.replace("    if ! grep -q 'REMOTE_URL=\"https://raw.githubusercontent.com/Pretic/Pre-cfy/main/cfy.sh\"' \"$tmp_file\"; then", "    if ! bash -n \"$tmp_file\" || ! grep -q 'REMOTE_URL=\"https://raw.githubusercontent.com/Pretic/Pre-cfy/main/cfy.sh\"' \"$tmp_file\"; then")
p.write_text(s)
assert 'CFY_HEALTH_PROBE="${CFY_HEALTH_PROBE:-1}"' in s
assert 'update_self\n        exit $?' in s
print('CFY_SHA256='+hashlib.sha256(p.read_bytes()).hexdigest())
