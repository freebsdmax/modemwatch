#!/bin/sh
# Build modemwatch and luci-app-modemwatch with the official OpenWrt SDK.
# Tested with OpenWrt 24.10.1, target ipq40xx/mikrotik (MikroTik hAP ac3).
set -eu

SDK_VERSION="24.10.1"
SDK_TARGET="ipq40xx/mikrotik"
SDK_FILE="openwrt-sdk-${SDK_VERSION}-ipq40xx-mikrotik_gcc-13.3.0_musl_eabi.Linux-x86_64.tar.zst"
SDK_DIR="${SDK_FILE%.tar.zst}"
SDK_URL="https://downloads.openwrt.org/releases/${SDK_VERSION}/targets/${SDK_TARGET}/${SDK_FILE}"

ROOT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)

if [ ! -d "$ROOT_DIR/$SDK_DIR" ]; then
	echo "==> Downloading OpenWrt SDK ${SDK_VERSION}"
	if command -v curl >/dev/null 2>&1; then
		curl -L -o "$ROOT_DIR/$SDK_FILE" "$SDK_URL"
	elif command -v wget >/dev/null 2>&1; then
		wget -O "$ROOT_DIR/$SDK_FILE" "$SDK_URL"
	else
		echo "curl or wget is required" >&2
		exit 1
	fi

	echo "==> Extracting SDK"
	tar --zstd -xf "$ROOT_DIR/$SDK_FILE" -C "$ROOT_DIR"
fi

cd "$ROOT_DIR/$SDK_DIR"

echo "==> Copying packages into SDK"
rm -rf package/modemwatch package/luci-app-modemwatch package/luci-i18n-modemwatch-uk
mkdir -p package/modemwatch package/luci-app-modemwatch package/luci-i18n-modemwatch-uk
cp -r "$ROOT_DIR/modemwatch/." package/modemwatch/
cp -r "$ROOT_DIR/luci-app-modemwatch/." package/luci-app-modemwatch/
cp -r "$ROOT_DIR/luci-i18n-modemwatch-uk/." package/luci-i18n-modemwatch-uk/

echo "==> Building"
make defconfig
make package/modemwatch/compile V=s
make package/luci-app-modemwatch/compile V=s
make package/luci-i18n-modemwatch-uk/compile V=s

echo "==> Built packages:"
find bin/packages -type f \( -name 'modemwatch*.ipk' -o -name 'luci-app-modemwatch*.ipk' -o -name 'luci-i18n-modemwatch-uk*.ipk' \) -print
