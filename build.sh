#!/bin/bash
#
# Copyright (C) 2017 OVH OverTheBox
# Copyright (C) 2017-2024 Ycarus (Yannick Chabanois) <ycarus@zugaina.org> for OpenMPTCProuter project
#
# This is free software, licensed under the GNU General Public License v3.
# See /LICENSE for more information.
#

# 脚本执行时输出行号
# export PS4='<Line ${LINENO}> '
set -x
set -e

umask 0022
unset GREP_OPTIONS SED

TOP_DIR=$(readlink -f "$(pwd)/../")

# 拉取远端仓库的最新代码，并检出指定分支
_get_repo() (
	mkdir -p "$1"
	cd "$1"
	[ -d .git ] || git init
	if git remote get-url origin >/dev/null 2>/dev/null; then
		git remote set-url origin "$2"
	else
		git remote add origin "$2"
	fi
	git fetch origin -f
	git fetch origin --tags -f
	git checkout -f "origin/$3" -B "build" 2>/dev/null || git checkout -f "$3" -B "build"
)

OMR_DIST=${OMR_DIST:-openmptcprouter}                   # 目标路径
OMR_HOST=${OMR_HOST:-$(curl -sS ifconfig.co)}           # 编译主机的公网IP
OMR_KEEPBIN=${OMR_KEEPBIN:-yes}                         # 保留上一次的编译产物
OMR_LOG=${OMR_LOG:-yes}                                 # 编译日志
OMR_TARGET=${OMR_TARGET:-rpi4}                        	# 目标平台
OMR_TARGET_CONFIG="config-$OMR_TARGET"                  # 目标平台配置文件
SYSLOG=${SYSLOG:-logd}                                  # 使用logd管理系统日志
OMR_KERNEL=${OMR_KERNEL:-6.6}                           # 内核版本

OMR_RELEASE=v0.63-snapshot    							# OMR_RELEASE=v0.63-snapshot

OMR_FEED_URL="${OMR_FEED_URL:-https://github.com/ysurac/openmptcprouter-feeds}"                     # OMR_FEED_URL=https://github.com/ysurac/openmptcprouter-feeds
OMR_FEED_SRC="${OMR_FEED_SRC:-master}"                  # 使用openmptcprouter的master分支

