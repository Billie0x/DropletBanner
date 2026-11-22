#import <UIKit/UIKit.h>
#import <QuartzCore/QuartzCore.h>
#import <CoreGraphics/CoreGraphics.h>
#import <CoreFoundation/CoreFoundation.h>
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

static BOOL gEnabled = YES;
static BOOL gAnimateDismiss = YES;
static BOOL gTintDropletWithAppIcon = YES;
static double gEntryDuration = 0.48;
static double gAmplitude = 1.0;

static void DBLoadPreferences(void) {
    CFPreferencesAppSynchronize((__bridge CFStringRef)kPrefsDomain);

    id enabledObj = CFBridgingRelease(CFPreferencesCopyAppValue(CFSTR("Enabled"), (__bridge CFStringRef)kPrefsDomain));
    gEnabled = enabledObj ? [enabledObj boolValue] : YES;

    id dismissObj = CFBridgingRelease(CFPreferencesCopyAppValue(CFSTR("AnimateDismiss"), (__bridge CFStringRef)kPrefsDomain));
    gAnimateDismiss = dismissObj ? [dismissObj boolValue] : YES;

    id tintObj = CFBridgingRelease(CFPreferencesCopyAppValue(CFSTR("TintDropletWithAppIcon"), (__bridge CFStringRef)kPrefsDomain));
    gTintDropletWithAppIcon = tintObj ? [tintObj boolValue] : YES;

    id durObj = CFBridgingRelease(CFPreferencesCopyAppValue(CFSTR("EntryDuration"), (__bridge CFStringRef)kPrefsDomain));
    gEntryDuration = durObj ? fmin(fmax([durObj doubleValue], 0.25), 0.90) : 0.48;

    id ampObj = CFBridgingRelease(CFPreferencesCopyAppValue(CFSTR("DropletAmplitude"), (__bridge CFStringRef)kPrefsDomain));
    gAmplitude = ampObj ? fmin(fmax([ampObj doubleValue], 0.40), 1.60) : 1.0;
}

static void DBPrefsChangedCallback(CFNotificationCenterRef center, void *observer, CFStringRef name, const void *object, CFDictionaryRef userInfo) {
    DBLoadPreferences();
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

static CGRect DBResolveCutoutRectForWindow(UIWindow *window) {
    CGSize size = window.bounds.size;
    CGFloat topInset = window.safeAreaInsets.top;
    CGFloat midX = size.width * 0.5;

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

#pragma mark - App Icon Dominant Color Extraction

static NSCache<NSString *, UIColor *> *gIconColorCache = nil;
static const void *kDBViewDropletColorKey = &kDBViewDropletColorKey;

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

        // Ignore near-white, near-black, and low-saturation grays when finding the signature brand color
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
                // Keep the water drop rich and readable without blowing out to harsh neon
                s = fmin(0.92, fmax(s, 0.58));
                v = fmin(0.94, fmax(v, 0.52));
                return [UIColor colorWithHue:h saturation:s brightness:v alpha:1.0];
            }
            return rawColor;
        }
    }

    // Monochrome icon fallback (e.g. X, Threads, Settings): keep black icons black, silver/white icons clean gray
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
                        // App icons sit near the leading edge (or trailing edge in RTL)
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

