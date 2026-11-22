#import <UIKit/UIKit.h>
#import <QuartzCore/QuartzCore.h>
#import <CoreGraphics/CoreGraphics.h>
#import <CoreFoundation/CoreFoundation.h>
#import <CoreMotion/CoreMotion.h>
#import <objc/runtime.h>
#import <math.h>

#pragma mark - Private SpringBoard / BannerKit Declarations

@protocol BNPresentable <NSObject>
@optional
- (UIViewController *)notificationViewController;
- (UIViewController *)viewController;
- (id)notificationRequest;
@end

@interface SBNotificationBannerDestination : NSObject
- (void)presentableWillAppearAsBanner:(id<BNPresentable>)presentable;
- (void)presentableWillDisappearAsBanner:(id<BNPresentable>)presentable withReason:(NSString *)reason;
@end

@interface NCNotificationShortLookViewController : UIViewController
- (id)notificationRequest;
@end

@interface UIImage (DBPrivateAppIcon)
+ (UIImage *)_applicationIconImageForBundleIdentifier:(NSString *)bundleIdentifier format:(int)format scale:(CGFloat)scale;
@end

#pragma mark - Preferences

static NSString *const kPrefsDomain = @"com.billie.dropletbanner";
static NSString *const kPrefsChangedNotification = @"com.billie.dropletbanner/prefsChanged";
static NSString *const kTestPreviewNotification = @"com.billie.dropletbanner/testPreview";

typedef NS_ENUM(NSInteger, DBDropletColorMode) {
    DBDropletColorModeBlack = 0,
    DBDropletColorModeAppIcon = 1,
    DBDropletColorModeCustom = 2,
};

typedef NS_ENUM(NSInteger, DBPhysicsPreset) {
    DBPhysicsPresetSnappy = 0,
    DBPhysicsPresetLiquid = 1,
    DBPhysicsPresetBouncy = 2,
    DBPhysicsPresetCustom = 3,
};

static BOOL gEnabled = YES;
static BOOL gAnimateDismiss = YES;
static NSInteger gPhysicsPreset = DBPhysicsPresetLiquid;
static double gEntryDuration = 0.48;
static double gAmplitude = 1.0;

static NSInteger gDropletColorMode = DBDropletColorModeAppIcon;
static UIColor *gCustomDropletColor = nil;

static BOOL gBloomRimEnabled = YES;
static double gBloomRimWidth = 1.4;
static double gBloomRimDuration = 0.38;

static BOOL gIslandRecoilEnabled = YES;
static double gIslandRecoilIntensity = 1.0;

static BOOL gMagneticSwipeNeckEnabled = YES;
static double gMagneticNeckStrength = 1.0;

static BOOL gGyroCurveEnabled = YES;
static double gGyroCurveIntensity = 1.0;

static BOOL gHapticsEnabled = YES;
static NSInteger gHapticStrength = 0; // 0: Soft, 1: Light, 2: Medium, 3: Rigid

static BOOL gPauseInLowPowerMode = YES;
static BOOL gPauseInLandscape = YES;

static BOOL gExcludedAppsEnabled = YES;
static NSSet<NSString *> *gExcludedBundleIDs = nil;

static UIColor *DBColorFromHexString(NSString *hexString) {
    if (![hexString isKindOfClass:[NSString class]] || hexString.length == 0) {
        return [UIColor colorWithRed:0.039 green:0.518 blue:1.0 alpha:1.0]; // #0A84FF
    }
    NSString *clean = [[hexString stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]] uppercaseString];
    if ([clean hasPrefix:@"#"]) {
        clean = [clean substringFromIndex:1];
    }
    if (clean.length != 6) {
        return [UIColor colorWithRed:0.039 green:0.518 blue:1.0 alpha:1.0];
    }
    unsigned int rgb = 0;
    NSScanner *scanner = [NSScanner scannerWithString:clean];
    if (![scanner scanHexInt:&rgb]) {
        return [UIColor colorWithRed:0.039 green:0.518 blue:1.0 alpha:1.0];
    }
    CGFloat r = ((rgb >> 16) & 0xFF) / 255.0;
    CGFloat g = ((rgb >> 8) & 0xFF) / 255.0;
    CGFloat b = (rgb & 0xFF) / 255.0;
    return [UIColor colorWithRed:r green:g blue:b alpha:1.0];
}

static void DBLoadPreferences(void) {
    CFPreferencesAppSynchronize((__bridge CFStringRef)kPrefsDomain);

    id enabledObj = CFBridgingRelease(CFPreferencesCopyAppValue(CFSTR("Enabled"), (__bridge CFStringRef)kPrefsDomain));
    gEnabled = enabledObj ? [enabledObj boolValue] : YES;

    id dismissObj = CFBridgingRelease(CFPreferencesCopyAppValue(CFSTR("AnimateDismiss"), (__bridge CFStringRef)kPrefsDomain));
    gAnimateDismiss = dismissObj ? [dismissObj boolValue] : YES;

    id presetObj = CFBridgingRelease(CFPreferencesCopyAppValue(CFSTR("PhysicsPreset"), (__bridge CFStringRef)kPrefsDomain));
    gPhysicsPreset = presetObj ? [presetObj integerValue] : DBPhysicsPresetLiquid;

    id durObj = CFBridgingRelease(CFPreferencesCopyAppValue(CFSTR("EntryDuration"), (__bridge CFStringRef)kPrefsDomain));
    id ampObj = CFBridgingRelease(CFPreferencesCopyAppValue(CFSTR("DropletAmplitude"), (__bridge CFStringRef)kPrefsDomain));

    if (gPhysicsPreset == DBPhysicsPresetSnappy) {
        gEntryDuration = 0.34;
        gAmplitude = 0.75;
    } else if (gPhysicsPreset == DBPhysicsPresetLiquid) {
        gEntryDuration = 0.48;
        gAmplitude = 1.00;
    } else if (gPhysicsPreset == DBPhysicsPresetBouncy) {
        gEntryDuration = 0.58;
        gAmplitude = 1.38;
    } else {
        gEntryDuration = durObj ? fmin(fmax([durObj doubleValue], 0.25), 0.90) : 0.48;
        gAmplitude = ampObj ? fmin(fmax([ampObj doubleValue], 0.40), 1.60) : 1.0;
    }

    // Color mode with seamless backwards-compatibility for v1.7.0 TintDropletWithAppIcon key
    id colorModeObj = CFBridgingRelease(CFPreferencesCopyAppValue(CFSTR("DropletColorMode"), (__bridge CFStringRef)kPrefsDomain));
    if (colorModeObj) {
        NSInteger m = [colorModeObj integerValue];
        gDropletColorMode = (m >= 0 && m <= 2) ? m : DBDropletColorModeAppIcon;
    } else {
        id legacyTintObj = CFBridgingRelease(CFPreferencesCopyAppValue(CFSTR("TintDropletWithAppIcon"), (__bridge CFStringRef)kPrefsDomain));
        BOOL legacyTint = legacyTintObj ? [legacyTintObj boolValue] : YES;
        gDropletColorMode = legacyTint ? DBDropletColorModeAppIcon : DBDropletColorModeBlack;
    }

    id hexObj = CFBridgingRelease(CFPreferencesCopyAppValue(CFSTR("CustomDropletColorHex"), (__bridge CFStringRef)kPrefsDomain));
    gCustomDropletColor = DBColorFromHexString([hexObj isKindOfClass:[NSString class]] ? (NSString *)hexObj : @"#0A84FF");

    // Bloom Rim Accent
    id rimEnabledObj = CFBridgingRelease(CFPreferencesCopyAppValue(CFSTR("BloomRimEnabled"), (__bridge CFStringRef)kPrefsDomain));
    gBloomRimEnabled = rimEnabledObj ? [rimEnabledObj boolValue] : YES;

    id rimWidthObj = CFBridgingRelease(CFPreferencesCopyAppValue(CFSTR("BloomRimWidth"), (__bridge CFStringRef)kPrefsDomain));
    gBloomRimWidth = rimWidthObj ? fmin(fmax([rimWidthObj doubleValue], 0.8), 3.0) : 1.4;

    id rimDurObj = CFBridgingRelease(CFPreferencesCopyAppValue(CFSTR("BloomRimDuration"), (__bridge CFStringRef)kPrefsDomain));
    gBloomRimDuration = rimDurObj ? fmin(fmax([rimDurObj doubleValue], 0.20), 0.75) : 0.38;

    // Dynamic Island Recoil Pulse
    id recoilObj = CFBridgingRelease(CFPreferencesCopyAppValue(CFSTR("IslandRecoilEnabled"), (__bridge CFStringRef)kPrefsDomain));
    gIslandRecoilEnabled = recoilObj ? [recoilObj boolValue] : YES;

    id recoilIntObj = CFBridgingRelease(CFPreferencesCopyAppValue(CFSTR("IslandRecoilIntensity"), (__bridge CFStringRef)kPrefsDomain));
    gIslandRecoilIntensity = recoilIntObj ? fmin(fmax([recoilIntObj doubleValue], 0.3), 2.0) : 1.0;

    // Magnetic Swipe-Up Neck
    id magEnabledObj = CFBridgingRelease(CFPreferencesCopyAppValue(CFSTR("MagneticSwipeNeckEnabled"), (__bridge CFStringRef)kPrefsDomain));
    gMagneticSwipeNeckEnabled = magEnabledObj ? [magEnabledObj boolValue] : YES;

    id magStrengthObj = CFBridgingRelease(CFPreferencesCopyAppValue(CFSTR("MagneticNeckStrength"), (__bridge CFStringRef)kPrefsDomain));
    gMagneticNeckStrength = magStrengthObj ? fmin(fmax([magStrengthObj doubleValue], 0.5), 2.0) : 1.0;

    // Gyro-Reactive Droplet Curve
    id gyroEnabledObj = CFBridgingRelease(CFPreferencesCopyAppValue(CFSTR("GyroCurveEnabled"), (__bridge CFStringRef)kPrefsDomain));
    gGyroCurveEnabled = gyroEnabledObj ? [gyroEnabledObj boolValue] : YES;

    id gyroIntObj = CFBridgingRelease(CFPreferencesCopyAppValue(CFSTR("GyroCurveIntensity"), (__bridge CFStringRef)kPrefsDomain));
    gGyroCurveIntensity = gyroIntObj ? fmin(fmax([gyroIntObj doubleValue], 0.3), 2.0) : 1.0;

    // Neck-Snap Micro-Haptic
    id hapticsObj = CFBridgingRelease(CFPreferencesCopyAppValue(CFSTR("HapticsEnabled"), (__bridge CFStringRef)kPrefsDomain));
    gHapticsEnabled = hapticsObj ? [hapticsObj boolValue] : YES;

    id hapticStyleObj = CFBridgingRelease(CFPreferencesCopyAppValue(CFSTR("HapticStrength"), (__bridge CFStringRef)kPrefsDomain));
    gHapticStrength = hapticStyleObj ? [hapticStyleObj integerValue] : 0;

    // Smart Auto-Pause
    id lpmObj = CFBridgingRelease(CFPreferencesCopyAppValue(CFSTR("PauseInLowPowerMode"), (__bridge CFStringRef)kPrefsDomain));
    gPauseInLowPowerMode = lpmObj ? [lpmObj boolValue] : YES;

    id landObj = CFBridgingRelease(CFPreferencesCopyAppValue(CFSTR("PauseInLandscape"), (__bridge CFStringRef)kPrefsDomain));
    gPauseInLandscape = landObj ? [landObj boolValue] : YES;

    // Per-App Exclusions
    id exclEnabledObj = CFBridgingRelease(CFPreferencesCopyAppValue(CFSTR("ExcludedAppsEnabled"), (__bridge CFStringRef)kPrefsDomain));
    gExcludedAppsEnabled = exclEnabledObj ? [exclEnabledObj boolValue] : YES;

    id exclListObj = CFBridgingRelease(CFPreferencesCopyAppValue(CFSTR("ExcludedBundleIDs"), (__bridge CFStringRef)kPrefsDomain));
    if ([exclListObj isKindOfClass:[NSArray class]]) {
        NSMutableSet<NSString *> *set = [NSMutableSet set];
        for (id item in (NSArray *)exclListObj) {
            if ([item isKindOfClass:[NSString class]] && ((NSString *)item).length > 0) {
                [set addObject:(NSString *)item];
            }
        }
        gExcludedBundleIDs = [set copy];
    } else {
        gExcludedBundleIDs = [NSSet set];
    }
}

static void DBPrefsChangedCallback(CFNotificationCenterRef center, void *observer, CFStringRef name, const void *object, CFDictionaryRef userInfo) {
    DBLoadPreferences();
}

static BOOL DBShouldSkipGlobally(void) {
    if (!gEnabled) return YES;
    if (UIAccessibilityIsReduceMotionEnabled()) return YES;
    if (gPauseInLowPowerMode && [NSProcessInfo processInfo].lowPowerModeEnabled) return YES;
    return NO;
}

#pragma mark - Droplet Spring & Geometry Helpers

static inline double DBClamp01(double x) {
    return x < 0.0 ? 0.0 : (x > 1.0 ? 1.0 : x);
}

static inline double DBLerp(double a, double b, double t) {
    return a + (b - a) * t;
}

