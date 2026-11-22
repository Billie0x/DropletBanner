#import <UIKit/UIKit.h>
#import <QuartzCore/QuartzCore.h>
#import <CoreFoundation/CoreFoundation.h>
#import <objc/runtime.h>
#import <math.h>

#pragma mark - Private SpringBoard / BannerKit Declarations

@protocol BNPresentable <NSObject>
@optional
- (UIViewController *)notificationViewController;
- (UIViewController *)viewController;
@end

@interface SBNotificationBannerDestination : NSObject
- (void)presentableWillAppearAsBanner:(id<BNPresentable>)presentable;
- (void)presentableWillDisappearAsBanner:(id<BNPresentable>)presentable withReason:(NSString *)reason;
@end

@interface NCNotificationShortLookViewController : UIViewController
@end

#pragma mark - Preferences

static NSString *const kPrefsDomain = @"com.custom.dropletbanner";
static NSString *const kPrefsChangedNotification = @"com.custom.dropletbanner/prefsChanged";
static NSString *const kOpacityAnimKey = @"DBDropletNativeOpacity";

static BOOL gEnabled = YES;
static BOOL gAnimateDismiss = YES;
static double gEntryDuration = 0.48;
static double gAmplitude = 1.0;

static void DBLoadPreferences(void) {
    CFPreferencesAppSynchronize((__bridge CFStringRef)kPrefsDomain);

    id enabledObj = CFBridgingRelease(CFPreferencesCopyAppValue(CFSTR("Enabled"), (__bridge CFStringRef)kPrefsDomain));
    gEnabled = enabledObj ? [enabledObj boolValue] : YES;

    id dismissObj = CFBridgingRelease(CFPreferencesCopyAppValue(CFSTR("AnimateDismiss"), (__bridge CFStringRef)kPrefsDomain));
    gAnimateDismiss = dismissObj ? [dismissObj boolValue] : YES;

    id durObj = CFBridgingRelease(CFPreferencesCopyAppValue(CFSTR("EntryDuration"), (__bridge CFStringRef)kPrefsDomain));
    gEntryDuration = durObj ? fmin(fmax([durObj doubleValue], 0.25), 0.90) : 0.48;

    id ampObj = CFBridgingRelease(CFPreferencesCopyAppValue(CFSTR("DropletAmplitude"), (__bridge CFStringRef)kPrefsDomain));
    gAmplitude = ampObj ? fmin(fmax([ampObj doubleValue], 0.40), 1.60) : 1.0;
}

static void DBPrefsChangedCallback(CFNotificationCenterRef center, void *observer, CFStringRef name, const void *object, CFDictionaryRef userInfo) {
    DBLoadPreferences();
}

#pragma mark - Exact Lunora Droplet Spring Math

static inline double DBClamp01(double x) {
    return x < 0.0 ? 0.0 : (x > 1.0 ? 1.0 : x);
}

static inline double DBLerp(double a, double b, double t) {
    return a + (b - a) * t;
}

// Damped spring curve matching Lunora's IDIIslandNotificationAnimator
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

// Find the actual banner card view (never a full-screen wrapper)
static UIView *DBFindCardView(UIView *root, UIWindow *win) {
    if (!root || !win) return root;
    CGSize winSize = win.bounds.size;
    CGRect rootRect = [root convertRect:root.bounds toCoordinateSpace:win.coordinateSpace];
    if (rootRect.size.height < winSize.height * 0.55 && rootRect.size.width >= 120.0 && rootRect.size.height >= 34.0) {
        return root;
    }

    NSMutableArray<UIView *> *queue = [NSMutableArray arrayWithObject:root];
    NSInteger inspected = 0;
    while (queue.count > 0 && inspected < 45) {
        UIView *cur = queue.firstObject;
        [queue removeObjectAtIndex:0];
        inspected++;

        for (UIView *sub in cur.subviews) {
            if (sub.hidden || sub.alpha < 0.05) continue;
            CGRect r = [sub convertRect:sub.bounds toCoordinateSpace:win.coordinateSpace];
            if (r.size.width >= winSize.width * 0.55 &&
                r.size.height >= 42.0 &&
                r.size.height <= 260.0 &&
                r.origin.y < winSize.height * 0.35) {
                return sub;
            }
            [queue addObject:sub];
        }
    }
    return root;
}

