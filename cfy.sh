#!/bin/bash

INSTALL_PATH="/usr/local/bin/cfy"
URL_FILE="/etc/sing-box/url.txt"
RESULT_FILE="/etc/sing-box/cfy-url.txt"
SUB_FILE="/etc/sing-box/cfy-sub.txt"
RESULT_DIR="/etc/sing-box/cfy-results"

if [ "$0" != "$INSTALL_PATH" ]; then
    echo "正在安装 [cfy 节点优选生成器]..."

    if [ "$(id -u)" -ne 0 ]; then
        echo "错误: 安装需要管理员权限。请使用 'curl ... | sudo bash' 或 'sudo bash <(curl ...)' 命令来运行。"
        exit 1
    fi
    
    echo "正在将脚本写入到 $INSTALL_PATH..."
    
    # 智能判断执行模式
    if [[ "$(basename "$0")" == "bash" || "$(basename "$0")" == "sh" || "$(basename "$0")" == "-bash" ]]; then
        # 管道模式: curl ... | bash
        # 脚本内容在标准输入 (fd/0)
        if ! cat /proc/self/fd/0 > "$INSTALL_PATH"; then
            echo "❌ 写入脚本失败 (管道模式)，请重试。"
            exit 1
        fi
    else
        # 文件模式: bash cfy.sh 或 bash <(curl ...)
        # 脚本内容在 $0 所指向的文件路径
        if ! cp "$0" "$INSTALL_PATH"; then
            echo "❌ 复制脚本失败 (文件模式)，请重试。"
            exit 1
        fi
    fi

    if [ $? -eq 0 ]; then
        chmod +x "$INSTALL_PATH"
        echo "✅ 安装成功! 您现在可以随时随地运行 'cfy' 命令。"
        echo "---"
        echo "首次运行..."
        exec "$INSTALL_PATH" "$@"
    else
        echo "❌ 安装后赋权失败, 请检查权限。"
        exit 1
    fi
    exit 0
fi

# --- 主程序从这里开始 ---

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'
declare -a generated_urls

show_help() {
    echo "用法: cfy [参数]"
    echo "  无参数        生成 Cloudflare 优选节点"
    echo "  -c, --check   查看最近一次生成的优选节点"
    echo "  -h, --help    显示帮助"
}

show_saved_results() {
    if [ ! -s "$RESULT_FILE" ]; then
        echo -e "${YELLOW}尚未找到已保存的优选节点，请先运行 cfy 生成一次。${NC}"
        return 1
    fi

    echo -e "${GREEN}=== 最近一次优选节点 ===${NC}"
    cat "$RESULT_FILE"
    echo ""
    [ -s "$SUB_FILE" ] && echo -e "${GREEN}Base64订阅文件: ${SUB_FILE}${NC}"
    [ -d "$RESULT_DIR" ] && echo -e "${GREEN}历史结果目录: ${RESULT_DIR}${NC}"
}

write_base64_file() {
    if base64 -w0 "$RESULT_FILE" > "$SUB_FILE" 2>/dev/null; then
        return 0
    fi
    base64 "$RESULT_FILE" | tr -d '\n\r' > "$SUB_FILE"
}