static inline double DBSpringCurve(double u, double decay, double freq, double sinAmp) {
    if (u <= 0.0) return 0.0;
    if (u >= 1.0) return 1.0;
    return 1.0 - exp(-decay * u) * (cos(freq * u) + sinAmp * sin(freq * u));
}

static UIImpactFeedbackStyle DBCurrentImpactStyle(void) {
    switch (gHapticStrength) {
        case 1: return UIImpactFeedbackStyleLight;
        case 2: return UIImpactFeedbackStyleMedium;
        case 3: return UIImpactFeedbackStyleRigid;
        case 0:
        default: return UIImpactFeedbackStyleSoft;
    }
}

static CGRect DBResolveCutoutRectForWindow(UIWindow *window) {
    CGSize size = window.bounds.size;
    CGFloat topInset = window.safeAreaInsets.top;
    CGFloat midX = size.width * 0.5;

    // Landscape top-center fallback when user disables PauseInLandscape
    if (size.width > size.height) {
        CGFloat pillW = 112.0;
        CGFloat pillH = 24.0;
        return CGRectMake(midX - pillW * 0.5, 4.0, pillW, pillH);
    }

    // Dynamic Island devices (iPhone 14 Pro / 15 / 16 series)
    if (topInset >= 52.0) {
        CGFloat islandW = 126.0;
        CGFloat islandH = 37.0;
        CGFloat islandY = 11.0;
        return CGRectMake(midX - islandW * 0.5, islandY, islandW, islandH);
    }

    // Notched Face ID devices (iPhone X - 14)
    if (topInset >= 40.0) {
        CGFloat notchW = 112.0;
        CGFloat notchH = 30.0;
        return CGRectMake(midX - notchW * 0.5, 0.0, notchW, notchH);
    }

    CGFloat fallbackW = 104.0;
    CGFloat fallbackH = 24.0;
    return CGRectMake(midX - fallbackW * 0.5, 4.0, fallbackW, fallbackH);
}

static UIView *DBFindCardView(UIView *root, UIWindow *win) {
    if (!root || !win) return root;
    CGSize winSize = win.bounds.size;
    CGRect rootRect = [root convertRect:root.bounds toCoordinateSpace:win.coordinateSpace];
    if (rootRect.size.height < winSize.height * 0.50 && rootRect.size.width >= 120.0 && rootRect.size.height >= 34.0) {
        return root;
    }

    NSMutableArray<UIView *> *queue = [NSMutableArray arrayWithObject:root];
    NSInteger inspected = 0;
    while (queue.count > 0 && inspected < 45) {
        UIView *cur = queue.firstObject;
        [queue removeObjectAtIndex:0];
        inspected++;

        for (UIView *sub in cur.subviews) {
            CGRect r = [sub convertRect:sub.bounds toCoordinateSpace:win.coordinateSpace];
            if (r.size.width >= winSize.width * 0.55 &&
                r.size.height >= 42.0 &&
                r.size.height <= 260.0) {
                return sub;
            }
            [queue addObject:sub];
        }
    }
    return root;
}

static UIView *DBFindPerBannerContainer(UIView *cardView, UIWindow *win) {
    if (!cardView || !win) return cardView;
    CGSize winSize = win.bounds.size;
    UIView *surface = cardView;
    UIView *cur = cardView.superview;
    while (cur && cur != win) {
        CGRect r = cur.bounds;
        if (r.size.height >= 30.0 && r.size.height < winSize.height * 0.50 && r.size.width >= 120.0) {
            surface = cur;
        } else {
            break;
        }
        cur = cur.superview;
    }
    return surface;
}

static CGFloat DBResolveCornerRadius(UIView *view) {
    CGFloat r = view.layer.cornerRadius;
    if (r >= 14.0) return r;
    for (UIView *sub in view.subviews) {
        if (sub.layer.cornerRadius >= 14.0 && CGRectGetWidth(sub.bounds) > CGRectGetWidth(view.bounds) * 0.75) {
            return sub.layer.cornerRadius;
        }
    }
    return 26.0;
}

static UIImage *DBSnapshotView(UIView *view) {
    if (!view || CGRectIsEmpty(view.bounds)) return nil;
    UIGraphicsImageRendererFormat *fmt = [UIGraphicsImageRendererFormat defaultFormat];
    fmt.opaque = NO;
    fmt.scale = [UIScreen mainScreen].scale;
    UIGraphicsImageRenderer *renderer = [[UIGraphicsImageRenderer alloc] initWithSize:view.bounds.size format:fmt];
    return [renderer imageWithActions:^(UIGraphicsImageRendererContext *ctx) {
        [view drawViewHierarchyInRect:view.bounds afterScreenUpdates:NO];
    }];
}

#pragma mark - App Bundle ID & Dominant Color Extraction

static NSCache<NSString *, UIColor *> *gIconColorCache = nil;
static const void *kDBViewDropletColorKey = &kDBViewDropletColorKey;

static id DBSafeValueForKey(id obj, NSString *key) {
    if (!obj || !key) return nil;
    SEL sel = NSSelectorFromString(key);
    if ([obj respondsToSelector:sel]) {
        @try {
            return [obj valueForKey:key];
        } @catch (NSException *exception) {
            return nil;
        }
    }
    return nil;
}

static NSString *DBExtractSectionIdentifier(id sourceObj) {
    if (!sourceObj) return nil;
    id req = DBSafeValueForKey(sourceObj, @"notificationRequest");
    if (!req) {
        id vc = DBSafeValueForKey(sourceObj, @"notificationViewController");
        if (vc) {
            req = DBSafeValueForKey(vc, @"notificationRequest");
        }
    }
    id rawSectionID = DBSafeValueForKey(req, @"sectionIdentifier");
    if ([rawSectionID isKindOfClass:[NSString class]] && ((NSString *)rawSectionID).length > 0) {
        return (NSString *)rawSectionID;
    }
    return nil;
}

static BOOL DBIsSourceExcluded(id sourceObj) {
    if (!gExcludedAppsEnabled || gExcludedBundleIDs.count == 0) return NO;
    NSString *sectionID = DBExtractSectionIdentifier(sourceObj);
    if (sectionID && [gExcludedBundleIDs containsObject:sectionID]) {
        return YES;
    }
    return NO;
}

static UIColor *DBExtractDominantColorFromImage(UIImage *image) {
    if (!image) return nil;
    CGImageRef cgImg = image.CGImage;
    if (!cgImg) return nil;

    enum { kDBIconDim = 16, kDBHueBins = 24 };
    const size_t dim = kDBIconDim;
    uint8_t pixels[kDBIconDim * kDBIconDim * 4];
    memset(pixels, 0, sizeof(pixels));

    CGColorSpaceRef cs = CGColorSpaceCreateDeviceRGB();
    CGContextRef ctx = CGBitmapContextCreate(
        pixels,
        dim,
        dim,
        8,
        dim * 4,
        cs,
        kCGImageAlphaPremultipliedLast | kCGBitmapByteOrder32Big
    );
    CGColorSpaceRelease(cs);
    if (!ctx) return nil;

    CGContextSetInterpolationQuality(ctx, kCGInterpolationLow);
    CGContextDrawImage(ctx, CGRectMake(0, 0, dim, dim), cgImg);
    CGContextRelease(ctx);

    const int kBins = kDBHueBins;
    double binWeight[kDBHueBins] = {0};
    double binR[kDBHueBins] = {0};
    double binG[kDBHueBins] = {0};
    double binB[kDBHueBins] = {0};

    double totalColorfulWeight = 0.0;
    double neutralWeight = 0.0;
    double neutralR = 0.0, neutralG = 0.0, neutralB = 0.0;

    for (size_t i = 0; i < dim * dim; i++) {
        double a = pixels[i * 4 + 3] / 255.0;
        if (a < 0.55) continue;

        double r = fmin(1.0, (pixels[i * 4 + 0] / 255.0) / a);
        double g = fmin(1.0, (pixels[i * 4 + 1] / 255.0) / a);
        double b = fmin(1.0, (pixels[i * 4 + 2] / 255.0) / a);

        double maxC = fmax(r, fmax(g, b));
        double minC = fmin(r, fmin(g, b));
        double delta = maxC - minC;
        double sat = (maxC > 0.001) ? (delta / maxC) : 0.0;
        double val = maxC;

        neutralR += r;
        neutralG += g;
        neutralB += b;
        neutralWeight += 1.0;

        if (sat < 0.18 || val < 0.14) continue;

        double hue = 0.0;
        if (delta > 0.0001) {
            if (maxC == r) {
                hue = fmod(((g - b) / delta), 6.0);
            } else if (maxC == g) {
                hue = ((b - r) / delta) + 2.0;
            } else {
                hue = ((r - g) / delta) + 4.0;
            }
            hue *= 60.0;
            if (hue < 0.0) hue += 360.0;
        }

        int bin = (int)floor(hue / (360.0 / kBins)) % kBins;
        if (bin < 0) bin += kBins;

        double w = (sat * sat) * (0.35 + 0.65 * val);
        binWeight[bin] += w;
        binR[bin] += r * w;
        binG[bin] += g * w;
        binB[bin] += b * w;
        totalColorfulWeight += w;
    }

    if (totalColorfulWeight > 1.2) {
        int bestBin = 0;
        double bestScore = -1.0;
        for (int b = 0; b < kBins; b++) {
            int prev = (b + kBins - 1) % kBins;
            int next = (b + 1) % kBins;
            double score = binWeight[b] + 0.45 * (binWeight[prev] + binWeight[next]);
            if (score > bestScore) {
                bestScore = score;
                bestBin = b;
            }
        }

        int prev = (bestBin + kBins - 1) % kBins;
        int next = (bestBin + 1) % kBins;
        double wSum = binWeight[bestBin] + 0.45 * (binWeight[prev] + binWeight[next]);
        if (wSum > 0.001) {
            double r = (binR[bestBin] + 0.45 * (binR[prev] + binR[next])) / wSum;
            double g = (binG[bestBin] + 0.45 * (binG[prev] + binG[next])) / wSum;
            double b = (binB[bestBin] + 0.45 * (binB[prev] + binB[next])) / wSum;

            UIColor *rawColor = [UIColor colorWithRed:r green:g blue:b alpha:1.0];
            CGFloat h = 0, s = 0, v = 0, al = 1.0;
            if ([rawColor getHue:&h saturation:&s brightness:&v alpha:&al]) {
                s = fmin(0.92, fmax(s, 0.58));
                v = fmin(0.94, fmax(v, 0.52));
                return [UIColor colorWithHue:h saturation:s brightness:v alpha:1.0];
            }
            return rawColor;
        }
    }

    if (neutralWeight > 0.5) {
        double lum = (0.299 * neutralR + 0.587 * neutralG + 0.114 * neutralB) / neutralWeight;
        if (lum < 0.28) {
            return [UIColor blackColor];
        }
        CGFloat gray = (CGFloat)fmin(0.84, fmax(0.45, lum));
        return [UIColor colorWithWhite:gray alpha:1.0];
    }

    return nil;
}

static UIImage *DBFindAppIconImageInView(UIView *cardView, UIWindow *win) {
    if (!cardView || !win) return nil;
    CGRect cardInWin = [cardView convertRect:cardView.bounds toCoordinateSpace:win.coordinateSpace];
    if (CGRectIsEmpty(cardInWin)) return nil;

    UIImage *bestImage = nil;
    CGFloat bestScore = -1.0;

    NSMutableArray<UIView *> *queue = [NSMutableArray arrayWithObject:cardView];
    NSInteger inspected = 0;
    while (queue.count > 0 && inspected < 75) {
        UIView *cur = queue.firstObject;
        [queue removeObjectAtIndex:0];
        inspected++;

        if ([cur isKindOfClass:[UIImageView class]]) {
            UIImageView *iv = (UIImageView *)cur;
            if (iv.image && iv.image.CGImage) {
                CGRect r = [iv convertRect:iv.bounds toCoordinateSpace:win.coordinateSpace];
                CGFloat w = r.size.width;
                CGFloat h = r.size.height;
                if (w >= 18.0 && w <= 56.0 && h >= 18.0 && h <= 56.0) {
                    CGFloat ratio = w / fmax(1.0, h);
                    if (ratio >= 0.78 && ratio <= 1.28) {
                        CGFloat relX = (CGRectGetMidX(r) - CGRectGetMinX(cardInWin)) / fmax(1.0, CGRectGetWidth(cardInWin));
                        CGFloat edgeBonus = (relX <= 0.35 || relX >= 0.65) ? 40.0 : 0.0;
                        CGFloat sizeBonus = 30.0 - fabs(w - 38.0);
                        CGFloat score = edgeBonus + sizeBonus;
                        if (score > bestScore) {
                            bestScore = score;
                            bestImage = iv.image;
                        }
                    }
                }
            }
        }

        for (UIView *sub in cur.subviews) {
            [queue addObject:sub];
        }
    }
    return bestImage;
}

