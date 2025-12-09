#!/bin/sh

# --- 日志函数 ---
log() { printf "\033[32m[%s]\033[0m %s\n" "$(date +'%Y-%m-%d %H:%M:%S')" "$1"; }
err() { printf "\033[31m[%s] ERROR: %s\033[0m\n" "$(date +'%Y-%m-%d %H:%M:%S')" "$1"; }

# --- 变量配置 ---
MENU_DIR="/usr/share/oui/menu.d"
DOCKER_PKGS="docker dockerd docker-compose luci-app-dockerman luci-i18n-dockerman-zh-cn"
EXPECTED_FEEDS="src/gz custombase http://glinet.83970255.xyz/?f=/mt798x-openwrt21/base
src/gz custompackages http://glinet.83970255.xyz/?f=/mt798x-openwrt21/packages
src/gz customluci http://glinet.83970255.xyz/?f=/mt798x-openwrt21/luci"

# --- 核心功能区 ---

unlock_hidden() {
    log "[+] 解锁隐藏功能 (AdGuard Home 等)..."
    [ ! -d "$MENU_DIR" ] && { err "目录不存在"; return; }

    # 1. 尝试创建备份
    log "[+] 创建备份..."
    cp -r "$MENU_DIR" "${MENU_DIR}_bak_$(date +%s)" 2>/dev/null

    # 2. 执行解锁 (原版命令)
    log "[+] 修改配置..."
    find "$MENU_DIR" -type f -name "*.json" -exec sed -i '/"lang_hide"/{n;s/"zh-cn"/"zh-tw"/;}' {} +

    log "[✓] 解锁完毕！请刷新浏览器"
}

restore_hidden() {
    log "[+] 正在还原..."

    # 1. 优先尝试从备份恢复
    LATEST_BAK=$(ls -d ${MENU_DIR}_bak_* 2>/dev/null | tail -n 1)
    if [ -n "$LATEST_BAK" ] && [ -d "$LATEST_BAK" ]; then
        cp -r "$LATEST_BAK"/* "$MENU_DIR/"
        log "[✓] 已从备份文件还原"
    else
        # 2. 如果没备份(手动解锁的情况)，执行逆向命令
        log "[!] 未找到备份，尝试使用逆向命令强制还原..."
        find "$MENU_DIR" -type f -name "*.json" -exec sed -i '/"lang_hide"/{n;s/"zh-tw"/"zh-cn"/;}' {} +
        log "[✓] 已通过逆向修改还原配置"
    fi
}

install_docker() {
    log "[+] 安装 Docker..."
    mkdir -p /etc/opkg
    echo "$EXPECTED_FEEDS" > /etc/opkg/customfeeds.conf
    opkg update

    for pkg in luci-lib-ipkg luci-compat; do
        opkg list-installed | grep -q "^$pkg " || opkg install $pkg
    done

    if opkg install $DOCKER_PKGS; then
        log "[✓] Docker 安装成功"
    else
        log "[!] 尝试强制修复安装..."
        opkg install $DOCKER_PKGS --force-depends
    fi
}

# --- 主菜单 ---
while :; do
    echo
    echo "========================"
    echo "   GL.iNet 简易配置"
    echo " 1. 解锁隐藏功能"
    echo " 2. 安装 Docker"
    echo " 3. 还原配置 (支持无备份还原)"
    echo " 4. 退出"
    echo "========================"
    printf "请输入选项 [1-4]: "

    if ! read -r c < /dev/tty 2>/dev/null; then read -r c; fi
    [ -z "$c" ] && exit 0

    case $c in
        1) unlock_hidden ;;
        2) install_docker ;;
        3) restore_hidden ;;
        4) exit 0 ;;
        *) err "无效选项" ;;
    esac
done
