#!/bin/bash

# =========================================================
# 1. 基础网络、主机名、密码与默认 Shell 设置
# =========================================================
# 修改默认 LAN IP 为 192.168.30.1
sed -i 's/192.168.1.1/192.168.30.1/g' package/base-files/files/bin/config_generate

# 修改默认主机名为 Redmi-AX6
sed -i 's/ImmortalWrt/Redmi-AX6/g' package/base-files/files/bin/config_generate

# 设置默认登录密码为: 123456789
sed -i 's/root:::0:99999:7:::/root:\$1\$V44XV16Y\$221.A8ESL322338.309071:0:99999:7:::/g' package/base-files/files/etc/shadow 2>/dev/null || true
if [ -f "package/lean/default-settings/files/zzz-default-settings" ]; then
    sed -i '/CYXluq4wUaawER1/d' package/lean/default-settings/files/zzz-default-settings 2>/dev/null || true
    sed -i 's/root:.*$/root:\$1\$V44XV16Y\$221.A8ESL322338.309071:17880:0:99999:7:::/g' package/lean/default-settings/files/zzz-default-settings 2>/dev/null || true
fi

# 更改默认 Shell 为 zsh
sed -i 's/\/bin\/ash/\/usr\/bin\/zsh/g' package/base-files/files/etc/passwd

# TTYD 免登录
sed -i 's|/bin/login|/bin/login -f root|g' feeds/packages/utils/ttyd/files/ttyd.config 2>/dev/null || true

# =========================================================
# 2. 设置 Wi-Fi 默认 SSID (OWrt-5G / OWrt-2.4G)
# =========================================================
mkdir -p package/base-files/files/etc/uci-defaults
cat << 'EOF' > package/base-files/files/etc/uci-defaults/99-custom-wifi
#!/bin/sh

# 遍历所有 wireless 设备接口并设置默认 SSID
for dev in $(uci show wireless | grep "=wifi-device" | cut -d'.' -f2 | cut -d'=' -f1); do
    band=$(uci -q get wireless.${dev}.band)
    htmode=$(uci -q get wireless.${dev}.htmode)

    # 优先通过 band 或 htmode 识别 5G / 2.4G 频段
    if [ "$band" = "5g" ] || echo "$htmode" | grep -qE "HE80|HE160|VHT"; then
        uci -q set wireless.default_${dev}.ssid='OWrt-5G'
    else
        uci -q set wireless.default_${dev}.ssid='OWrt-2.4G'
    fi
    # 默认开启 Wi-Fi (取消禁用)
    uci -q set wireless.${dev}.disabled='0'
done

uci commit wireless
exit 0
EOF
chmod +x package/base-files/files/etc/uci-defaults/99-custom-wifi

# 双重保险静态修改
sed -i 's/ssid=ImmortalWrt/ssid=OWrt-2.4G/g' package/kernel/mac80211/files/lib/wifi/mac80211.sh 2>/dev/null || true
sed -i 's/ssid=OpenWrt/ssid=OWrt-2.4G/g' package/kernel/mac80211/files/lib/wifi/mac80211.sh 2>/dev/null || true

# =========================================================
# 3. 清理 Feed 中可能冲突的旧软件包
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
# 5. 引入第三方核心仓库 (包含 daed / Argon / 实用工具)
# =========================================================
# kenzok8 small-package 包含 daed, dae, SmartDNS, MosDNS, Alist 等组件
git clone --depth=1 https://github.com/kenzok8/small-package.git package/small-package

# 替换最新的 Argon 主题及配置插件
git clone --depth=1 https://github.com/jerrykuku/luci-theme-argon package/luci-theme-argon
git clone --depth=1 https://github.com/jerrykuku/luci-app-argon-config package/luci-app-argon-config

# 实用小工具
git clone --depth=1 https://github.com/esirplayground/luci-app-poweroff package/luci-app-poweroff
git clone --depth=1 https://github.com/Jason6111/luci-app-netdata package/luci-app-netdata
git_sparse_clone main https://github.com/Lienol/openwrt-package luci-app-filebrowser

# 引入 Nikki (luci-app-nikki) 及其核心依赖
rm -rf package/luci-app-nikki
git clone --depth=1 https://github.com/nikkinikki-org/luci-app-nikki.git package/luci-app-nikki

# =========================================================
# 6. 系统个性化与修复补丁
# =========================================================
# 修改本地时间格式
sed -i 's/os.date()/os.date("%a %Y-%m-%d %H:%M:%S")/g' package/lean/autocore/files/*/index.htm 2>/dev/null || true

# 修改版本显示为当前编译日期
date_version=$(date +"%y.%m.%d")
if [ -f "package/lean/default-settings/files/zzz-default-settings" ]; then
    orig_version=$(cat "package/lean/default-settings/files/zzz-default-settings" | grep DISTRIB_REVISION= | awk -F "'" '{print $2}')
    sed -i "s/${orig_version}/R${date_version} for AX6/g" package/lean/default-settings/files/zzz-default-settings
fi

# 修正部分第三方 package Makefile 路径引用
find package/*/ -maxdepth 2 -path "*/Makefile" | xargs -i sed -i 's/..\/..\/luci.mk/$(TOPDIR)\/feeds\/luci\/luci.mk/g' {} 2>/dev/null || true
find package/*/ -maxdepth 2 -path "*/Makefile" | xargs -i sed -i 's/PKG_SOURCE_URL:=@GHREPO/PKG_SOURCE_URL:=https:\/\/github.com/g' {} 2>/dev/null || true
find package/*/ -maxdepth 2 -path "*/Makefile" | xargs -i sed -i 's/PKG_SOURCE_URL:=@GHCODELOAD/PKG_SOURCE_URL:=https:\/\/codeload.github.com/g' {} 2>/dev/null || true

# 取消主题强制默认设置
find package/luci-theme-*/* -type f -name '*luci-theme-*' -print -exec sed -i '/set luci.main.mediaurlbase/d' {} \; 2>/dev/null || true

# =========================================================
# 7. 刷新并安装所有包 Feeds
# =========================================================
./scripts/feeds update -a
./scripts/feeds install -a

# =========================================================
# 8. 清理冲突包与修复 eBPF / Coremark / Clang 源码硬链
# =========================================================
# 清理有冲突的内核/工具依赖项
rm -rf package/kernel/bpf-headers
rm -rf feeds/packages/kernel/bpf-headers
rm -rf package/small-package/tcping

# 清理 small-package 中存在 mkdir 缺失 -p 逻辑 Bug 的 coremark 源码包，自动回退使用官方源
rm -rf package/small-package/coremark

# 找到系统真实 clang 路径
SYSTEM_CLANG=$(which clang || echo "/usr/bin/clang")

# 强制替换 include/bpf.mk 源码中的 /invalid/clang 兜底路径
if [ -f "include/bpf.mk" ]; then
    sed -i "s|/invalid/clang|${SYSTEM_CLANG}|g" include/bpf.mk
fi

# 创建系统全局 Clang 软链接
sudo ln -sf "$SYSTEM_CLANG" /usr/local/bin/clang 2>/dev/null || true