static UIColor *DBResolveDropletColor(id sourceObj, UIView *bannerView) {
    if (gDropletColorMode == DBDropletColorModeBlack) {
        return nil;
    }
    if (gDropletColorMode == DBDropletColorModeCustom) {
        UIColor *custom = gCustomDropletColor ?: [UIColor systemBlueColor];
        if (bannerView) {
            objc_setAssociatedObject(bannerView, kDBViewDropletColorKey, custom, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        }
        return custom;
    }

    // DBDropletColorModeAppIcon
    if (!gIconColorCache) {
        gIconColorCache = [[NSCache alloc] init];
        gIconColorCache.countLimit = 64;
    }

    id req = DBSafeValueForKey(sourceObj, @"notificationRequest");
    if (!req) {
        id vc = DBSafeValueForKey(sourceObj, @"notificationViewController");
        if (vc) {
            req = DBSafeValueForKey(vc, @"notificationRequest");
        }
    }

    NSString *sectionID = nil;
    id rawSectionID = DBSafeValueForKey(req, @"sectionIdentifier");
    if ([rawSectionID isKindOfClass:[NSString class]] && ((NSString *)rawSectionID).length > 0) {
        sectionID = (NSString *)rawSectionID;
        UIColor *cached = [gIconColorCache objectForKey:sectionID];
        if (cached) {
            if (bannerView) {
                objc_setAssociatedObject(bannerView, kDBViewDropletColorKey, cached, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
            }
            return cached;
        }
    }

    UIImage *iconImage = nil;

    // 1. NCNotificationRequest.content.icons
    id content = DBSafeValueForKey(req, @"content");
    id icons = DBSafeValueForKey(content, @"icons");
    if ([icons isKindOfClass:[NSArray class]]) {
        for (id item in (NSArray *)icons) {
            if ([item isKindOfClass:[UIImage class]] && ((UIImage *)item).CGImage) {
                iconImage = (UIImage *)item;
                break;
            }
        }
    }
    if (!iconImage) {
        id singleIcon = DBSafeValueForKey(content, @"icon");
        if ([singleIcon isKindOfClass:[UIImage class]] && ((UIImage *)singleIcon).CGImage) {
            iconImage = (UIImage *)singleIcon;
        }
    }

    // 2. SpringBoard icon services via sectionIdentifier
    if (!iconImage && sectionID && [UIImage respondsToSelector:@selector(_applicationIconImageForBundleIdentifier:format:scale:)]) {
        @try {
            iconImage = [UIImage _applicationIconImageForBundleIdentifier:sectionID format:2 scale:1.0];
        } @catch (NSException *exception) {}
    }

    // 3. Fallback: inspect live banner view hierarchy
    if (!iconImage && bannerView && bannerView.window) {
        UIView *cardView = DBFindCardView(bannerView, bannerView.window);
        iconImage = DBFindAppIconImageInView(cardView, bannerView.window);
    }

    UIColor *resolvedColor = DBExtractDominantColorFromImage(iconImage);
    if (resolvedColor) {
        if (sectionID) {
            [gIconColorCache setObject:resolvedColor forKey:sectionID];
        }
        if (bannerView) {
            objc_setAssociatedObject(bannerView, kDBViewDropletColorKey, resolvedColor, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        }
    }
    return resolvedColor;
}

#pragma mark - Passthrough Overlay Window

@interface DBDropletEffectWindow : UIWindow
@end

@implementation DBDropletEffectWindow

- (BOOL)canBecomeKeyWindow {
    return NO;
}

- (UIView *)hitTest:(CGPoint)point withEvent:(UIEvent *)event {
    return nil;
}

@end

#pragma mark - CADisplayLink Weak Proxy

@class DBDropletAnimator;

@interface DBDisplayLinkProxy : NSObject
@property (nonatomic, weak) DBDropletAnimator *owner;
- (void)tick:(CADisplayLink *)link;
@end

#pragma mark - Global Shared Geometry & Active State

static DBDropletAnimator *gActiveAnimator = nil;
static __weak id gLatestPresentable = nil;
static CFTimeInterval gLatestEntryRequestTime = 0.0;
static CGRect gCachedRestingCardRect = {{0, 0}, {0, 0}};
static CGFloat gCachedCornerRadius = 26.0;
static const void *kDBViewEntryTimestampKey = &kDBViewEntryTimestampKey;

#pragma mark - Gyro-Reactive Motion Tracker (Zero Idle Battery Usage)

@interface DBMotionTracker : NSObject
@property (nonatomic, strong) CMMotionManager *manager;
@property (nonatomic, assign) NSInteger activeUsers;
@property (nonatomic, assign) NSUInteger stopToken;
@property (nonatomic, assign) double smoothedGravityX;
+ (instancetype)shared;
- (void)acquire;
- (void)releaseMotion;
- (double)currentGravityX;
@end

@implementation DBMotionTracker

+ (instancetype)shared {
    static DBMotionTracker *instance = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        instance = [[DBMotionTracker alloc] init];
    });
    return instance;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        _manager = [[CMMotionManager alloc] init];
        _manager.deviceMotionUpdateInterval = 1.0 / 60.0;
    }
    return self;
}

- (void)acquire {
    if (!gGyroCurveEnabled || !self.manager.deviceMotionAvailable) return;
    self.activeUsers += 1;
    self.stopToken += 1;
    if (!self.manager.deviceMotionActive) {
        [self.manager startDeviceMotionUpdates];
    }
}

- (void)releaseMotion {
    if (self.activeUsers > 0) {
        self.activeUsers -= 1;
    }
    if (self.activeUsers == 0 && self.manager.deviceMotionActive) {
        NSUInteger token = ++self.stopToken;
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.65 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            if (self.stopToken == token && self.activeUsers == 0 && self.manager.deviceMotionActive) {
                [self.manager stopDeviceMotionUpdates];
                self.smoothedGravityX = 0.0;
            }
        });
    }
}

- (double)currentGravityX {
    if (!gGyroCurveEnabled || !self.manager.deviceMotionAvailable) return 0.0;
    CMDeviceMotion *motion = self.manager.deviceMotion;
    if (!motion) return self.smoothedGravityX;

    double rawGx = motion.gravity.x;
    if (isnan(rawGx) || isinf(rawGx)) rawGx = 0.0;
    rawGx = fmin(fmax(rawGx, -0.65), 0.65);

    // Smooth low-pass filter so liquid tilt feels weighty rather than jittery
    self.smoothedGravityX = self.smoothedGravityX + (rawGx - self.smoothedGravityX) * 0.24;
    return self.smoothedGravityX;
}

@end

#pragma mark - Droplet Animator

@interface DBDropletAnimator : NSObject
@property (nonatomic, weak) UIView *contentView;
@property (nonatomic, weak) UIView *hideContainer;
@property (nonatomic, weak) UIWindow *sourceWindow;
@property (nonatomic, strong) DBDropletEffectWindow *effectWindow;
@property (nonatomic, strong) UIView *canvasView;
@property (nonatomic, strong) CAShapeLayer *islandPulseLayer;
@property (nonatomic, strong) CAGradientLayer *neckGradientLayer;
@property (nonatomic, strong) CAShapeLayer *neckMaskLayer;
@property (nonatomic, strong) CAShapeLayer *bodyLayer;
@property (nonatomic, strong) CAShapeLayer *rimLayer;
@property (nonatomic, strong) UIImageView *exitSnapshotView;
@property (nonatomic, strong) UIColor *surfaceColor;
@property (nonatomic, strong) UIColor *dropletTintColor;
@property (nonatomic, strong) UIImpactFeedbackGenerator *hapticGenerator;
@property (nonatomic, assign) BOOL hapticFired;
@property (nonatomic, assign) BOOL motionAcquired;
@property (nonatomic, strong) CADisplayLink *displayLink;
@property (nonatomic, strong) DBDisplayLinkProxy *proxy;
@property (nonatomic, assign) CFTimeInterval startedAt;
@property (nonatomic, assign) CFTimeInterval mainDuration;
@property (nonatomic, assign) CFTimeInterval totalDuration;
@property (nonatomic, assign) CFTimeInterval rimStartTime;
@property (nonatomic, assign) CFTimeInterval rimEndTime;
@property (nonatomic, assign) BOOL exiting;
@property (nonatomic, assign) CGRect cutoutRect;
@property (nonatomic, assign) CGRect cardRect;
@property (nonatomic, assign) CGFloat cardCornerRadius;
@property (nonatomic, copy) dispatch_block_t completionHandler;
- (void)startEntryForView:(UIView *)view dropletColor:(UIColor *)dropletColor;
- (void)startExitForView:(UIView *)view fromSwipe:(BOOL)fromSwipe dropletColor:(UIColor *)dropletColor;
- (void)tick:(CADisplayLink *)link;
- (void)stop;
@end

@implementation DBDisplayLinkProxy
- (void)tick:(CADisplayLink *)link {
    [self.owner tick:link];
}
@end

@implementation DBDropletAnimator

- (void)dealloc {
    [self stop];
}

- (void)stop {
    if (self.displayLink) {
        [self.displayLink invalidate];
        self.displayLink = nil;
    }
    self.proxy = nil;
    self.hapticGenerator = nil;
    if (self.motionAcquired) {
        self.motionAcquired = NO;
        [[DBMotionTracker shared] releaseMotion];
    }

    BOOL wasExiting = self.exiting;
    UIView *containerToRestore = self.hideContainer;
    UIView *contentToRestore = self.contentView;
    dispatch_block_t completion = self.completionHandler;
    self.hideContainer = nil;
    self.contentView = nil;
    self.completionHandler = nil;

    [UIView performWithoutAnimation:^{
        [CATransaction begin];
        [CATransaction setDisableActions:YES];

        if (!wasExiting) {
            if (containerToRestore) {
                containerToRestore.hidden = NO;
                containerToRestore.alpha = 1.0;
            }
            if (contentToRestore) {
                contentToRestore.hidden = NO;
                contentToRestore.alpha = 1.0;
            }
        } else if (containerToRestore || contentToRestore) {
            __weak UIView *weakContainer = containerToRestore;
            __weak UIView *weakContent = contentToRestore;
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.24 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
                if (gActiveAnimator && !gActiveAnimator.exiting &&
                    (gActiveAnimator.hideContainer == weakContainer || gActiveAnimator.contentView == weakContent)) {
                    return;
                }
                [UIView performWithoutAnimation:^{
                    if (weakContainer) {
                        weakContainer.hidden = NO;
                        weakContainer.alpha = 1.0;
                    }
                    if (weakContent) {
                        weakContent.hidden = NO;
                        weakContent.alpha = 1.0;
                    }
                }];
            });
        }

        if (self.exitSnapshotView) {
            [self.exitSnapshotView removeFromSuperview];
            self.exitSnapshotView = nil;
        }
        if (self.rimLayer) {
            [self.rimLayer removeFromSuperlayer];
            self.rimLayer = nil;
        }
        if (self.bodyLayer) {
            [self.bodyLayer removeFromSuperlayer];
            self.bodyLayer = nil;
        }
        if (self.neckGradientLayer) {
            [self.neckGradientLayer removeFromSuperlayer];
            self.neckGradientLayer = nil;
        }
        self.neckMaskLayer = nil;
        if (self.islandPulseLayer) {
            [self.islandPulseLayer removeFromSuperlayer];
            self.islandPulseLayer = nil;
        }
        if (self.effectWindow) {
            self.effectWindow.hidden = YES;
            self.effectWindow.rootViewController = nil;
            self.effectWindow = nil;
        }
        self.canvasView = nil;

        [CATransaction commit];
    }];

    if (gActiveAnimator == self) {
        gActiveAnimator = nil;
    }

    if (completion) {
        completion();
    }
}

