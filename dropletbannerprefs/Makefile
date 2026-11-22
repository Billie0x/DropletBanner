TARGET := iphone:clang:16.5:15.0
ARCHS = arm64 arm64e

include $(THEOS)/makefiles/common.mk

BUNDLE_NAME = DropletBannerPrefs
DropletBannerPrefs_FILES = DBRootListController.m
DropletBannerPrefs_FRAMEWORKS = UIKit QuartzCore CoreGraphics CoreFoundation
DropletBannerPrefs_PRIVATE_FRAMEWORKS = Preferences
DropletBannerPrefs_INSTALL_PATH = /Library/PreferenceBundles
DropletBannerPrefs_CFLAGS = -fobjc-arc -Wall

include $(THEOS_MAKE_PATH)/bundle.mk

# THEOS_STAGING_DIR already includes the scheme prefix (e.g. /var/jb for rootless),
# so paths here must not add $(THEOS_PACKAGE_INSTALL_PREFIX) again.
PREFLOADER_DIR = $(THEOS_STAGING_DIR)/Library/PreferenceLoader/Preferences/DropletBanner

internal-stage::
	$(ECHO_NOTHING)mkdir -p "$(PREFLOADER_DIR)"$(ECHO_END)
	$(ECHO_NOTHING)cp entry.plist "$(PREFLOADER_DIR)/Root.plist"$(ECHO_END)
	$(ECHO_NOTHING)cp Resources/icon.png Resources/icon@2x.png Resources/icon@3x.png "$(PREFLOADER_DIR)/"$(ECHO_END)