static UIColor *DBResolveAppIconColor(id sourceObj, UIView *bannerView) {
    if (!gTintDropletWithAppIcon) return nil;

    if (!gIconColorCache) {
        gIconColorCache = [[NSCache alloc] init];
        gIconColorCache.countLimit = 64;
    }

    // Extract NCNotificationRequest from presentable or view controller
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

    // 1. Primary: NCNotificationRequest.content.icons
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

    // 2. Secondary: SpringBoard icon services via sectionIdentifier
    if (!iconImage && sectionID && [UIImage respondsToSelector:@selector(_applicationIconImageForBundleIdentifier:format:scale:)]) {
        @try {
            iconImage = [UIImage _applicationIconImageForBundleIdentifier:sectionID format:2 scale:1.0];
        } @catch (NSException *exception) {}
    }

    // 3. Fallback: inspect live banner view hierarchy for app icon UIImageView
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

#pragma mark - Droplet Animator

@interface DBDropletAnimator : NSObject
@property (nonatomic, weak) UIView *contentView;
@property (nonatomic, weak) UIView *hideContainer;
@property (nonatomic, weak) UIWindow *sourceWindow;
@property (nonatomic, strong) DBDropletEffectWindow *effectWindow;
@property (nonatomic, strong) UIView *canvasView;
@property (nonatomic, strong) CAGradientLayer *neckGradientLayer;
@property (nonatomic, strong) CAShapeLayer *neckMaskLayer;
@property (nonatomic, strong) CAShapeLayer *bodyLayer;
@property (nonatomic, strong) UIImageView *exitSnapshotView;
@property (nonatomic, strong) UIColor *surfaceColor;
@property (nonatomic, strong) UIColor *dropletTintColor;
@property (nonatomic, strong) CADisplayLink *displayLink;
@property (nonatomic, strong) DBDisplayLinkProxy *proxy;
@property (nonatomic, assign) CFTimeInterval startedAt;
@property (nonatomic, assign) CFTimeInterval duration;
@property (nonatomic, assign) BOOL exiting;
@property (nonatomic, assign) CGRect cutoutRect;
@property (nonatomic, assign) CGRect cardRect;
@property (nonatomic, assign) CGFloat cardCornerRadius;
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

    BOOL wasExiting = self.exiting;
    UIView *containerToRestore = self.hideContainer;
    UIView *contentToRestore = self.contentView;
    self.hideContainer = nil;
    self.contentView = nil;

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
        if (self.bodyLayer) {
            [self.bodyLayer removeFromSuperlayer];
            self.bodyLayer = nil;
        }
        if (self.neckGradientLayer) {
            [self.neckGradientLayer removeFromSuperlayer];
            self.neckGradientLayer = nil;
        }
        self.neckMaskLayer = nil;
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
}