- (BOOL)setupOverlayForView:(UIView *)rawView isExit:(BOOL)isExit fromSwipe:(BOOL)fromSwipe dropletColor:(UIColor *)dropletColor {
    UIWindow *win = rawView.window;
    if (!win) return NO;

    CGSize winSize = win.bounds.size;
    if (winSize.width < 250.0) return NO;
    if (gPauseInLandscape && winSize.width > winSize.height) return NO;

    UIView *cardView = DBFindCardView(rawView, win);
    if (!cardView) return NO;

    UIView *container = DBFindPerBannerContainer(cardView, win);
    CGRect cutout = DBResolveCutoutRectForWindow(win);

    CGRect frameInWin = [cardView convertRect:cardView.bounds toCoordinateSpace:win.coordinateSpace];

    if (isExit && cardView.layer.presentationLayer && win.layer.presentationLayer) {
        CGRect presRect = [cardView.layer.presentationLayer convertRect:cardView.layer.presentationLayer.bounds
                                                                toLayer:win.layer.presentationLayer];
        if (!CGRectIsEmpty(presRect) && presRect.size.width >= 120.0 && presRect.size.height >= 34.0) {
            frameInWin = presRect;
        }
    }

    BOOL isPortrait = (winSize.height >= winSize.width);
    if (isPortrait &&
        (CGRectIsEmpty(frameInWin) || frameInWin.size.width < winSize.width * 0.55 || frameInWin.size.height < 34.0) &&
        !CGRectIsEmpty(gCachedRestingCardRect)) {
        frameInWin = gCachedRestingCardRect;
    }

    if (CGRectIsEmpty(frameInWin) || frameInWin.size.width < 120.0 || frameInWin.size.height < 34.0) {
        return NO;
    }

    CGFloat minRestingY = CGRectGetMaxY(cutout) + 10.0;
    if (!isExit) {
        if (frameInWin.origin.y < minRestingY - 4.0 || frameInWin.origin.y > winSize.height * 0.35) {
            frameInWin.origin.y = (isPortrait && !CGRectIsEmpty(gCachedRestingCardRect)) ? gCachedRestingCardRect.origin.y : minRestingY;
        }
    } else {
        CGFloat minVisibleSwipeY = CGRectGetMaxY(cutout) - 4.0;
        if (frameInWin.origin.y < CGRectGetMinY(cutout) - 10.0 || frameInWin.origin.y > winSize.height * 0.40) {
            frameInWin.origin.y = (isPortrait && !CGRectIsEmpty(gCachedRestingCardRect)) ? gCachedRestingCardRect.origin.y : minRestingY;
        } else if (fromSwipe && frameInWin.origin.y < minVisibleSwipeY) {
            frameInWin.origin.y = minVisibleSwipeY;
        }
    }
    frameInWin.origin.x = round((winSize.width - frameInWin.size.width) * 0.5);

    CGFloat cornerR = DBResolveCornerRadius(cardView);
    if (!isExit && isPortrait) {
        gCachedRestingCardRect = frameInWin;
        gCachedCornerRadius = cornerR;
    } else if (isPortrait && gCachedCornerRadius >= 14.0) {
        cornerR = gCachedCornerRadius;
    }

    self.contentView = cardView;
    self.hideContainer = container ?: cardView;
    self.sourceWindow = win;
    self.cutoutRect = cutout;
    self.cardRect = frameInWin;
    self.cardCornerRadius = cornerR;
    self.surfaceColor = [[UIColor secondarySystemBackgroundColor] resolvedColorWithTraitCollection:cardView.traitCollection];
    self.dropletTintColor = (gDropletColorMode != DBDropletColorModeBlack) ? dropletColor : nil;

    DBDropletEffectWindow *overlay = nil;
    if (win.windowScene) {
        overlay = [[DBDropletEffectWindow alloc] initWithWindowScene:win.windowScene];
    } else {
        overlay = [[DBDropletEffectWindow alloc] initWithFrame:win.bounds];
    }
    overlay.frame = win.bounds;
    overlay.windowLevel = win.windowLevel + 1.0;
    overlay.backgroundColor = [UIColor clearColor];
    overlay.clipsToBounds = NO;
    overlay.userInteractionEnabled = NO;
    overlay.accessibilityElementsHidden = YES;

    UIViewController *rootVC = [[UIViewController alloc] init];
    rootVC.view.backgroundColor = [UIColor clearColor];
    rootVC.view.clipsToBounds = NO;
    rootVC.view.userInteractionEnabled = NO;
    rootVC.view.frame = overlay.bounds;
    overlay.rootViewController = rootVC;
    [overlay layoutIfNeeded];

    UIView *canvas = [[UIView alloc] initWithFrame:overlay.bounds];
    canvas.backgroundColor = [UIColor clearColor];
    canvas.clipsToBounds = NO;
    canvas.userInteractionEnabled = NO;
    canvas.accessibilityElementsHidden = YES;
    [rootVC.view addSubview:canvas];

    // 1. Dynamic Island Recoil Pulse Layer
    CAShapeLayer *islandPulse = [CAShapeLayer layer];
    islandPulse.frame = canvas.bounds;
    islandPulse.fillColor = [UIColor blackColor].CGColor;
    islandPulse.opacity = 0.0f;
    [canvas.layer addSublayer:islandPulse];

    // 2. Curved Liquid Neck Layer (Gradient black -> droplet tint)
    CAGradientLayer *neckGrad = [CAGradientLayer layer];
    neckGrad.frame = canvas.bounds;
    neckGrad.colors = @[ (id)[UIColor blackColor].CGColor, (id)[UIColor blackColor].CGColor ];
    neckGrad.locations = @[ @(0.0), @(1.0) ];

    CAShapeLayer *neckMask = [CAShapeLayer layer];
    neckMask.frame = canvas.bounds;
    neckMask.fillColor = [UIColor whiteColor].CGColor;
    neckGrad.mask = neckMask;
    [canvas.layer addSublayer:neckGrad];

    // 3. Teardrop / Banner Body Layer
    CAShapeLayer *body = [CAShapeLayer layer];
    body.frame = canvas.bounds;
    body.fillColor = [UIColor blackColor].CGColor;
    [canvas.layer addSublayer:body];

    // 4. Brief Bloom Rim Accent Layer
    CAShapeLayer *rim = [CAShapeLayer layer];
    rim.frame = canvas.bounds;
    rim.fillColor = [UIColor clearColor].CGColor;
    rim.lineWidth = (CGFloat)gBloomRimWidth;
    rim.opacity = 0.0f;
    UIColor *rimStrokeColor = self.dropletTintColor
        ? self.dropletTintColor
        : [UIColor colorWithWhite:1.0 alpha:0.65];
    rim.strokeColor = rimStrokeColor.CGColor;
    rim.shadowColor = rimStrokeColor.CGColor;
    rim.shadowRadius = 4.5;
    rim.shadowOpacity = self.dropletTintColor ? 0.45f : 0.25f;
    rim.shadowOffset = CGSizeZero;
    [canvas.layer addSublayer:rim];

    self.effectWindow = overlay;
    self.canvasView = canvas;
    self.islandPulseLayer = islandPulse;
    self.neckGradientLayer = neckGrad;
    self.neckMaskLayer = neckMask;
    self.bodyLayer = body;
    self.rimLayer = rim;

    self.hapticFired = NO;
    if (gHapticsEnabled) {
        self.hapticGenerator = [[UIImpactFeedbackGenerator alloc] initWithStyle:DBCurrentImpactStyle()];
        [self.hapticGenerator prepare];
    } else {
        self.hapticGenerator = nil;
    }

    if (gGyroCurveEnabled && !self.motionAcquired) {
        self.motionAcquired = YES;
        [[DBMotionTracker shared] acquire];
    }

    return YES;
}

- (void)startDisplayLink {
    self.proxy = [[DBDisplayLinkProxy alloc] init];
    self.proxy.owner = self;
    self.displayLink = [CADisplayLink displayLinkWithTarget:self.proxy selector:@selector(tick:)];
    if (@available(iOS 15.0, *)) {
        self.displayLink.preferredFrameRateRange = CAFrameRateRangeMake(60, 120, 120);
    }
    [self.displayLink addToRunLoop:[NSRunLoop mainRunLoop] forMode:NSRunLoopCommonModes];
}

- (void)startEntryForView:(UIView *)view dropletColor:(UIColor *)dropletColor {
    self.exiting = NO;

    __block BOOL ready = NO;
    [UIView performWithoutAnimation:^{
        [CATransaction begin];
        [CATransaction setDisableActions:YES];

        ready = [self setupOverlayForView:view isExit:NO fromSwipe:NO dropletColor:dropletColor];
        if (ready) {
            double speedScale = gEntryDuration / 0.48;
            self.mainDuration = fmin(fmax(0.84 * speedScale, 0.46), 1.45);

            if (gBloomRimEnabled) {
                self.rimStartTime = self.mainDuration * 0.54;
                self.rimEndTime = self.rimStartTime + gBloomRimDuration;
                self.totalDuration = fmax(self.mainDuration, self.rimEndTime);
            } else {
                self.rimStartTime = 0.0;
                self.rimEndTime = 0.0;
                self.totalDuration = self.mainDuration;
            }

            self.hideContainer.hidden = YES;
            self.hideContainer.alpha = 0.0;

            self.startedAt = CACurrentMediaTime();
            [self renderElapsed:0.0];
            self.effectWindow.hidden = NO;
        }

        [CATransaction commit];
    }];

    if (ready) {
        [self startDisplayLink];
    } else if (gActiveAnimator == self) {
        gActiveAnimator = nil;
    }
}

- (void)startExitForView:(UIView *)view fromSwipe:(BOOL)fromSwipe dropletColor:(UIColor *)dropletColor {
    self.exiting = YES;

    __block BOOL ready = NO;
    [UIView performWithoutAnimation:^{
        [CATransaction begin];
        [CATransaction setDisableActions:YES];

        ready = [self setupOverlayForView:view isExit:YES fromSwipe:fromSwipe dropletColor:dropletColor];
        if (ready) {
            UIImage *snap = DBSnapshotView(self.contentView);
            if (snap) {
                UIImageView *snapView = [[UIImageView alloc] initWithImage:snap];
                snapView.frame = self.cardRect;
                snapView.contentMode = UIViewContentModeScaleToFill;
                snapView.layer.anchorPoint = CGPointMake(0.5, 0.5);
                snapView.layer.bounds = CGRectMake(0, 0, self.cardRect.size.width, self.cardRect.size.height);
                snapView.layer.position = CGPointMake(CGRectGetMidX(self.cardRect), CGRectGetMidY(self.cardRect));
                snapView.layer.cornerRadius = self.cardCornerRadius;
                snapView.layer.cornerCurve = kCACornerCurveContinuous;
                snapView.clipsToBounds = YES;
                snapView.userInteractionEnabled = NO;
                [self.canvasView addSubview:snapView];
                self.exitSnapshotView = snapView;
            }

            self.hideContainer.hidden = YES;
            self.hideContainer.alpha = 0.0;

            double speedScale = gEntryDuration / 0.48;
            double baseExit = fromSwipe ? 0.38 : 0.44;
            self.mainDuration = fmin(fmax(baseExit * speedScale, 0.24), 0.72);
            self.totalDuration = self.mainDuration;
            self.rimStartTime = 0.0;
            self.rimEndTime = 0.0;

            self.startedAt = CACurrentMediaTime();
            [self renderElapsed:0.0];
            self.effectWindow.hidden = NO;
        }

        [CATransaction commit];
    }];

    if (ready) {
        [self startDisplayLink];
    } else if (gActiveAnimator == self) {
        gActiveAnimator = nil;
    }
}

- (void)tick:(CADisplayLink *)link {
    CFTimeInterval elapsed = CACurrentMediaTime() - self.startedAt;
    if (elapsed >= self.totalDuration) {
        [self renderElapsed:self.totalDuration];
        [self stop];
        return;
    }
    [self renderElapsed:elapsed];
}

