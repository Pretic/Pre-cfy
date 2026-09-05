#!/bin/bash

INSTALL_PATH="/usr/local/bin/cfy"
REMOTE_URL="https://raw.githubusercontent.com/Pretic/Pre-cfy/main/cfy.sh"
umask 077

clear_inherited_transaction_lock_state() {
    unset \
        SUBSCRIPTION_LOCK_HELD \
        STABLE_TX_MUTATION_DEPTH STABLE_TX_MUTATION_FD \
        STABLE_TX_SUBSCRIPTION_DEPTH STABLE_TX_SUBSCRIPTION_FD \
        STABLE_TX_FIREWALL_DEPTH STABLE_TX_FIREWALL_FD \
        LEGACY_TX_MUTATION_DEPTH LEGACY_TX_MUTATION_FD LEGACY_TX_MUTATION_PATH \
        LEGACY_TX_SUBSCRIPTION_DEPTH LEGACY_TX_SUBSCRIPTION_FD LEGACY_TX_SUBSCRIPTION_PATH \
        LEGACY_TX_FIREWALL_DEPTH LEGACY_TX_FIREWALL_FD LEGACY_TX_FIREWALL_PATH
}

clear_inherited_transaction_lock_state || exit 2
URL_FILE="${URL_FILE:-/etc/sing-box/url.txt}"
RESULT_FILE="${RESULT_FILE:-/etc/sing-box/cfy-url.txt}"
SUB_FILE="${SUB_FILE:-/etc/sing-box/cfy-sub.txt}"
COMBINED_URL_FILE="${COMBINED_URL_FILE:-/etc/sing-box/all-url.txt}"
COMBINED_SUB_FILE="${COMBINED_SUB_FILE:-/etc/sing-box/all-sub.txt}"
SERVED_SUB_FILE="${SERVED_SUB_FILE:-/etc/sing-box/sub.txt}"
SUBSCRIPTION_LOCK_FILE="${SUBSCRIPTION_LOCK_FILE:-/etc/sing-box/.subscription.lock}"
CFY_SOURCE_GENERATION_FILE="${CFY_SOURCE_GENERATION_FILE:-/etc/sing-box/cfy-source.generation}"
RESULT_DIR="${RESULT_DIR:-/etc/sing-box/cfy-results}"
CFY_CURL_CONNECT_TIMEOUT="${CFY_CURL_CONNECT_TIMEOUT:-10}"
CFY_CURL_MAX_TIME="${CFY_CURL_MAX_TIME:-30}"
CFY_OPTIMIZED_IP_API_URL="${CFY_OPTIMIZED_IP_API_URL:-https://www.wetest.vip/api/cf2dns/get_cloudflare_ip}"
CFY_OPTIMIZED_IP_API_KEY="${CFY_OPTIMIZED_IP_API_KEY:-o1zrmHAF}"
CFY_IP_VERSION_SCOPE="${CFY_IP_VERSION_SCOPE:-}"
CFY_PER_ISP_LIMIT="${CFY_PER_ISP_LIMIT:-}"
CFY_HEALTH_PROBE="${CFY_HEALTH_PROBE:-0}"
CFY_HEALTH_PROBE_ATTEMPTS="${CFY_HEALTH_PROBE_ATTEMPTS:-2}"
CFY_HEALTH_MIN_SUCCESS="${CFY_HEALTH_MIN_SUCCESS:-2}"
CFY_HEALTH_CONNECT_TIMEOUT="${CFY_HEALTH_CONNECT_TIMEOUT:-3}"
CFY_HEALTH_MAX_TIME="${CFY_HEALTH_MAX_TIME:-5}"

repair_served_subscription_file() {
    [ -e "$SERVED_SUB_FILE" ] || return 0
    chmod 644 "$SERVED_SUB_FILE"
}

check_update_dependencies() {
    local cmd

    for cmd in flock sha256sum stat; do
        if ! command -v "$cmd" >/dev/null 2>&1; then
            case "$cmd" in
                flock)
                    echo "错误: 安装或更新前需要命令 'flock'。Debian/Ubuntu 与 Alpine 均请安装 util-linux。" >&2
                    ;;
                sha256sum|stat)
                    echo "错误: 安装或更新前需要命令 '$cmd'，请安装 coreutils。" >&2
                    ;;
            esac
            return 1
        fi
    done
    if [ -n "${SING_BOX_TRANSACTION_GROUP:-}" ] && \
       [[ ! "${SING_BOX_TRANSACTION_GROUP}" =~ ^[0-9]+$ ]] && \
       ! command -v getent >/dev/null 2>&1; then
        echo "错误: 使用命名的 SING_BOX_TRANSACTION_GROUP 时需要命令 'getent'。" >&2
        return 1
    fi
}

is_stdin_script() {
    case "$(basename "$0")" in
        bash|sh|-bash)
            return 0
            ;;
        *)
            return 1
            ;;
    esac
}

