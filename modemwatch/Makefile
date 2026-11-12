include $(TOPDIR)/rules.mk

PKG_NAME:=modemwatch
PKG_VERSION:=1.0.5
PKG_RELEASE:=1
PKG_LICENSE:=MIT
PKG_MAINTAINER:=modemwatch contributors

include $(INCLUDE_DIR)/package.mk

define Package/modemwatch
  SECTION:=utils
  CATEGORY:=Utilities
  TITLE:=Quectel modem watchdog with internet check
  DEPENDS:=+picocom +sms-tool +ubus
  PKGARCH:=all
endef

define Package/modemwatch/description
  Lightweight OpenWrt service for Quectel LTE modems.

  It checks internet connectivity, sends AT+CFUN=1,1 to the modem after a
  configurable number of failures, rate-limits reboots, and exposes status
  through a small CLI and a LuCI web interface.
endef

define Package/modemwatch/postinst
#!/bin/sh
[ -n "$${IPKG_INSTROOT}" ] && exit 0
echo "modemwatch: dependencies / залежності: picocom sms-tool ubus"
missing=""
for p in picocom sms-tool; do
	case "$$p" in
		sms-tool) command -v sms_tool >/dev/null 2>&1 || missing="$$missing $$p" ;;
		*) command -v "$$p" >/dev/null 2>&1 || missing="$$missing $$p" ;;
	esac
done
command -v ubus >/dev/null 2>&1 || missing="$$missing ubus"
if [ -n "$$missing" ]; then
	echo "modemwatch: missing / не вистачає:$$missing"
	if command -v apk >/dev/null 2>&1; then
		echo "modemwatch: install / встановіть: apk update && apk add$$missing"
	else
		echo "modemwatch: install / встановіть: opkg update && opkg install$$missing"
	fi
fi
exit 0
endef

define Build/Prepare
	mkdir -p $(PKG_BUILD_DIR)
endef

define Build/Compile
endef

define Package/modemwatch/install
	$(INSTALL_DIR) $(1)/etc/config
	$(INSTALL_CONF) ./files/etc/config/modemwatch $(1)/etc/config/modemwatch
	$(INSTALL_DIR) $(1)/etc/init.d
	$(INSTALL_BIN) ./files/etc/init.d/modemwatch $(1)/etc/init.d/modemwatch
	$(INSTALL_DIR) $(1)/usr/bin
	$(INSTALL_BIN) ./files/usr/bin/modemwatch.sh $(1)/usr/bin/modemwatch.sh
endef

$(eval $(call BuildPackage,modemwatch))