- (void)renderElapsed:(CFTimeInterval)elapsed {
    double normT = (self.mainDuration > 0.0) ? DBClamp01(elapsed / self.mainDuration) : 1.0;
    double amp = gAmplitude;
    double yProg = 0.0;
    double wProg = 0.0;
    double revealProg = 0.0;
    double neckProg = 0.0;
    double tCanonical = 0.0;

    if (!self.exiting) {
        tCanonical = normT * 1.2;
        yProg = DBSpringCurve(tCanonical / 1.15, 7.38, 5.15127, 1.43266);
        wProg = DBSpringCurve((tCanonical - 0.32) / 0.86, 7.20, 5.40, 1.33333);
        revealProg = DBClamp01((tCanonical - 0.62) / 0.34);
        neckProg = DBSpringCurve((tCanonical - 0.11) / 0.70, 8.91, 1.26961, 7.01792);
    } else {
        tCanonical = normT * 0.82;
        yProg = 1.0 - DBSpringCurve((tCanonical - 0.20) / 0.62, 7.60, 3.80, 1.95);
        wProg = 1.0 - DBSpringCurve((tCanonical - 0.04) / 0.48, 7.90, 3.50, 2.25);
        revealProg = 1.0 - DBClamp01(tCanonical / 0.20);
        neckProg = 1.0 - DBSpringCurve((tCanonical - 0.20) / 0.62, 7.60, 3.80, 1.95);
    }

    // Fire neck-snap micro-haptic at the exact detach (entry) or click-in (exit) moment
    if (gHapticsEnabled && self.hapticGenerator && !self.hapticFired) {
        BOOL shouldFire = (!self.exiting && neckProg >= 0.72) || (self.exiting && normT >= 0.72);
        if (shouldFire) {
            self.hapticFired = YES;
            [self.hapticGenerator impactOccurred];
        }
    }

    double clampedWProg = fmax(0.0, wProg);
    double clampedYProg = fmax(0.0, yProg);

    // Teardrop vertical liquid stretch bulge
    double u = DBClamp01(clampedYProg / 0.82);
    double bulge = (pow(u, 1.6) * pow(1.0 - u, 1.4)) / 0.12583674;
    double stretch = 1.0 + (0.38 * amp) * bulge;

    double baseDropDiameter = fmin(CGRectGetHeight(self.cutoutRect) * 0.96, CGRectGetHeight(self.cardRect) * 0.72);
    double dropGrow = 1.0 - pow(1.0 - DBClamp01(clampedYProg / 0.70), 2.0);
    double dropSize = baseDropDiameter * (0.62 + 0.38 * dropGrow);

    double dropW = dropSize / stretch;
    double dropH = dropSize * stretch;

    double curW = fmax(16.0, DBLerp(dropW, CGRectGetWidth(self.cardRect), clampedWProg));
    double curH = fmax(16.0, DBLerp(dropH, CGRectGetHeight(self.cardRect), clampedWProg));

    double islandMidX = CGRectGetMidX(self.cutoutRect);
    double gyroSwayX = 0.0;
    if (gGyroCurveEnabled) {
        double gx = [[DBMotionTracker shared] currentGravityX];
        double maxSway = 26.0 * gGyroCurveIntensity;
        double dropArc = sin(DBClamp01(clampedYProg) * M_PI);
        double freeFromCard = 1.0 - DBClamp01(clampedWProg * 1.15);
        gyroSwayX = gx * maxSway * dropArc * freeFromCard;
    }

    double startMidY = CGRectGetMaxY(self.cutoutRect) - 0.34 * dropH;
    double curMidY = DBLerp(startMidY, CGRectGetMidY(self.cardRect), yProg);
    double curMidX = islandMidX + gyroSwayX;

    CGRect curRect = CGRectMake(curMidX - curW * 0.5, curMidY - curH * 0.5, curW, curH);
    CGFloat maxR = (CGFloat)(fmin(curW, curH) * 0.5);
    CGFloat curRadius = (CGFloat)fmin(maxR, DBLerp(maxR, self.cardCornerRadius, DBClamp01(clampedWProg)));

    UIBezierPath *bodyPath = [UIBezierPath bezierPathWithRoundedRect:curRect cornerRadius:curRadius];

    // Dynamic Island Recoil Pulse Path
    UIBezierPath *islandPulsePath = nil;
    double islandPulseAlpha = 0.0;
    if (gIslandRecoilEnabled && CGRectGetHeight(self.cutoutRect) >= 32.0) {
        double pU = 0.0;
        double basePadX = 0.0;
        double basePadY = 0.0;
        double tugDown = 0.0;

        if (!self.exiting) {
            pU = DBClamp01((tCanonical - 0.03) / 0.38);
            basePadX = 4.2 * gIslandRecoilIntensity;
            basePadY = 2.8 * gIslandRecoilIntensity;
            tugDown = 0.45;
        } else {
            pU = DBClamp01((normT - 0.56) / 0.44);
            basePadX = 4.8 * gIslandRecoilIntensity;
            basePadY = 3.2 * gIslandRecoilIntensity;
            tugDown = 0.25;
        }

        if (pU > 0.002 && pU < 0.998) {
            double pulse = fmin(1.15, 2.40 * sin(pU * M_PI) * exp(-2.2 * pU));
            CGFloat padX = (CGFloat)(basePadX * pulse);
            CGFloat padY = (CGFloat)(basePadY * pulse);
            if (padX > 0.15 || padY > 0.15) {
                CGRect pulseRect = CGRectInset(self.cutoutRect, -padX, -padY * 0.5);
                pulseRect.origin.y += (CGFloat)(padY * tugDown);
                islandPulsePath = [UIBezierPath bezierPathWithRoundedRect:pulseRect cornerRadius:pulseRect.size.height * 0.5];
                islandPulseAlpha = DBClamp01(pulse * 2.5);
            }
        }
    }

    // Curved liquid neck bridging Dynamic Island bottom to the teardrop
    double neckVisibility = 0.0;
    if (clampedYProg > 0.02 && neckProg < 0.94) {
        double rise = DBClamp01(clampedYProg / 0.18);
        double snap = 1.0 - DBClamp01((neckProg - 0.25) / 0.69);
        neckVisibility = rise * snap;
    }

    UIBezierPath *neckPath = nil;
    CGFloat islandBottomY = CGRectGetMaxY(self.cutoutRect) - 4.0;
    CGFloat dropAttachY = CGRectGetMinY(curRect) + fmin(curRadius * 0.85, 18.0);

    if (neckVisibility > 0.01 && dropAttachY > islandBottomY + 1.0) {
        CGFloat topHalfW = (CGFloat)(CGRectGetWidth(self.cutoutRect) * 0.28 * (0.45 + 0.55 * neckVisibility));
        CGFloat botHalfW = (CGFloat)(fmin(curW * 0.42, topHalfW * 1.15) * (0.45 + 0.55 * neckVisibility));
        CGFloat midY = (islandBottomY + dropAttachY) * 0.5;
        CGFloat pinchX = (CGFloat)(topHalfW * 0.22 * (0.5 + 0.5 * neckVisibility));

        CGFloat topMidX = (CGFloat)islandMidX;
        CGFloat botMidX = (CGFloat)curMidX;
        CGFloat bendMidX = (CGFloat)((topMidX + botMidX) * 0.5 + gyroSwayX * 0.25);
        CGFloat spanY = dropAttachY - islandBottomY;

        neckPath = [UIBezierPath bezierPath];
        [neckPath moveToPoint:CGPointMake(topMidX - topHalfW, islandBottomY)];
        [neckPath addCurveToPoint:CGPointMake(botMidX - botHalfW, dropAttachY)
                    controlPoint1:CGPointMake(topMidX - pinchX, midY - spanY * 0.08)
                    controlPoint2:CGPointMake(bendMidX - pinchX, midY + spanY * 0.08)];
        [neckPath addLineToPoint:CGPointMake(botMidX + botHalfW, dropAttachY)];
        [neckPath addCurveToPoint:CGPointMake(topMidX + topHalfW, islandBottomY)
                    controlPoint1:CGPointMake(bendMidX + pinchX, midY + spanY * 0.08)
                    controlPoint2:CGPointMake(topMidX + pinchX, midY - spanY * 0.08)];
        [neckPath closePath];
    }

    CGFloat sr = 0.12, sg = 0.12, sb = 0.14, sa = 1.0;
    if (self.surfaceColor) {
        [self.surfaceColor getRed:&sr green:&sg blue:&sb alpha:&sa];
    }

    UIColor *bodyColor = nil;
    if (self.dropletTintColor) {
        CGFloat dr = 0.0, dg = 0.0, db = 0.0, da = 1.0;
        [self.dropletTintColor getRed:&dr green:&dg blue:&db alpha:&da];

        // Keep ONLY the water drop tinted: black -> tint as it drops, then tint -> neutral banner surface as it blooms
        double tintIn = DBClamp01(clampedYProg / 0.22);
        double bloomOut = DBClamp01((clampedWProg - 0.08) / 0.52);

        double baseR = dr * tintIn;
        double baseG = dg * tintIn;
        double baseB = db * tintIn;

        double finalR = DBLerp(baseR, sr, bloomOut);
        double finalG = DBLerp(baseG, sg, bloomOut);
        double finalB = DBLerp(baseB, sb, bloomOut);
        bodyColor = [UIColor colorWithRed:finalR green:finalG blue:finalB alpha:1.0];
    } else {
        double colorBlend = DBClamp01(clampedWProg * 0.82);
        bodyColor = [UIColor colorWithRed:sr * colorBlend green:sg * colorBlend blue:sb * colorBlend alpha:1.0];
    }

    // Brief Bloom Rim Accent
    UIBezierPath *rimPath = nil;
    double rimOpacity = 0.0;
    if (!self.exiting && gBloomRimEnabled && self.rimEndTime > self.rimStartTime) {
        if (elapsed >= self.rimStartTime && elapsed <= self.rimEndTime) {
            double rU = (elapsed - self.rimStartTime) / (self.rimEndTime - self.rimStartTime);
            // Quick crisp rise (0..0.28), then silky exponential-cubic fade-out (0.28..1.0)
            double envelope = (rU < 0.28)
                ? (rU / 0.28)
                : pow(1.0 - ((rU - 0.28) / 0.72), 1.8);
            double maxAlpha = self.dropletTintColor ? 0.86 : 0.52;
            rimOpacity = DBClamp01(envelope) * maxAlpha;

            CGFloat lw = (CGFloat)gBloomRimWidth;
            CGRect rimRect = CGRectInset(curRect, lw * 0.5, lw * 0.5);
            CGFloat rimRadius = fmax(2.0, curRadius - lw * 0.5);
            rimPath = [UIBezierPath bezierPathWithRoundedRect:rimRect cornerRadius:rimRadius];
        }
    }

    CGFloat canvasH = fmax(1.0, CGRectGetHeight(self.canvasView.bounds));
    CGFloat startGradY = (CGFloat)DBClamp01(islandBottomY / canvasH);
    CGFloat endGradY = (CGFloat)DBClamp01(fmax(islandBottomY + 2.0, dropAttachY) / canvasH);

    [UIView performWithoutAnimation:^{
        [CATransaction begin];
        [CATransaction setDisableActions:YES];

        if (islandPulsePath && islandPulseAlpha > 0.01) {
            self.islandPulseLayer.path = islandPulsePath.CGPath;
            self.islandPulseLayer.opacity = (float)islandPulseAlpha;
        } else {
            self.islandPulseLayer.path = NULL;
            self.islandPulseLayer.opacity = 0.0f;
        }

        self.bodyLayer.path = bodyPath.CGPath;
        self.bodyLayer.fillColor = bodyColor.CGColor;

        if (neckPath) {
            self.neckMaskLayer.path = neckPath.CGPath;
            self.neckGradientLayer.startPoint = CGPointMake(0.5, startGradY);
            self.neckGradientLayer.endPoint = CGPointMake(0.5, endGradY);
            if (self.dropletTintColor) {
                self.neckGradientLayer.colors = @[ (id)[UIColor blackColor].CGColor, (id)bodyColor.CGColor ];
            } else {
                self.neckGradientLayer.colors = @[ (id)[UIColor blackColor].CGColor, (id)[UIColor blackColor].CGColor ];
            }
            self.neckGradientLayer.opacity = (float)DBClamp01(neckVisibility * 1.15);
        } else {
            self.neckMaskLayer.path = NULL;
            self.neckGradientLayer.opacity = 0.0f;
        }

        if (rimPath && rimOpacity > 0.005) {
            self.rimLayer.path = rimPath.CGPath;
            self.rimLayer.opacity = (float)rimOpacity;
        } else {
            self.rimLayer.path = NULL;
            self.rimLayer.opacity = 0.0f;
        }

        if (!self.exiting) {
            if (revealProg <= 0.005) {
                self.hideContainer.hidden = YES;
                self.hideContainer.alpha = 0.0;
            } else {
                self.hideContainer.hidden = NO;
                self.hideContainer.alpha = revealProg;
            }
            self.bodyLayer.opacity = (float)DBClamp01(1.0 - revealProg);
        } else {
            self.hideContainer.hidden = YES;
            self.hideContainer.alpha = 0.0;

            double endFade = 1.0 - DBClamp01((normT - 0.82) / 0.18);
            self.bodyLayer.opacity = (float)endFade;
            if (self.exitSnapshotView) {
                self.exitSnapshotView.layer.bounds = CGRectMake(0, 0, curW, curH);
                self.exitSnapshotView.layer.position = CGPointMake(curMidX, curMidY);
                self.exitSnapshotView.layer.cornerRadius = curRadius;
                self.exitSnapshotView.layer.opacity = (float)DBClamp01(revealProg);
            }
        }

        [CATransaction commit];
    }];
}

@end

#pragma mark - Magnetic Swipe-Up Neck Controller

static const void *kDBMagneticPanKey = &kDBMagneticPanKey;

@class DBMagneticNeckController;

@interface DBMagneticLinkProxy : NSObject
@property (nonatomic, weak) DBMagneticNeckController *owner;
- (void)tickCollapse:(CADisplayLink *)link;
@end

@interface DBMagneticNeckController : NSObject <UIGestureRecognizerDelegate>
@property (nonatomic, weak) UIView *trackedCard;
@property (nonatomic, weak) UIWindow *sourceWindow;
@property (nonatomic, strong) DBDropletEffectWindow *overlayWindow;
@property (nonatomic, strong) UIView *canvasView;
@property (nonatomic, strong) CAShapeLayer *islandPulseLayer;
@property (nonatomic, strong) CAGradientLayer *neckGradientLayer;
@property (nonatomic, strong) CAShapeLayer *neckMaskLayer;
@property (nonatomic, strong) UIColor *tintColor;
@property (nonatomic, assign) CGRect cutoutRect;
@property (nonatomic, assign) CGRect startCardRect;
@property (nonatomic, assign) CGFloat lastPullProgress;
@property (nonatomic, assign) CGFloat lastAttachY;
@property (nonatomic, assign) CGFloat lastCardMidX;
@property (nonatomic, assign) CGFloat lastCardWidth;
@property (nonatomic, assign) BOOL active;
@property (nonatomic, assign) BOOL latchHapticFired;
@property (nonatomic, assign) BOOL motionAcquired;
@property (nonatomic, strong) UIImpactFeedbackGenerator *hapticGenerator;
@property (nonatomic, strong) CADisplayLink *collapseLink;
@property (nonatomic, strong) DBMagneticLinkProxy *collapseProxy;
@property (nonatomic, assign) CFTimeInterval collapseStartedAt;
@property (nonatomic, assign) CGFloat collapseStartProgress;
+ (instancetype)shared;
- (void)attachToBannerView:(UIView *)rawView dropletColor:(UIColor *)dropletColor;
- (void)updateInteractiveCard:(UIView *)cardView window:(UIWindow *)win upwardPull:(CGFloat)upwardPull cardTopY:(CGFloat)cardTopY cardMidX:(CGFloat)cardMidX cardWidth:(CGFloat)cardWidth tintColor:(UIColor *)tintColor;
- (void)beginCollapse;
- (void)db_tickCollapse:(CADisplayLink *)link;
- (void)cancelImmediate;
@end

@implementation DBMagneticLinkProxy
- (void)tickCollapse:(CADisplayLink *)link {
    [self.owner db_tickCollapse:link];
}
@end

@implementation DBMagneticNeckController

+ (instancetype)shared {
    static DBMagneticNeckController *instance = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        instance = [[DBMagneticNeckController alloc] init];
    });
    return instance;
}

- (BOOL)gestureRecognizer:(UIGestureRecognizer *)gestureRecognizer shouldRecognizeSimultaneouslyWithGestureRecognizer:(UIGestureRecognizer *)otherGestureRecognizer {
    return YES;
}

