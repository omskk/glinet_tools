#!/bin/sh

# --- 1. 日志配置 (使用 printf 修复 OpenWrt 颜色兼容性) ---
log() {
    printf "\033[32m[%s]\033[0m %s\n" "$(date +'%Y-%m-%d %H:%M:%S')" "$1"
}

err() {
    printf "\033[31m[%s] ERROR: %s\033[0m\n" "$(date +'%Y-%m-%d %H:%M:%S')" "$1"
}

# --- 2. 核心变量配置 ---
EXPECTED_FEEDS="src/gz custombase http://glinet.83970255.xyz/?f=/mt798x-openwrt21/base
src/gz custompackages http://glinet.83970255.xyz/?f=/mt798x-openwrt21/packages
src/gz customluci http://glinet.83970255.xyz/?f=/mt798x-openwrt21/luci"

MENU_DIR="/usr/share/oui/menu.d"
DOCKER_PKGS="docker dockerd docker-compose luci-app-dockerman luci-i18n-dockerman-zh-cn"
FEED_FILE="/etc/opkg/customfeeds.conf"

# --- 3. 环境初始化 ---
log "[+] 开始环境检查..."

# 3.1 配置软件源
mkdir -p /etc/opkg
if [ -f "$FEED_FILE" ] && [ "$(cat "$FEED_FILE")" = "$EXPECTED_FEEDS" ]; then
    log "[✓] 软件源配置一致，跳过写入"
else
    echo "$EXPECTED_FEEDS" > "$FEED_FILE"
    log "[+] 软件源已更新"
fi

# 3.2 更新列表 (失败仅警告，不退出)
log "[+] 更新软件包列表..."
if opkg update; then
    log "[✓] 列表更新成功"
else
    err "列表更新失败，请检查网络。脚本将继续尝试运行..."
fi

# 3.3 检查必备依赖
log "[+] 检查必备依赖: luci-lib-ipkg luci-compat"
MISSING_PKGS=""
for pkg in luci-lib-ipkg luci-compat; do
    if ! opkg list-installed | grep -q "^$pkg "; then
        MISSING_PKGS="$MISSING_PKGS $pkg"
    fi
done

if [ -n "$MISSING_PKGS" ]; then
    log "[+] 安装缺失依赖: $MISSING_PKGS"
    opkg install $MISSING_PKGS || err "依赖安装失败，后续 Docker 安装可能会出错"
else
    log "[✓] 必备依赖已安装"
fi

# --- 4. 功能函数 ---

unlock_hidden() {
    log "[+] 正在解锁隐藏功能 (AdGuard Home 等)..."
    [ ! -d "$MENU_DIR" ] && { err "菜单目录 $MENU_DIR 不存在"; return; }

    # 查找包含 lang_hide 的文件
    files=$(grep -l '"lang_hide"' "$MENU_DIR"/*.json 2>/dev/null)

    if [ -z "$files" ]; then
        log "[!] 未找到含有隐藏限制的文件 (可能已解锁或固件版本不同)"
        return
    fi

    for f in $files; do
        bak="$f.bak"
        # 仅当备份不存在时备份
        [ ! -f "$bak" ] && cp "$f" "$bak" && log "  备份: ${f##*/}"

        # 核心逻辑：修改 zh-cn 为 zh-tw 以绕过简体中文隐藏限制
        if grep -q '"lang_hide".*"zh-cn"' "$f"; then
            sed -i '/"lang_hide"/s/"zh-cn"/"zh-tw"/' "$f"
            log "  解锁 (单行): ${f##*/}"
        elif grep -q '"lang_hide"' "$f"; then
            sed -i '/"lang_hide"/{n;s/"zh-cn"/"zh-tw"/;}' "$f"
            log "  解锁 (多行): ${f##*/}"
        fi
    done
    log "[✓] 隐藏菜单已解锁，请刷新浏览器页面查看"
}

restore_hidden() {
    log "[+] 还原隐藏功能：恢复原始菜单"
    [ ! -d "$MENU_DIR" ] && { err "菜单目录不存在"; return; }

    baks=$(find "$MENU_DIR" -type f -name "*.json.bak" 2>/dev/null)
    [ -z "$baks" ] && { log "[!] 无备份文件，跳过还原"; return; }

    for b in $baks; do
        target="${b%.bak}"
        cp "$b" "$target" && rm "$b" && log "  还原并删除备份: ${b##*/}"
    done
    log "[✓] 已恢复初始状态"
}

install_docker() {
    log "[+] 开始安装 Docker 套件..."
    if opkg install $DOCKER_PKGS; then
        log "[✓] Docker 安装成功！"
    else
        err "Docker 安装部分失败，尝试修复依赖..."
        opkg install $DOCKER_PKGS --force-depends
    fi
}

# --- 5. 主菜单 (修复无限循环 Bug) ---
while :; do
    echo
    echo "========================"
    echo "   GL.iNet 配置助手"
    echo "========================"
    echo " 1. 安装 Docker 套件"
    echo " 2. 解锁AdGuard Home等隐藏功能"
    echo " 3. 还原隐藏功能"
    echo " 4. 强制刷新软件源"
    echo " 5. 一键全套 (解锁 + Docker)"
    echo " 6. 退出"
    echo "========================"
    printf "请输入选项 [1-6]: "

    # === 关键修复：强制从 /dev/tty 读取输入，解决管道运行时的死循环 ===
    if [ -c /dev/tty ]; then
        read -r c < /dev/tty
    else
        read -r c
    fi
    # ============================================================

    case $c in
        1) install_docker ;;
        2) unlock_hidden ;;
        3) restore_hidden ;;
        4) opkg update && log "[✓] 源已刷新" ;;
        5) unlock_hidden; install_docker; log "[✓] 全部执行完成" ;;
        6) log "退出脚本"; exit 0 ;;
        *) err "无效选项，请重试" ;;
    esac
done