// Walk up to the top-most non-fullscreen banner container so hiding opacity hides the entire stock banner + platter
static UIView *DBFindNativeSurface(UIView *cardView, UIWindow *win) {
    if (!cardView || !win) return cardView;
    CGSize winSize = win.bounds.size;
    UIView *surface = cardView;
    UIView *cur = cardView.superview;
    while (cur && cur != win) {
        CGRect r = cur.bounds;
        if (r.size.height > 30.0 && r.size.height < winSize.height * 0.55 && r.size.width >= 120.0) {
            surface = cur;
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

#pragma mark - Droplet Animator (Pure Shape Layers — No Extra Glass)

@interface DBDropletAnimator : NSObject
@property (nonatomic, weak) UIView *contentView;
@property (nonatomic, weak) UIView *nativeSurface;
@property (nonatomic, weak) CALayer *maskedNativeLayer;
@property (nonatomic, weak) UIWindow *sourceWindow;
@property (nonatomic, strong) DBDropletEffectWindow *effectWindow;
@property (nonatomic, strong) UIView *canvasView;
@property (nonatomic, strong) CAShapeLayer *neckLayer;
@property (nonatomic, strong) CAShapeLayer *bodyLayer;
@property (nonatomic, strong) UIImageView *exitSnapshotView;
@property (nonatomic, strong) UIColor *surfaceColor;
@property (nonatomic, strong) CADisplayLink *displayLink;
@property (nonatomic, strong) DBDisplayLinkProxy *proxy;
@property (nonatomic, assign) CFTimeInterval startedAt;
@property (nonatomic, assign) CFTimeInterval duration;
@property (nonatomic, assign) BOOL exiting;
@property (nonatomic, assign) CGRect cutoutRect;
@property (nonatomic, assign) CGRect cardRect;
@property (nonatomic, assign) CGFloat cardCornerRadius;
- (void)startEntryForView:(UIView *)view;
- (void)startExitForView:(UIView *)view;
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

    if (self.maskedNativeLayer) {
        [self.maskedNativeLayer removeAnimationForKey:kOpacityAnimKey];
        self.maskedNativeLayer = nil;
    }

    if (self.exitSnapshotView) {
        [self.exitSnapshotView removeFromSuperview];
        self.exitSnapshotView = nil;
    }
    if (self.bodyLayer) {
        [self.bodyLayer removeFromSuperlayer];
        self.bodyLayer = nil;
    }
    if (self.neckLayer) {
        [self.neckLayer removeFromSuperlayer];
        self.neckLayer = nil;
    }
    if (self.effectWindow) {
        self.effectWindow.hidden = YES;
        self.effectWindow.rootViewController = nil;
        self.effectWindow = nil;
    }
    self.canvasView = nil;
}

- (BOOL)setupOverlayForView:(UIView *)rawView {
    UIWindow *win = rawView.window;
    if (!win) return NO;

    CGSize winSize = win.bounds.size;
    // Portrait only; preserve stock animation in landscape
    if (winSize.width > winSize.height || winSize.width < 250.0) return NO;

    UIView *cardView = DBFindCardView(rawView, win);
    if (!cardView) return NO;

    UIView *surface = DBFindNativeSurface(cardView, win);

    CGRect cutout = DBResolveCutoutRectForWindow(win);
    CGRect frameInWin = [cardView convertRect:cardView.bounds toCoordinateSpace:win.coordinateSpace];
    if (CGRectIsEmpty(frameInWin) || frameInWin.size.width < 120.0 || frameInWin.size.height < 34.0) {
        return NO;
    }

    // If BannerKit hasn't placed the model frame below the Island yet, target the standard resting Y
    CGFloat minRestingY = CGRectGetMaxY(cutout) + 10.0;
    if (frameInWin.origin.y < minRestingY - 4.0) {
        frameInWin.origin.y = minRestingY;
    }

    self.contentView = cardView;
    self.nativeSurface = surface ?: cardView;
    self.sourceWindow = win;
    self.cutoutRect = cutout;
    self.cardRect = frameInWin;
    self.cardCornerRadius = DBResolveCornerRadius(cardView);
    self.surfaceColor = [[UIColor secondarySystemBackgroundColor] resolvedColorWithTraitCollection:cardView.traitCollection];

    // Overlay window sitting directly ABOVE the banner window (never blocked by BannerKit)
    DBDropletEffectWindow *overlay = nil;
    if (win.windowScene) {
        overlay = [[DBDropletEffectWindow alloc] initWithWindowScene:win.windowScene];
    } else {
        overlay = [[DBDropletEffectWindow alloc] initWithFrame:win.bounds];
    }
    overlay.frame = win.coordinateSpace.bounds;
    overlay.windowLevel = win.windowLevel + 1.0;
    overlay.backgroundColor = [UIColor clearColor];
    overlay.userInteractionEnabled = NO;
    overlay.accessibilityElementsHidden = YES;

    UIViewController *rootVC = [[UIViewController alloc] init];
    rootVC.view.backgroundColor = [UIColor clearColor];
    rootVC.view.userInteractionEnabled = NO;
    rootVC.view.frame = overlay.bounds;
    overlay.rootViewController = rootVC;
    [overlay layoutIfNeeded];

    UIView *canvas = [[UIView alloc] initWithFrame:rootVC.view.bounds];
    canvas.backgroundColor = [UIColor clearColor];
    canvas.userInteractionEnabled = NO;
    canvas.accessibilityElementsHidden = YES;
    [rootVC.view addSubview:canvas];

    CAShapeLayer *neck = [CAShapeLayer layer];
    neck.fillColor = [UIColor blackColor].CGColor;
    [canvas.layer addSublayer:neck];

    CAShapeLayer *body = [CAShapeLayer layer];
    body.fillColor = [UIColor blackColor].CGColor;
    [canvas.layer addSublayer:body];

    self.effectWindow = overlay;
    self.canvasView = canvas;
    self.neckLayer = neck;
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

- (void)startEntryForView:(UIView *)view {
    [self stop];
    self.exiting = NO;
    if (![self setupOverlayForView:view]) return;

    // Default slider (0.48) => snappy 0.92s full spring (drop 0-0.26s, bloom 0.26-0.62s, reveal 0.43-0.70s)
    double speedScale = gEntryDuration / 0.48;
    self.duration = fmin(fmax(0.92 * speedScale, 0.55), 1.55);

    // Hide the native banner completely during the droplet drop, then crossfade it in cleanly at resting position
    CALayer *nativeLayer = self.nativeSurface.layer;
    self.maskedNativeLayer = nativeLayer;
    CAKeyframeAnimation *opacityAnim = [CAKeyframeAnimation animationWithKeyPath:@"opacity"];
    opacityAnim.values = @[ @(0.0), @(0.0), @(1.0), @(1.0) ];
    opacityAnim.keyTimes = @[ @(0.0), @(0.467), @(0.758), @(1.0) ];
    opacityAnim.duration = self.duration;
    opacityAnim.removedOnCompletion = YES;
    [nativeLayer addAnimation:opacityAnim forKey:kOpacityAnimKey];

    self.startedAt = CACurrentMediaTime();
    [self renderNormalizedTime:0.0];
    self.effectWindow.hidden = NO;
    [self startDisplayLink];
}

- (void)startExitForView:(UIView *)view {
    [self stop];
    self.exiting = YES;
    if (![self setupOverlayForView:view]) return;

    UIImage *snap = DBSnapshotView(self.contentView);
    if (!snap) {
        [self stop];
        return;
    }

    UIImageView *snapView = [[UIImageView alloc] initWithImage:snap];
    snapView.frame = self.cardRect;
    snapView.contentMode = UIViewContentModeScaleToFill;
    snapView.layer.cornerRadius = self.cardCornerRadius;
    snapView.layer.cornerCurve = kCACornerCurveContinuous;
    snapView.clipsToBounds = YES;
    snapView.userInteractionEnabled = NO;
    [self.canvasView addSubview:snapView];
    self.exitSnapshotView = snapView;

    double speedScale = gEntryDuration / 0.48;
    self.duration = fmin(fmax(0.68 * speedScale, 0.40), 1.15);

    CALayer *nativeLayer = self.nativeSurface.layer;
    self.maskedNativeLayer = nativeLayer;
    CAKeyframeAnimation *hideAnim = [CAKeyframeAnimation animationWithKeyPath:@"opacity"];
    hideAnim.values = @[ @(0.0), @(0.0) ];
    hideAnim.keyTimes = @[ @(0.0), @(1.0) ];
    hideAnim.duration = self.duration + 0.12;
    hideAnim.removedOnCompletion = YES;
    [nativeLayer addAnimation:hideAnim forKey:kOpacityAnimKey];

    self.startedAt = CACurrentMediaTime();
    [self renderNormalizedTime:0.0];
    self.effectWindow.hidden = NO;
    [self startDisplayLink];
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

// normT is 0.0 -> 1.0; mapped onto Lunora's canonical 0.0 -> 1.2s curve space
- (void)renderNormalizedTime:(double)normT {
    double t = DBClamp01(normT) * 1.2;
    double amp = gAmplitude;

    double yProg = 0.0;
    double wProg = 0.0;
    double revealProg = 0.0;
    double neckProg = 0.0;

    if (!self.exiting) {
        // ENTRY: drop down first (0.0 -> 1.15), then bloom width (0.34 -> 1.20), then crossfade (0.56 -> 0.91)
        yProg = DBSpringCurve(t / 1.15, 7.38, 5.15127, 1.43266);
        wProg = DBSpringCurve((t - 0.34) / 0.86, 7.20, 5.40, 1.33333);
        revealProg = DBClamp01((t - 0.56) / 0.35);
        neckProg = DBSpringCurve((t - 0.11) / 0.70, 8.91, 1.26961, 7.01792);
    } else {
        // EXIT: fade snapshot (0.0 -> 0.24), squeeze width first (0.10 -> 0.76), then suck up into Island (0.28 -> 1.20)
        yProg = 1.0 - DBSpringCurve((t - 0.28) / 0.92, 8.10, 3.92301, 2.06474);
        wProg = 1.0 - DBSpringCurve((t - 0.10) / 0.66, 8.28, 3.52727, 2.34743);
        revealProg = 1.0 - DBClamp01(t / 0.24);
        neckProg = 1.0 - DBSpringCurve((t - 0.28) / 0.92, 8.10, 3.92301, 2.06474);
    }

    // Vertical liquid teardrop stretch bulge while dropping out of the Dynamic Island
    double u = DBClamp01(yProg / 0.82);
    double bulge = (pow(u, 1.6) * pow(1.0 - u, 1.4)) / 0.12583674;
    double stretch = 1.0 + (0.38 * amp) * bulge;

    // Compact teardrop base size before horizontal bloom
    double baseDropDiameter = fmin(CGRectGetHeight(self.cutoutRect) * 0.96, CGRectGetHeight(self.cardRect) * 0.72);
    double dropGrow = 1.0 - pow(1.0 - DBClamp01(yProg / 0.70), 2.0);
    double dropSize = baseDropDiameter * (0.62 + 0.38 * dropGrow);

    double dropW = dropSize / stretch;
    double dropH = dropSize * stretch;

    double curW = DBLerp(dropW, CGRectGetWidth(self.cardRect), wProg);
    double curH = DBLerp(dropH, CGRectGetHeight(self.cardRect), wProg);

    // Droplet center Y starts tucked inside the bottom edge of the Dynamic Island and drops to card.midY
    double startMidY = CGRectGetMaxY(self.cutoutRect) - 0.34 * dropH;
    double curMidY = DBLerp(startMidY, CGRectGetMidY(self.cardRect), yProg);
    double curMidX = DBLerp(CGRectGetMidX(self.cutoutRect), CGRectGetMidX(self.cardRect), wProg);

    CGRect curRect = CGRectMake(curMidX - curW * 0.5, curMidY - curH * 0.5, curW, curH);
    CGFloat maxR = (CGFloat)(fmin(curW, curH) * 0.5);
    CGFloat curRadius = (CGFloat)fmin(maxR, DBLerp(maxR, self.cardCornerRadius, DBClamp01(wProg)));

    UIBezierPath *bodyPath = [UIBezierPath bezierPathWithRoundedRect:curRect cornerRadius:curRadius];

    // Curved black liquid neck bridging Dynamic Island bottom to the dropping teardrop
    double neckVisibility = 0.0;
    if (yProg > 0.02 && neckProg < 0.94) {
        double rise = DBClamp01(yProg / 0.18);
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

    // Smoothly transition droplet color from pitch black (Dynamic Island) toward the banner's own dark/light surface tone
    CGFloat sr = 0.12, sg = 0.12, sb = 0.14, sa = 1.0;
    if (self.surfaceColor) {
        [self.surfaceColor getRed:&sr green:&sg blue:&sb alpha:&sa];
    }
    double colorBlend = DBClamp01(wProg * 0.85);
    UIColor *bodyColor = [UIColor colorWithRed:sr * colorBlend green:sg * colorBlend blue:sb * colorBlend alpha:1.0];

    [CATransaction begin];
    [CATransaction setDisableActions:YES];

    self.bodyLayer.path = bodyPath.CGPath;
    self.bodyLayer.fillColor = bodyColor.CGColor;

    if (neckPath) {
        self.neckLayer.path = neckPath.CGPath;
        self.neckLayer.fillColor = [UIColor blackColor].CGColor;
        self.neckLayer.opacity = (float)DBClamp01(neckVisibility * 1.15);
    } else {
        self.neckLayer.path = NULL;
        self.neckLayer.opacity = 0.0f;
    }

    if (!self.exiting) {
        // Stay solid during drop + bloom, then cleanly dissolve away as native Liquid Glass banner reveals underneath
        self.bodyLayer.opacity = (float)DBClamp01(1.0 - revealProg);
    } else {
        // Hide droplet at the very end once it completely re-enters the Dynamic Island
        double endFade = 1.0 - DBClamp01((normT - 0.86) / 0.14);
        self.bodyLayer.opacity = (float)endFade;
        if (self.exitSnapshotView) {
            self.exitSnapshotView.layer.bounds = CGRectMake(0, 0, curW, curH);
            self.exitSnapshotView.layer.position = CGPointMake(curMidX, curMidY);
            self.exitSnapshotView.layer.cornerRadius = curRadius;
            self.exitSnapshotView.layer.opacity = (float)DBClamp01(revealProg);
        }
    }

    [CATransaction commit];
}

@end

#pragma mark - Banner View Extraction & Deduplication

static DBDropletAnimator *gActiveAnimator = nil;
static CFTimeInterval gLastTriggerTime = 0.0;

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

static void DBTriggerEntryIfReady(UIView *view) {
    CFTimeInterval now = CACurrentMediaTime();
    if (now - gLastTriggerTime < 0.25) return;
    gLastTriggerTime = now;

    if (!gActiveAnimator) {
        gActiveAnimator = [[DBDropletAnimator alloc] init];
    }
    [gActiveAnimator startEntryForView:view];
}

static void DBScheduleEntryForPresentable(id<BNPresentable> presentable, NSInteger attempt) {
    UIView *bannerView = DBExtractBannerViewFromPresentable(presentable);
    if (bannerView && bannerView.window && !CGRectIsEmpty(bannerView.bounds)) {
        DBTriggerEntryIfReady(bannerView);
        return;
    }
    if (attempt < 10) {
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.016 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            DBScheduleEntryForPresentable(presentable, attempt + 1);
        });
    }
}

static void DBScheduleEntryForViewController(UIViewController *vc, NSInteger attempt) {
    UIView *v = vc.viewIfLoaded;
    if (v && v.window && !CGRectIsEmpty(v.bounds)) {
        if (DBIsBannerViewController(vc)) {
            DBTriggerEntryIfReady(v);
        }
        return;
    }
    if (attempt < 10) {
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.016 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            DBScheduleEntryForViewController(vc, attempt + 1);
        });
    }
}

#pragma mark - SpringBoard Hooks

%hook SBNotificationBannerDestination

- (void)presentableWillAppearAsBanner:(id<BNPresentable>)presentable {
    %orig;
    if (!gEnabled || UIAccessibilityIsReduceMotionEnabled()) return;

    dispatch_async(dispatch_get_main_queue(), ^{
        DBScheduleEntryForPresentable(presentable, 0);
    });
}

- (void)presentableWillDisappearAsBanner:(id<BNPresentable>)presentable withReason:(NSString *)reason {
    if (gEnabled && gAnimateDismiss && !UIAccessibilityIsReduceMotionEnabled()) {
        BOOL isInteractive = (reason && ([reason.lowercaseString containsString:@"gesture"] ||
                                         [reason.lowercaseString containsString:@"drag"] ||
                                         [reason.lowercaseString containsString:@"tap"] ||
                                         [reason.lowercaseString containsString:@"action"]));
        if (!isInteractive) {
            UIView *bannerView = DBExtractBannerViewFromPresentable(presentable);
            if (bannerView && bannerView.window) {
                if (!gActiveAnimator) {
                    gActiveAnimator = [[DBDropletAnimator alloc] init];
                }
                [gActiveAnimator startExitForView:bannerView];
            }
        } else if (gActiveAnimator) {
            [gActiveAnimator stop];
        }
    }
    %orig;
}

%end

%hook NCNotificationShortLookViewController

- (void)viewWillAppear:(BOOL)animated {
    %orig;
    if (!gEnabled || UIAccessibilityIsReduceMotionEnabled()) return;

    dispatch_async(dispatch_get_main_queue(), ^{
        DBScheduleEntryForViewController(self, 0);
    });
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