- (void)attachToBannerView:(UIView *)rawView dropletColor:(UIColor *)dropletColor {
    if (!rawView || !rawView.window) return;
    UIWindow *win = rawView.window;
    UIView *cardView = DBFindCardView(rawView, win);
    if (!cardView) return;

    if (dropletColor) {
        objc_setAssociatedObject(cardView, kDBViewDropletColorKey, dropletColor, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }

    UIPanGestureRecognizer *existing = objc_getAssociatedObject(cardView, kDBMagneticPanKey);
    if (existing && existing.view == cardView) return;

    UIPanGestureRecognizer *pan = [[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(db_handleBannerPan:)];
    pan.cancelsTouchesInView = NO;
    pan.delaysTouchesBegan = NO;
    pan.delaysTouchesEnded = NO;
    pan.delegate = self;
    [cardView addGestureRecognizer:pan];
    objc_setAssociatedObject(cardView, kDBMagneticPanKey, pan, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}

- (BOOL)db_ensureOverlayForWindow:(UIWindow *)win tintColor:(UIColor *)tintColor {
    if (!win) return NO;
    CGSize winSize = win.bounds.size;
    if (winSize.width < 250.0) return NO;
    if (gPauseInLandscape && winSize.width > winSize.height) return NO;

    if (self.overlayWindow && self.sourceWindow == win) {
        self.tintColor = (gDropletColorMode != DBDropletColorModeBlack) ? tintColor : nil;
        return YES;
    }

    [self cancelImmediate];

    self.sourceWindow = win;
    self.cutoutRect = DBResolveCutoutRectForWindow(win);
    self.tintColor = (gDropletColorMode != DBDropletColorModeBlack) ? tintColor : nil;

    [UIView performWithoutAnimation:^{
        [CATransaction begin];
        [CATransaction setDisableActions:YES];

        DBDropletEffectWindow *overlay = win.windowScene
            ? [[DBDropletEffectWindow alloc] initWithWindowScene:win.windowScene]
            : [[DBDropletEffectWindow alloc] initWithFrame:win.bounds];
        overlay.frame = win.bounds;
        overlay.windowLevel = win.windowLevel + 1.0;
        overlay.backgroundColor = [UIColor clearColor];
        overlay.clipsToBounds = NO;
        overlay.userInteractionEnabled = NO;
        overlay.accessibilityElementsHidden = YES;

        UIViewController *rootVC = [[UIViewController alloc] init];
        rootVC.view.backgroundColor = [UIColor clearColor];
        rootVC.view.clipsToBounds = NO;
        rootVC.view.userInteractionEnabled = NO;
        rootVC.view.frame = overlay.bounds;
        overlay.rootViewController = rootVC;
        [overlay layoutIfNeeded];

        UIView *canvas = [[UIView alloc] initWithFrame:overlay.bounds];
        canvas.backgroundColor = [UIColor clearColor];
        canvas.clipsToBounds = NO;
        canvas.userInteractionEnabled = NO;
        canvas.accessibilityElementsHidden = YES;
        [rootVC.view addSubview:canvas];

        CAShapeLayer *islandPulse = [CAShapeLayer layer];
        islandPulse.frame = canvas.bounds;
        islandPulse.fillColor = [UIColor blackColor].CGColor;
        islandPulse.opacity = 0.0f;
        [canvas.layer addSublayer:islandPulse];

        CAGradientLayer *neckGrad = [CAGradientLayer layer];
        neckGrad.frame = canvas.bounds;
        neckGrad.colors = @[ (id)[UIColor blackColor].CGColor, (id)[UIColor blackColor].CGColor ];
        neckGrad.locations = @[ @(0.0), @(1.0) ];

        CAShapeLayer *neckMask = [CAShapeLayer layer];
        neckMask.frame = canvas.bounds;
        neckMask.fillColor = [UIColor whiteColor].CGColor;
        neckGrad.mask = neckMask;
        [canvas.layer addSublayer:neckGrad];

        overlay.hidden = NO;

        self.overlayWindow = overlay;
        self.canvasView = canvas;
        self.islandPulseLayer = islandPulse;
        self.neckGradientLayer = neckGrad;
        self.neckMaskLayer = neckMask;

        [CATransaction commit];
    }];

    self.latchHapticFired = NO;
    if (gHapticsEnabled) {
        self.hapticGenerator = [[UIImpactFeedbackGenerator alloc] initWithStyle:DBCurrentImpactStyle()];
        [self.hapticGenerator prepare];
    } else {
        self.hapticGenerator = nil;
    }

    if (gGyroCurveEnabled && !self.motionAcquired) {
        self.motionAcquired = YES;
        [[DBMotionTracker shared] acquire];
    }

    self.active = YES;
    return YES;
}

- (void)db_renderNeckProgress:(CGFloat)progress attachY:(CGFloat)attachY cardMidX:(CGFloat)cardMidX cardWidth:(CGFloat)cardWidth {
    if (!self.overlayWindow || !self.canvasView) return;

    CGFloat islandMidX = CGRectGetMidX(self.cutoutRect);
    CGFloat islandBottomY = CGRectGetMaxY(self.cutoutRect) - 4.0;
    CGFloat strength = (CGFloat)fmin(fmax(gMagneticNeckStrength, 0.5), 2.0);
    CGFloat p = (CGFloat)DBClamp01(progress);

    // Subtle gyro tilt on the magnetic bridge as well
    CGFloat gyroBendX = 0.0;
    if (gGyroCurveEnabled) {
        double gx = [[DBMotionTracker shared] currentGravityX];
        gyroBendX = (CGFloat)(gx * 16.0 * gGyroCurveIntensity * p);
    }

    // Clamp attachment point so bridge smoothly spans from Island down to banner top edge
    CGFloat clampedAttachY = fmax(islandBottomY + 2.0, fmin(attachY, islandBottomY + 95.0));
    CGFloat spanY = clampedAttachY - islandBottomY;

    // Stretch factor: thicker & wider as the banner gets pulled closer to the Dynamic Island
    CGFloat topHalfW = CGRectGetWidth(self.cutoutRect) * (0.20 + 0.20 * p) * (0.85 + 0.15 * strength);
    CGFloat botHalfW = fmin(cardWidth * 0.34, topHalfW * (1.28 + 0.35 * p));
    CGFloat pinchHalfW = fmax(3.5, topHalfW * (0.16 + 0.34 * p));
    CGFloat midY = islandBottomY + spanY * 0.50;

    CGFloat targetBotMidX = islandMidX + (cardMidX - islandMidX) * 0.35 + gyroBendX * 0.45;
    CGFloat bendMidX = (islandMidX + targetBotMidX) * 0.5 + gyroBendX * 0.45;

    UIBezierPath *neckPath = nil;
    if (p > 0.015 && spanY > 2.0) {
        neckPath = [UIBezierPath bezierPath];
        [neckPath moveToPoint:CGPointMake(islandMidX - topHalfW, islandBottomY)];
        [neckPath addCurveToPoint:CGPointMake(targetBotMidX - botHalfW, clampedAttachY)
                    controlPoint1:CGPointMake(islandMidX - pinchHalfW, midY - spanY * 0.08)
                    controlPoint2:CGPointMake(bendMidX - pinchHalfW, midY + spanY * 0.08)];
        [neckPath addLineToPoint:CGPointMake(targetBotMidX + botHalfW, clampedAttachY)];
        [neckPath addCurveToPoint:CGPointMake(islandMidX + topHalfW, islandBottomY)
                    controlPoint1:CGPointMake(bendMidX + pinchHalfW, midY + spanY * 0.08)
                    controlPoint2:CGPointMake(islandMidX + pinchHalfW, midY - spanY * 0.08)];
        [neckPath closePath];
    }

    // Subtle Dynamic Island magnetic swell while pulling upward
    UIBezierPath *pulsePath = nil;
    CGFloat pulseAlpha = 0.0;
    if (gIslandRecoilEnabled && CGRectGetHeight(self.cutoutRect) >= 32.0 && p > 0.05) {
        CGFloat padX = (CGFloat)(3.6 * gIslandRecoilIntensity * p);
        CGFloat padY = (CGFloat)(2.4 * gIslandRecoilIntensity * p);
        CGRect pulseRect = CGRectInset(self.cutoutRect, -padX, -padY * 0.5);
        pulseRect.origin.y += padY * 0.45;
        pulsePath = [UIBezierPath bezierPathWithRoundedRect:pulseRect cornerRadius:pulseRect.size.height * 0.5];
        pulseAlpha = fmin(1.0, p * 1.4);
    }

    CGFloat canvasH = fmax(1.0, CGRectGetHeight(self.canvasView.bounds));
    CGFloat startGradY = (CGFloat)DBClamp01(islandBottomY / canvasH);
    CGFloat endGradY = (CGFloat)DBClamp01(clampedAttachY / canvasH);

    UIColor *bottomColor = self.tintColor ?: [UIColor blackColor];

    [UIView performWithoutAnimation:^{
        [CATransaction begin];
        [CATransaction setDisableActions:YES];

        if (pulsePath && pulseAlpha > 0.01) {
            self.islandPulseLayer.path = pulsePath.CGPath;
            self.islandPulseLayer.opacity = (float)pulseAlpha;
        } else {
            self.islandPulseLayer.path = NULL;
            self.islandPulseLayer.opacity = 0.0f;
        }

        if (neckPath) {
            self.neckMaskLayer.path = neckPath.CGPath;
            self.neckGradientLayer.startPoint = CGPointMake(0.5, startGradY);
            self.neckGradientLayer.endPoint = CGPointMake(0.5, endGradY);
            self.neckGradientLayer.colors = @[ (id)[UIColor blackColor].CGColor, (id)bottomColor.CGColor ];
            self.neckGradientLayer.opacity = (float)DBClamp01(p * 1.15);
        } else {
            self.neckMaskLayer.path = NULL;
            self.neckGradientLayer.opacity = 0.0f;
        }

        [CATransaction commit];
    }];
}

- (void)updateInteractiveCard:(UIView *)cardView window:(UIWindow *)win upwardPull:(CGFloat)upwardPull cardTopY:(CGFloat)cardTopY cardMidX:(CGFloat)cardMidX cardWidth:(CGFloat)cardWidth tintColor:(UIColor *)tintColor {
    if (!gMagneticSwipeNeckEnabled || DBShouldSkipGlobally()) {
        [self cancelImmediate];
        return;
    }

    if (self.collapseLink) {
        [self.collapseLink invalidate];
        self.collapseLink = nil;
        self.collapseProxy = nil;
    }

    if (upwardPull <= 2.0) {
        if (self.active) {
            [self db_renderNeckProgress:0.0 attachY:cardTopY + 10.0 cardMidX:cardMidX cardWidth:cardWidth];
        }
        return;
    }

    if (![self db_ensureOverlayForWindow:win tintColor:tintColor]) return;

    CGFloat reachDistance = (CGFloat)(52.0 / fmax(0.5, gMagneticNeckStrength));
    CGFloat pullProg = (CGFloat)DBClamp01(upwardPull / reachDistance);
    CGFloat islandBottomY = CGRectGetMaxY(self.cutoutRect) - 4.0;
    CGFloat gap = fmax(0.0, cardTopY - islandBottomY);
    CGFloat proximityProg = (CGFloat)DBClamp01(1.0 - (gap / (54.0 * fmax(0.6, gMagneticNeckStrength))));
    CGFloat combinedProg = (CGFloat)DBClamp01(fmax(pullProg, pullProg * 0.55 + proximityProg * 0.45));

    if (gHapticsEnabled && self.hapticGenerator && !self.latchHapticFired && combinedProg >= 0.48) {
        self.latchHapticFired = YES;
        [self.hapticGenerator impactOccurred];
    }

    self.trackedCard = cardView;
    self.lastPullProgress = combinedProg;
    self.lastAttachY = cardTopY + 12.0;
    self.lastCardMidX = cardMidX;
    self.lastCardWidth = cardWidth;

    [self db_renderNeckProgress:combinedProg attachY:self.lastAttachY cardMidX:cardMidX cardWidth:cardWidth];
}

- (void)db_handleBannerPan:(UIPanGestureRecognizer *)pan {
    if (!gMagneticSwipeNeckEnabled || DBShouldSkipGlobally()) {
        if (self.active) [self cancelImmediate];
        return;
    }
    // Never overlap with an active entry or exit droplet animation
    if (gActiveAnimator) return;

    UIView *cardView = pan.view;
    UIWindow *win = cardView.window;
    if (!cardView || !win) {
        if (self.active) [self cancelImmediate];
        return;
    }

    if (pan.state == UIGestureRecognizerStateBegan) {
        self.startCardRect = [cardView convertRect:cardView.bounds toCoordinateSpace:win.coordinateSpace];
        return;
    }

    if (pan.state == UIGestureRecognizerStateChanged) {
        CGPoint trans = [pan translationInView:win];
        CGFloat upwardPull = -trans.y;

        CGRect liveRect = [cardView convertRect:cardView.bounds toCoordinateSpace:win.coordinateSpace];
        if (cardView.layer.presentationLayer && win.layer.presentationLayer) {
            CGRect presRect = [cardView.layer.presentationLayer convertRect:cardView.layer.presentationLayer.bounds
                                                                    toLayer:win.layer.presentationLayer];
            if (!CGRectIsEmpty(presRect) && presRect.size.width >= 120.0) {
                liveRect = presRect;
            }
        }
        // If BannerKit hasn't moved the layer yet on the first drag pixels, approximate smoothly from translation
        CGFloat cardTopY = liveRect.origin.y;
        if (!CGRectIsEmpty(self.startCardRect) && fabs(cardTopY - self.startCardRect.origin.y) < 1.0 && upwardPull > 2.0) {
            cardTopY = self.startCardRect.origin.y - upwardPull * 0.55;
        }

        UIColor *tint = nil;
        if (gDropletColorMode == DBDropletColorModeCustom) {
            tint = gCustomDropletColor ?: [UIColor systemBlueColor];
        } else if (gDropletColorMode == DBDropletColorModeAppIcon) {
            tint = objc_getAssociatedObject(cardView, kDBViewDropletColorKey);
        }

        [self updateInteractiveCard:cardView
                             window:win
                         upwardPull:upwardPull
                           cardTopY:cardTopY
                           cardMidX:CGRectGetMidX(liveRect)
                          cardWidth:CGRectGetWidth(liveRect)
                          tintColor:tint];
        return;
    }

    if (pan.state == UIGestureRecognizerStateEnded ||
        pan.state == UIGestureRecognizerStateCancelled ||
        pan.state == UIGestureRecognizerStateFailed) {
        if (self.active) {
            [self beginCollapse];
        }
    }
}

- (void)beginCollapse {
    if (!self.active || !self.overlayWindow) {
        [self cancelImmediate];
        return;
    }
    if (self.collapseLink) {
        [self.collapseLink invalidate];
        self.collapseLink = nil;
    }
    self.collapseStartProgress = self.lastPullProgress;
    self.collapseStartedAt = CACurrentMediaTime();
    self.collapseProxy = [[DBMagneticLinkProxy alloc] init];
    self.collapseProxy.owner = self;
    self.collapseLink = [CADisplayLink displayLinkWithTarget:self.collapseProxy selector:@selector(tickCollapse:)];
    if (@available(iOS 15.0, *)) {
        self.collapseLink.preferredFrameRateRange = CAFrameRateRangeMake(60, 120, 120);
    }
    [self.collapseLink addToRunLoop:[NSRunLoop mainRunLoop] forMode:NSRunLoopCommonModes];
}

- (void)db_tickCollapse:(CADisplayLink *)link {
    CFTimeInterval elapsed = CACurrentMediaTime() - self.collapseStartedAt;
    double p = DBClamp01(elapsed / 0.18);
    if (p >= 1.0) {
        [self cancelImmediate];
        return;
    }
    double rem = (1.0 - p) * (1.0 - p);
    [self db_renderNeckProgress:(CGFloat)(self.collapseStartProgress * rem)
                        attachY:self.lastAttachY
                       cardMidX:self.lastCardMidX
                      cardWidth:self.lastCardWidth];
}

- (void)cancelImmediate {
    if (self.collapseLink) {
        [self.collapseLink invalidate];
        self.collapseLink = nil;
    }
    self.collapseProxy = nil;
    self.hapticGenerator = nil;
    self.active = NO;
    self.latchHapticFired = NO;
    self.lastPullProgress = 0.0;

    if (self.motionAcquired) {
        self.motionAcquired = NO;
        [[DBMotionTracker shared] releaseMotion];
    }

    [UIView performWithoutAnimation:^{
        [CATransaction begin];
        [CATransaction setDisableActions:YES];

        if (self.neckGradientLayer) {
            [self.neckGradientLayer removeFromSuperlayer];
            self.neckGradientLayer = nil;
        }
        self.neckMaskLayer = nil;
        if (self.islandPulseLayer) {
            [self.islandPulseLayer removeFromSuperlayer];
            self.islandPulseLayer = nil;
        }
        if (self.overlayWindow) {
            self.overlayWindow.hidden = YES;
            self.overlayWindow.rootViewController = nil;
            self.overlayWindow = nil;
        }
        self.canvasView = nil;

        [CATransaction commit];
    }];

    self.trackedCard = nil;
    self.sourceWindow = nil;
}

@end

#pragma mark - Built-In Live Preview Banner (Triggered From Settings)

@interface DBPreviewBannerWindow : UIWindow
@property (nonatomic, weak) UIView *interactiveCard;
@end

@implementation DBPreviewBannerWindow

- (BOOL)canBecomeKeyWindow {
    return NO;
}

- (UIView *)hitTest:(CGPoint)point withEvent:(UIEvent *)event {
    UIView *hit = [super hitTest:point withEvent:event];
    if (self.interactiveCard && hit && [hit isDescendantOfView:self.interactiveCard]) {
        return hit;
    }
    return nil;
}

@end

@interface DBPreviewManager : NSObject
@property (nonatomic, strong) DBPreviewBannerWindow *previewWindow;
@property (nonatomic, weak) UIView *previewCard;
@property (nonatomic, strong) UIColor *sampleColor;
@property (nonatomic, assign) NSUInteger token;
@property (nonatomic, assign) NSUInteger sampleIndex;
@property (nonatomic, assign) BOOL dismissing;
@property (nonatomic, assign) BOOL dragging;
@property (nonatomic, assign) CGRect restingCardFrame;
+ (instancetype)shared;
- (void)showPreview;
- (void)dismissPreviewFromSwipe:(BOOL)fromSwipe;
@end

@implementation DBPreviewManager

+ (instancetype)shared {
    static DBPreviewManager *instance = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        instance = [[DBPreviewManager alloc] init];
    });
    return instance;
}

- (UIWindowScene *)activeWindowScene {
    UIWindowScene *fallback = nil;
    for (UIScene *scene in [UIApplication sharedApplication].connectedScenes) {
        if (![scene isKindOfClass:[UIWindowScene class]]) continue;
        UIWindowScene *ws = (UIWindowScene *)scene;
        if (ws.activationState == UISceneActivationStateForegroundActive) {
            return ws;
        }
        if (!fallback) fallback = ws;
    }
    return fallback;
}

- (void)teardownWindow {
    if (self.previewWindow) {
        self.previewWindow.hidden = YES;
        self.previewWindow.rootViewController = nil;
        self.previewWindow = nil;
    }
    self.previewCard = nil;
    self.dismissing = NO;
}

- (void)handlePreviewPan:(UIPanGestureRecognizer *)pan {
    if (self.dismissing || !self.previewCard || !self.previewWindow) return;
    if (gActiveAnimator) return;

    UIView *card = self.previewCard;
    UIWindow *win = self.previewWindow;

    UIColor *activeTint = nil;
    if (gDropletColorMode == DBDropletColorModeAppIcon) {
        activeTint = self.sampleColor;
    } else if (gDropletColorMode == DBDropletColorModeCustom) {
        activeTint = gCustomDropletColor ?: [UIColor systemBlueColor];
    }

    if (pan.state == UIGestureRecognizerStateBegan) {
        self.dragging = YES;
        return;
    }

    if (pan.state == UIGestureRecognizerStateChanged) {
        CGPoint trans = [pan translationInView:win];
        CGFloat dy = trans.y;
        // Rubber-band downward drags; follow upward drags smoothly toward the Dynamic Island
        CGFloat visualDy = (dy < 0.0) ? fmax(-68.0, dy * 0.78) : fmin(16.0, dy * 0.25);
        card.transform = CGAffineTransformMakeTranslation(0.0, visualDy);

        CGFloat liveTopY = self.restingCardFrame.origin.y + visualDy;
        [[DBMagneticNeckController shared] updateInteractiveCard:card
                                                          window:win
                                                      upwardPull:fmax(0.0, -dy)
                                                        cardTopY:liveTopY
                                                        cardMidX:CGRectGetMidX(self.restingCardFrame)
                                                       cardWidth:CGRectGetWidth(self.restingCardFrame)
                                                       tintColor:activeTint];
        return;
    }

    if (pan.state == UIGestureRecognizerStateEnded ||
        pan.state == UIGestureRecognizerStateCancelled ||
        pan.state == UIGestureRecognizerStateFailed) {
        self.dragging = NO;
        CGPoint trans = [pan translationInView:win];
        CGPoint vel = [pan velocityInView:win];
        if (trans.y < -26.0 || vel.y < -240.0) {
            [[DBMagneticNeckController shared] cancelImmediate];
            [self dismissPreviewFromSwipe:YES];
        } else {
            [[DBMagneticNeckController shared] beginCollapse];
            [UIView animateWithDuration:0.32 delay:0.0 usingSpringWithDamping:0.78 initialSpringVelocity:0.5 options:0 animations:^{
                card.transform = CGAffineTransformIdentity;
            } completion:nil];
            NSUInteger myToken = self.token;
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(2.2 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
                if (self.token == myToken && !self.dismissing && !self.dragging && self.previewWindow) {
                    [self dismissPreviewFromSwipe:NO];
                }
            });
        }
    }
}