save_generated_urls() {
    [ ${#generated_urls[@]} -eq 0 ] && return 0

    mkdir -p "$(dirname "$RESULT_FILE")" "$RESULT_DIR"
    printf '%s\n' "${generated_urls[@]}" > "$RESULT_FILE"
    write_base64_file

    local history_file="${RESULT_DIR}/$(date +%Y%m%d-%H%M%S).txt"
    cp "$RESULT_FILE" "$history_file" 2>/dev/null || true

    echo -e "${GREEN}已保存最近一次优选结果: ${RESULT_FILE}${NC}"
    echo -e "${GREEN}后续可运行 cfy -c 再次查看。${NC}"
}

check_deps() {
    for cmd in jq curl base64 grep sed mktemp shuf; do
        if ! command -v "$cmd" &> /dev/null; then
            echo -e "${RED}错误: 命令 '$cmd' 未找到. 请先安装它.${NC}"
            exit 1
        fi
    done
}

get_all_optimized_ips() {
    local url_v4="https://www.wetest.vip/page/cloudflare/address_v4.html"
    local url_v6="https://www.wetest.vip/page/cloudflare/address_v6.html"
    
    echo -e "${YELLOW}正在合并获取所有优选 IP (IPv4 & IPv6)...${NC}"
    
    local paired_data_file
    paired_data_file=$(mktemp)
    trap 'rm -f "$paired_data_file"' EXIT

    parse_url() {
        local url="$1"; local type_desc="$2"
        echo -e "  -> 正在获取 ${type_desc} 列表..."
        local html_content=$(curl -s "$url")
        if [ -z "$html_content" ]; then echo -e "${RED}  -> 获取 ${type_desc} 列表失败!${NC}"; return; fi
        local table_rows=$(echo "$html_content" | tr -d '\n\r' | sed 's/<tr>/\n&/g' | grep '^<tr>')
        local ips=$(echo "$table_rows" | sed -n 's/.*data-label="优选地址">\([^<]*\)<.*/\1/p')
        local isps=$(echo "$table_rows" | sed -n 's/.*data-label="线路名称">\([^<]*\)<.*/\1/p')
        paste -d' ' <(echo "$ips") <(echo "$isps") >> "$paired_data_file"
    }

    parse_url "$url_v4" "IPv4"; parse_url "$url_v6" "IPv6"

    if ! [ -s "$paired_data_file" ]; then echo -e "${RED}无法从任何来源解析出优选 IP 地址.${NC}"; return 1; fi

    declare -g -a ip_list isp_list; local shuffled_pairs
    mapfile -t shuffled_pairs < <(shuf "$paired_data_file")
    for pair in "${shuffled_pairs[@]}"; do
        ip_list+=("$(echo "$pair" | cut -d' ' -f1)")
        isp_list+=("$(echo "$pair" | cut -d' ' -f2-)")
    done
    if [ ${#ip_list[@]} -eq 0 ]; then echo -e "${RED}解析成功, 但未找到任何有效的 IP 地址.${NC}"; return 1; fi
    echo -e "${GREEN}成功合并获取 ${#ip_list[@]} 个优选 IP 地址, 列表已随机打乱.${NC}"; return 0
}

get_vless_ps() {
    local url="$1"
    local ps="${url##*#}"
    if [ "$ps" = "$url" ] || [ -z "$ps" ]; then
        ps="vless-ws-tls-argo"
    fi
    echo "$ps"
}

extract_vless_port() {
    local url="$1"
    local rest="${url#*@}"
    local endpoint="${rest%%\?*}"

    if [[ "$endpoint" =~ ^\[[^]]+\]:([0-9]+)$ ]]; then
        echo "${BASH_REMATCH[1]}"
    elif [[ "$endpoint" =~ :([0-9]+)$ ]]; then
        echo "${BASH_REMATCH[1]}"
    else
        echo "443"
    fi
}

format_host_port() {
    local host="$1"
    local port="$2"

    if [[ "$host" == \[*\] ]]; then
        echo "${host}:${port}"
    elif [[ "$host" == *:* ]]; then
        echo "[${host}]:${port}"
    else
        echo "${host}:${port}"
    fi
}

normalize_edge_input() {
    local edge="$1"
    local fallback_port="$2"
    EDGE_HOST="$edge"
    EDGE_PORT="$fallback_port"

    if [[ "$edge" =~ ^\[([^]]+)\]:([0-9]+)$ ]]; then
        EDGE_HOST="${BASH_REMATCH[1]}"
        EDGE_PORT="${BASH_REMATCH[2]}"
    elif [[ "$edge" =~ ^([^:]+):([0-9]+)$ ]]; then
        EDGE_HOST="${BASH_REMATCH[1]}"
        EDGE_PORT="${BASH_REMATCH[2]}"
    elif [[ "$edge" =~ ^\[([^]]+)\]$ ]]; then
        EDGE_HOST="${BASH_REMATCH[1]}"
    fi
}

update_vless_url() {
    local original_url="$1"
    local new_add="$2"
    local new_ps="$3"
    local port endpoint prefix rest suffix updated

    port=$(extract_vless_port "$original_url")
    normalize_edge_input "$new_add" "$port"
    endpoint=$(format_host_port "$EDGE_HOST" "$EDGE_PORT")
    prefix="${original_url%%@*}@"
    rest="${original_url#*@}"
    suffix="?${rest#*\?}"
    updated="${prefix}${endpoint}${suffix}"

    if [[ "$updated" == *"#"* ]]; then
        updated="${updated%%#*}#${new_ps}"
    else
        updated="${updated}#${new_ps}"
    fi

    echo "$updated"
}

update_vmess_url() {
    local original_json="$1"
    local new_add="$2"
    local new_ps="$3"
    local modified_json new_base64

    modified_json=$(echo "$original_json" | jq --arg new_add "$new_add" --arg new_ps "$new_ps" '.add = $new_add | .ps = $new_ps | del(.allowInsecure)')
    new_base64=$(echo -n "$modified_json" | base64 | tr -d '\n')
    echo "vmess://${new_base64}"
}

cidr_to_usable_ip() {
    local cidr="$1"
    local ip="${cidr%/*}"
    local prefix="${cidr#*/}"

    if [[ "$cidr" != */* ]]; then
        echo "$cidr"
        return
    fi

    if [[ "$ip" == *:* ]]; then
        echo "$ip"
        return
    fi

    local a b c d
    IFS=. read -r a b c d <<< "$ip"
    if [[ ! "$a$b$c$d$prefix" =~ ^[0-9]+$ ]] || [ "$prefix" -ge 31 ]; then
        echo "$ip"
        return
    fi

    d=$((d + 1))
    if [ "$d" -gt 255 ]; then
        d=1
        c=$((c + 1))
    fi
    echo "${a}.${b}.${c}.${d}"
}

select_vless_template() {
    local url ps

    for url in "${urls[@]}"; do
        [[ "$url" == vless://* ]] || continue
        [[ "$url" == *"security=tls"* && "$url" == *"type=ws"* ]] || continue
        [[ "$url" == *"path=%2Fvless-argo"* || "$url" == *"path=/vless-argo"* ]] || continue
        ps=$(get_vless_ps "$url")
        valid_urls+=("$url")
        valid_ps_names+=("$ps")
        valid_types+=("vless")
    done
}

select_vmess_template() {
    local url decoded_json ps

    for url in "${urls[@]}"; do
        [[ "$url" == vmess://* ]] || continue
        decoded_json=$(echo "${url#"vmess://"}" | base64 -d 2>/dev/null)
        if [ $? -eq 0 ] && [ -n "$decoded_json" ]; then
            ps=$(echo "$decoded_json" | jq -r .ps 2>/dev/null)
            if [ $? -eq 0 ] && [ -n "$ps" ] && [ "$ps" != "null" ]; then
                valid_urls+=("$url")
                valid_ps_names+=("$ps")
                valid_types+=("vmess")
            fi
        fi
    done
}

main() {
    local url_file="$URL_FILE"
    declare -a valid_urls valid_ps_names valid_types
    generated_urls=()
    
    echo -e "${GREEN}=================================================="
    echo -e " 节点优选生成器 (cfy)"
    echo -e " (适配老王的4合一sing-box)"
    echo -e " "
    echo -e " 作者: byJoey (github.com/byJoey)"
    echo -e " 博客: joeyblog.net"
    echo -e " TG群: t.me/+ft-zI76oovgwNmRh"
    echo -e "==================================================${NC}"
    echo ""

    if [ -f "$url_file" ]; then
        mapfile -t urls < "$url_file"
        select_vless_template
        if [ ${#valid_urls[@]} -eq 0 ]; then
            select_vmess_template
        fi
    fi

    local selected_url selected_type
    if [ ${#valid_urls[@]} -gt 0 ]; then
        if [ ${#valid_urls[@]} -eq 1 ]; then
            selected_url=${valid_urls[0]}
            selected_type=${valid_types[0]}
            echo -e "${YELLOW}检测到只有一个有效节点, 已自动选择: ${valid_ps_names[0]}${NC}"
        else
            echo -e "${YELLOW}请选择一个节点作为:${NC}"
            for i in "${!valid_ps_names[@]}"; do printf "%3d) %s\n" "$((i+1))" "${valid_ps_names[$i]}"; done
            local choice
            while true; do
                read -p "请输入选项编号 (1-${#valid_urls[@]}): " choice
                if [[ "$choice" =~ ^[0-9]+$ ]] && [ "$choice" -ge 1 ] && [ "$choice" -le ${#valid_urls[@]} ]; then
                    selected_url=${valid_urls[$((choice-1))]}
                    selected_type=${valid_types[$((choice-1))]}
                    break
                else echo -e "${RED}无效的输入, 请重试.${NC}"; fi
            done
        fi
    else
        echo -e "${YELLOW}在 $url_file 中未找到有效节点.${NC}"
        while true; do
            read -p "请手动粘贴一个 vless:// 或 vmess:// 链接作为模板: " selected_url
            if [[ "$selected_url" == vless://* ]]; then
                selected_type="vless"
                break
            fi
            if [[ "$selected_url" == vmess://* ]]; then
                decoded_json=$(echo "${selected_url#"vmess://"}" | base64 -d 2>/dev/null)
                if [ $? -ne 0 ] || [ -z "$decoded_json" ]; then echo -e "${RED}无法解码链接, 请检查链接是否完整有效.${NC}"; continue; fi
                ps_check=$(echo "$decoded_json" | jq -e .ps >/dev/null 2>&1)
                if [ $? -ne 0 ]; then echo -e "${RED}解码成功, 但JSON内容不完整或格式错误. 请重试.${NC}"; continue; fi
                selected_type="vmess"
                break
            fi
            echo -e "${RED}格式错误, 必须以 vless:// 或 vmess:// 开头.${NC}"
            continue
        done
    fi

    local base64_part original_json original_ps
    if [ "$selected_type" = "vless" ]; then
        original_ps=$(get_vless_ps "$selected_url")
    else
        base64_part=${selected_url#"vmess://"}
        original_json=$(echo "$base64_part" | base64 -d)
        original_ps=$(echo "$original_json" | jq -r .ps)
    fi
    echo -e "${GREEN}已选择: $original_ps${NC}"
    
    echo -e "${YELLOW}请选择要使用的 IP 地址来源:${NC}"
    echo "  1) Cloudflare 官方 (手动优选)"
    echo "  2) 云优选  "
    
    local ip_source_choice; local use_optimized_ips=false
    while true; do
        read -p "请输入选项编号 (1-2): " ip_source_choice
        if [[ "$ip_source_choice" == "1" ]]; then break;
        elif [[ "$ip_source_choice" == "2" ]]; then use_optimized_ips=true; break;
        else echo -e "${RED}无效的输入, 请重试.${NC}"; fi
    done
    
    declare -a ip_list isp_list; local num_to_generate=0
    if $use_optimized_ips; then
        get_all_optimized_ips || exit 1
        num_to_generate=${#ip_list[@]}
    else
        echo -e "${YELLOW}正在从 Cloudflare 官网获取 IPv4 地址列表...${NC}"
        cloudflare_ips=$(curl -s https://www.cloudflare.com/ips-v4)
        if [ -z "$cloudflare_ips" ]; then echo -e "${RED}无法获取 Cloudflare IP 列表.${NC}"; exit 1; fi
        mapfile -t ip_list <<< "$cloudflare_ips"
        echo -e "${GREEN}成功获取 ${#ip_list[@]} 个 Cloudflare IPv4 地址段.${NC}"
        while true; do
            read -p "请输入您想生成的 URL 数量: " num_to_generate
            if [[ "$num_to_generate" =~ ^[0-9]+$ ]] && [ "$num_to_generate" -gt 0 ]; then break;
            else echo -e "${RED}请输入一个有效的正整数.${NC}"; fi
        done
    fi

    echo "---"; echo -e "${YELLOW}生成的新节点链接如下:${NC}"
    if $use_optimized_ips; then
        for ((i=0; i<$num_to_generate; i++)); do
            local current_ip=${ip_list[$i]}; local isp_name=${isp_list[$i]}
            local name_prefix="${CFY_NAME_PREFIX:-$original_ps}"
            local new_ps="${name_prefix}-优选${isp_name}"
            local generated_url
            if [ "$selected_type" = "vless" ]; then
                generated_url=$(update_vless_url "$selected_url" "$current_ip" "$new_ps")
            else
                generated_url=$(update_vmess_url "$original_json" "$current_ip" "$new_ps")
            fi
            echo "$generated_url"
            generated_urls+=("$generated_url")
        done
    else
        for ((i=0; i<$num_to_generate; i++)); do
            local random_ip_range=${ip_list[$((RANDOM % ${#ip_list[@]}))]}
            local ip_from_range
            ip_from_range=$(cidr_to_usable_ip "$random_ip_range")
            local name_prefix="${CFY_NAME_PREFIX:-$original_ps}"
            local new_ps="${name_prefix}-CF$((i+1))"
            local generated_url
            if [ "$selected_type" = "vless" ]; then
                generated_url=$(update_vless_url "$selected_url" "$ip_from_range" "$new_ps")
            else
                generated_url=$(update_vmess_url "$original_json" "$ip_from_range" "$new_ps")
            fi
            echo "$generated_url"
            generated_urls+=("$generated_url")
        done
    fi
    save_generated_urls
    echo "---"; echo -e "${GREEN}共 ${num_to_generate} 个链接已生成完毕.${NC}"
}

case "$1" in
    -c|--check|--show)
        show_saved_results
        exit $?
        ;;
    -h|--help)
        show_help
        exit 0
        ;;
esac

check_deps
main
