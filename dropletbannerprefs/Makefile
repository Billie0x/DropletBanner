TARGET := iphone:clang:latest:15.0
ARCHS = arm64 arm64e

include $(THEOS)/makefiles/common.mk

BUNDLE_NAME = DropletBannerPrefs
DropletBannerPrefs_FILES = DBRootListController.m
DropletBannerPrefs_FRAMEWORKS = UIKit
DropletBannerPrefs_PRIVATE_FRAMEWORKS = Preferences
DropletBannerPrefs_INSTALL_PATH = /Library/PreferenceBundles
DropletBannerPrefs_CFLAGS = -fobjc-arc

include $(THEOS_MAKE_PATH)/bundle.mk
