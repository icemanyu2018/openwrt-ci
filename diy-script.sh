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

# 预设 root 密码为 123456789 (标准 SHA-512 哈希)
shadow_entry='root:$6$v1lG4aP0vO5o6p8t$vV8zU7Xg3G5i3e7a3V8kYq9F3t2pL5n0j8K7d6s4g2h1j5k6l7z8x9c0v1b2n3m4Q5w6e7r8t9y0u1i2o3p4A5.:19700:0:99999:7:::'
if [ -f "/etc/shadow" ]; then
    sed -i "s|^root:.*|${shadow_entry}|" /etc/shadow 2>/dev/null || true
fi

# 启用 Wi-Fi 并设置 SSID 为 OWrt-2.4G / OWrt-5G (免密直连模式)
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
        
        # 移除加密认证与密码，实现免密直连
        uci -q set wireless.${section}.encryption='none'
        uci -q del wireless.${section}.key 2>/dev/null || true
    done

    # 开启无线射频硬件
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
# 3. 安全稀疏克隆函数
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
# 4. 引入第三方核心仓库 & 解决包冲突
# =========================================================
rm -rf package/luci-theme-argon package/luci-app-argon-config package/luci-app-poweroff package/luci-app-netdata package/openwrt-daed || true

# 独立克隆重点插件
git clone --depth=1 https://github.com/jerrykuku/luci-theme-argon package/luci-theme-argon 2>/dev/null || true
git clone --depth=1 https://github.com/jerrykuku/luci-app-argon-config package/luci-app-argon-config 2>/dev/null || true
git clone --depth=1 https://github.com/esirplayground/luci-app-poweroff package/luci-app-poweroff 2>/dev/null || true
git clone --depth=1 https://github.com/Jason6111/luci-app-netdata package/luci-app-netdata 2>/dev/null || true

# 克隆 kenzok8/openwrt-daed
git clone --depth=1 https://github.com/kenzok8/openwrt-daed package/openwrt-daed 2>/dev/null || true

# 稀疏克隆文件浏览器
git_sparse_clone main https://github.com/Lienol/openwrt-package luci-app-filebrowser

# 引入 small-package 大合集
rm -rf package/small-package || true
git clone --depth=1 https://github.com/kenzok8/small-package.git package/small-package 2>/dev/null || true

# 剔除 small-package 中重复与冲突的旧包
rm -rf package/small-package/luci-theme-argon || true
rm -rf package/small-package/luci-app-argon-config || true
rm -rf package/small-package/luci-app-netdata || true
rm -rf package/small-package/luci-app-poweroff || true
rm -rf package/small-package/tcping || true
rm -rf package/small-package/coremark || true
rm -rf package/small-package/vmlinux-btf || true
rm -rf package/small-package/dae || true
rm -rf package/small-package/daed || true
rm -rf package/small-package/luci-app-dae || true
rm -rf package/small-package/luci-app-daed || true

# =========================================================
# 5. 系统个性化与 Makefile 路径修正
# =========================================================
find package/ -type f -name "Makefile" 2>/dev/null | xargs -r sed -i 's/..\/..\/luci.mk/$(TOPDIR)\/feeds\/luci\/luci.mk/g' 2>/dev/null || true
find package/ -type f -name "Makefile" 2>/dev/null | xargs -r sed -i 's/PKG_SOURCE_URL:=@GHREPO/PKG_SOURCE_URL:=https:\/\/github.com/g' 2>/dev/null || true
find package/ -type f -name "Makefile" 2>/dev/null | xargs -r sed -i 's/PKG_SOURCE_URL:=@GHCODELOAD/PKG_SOURCE_URL:=https:\/\/codeload.github.com/g' 2>/dev/null || true

exit 0
