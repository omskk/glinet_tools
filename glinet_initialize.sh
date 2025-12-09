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

# 功能1: 初始化菜单 (内部逻辑: 解锁隐藏项)
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

# 功能2: 还原配置
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

# 功能3: 安装 Docker
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

# 功能4: 安装 OpenClash (动态获取最新版)
install_openclash() {
    log "[+] 准备安装 OpenClash..."

    # 1. 配置软件源 (OpenClash 依赖很多基础库，需要源支持)
    mkdir -p /etc/opkg
    echo "$EXPECTED_FEEDS" > /etc/opkg/customfeeds.conf

    # 2. 必须执行 update 来获取依赖包列表
    log "[+] 更新软件包列表 (用于处理依赖)..."
    opkg update

    # 3. 动态获取最新下载链接
    log "[+] 正在获取 GitHub 最新版本链接..."
    API_URL="https://api.github.com/repos/vernesong/OpenClash/releases/latest"

    # 使用 wget -qO- 读取 API 返回的 JSON，然后提取 browser_download_url 字段中以 .ipk 结尾的链接
    DOWNLOAD_URL=$(wget -qO- "$API_URL" | grep -o 'https://[^"]*luci-app-openclash[^"]*\.ipk' | head -n 1)

    if [ -z "$DOWNLOAD_URL" ]; then
        err "获取下载链接失败，请检查网络连接或 GitHub API 状态。"
        return
    fi

    log "[+] 发现最新版: $(basename "$DOWNLOAD_URL")"

    # 4. 下载到临时目录
    TMP_FILE="/tmp/openclash.ipk"
    log "[+] 正在下载..."
    if wget -O "$TMP_FILE" "$DOWNLOAD_URL"; then
        log "[+] 下载完成，开始安装..."

        # 5. 执行安装 (opkg install ipk文件 会自动尝试从源里下载依赖)
        if opkg install "$TMP_FILE"; then
            log "[✓] OpenClash 安装成功！请刷新后台查看"
        else
            log "[!] 安装遇到依赖错误，尝试强制修复..."
            opkg install "$TMP_FILE" --force-depends
        fi

        # 清理垃圾
        rm "$TMP_FILE"
    else
        err "文件下载失败"
    fi
}

# 工具: 通过 URL 安装 IPK (隐藏功能，供手动调用)
# 用法: install_ipk_url "https://example.com/app.ipk"
install_ipk_url() {
    [ -z "$1" ] && { err "请提供下载链接"; return; }
    tmp_file="/tmp/temp_install.ipk"
    log "[+] 正在下载: $1"
    if wget -O "$tmp_file" "$1"; then
        log "[+] 开始安装..."
        opkg install "$tmp_file"
        rm "$tmp_file"
        log "[✓] 安装完成"
    else
        err "下载失败，请检查网络"
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

    # 核心修复: 强制从 /dev/tty 读取输入
    # 解决 curl | sh 管道运行时的无限死循环问题
    if ! read -r c < /dev/tty 2>/dev/null; then read -r c; fi

    # 如果非交互模式下读取为空，强制退出防止死循环
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