is_process_substitution_script() {
    [[ "$0" == /dev/fd/* || "$0" == /proc/*/fd/* ]]
}

drain_bootstrap_input() {
    # Bash executes this installer before the download has necessarily finished.
    # Consume the remaining stream before exit/exec closes curl's output pipe.
    if is_process_substitution_script; then
        cat -- "$0" >/dev/null
    elif is_stdin_script && [ ! -t 0 ]; then
        cat >/dev/null
    fi
}

install_from_remote() {
    if ! command -v curl >/dev/null 2>&1; then
        echo "错误: 未找到 curl，无法从远端安装 cfy。"
        return 1
    fi

    local tmp_file
    tmp_file="$(mktemp)"
    echo "正在从 GitHub 下载最新 cfy 脚本..."

    if ! curl -fsSL "$REMOTE_URL" -o "$tmp_file"; then
        rm -f "$tmp_file"
        echo "下载失败: 无法访问 $REMOTE_URL"
        return 1
    fi

    if ! grep -q 'REMOTE_URL="https://raw.githubusercontent.com/Pretic/Pre-cfy/main/cfy.sh"' "$tmp_file"; then
        rm -f "$tmp_file"
        echo "下载内容校验失败，未覆盖本地 cfy。"
        return 1
    fi

    if ! cp "$tmp_file" "$INSTALL_PATH"; then
        rm -f "$tmp_file"
        echo "❌ 写入脚本失败，请重试。"
        return 1
    fi

    rm -f "$tmp_file"
}

finish_install() {
    if ! chmod +x "$INSTALL_PATH"; then
        echo "❌ 安装后赋权失败，请检查权限。"
        exit 1
    fi

    if ! repair_served_subscription_file; then
        echo "警告: 无法修复 $SERVED_SUB_FILE 的读取权限，请手动执行 chmod 644。"
    fi

    echo "✅ 安装成功! 您现在可以随时随地运行 'cfy' 命令。"
    case "${1:-}" in
        --update|--upgrade)
            echo "cfy updated at $INSTALL_PATH."
            exit 0
            ;;
    esac

    echo "---"
    echo "首次运行..."
    exec "$INSTALL_PATH" "$@"
}

if [ "$0" != "$INSTALL_PATH" ]; then
    echo "正在安装 [cfy 节点优选生成器]..."

    if [ "$(id -u)" -ne 0 ]; then
        echo "错误: 安装需要管理员权限。请使用 'curl ... | sudo bash' 或 'sudo bash <(curl ...)' 命令来运行。"
        exit 1
    fi

    check_update_dependencies || exit 1

    echo "正在将脚本写入到 $INSTALL_PATH..."

    if is_stdin_script || is_process_substitution_script; then
        drain_bootstrap_input || exit 1
        install_from_remote || exit 1
    else
        if ! cp "$0" "$INSTALL_PATH"; then
            echo "❌ 复制脚本失败，请重试。"
            exit 1
        fi
    fi

    finish_install "$@"
fi
# --- 主程序从这里开始 ---

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'
declare -a generated_urls

atomic_write_file() {
    local target_file="$1"
    local mode="${2:-644}"
    local target_dir target_name tmp_file

    target_dir=$(dirname "$target_file")
    target_name=$(basename "$target_file")
    mkdir -p "$target_dir" || return 1
    tmp_file=$(mktemp "${target_dir}/.tmp.${target_name}.XXXXXX") || return 1

    if ! cat > "$tmp_file"; then
        rm -f "$tmp_file"
        return 1
    fi
    chmod "$mode" "$tmp_file" 2>/dev/null || true
    mv -f "$tmp_file" "$target_file"
}

write_text_file() {
    local target_file="$1"
    shift

    if [ "$#" -eq 0 ]; then
        printf '' | atomic_write_file "$target_file" 600
    else
        printf '%s\n' "$@" | atomic_write_file "$target_file" 600
    fi
}

show_help() {
    echo "用法: cfy [参数]"
    echo "  无参数        生成 Cloudflare 优选节点"
    echo "  -c, --check   查看最近一次生成的优选节点"
    echo "      --update  更新 cfy 脚本后退出"
    echo "  -h, --help    显示帮助"
}

show_update_done() {
    echo -e "${GREEN}cfy 已更新到 $INSTALL_PATH。${NC}"
    echo -e "${GREEN}更新命令不会修改 sing-box 已有节点或最近一次优选结果。${NC}"
}

update_self() {
    if [ "$(id -u)" -ne 0 ]; then
        echo -e "${RED}错误: 更新需要管理员权限，请使用 root 或 sudo 运行。${NC}"
        exit 1
    fi

    check_update_dependencies || exit 1

    if ! command -v curl >/dev/null 2>&1; then
        echo -e "${RED}错误: 未找到 curl，无法从远端更新 cfy。${NC}"
        exit 1
    fi

    local tmp_file
    tmp_file="$(mktemp)"
    echo -e "${YELLOW}正在从 GitHub 下载最新 cfy 脚本...${NC}"

    if ! curl -fsSL "$REMOTE_URL" -o "$tmp_file"; then
        rm -f "$tmp_file"
        echo -e "${RED}下载失败: 无法访问 $REMOTE_URL${NC}"
        echo -e "${YELLOW}请先检查本机是否能访问 raw.githubusercontent.com。${NC}"
        exit 1
    fi

    if ! grep -q 'INSTALL_PATH="/usr/local/bin/cfy"' "$tmp_file"; then
        rm -f "$tmp_file"
        echo -e "${RED}下载内容校验失败，未覆盖本地 cfy。${NC}"
        exit 1
    fi

    if ! install -m 755 "$tmp_file" "$INSTALL_PATH"; then
        rm -f "$tmp_file"
        echo -e "${RED}写入 $INSTALL_PATH 失败。${NC}"
        exit 1
    fi

    rm -f "$tmp_file"
    if ! repair_served_subscription_file; then
        echo -e "${YELLOW}警告: 无法修复 $SERVED_SUB_FILE 的读取权限，请手动执行 chmod 644。${NC}"
    fi
    show_update_done
}

show_saved_results() {
    if [ ! -s "$RESULT_FILE" ]; then
        echo -e "${YELLOW}尚未找到已保存的优选节点，请先运行 cfy 生成一次。${NC}"
        if show_source_templates; then
            echo -e "${YELLOW}以上是 Sing-box 已创建的 VLESS-WS-TLS-Argo 模板节点，运行 cfy 后会生成优选节点并保存。${NC}"
            return 0
        fi
        return 1
    fi

    echo -e "${GREEN}=== 最近一次优选节点 ===${NC}"
    cat "$RESULT_FILE"
    echo ""
    [ -s "$SUB_FILE" ] && echo -e "${GREEN}Base64订阅文件: ${SUB_FILE}${NC}"
    [ -s "$COMBINED_SUB_FILE" ] && echo -e "${GREEN}综合订阅文件: ${COMBINED_SUB_FILE} -> ${SERVED_SUB_FILE}${NC}"
    [ -d "$RESULT_DIR" ] && echo -e "${GREEN}历史结果目录: ${RESULT_DIR}${NC}"
}

command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Shared, versioned control-plane transaction namespace. Lock files are
# permanent inode anchors: callers may flock them, but must never truncate,
# rename, or unlink them. SING_BOX_TRANSACTION_ROOT exists for tests/chroots;
# production shares the root-owned default with Sing-box.
transaction_root_path() {
    local root="${SING_BOX_TRANSACTION_ROOT:-/var/lib/sing-box-transactions}"

    [ -n "$root" ] && [ "$root" != / ] && [[ "$root" = /* ]] || return 1
    [[ "$root" != *$'\n'* && "$root" != *$'\r'* ]] || return 1
    case "$root" in
        *//*|*/./*|*/../*|*/.|*/..) return 1 ;;
    esac
    root="${root%/}"
    [ -n "$root" ] && [ "$root" != / ] || return 1
    printf '%s\n' "$root"
}

transaction_expected_dir_mode() {
    if [ -n "${SING_BOX_TRANSACTION_GROUP:-}" ]; then
        printf '750\n'
    else
        printf '700\n'
    fi
}

transaction_expected_file_mode() {
    if [ -n "${SING_BOX_TRANSACTION_GROUP:-}" ]; then
        printf '640\n'
    else
        printf '600\n'
    fi
}

transaction_expected_gid() {
    local requested_group="${SING_BOX_TRANSACTION_GROUP:-}" group_entry gid

    if [ -z "$requested_group" ]; then
        id -g
        return
    fi
    [[ "$requested_group" != *$'\n'* && "$requested_group" != *$'\r'* ]] || return 1
    if command -v getent >/dev/null 2>&1; then
        group_entry=$(getent group "$requested_group" 2>/dev/null) || return 1
        gid=$(printf '%s\n' "$group_entry" | awk -F: 'NR == 1 { print $3 }') || return 1
    elif [[ "$requested_group" =~ ^[0-9]+$ ]]; then
        gid="$requested_group"
        if [ "$gid" != "$(id -g)" ] && \
           ! awk -F: -v wanted="$gid" '$3 == wanted { found=1 } END { exit !found }' /etc/group 2>/dev/null; then
            return 1
        fi
    else
        gid=$(awk -F: -v wanted="$requested_group" \
            '$1 == wanted { print $3; found=1; exit } END { exit !found }' \
            /etc/group 2>/dev/null) || return 1
    fi
    [[ "$gid" =~ ^[0-9]+$ ]] || return 1
    printf '%s\n' "$gid"
}

validate_transaction_path_components() {
    local path="${1:-}" component current=''
    local -a components=()

    [ -n "$path" ] && [ "$path" != / ] && [[ "$path" = /* ]] || return 1
    [[ "$path" != *$'\n'* && "$path" != *$'\r'* ]] || return 1
    case "$path" in
        *//*|*/./*|*/../*|*/.|*/..) return 1 ;;
    esac
    IFS='/' read -r -a components <<< "${path#/}"
    for component in "${components[@]}"; do
        [ -n "$component" ] || return 1
        current="${current}/${component}"
        if [ -e "$current" ] || [ -L "$current" ]; then
            [ -d "$current" ] && [ ! -L "$current" ] || return 1
        else
            break
        fi
    done
}

validate_transaction_directory() {
    local path="${1:-}" expected_mode="${2:-}" expected_gid="${3:-}"
    local actual_uid actual_gid actual_mode

    [ -d "$path" ] && [ ! -L "$path" ] || return 1
    actual_uid=$(stat -c '%u' -- "$path" 2>/dev/null) || return 1
    actual_gid=$(stat -c '%g' -- "$path" 2>/dev/null) || return 1
    actual_mode=$(stat -c '%a' -- "$path" 2>/dev/null) || return 1
    [ "$actual_uid" = "$(id -u)" ] && [ "$actual_gid" = "$expected_gid" ] && \
        [ "$actual_mode" = "$expected_mode" ]
}

ensure_transaction_directory() {
    local path="${1:-}" expected_mode="${2:-}" expected_gid="${3:-}"
    local actual_uid

    [ -n "$path" ] && [[ "$expected_mode" =~ ^7[05]0$ ]] && \
        [[ "$expected_gid" =~ ^[0-9]+$ ]] || return 1
    if [ -e "$path" ] || [ -L "$path" ]; then
        [ -d "$path" ] && [ ! -L "$path" ] || return 2
    elif ! (umask 077 && mkdir -- "$path"); then
        [ -d "$path" ] && [ ! -L "$path" ] || return 1
    fi
    actual_uid=$(stat -c '%u' -- "$path" 2>/dev/null) || return 2
    [ "$actual_uid" = "$(id -u)" ] || return 2
    chgrp "$expected_gid" -- "$path" 2>/dev/null || return 1
    chmod "$expected_mode" -- "$path" || return 1
    validate_transaction_directory "$path" "$expected_mode" "$expected_gid" || return 2
}

validate_transaction_regular_file() {
    local path="${1:-}" expected_mode="${2:-}" expected_gid="${3:-}"
    local actual_uid actual_gid actual_mode link_count

    [ -f "$path" ] && [ ! -L "$path" ] || return 1
    actual_uid=$(stat -c '%u' -- "$path" 2>/dev/null) || return 1
    actual_gid=$(stat -c '%g' -- "$path" 2>/dev/null) || return 1
    actual_mode=$(stat -c '%a' -- "$path" 2>/dev/null) || return 1
    link_count=$(stat -c '%h' -- "$path" 2>/dev/null) || return 1
    [ "$actual_uid" = "$(id -u)" ] && [ "$actual_gid" = "$expected_gid" ] && \
        [ "$actual_mode" = "$expected_mode" ] && [ "$link_count" = 1 ]
}

ensure_transaction_regular_file() {
    local path="${1:-}" expected_mode="${2:-}" expected_gid="${3:-}"
    local file_dir file_name tmp_file actual_uid link_count

    [ -n "$path" ] && [[ "$expected_mode" =~ ^6[04]0$ ]] && \
        [[ "$expected_gid" =~ ^[0-9]+$ ]] || return 1
    file_dir=$(dirname "$path") || return 1
    file_name=$(basename "$path") || return 1
    [ -d "$file_dir" ] && [ ! -L "$file_dir" ] || return 2
    if [ ! -e "$path" ] && [ ! -L "$path" ]; then
        tmp_file=$(mktemp "${file_dir}/.transaction-${file_name}.XXXXXX") || return 1
        if ! chgrp "$expected_gid" -- "$tmp_file" 2>/dev/null || \
           ! chmod "$expected_mode" -- "$tmp_file" || \
           ! ln -- "$tmp_file" "$path" 2>/dev/null; then
            rm -f -- "$tmp_file"
            [ -e "$path" ] || [ -L "$path" ] || return 1
        else
            rm -f -- "$tmp_file" || return 1
        fi
    fi
    [ -f "$path" ] && [ ! -L "$path" ] || return 2
    actual_uid=$(stat -c '%u' -- "$path" 2>/dev/null) || return 2
    link_count=$(stat -c '%h' -- "$path" 2>/dev/null) || return 2
    [ "$actual_uid" = "$(id -u)" ] && [ "$link_count" = 1 ] || return 2
    chgrp "$expected_gid" -- "$path" 2>/dev/null || return 1
    chmod "$expected_mode" -- "$path" || return 1
    validate_transaction_regular_file "$path" "$expected_mode" "$expected_gid" || return 2
}

write_transaction_schema_file() {
    local schema_file="${1:-}" expected_mode="${2:-}" expected_gid="${3:-}"
    local schema_dir schema_name tmp_file schema_value schema_size

    [ -n "$schema_file" ] || return 1
    schema_dir=$(dirname "$schema_file") || return 1
    schema_name=$(basename "$schema_file") || return 1
    if [ ! -e "$schema_file" ] && [ ! -L "$schema_file" ]; then
        tmp_file=$(mktemp "${schema_dir}/.transaction-${schema_name}.XXXXXX") || return 1
        if ! printf '1\n' > "$tmp_file" || \
           ! chgrp "$expected_gid" -- "$tmp_file" 2>/dev/null || \
           ! chmod "$expected_mode" -- "$tmp_file" || \
           ! ln -- "$tmp_file" "$schema_file" 2>/dev/null; then
            rm -f -- "$tmp_file"
            [ -e "$schema_file" ] || [ -L "$schema_file" ] || return 1
        else
            rm -f -- "$tmp_file" || return 1
        fi
    fi
    ensure_transaction_regular_file "$schema_file" "$expected_mode" "$expected_gid" || return $?
    schema_size=$(LC_ALL=C wc -c < "$schema_file" 2>/dev/null | tr -d '[:space:]') || return 2
    IFS= read -r schema_value < "$schema_file" || return 2
    [ "$schema_size" = 2 ] && [ "$schema_value" = 1 ] || return 2
}

ensure_stable_transaction_root() {
    local root dir_mode file_mode expected_gid lock_kind lock_path

    root=$(transaction_root_path) || return 2
    validate_transaction_path_components "$root" || return 2
    dir_mode=$(transaction_expected_dir_mode) || return 2
    file_mode=$(transaction_expected_file_mode) || return 2
    expected_gid=$(transaction_expected_gid) || return 2

    ensure_transaction_directory "$root" "$dir_mode" "$expected_gid" || return $?
    ensure_transaction_directory "$root/pending" "$dir_mode" "$expected_gid" || return $?
    ensure_transaction_directory "$root/recoveries" "$dir_mode" "$expected_gid" || return $?
    write_transaction_schema_file "$root/schema-version" "$file_mode" "$expected_gid" || return $?
    for lock_kind in mutation subscription firewall; do
        lock_path="$root/${lock_kind}.lock"
        ensure_transaction_regular_file "$lock_path" "$file_mode" "$expected_gid" || return $?
        [ ! -s "$lock_path" ] || return 2
    done
}

stable_transaction_lock_path() {
    local kind="${1:-}" root

    case "$kind" in mutation|subscription|firewall) ;; *) return 1 ;; esac
    root=$(transaction_root_path) || return 1
    printf '%s/%s.lock\n' "$root" "$kind"
}

