#!/bin/bash
#
# ┌─────────────────────────────────────────────────┐
# │   scrcpy 一键投屏  —  macOS 版                   │
# │   由 Windows「一键启动投屏.bat」改造              │
# └─────────────────────────────────────────────────┘
#
# 用法:
#   方式一:  双击「一键启动投屏.command」文件
#   方式二:  终端执行  ./一键启动投屏.command
#
# 功能:
#   • 自动检测已连接的 USB 设备
#   • 记住并探测历史 WiFi IP，在线设备优先显示
#   • 输入数字 = 选序号; 输入 IP 地址 = 直接连
#
# ─── 可调参数 ───────────────────────────────────
MAX_SIZE=1280
VIDEO_BIT_RATE=4M
MAX_FPS=30
MAX_HISTORY=10

# ─── 内部路径 ───────────────────────────────────
HISTORY_FILE="$HOME/.scrcpy_hosts"

# ─── 颜色 ───────────────────────────────────────
RED='\033[0;31m'
GRN='\033[0;32m'
YEL='\033[0;33m'
CYN='\033[0;36m'
BLD='\033[1m'
DIM='\033[2m'
RST='\033[0m'

# ─── 菜单数组 ───────────────────────────────────
m_dev=()
m_type=()
WIFI_TARGET=""

# ═════════════════════════════════════════════════
#  函数
# ═════════════════════════════════════════════════

check_deps() {
    local missing=""
    command -v adb    >/dev/null 2>&1 || missing="$missing adb"
    command -v scrcpy >/dev/null 2>&1 || missing="$missing scrcpy"
    if [ -n "$missing" ]; then
        echo -e "  ${RED}✗ 缺少工具:$missing${RST}"
        echo    "  请用 Homebrew 安装:"
        echo -e "    ${BLD}brew install scrcpy android-platform-tools${RST}"
        exit 1
    fi
}

# 判断是否为 IP 地址 (包含 . 或 : 即视为 IP)
is_ip() {
    [[ "$1" == *.* || "$1" == *:* ]]
}

load_history() {
    [ -f "$HISTORY_FILE" ] && cat "$HISTORY_FILE" || true
}

# 将 IP 写入历史 (去重、置顶、限量)
save_history() {
    local ip="$1"
    touch "$HISTORY_FILE"
    local rest
    rest=$(grep -vxF "$ip" "$HISTORY_FILE" 2>/dev/null || true)
    printf '%s\n' "$ip" > "$HISTORY_FILE"
    [ -n "$rest" ] && printf '%s\n' "$rest" >> "$HISTORY_FILE"
    head -n "$MAX_HISTORY" "$HISTORY_FILE" > "${HISTORY_FILE}.tmp" \
        && mv "${HISTORY_FILE}.tmp" "$HISTORY_FILE"
}

# 只探测 ADB TCP 服务，不建立 ADB 连接
is_history_online() {
    nc -z -G 1 "$1" 5555 >/dev/null 2>&1
}

