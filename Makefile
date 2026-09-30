include $(TOPDIR)/rules.mk

PKG_NAME:=piratebox
PKG_VERSION:=1.0.0
PKG_RELEASE:=1
PKG_MAINTAINER:=PirateBoxWRT
PKG_BUILD_DIR:=$(BUILD_DIR)/$(PKG_NAME)

include $(INCLUDE_DIR)/package.mk

define Package/piratebox
  SECTION:=net
  CATEGORY:=Network
  TITLE:=PirateBox - file sharing, forum e chat anonimi e offline
  DEPENDS:=+ucode +ucode-mod-fs +uhttpd
  PKGARCH:=all
endef

define Package/piratebox/conffiles
/etc/config/piratebox
endef

define Build/Prepare
	mkdir -p $(PKG_BUILD_DIR)
endef

define Build/Compile
endef

define Package/piratebox/install
	$(CP) ./root/* $(1)/
	$(INSTALL_DATA) ./PirateBox-logo.svg $(1)/www/piratebox/logo.svg
endef

define Package/piratebox/postinst
#!/bin/sh
[ -n "$${IPKG_INSTROOT}" ] || /usr/sbin/piratebox-setup
exit 0
endef

define Package/piratebox/prerm
#!/bin/sh
[ -n "$${IPKG_INSTROOT}" ] || /usr/sbin/piratebox-setup --remove
exit 0
endef

$(eval $(call BuildPackage,piratebox))
