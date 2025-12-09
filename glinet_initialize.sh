#!/bin/sh

# --- 日志函数 (OpenWrt 兼容) ---
log() { printf "\033[32m[%s]\033[0m %s\n" "$(date +'%Y-%m-%d %H:%M:%S')" "$1"; }
err() { printf "\033[31m[%s] ERROR: %s\033[0m\n" "$(date +'%Y-%m-%d %H:%M:%S')" "$1"; }

# --- 变量配置 ---
MENU_DIR="/usr/share/oui/menu.d"
DOCKER_PKGS="docker dockerd docker-compose luci-app-dockerman luci-i18n-dockerman-zh-cn"
# OPENCLASH_PKG 变量不再直接使用，改为动态获取

# 第三方源配置
EXPECTED_FEEDS="src/gz custombase http://glinet.83970255.xyz/?f=/mt798x-openwrt21/base
src/gz custompackages http://glinet.83970255.xyz/?f=/mt798x-openwrt21/packages
src/gz customluci http://glinet.83970255.xyz/?f=/mt798x-openwrt21/luci"

# --- 核心功能区 ---

# 功能3: 解锁AdGuardHome (原初始化菜单)
# 作用: 修复简体中文环境下部分菜单(如AdGuard Home)不显示的问题
init_menu() {
    log "[+] 开始执行系统菜单初始化..."
    [ ! -d "$MENU_DIR" ] && { err "目录不存在"; return; }

    # 1. 尝试创建备份
    log "[+] 正在备份配置文件..."
    cp -r "$MENU_DIR" "${MENU_DIR}_bak_$(date +%s)" 2>/dev/null

    # 2. 执行配置修正
    log "[+] 优化菜单配置..."
    # 使用 find 配合 sed 将 lang_hide 限制中的 zh-cn 替换为 zh-tw 以绕过前端判断
    find "$MENU_DIR" -type f -name "*.json" -exec sed -i '/"lang_hide"/{n;s/"zh-cn"/"zh-tw"/;}' {} +

    log "[✓] 菜单初始化完成！请刷新浏览器 (建议 Ctrl+F5)"
}