stable_transaction_lock_rank() {
    case "${1:-}" in
        mutation) printf '1\n' ;;
        subscription) printf '2\n' ;;
        firewall) printf '3\n' ;;
        *) return 1 ;;
    esac
}

stable_transaction_lock_is_held() {
    case "${1:-}" in
        mutation) [ "${STABLE_TX_MUTATION_DEPTH:-0}" -gt 0 ] 2>/dev/null ;;
        subscription) [ "${STABLE_TX_SUBSCRIPTION_DEPTH:-0}" -gt 0 ] 2>/dev/null ;;
        firewall) [ "${STABLE_TX_FIREWALL_DEPTH:-0}" -gt 0 ] 2>/dev/null ;;
        *) return 1 ;;
    esac
}

stable_transaction_highest_rank() {
    if stable_transaction_lock_is_held firewall; then
        printf '3\n'
    elif stable_transaction_lock_is_held subscription; then
        printf '2\n'
    elif stable_transaction_lock_is_held mutation; then
        printf '1\n'
    else
        printf '0\n'
    fi
}

stable_transaction_lock_hook() {
    :
}

legacy_transaction_lock_hook() {
    :
}

reset_stable_transaction_lock_state() {
    local depth fd saved_path

    [ "$(stable_transaction_highest_rank)" -eq 0 ] || return 2
    for depth in \
        "${STABLE_TX_MUTATION_DEPTH:-0}" \
        "${STABLE_TX_SUBSCRIPTION_DEPTH:-0}" \
        "${STABLE_TX_FIREWALL_DEPTH:-0}" \
        "${LEGACY_TX_MUTATION_DEPTH:-0}" \
        "${LEGACY_TX_SUBSCRIPTION_DEPTH:-0}" \
        "${LEGACY_TX_FIREWALL_DEPTH:-0}"; do
        [ "$depth" = 0 ] || return 2
    done
    for fd in \
        "${STABLE_TX_MUTATION_FD:-}" \
        "${STABLE_TX_SUBSCRIPTION_FD:-}" \
        "${STABLE_TX_FIREWALL_FD:-}" \
        "${LEGACY_TX_MUTATION_FD:-}" \
        "${LEGACY_TX_SUBSCRIPTION_FD:-}" \
        "${LEGACY_TX_FIREWALL_FD:-}"; do
        [ -z "$fd" ] || return 2
    done
    for saved_path in \
        "${LEGACY_TX_MUTATION_PATH:-}" \
        "${LEGACY_TX_SUBSCRIPTION_PATH:-}" \
        "${LEGACY_TX_FIREWALL_PATH:-}"; do
        [ -z "$saved_path" ] || return 2
    done
    STABLE_TX_MUTATION_DEPTH=0
    STABLE_TX_MUTATION_FD=''
    STABLE_TX_SUBSCRIPTION_DEPTH=0
    STABLE_TX_SUBSCRIPTION_FD=''
    STABLE_TX_FIREWALL_DEPTH=0
    STABLE_TX_FIREWALL_FD=''
    LEGACY_TX_MUTATION_DEPTH=0
    LEGACY_TX_MUTATION_FD=''
    LEGACY_TX_MUTATION_PATH=''
    LEGACY_TX_SUBSCRIPTION_DEPTH=0
    LEGACY_TX_SUBSCRIPTION_FD=''
    LEGACY_TX_SUBSCRIPTION_PATH=''
    LEGACY_TX_FIREWALL_DEPTH=0
    LEGACY_TX_FIREWALL_FD=''
    LEGACY_TX_FIREWALL_PATH=''
}

acquire_stable_transaction_lock() {
    local kind="${1:-}" timeout_seconds="${2:-${STABLE_TRANSACTION_LOCK_TIMEOUT_SECONDS:-30}}"
    local rank highest_rank depth_var fd_var depth lock_path lock_fd
    local path_identity fd_identity file_mode expected_gid

    [[ "$timeout_seconds" =~ ^[0-9]+$ ]] || return 1
    rank=$(stable_transaction_lock_rank "$kind") || return 1
    case "$kind" in
        mutation) depth_var=STABLE_TX_MUTATION_DEPTH; fd_var=STABLE_TX_MUTATION_FD ;;
        subscription) depth_var=STABLE_TX_SUBSCRIPTION_DEPTH; fd_var=STABLE_TX_SUBSCRIPTION_FD ;;
        firewall) depth_var=STABLE_TX_FIREWALL_DEPTH; fd_var=STABLE_TX_FIREWALL_FD ;;
        *) return 1 ;;
    esac
    depth="${!depth_var:-0}"
    [[ "$depth" =~ ^[0-9]+$ ]] || return 2
    highest_rank=$(stable_transaction_highest_rank) || return 2
    [ "$highest_rank" -le "$rank" ] || return 2
    if [ "$depth" -gt 0 ]; then
        printf -v "$depth_var" '%s' "$((depth + 1))"
        return 0
    fi

    command_exists flock || return 1
    ensure_stable_transaction_root || return $?
    lock_path=$(stable_transaction_lock_path "$kind") || return 2
    file_mode=$(transaction_expected_file_mode) || return 2
    expected_gid=$(transaction_expected_gid) || return 2
    path_identity=$(stat -c '%d:%i' -- "$lock_path" 2>/dev/null) || return 2
    exec {lock_fd}>>"$lock_path" || return 1
    fd_identity=$(stat -Lc '%d:%i' -- "/proc/${BASHPID}/fd/${lock_fd}" 2>/dev/null) || {
        exec {lock_fd}>&-
        return 2
    }
    if [ "$fd_identity" != "$path_identity" ]; then
        exec {lock_fd}>&-
        return 2
    fi
    if ! flock -x -w "$timeout_seconds" "$lock_fd"; then
        exec {lock_fd}>&-
        return 1
    fi
    if ! validate_transaction_regular_file "$lock_path" "$file_mode" "$expected_gid" || \
       [ "$(stat -c '%d:%i' -- "$lock_path" 2>/dev/null)" != "$path_identity" ]; then
        exec {lock_fd}>&-
        return 2
    fi
    printf -v "$fd_var" '%s' "$lock_fd"
    printf -v "$depth_var" '1'
    if ! stable_transaction_lock_hook acquired "$kind" "$lock_path"; then
        release_stable_transaction_lock "$kind" >/dev/null 2>&1 || true
        return 2
    fi
}

release_stable_transaction_lock() {
    local kind="${1:-}" rank highest_rank depth_var fd_var depth lock_fd

    rank=$(stable_transaction_lock_rank "$kind") || return 1
    case "$kind" in
        mutation) depth_var=STABLE_TX_MUTATION_DEPTH; fd_var=STABLE_TX_MUTATION_FD ;;
        subscription) depth_var=STABLE_TX_SUBSCRIPTION_DEPTH; fd_var=STABLE_TX_SUBSCRIPTION_FD ;;
        firewall) depth_var=STABLE_TX_FIREWALL_DEPTH; fd_var=STABLE_TX_FIREWALL_FD ;;
        *) return 1 ;;
    esac
    depth="${!depth_var:-0}"
    [[ "$depth" =~ ^[1-9][0-9]*$ ]] || return 2
    highest_rank=$(stable_transaction_highest_rank) || return 2
    [ "$highest_rank" -le "$rank" ] || return 2
    if [ "$depth" -gt 1 ]; then
        printf -v "$depth_var" '%s' "$((depth - 1))"
        return 0
    fi
    lock_fd="${!fd_var:-}"
    [[ "$lock_fd" =~ ^[0-9]+$ ]] || return 2
    flock -u "$lock_fd" >/dev/null 2>&1 || true
    exec {lock_fd}>&-
    printf -v "$fd_var" ''
    printf -v "$depth_var" '0'
    stable_transaction_lock_hook released "$kind" '' || return 2
}

with_stable_transaction_lock() {
    local kind="${1:-}" callback="${2:-}" callback_status=0 release_status=0
    shift 2 || return 1

    declare -F "$callback" >/dev/null 2>&1 || return 1
    acquire_stable_transaction_lock "$kind" || return $?
    "$callback" "$@" || callback_status=$?
    release_stable_transaction_lock "$kind" || release_status=$?
    [ "$release_status" -eq 0 ] || return 2
    return "$callback_status"
}