- (BOOL)setupOverlayForView:(UIView *)rawView isExit:(BOOL)isExit fromSwipe:(BOOL)fromSwipe dropletColor:(UIColor *)dropletColor {
    UIWindow *win = rawView.window;
    if (!win) return NO;

    CGSize winSize = win.bounds.size;
    // Portrait only; keep native animation in landscape
    if (winSize.width > winSize.height || winSize.width < 250.0) return NO;

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

    if ((CGRectIsEmpty(frameInWin) || frameInWin.size.width < winSize.width * 0.55 || frameInWin.size.height < 34.0) &&
        !CGRectIsEmpty(gCachedRestingCardRect)) {
        frameInWin = gCachedRestingCardRect;
    }

    if (CGRectIsEmpty(frameInWin) || frameInWin.size.width < 120.0 || frameInWin.size.height < 34.0) {
        return NO;
    }

    CGFloat minRestingY = CGRectGetMaxY(cutout) + 10.0;
    if (!isExit) {
        if (frameInWin.origin.y < minRestingY - 4.0 || frameInWin.origin.y > winSize.height * 0.30) {
            frameInWin.origin.y = !CGRectIsEmpty(gCachedRestingCardRect) ? gCachedRestingCardRect.origin.y : minRestingY;
        }
    } else {
        CGFloat minVisibleSwipeY = CGRectGetMaxY(cutout) - 4.0;
        if (frameInWin.origin.y < CGRectGetMinY(cutout) - 10.0 || frameInWin.origin.y > winSize.height * 0.35) {
            frameInWin.origin.y = !CGRectIsEmpty(gCachedRestingCardRect) ? gCachedRestingCardRect.origin.y : minRestingY;
        } else if (fromSwipe && frameInWin.origin.y < minVisibleSwipeY) {
            frameInWin.origin.y = minVisibleSwipeY;
        }
    }
    frameInWin.origin.x = round((winSize.width - frameInWin.size.width) * 0.5);

    CGFloat cornerR = DBResolveCornerRadius(cardView);
    if (!isExit) {
        gCachedRestingCardRect = frameInWin;
        gCachedCornerRadius = cornerR;
    } else if (gCachedCornerRadius >= 14.0) {
        cornerR = gCachedCornerRadius;
    }

    self.contentView = cardView;
    self.hideContainer = container ?: cardView;
    self.sourceWindow = win;
    self.cutoutRect = cutout;
    self.cardRect = frameInWin;
    self.cardCornerRadius = cornerR;
    self.surfaceColor = [[UIColor secondarySystemBackgroundColor] resolvedColorWithTraitCollection:cardView.traitCollection];
    self.dropletTintColor = gTintDropletWithAppIcon ? dropletColor : nil;

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

    // Liquid neck uses a vertical gradient masked to the curved neck path so the pitch-black
    // Dynamic Island smoothly liquefies into the app-icon-colored water drop with zero seam.
    CAGradientLayer *neckGrad = [CAGradientLayer layer];
    neckGrad.frame = canvas.bounds;
    neckGrad.colors = @[ (id)[UIColor blackColor].CGColor, (id)[UIColor blackColor].CGColor ];
    neckGrad.locations = @[ @(0.0), @(1.0) ];

    CAShapeLayer *neckMask = [CAShapeLayer layer];
    neckMask.frame = canvas.bounds;
    neckMask.fillColor = [UIColor whiteColor].CGColor;
    neckGrad.mask = neckMask;
    [canvas.layer addSublayer:neckGrad];

    CAShapeLayer *body = [CAShapeLayer layer];
    body.frame = canvas.bounds;
    body.fillColor = [UIColor blackColor].CGColor;
    [canvas.layer addSublayer:body];

    self.effectWindow = overlay;
    self.canvasView = canvas;
    self.neckGradientLayer = neckGrad;
    self.neckMaskLayer = neckMask;
    self.bodyLayer = body;
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
            self.duration = fmin(fmax(0.84 * speedScale, 0.46), 1.45);

            self.hideContainer.hidden = YES;
            self.hideContainer.alpha = 0.0;

            self.startedAt = CACurrentMediaTime();
            [self renderNormalizedTime:0.0];
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
            self.duration = fmin(fmax(baseExit * speedScale, 0.24), 0.72);
            self.startedAt = CACurrentMediaTime();
            [self renderNormalizedTime:0.0];
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
    double normT = (self.duration > 0.0) ? (elapsed / self.duration) : 1.0;

    if (normT >= 1.0) {
        [self renderNormalizedTime:1.0];
        [self stop];
        return;
    }
    [self renderNormalizedTime:normT];
}

