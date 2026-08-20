#!/bin/bash

# =========================================================
# 1. 基础网络、主机名与默认 Shell 设置
# =========================================================
# 设定后台默认 IP 为 192.168.5.1
[ -f "package/base-files/files/bin/config_generate" ] && sed -i 's/192.168.1.1/192.168.5.1/g' package/base-files/files/bin/config_generate || true
[ -f "package/base-files/files/bin/config_generate" ] && sed -i 's/ImmortalWrt/Redmi-AX6/g' package/base-files/files/bin/config_generate || true
[ -f "package/base-files/files/etc/passwd" ] && sed -i 's/\/bin\/ash/\/usr\/bin\/zsh/g' package/base-files/files/etc/passwd 2>/dev/null || true
[ -f "feeds/packages/utils/ttyd/files/ttyd.config" ] && sed -i 's|/bin/login|/bin/login -f root|g' feeds/packages/utils/ttyd/files/ttyd.config 2>/dev/null || true

# =========================================================
# 2. 首次启动 UCI 自动配置 (WiFi 免密 & 默认密码 123456789)
# =========================================================
mkdir -p package/base-files/files/etc/uci-defaults || true

cat << 'EOF' > package/base-files/files/etc/uci-defaults/99-custom-setup
#!/bin/sh

shadow_entry='root:$6$v1lG4aP0vO5o6p8t$vV8zU7Xg3G5i3e7a3V8kYq9F3t2pL5n0j8K7d6s4g2h1j5k6l7z8x9c0v1b2n3m4Q5w6e7r8t9y0u1i2o3p4A5.:19700:0:99999:7:::'
if [ -f "/etc/shadow" ]; then
    sed -i "s|^root:.*|${shadow_entry}|" /etc/shadow 2>/dev/null || true
fi

if command -v uci >/dev/null 2>&1; then
    for section in $(uci show wireless 2>/dev/null | grep "=wifi-iface" | cut -d'.' -f2 | cut -d'=' -f1); do
        device=$(uci -q get wireless.${section}.device)
        band=$(uci -q get wireless.${device}.band)
        htmode=$(uci -q get wireless.${device}.htmode)

        if [ "$band" = "5g" ] || echo "$htmode" | grep -qE "HE80|HE160|VHT"; then
            uci -q set wireless.${section}.ssid='OWrt-5G'
        else
            uci -q set wireless.${section}.ssid='OWrt-2.4G'
        fi
        
        uci -q set wireless.${section}.encryption='none'
        uci -q del wireless.${section}.key 2>/dev/null || true
    done

    for dev in $(uci show wireless 2>/dev/null | grep "=wifi-device" | cut -d'.' -f2 | cut -d'=' -f1); do
        uci -q set wireless.${dev}.disabled='0'
    done

    uci commit wireless
fi
exit 0
EOF
chmod +x package/base-files/files/etc/uci-defaults/99-custom-setup || true

[ -f "package/kernel/mac80211/files/lib/wifi/mac80211.sh" ] && sed -i 's/ssid=ImmortalWrt/ssid=OWrt-2.4G/g' package/kernel/mac80211/files/lib/wifi/mac80211.sh 2>/dev/null || true
[ -f "package/kernel/mac80211/files/lib/wifi/mac80211.sh" ] && sed -i 's/ssid=OpenWrt/ssid=OWrt-2.4G/g' package/kernel/mac80211/files/lib/wifi/mac80211.sh 2>/dev/null || true

# =========================================================
# 3. 修复 hostapd 补丁冲突
# =========================================================
rm -f package/network/services/hostapd/patches/602-nl80211-short-circuit-use-existing-iface.patch || true

# =========================================================
# 4. 安全稀疏克隆函数
# =========================================================
function git_sparse_clone() {
  local branch="$1" repourl="$2" && shift 2
  local target_pkgs="$@"
  local repodir="tmp_sparse_repo"

  rm -rf "$repodir" || true
  git clone --depth=1 -b "$branch" --single-branch --filter=blob:none --sparse "$repourl" "$repodir" 2>/dev/null || return 0
  
  if [ -d "$repodir" ]; then
    git -C "$repodir" sparse-checkout set $target_pkgs 2>/dev/null || true
    for pkg in $target_pkgs; do
      if [ -d "$repodir/$pkg" ]; then
        rm -rf "package/$(basename $pkg)" || true
        cp -rf "$repodir/$pkg" package/ || true
      fi
    done
    rm -rf "$repodir" || true
  fi
}

# =========================================================
# 5. 引入第三方核心仓库
# =========================================================
rm -rf package/luci-theme-argon package/luci-app-argon-config package/luci-app-poweroff package/luci-app-netdata \
       package/luci-app-nikki package/nikki package/mihomo package/luci-app-adguardhome package/luci-app-openclash \
       package/luci-app-mosdns package/mosdns package/luci-app-smartdns package/smartdns || true

# 1. Argon 主题与配置插件
git clone --depth=1 https://github.com/jerrykuku/luci-theme-argon package/luci-theme-argon 2>/dev/null || true
git clone --depth=1 https://github.com/jerrykuku/luci-app-argon-config package/luci-app-argon-config 2>/dev/null || true

# 2. 关机与 Netdata
git clone --depth=1 https://github.com/esirplayground/luci-app-poweroff package/luci-app-poweroff 2>/dev/null || true
git clone --depth=1 https://github.com/Jason6111/luci-app-netdata package/luci-app-netdata 2>/dev/null || true

# 3. OpenClash
git clone --depth=1 -b master https://github.com/vernesong/OpenClash package/luci-app-openclash 2>/dev/null || true

# 4. Nikki (Mihomo 原生支持)
git clone --depth=1 https://github.com/nikkinikki-org/OpenWrt-nikki package/luci-app-nikki 2>/dev/null || git clone --depth=1 https://github.com/morytyann/OpenWrt-nikki package/luci-app-nikki 2>/dev/null || true

# 5. AdGuard Home 面板
git clone --depth=1 https://github.com/rufengsuixing/luci-app-adguardhome package/luci-app-adguardhome 2>/dev/null || true

# 6. MosDNS
git clone --depth=1 https://github.com/sbwml/luci-app-mosdns package/luci-app-mosdns 2>/dev/null || true

# 7. 稀疏克隆文件浏览器
git_sparse_clone main https://github.com/Lienol/openwrt-package luci-app-filebrowser

# =========================================================
# 6. 系统个性化与 Makefile 路径修正
# =========================================================
find package/ -type f -name "Makefile" 2>/dev/null | xargs -r sed -i 's/..\/..\/luci.mk/$(TOPDIR)\/feeds\/luci\/luci.mk/g' 2>/dev/null || true
find package/ -type f -name "Makefile" 2>/dev/null | xargs -r sed -i 's/PKG_SOURCE_URL:=@GHREPO/PKG_SOURCE_URL:=https:\/\/github.com/g' 2>/dev/null || true
find package/ -type f -name "Makefile" 2>/dev/null | xargs -r sed -i 's/PKG_SOURCE_URL:=@GHCODELOAD/PKG_SOURCE_URL:=https:\/\/codeload.github.com/g' 2>/dev/null || true

exit 0
