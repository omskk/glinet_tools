#!/bin/sh

log() { echo "[$(date +'%Y-%m-%d %H:%M:%S')] $1"; }

EXPECTED_FEEDS='src/gz custombase http://glinet.83970255.xyz/?f=/mt798x-openwrt21/base
src/gz custompackages http://glinet.83970255.xyz/?f=/mt798x-openwrt21/packages
src/gz customluci http://glinet.83970255.xyz/?f=/mt798x-openwrt21/luci'
MENU_DIR="/usr/share/oui/menu.d"
DOCKER_PKGS="docker dockerd docker-compose luci-app-dockerman luci-i18n-dockerman-zh-cn"

# --- 启动：配置基础环境 ---
log "[+] 配置软件源"
mkdir -p /etc/opkg
echo "$EXPECTED_FEEDS" | cmp -s /etc/opkg/customfeeds.conf 2>/dev/null || {
    echo "$EXPECTED_FEEDS" > /etc/opkg/customfeeds.conf
    log "[✓] 软件源配置完成"
}

log "[+] 更新软件包列表"
opkg update || { log "[-] 更新失败"; exit 1; }

log "[+] 检查必备包：luci-lib-ipkg luci-compat"
missing=""
for pkg in luci-lib-ipkg luci-compat; do
    opkg list-installed | grep -q "^$pkg " || missing="$missing $pkg"
done
[ -n "$missing" ] && { opkg install $missing || exit 1; log "[✓] 必备包已安装"; }

# --- 核心功能 ---
unlock_hidden() {
    log "[+] 解锁隐藏功能：绕过 lang_hide 限制"
    [ -d "$MENU_DIR" ] || { log "[-] 菜单目录不存在"; return; }
    files=$(find "$MENU_DIR" -type f -name "*.json" -exec grep -l '"lang_hide"' {} \; 2>/dev/null)
    [ -z "$files" ] && { log "[+] 无隐藏功能项"; return; }
    for f in $files; do
        bak="$f.bak"
        [ ! -f "$bak" ] && cp "$f" "$bak" && log "  备份: ${f##*/}"
        if grep -q '"lang_hide".*"zh-cn"' "$f"; then
            sed -i '/"lang_hide"/{n;s/"zh-cn"/"zh-tw"/;}' "$f"
            log "  解锁: ${f##*/}"
        fi
    done
    log "[✓] 隐藏功能已解锁"
}

restore_hidden() {
    log "[+] 还原隐藏功能：恢复原始菜单"
    [ -d "$MENU_DIR" ] || { log "[-] 菜单目录不存在"; return; }
    baks=$(find "$MENU_DIR" -type f -name "*.json.bak" 2>/dev/null)
    [ -z "$baks" ] && { log "[+] 无备份，跳过"; return; }
    for b in $baks; do
        cp "$b" "${b%.bak}" && log "  还原: ${b##*/}"
    done
    log "[✓] 已恢复隐藏状态"
}

install_docker() {
    log "[+] 安装 Docker 套件"
    opkg install $DOCKER_PKGS && log "[✓] Docker 安装成功" || log "[-] 部分失败"
}

# --- 主菜单 ---
while :; do
    cat <<EOF

=== GL.iNet 配置助手 ===
1) 安装 Docker 套件
2) 解锁隐藏功能（自动备份）
3) 还原隐藏功能
4) 刷新软件源
5) 全部执行（解锁 + Docker）
6) 退出
========================
EOF
    printf "请选择 [1-6]: "; read -r c
    case $c in
        1) install_docker ;;
        2) unlock_hidden ;;
        3) restore_hidden ;;
        4) opkg update && log "[✓] 源已刷新" ;;
        5) unlock_hidden; install_docker; log "[✓] 全部执行完成" ;;
        6) log "[+] 退出脚本"; exit ;;
        *) log "[-] 无效选项" ;;
    esac
done
