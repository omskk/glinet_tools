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

# 功能1: 安装 OpenClash
install_openclash() {
    log "[+] 获取最新 OpenClash 版本号..."

    # 定义基础 URL 和默认代理
    GH_URL="https://github.com/vernesong/OpenClash/releases/latest"
    PROXY_PREFIX="https://cdn.gh-proxy.org/"
    VERSION=""

    # 1. 尝试直接获取
    HTML=$(uclient-fetch -qO- "$GH_URL" 2>/dev/null)

    # 2. 如果直接获取失败，提供手动方案
    if [ -z "$HTML" ]; then
        err "直接获取版本失败 (网络超时)"
        echo "请选择手动方案:"
        echo " 1. 输入加速代理前缀 (尝试重新获取)"
        echo " 2. 直接输入版本号 (跳过获取)"
        printf "请输入选项 [1-2]: "

        if ! read -r CHOICE < /dev/tty 2>/dev/null; then read -r CHOICE; fi

        if [ "$CHOICE" = "1" ]; then
            printf "请输入加速代理前缀 (例如 https://mirror.ghproxy.com/ ): "
            if ! read -r USER_PREFIX < /dev/tty 2>/dev/null; then read -r USER_PREFIX; fi

            if [ -n "$USER_PREFIX" ]; then
                log "[+] 使用加速前缀重试: $USER_PREFIX"
                HTML=$(uclient-fetch -qO- "${USER_PREFIX}${GH_URL}" 2>/dev/null)
                PROXY_PREFIX="$USER_PREFIX"
            else
                err "未输入前缀，安装取消"
                return 1
            fi
        elif [ "$CHOICE" = "2" ]; then
             printf "请输入版本号 (例如 v0.48.13): "
             if ! read -r MANUAL_VER < /dev/tty 2>/dev/null; then read -r MANUAL_VER; fi

             if [ -n "$MANUAL_VER" ]; then
                 # 自动补全 v 前缀
                 case "$MANUAL_VER" in
                    v*) VERSION="$MANUAL_VER" ;;
                    *) VERSION="v$MANUAL_VER" ;;
                 esac
             else
                 err "未输入版本号，安装取消"
                 return 1
             fi
        else
            err "无效选项"
            return 1
        fi
    fi

    # 3. 解析版本号 (如果尚未手动设置版本)
    if [ -z "$VERSION" ]; then
        VERSION=$(echo "$HTML" | grep -o 'href="/vernesong/OpenClash/releases/tag/v[0-9.]*"' | head -n1 | sed 's|.*tag/||; s/"$//')
    fi

    if [ -z "$VERSION" ]; then
        err "版本解析失败，请检查网络或前缀是否有效"
        return 1
    fi

    VER_NUM=${VERSION#v}
    # 拼接最终下载链接
    URL="${PROXY_PREFIX}https://github.com/vernesong/OpenClash/releases/download/${VERSION}/luci-app-openclash_${VER_NUM}_all.ipk"

    log "[✓] 目标版本: $VERSION"
    log "[⚡] 正在下载..."

    # 修复 Illegal file name 错误：先下载到本地再安装
    TMP_FILE="/tmp/openclash.ipk"
    if uclient-fetch -qO "$TMP_FILE" "$URL" 2>/dev/null; then
        log "[⚡] 下载完成，开始安装..."
        if opkg install "$TMP_FILE"; then
            log "[✓] 安装成功！"
            /etc/init.d/openclash enable 2>/dev/null
            /etc/init.d/openclash start 2>/dev/null && log "[+] 服务已启动"
        else
            log "[!] 安装失败，尝试强制修复依赖..."
            opkg install "$TMP_FILE" --force-depends && log "[!] 强制安装完成"
        fi
        rm -f "$TMP_FILE"
    else
        err "文件下载失败，请检查网络"
        return 1
    fi
}


# 工具: 通过 URL 安装 IPK
install_ipk_url() {
    [ -z "$1" ] && { err "请提供下载链接"; return; }
    # 修复：先下载后安装，避免 URL 解析错误
    tmp_file="/tmp/manual_install.ipk"
    log "[+] 正在下载: $1"
    if uclient-fetch -qO "$tmp_file" "$1" 2>/dev/null; then
        log "[+] 开始安装..."
        opkg install "$tmp_file" || log "[!] 安装失败"
        rm -f "$tmp_file"
    else
        err "下载失败，请检查链接"
    fi
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