OMR_OPENWRT=${OMR_OPENWRT:-default}                     # OMR_OPENWRT=default
OMR_OPENWRT_GIT=${OMR_OPENWRT_GIT:-https://github.com}  # OMR_OPENWRT_GIT=https://github.com
OMR_FORCE_DSA=${OMR_FORCE_DSA:-0}                       # OMR_FORCE_DSA=0

# RPI CM4
if [ "$OMR_TARGET" = "rpi4" ]; then
	OMR_REAL_TARGET="aarch64_cortex-a72"
# RPI CM5
elif [ "$OMR_TARGET" = "rpi5" ]; then
	OMR_REAL_TARGET="aarch64_cortex-a76"
else
	OMR_REAL_TARGET=${OMR_TARGET}
fi

# 创建source目录
KERNEL_DIR=${OMR_TARGET}/${OMR_KERNEL}
mkdir -p ${KERNEL_DIR}
rm -rf ${KERNEL_DIR}/source && ln -s ${TOP_DIR}/submodules/openwrt ${KERNEL_DIR}/source

# 为各个模块创建软链接
mkdir -p ${KERNEL_DIR}/source/feeds/${OMR_KERNEL}
rm -rf ${KERNEL_DIR}/source/feeds/${OMR_KERNEL}/packages && ln -s ${TOP_DIR}/submodules/packages ${KERNEL_DIR}/source/feeds/${OMR_KERNEL}/packages
rm -rf ${KERNEL_DIR}/source/feeds/${OMR_KERNEL}/luci && ln -s ${TOP_DIR}/submodules/luci ${KERNEL_DIR}/source/feeds/${OMR_KERNEL}/luci
rm -rf ${KERNEL_DIR}/source/feeds/${OMR_KERNEL}/routing && ln -s ${TOP_DIR}/submodules/luci ${KERNEL_DIR}/source/feeds/${OMR_KERNEL}/routing
rm -rf ${KERNEL_DIR}/source/feeds/openmptcprouter && ln -s ${TOP_DIR}/submodules/openmptcprouter-feeds ${KERNEL_DIR}/source/feeds/openmptcprouter

if [ "$OMR_KEEPBIN" = "no" ]; then 
	rm -rf "$OMR_TARGET/${OMR_KERNEL}/source/bin"
fi

# QUESTION: 这个操作应该没用吧
# rm -rf "$OMR_TARGET/${OMR_KERNEL}/source/files" "$OMR_TARGET/${OMR_KERNEL}/source/tmp"
# echo "rm -rf $OMR_TARGET/${OMR_KERNEL}/source/package/boot/uboot-mvebu"
# rm -rf "${OMR_TARGET}/${OMR_KERNEL}/source/package/boot/uboot-mvebu"

# QUESTION: 这个操作应该没用吧
# echo "rm -rf $OMR_TARGET/${OMR_KERNEL}/source/package/boot/uboot-ipq40xx"
# rm -rf "${OMR_TARGET}/${OMR_KERNEL}/source/package/boot/uboot-ipq40xx"

# openmptcprouter/common,一些通用的脚本和文件
echo "cp -rf common/* $OMR_TARGET/${OMR_KERNEL}/source"
cp -rf common/* "$OMR_TARGET/${OMR_KERNEL}/source"
echo "cp -rf ${OMR_KERNEL}/* $OMR_TARGET/${OMR_KERNEL}/source"
cp -rf ${OMR_KERNEL}/* "$OMR_TARGET/${OMR_KERNEL}/source"

# 编译信息
cat >> "$OMR_TARGET/${OMR_KERNEL}/source/package/base-files/files/etc/version" <<EOF
-----------------------------------------------------
 PACKAGE:     $OMR_DIST
 VERSION:     $OMR_RELEASE
 TARGET:      $OMR_TARGET
 ARCH:        $OMR_REAL_TARGET

 BUILD REPO:  $(git config --get remote.origin.url)
 BUILD DATE:  $(date -u)
-----------------------------------------------------
EOF

# 编译时使用
cat > "$OMR_TARGET/${OMR_KERNEL}/source/feeds.conf" <<EOF
src-link packages $(readlink -f feeds/${OMR_KERNEL}/packages)
src-link luci $(readlink -f feeds/${OMR_KERNEL}/luci)
src-link openmptcprouter $(readlink -f feeds/openmptcprouter)
EOF

# 默认的feed软件源
# cat > "$OMR_TARGET/${OMR_KERNEL}/source/package/system/opkg/files/customfeeds.conf" <<-EOF
# src/gz openwrt_luci http://packages.openmptcprouter.com/${OMR_RELEASE}/${OMR_REAL_TARGET}/luci
# src/gz openwrt_packages http://packages.openmptcprouter.com/${OMR_RELEASE}/${OMR_REAL_TARGET}/packages
# src/gz openwrt_base http://packages.openmptcprouter.com/${OMR_RELEASE}/${OMR_REAL_TARGET}/base
# src/gz openwrt_routing http://packages.openmptcprouter.com/${OMR_RELEASE}/${OMR_REAL_TARGET}/routing
# src/gz openwrt_telephony http://packages.openmptcprouter.com/${OMR_RELEASE}/${OMR_REAL_TARGET}/telephony
# EOF

# 默认的feed软件源，更改为清华源
cat > "$OMR_TARGET/${OMR_KERNEL}/source/package/system/opkg/files/customfeeds.conf" <<-EOF
src/gz openwrt_core https://mirrors.tuna.tsinghua.edu.cn/openwrt/releases/22.03.3/targets/bcm27xx/bcm2711/packages
src/gz openwrt_base https://mirrors.tuna.tsinghua.edu.cn/openwrt/releases/22.03.3/packages/aarch64_cortex-a72/base
src/gz openwrt_luci https://mirrors.tuna.tsinghua.edu.cn/openwrt/releases/22.03.3/packages/aarch64_cortex-a72/luci
src/gz openwrt_packages https://mirrors.tuna.tsinghua.edu.cn/openwrt/releases/22.03.3/packages/aarch64_cortex-a72/packages
src/gz openwrt_routing https://mirrors.tuna.tsinghua.edu.cn/openwrt/releases/22.03.3/packages/aarch64_cortex-a72/routing
src/gz openwrt_telephony https://mirrors.tuna.tsinghua.edu.cn/openwrt/releases/22.03.3/packages/aarch64_cortex-a72/telephony
EOF

cd "$OMR_TARGET/${OMR_KERNEL}/source"

# 更新Makefile文件中的内核版本号为6.6
echo "Set to kernel 6.6 for bcm27xx"
find target/linux/bcm27xx -type f -name Makefile -exec sed -i 's%KERNEL_PATCHVER:=6.1%KERNEL_PATCHVER:=6.6%g' {} \;

# TODO: 为什么要删除这个模块？
# cd "../../.."
# rm -rf feeds/${OMR_KERNEL}/luci/modules/luci-mod-network

# 系统日志syslog功能相关补丁
# cd feeds/${OMR_KERNEL}
# if ! patch -Rf -N -p1 -s --dry-run < ../../patches/luci-syslog-6.10.patch; then
#     patch -N -p1 -s < ../../patches/luci-syslog-6.10.patch
# fi
# cd -

# unbound DNS域名解析日志相关补丁
# cd feeds/${OMR_KERNEL}
# if ! patch -Rf -N -p1 -s --dry-run < ../../patches/luci-unbound-logread.patch; then
# 	patch -N -p1 -s < ../../patches/luci-unbound-logread.patch
# fi
# cd -

# TODO: 为什么要先删除下面这些模块？？？
# [ -d feeds/${OMR_KERNEL}/${OMR_DIST}/luci-app-statistics ] && rm -rf feeds/${OMR_KERNEL}/luci/applications/luci-app-statistics
# [ -d feeds/${OMR_KERNEL}/${OMR_DIST}/luci-proto-modemmanager ] && rm -rf feeds/${OMR_KERNEL}/luci/protocols/luci-proto-modemmanager
# [ -d ${OMR_FEED}/libgpiod ] && rm -rf feeds/${OMR_KERNEL}/packages/libs/libgpiod
# [ -d ${OMR_FEED}/iperf3 ] && rm -rf feeds/${OMR_KERNEL}/packages/net/iperf3
# [ -d ${OMR_FEED}/golang ] && {
# 	rm -rf feeds/${OMR_KERNEL}/packages/lang/golang
# 	cp -r ${OMR_FEED}/golang feeds/${OMR_KERNEL}/packages/lang/
# }
# [ -d ${OMR_FEED}/openvpn ] && rm -rf feeds/${OMR_KERNEL}/packages/net/openvpn
# [ -d ${OMR_FEED}/iproute2 ] && rm -rf feeds/${OMR_KERNEL}/packages/network/utils/iproute2
# [ -d ${CUSTOM_FEED}/syslog-ng ] && rm -rf feeds/${OMR_KERNEL}/packages/admin/syslog-ng
# ([ "$OMR_KERNEL" = "6.6" ] || [ "$OMR_KERNEL" = "6.10" ]) && [ -d ${OMR_FEED}/xtables-addons ] && rm -rf feeds/${OMR_KERNEL}/packages/net/xtables-addons

# 奥克语语言支持
# echo "Add Occitan translation support"
# cd feeds/${OMR_KERNEL}
# if ! patch -Rf -N -p1 -s --dry-run < ../../patches/luci-occitan.patch; then
# 	patch -N -p1 -s < ../../patches/luci-occitan.patch
# fi

# Luci界面的多语言支持
cd ../..
[ -d $OMR_FEED/luci-base/po/oc ] && cp -rf $OMR_FEED/luci-base/po/oc feeds/${OMR_KERNEL}/luci/modules/luci-base/po/
echo "Done"

# 更新编译时的.config配置文件
cd "${TOP_DIR}/openmptcprouter/${OMR_TARGET}/${OMR_KERNEL}/source"
echo "Update feeds index"
cp ${TOP_DIR}/conf/rpi4/custom_conf .config && cp .config .config.keep


# scripts/feeds clean
# scripts/feeds update -a

# scripts/feeds install -a -d y -f -p openmptcprouter

cp .config.keep .config
scripts/feeds install kmod-macremapper
echo "Done"

echo "Building $OMR_DIST for the target $OMR_TARGET with kernel ${OMR_KERNEL}"
# make defconfig 		# 我已经生成了一个.config文件，这一步操作没有必要
make -j$(nproc) IGNORE_ERRORS=m "$@"
echo "Done"
