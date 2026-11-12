include $(TOPDIR)/rules.mk

PKG_NAME:=luci-i18n-modemwatch-zh-cn
PKG_VERSION:=1.0.6
PKG_RELEASE:=1
PKG_LICENSE:=MIT
PKG_MAINTAINER:=modemwatch contributors

include $(INCLUDE_DIR)/package.mk

define Package/luci-i18n-modemwatch-zh-cn
  SECTION:=luci
  CATEGORY:=LuCI
  SUBMENU:=Translations
  TITLE:=Simplified Chinese translation for luci-app-modemwatch
  DEPENDS:=+luci-app-modemwatch +luci-base
  PKGARCH:=all
endef

define Package/luci-i18n-modemwatch-zh-cn/description
  Simplified Chinese translation for the modemwatch LuCI application.
endef

define Build/Prepare
	mkdir -p $(PKG_BUILD_DIR)
endef

define Build/Compile
endef

define Package/luci-i18n-modemwatch-zh-cn/install
	$(INSTALL_DIR) $(1)/usr/lib/lua/luci/i18n
	$(INSTALL_DATA) ./files/usr/lib/lua/luci/i18n/modemwatch.zh-cn.lmo $(1)/usr/lib/lua/luci/i18n/modemwatch.zh-cn.lmo
	$(INSTALL_DIR) $(1)/etc/uci-defaults
	$(INSTALL_BIN) ./files/etc/uci-defaults/luci-i18n-modemwatch-zh-cn $(1)/etc/uci-defaults/luci-i18n-modemwatch-zh-cn
endef

$(eval $(call BuildPackage,luci-i18n-modemwatch-zh-cn))