- (void)handleTap:(UITapGestureRecognizer *)gesture {
    [self dismissPreviewFromSwipe:YES];
}

- (void)showPreview {
    DBLoadPreferences();

    self.token += 1;
    NSUInteger myToken = self.token;
    if (gActiveAnimator) {
        [gActiveAnimator stop];
    }
    [self teardownWindow];

    UIWindowScene *scene = [self activeWindowScene];
    CGRect bounds = scene ? scene.coordinateSpace.bounds : [UIScreen mainScreen].bounds;

    DBPreviewBannerWindow *win = scene
        ? [[DBPreviewBannerWindow alloc] initWithWindowScene:scene]
        : [[DBPreviewBannerWindow alloc] initWithFrame:bounds];
    win.frame = bounds;
    win.windowLevel = UIWindowLevelStatusBar + 50.0;
    win.backgroundColor = [UIColor clearColor];

    UIViewController *rootVC = [[UIViewController alloc] init];
    rootVC.view.backgroundColor = [UIColor clearColor];
    rootVC.view.frame = bounds;
    win.rootViewController = rootVC;
    win.hidden = NO;
    [win layoutIfNeeded];

    CGRect cutout = DBResolveCutoutRectForWindow(win);
    CGFloat cardW = fmin(bounds.size.width - 24.0, 390.0);
    CGFloat cardH = 78.0;
    CGFloat cardX = round((bounds.size.width - cardW) * 0.5);
    CGFloat cardY = CGRectGetMaxY(cutout) + 10.0;

    // Cycle through crisp Apple-style app badge colors so App Icon Color & Bloom Rim are immediately visible
    NSArray<UIColor *> *palette = @[
        [UIColor colorWithRed:0.039 green:0.518 blue:1.000 alpha:1.0], // iOS Blue
        [UIColor colorWithRed:0.188 green:0.820 blue:0.345 alpha:1.0], // WhatsApp / Messages Green
        [UIColor colorWithRed:1.000 green:0.176 blue:0.333 alpha:1.0], // Music / Instagram Pink
        [UIColor colorWithRed:1.000 green:0.584 blue:0.000 alpha:1.0], // Warm Orange
        [UIColor colorWithRed:0.686 green:0.322 blue:0.871 alpha:1.0], // Vivid Purple
    ];
    UIColor *badgeColor = palette[self.sampleIndex % palette.count];
    self.sampleIndex += 1;
    self.sampleColor = badgeColor;

    UIView *card = [[UIView alloc] initWithFrame:CGRectMake(cardX, cardY, cardW, cardH)];
    card.backgroundColor = [UIColor clearColor];
    card.layer.cornerRadius = 26.0;
    card.layer.cornerCurve = kCACornerCurveContinuous;
    card.layer.shadowColor = [UIColor blackColor].CGColor;
    card.layer.shadowOpacity = 0.24;
    card.layer.shadowRadius = 18.0;
    card.layer.shadowOffset = CGSizeMake(0.0, 8.0);

    UIBlurEffect *blur = [UIBlurEffect effectWithStyle:UIBlurEffectStyleSystemChromeMaterial];
    UIVisualEffectView *bg = [[UIVisualEffectView alloc] initWithEffect:blur];
    bg.frame = card.bounds;
    bg.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    bg.layer.cornerRadius = 26.0;
    bg.layer.cornerCurve = kCACornerCurveContinuous;
    bg.clipsToBounds = YES;
    [card addSubview:bg];

    // Sample app icon badge
    UIView *iconBadge = [[UIView alloc] initWithFrame:CGRectMake(14.0, (cardH - 40.0) * 0.5, 40.0, 40.0)];
    iconBadge.backgroundColor = badgeColor;
    iconBadge.layer.cornerRadius = 10.0;
    iconBadge.layer.cornerCurve = kCACornerCurveContinuous;
    UIImageView *bellGlyph = [[UIImageView alloc] initWithImage:[UIImage systemImageNamed:@"bell.fill"]];
    bellGlyph.tintColor = [UIColor whiteColor];
    bellGlyph.contentMode = UIViewContentModeScaleAspectFit;
    bellGlyph.frame = CGRectInset(iconBadge.bounds, 9.0, 9.0);
    [iconBadge addSubview:bellGlyph];
    [bg.contentView addSubview:iconBadge];

    UILabel *titleLabel = [[UILabel alloc] initWithFrame:CGRectMake(66.0, 17.0, cardW - 122.0, 20.0)];
    titleLabel.text = @"DropletBanner";
    titleLabel.font = [UIFont systemFontOfSize:15.0 weight:UIFontWeightSemibold];
    titleLabel.textColor = [UIColor labelColor];
    [bg.contentView addSubview:titleLabel];

    UILabel *timeLabel = [[UILabel alloc] initWithFrame:CGRectMake(cardW - 56.0, 17.0, 42.0, 18.0)];
    timeLabel.text = @"now";
    timeLabel.font = [UIFont systemFontOfSize:12.5 weight:UIFontWeightRegular];
    timeLabel.textColor = [UIColor secondaryLabelColor];
    timeLabel.textAlignment = NSTextAlignmentRight;
    [bg.contentView addSubview:timeLabel];

    UILabel *bodyLabel = [[UILabel alloc] initWithFrame:CGRectMake(66.0, 39.0, cardW - 82.0, 20.0)];
    bodyLabel.text = @"Drag up for magnetic neck • tilt for gyro";
    bodyLabel.font = [UIFont systemFontOfSize:14.0 weight:UIFontWeightRegular];
    bodyLabel.textColor = [UIColor secondaryLabelColor];
    [bg.contentView addSubview:bodyLabel];

    UIPanGestureRecognizer *pan = [[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(handlePreviewPan:)];
    [card addGestureRecognizer:pan];

    UITapGestureRecognizer *tap = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(handleTap:)];
    [card addGestureRecognizer:tap];

    [rootVC.view addSubview:card];
    win.interactiveCard = card;
    self.previewWindow = win;
    self.previewCard = card;
    self.restingCardFrame = card.frame;
    self.dismissing = NO;
    self.dragging = NO;

    UIColor *activeTint = nil;
    if (gDropletColorMode == DBDropletColorModeAppIcon) {
        activeTint = badgeColor;
    } else if (gDropletColorMode == DBDropletColorModeCustom) {
        activeTint = gCustomDropletColor ?: [UIColor systemBlueColor];
    }

    if (!DBShouldSkipGlobally()) {
        DBDropletAnimator *animator = [[DBDropletAnimator alloc] init];
        gActiveAnimator = animator;
        [animator startEntryForView:card dropletColor:activeTint];
    } else {
        // Show stock-like slide-in when disabled / Low Power Mode so user can compare live
        card.transform = CGAffineTransformMakeTranslation(0.0, -(cardY + cardH));
        card.alpha = 0.0;
        [UIView animateWithDuration:0.32 delay:0.0 usingSpringWithDamping:0.86 initialSpringVelocity:0.6 options:0 animations:^{
            card.transform = CGAffineTransformIdentity;
            card.alpha = 1.0;
        } completion:nil];
    }

    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(3.6 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        if (self.token == myToken && !self.dismissing && !self.dragging && self.previewWindow) {
            [self dismissPreviewFromSwipe:NO];
        }
    });
}

