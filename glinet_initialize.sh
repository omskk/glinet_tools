#!/bin/sh

set -e

# 配置自定义软件源
cat > /etc/opkg/customfeeds.conf <<'EOF'
src/gz custombase http://glinet.83970255.xyz/?f=/mt798x-openwrt21/base
src/gz custompackages http://glinet.83970255.xyz/?f=/mt798x-openwrt21/packages
src/gz customluci http://glinet.83970255.xyz/?f=/mt798x-openwrt21/luci
EOF

# 更新软件包列表
opkg update

# 安装必备基础包
opkg install luci-lib-ipkg luci-compat

# 安装 Docker 相关包
opkg install docker dockerd docker-compose luci-app-dockerman luci-i18n-dockerman-zh-cn