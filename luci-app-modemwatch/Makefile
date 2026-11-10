include $(TOPDIR)/rules.mk

PKG_NAME:=luci-app-modemwatch
PKG_VERSION:=1.0.2
PKG_RELEASE:=1
PKG_LICENSE:=MIT
PKG_MAINTAINER:=modemwatch contributors

LUCI_TITLE:=LuCI interface for Modem LTE 4G
LUCI_DESCRIPTION:=Web UI for the modemwatch service
LUCI_DEPENDS:=+modemwatch +luci-compat +luci-lua-runtime +luci-lib-jsonc +luci-lib-nixio +curl +ca-bundle
LUCI_PKGARCH:=all
PKGARCH:=all

define Package/luci-app-modemwatch/postinst
#!/bin/sh
[ -n "$${IPKG_INSTROOT}" ] || {
	rm -f /tmp/luci-indexcache.*
	rm -rf /tmp/luci-modulecache/
	/etc/init.d/rpcd reload 2>/dev/null
}
echo "luci-app-modemwatch: dependencies / залежності: modemwatch luci-compat luci-lua-runtime luci-lib-jsonc luci-lib-nixio curl ca-bundle"
missing=""
for p in modemwatch luci-compat luci-lua-runtime luci-lib-jsonc luci-lib-nixio curl ca-bundle; do
	if command -v apk >/dev/null 2>&1; then
		apk info -e "$$p" >/dev/null 2>&1 || missing="$$missing $$p"
	elif command -v opkg >/dev/null 2>&1; then
		opkg list-installed "$$p" 2>/dev/null | grep -q "^$$p " || missing="$$missing $$p"
	fi
done
if [ -n "$$missing" ]; then
	echo "luci-app-modemwatch: missing / не вистачає:$$missing"
	if command -v apk >/dev/null 2>&1; then
		echo "luci-app-modemwatch: install / встановіть: apk update && apk add$$missing"
	else
		echo "luci-app-modemwatch: install / встановіть: opkg update && opkg install$$missing"
	fi
fi
exit 0
endef

include $(TOPDIR)/feeds/luci/luci.mk

# call BuildPackage - OpenWrt buildroot signature