# 功能4: 还原CN (还原配置)
restore_config() {
    log "[+] 正在还原配置..."

    # 1. 优先尝试从自动备份恢复
    LATEST_BAK=$(ls -d ${MENU_DIR}_bak_* 2>/dev/null | tail -n 1)
    if [ -n "$LATEST_BAK" ] && [ -d "$LATEST_BAK" ]; then
        cp -r "$LATEST_BAK"/* "$MENU_DIR/"
        log "[✓] 已从备份文件还原"
    else
        # 2. 如果没备份(比如手动修改过)，执行逆向命令
        log "[!] 未找到备份，正在尝试重置配置..."
        find "$MENU_DIR" -type f -name "*.json" -exec sed -i '/"lang_hide"/{n;s/"zh-tw"/"zh-cn"/;}' {} +
        log "[✓] 配置已重置为默认状态"
    fi
}

# 功能2: 部署 Docker 环境
install_docker() {
    log "[+] 初始化 Docker 环境..."

    # 1. 配置软件源
    mkdir -p /etc/opkg
    echo "$EXPECTED_FEEDS" > /etc/opkg/customfeeds.conf

    # 2. 更新列表
    log "[+] 更新软件包列表..."
    opkg update

    # 3. 补充必备依赖
    log "[+] 检查依赖..."
    for pkg in luci-lib-ipkg luci-compat; do
        opkg list-installed | grep -q "^$pkg " || opkg install $pkg
    done

    # 4. 安装 Docker 套件
    if opkg install $DOCKER_PKGS; then
        log "[✓] Docker 环境部署成功"
    else
        log "[!] 安装遇到问题，尝试自动修复依赖..."
        opkg install $DOCKER_PKGS --force-depends
    fi
}

# 功能1: 安装 OpenClash (三级容灾版)
install_openclash() {
    log "[+] 准备安装 OpenClash..."

    mkdir -p /etc/opkg
    echo "$EXPECTED_FEEDS" > /etc/opkg/customfeeds.conf

    log "[+] 更新软件包列表 (用于处理依赖)..."
    opkg update

    # === 阶段一：获取下载地址 (三级策略) ===
    log "[+] 正在获取最新版本信息..."
    API_URL="https://api.github.com/repos/vernesong/OpenClash/releases/latest"
    ORIGIN_URL=""

    # 策略A: 官方 API (3秒极速超时，不行就撤)
    ORIGIN_URL=$(wget -T 3 -qO- "$API_URL" 2>/dev/null | grep -o 'https://[^"]*luci-app-openclash[^"]*\.ipk' | head -n 1)

    # 策略B: 镜像页面爬取 (如果 API 挂了，爬取 HTML 页面)
    if [ -z "$ORIGIN_URL" ]; then
        log "[!] 官方 API 连接超时，切换至镜像页面抓取..."
        MIRROR_PAGE="https://mirror.ghproxy.com/https://github.com/vernesong/OpenClash/releases/latest"
        # 抓取相对路径
        REL_PATH=$(wget -T 10 -qO- "$MIRROR_PAGE" 2>/dev/null | grep -o '/vernesong/OpenClash/releases/download/[^"]*\.ipk' | head -n 1)

        if [ -n "$REL_PATH" ]; then
            ORIGIN_URL="https://github.com${REL_PATH}"
            log "[✓] 已通过镜像页面成功获取版本信息"
        fi
    fi

    DOWNLOAD_URL=""

    if [ -n "$ORIGIN_URL" ]; then
        # 自动获取成功，添加加速前缀
        DOWNLOAD_URL="https://mirror.ghproxy.com/$ORIGIN_URL"
        log "[+] 发现最新版: $(basename "$ORIGIN_URL")"
    else
        # 策略C: 最终兜底 (手动输入)
        err "自动获取版本失败！(官方API和镜像源均无法访问)"
        printf "请手动粘贴 OpenClash 的下载链接 (.ipk): "
        # 强制从终端读取
        read -r MANUAL_URL < /dev/tty

        if [ -n "$MANUAL_URL" ]; then
            DOWNLOAD_URL="$MANUAL_URL"
            log "[+] 使用手动提供的链接..."
        else
            err "未输入链接，操作取消"
            return
        fi
    fi
    # ==========================================

    # === 阶段二：直接安装 (OPKG 直连) ===
    log "[+] 正在通过 URL 直接安装..."
    log "    源: $DOWNLOAD_URL"

    # 直接使用 opkg install URL，省去下载到本地的步骤
    if opkg install "$DOWNLOAD_URL"; then
        log "[✓] OpenClash 安装成功！请刷新后台查看"
    else
        log "[!] 安装失败或依赖报错，尝试强制修复..."
        opkg install "$DOWNLOAD_URL" --force-depends
    fi
}

# 工具: 通过 URL 安装 IPK
install_ipk_url() {
    [ -z "$1" ] && { err "请提供下载链接"; return; }
    log "[+] 开始直接安装: $1"
    opkg install "$1" || log "[!] 安装失败，请检查 URL 或依赖"
}

# --- 主菜单 ---
while :; do
    echo
    echo "========================"
    echo "   GL.iNet 一键初始化"
    echo " 1. 安装OpenClash"
    echo " 2. 部署 Docker 环境"
    echo " 3. 解锁AdGuardHome"
    echo " 4. 还原CN"
    echo " 5. 退出"
    echo "========================"
    printf "请输入选项 [1-5]: "

    if ! read -r c < /dev/tty 2>/dev/null; then read -r c; fi
    [ -z "$c" ] && exit 0

    case $c in
        1) install_openclash ;;
        2) install_docker ;;
        3) init_menu ;;
        4) restore_config ;;
        5) exit 0 ;;
        *) err "无效选项" ;;
    esac
done
