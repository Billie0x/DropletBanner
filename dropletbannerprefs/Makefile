TARGET := iphone:clang:16.5:15.0
ARCHS = arm64 arm64e

include $(THEOS)/makefiles/common.mk

BUNDLE_NAME = DropletBannerPrefs
DropletBannerPrefs_FILES = DBRootListController.m
DropletBannerPrefs_FRAMEWORKS = UIKit QuartzCore
DropletBannerPrefs_PRIVATE_FRAMEWORKS = Preferences
DropletBannerPrefs_INSTALL_PATH = /Library/PreferenceBundles
DropletBannerPrefs_CFLAGS = -fobjc-arc

include $(THEOS_MAKE_PATH)/bundle.mk

internal-stage:: ; mkdir -p $(THEOS_STAGING_DIR)$(THEOS_PACKAGE_INSTALL_PREFIX)/Library/PreferenceLoader/Preferences/DropletBanner && cp entry.plist $(THEOS_STAGING_DIR)$(THEOS_PACKAGE_INSTALL_PREFIX)/Library/PreferenceLoader/Preferences/DropletBanner/Root.plist && cp Resources/icon.png Resources/icon@2x.png Resources/icon@3x.png $(THEOS_STAGING_DIR)$(THEOS_PACKAGE_INSTALL_PREFIX)/Library/PreferenceLoader/Preferences/DropletBanner/
