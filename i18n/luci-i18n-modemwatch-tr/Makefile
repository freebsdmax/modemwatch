include $(TOPDIR)/rules.mk

PKG_NAME:=luci-i18n-modemwatch-tr
PKG_VERSION:=1.0.5
PKG_RELEASE:=1
PKG_LICENSE:=MIT
PKG_MAINTAINER:=modemwatch contributors

include $(INCLUDE_DIR)/package.mk

define Package/luci-i18n-modemwatch-tr
  SECTION:=luci
  CATEGORY:=LuCI
  SUBMENU:=Translations
  TITLE:=Turkish translation for luci-app-modemwatch
  DEPENDS:=+luci-app-modemwatch +luci-base
  PKGARCH:=all
endef

define Package/luci-i18n-modemwatch-tr/description
  Turkish translation for the modemwatch LuCI application.
endef

define Build/Prepare
	mkdir -p $(PKG_BUILD_DIR)
endef

define Build/Compile
endef

define Package/luci-i18n-modemwatch-tr/install
	$(INSTALL_DIR) $(1)/usr/lib/lua/luci/i18n
	$(INSTALL_DATA) ./files/usr/lib/lua/luci/i18n/modemwatch.tr.lmo $(1)/usr/lib/lua/luci/i18n/modemwatch.tr.lmo
	$(INSTALL_DIR) $(1)/etc/uci-defaults
	$(INSTALL_BIN) ./files/etc/uci-defaults/luci-i18n-modemwatch-tr $(1)/etc/uci-defaults/luci-i18n-modemwatch-tr
endef

$(eval $(call BuildPackage,luci-i18n-modemwatch-tr))