validate_safe_legacy_lock() {
    local lock_path="${1:-}" expected_gid file_mode actual_uid actual_gid actual_mode
    local link_count lock_dir

    [ -n "$lock_path" ] && [[ "$lock_path" = /* ]] || return 1
    [[ "$lock_path" != *$'\n'* && "$lock_path" != *$'\r'* ]] || return 1
    lock_dir=$(dirname "$lock_path") || return 1
    validate_transaction_path_components "$lock_dir" || return 1
    [ -f "$lock_path" ] && [ ! -L "$lock_path" ] || return 1
    actual_uid=$(stat -c '%u' -- "$lock_path" 2>/dev/null) || return 1
    actual_gid=$(stat -c '%g' -- "$lock_path" 2>/dev/null) || return 1
    actual_mode=$(stat -c '%a' -- "$lock_path" 2>/dev/null) || return 1
    link_count=$(stat -c '%h' -- "$lock_path" 2>/dev/null) || return 1
    expected_gid=$(transaction_expected_gid) || return 1
    file_mode=$(transaction_expected_file_mode) || return 1
    [ "$actual_uid" = "$(id -u)" ] && [ "$link_count" = 1 ] || return 1
    if [ "$actual_mode" = 600 ]; then
        return 0
    fi
    [ "$actual_mode" = "$file_mode" ] && [ "$actual_gid" = "$expected_gid" ]
}

acquire_safe_legacy_lock() {
    local kind="${1:-}" lock_path="${2:-}" timeout_seconds="${3:-${STABLE_TRANSACTION_LOCK_TIMEOUT_SECONDS:-30}}"
    local depth_var fd_var path_var depth saved_path lock_fd path_identity fd_identity

    [[ "$timeout_seconds" =~ ^[0-9]+$ ]] || return 1
    case "$kind" in
        mutation) depth_var=LEGACY_TX_MUTATION_DEPTH; fd_var=LEGACY_TX_MUTATION_FD; path_var=LEGACY_TX_MUTATION_PATH ;;
        subscription) depth_var=LEGACY_TX_SUBSCRIPTION_DEPTH; fd_var=LEGACY_TX_SUBSCRIPTION_FD; path_var=LEGACY_TX_SUBSCRIPTION_PATH ;;
        firewall) depth_var=LEGACY_TX_FIREWALL_DEPTH; fd_var=LEGACY_TX_FIREWALL_FD; path_var=LEGACY_TX_FIREWALL_PATH ;;
        *) return 1 ;;
    esac
    depth="${!depth_var:-0}"
    saved_path="${!path_var:-}"
    [[ "$depth" =~ ^[0-9]+$ ]] || return 2
    if [ "$depth" -gt 0 ]; then
        [ "$saved_path" = "$lock_path" ] || return 2
        printf -v "$depth_var" '%s' "$((depth + 1))"
        return 0
    fi
    [[ "$lock_path" != *$'\n'* && "$lock_path" != *$'\r'* ]] || return 2
    if [ -z "$lock_path" ] || { [ ! -e "$lock_path" ] && [ ! -L "$lock_path" ]; }; then
        printf -v "$path_var" '%s' "$lock_path"
        printf -v "$fd_var" ''
        printf -v "$depth_var" '1'
        if ! legacy_transaction_lock_hook skipped "$kind" "$lock_path"; then
            printf -v "$path_var" ''
            printf -v "$fd_var" ''
            printf -v "$depth_var" '0'
            return 2
        fi
        return 0
    fi
    command_exists flock || return 1
    validate_safe_legacy_lock "$lock_path" || return 2
    path_identity=$(stat -c '%d:%i' -- "$lock_path" 2>/dev/null) || return 2
    exec {lock_fd}<"$lock_path" || return 2
    fd_identity=$(stat -Lc '%d:%i' -- "/proc/${BASHPID}/fd/${lock_fd}" 2>/dev/null) || {
        exec {lock_fd}>&-
        return 2
    }
    if [ "$fd_identity" != "$path_identity" ]; then
        exec {lock_fd}>&-
        return 2
    fi
    if ! flock -x -w "$timeout_seconds" "$lock_fd"; then
        exec {lock_fd}>&-
        return 1
    fi
    if ! validate_safe_legacy_lock "$lock_path" || \
       [ "$(stat -c '%d:%i' -- "$lock_path" 2>/dev/null)" != "$path_identity" ]; then
        exec {lock_fd}>&-
        return 2
    fi
    printf -v "$path_var" '%s' "$lock_path"
    printf -v "$fd_var" '%s' "$lock_fd"
    printf -v "$depth_var" '1'
    if ! legacy_transaction_lock_hook acquired "$kind" "$lock_path"; then
        release_safe_legacy_lock "$kind" >/dev/null 2>&1 || true
        return 2
    fi
}

release_safe_legacy_lock() {
    local kind="${1:-}" depth_var fd_var path_var depth lock_fd

    case "$kind" in
        mutation) depth_var=LEGACY_TX_MUTATION_DEPTH; fd_var=LEGACY_TX_MUTATION_FD; path_var=LEGACY_TX_MUTATION_PATH ;;
        subscription) depth_var=LEGACY_TX_SUBSCRIPTION_DEPTH; fd_var=LEGACY_TX_SUBSCRIPTION_FD; path_var=LEGACY_TX_SUBSCRIPTION_PATH ;;
        firewall) depth_var=LEGACY_TX_FIREWALL_DEPTH; fd_var=LEGACY_TX_FIREWALL_FD; path_var=LEGACY_TX_FIREWALL_PATH ;;
        *) return 1 ;;
    esac
    depth="${!depth_var:-0}"
    [[ "$depth" =~ ^[1-9][0-9]*$ ]] || return 2
    if [ "$depth" -gt 1 ]; then
        printf -v "$depth_var" '%s' "$((depth - 1))"
        return 0
    fi
    lock_fd="${!fd_var:-}"
    if [ -n "$lock_fd" ]; then
        [[ "$lock_fd" =~ ^[0-9]+$ ]] || return 2
        flock -u "$lock_fd" >/dev/null 2>&1 || true
        exec {lock_fd}>&-
    fi
    printf -v "$fd_var" ''
    printf -v "$path_var" ''
    printf -v "$depth_var" '0'
    legacy_transaction_lock_hook released "$kind" '' || return 2
}

acquire_transaction_lock_with_legacy() {
    local kind="${1:-}" legacy_path="${2:-}" timeout_seconds="${3:-${STABLE_TRANSACTION_LOCK_TIMEOUT_SECONDS:-30}}"
    local status stable_release_status=0

    acquire_stable_transaction_lock "$kind" "$timeout_seconds" || return $?
    acquire_safe_legacy_lock "$kind" "$legacy_path" "$timeout_seconds"
    status=$?
    if [ "$status" -ne 0 ]; then
        release_stable_transaction_lock "$kind" >/dev/null 2>&1 || stable_release_status=$?
        [ "$stable_release_status" -eq 0 ] || return 2
        return "$status"
    fi
}

release_transaction_lock_with_legacy() {
    local kind="${1:-}" legacy_status=0 stable_status=0

    release_safe_legacy_lock "$kind" || legacy_status=$?
    release_stable_transaction_lock "$kind" || stable_status=$?
    [ "$legacy_status" -eq 0 ] && [ "$stable_status" -eq 0 ] || return 2
}

with_transaction_lock_with_legacy() {
    local kind="${1:-}" legacy_path="${2:-}" callback="${3:-}"
    local callback_status=0 release_status=0
    shift 3 || return 1

    declare -F "$callback" >/dev/null 2>&1 || return 1
    acquire_transaction_lock_with_legacy "$kind" "$legacy_path" || return $?
    "$callback" "$@" || callback_status=$?
    release_transaction_lock_with_legacy "$kind" || release_status=$?
    [ "$release_status" -eq 0 ] || return 2
    return "$callback_status"
}

with_subscription_lock() {
    local lock_file="${SUBSCRIPTION_LOCK_FILE:-/etc/sing-box/.subscription.lock}"
    local timeout_seconds="${SUBSCRIPTION_LOCK_TIMEOUT_SECONDS:-30}"
    local lock_status=0 release_status=0

    if [ "${SUBSCRIPTION_LOCK_HELD:-0}" = 1 ]; then
        "$@"
        return $?
    fi
    [[ "$timeout_seconds" =~ ^[0-9]+$ ]] || return 1
    command -v flock >/dev/null 2>&1 || return 1
    acquire_transaction_lock_with_legacy subscription "$lock_file" "$timeout_seconds" || return $?

    local SUBSCRIPTION_LOCK_HELD=1
    "$@" || lock_status=$?
    release_transaction_lock_with_legacy subscription || release_status=$?
    [ "$release_status" -eq 0 ] || return 2
    return "$lock_status"
}

get_subscription_source_generation() {
    local source_file="${1:-$URL_FILE}"
    local digest byte_count

    [ -f "$source_file" ] && [ ! -L "$source_file" ] || return 1
    digest=$(sha256sum "$source_file" 2>/dev/null) || return 1
    digest=${digest%%[[:space:]]*}
    [[ "$digest" =~ ^[0-9A-Fa-f]{64}$ ]] || return 1
    byte_count=$(wc -c < "$source_file") || return 1
    byte_count=${byte_count//[[:space:]]/}
    [[ "$byte_count" =~ ^[0-9]+$ ]] || return 1
    printf '%s:%s\n' "${digest,,}" "$byte_count"
}

read_strict_subscription_generation_file() {
    local generation_file="${1:-}"
    local generation file_mode

    [ -n "$generation_file" ] || return 1
    [ -f "$generation_file" ] && [ ! -L "$generation_file" ] || return 1
    file_mode=$(stat -c '%a' -- "$generation_file" 2>/dev/null) || return 1
    [ "$file_mode" = 600 ] || return 1
    generation=$(awk '
        NR == 1 { value = $0; next }
        { invalid = 1 }
        END {
            if (NR != 1 || invalid) exit 1
            printf "%s", value
        }
    ' "$generation_file") || return 1
    [[ "$generation" =~ ^[0-9a-f]{64}:[0-9]+$ ]] || return 1
    printf '%s\n' "$generation"
}

read_cfy_source_generation_file() {
    local generation_file="${1:-$CFY_SOURCE_GENERATION_FILE}"

    read_strict_subscription_generation_file "$generation_file"
}

select_existing_cfy_subscription_source_locked() {
    local current_generation="${1:-}"
    local cfy_generation

    [ "${SUBSCRIPTION_LOCK_HELD:-0}" = 1 ] || return 1
    [[ "$current_generation" =~ ^[0-9a-f]{64}:[0-9]+$ ]] || return 1
    if [ -f "$RESULT_FILE" ] && [ ! -L "$RESULT_FILE" ] &&
       cfy_generation=$(read_cfy_source_generation_file "$CFY_SOURCE_GENERATION_FILE") &&
       [ "$cfy_generation" = "$current_generation" ]; then
        chmod 600 "$RESULT_FILE" || return 1
        printf '%s\n' "$RESULT_FILE"
    else
        printf '/dev/null\n'
    fi
}

verify_subscription_source_generation_locked() {
    local expected_generation="${1:-}"
    local current_generation

    [ "${SUBSCRIPTION_LOCK_HELD:-0}" = 1 ] || return 1
    [ -n "$expected_generation" ] || {
        echo -e "${RED}订阅源代际未知；拒绝发布长任务结果。${NC}" >&2
        return 1
    }
    current_generation=$(get_subscription_source_generation "$URL_FILE") || return 1
    if [ "$current_generation" != "$expected_generation" ]; then
        echo -e "${RED}Sing-box 订阅源已变化；丢弃基于旧代际生成的结果。${NC}" >&2
        return 1
    fi
}

encode_subscription_source() {
    local source_file="$1"
    local output_file="$2"

    if [ ! -s "$source_file" ]; then
        : > "$output_file"
    elif base64 -w0 "$source_file" > "$output_file" 2>/dev/null; then
        return 0
    else
        (set -o pipefail; base64 "$source_file" | tr -d '\n\r' > "$output_file")
    fi
}

write_base64_file() {
    local source_file="${1:-$RESULT_FILE}"
    local sub_file="${2:-$SUB_FILE}"
    local output_mode="${3:-600}"
    local sub_dir sub_name tmp_file

    case "$output_mode" in
        600|644) ;;
        *) return 1 ;;
    esac

    sub_dir=$(dirname "$sub_file")
    sub_name=$(basename "$sub_file")
    mkdir -p "$sub_dir" || return 1
    tmp_file=$(mktemp "${sub_dir}/.tmp.${sub_name}.XXXXXX") || return 1

    if [ -e "$sub_file" ] || [ -L "$sub_file" ]; then
        [ -f "$sub_file" ] && [ ! -L "$sub_file" ] || { rm -f "$tmp_file"; return 1; }
    fi
    encode_subscription_source "$source_file" "$tmp_file" || { rm -f "$tmp_file"; return 1; }
    chmod "$output_mode" "$tmp_file" || { rm -f "$tmp_file"; return 1; }
    mv -f "$tmp_file" "$sub_file" || { rm -f "$tmp_file"; return 1; }
}
normalize_url_candidate() {
    local line="$1"
    local candidate=""
    local esc=$'\033'

    line="${line//$'\r'/}"
    line="${line#"${line%%[![:space:]]*}"}"
    line="${line%"${line##*[![:space:]]}"}"

    if [[ "$line" == vless://* || "$line" == vmess://* ]]; then
        candidate="$line"
    elif [[ "$line" =~ (vless://[^[:space:]]+|vmess://[^[:space:]]+) ]]; then
        candidate="${BASH_REMATCH[1]}"
    else
        return 1
    fi

    candidate="${candidate%%${esc}*}"
    candidate="${candidate%$'\r'}"
    [ -n "$candidate" ] || return 1
    printf '%s\n' "$candidate"
}

add_url_candidate() {
    local line="$1" existing normalized

    normalized=$(normalize_url_candidate "$line" || true)
    [ -n "$normalized" ] || return 0
    for existing in "${urls[@]}"; do
        [ "$existing" = "$normalized" ] && return 0
    done
    urls+=("$normalized")
}

load_urls_from_file() {
    local source_file="$1" line

    [ -s "$source_file" ] || return 1
    while IFS= read -r line || [ -n "$line" ]; do
        line="${line//$'\r'/}"
        [ -z "$line" ] && continue
        add_url_candidate "$line"
    done < "$source_file"
}

load_urls_from_base64_file() {
    local source_file="$1" decoded line

    [ -s "$source_file" ] || return 1
    decoded=$(base64 -d "$source_file" 2>/dev/null || base64 --decode "$source_file" 2>/dev/null || true)
    [ -n "$decoded" ] || return 1
    while IFS= read -r line || [ -n "$line" ]; do
        line="${line//$'\r'/}"
        [ -z "$line" ] && continue
        add_url_candidate "$line"
    done <<< "$decoded"
}

load_source_urls_locked() {
    local source_generation

    [ "${SUBSCRIPTION_LOCK_HELD:-0}" = 1 ] || return 1
    urls=()
    load_urls_from_file "$URL_FILE" || true
    source_generation=$(get_subscription_source_generation "$URL_FILE") || return 1
    SOURCE_URL_GENERATION="$source_generation"
}

load_source_urls() {
    with_subscription_lock load_source_urls_locked
}

show_template_sources_hint() {
    local source_file

    echo -e "${YELLOW}已检查以下模板来源:${NC}"
    for source_file in "$URL_FILE" "$COMBINED_URL_FILE" "$RESULT_FILE" "$SERVED_SUB_FILE"; do
        if [ -s "$source_file" ]; then
            echo "  - $source_file (存在)"
        else
            echo "  - $source_file (不存在或为空)"
        fi
    done
}

publish_subscriptions_locked() {
    local staged_result_file="${1:-}"
    local expected_source_generation="${2:-}"
    local cfy_source_file=/dev/null
    local tmp_base_sub tmp_cfy_sub tmp_all_url tmp_all_sub tmp_sub tmp_sidecar='' target_file
    local base_sub_file="${BASE_SUB_FILE:-$(dirname "$URL_FILE")/base-sub.txt}"
    local current_source_generation
    local backup_file commit_failed=0 rollback_failed=0 index restore_index
    local -a commit_sources=() commit_targets=() backup_files=() target_existed=()

    [ "${SUBSCRIPTION_LOCK_HELD:-0}" = 1 ] || return 1
    for target_file in "$URL_FILE" "$base_sub_file" "$SUB_FILE" \
        "$COMBINED_URL_FILE" "$COMBINED_SUB_FILE" "$SERVED_SUB_FILE"; do
        mkdir -p "$(dirname "$target_file")" || return 1
        if [ -e "$target_file" ] || [ -L "$target_file" ]; then
            [ -f "$target_file" ] && [ ! -L "$target_file" ] || return 1
        fi
    done
    mkdir -p "$(dirname "$RESULT_FILE")" "$(dirname "$CFY_SOURCE_GENERATION_FILE")" || return 1
    [ -f "$URL_FILE" ] || return 1
    chmod 600 "$URL_FILE" || return 1
    current_source_generation=$(get_subscription_source_generation "$URL_FILE") || return 1

    if [ -n "$staged_result_file" ]; then
        [[ "$expected_source_generation" =~ ^[0-9a-f]{64}:[0-9]+$ ]] || return 1
        verify_subscription_source_generation_locked "$expected_source_generation" || return 1
        [ -f "$staged_result_file" ] && [ ! -L "$staged_result_file" ] || return 1
        chmod 600 "$staged_result_file" || return 1
        for target_file in "$RESULT_FILE" "$CFY_SOURCE_GENERATION_FILE"; do
            if [ -e "$target_file" ] || [ -L "$target_file" ]; then
                [ -f "$target_file" ] && [ ! -L "$target_file" ] || return 1
            fi
        done
        cfy_source_file="$staged_result_file"
    else
        cfy_source_file=$(select_existing_cfy_subscription_source_locked "$current_source_generation") || return 1
    fi

    tmp_base_sub=$(mktemp "$(dirname "$base_sub_file")/.tmp.$(basename "$base_sub_file").XXXXXX") || return 1
    tmp_cfy_sub=$(mktemp "$(dirname "$SUB_FILE")/.tmp.$(basename "$SUB_FILE").XXXXXX") || { rm -f "$tmp_base_sub"; return 1; }
    tmp_all_url=$(mktemp "$(dirname "$COMBINED_URL_FILE")/.tmp.$(basename "$COMBINED_URL_FILE").XXXXXX") || { rm -f "$tmp_base_sub" "$tmp_cfy_sub"; return 1; }
    tmp_all_sub=$(mktemp "$(dirname "$COMBINED_SUB_FILE")/.tmp.$(basename "$COMBINED_SUB_FILE").XXXXXX") || { rm -f "$tmp_base_sub" "$tmp_cfy_sub" "$tmp_all_url"; return 1; }
    tmp_sub=$(mktemp "$(dirname "$SERVED_SUB_FILE")/.tmp.$(basename "$SERVED_SUB_FILE").XXXXXX") || { rm -f "$tmp_base_sub" "$tmp_cfy_sub" "$tmp_all_url" "$tmp_all_sub"; return 1; }
    if [ -n "$staged_result_file" ]; then
        tmp_sidecar=$(mktemp "$(dirname "$CFY_SOURCE_GENERATION_FILE")/.tmp.$(basename "$CFY_SOURCE_GENERATION_FILE").XXXXXX") || {
            rm -f "$tmp_base_sub" "$tmp_cfy_sub" "$tmp_all_url" "$tmp_all_sub" "$tmp_sub"
            return 1
        }
        printf '%s\n' "$expected_source_generation" > "$tmp_sidecar" || {
            rm -f "$tmp_base_sub" "$tmp_cfy_sub" "$tmp_all_url" "$tmp_all_sub" "$tmp_sub" "$tmp_sidecar"
            return 1
        }
        chmod 600 "$tmp_sidecar" || {
            rm -f "$tmp_base_sub" "$tmp_cfy_sub" "$tmp_all_url" "$tmp_all_sub" "$tmp_sub" "$tmp_sidecar"
            return 1
        }
    fi

    if ! awk '{ sub(/\r$/, ""); if ($0 ~ /^[[:space:]]*$/) next; if (!seen[$0]++) print }' \
        "$URL_FILE" "$cfy_source_file" 2>/dev/null > "$tmp_all_url" ||
       ! encode_subscription_source "$URL_FILE" "$tmp_base_sub" ||
       ! encode_subscription_source "$cfy_source_file" "$tmp_cfy_sub" ||
       ! encode_subscription_source "$tmp_all_url" "$tmp_all_sub" ||
       ! encode_subscription_source "$tmp_all_url" "$tmp_sub" ||
       ! chmod 600 "$tmp_base_sub" "$tmp_cfy_sub" "$tmp_all_url" "$tmp_all_sub" ||
       ! chmod 644 "$tmp_sub"; then
        rm -f "$tmp_base_sub" "$tmp_cfy_sub" "$tmp_all_url" "$tmp_all_sub" "$tmp_sub"
        [ -n "$tmp_sidecar" ] && rm -f "$tmp_sidecar"
        return 1
    fi

    if [ -n "$expected_source_generation" ] &&
       ! verify_subscription_source_generation_locked "$expected_source_generation"; then
        rm -f "$tmp_base_sub" "$tmp_cfy_sub" "$tmp_all_url" "$tmp_all_sub" "$tmp_sub"
        [ -n "$tmp_sidecar" ] && rm -f "$tmp_sidecar"
        return 1
    fi

    if [ -n "$staged_result_file" ]; then
        commit_sources+=("$staged_result_file")
        commit_targets+=("$RESULT_FILE")
        commit_sources+=("$tmp_sidecar")
        commit_targets+=("$CFY_SOURCE_GENERATION_FILE")
    fi
    commit_sources+=("$tmp_base_sub" "$tmp_cfy_sub" "$tmp_all_url" "$tmp_all_sub" "$tmp_sub")
    commit_targets+=("$base_sub_file" "$SUB_FILE" "$COMBINED_URL_FILE" "$COMBINED_SUB_FILE" "$SERVED_SUB_FILE")

    for ((index = 0; index < ${#commit_targets[@]}; index++)); do
        target_file="${commit_targets[$index]}"
        backup_file=$(mktemp "$(dirname "$target_file")/.tmp.$(basename "$target_file").rollback.XXXXXX") || {
            rm -f "${commit_sources[@]}" "${backup_files[@]}"
            return 1
        }
        if [ -f "$target_file" ]; then
            cp -p -- "$target_file" "$backup_file" || {
                rm -f "$backup_file" "${commit_sources[@]}" "${backup_files[@]}"
                return 1
            }
            target_existed+=(1)
        else
            rm -f "$backup_file"
            target_existed+=(0)
        fi
        backup_files+=("$backup_file")
    done

    for ((index = 0; index < ${#commit_targets[@]}; index++)); do
        if ! mv -f -- "${commit_sources[$index]}" "${commit_targets[$index]}"; then
            commit_failed=1
            for ((restore_index = index - 1; restore_index >= 0; restore_index--)); do
                if [ "${target_existed[$restore_index]}" = 1 ]; then
                    if ! mv -f -- "${backup_files[$restore_index]}" "${commit_targets[$restore_index]}"; then
                        rollback_failed=1
                        printf 'FATAL: subscription rollback failed; preserved backup %s for %s\n' \
                            "${backup_files[$restore_index]}" "${commit_targets[$restore_index]}" >&2
                    fi
                else
                    if ! rm -f -- "${commit_targets[$restore_index]}"; then
                        rollback_failed=1
                        printf 'FATAL: subscription rollback failed; remove manually: %s\n' \
                            "${commit_targets[$restore_index]}" >&2
                    fi
                fi
            done
            break
        fi
    done
    rm -f "${commit_sources[@]}"
    if [ "$commit_failed" -eq 0 ]; then
        rm -f "${backup_files[@]}"
        return 0
    fi
    if [ "$rollback_failed" -ne 0 ]; then
        printf 'FATAL: subscription rollback was incomplete; recovery files remain beside the subscription targets\n' >&2
        return 2
    fi
    rm -f "${backup_files[@]}"
    return 1
}

sync_combined_subscription() {
    with_subscription_lock publish_subscriptions_locked
}

save_generated_urls_locked() {
    local result_dir staged_result_file history_file publish_status
    local expected_source_generation="${SOURCE_URL_GENERATION:-}"

    [ ${#generated_urls[@]} -eq 0 ] && return 0
    verify_subscription_source_generation_locked "$expected_source_generation" || return 1

    result_dir=$(dirname "$RESULT_FILE") || return 1
    mkdir -p "$result_dir" "$RESULT_DIR" || return 1
    if [ -e "$RESULT_FILE" ] || [ -L "$RESULT_FILE" ]; then
        [ -f "$RESULT_FILE" ] && [ ! -L "$RESULT_FILE" ] || return 1
    fi
    staged_result_file=$(mktemp "${result_dir}/.tmp.$(basename "$RESULT_FILE").XXXXXX") || return 1
    printf '%s\n' "${generated_urls[@]}" > "$staged_result_file" || { rm -f "$staged_result_file"; return 1; }
    chmod 600 "$staged_result_file" || { rm -f "$staged_result_file"; return 1; }
    publish_subscriptions_locked "$staged_result_file" "$expected_source_generation" || {
        publish_status=$?
        rm -f "$staged_result_file"
        return "$publish_status"
    }

    history_file="${RESULT_DIR}/$(date +%Y%m%d-%H%M%S).txt"
    cp "$RESULT_FILE" "$history_file" 2>/dev/null || true

    echo -e "${GREEN}已保存最近一次优选结果: ${RESULT_FILE}${NC}"
    echo -e "${GREEN}已同步到综合订阅: ${SERVED_SUB_FILE}${NC}"
    echo -e "${GREEN}后续可运行 cfy -c 再次查看。${NC}"
}

save_generated_urls() {
    with_subscription_lock save_generated_urls_locked
}

is_valid_edge_address() {
    local edge="$1"
    local host="$edge"

    [ -n "$host" ] || return 1
    host="${host%%/*}"
    if [[ "$host" =~ ^\[([0-9A-Fa-f:.]+)\](:[0-9]+)?$ ]]; then
        return 0
    fi
    if [[ "$host" =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}(:[0-9]+)?$ ]]; then
        return 0
    fi
    if [[ "$host" =~ ^[0-9A-Fa-f:]+$ ]] && [[ "$host" == *:* ]]; then
        return 0
    fi
    [[ "$host" =~ ^[A-Za-z0-9.-]+(:[0-9]+)?$ ]] && [[ "$host" == *.* ]]
}

is_valid_ipv4_literal() {
    local address="$1" octet
    local -a octets

    [[ "$address" =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}$ ]] || return 1
    IFS='.' read -r -a octets <<< "$address"
    [ "${#octets[@]}" -eq 4 ] || return 1
    for octet in "${octets[@]}"; do
        (( 10#$octet <= 255 )) || return 1
    done
}

is_valid_ipv6_literal() {
    local address="$1" left right remainder segment
    local count=0
    local -a groups

    [[ "$address" =~ ^[0-9A-Fa-f:]+$ ]] && [[ "$address" == *:* ]] || return 1
    [[ "$address" != *:::* ]] || return 1
    [[ "$address" != :* || "$address" == ::* ]] || return 1
    [[ "$address" != *: || "$address" == *:: ]] || return 1

    if [[ "$address" == *"::"* ]]; then
        remainder="${address#*::}"
        [[ "$remainder" != *"::"* ]] || return 1
        left="${address%%::*}"
        right="${address#*::}"
        for remainder in "$left" "$right"; do
            [ -n "$remainder" ] || continue
            IFS=':' read -r -a groups <<< "$remainder"
            for segment in "${groups[@]}"; do
                [[ "$segment" =~ ^[0-9A-Fa-f]{1,4}$ ]] || return 1
                count=$((count + 1))
            done
        done
        [ "$count" -lt 8 ]
        return
    fi

    [[ "$address" != :* && "$address" != *: ]] || return 1
    IFS=':' read -r -a groups <<< "$address"
    [ "${#groups[@]}" -eq 8 ] || return 1
    for segment in "${groups[@]}"; do
        [[ "$segment" =~ ^[0-9A-Fa-f]{1,4}$ ]] || return 1
    done
}

is_valid_optimized_ip_literal() {
    local address="$1" expected_version="${2:-both}"

    case "$expected_version" in
        ipv4) is_valid_ipv4_literal "$address" ;;
        ipv6) is_valid_ipv6_literal "$address" ;;
        both) is_valid_ipv4_literal "$address" || is_valid_ipv6_literal "$address" ;;
        *) return 1 ;;
    esac
}

normalize_edge_latency() {
    local latency="$1" digits

    latency=$(printf '%s' "$latency" | sed 's/^[[:space:]]*//; s/[[:space:]]*$//')
    [[ "$latency" =~ ^([0-9]+)[[:space:]]*([mM][sS]|毫秒)?$ ]] || return 1
    digits="${BASH_REMATCH[1]}"
    while [ "${#digits}" -gt 1 ] && [ "${digits:0:1}" = "0" ]; do
        digits="${digits:1}"
    done
    [ "$digits" != "0" ] || return 1
    printf '%s\n' "$digits"
}

decimal_latency_less_than() {
    local left="$1" right="$2" index left_digit right_digit

    if [ "${#left}" -lt "${#right}" ]; then
        return 0
    elif [ "${#left}" -gt "${#right}" ]; then
        return 1
    fi
    for ((index=0; index<${#left}; index++)); do
        left_digit="${left:index:1}"
        right_digit="${right:index:1}"
        [ "$left_digit" = "$right_digit" ] && continue
        [ "$left_digit" -lt "$right_digit" ]
        return
    done
    return 1
}

check_deps() {
    for cmd in jq curl base64 grep sed mktemp flock sha256sum stat; do
        if ! command -v "$cmd" &> /dev/null; then
            if [ "$cmd" = flock ]; then
                echo -e "${RED}错误: 命令 'flock' 未找到。Debian/Ubuntu 与 Alpine 均请安装 util-linux.${NC}"
            else
                echo -e "${RED}错误: 命令 '$cmd' 未找到. 请先安装它.${NC}"
            fi
            exit 1
        fi
    done
    if [ -n "${SING_BOX_TRANSACTION_GROUP:-}" ] && \
       [[ ! "${SING_BOX_TRANSACTION_GROUP}" =~ ^[0-9]+$ ]] && \
       ! command -v getent >/dev/null 2>&1; then
        echo -e "${RED}错误: 使用命名的 SING_BOX_TRANSACTION_GROUP 时需要命令 'getent'.${NC}"
        exit 1
    fi
}

collect_unique_optimized_pairs() {
    local source_file="$1"
    local pair edge_ip edge_isp
    declare -A seen_edges=()

    ip_list=()
    isp_list=()

    while IFS= read -r pair || [ -n "$pair" ]; do
        [ -n "$pair" ] || continue
        edge_ip="${pair%% *}"
        edge_isp="${pair#* }"
        if [[ -n "${seen_edges[$edge_ip]+x}" ]]; then
            continue
        fi
        seen_edges["$edge_ip"]=1
        ip_list+=("$edge_ip")
        isp_list+=("$edge_isp")
    done < "$source_file"
}

collect_ranked_optimized_pairs() {
    local source_file="$1"
    local per_group_limit="${2:-3}"
    local ip_scope="${3:-both}"
    local line edge_ip edge_isp edge_latency edge_version group_key
    local index group slot best_index best_latency desired_version
    local -a candidate_ips candidate_isps candidate_latencies candidate_groups group_order
    declare -A seen_edges=()
    declare -A seen_groups=()
    declare -A selected_indices=()

    if [[ ! "$per_group_limit" =~ ^[1-9][0-9]*$ ]]; then
        per_group_limit=3
    fi

    while IFS='|' read -r edge_ip edge_isp edge_latency || [ -n "$edge_ip" ]; do
        edge_ip=$(printf '%s' "$edge_ip" | sed 's/^[[:space:]]*//; s/[[:space:]]*$//')
        edge_isp=$(printf '%s' "${edge_isp:-CF}" | sed 's/^[[:space:]]*//; s/[[:space:]]*$//; s/[[:space:]]\+/_/g')
        is_valid_edge_address "$edge_ip" || continue
        edge_latency=$(normalize_edge_latency "$edge_latency") || continue
        if [[ -n "${seen_edges[$edge_ip]+x}" ]]; then
            continue
        fi
        seen_edges["$edge_ip"]=1

        edge_version=$(get_edge_ip_version "$edge_ip")
        case "$ip_scope" in
            ipv4) [ "$edge_version" = "ipv4" ] || continue ;;
            ipv6) [ "$edge_version" = "ipv6" ] || continue ;;
        esac
        group_key="${edge_isp:-CF}|${edge_version}"
        if [[ -z "${seen_groups[$group_key]+x}" ]]; then
            seen_groups["$group_key"]=1
            group_order+=("$group_key")
        fi
        candidate_ips+=("$edge_ip")
        candidate_isps+=("${edge_isp:-CF}")
        candidate_latencies+=("$edge_latency")
        candidate_groups+=("$group_key")
    done < "$source_file"

    ip_list=()
    isp_list=()
    for desired_version in ipv4 ipv6; do
        case "$ip_scope" in
            ipv4) [ "$desired_version" = "ipv4" ] || continue ;;
            ipv6) [ "$desired_version" = "ipv6" ] || continue ;;
        esac
        for group in "${group_order[@]}"; do
            [ "${group##*|}" = "$desired_version" ] || continue
            for ((slot=0; slot<per_group_limit; slot++)); do
                best_index=-1
                best_latency=''
                for ((index=0; index<${#candidate_ips[@]}; index++)); do
                    [ "${candidate_groups[$index]}" = "$group" ] || continue
                    [[ -z "${selected_indices[$index]+x}" ]] || continue
                    if [ "$best_index" -lt 0 ] || decimal_latency_less_than "${candidate_latencies[$index]}" "$best_latency"; then
                        best_index=$index
                        best_latency=${candidate_latencies[$index]}
                    fi
                done
                [ "$best_index" -ge 0 ] || break
                selected_indices["$best_index"]=1
                ip_list+=("${candidate_ips[$best_index]}")
                isp_list+=("${candidate_isps[$best_index]}")
            done
        done
    done
}

get_candidate_group_limit() {
    local ip_scope="$1"

    if [[ "${CFY_PER_ISP_LIMIT:-}" =~ ^[1-9][0-9]*$ ]]; then
        printf '%s\n' "$CFY_PER_ISP_LIMIT"
    elif [ "$ip_scope" = "both" ]; then
        printf '%s\n' "3"
    else
        printf '%s\n' "5"
    fi
}

parse_wetest_api_payload() {
    local payload="$1"
    local target_file="$2"
    local expected_version="${3:-both}"
    local rows ip isp latency normalized_latency actual_version normalized_isp
    local appended=0

    rows=$(printf '%s' "$payload" | jq -r '
        def candidate_row($fallback):
            [
                (.ip // ""),
                (.line_name // .line // $fallback),
                ((.rtt_avg // .latency // "")
                    | if type == "number" then (. * 1000 | round) else . end)
            ]
            | @tsv;
        if (.status == true and ((.code | tostring) == "200")) then
            if ((.info | type) == "object") then
                .info
                | to_entries[]
                | select(.key == "CM" or .key == "CU" or .key == "CT")
                | .key as $group
                | select((.value | type) == "array")
                | .value[]
                | select(type == "object")
                | candidate_row($group)
            elif ((.info | type) == "array") then
                .info[]
                | select(type == "object")
                | candidate_row("CF")
            else
                empty
            end
        else
            empty
        end
    ' 2>/dev/null) || return 1

    while IFS=$'\t' read -r ip isp latency || [ -n "$ip" ]; do
        ip=$(printf '%s' "$ip" | sed 's/^[[:space:]]*//; s/[[:space:]]*$//')
        isp=$(printf '%s' "${isp:-CF}" | sed 's/^[[:space:]]*//; s/[[:space:]]*$//; s/[[:space:]|]\+/_/g')
        is_valid_optimized_ip_literal "$ip" "$expected_version" || continue
        actual_version=$(get_edge_ip_version "$ip")
        case "$expected_version" in
            ipv4|ipv6) [ "$actual_version" = "$expected_version" ] || continue ;;
        esac
        normalized_latency=$(normalize_edge_latency "$latency") || continue
        normalized_isp=$(printf '%s' "$isp" | tr '[:upper:]' '[:lower:]')
        case "$normalized_isp" in
            cm) isp="Mobile" ;;
            cu) isp="Unicom" ;;
            ct) isp="Telecom" ;;
        esac
        printf '%s|%s|%s\n' "$ip" "${isp:-CF}" "$normalized_latency" >> "$target_file"
        appended=$((appended + 1))
    done <<< "$rows"

    [ "$appended" -gt 0 ]
}

get_all_optimized_ips() {
    local url_v4="https://www.wetest.vip/page/cloudflare/address_v4.html"
    local url_v6="https://www.wetest.vip/page/cloudflare/address_v6.html"
    local api_url="${CFY_OPTIMIZED_IP_API_URL:-https://www.wetest.vip/api/cf2dns/get_cloudflare_ip}"
    local api_key="${CFY_OPTIMIZED_IP_API_KEY:-o1zrmHAF}"

    echo -e "${YELLOW}Fetching optimized IP list (IPv4 & IPv6)...${NC}"

    local paired_data_file
    paired_data_file=$(mktemp) || return 1

    parse_html_url() {
        local url="$1" type_desc="$2" expected_version="$3"
        local html_content table_rows row ip isp latency
        local ip_label=$'\344\274\230\351\200\211\345\234\260\345\235\200'
        local isp_label=$'\347\272\277\350\267\257\345\220\215\347\247\260'
        local latency_label=$'\345\276\200\350\277\224\345\273\266\350\277\237'

        echo -e "  -> Fetching ${type_desc} list..."
        html_content=$(curl -fsSL --connect-timeout "$CFY_CURL_CONNECT_TIMEOUT" --max-time "$CFY_CURL_MAX_TIME" "$url" 2>/dev/null || true)
        if [ -z "$html_content" ]; then
            echo -e "${RED}  -> Failed to fetch ${type_desc} list.${NC}"
            return
        fi

        table_rows=$(printf '%s' "$html_content" | tr -d '\n\r' | sed 's/<tr>/\n&/g' | grep '^<tr>' || true)
        while IFS= read -r row || [ -n "$row" ]; do
            ip=$(printf '%s' "$row" | sed -n "s/.*data-label=\"$ip_label\">\([^<]*\)<.*/\1/p")
            isp=$(printf '%s' "$row" | sed -n "s/.*data-label=\"$isp_label\">\([^<]*\)<.*/\1/p")
            latency=$(printf '%s' "$row" | sed -n "s/.*data-label=\"$latency_label\">\([^<]*\)<.*/\1/p")
            ip=$(printf '%s' "$ip" | sed 's/^[[:space:]]*//; s/[[:space:]]*$//')
            isp=$(printf '%s' "${isp:-CF}" | sed 's/^[[:space:]]*//; s/[[:space:]]*$//; s/[[:space:]]\+/_/g')
            is_valid_optimized_ip_literal "$ip" "$expected_version" || continue
            latency=$(normalize_edge_latency "$latency") || continue
            printf '%s|%s|%s\n' "$ip" "${isp:-CF}" "$latency" >> "$paired_data_file"
        done <<< "$table_rows"
    }

    fetch_family() {
        local api_type="$1" expected_version="$2" html_url="$3" type_desc="$4" api_content

        echo -e "  -> Fetching ${type_desc} list..."
        api_content=$(curl -fsSL \
            --connect-timeout "$CFY_CURL_CONNECT_TIMEOUT" \
            --max-time "$CFY_CURL_MAX_TIME" \
            --get \
            --data-urlencode "key=${api_key}" \
            --data-urlencode "type=${api_type}" \
            "$api_url" 2>/dev/null || true)
        if [ -n "$api_content" ] && \
           parse_wetest_api_payload "$api_content" "$paired_data_file" "$expected_version"; then
            return 0
        fi

        echo -e "${YELLOW}  -> ${type_desc} API unavailable or invalid; trying the page fallback.${NC}"
        parse_html_url "$html_url" "${type_desc} fallback" "$expected_version"
    }

    fetch_family "v4" "ipv4" "$url_v4" "IPv4"
    fetch_family "v6" "ipv6" "$url_v6" "IPv6"

    if ! [ -s "$paired_data_file" ]; then
        rm -f "$paired_data_file"
        echo -e "${RED}Failed to parse optimized IP addresses from all sources.${NC}"
        return 1
    fi

    declare -g -a ip_list isp_list
    local count_ipv4=0 count_ipv6=0 edge_ip edge_version group_limit
    group_limit=$(get_candidate_group_limit "$IP_VERSION_SCOPE")
    collect_ranked_optimized_pairs "$paired_data_file" "$group_limit" "$IP_VERSION_SCOPE"
    rm -f "$paired_data_file"
    for edge_ip in "${ip_list[@]}"; do
        edge_version="$(get_edge_ip_version "$edge_ip")"
        if [ "$edge_version" = "ipv6" ]; then
            count_ipv6=$((count_ipv6 + 1))
        else
            count_ipv4=$((count_ipv4 + 1))
        fi
    done
    if [ ${#ip_list[@]} -eq 0 ]; then
        echo -e "${RED}Parsed sources but found no valid IP addresses.${NC}"
        return 1
    fi
    echo -e "${GREEN}Selected ${#ip_list[@]} low-RTT optimized IP addresses (${count_ipv4} IPv4, ${count_ipv6} IPv6; up to ${group_limit} per ISP/family; scope ${IP_VERSION_SCOPE}).${NC}"
    return 0
}
get_vless_ps() {
    local url="$1"
    local ps="${url##*#}"
    if [ "$ps" = "$url" ] || [ -z "$ps" ]; then
        ps="vless-ws-tls-argo"
    fi
    echo "$ps"
}

url_decode() {
    local value="${1//+/ }"
    printf '%b' "${value//%/\\x}"
}

url_encode_fragment() {
    jq -nr --arg value "$1" '$value|@uri'
}

sanitize_remark() {
    local value="$1"
    value=$(printf '%s' "$value" | sed -E 's/[[:space:]]+/_/g; s/[^A-Za-z0-9._-]+/_/g; s/_+/_/g; s/^_//; s/_$//')
    printf '%s\n' "$value"
}

get_name_prefix() {
    local ps="$1"
    local prefix="$ps"

    prefix="${prefix%-vless-ws-tls-argo}"
    prefix="${prefix%-vless-reality-ipv4}"
    prefix="${prefix%-vless-reality-ipv6}"
    prefix=$(printf '%s' "$prefix" | sed -E 's/[[:space:]]+/_/g; s/_+/_/g; s/^-+//; s/-+$//')
    [ -n "$prefix" ] || prefix="PreNet"
    printf '%s\n' "$prefix"
}

normalize_isp_group() {
    local isp="$1"
    local normalized

    normalized=$(printf '%s' "$isp" | tr '[:upper:]' '[:lower:]')
    case "$normalized" in
        *电信*|*telecom*|*chinanet*|*ctcc*) printf '%s\n' "中国电信" ;;
        *联通*|*unicom*|*china169*|*cucc*) printf '%s\n' "中国联通" ;;
        *移动*|*mobile*|*cmcc*|*cmi*) printf '%s\n' "中国移动" ;;
        *) return 1 ;;
    esac
}

is_ipv6_edge() {
    local edge="$1"
    local host="${edge%%/*}"

    if [[ "$host" =~ ^\[([0-9A-Fa-f:.]+)\](:[0-9]+)?$ ]]; then
        return 0
    fi
    [[ "$host" =~ ^[0-9A-Fa-f:]+$ ]] && [[ "$host" == *:* ]]
}

get_edge_ip_version() {
    if is_ipv6_edge "$1"; then
        printf '%s\n' "ipv6"
    else
        printf '%s\n' "ipv4"
    fi
}

resolve_ip_version_scope() {
    local requested_scope="${1:-}"
    local has_ipv4="${2:-0}"
    local has_ipv6="${3:-0}"

    case "$requested_scope" in
        ipv4|IPv4|4) printf '%s\n' "ipv4"; return 0 ;;
        ipv6|IPv6|6) printf '%s\n' "ipv6"; return 0 ;;
        both|BOTH|all|ALL|dual|DUAL|46|ipv4+ipv6|IPv4+IPv6) printf '%s\n' "both"; return 0 ;;
    esac

    if [ "$has_ipv4" = "1" ] && [ "$has_ipv6" = "1" ]; then
        printf '%s\n' "both"
    elif [ "$has_ipv6" = "1" ]; then
        printf '%s\n' "ipv6"
    else
        printf '%s\n' "ipv4"
    fi
}

