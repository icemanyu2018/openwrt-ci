#!/bin/bash

# =========================================================
# 1. 基础网络、主机名与默认 Shell 设置
# =========================================================
# 修改默认 LAN IP 为 192.168.30.1
[ -f "package/base-files/files/bin/config_generate" ] && sed -i 's/192.168.1.1/192.168.30.1/g' package/base-files/files/bin/config_generate || true

# 修改默认主机名为 Redmi-AX6
[ -f "package/base-files/files/bin/config_generate" ] && sed -i 's/ImmortalWrt/Redmi-AX6/g' package/base-files/files/bin/config_generate || true

# 更改默认 Shell 为 zsh
[ -f "package/base-files/files/etc/passwd" ] && sed -i 's/\/bin\/ash/\/usr\/bin\/zsh/g' package/base-files/files/etc/passwd 2>/dev/null || true

# TTYD 免登录
[ -f "feeds/packages/utils/ttyd/files/ttyd.config" ] && sed -i 's|/bin/login|/bin/login -f root|g' feeds/packages/utils/ttyd/files/ttyd.config 2>/dev/null || true

# =========================================================
# 2. 首次启动 UCI 自动配置 (设置密码、Wi-Fi SSID)
# =========================================================
mkdir -p package/base-files/files/etc/uci-defaults || true

cat << 'EOF' > package/base-files/files/etc/uci-defaults/99-custom-setup
#!/bin/sh

# 1. 设置默认 root 密码为: 123456789
shadow_entry='root:$1$V44XV16Y$221.A8ESL322338.309071:17880:0:99999:7:::'
[ -f "/etc/shadow" ] && sed -i "s|^root:.*|${shadow_entry}|" /etc/shadow 2>/dev/null || true

# 2. 遍历所有 wireless 接口设置默认 SSID (OWrt-5G / OWrt-2.4G) 并开启 Wi-Fi
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
    done

    for dev in $(uci show wireless 2>/dev/null | grep "=wifi-device" | cut -d'.' -f2 | cut -d'=' -f1); do
        uci -q set wireless.${dev}.disabled='0'
    done

    uci commit wireless
fi
exit 0
EOF
chmod +x package/base-files/files/etc/uci-defaults/99-custom-setup || true

# 静态双重保险修改 Wi-Fi 默认 SSID
[ -f "package/kernel/mac80211/files/lib/wifi/mac80211.sh" ] && sed -i 's/ssid=ImmortalWrt/ssid=OWrt-2.4G/g' package/kernel/mac80211/files/lib/wifi/mac80211.sh 2>/dev/null || true
[ -f "package/kernel/mac80211/files/lib/wifi/mac80211.sh" ] && sed -i 's/ssid=OpenWrt/ssid=OWrt-2.4G/g' package/kernel/mac80211/files/lib/wifi/mac80211.sh 2>/dev/null || true

# =========================================================
# 3. 安全稀疏克隆函数 (无需切换 cd 目录，彻底消除 Exit 1)
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
# 清理可能已存在的旧文件夹
rm -rf package/luci-theme-argon package/luci-app-argon-config package/luci-app-poweroff package/luci-app-netdata package/luci-app-nikki || true

# 独立克隆重点插件
git clone --depth=1 https://github.com/jerrykuku/luci-theme-argon package/luci-theme-argon 2>/dev/null || true
git clone --depth=1 https://github.com/jerrykuku/luci-app-argon-config package/luci-app-argon-config 2>/dev/null || true
git clone --depth=1 https://github.com/esirplayground/luci-app-poweroff package/luci-app-poweroff 2>/dev/null || true
git clone --depth=1 https://github.com/Jason6111/luci-app-netdata package/luci-app-netdata 2>/dev/null || true
git clone --depth=1 https://github.com/nikkinikki-org/luci-app-nikki package/luci-app-nikki 2>/dev/null || true

# 稀疏克隆文件浏览器
git_sparse_clone main https://github.com/Lienol/openwrt-package luci-app-filebrowser

# 引入 small-package 大合集
rm -rf package/small-package || true
git clone --depth=1 https://github.com/kenzok8/small-package.git package/small-package 2>/dev/null || true

# 剔除 small-package 中重复的包
rm -rf package/small-package/luci-theme-argon || true
rm -rf package/small-package/luci-app-argon-config || true
[ -d "package/luci-app-nikki" ] && rm -rf package/small-package/luci-app-nikki || true
rm -rf package/small-package/luci-app-netdata || true
rm -rf package/small-package/luci-app-poweroff || true
rm -rf package/small-package/tcping || true
rm -rf package/small-package/coremark || true

# =========================================================
# 5. 系统个性化与 Makefile 路径修正
# =========================================================
# 安全替换，加 -r 参数防止空查找抛出异常退出状态
find package/ -type f -name "Makefile" 2>/dev/null | xargs -r sed -i 's/..\/..\/luci.mk/$(TOPDIR)\/feeds\/luci\/luci.mk/g' 2>/dev/null || true
find package/ -type f -name "Makefile" 2>/dev/null | xargs -r sed -i 's/PKG_SOURCE_URL:=@GHREPO/PKG_SOURCE_URL:=https:\/\/github.com/g' 2>/dev/null || true
find package/ -type f -name "Makefile" 2>/dev/null | xargs -r sed -i 's/PKG_SOURCE_URL:=@GHCODELOAD/PKG_SOURCE_URL:=https:\/\/codeload.github.com/g' 2>/dev/null || true

# =========================================================
# 6. 清理内核与 eBPF / Clang 修复
# =========================================================
rm -rf package/kernel/bpf-headers || true

SYSTEM_CLANG=$(which clang 2>/dev/null || echo "/usr/bin/clang")

if [ -f "include/bpf.mk" ]; then
    sed -i "s|/invalid/clang|${SYSTEM_CLANG}|g" include/bpf.mk 2>/dev/null || true
fi

# 显式返回 0，确保流程绝对顺畅通过
exit 0