- (void)dismissPreviewFromSwipe:(BOOL)fromSwipe {
    if (self.dismissing || !self.previewWindow || !self.previewCard) return;
    self.dismissing = YES;
    self.dragging = NO;
    [[DBMagneticNeckController shared] cancelImmediate];

    NSUInteger myToken = self.token;
    UIView *card = self.previewCard;

    UIColor *activeTint = nil;
    if (gDropletColorMode == DBDropletColorModeAppIcon) {
        activeTint = self.sampleColor;
    } else if (gDropletColorMode == DBDropletColorModeCustom) {
        activeTint = gCustomDropletColor ?: [UIColor systemBlueColor];
    }

    if (!DBShouldSkipGlobally() && gAnimateDismiss) {
        if (gActiveAnimator) {
            [gActiveAnimator stop];
        }
        DBDropletAnimator *exitAnimator = [[DBDropletAnimator alloc] init];
        __weak typeof(self) weakSelf = self;
        exitAnimator.completionHandler = ^{
            if (weakSelf && weakSelf.token == myToken) {
                [weakSelf teardownWindow];
            }
        };
        gActiveAnimator = exitAnimator;
        [exitAnimator startExitForView:card fromSwipe:fromSwipe dropletColor:activeTint];
    } else {
        [UIView animateWithDuration:0.24 animations:^{
            card.transform = CGAffineTransformMakeTranslation(0.0, -140.0);
            card.alpha = 0.0;
        } completion:^(BOOL finished) {
            if (self.token == myToken) {
                [self teardownWindow];
            }
        }];
    }
}

@end

static void DBTestPreviewCallback(CFNotificationCenterRef center, void *observer, CFStringRef name, const void *object, CFDictionaryRef userInfo) {
    dispatch_async(dispatch_get_main_queue(), ^{
        [[DBPreviewManager shared] showPreview];
    });
}

#pragma mark - Banner View Extraction & Rapid-Fire Coordination

static BOOL DBIsBannerViewController(UIViewController *vc) {
    if (!vc) return NO;
    UIWindow *win = vc.viewIfLoaded.window;
    if (win) {
        NSString *winCls = NSStringFromClass(win.class);
        if ([winCls localizedCaseInsensitiveContainsString:@"banner"]) {
            return YES;
        }
    }
    UIViewController *parent = vc.parentViewController;
    while (parent) {
        NSString *pCls = NSStringFromClass(parent.class);
        if ([pCls localizedCaseInsensitiveContainsString:@"banner"] ||
            [pCls hasPrefix:@"BN"] ||
            [pCls localizedCaseInsensitiveContainsString:@"presentable"]) {
            return YES;
        }
        parent = parent.parentViewController;
    }
    return NO;
}

static UIView *DBExtractBannerViewFromPresentable(id<BNPresentable> presentable) {
    if (!presentable) return nil;
    UIViewController *vc = nil;

    if ([presentable respondsToSelector:@selector(notificationViewController)]) {
        vc = [presentable notificationViewController];
    } else {
        @try {
            id val = [(id)presentable valueForKey:@"notificationViewController"];
            if ([val isKindOfClass:[UIViewController class]]) {
                vc = (UIViewController *)val;
            }
        } @catch (NSException *exception) {}
    }

    if (!vc && [presentable respondsToSelector:@selector(viewController)]) {
        vc = [presentable viewController];
    }
    if (!vc && [presentable isKindOfClass:[UIViewController class]]) {
        vc = (UIViewController *)presentable;
    }

    if (!vc) return nil;
    return vc.viewIfLoaded ?: vc.view;
}

static void DBLaunchEntryForView(UIView *view, id sourceObj) {
    if (!view || !view.window) return;
    if (DBShouldSkipGlobally()) return;
    if (DBIsSourceExcluded(sourceObj)) return;

    CFTimeInterval now = CACurrentMediaTime();
    NSNumber *lastEntryNum = objc_getAssociatedObject(view, kDBViewEntryTimestampKey);
    if (lastEntryNum && (now - lastEntryNum.doubleValue < 0.60)) {
        return;
    }
    objc_setAssociatedObject(view, kDBViewEntryTimestampKey, @(now), OBJC_ASSOCIATION_RETAIN_NONATOMIC);

    [[DBMagneticNeckController shared] cancelImmediate];
    if (gActiveAnimator) {
        [gActiveAnimator stop];
    }

    UIColor *dropColor = DBResolveDropletColor(sourceObj, view);
    [[DBMagneticNeckController shared] attachToBannerView:view dropletColor:dropColor];

    DBDropletAnimator *animator = [[DBDropletAnimator alloc] init];
    gActiveAnimator = animator;
    [animator startEntryForView:view dropletColor:dropColor];
}

static void DBScheduleEntryForPresentable(id<BNPresentable> presentable, NSInteger attempt) {
    if (!presentable) return;
    if (gLatestPresentable && gLatestPresentable != presentable) return;

    UIView *bannerView = DBExtractBannerViewFromPresentable(presentable);
    if (bannerView && bannerView.window && !CGRectIsEmpty(bannerView.bounds)) {
        DBLaunchEntryForView(bannerView, presentable);
        return;
    }
    if (attempt < 15) {
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.012 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            DBScheduleEntryForPresentable(presentable, attempt + 1);
        });
    }
}

static void DBScheduleEntryForViewController(UIViewController *vc, NSInteger attempt) {
    if (!vc) return;
    UIView *v = vc.viewIfLoaded;
    if (v && v.window && !CGRectIsEmpty(v.bounds)) {
        if (DBIsBannerViewController(vc)) {
            DBLaunchEntryForView(v, vc);
        }
        return;
    }
    if (attempt < 15) {
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.012 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            DBScheduleEntryForViewController(vc, attempt + 1);
        });
    }
}

#pragma mark - SpringBoard Hooks

%hook SBNotificationBannerDestination

- (void)presentableWillAppearAsBanner:(id<BNPresentable>)presentable {
    if (!DBShouldSkipGlobally() && !DBIsSourceExcluded(presentable)) {
        gLatestPresentable = presentable;
        gLatestEntryRequestTime = CACurrentMediaTime();
    }

    %orig;
    if (DBShouldSkipGlobally() || DBIsSourceExcluded(presentable)) return;

    UIView *bannerView = DBExtractBannerViewFromPresentable(presentable);
    if (bannerView && bannerView.window && !CGRectIsEmpty(bannerView.bounds)) {
        DBLaunchEntryForView(bannerView, presentable);
    } else {
        dispatch_async(dispatch_get_main_queue(), ^{
            DBScheduleEntryForPresentable(presentable, 0);
        });
    }
}

- (void)presentableWillDisappearAsBanner:(id<BNPresentable>)presentable withReason:(NSString *)reason {
    if (!DBShouldSkipGlobally() && gAnimateDismiss && !DBIsSourceExcluded(presentable)) {
        NSString *lowerReason = reason ? reason.lowercaseString : @"";

        BOOL isTapOrExpand = ([lowerReason containsString:@"tap"] ||
                              [lowerReason containsString:@"action"] ||
                              [lowerReason containsString:@"open"] ||
                              [lowerReason containsString:@"launch"] ||
                              [lowerReason containsString:@"select"] ||
                              [lowerReason containsString:@"longlook"] ||
                              [lowerReason containsString:@"expand"]);

        BOOL isSwipeDismiss = ([lowerReason containsString:@"gesture"] ||
                               [lowerReason containsString:@"drag"] ||
                               [lowerReason containsString:@"pan"] ||
                               [lowerReason containsString:@"swipe"] ||
                               [lowerReason containsString:@"user"]);

        BOOL isReplacement = ([lowerReason containsString:@"replace"] ||
                              [lowerReason containsString:@"supersed"] ||
                              [lowerReason containsString:@"preempt"]);

        CFTimeInterval now = CACurrentMediaTime();
        BOOL newerIncoming = (gLatestPresentable && gLatestPresentable != presentable &&
                              ((gActiveAnimator && !gActiveAnimator.exiting) || (now - gLatestEntryRequestTime < 0.45)));

        [[DBMagneticNeckController shared] cancelImmediate];
        if (isTapOrExpand) {
            if (gActiveAnimator) {
                [gActiveAnimator stop];
            }
        } else if (newerIncoming || isReplacement) {
            UIView *oldView = DBExtractBannerViewFromPresentable(presentable);
            if (oldView && oldView.window) {
                UIView *oldCard = DBFindCardView(oldView, oldView.window);
                UIView *oldContainer = DBFindPerBannerContainer(oldCard, oldView.window);
                if (oldContainer && (!gActiveAnimator || gActiveAnimator.hideContainer != oldContainer)) {
                    [UIView performWithoutAnimation:^{
                        oldContainer.hidden = YES;
                        oldContainer.alpha = 0.0;
                    }];
                }
            }
        } else {
            UIView *bannerView = DBExtractBannerViewFromPresentable(presentable);
            if (bannerView && bannerView.window) {
                if (gActiveAnimator) {
                    [gActiveAnimator stop];
                }
                UIColor *dropColor = nil;
                if (gDropletColorMode == DBDropletColorModeCustom) {
                    dropColor = gCustomDropletColor ?: [UIColor systemBlueColor];
                } else if (gDropletColorMode == DBDropletColorModeAppIcon) {
                    dropColor = objc_getAssociatedObject(bannerView, kDBViewDropletColorKey);
                    if (!dropColor) {
                        dropColor = DBResolveDropletColor(presentable, bannerView);
                    }
                }
                DBDropletAnimator *exitAnimator = [[DBDropletAnimator alloc] init];
                gActiveAnimator = exitAnimator;
                [exitAnimator startExitForView:bannerView fromSwipe:isSwipeDismiss dropletColor:dropColor];
            }
        }
    }
    %orig;
}

%end

%hook NCNotificationShortLookViewController

- (void)viewWillAppear:(BOOL)animated {
    %orig;
    if (DBShouldSkipGlobally() || DBIsSourceExcluded(self)) return;

    UIView *v = self.viewIfLoaded;
    if (v && v.window && !CGRectIsEmpty(v.bounds) && DBIsBannerViewController(self)) {
        DBLaunchEntryForView(v, self);
    } else {
        dispatch_async(dispatch_get_main_queue(), ^{
            DBScheduleEntryForViewController(self, 0);
        });
    }
}

%end

%ctor {
    DBLoadPreferences();
    CFNotificationCenterAddObserver(
        CFNotificationCenterGetDarwinNotifyCenter(),
        NULL,
        DBPrefsChangedCallback,
        (__bridge CFStringRef)kPrefsChangedNotification,
        NULL,
        CFNotificationSuspensionBehaviorDeliverImmediately
    );
    CFNotificationCenterAddObserver(
        CFNotificationCenterGetDarwinNotifyCenter(),
        NULL,
        DBTestPreviewCallback,
        (__bridge CFStringRef)kTestPreviewNotification,
        NULL,
        CFNotificationSuspensionBehaviorDeliverImmediately
    );
    %init;
}