- (void)renderNormalizedTime:(double)normT {
    double amp = gAmplitude;
    double yProg = 0.0;
    double wProg = 0.0;
    double revealProg = 0.0;
    double neckProg = 0.0;

    if (!self.exiting) {
        double t = DBClamp01(normT) * 1.2;
        yProg = DBSpringCurve(t / 1.15, 7.38, 5.15127, 1.43266);
        wProg = DBSpringCurve((t - 0.32) / 0.86, 7.20, 5.40, 1.33333);
        revealProg = DBClamp01((t - 0.62) / 0.34);
        neckProg = DBSpringCurve((t - 0.11) / 0.70, 8.91, 1.26961, 7.01792);
    } else {
        double t = DBClamp01(normT) * 0.82;
        yProg = 1.0 - DBSpringCurve((t - 0.20) / 0.62, 7.60, 3.80, 1.95);
        wProg = 1.0 - DBSpringCurve((t - 0.04) / 0.48, 7.90, 3.50, 2.25);
        revealProg = 1.0 - DBClamp01(t / 0.20);
        neckProg = 1.0 - DBSpringCurve((t - 0.20) / 0.62, 7.60, 3.80, 1.95);
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

    double startMidY = CGRectGetMaxY(self.cutoutRect) - 0.34 * dropH;
    double curMidY = DBLerp(startMidY, CGRectGetMidY(self.cardRect), yProg);
    double curMidX = CGRectGetMidX(self.cutoutRect);

    CGRect curRect = CGRectMake(curMidX - curW * 0.5, curMidY - curH * 0.5, curW, curH);
    CGFloat maxR = (CGFloat)(fmin(curW, curH) * 0.5);
    CGFloat curRadius = (CGFloat)fmin(maxR, DBLerp(maxR, self.cardCornerRadius, DBClamp01(clampedWProg)));

    UIBezierPath *bodyPath = [UIBezierPath bezierPathWithRoundedRect:curRect cornerRadius:curRadius];

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

        neckPath = [UIBezierPath bezierPath];
        [neckPath moveToPoint:CGPointMake(curMidX - topHalfW, islandBottomY)];
        [neckPath addCurveToPoint:CGPointMake(curMidX - botHalfW, dropAttachY)
                    controlPoint1:CGPointMake(curMidX - pinchX, midY)
                    controlPoint2:CGPointMake(curMidX - pinchX, midY)];
        [neckPath addLineToPoint:CGPointMake(curMidX + botHalfW, dropAttachY)];
        [neckPath addCurveToPoint:CGPointMake(curMidX + topHalfW, islandBottomY)
                    controlPoint1:CGPointMake(curMidX + pinchX, midY)
                    controlPoint2:CGPointMake(curMidX + pinchX, midY)];
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

        // Keep ONLY the water drop tinted with the app icon color:
        // 1) Ramp black -> app icon color as the drop pulls out of the black Dynamic Island
        // 2) Smoothly transition app icon color -> neutral banner surface as it blooms into the full notification
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

    CGFloat canvasH = fmax(1.0, CGRectGetHeight(self.canvasView.bounds));
    CGFloat startGradY = (CGFloat)DBClamp01(islandBottomY / canvasH);
    CGFloat endGradY = (CGFloat)DBClamp01(fmax(islandBottomY + 2.0, dropAttachY) / canvasH);

    [UIView performWithoutAnimation:^{
        [CATransaction begin];
        [CATransaction setDisableActions:YES];

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

    CFTimeInterval now = CACurrentMediaTime();
    NSNumber *lastEntryNum = objc_getAssociatedObject(view, kDBViewEntryTimestampKey);
    if (lastEntryNum && (now - lastEntryNum.doubleValue < 0.60)) {
        return;
    }
    objc_setAssociatedObject(view, kDBViewEntryTimestampKey, @(now), OBJC_ASSOCIATION_RETAIN_NONATOMIC);

    if (gActiveAnimator) {
        [gActiveAnimator stop];
    }

    UIColor *dropColor = DBResolveAppIconColor(sourceObj, view);
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
    if (gEnabled && !UIAccessibilityIsReduceMotionEnabled()) {
        gLatestPresentable = presentable;
        gLatestEntryRequestTime = CACurrentMediaTime();
    }

    %orig;
    if (!gEnabled || UIAccessibilityIsReduceMotionEnabled()) return;

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
    if (gEnabled && gAnimateDismiss && !UIAccessibilityIsReduceMotionEnabled()) {
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
                if (gTintDropletWithAppIcon) {
                    dropColor = objc_getAssociatedObject(bannerView, kDBViewDropletColorKey);
                    if (!dropColor) {
                        dropColor = DBResolveAppIconColor(presentable, bannerView);
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
    if (!gEnabled || UIAccessibilityIsReduceMotionEnabled()) return;

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
    %init;
}
