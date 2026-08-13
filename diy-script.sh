#!/bin/bash

# =========================================================
# 1. 基础网络、主机名与默认 Shell 设置
# =========================================================
# 修改默认 LAN IP 为 192.168.30.1
[ -f "package/base-files/files/bin/config_generate" ] && sed -i 's/192.168.1.1/192.168.30.1/g' package/base-files/files/bin/config_generate

# 修改默认主机名为 Redmi-AX6
[ -f "package/base-files/files/bin/config_generate" ] && sed -i 's/ImmortalWrt/Redmi-AX6/g' package/base-files/files/bin/config_generate

# 更改默认 Shell 为 zsh
[ -f "package/base-files/files/etc/passwd" ] && sed -i 's/\/bin\/ash/\/usr\/bin\/zsh/g' package/base-files/files/etc/passwd 2>/dev/null || true

# TTYD 免登录
[ -f "feeds/packages/utils/ttyd/files/ttyd.config" ] && sed -i 's|/bin/login|/bin/login -f root|g' feeds/packages/utils/ttyd/files/ttyd.config 2>/dev/null || true

# =========================================================
# 2. 首次启动 UCI 自动配置 (设置密码、Wi-Fi SSID)
# =========================================================
mkdir -p package/base-files/files/etc/uci-defaults

cat << 'EOF' > package/base-files/files/etc/uci-defaults/99-custom-setup
#!/bin/sh

# 1. 设置默认 root 密码为: 123456789
shadow_entry='root:$1$V44XV16Y$221.A8ESL322338.309071:17880:0:99999:7:::'
[ -f "/etc/shadow" ] && sed -i "s|^root:.*|${shadow_entry}|" /etc/shadow

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
chmod +x package/base-files/files/etc/uci-defaults/99-custom-setup

# 静态双重保险修改 Wi-Fi 默认 SSID
[ -f "package/kernel/mac80211/files/lib/wifi/mac80211.sh" ] && sed -i 's/ssid=ImmortalWrt/ssid=OWrt-2.4G/g' package/kernel/mac80211/files/lib/wifi/mac80211.sh 2>/dev/null || true
[ -f "package/kernel/mac80211/files/lib/wifi/mac80211.sh" ] && sed -i 's/ssid=OpenWrt/ssid=OWrt-2.4G/g' package/kernel/mac80211/files/lib/wifi/mac80211.sh 2>/dev/null || true

# =========================================================
# 3. Git 稀疏克隆函数 (Sparse Clone)
# =========================================================
function git_sparse_clone() {
  branch="$1" repourl="$2" && shift 2
  repodir=$(basename $repourl .git)
  rm -rf $repodir
  git clone --depth=1 -b $branch --single-branch --filter=blob:none --sparse $repourl || return 0
  cd $repodir || return 0
  git sparse-checkout set $@
  for pkg in $@; do
    if [ -d "$pkg" ]; then
      rm -rf "../package/$(basename $pkg)"
      mv -f "$pkg" ../package/
    fi
  done
  cd .. && rm -rf $repodir
}

# =========================================================
# 4. 引入第三方核心仓库 & 解决包冲突
# =========================================================
# 清理可能已存在的旧文件夹
rm -rf package/luci-theme-argon
rm -rf package/luci-app-argon-config
rm -rf package/luci-app-poweroff
rm -rf package/luci-app-netdata
rm -rf package/luci-app-nikki

# 独立克隆重点插件
git clone --depth=1 https://github.com/jerrykuku/luci-theme-argon package/luci-theme-argon || true
git clone --depth=1 https://github.com/jerrykuku/luci-app-argon-config package/luci-app-argon-config || true
git clone --depth=1 https://github.com/esirplayground/luci-app-poweroff package/luci-app-poweroff || true
git clone --depth=1 https://github.com/Jason6111/luci-app-netdata package/luci-app-netdata || true
git clone --depth=1 https://github.com/nikkinikki-org/luci-app-nikki package/luci-app-nikki 2>/dev/null || true

git_sparse_clone main https://github.com/Lienol/openwrt-package luci-app-filebrowser

# 引入 small-package 大合集
rm -rf package/small-package
git clone --depth=1 https://github.com/kenzok8/small-package.git package/small-package || true

# 剔除 small-package 中重复的包
rm -rf package/small-package/luci-theme-argon
rm -rf package/small-package/luci-app-argon-config
[ -d "package/luci-app-nikki" ] && rm -rf package/small-package/luci-app-nikki
rm -rf package/small-package/luci-app-netdata
rm -rf package/small-package/luci-app-poweroff
rm -rf package/small-package/tcping
rm -rf package/small-package/coremark

# =========================================================
# 5. 系统个性化与 Makefile 路径修正 (修复 exit 1 隐患)
# =========================================================
# 修正 Makefile 中的路径与 URL
find package/ -type f -name "Makefile" 2>/dev/null | xargs -r sed -i 's/..\/..\/luci.mk/$(TOPDIR)\/feeds\/luci\/luci.mk/g' 2>/dev/null || true
find package/ -type f -name "Makefile" 2>/dev/null | xargs -r sed -i 's/PKG_SOURCE_URL:=@GHREPO/PKG_SOURCE_URL:=https:\/\/github.com/g' 2>/dev/null || true
find package/ -type f -name "Makefile" 2>/dev/null | xargs -r sed -i 's/PKG_SOURCE_URL:=@GHCODELOAD/PKG_SOURCE_URL:=https:\/\/codeload.github.com/g' 2>/dev/null || true

# 安全删除主题的强制默认设置（使用 find + grep 保护，防止没匹配到报错退出）
find package/ -type f \( -name "*luci-theme-*" -o -name "*argon*" \) 2>/dev/null | xargs -r sed -i '/set luci.main.mediaurlbase/d' 2>/dev/null || true

# =========================================================
# 6. 清理内核与 eBPF / Clang 修复
# =========================================================
rm -rf package/kernel/bpf-headers

SYSTEM_CLANG=$(which clang 2>/dev/null || echo "/usr/bin/clang")

if [ -f "include/bpf.mk" ]; then
    sed -i "s|/invalid/clang|${SYSTEM_CLANG}|g" include/bpf.mk 2>/dev/null || true
fi

# 确保脚本始终以 exit 0 正常退出
exit 0
