THEOS_PACKAGE_SCHEME ?= roothide
TARGET := iphone:clang:latest:15.0
ARCHS = arm64 arm64e
INSTALL_TARGET_PROCESSES = SpringBoard

include $(THEOS)/makefiles/common.mk

TWEAK_NAME = DropletBanner
DropletBanner_FILES = Tweak.x
DropletBanner_CFLAGS = -fobjc-arc -Wall
DropletBanner_FRAMEWORKS = UIKit QuartzCore CoreFoundation

SUBPROJECTS += dropletbannerprefs

include $(THEOS_MAKE_PATH)/tweak.mk
include $(THEOS_MAKE_PATH)/aggregate.mk