choose_ip_version_scope() {
    local has_ipv4=0 has_ipv6=0

    case "${CFY_IP_VERSION_SCOPE}" in
        ipv4|IPv4|4|ipv6|IPv6|6|both|BOTH|all|ALL|dual|DUAL|46|ipv4+ipv6|IPv4+IPv6)
            IP_VERSION_SCOPE=$(resolve_ip_version_scope "$CFY_IP_VERSION_SCOPE" 0 0)
            echo -e "${GREEN}Using requested IP stack scope: ${IP_VERSION_SCOPE}.${NC}"
            return 0
            ;;
    esac

    if curl -4 -fsS --connect-timeout 4 --max-time 8 -o /dev/null https://www.cloudflare.com/cdn-cgi/trace 2>/dev/null; then
        has_ipv4=1
    fi
    if curl -6 -fsS --connect-timeout 4 --max-time 8 -o /dev/null https://www.cloudflare.com/cdn-cgi/trace 2>/dev/null; then
        has_ipv6=1
    fi

    IP_VERSION_SCOPE=$(resolve_ip_version_scope "" "$has_ipv4" "$has_ipv6")
    if [ "$has_ipv4" = "0" ] && [ "$has_ipv6" = "0" ]; then
        echo -e "${YELLOW}Could not verify either IP stack; falling back to IPv4 candidates.${NC}"
    else
        echo -e "${GREEN}Detected VPS IP stack: ${IP_VERSION_SCOPE}.${NC}"
    fi
}