# 扫描设备，填充菜单数组
scan() {
    m_dev=()
    m_type=()
    local seen_ips=" "
    adb start-server >/dev/null 2>&1
    # ── 当前已连接设备 (USB + WiFi) ──
    while IFS=$'\t' read -r dev state _rest; do
        [ -z "$dev" ] && continue
        [ "$state" != "device" ] && continue
        if [[ "$dev" == *:* ]]; then
            seen_ips="$seen_ips${dev%%:*} "
            m_dev+=("$dev"); m_type+=("wifi-on")
        else
            m_dev+=("$dev"); m_type+=("usb")
        fi
    done < <(adb devices 2>/dev/null | tail -n +2)
    # ── 历史 IP (尚未连接的，并行探测、在线优先) ──
    local history_ips=() offline_ips=() probe_pids=() ip i
    while IFS= read -r ip; do
        [ -z "$ip" ] && continue
        [[ "$seen_ips" == *" $ip "* ]] && continue
        history_ips+=("$ip")
    done < <(load_history)

    local probe_dir
    probe_dir=$(mktemp -d "${TMPDIR:-/tmp}/scrcpy-probe.XXXXXX") || return 1
    for ((i = 0; i < ${#history_ips[@]}; i++)); do
        (is_history_online "${history_ips[$i]}" && : > "$probe_dir/$i") &
        probe_pids+=("$!")
    done
    for i in "${probe_pids[@]}"; do
        wait "$i" 2>/dev/null || true
    done
    for ((i = 0; i < ${#history_ips[@]}; i++)); do
        ip="${history_ips[$i]}"
        if [ -f "$probe_dir/$i" ]; then
            m_dev+=("$ip"); m_type+=("wifi-ready")
        else
            offline_ips+=("$ip")
        fi
        rm -f "$probe_dir/$i"
    done
    rmdir "$probe_dir" 2>/dev/null || true
    for ip in "${offline_ips[@]}"; do
        m_dev+=("$ip"); m_type+=("wifi-hist")
    done
}

# WiFi 连接; 成功时设置 WIFI_TARGET
wifi_connect() {
    local target="$1"

    # 5555 是 adb connect 的默认端口，不需要主动拼接。
    # 用户即使输入了 :5555，也只向 adb 传递纯 IP。
    target="${target%:5555}"

    echo -e "  ${CYN}连接中 ${target} …${RST}"
    adb connect "$target" 2>&1 | sed 's/^/    /'

    # 首次连接后 adbd 可能需要数秒才从 offline 变为 device。
    local device_serial="" attempt
    for ((attempt = 1; attempt <= 10; attempt++)); do
        device_serial=$(adb devices 2>/dev/null | awk -v t="$target" \
            '$2=="device" && ($1==t || $1==t ":5555") { print $1; exit }')
        if [ -n "$device_serial" ]; then
            break
        fi
        sleep 0.5
    done

    if [ -n "$device_serial" ]; then
        echo -e "  ${GRN}✓ WiFi 连接成功${RST}"
        save_history "$target"
        echo -e "  ${DIM}(已记住此 IP，下次可直接选择)${RST}"
        WIFI_TARGET="$device_serial"
        return 0
    else
        echo -e "  ${RED}✗ 连接失败${RST}"
        return 1
    fi
}

# ═════════════════════════════════════════════════
#  主流程
# ═════════════════════════════════════════════════

main() {
    export LANG="${LANG:-en_US.UTF-8}"
    check_deps
    echo ""
    echo -e "  ${BLD}╔══════════════════════════════════════╗${RST}"
    echo -e "  ${BLD}║     scrcpy 一键投屏  ·  macOS        ║${RST}"
    echo -e "  ${BLD}║     WiFi 无线 / USB 有线              ║${RST}"
    echo -e "  ${BLD}╚══════════════════════════════════════╝${RST}"
    echo ""
    scan
    local count=${#m_dev[@]}
    # ── 显示设备列表 ──
    echo -e "  ${YEL}[步骤 1/2] 选择设备${RST}"
    echo ""
    if [ "$count" -eq 0 ]; then
        echo -e "  ${DIM}(暂无已连接设备，也无历史记录)${RST}"
        echo -e "  直接输入 IP 地址即可连接，例如 ${CYN}192.168.1.100${RST}"
    else
        local i
        for ((i = 0; i < count; i++)); do
            local n=$((i + 1))
            case "${m_type[$i]}" in
                usb)
                    printf "  ${BLD}%2d${RST}) ${GRN}[USB]${RST}  %s\n" "$n" "${m_dev[$i]}" ;;
                wifi-on)
                    printf "  ${BLD}%2d${RST}) ${GRN}[WiFi]${RST} %s ${DIM}(已连接)${RST}\n" "$n" "${m_dev[$i]}" ;;
                wifi-ready)
                    printf "  ${BLD}%2d${RST}) ${GRN}[WiFi]${RST} %s ${GRN}(在线)${RST}\n" "$n" "${m_dev[$i]}" ;;
                wifi-hist)
                    printf "  ${BLD}%2d${RST}) ${CYN}[WiFi]${RST} %s ${DIM}(历史·离线)${RST}\n" "$n" "${m_dev[$i]}" ;;
            esac
        done
    fi
    echo ""
    # ── 读取用户输入 ──
    echo -ne "  ${CYN}请输入序号或 IP 地址${RST} ${DIM}(回车取消)${CYN}: ${RST}"
    local input
    if ! read -r input; then
        echo ""
        echo -e "  ${DIM}已取消${RST}"
        exit 0
    fi
    echo ""
    # 去除首尾空白
    input="${input#"${input%%[![:space:]]*}"}"
    input="${input%"${input##*[![:space:]]}"}"
    [ -z "$input" ] && { echo -e "  ${DIM}已取消${RST}"; exit 0; }
    # ── 解析输入: IP 地址 or 序号 ──
    local target="" action=""
    if is_ip "$input"; then
        target="$input"; action="wifi-new"
    elif [[ "$input" =~ ^[0-9]+$ ]]; then
        if [ "$input" -ge 1 ] 2>/dev/null && [ "$input" -le "$count" ]; then
            target="${m_dev[$((input - 1))]}"
            action="${m_type[$((input - 1))]}"
        else
            echo -e "  ${RED}序号超出范围: $input${RST}"
            [ "$count" -gt 0 ] && echo -e "  ${DIM}有效范围 1 – ${count}${RST}"
            exit 1
        fi
    else
        echo -e "  ${RED}无法识别: '$input'${RST}"
        echo -e "  ${DIM}请输入序号 (1, 2 …) 或 IP 地址 (192.168.x.x)${RST}"
        exit 1
    fi
    # ── 建立连接 ──
    case "$action" in
        usb)
            echo -e "  ${GRN}✓ USB 设备就绪: ${target}${RST}" ;;
        wifi-on)
            echo -e "  ${GRN}✓ 设备已连接: ${target}${RST}"
            save_history "${target%%:*}" ;;
        wifi-new|wifi-ready|wifi-hist)
            wifi_connect "$target" || {
                echo ""
                echo -e "  ${RED}设备连接失败${RST}"
                echo -e "  ${DIM}请确认:${RST}"
                echo -e "  ${DIM}  · 手机与电脑在同一 WiFi 局域网${RST}"
                echo -e "  ${DIM}  · 手机已开启无线调试 (端口 5555)${RST}"
                exit 1
            }
            target="$WIFI_TARGET" ;;
    esac
    # ── 启动 scrcpy ──
    echo ""
    echo -e "  ${YEL}[步骤 2/2] 启动 scrcpy 投屏${RST}"
    echo -e "  ${DIM}设备 ${target} · 分辨率 ${MAX_SIZE} · 码率 ${VIDEO_BIT_RATE} · 帧率 ${MAX_FPS}${RST}"
    echo -e "  ${DIM}(关闭窗口或按 Ctrl+C 可断开投屏)${RST}"
    echo ""
    exec scrcpy -s "$target" \
        --max-size "$MAX_SIZE" \
        --video-bit-rate "$VIDEO_BIT_RATE" \
        --max-fps "$MAX_FPS" \
        --stay-awake
}

main "$@"
