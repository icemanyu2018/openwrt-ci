#!/bin/bash

# =========================================================
# 1. 基础网络、主机名设置
# =========================================================
# 修改默认 LAN IP 为 192.168.30.1
sed -i 's/192.168.1.1/192.168.30.1/g' package/base-files/files/bin/config_generate

# 修改默认主机名为 Redmi-AX6
sed -i 's/ImmortalWrt/Redmi-AX6/g' package/base-files/files/bin/config_generate

# 更改默认 Shell 为 zsh
sed -i 's/\/bin\/ash/\/usr\/bin\/zsh/g' package/base-files/files/etc/passwd 2>/dev/null || true

# TTYD 免登录
sed -i 's|/bin/login|/bin/login -f root|g' feeds/packages/utils/ttyd/files/ttyd.config 2>/dev/null || true

# =========================================================
# 2. 首次启动 UCI 自动配置 (设置密码、Wi-Fi SSID)
# =========================================================
mkdir -p package/base-files/files/etc/uci-defaults

cat << 'EOF' > package/base-files/files/etc/uci-defaults/99-custom-setup
#!/bin/sh

# 1. 设置默认 root 密码为: 123456789
shadow_entry='root:$1$V44XV16Y$221.A8ESL322338.309071:17880:0:99999:7:::'
sed -i "s|^root:.*|${shadow_entry}|" /etc/shadow

# 2. 遍历所有 wireless 设备接口并设置默认 SSID (OWrt-5G / OWrt-2.4G)
for dev in $(uci show wireless | grep "=wifi-device" | cut -d'.' -f2 | cut -d'=' -f1); do
    band=$(uci -q get wireless.${dev}.band)
    htmode=$(uci -q get wireless.${dev}.htmode)

    if [ "$band" = "5g" ] || echo "$htmode" | grep -qE "HE80|HE160|VHT"; then
        uci -q set wireless.default_${dev}.ssid='OWrt-5G'
    else
        uci -q set wireless.default_${dev}.ssid='OWrt-2.4G'
    fi
    # 默认开启 Wi-Fi
    uci -q set wireless.${dev}.disabled='0'
done

uci commit wireless
exit 0
EOF
chmod +x package/base-files/files/etc/uci-defaults/99-custom-setup

# 静态双重保险修改 Wi-Fi 默认 SSID
sed -i 's/ssid=ImmortalWrt/ssid=OWrt-2.4G/g' package/kernel/mac80211/files/lib/wifi/mac80211.sh 2>/dev/null || true
sed -i 's/ssid=OpenWrt/ssid=OWrt-2.4G/g' package/kernel/mac80211/files/lib/wifi/mac80211.sh 2>/dev/null || true

# =========================================================
# 3. 清理 Feeds 中冲突的官方/旧软件包
# =========================================================
rm -rf feeds/packages/net/mosdns
rm -rf feeds/packages/net/msd_lite
rm -rf feeds/packages/net/smartdns
rm -rf feeds/luci/themes/luci-theme-argon
rm -rf feeds/luci/applications/luci-app-mosdns
rm -rf feeds/luci/applications/luci-app-netdata

# =========================================================
# 4. Git 稀疏克隆函数 (Sparse Clone)
# =========================================================
function git_sparse_clone() {
  branch="$1" repourl="$2" && shift 2
  git clone --depth=1 -b $branch --single-branch --filter=blob:none --sparse $repourl
  repodir=$(echo $repourl | awk -F '/' '{print $(NF)}')
  cd $repodir && git sparse-checkout set $@
  mv -f $@ ../package
  cd .. && rm -rf $repodir
}

# =========================================================
# 5. 引入第三方核心仓库 & 解决 small-package 包冲突
# =========================================================
# 独立克隆最新版的重点插件
git clone --depth=1 https://github.com/jerrykuku/luci-theme-argon package/luci-theme-argon
git clone --depth=1 https://github.com/jerrykuku/luci-app-argon-config package/luci-app-argon-config
git clone --depth=1 https://github.com/esirplayground/luci-app-poweroff package/luci-app-poweroff
git clone --depth=1 https://github.com/Jason6111/luci-app-netdata package/luci-app-netdata
git clone --depth=1 https://github.com/nikkinikki-org/luci-app-nikki.git package/luci-app-nikki
git_sparse_clone main https://github.com/Lienol/openwrt-package luci-app-filebrowser

# 引入 small-package 大合集
git clone --depth=1 https://github.com/kenzok8/small-package.git package/small-package

# 核心防撞处理：彻底剔除 small-package 中与上方重复的软件包！
rm -rf package/small-package/luci-theme-argon
rm -rf package/small-package/luci-app-argon-config
rm -rf package/small-package/luci-app-nikki
rm -rf package/small-package/luci-app-netdata
rm -rf package/small-package/luci-app-poweroff
rm -rf package/small-package/tcping
rm -rf package/small-package/coremark

# =========================================================
# 6. 系统个性化与 Makefile 路径修正
# =========================================================
# 修正部分第三方 package Makefile 路径引用
find package/*/ -maxdepth 2 -path "*/Makefile" | xargs -i sed -i 's/..\/..\/luci.mk/$(TOPDIR)\/feeds\/luci\/luci.mk/g' {} 2>/dev/null || true
find package/*/ -maxdepth 2 -path "*/Makefile" | xargs -i sed -i 's/PKG_SOURCE_URL:=@GHREPO/PKG_SOURCE_URL:=https:\/\/github.com/g' {} 2>/dev/null || true
find package/*/ -maxdepth 2 -path "*/Makefile" | xargs -i sed -i 's/PKG_SOURCE_URL:=@GHCODELOAD/PKG_SOURCE_URL:=https:\/\/codeload.github.com/g' {} 2>/dev/null || true

# 取消主题强制默认设置
find package/luci-theme-*/* -type f -name '*luci-theme-*' -print -exec sed -i '/set luci.main.mediaurlbase/d' {} \; 2>/dev/null || true

# =========================================================
# 7. 清理冲突包与 eBPF / Clang 修复
# =========================================================
rm -rf package/kernel/bpf-headers
rm -rf feeds/packages/kernel/bpf-headers

SYSTEM_CLANG=$(which clang || echo "/usr/bin/clang")

if [ -f "include/bpf.mk" ]; then
    sed -i "s|/invalid/clang|${SYSTEM_CLANG}|g" include/bpf.mk
fi