should_include_ip_version() {
    local ip_version="$1"

    case "$IP_VERSION_SCOPE" in
        both) return 0 ;;
        ipv6) [ "$ip_version" = "ipv6" ] ;;
        *)    [ "$ip_version" = "ipv4" ] ;;
    esac
}

get_vless_query_param() {
    local url="$1"
    local key="$2"
    local query pair param_name param_value

    [[ "$url" == *\?* ]] || return 1
    query="${url#*\?}"
    query="${query%%#*}"

    IFS='&' read -ra query_pairs <<< "$query"
    for pair in "${query_pairs[@]}"; do
        param_name="${pair%%=*}"
        param_value="${pair#*=}"
        if [ "$param_name" = "$key" ]; then
            url_decode "$param_value"
            return 0
        fi
    done

    return 1
}

is_vless_ws_tls_argo() {
    local url="$1"
    local security transport host sni

    [[ "$url" == vless://* ]] || return 1
    security="$(get_vless_query_param "$url" "security")"
    transport="$(get_vless_query_param "$url" "type")"
    host="$(get_vless_query_param "$url" "host")"
    sni="$(get_vless_query_param "$url" "sni")"

    [ "$security" = "tls" ] || return 1
    [ "$transport" = "ws" ] || return 1
    [ -n "$host" ] || [ -n "$sni" ]
}

show_source_templates() {
    local found=0 line

    load_source_urls || return 1
    [ ${#urls[@]} -gt 0 ] || return 1
    echo -e "${GREEN}=== Sing-box 已创建的 VLESS-WS-TLS-Argo 模板节点 ===${NC}"

    for line in "${urls[@]}"; do
        [ -z "$line" ] && continue
        if is_vless_ws_tls_argo "$line"; then
            echo "$line"
            found=1
        fi
    done

    [ "$found" -eq 1 ]
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

probe_vless_edge_candidate() {
    local original_url="$1"
    local edge_address="$2"
    local host sni path port tls_host request_host resolve_address result status
    local attempts="${CFY_HEALTH_PROBE_ATTEMPTS:-2}"
    local minimum_success="${CFY_HEALTH_MIN_SUCCESS:-2}"
    local success_count=0 attempt

    [[ "$attempts" =~ ^[1-9][0-9]*$ ]] || attempts=2
    [[ "$minimum_success" =~ ^[1-9][0-9]*$ ]] || minimum_success=$attempts
    [ "$minimum_success" -le "$attempts" ] || minimum_success=$attempts

    host=$(get_vless_query_param "$original_url" "host" || true)
    sni=$(get_vless_query_param "$original_url" "sni" || true)
    path=$(get_vless_query_param "$original_url" "path" || true)
    port=$(extract_vless_port "$original_url")
    tls_host="${sni:-$host}"
    request_host="${host:-$tls_host}"
    [ -n "$tls_host" ] && [ -n "$request_host" ] || return 1
    [ -n "$path" ] || path="/"

    normalize_edge_input "$edge_address" "$port"
    resolve_address="$EDGE_HOST"
    if is_ipv6_edge "$EDGE_HOST"; then
        resolve_address="[$EDGE_HOST]"
    fi

    for ((attempt=1; attempt<=attempts; attempt++)); do
        result=$(curl --http1.1 --silent --output /dev/null \
            --connect-timeout "${CFY_HEALTH_CONNECT_TIMEOUT:-3}" \
            --max-time "${CFY_HEALTH_MAX_TIME:-5}" \
            --resolve "${tls_host}:${EDGE_PORT}:${resolve_address}" \
            --header "Host: ${request_host}" \
            --write-out '%{http_code}|%{time_starttransfer}' \
            "https://${tls_host}:${EDGE_PORT}${path}" 2>/dev/null || true)
        status="${result%%|*}"
        if [ "$status" = "400" ]; then
            success_count=$((success_count + 1))
        fi
    done

    [ "$success_count" -ge "$minimum_success" ]
}

update_vless_url() {
    local original_url="$1"
    local new_add="$2"
    local new_ps="$3"
    local port endpoint prefix rest suffix updated encoded_ps

    port=$(extract_vless_port "$original_url")
    encoded_ps=$(url_encode_fragment "$new_ps")
    normalize_edge_input "$new_add" "$port"
    endpoint=$(format_host_port "$EDGE_HOST" "$EDGE_PORT")
    prefix="${original_url%%@*}@"
    rest="${original_url#*@}"
    suffix="?${rest#*\?}"
    updated="${prefix}${endpoint}${suffix}"

    if [[ "$updated" == *"#"* ]]; then
        updated="${updated%%#*}#${encoded_ps}"
    else
        updated="${updated}#${encoded_ps}"
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
        is_vless_ws_tls_argo "$url" || continue
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

finalize_generated_urls() {
    local generated_count="${1:-0}"
    local publish_status

    save_generated_urls
    publish_status=$?
    if [ "$publish_status" -ne 0 ]; then
        echo -e "${RED}订阅发布失败；未更新成功结果。${NC}" >&2
        return "$publish_status"
    fi
    echo "---"
    echo -e "${GREEN}共 ${generated_count} 个链接已生成完毕.${NC}"
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

    load_source_urls
    local load_status=$?
    if [ "$load_status" -ne 0 ]; then
        echo -e "${RED}读取 Sing-box 模板失败；订阅锁不可用或超时。${NC}" >&2
        return "$load_status"
    fi
    if [ ${#urls[@]} -gt 0 ]; then
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
        echo -e "${YELLOW}在 Sing-box 节点来源中未找到可用于优选的 VLESS-WS-TLS 或 VMess 模板.${NC}"
        show_template_sources_hint
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

    local ip_source_choice; local use_optimized_ips=false; local IP_VERSION_SCOPE="ipv4"
    while true; do
        read -p "请输入选项编号 (1-2): " ip_source_choice
        if [[ "$ip_source_choice" == "1" ]]; then break;
        elif [[ "$ip_source_choice" == "2" ]]; then use_optimized_ips=true; break;
        else echo -e "${RED}无效的输入, 请重试.${NC}"; fi
    done

    declare -a ip_list isp_list; local num_to_generate=0
    if $use_optimized_ips; then
        choose_ip_version_scope
        get_all_optimized_ips || exit 1
        num_to_generate=0
    else
        echo -e "${YELLOW}正在从 Cloudflare 官网获取 IPv4 地址列表...${NC}"
        cloudflare_ips=$(curl -fsSL --connect-timeout "$CFY_CURL_CONNECT_TIMEOUT" --max-time "$CFY_CURL_MAX_TIME" https://www.cloudflare.com/ips-v4 2>/dev/null || true)
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
        local name_prefix="${CFY_NAME_PREFIX:-$(get_name_prefix "$original_ps")}"
        declare -A name_counts

        for ((i=0; i<${#ip_list[@]}; i++)); do
            local current_ip=${ip_list[$i]}; local isp_name=${isp_list[$i]}
            local isp_group ip_version name_key new_ps generated_url

            ip_version=$(get_edge_ip_version "$current_ip")
            if ! should_include_ip_version "$ip_version"; then
                continue
            fi

            isp_group=$(normalize_isp_group "$isp_name" || true)
            name_key="${isp_group:-generic}-${ip_version}"
            name_counts[$name_key]=$(( ${name_counts[$name_key]:-0} + 1 ))
            if [ -n "$isp_group" ]; then
                local new_ps="${name_prefix}-${isp_group}-${ip_version}-${name_counts[$name_key]}"
            else
                local new_ps="${name_prefix}-${ip_version}-${name_counts[$name_key]}"
            fi
            if [ "$selected_type" = "vless" ]; then
                if [ "$CFY_HEALTH_PROBE" != "0" ] && ! probe_vless_edge_candidate "$selected_url" "$current_ip"; then
                    echo -e "${YELLOW}Skipping unhealthy edge candidate: ${current_ip}${NC}" >&2
                    continue
                fi
                generated_url=$(update_vless_url "$selected_url" "$current_ip" "$new_ps")
            else
                generated_url=$(update_vmess_url "$original_json" "$current_ip" "$new_ps")
            fi
            echo "$generated_url"
            generated_urls+=("$generated_url")
            num_to_generate=$((num_to_generate + 1))
        done

        if [ "$num_to_generate" -eq 0 ]; then
            echo -e "${RED}未找到符合 IPv4/IPv6 条件的优选入口.${NC}"
            exit 1
        fi
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
    finalize_generated_urls "$num_to_generate" || return $?
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
    --update|--upgrade)
        update_self
        exit 0
        ;;
esac

check_deps
main
