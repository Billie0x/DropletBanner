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

static BOOL gEnabled = YES;
static BOOL gAnimateDismiss = YES;
static double gEntryDuration = 0.54;
static double gAmplitude = 1.0;

static void DBLoadPreferences(void) {
    CFPreferencesAppSynchronize((__bridge CFStringRef)kPrefsDomain);

    id enabledObj = CFBridgingRelease(CFPreferencesCopyAppValue(CFSTR("Enabled"), (__bridge CFStringRef)kPrefsDomain));
    gEnabled = enabledObj ? [enabledObj boolValue] : YES;

    id dismissObj = CFBridgingRelease(CFPreferencesCopyAppValue(CFSTR("AnimateDismiss"), (__bridge CFStringRef)kPrefsDomain));
    gAnimateDismiss = dismissObj ? [dismissObj boolValue] : YES;

    id durObj = CFBridgingRelease(CFPreferencesCopyAppValue(CFSTR("EntryDuration"), (__bridge CFStringRef)kPrefsDomain));
    gEntryDuration = durObj ? fmin(fmax([durObj doubleValue], 0.25), 0.90) : 0.54;

    id ampObj = CFBridgingRelease(CFPreferencesCopyAppValue(CFSTR("DropletAmplitude"), (__bridge CFStringRef)kPrefsDomain));
    gAmplitude = ampObj ? fmin(fmax([ampObj doubleValue], 0.40), 1.60) : 1.0;
}

static void DBPrefsChangedCallback(CFNotificationCenterRef center, void *observer, CFStringRef name, const void *object, CFDictionaryRef userInfo) {
    DBLoadPreferences();
}

#pragma mark - Math & Geometry Helpers

static inline CGFloat DBClamp01(CGFloat x) {
    return x < 0.0 ? 0.0 : (x > 1.0 ? 1.0 : x);
}

static inline CGFloat DBLerp(CGFloat a, CGFloat b, CGFloat t) {
    return a + (b - a) * t;
}

static inline CGFloat DBSpring(CGFloat t, CGFloat zeta, CGFloat omega) {
    t = DBClamp01(t);
    if (t >= 1.0) return 1.0;
    CGFloat decay = exp(-zeta * omega * t);
    CGFloat osc = cos(omega * sqrt(fmax(0.01, 1.0 - zeta * zeta)) * t);
    return 1.0 - decay * osc;
}

static inline CGFloat DBEaseInOutCubic(CGFloat t) {
    t = DBClamp01(t);
    return t < 0.5 ? (4.0 * t * t * t) : (1.0 - pow(-2.0 * t + 2.0, 3.0) / 2.0);
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

    // Notched Face ID devices
    if (topInset >= 40.0) {
        CGFloat notchW = 112.0;
        CGFloat notchH = 30.0;
        return CGRectMake(midX - notchW * 0.5, 0.0, notchW, notchH);
    }

    CGFloat fallbackW = 104.0;
    CGFloat fallbackH = 24.0;
    return CGRectMake(midX - fallbackW * 0.5, 4.0, fallbackW, fallbackH);
}

// Walk down if the VC's root view is a full-screen wrapper so we animate the actual banner card
static UIView *DBFindCardView(UIView *root, UIWindow *win) {
    if (!root || !win) return root;
    CGSize winSize = win.bounds.size;
    CGRect rootRect = [root convertRect:root.bounds toView:win];
    if (rootRect.size.height < winSize.height * 0.55 && rootRect.size.width >= 120.0 && rootRect.size.height >= 34.0) {
        return root;
    }

    NSMutableArray<UIView *> *queue = [NSMutableArray arrayWithObject:root];
    NSInteger inspected = 0;
    while (queue.count > 0 && inspected < 40) {
        UIView *cur = queue.firstObject;
        [queue removeObjectAtIndex:0];
        inspected++;

        for (UIView *sub in cur.subviews) {
            if (sub.hidden || sub.alpha < 0.05) continue;
            CGRect r = [sub convertRect:sub.bounds toView:win];
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

static CGFloat DBResolveCornerRadius(UIView *view) {
    CGFloat r = view.layer.cornerRadius;
    if (r >= 14.0) return r;
    for (UIView *sub in view.subviews) {
        if (sub.layer.cornerRadius >= 14.0 && CGRectGetWidth(sub.bounds) > CGRectGetWidth(view.bounds) * 0.75) {
            return sub.layer.cornerRadius;
        }
    }
    return 28.0;
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

#pragma mark - CADisplayLink Weak Proxy

@class DBDropletAnimator;

@interface DBDisplayLinkProxy : NSObject
@property (nonatomic, weak) DBDropletAnimator *owner;
- (void)tick:(CADisplayLink *)link;
@end

#pragma mark - Liquid Glass Droplet Animator

@interface DBDropletAnimator : NSObject
@property (nonatomic, weak) UIView *targetView;
@property (nonatomic, weak) UIWindow *hostWindow;
@property (nonatomic, strong) UIView *canvasView;
@property (nonatomic, strong) UIVisualEffectView *glassView;
@property (nonatomic, strong) UIView *glassTintView;
@property (nonatomic, strong) CAShapeLayer *glassMaskLayer;
@property (nonatomic, strong) CAShapeLayer *specularRimLayer;
@property (nonatomic, strong) CAShapeLayer *islandBridgeLayer;
@property (nonatomic, strong) UIImageView *exitSnapshotView;
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

    if (self.targetView && !self.exiting) {
        self.targetView.transform = CGAffineTransformIdentity;
        self.targetView.alpha = 1.0;
    }

    if (self.canvasView) {
        [self.canvasView removeFromSuperview];
        self.canvasView = nil;
    }
    self.glassView = nil;
    self.glassTintView = nil;
    self.glassMaskLayer = nil;
    self.specularRimLayer = nil;
    self.islandBridgeLayer = nil;
    self.exitSnapshotView = nil;
}

- (BOOL)setupCanvasForView:(UIView *)rawView onTop:(BOOL)onTop {
    UIWindow *win = rawView.window;
    if (!win) return NO;

    CGSize winSize = win.bounds.size;
    // Portrait only; fall back to stock animation in landscape
    if (winSize.width > winSize.height || winSize.width < 250.0) return NO;

    UIView *cardView = DBFindCardView(rawView, win);
    if (!cardView) return NO;

    // Reset any prior transform so we measure the true resting banner rect
    CGAffineTransform savedTransform = cardView.transform;
    cardView.transform = CGAffineTransformIdentity;
    CGRect frameInWin = [cardView convertRect:cardView.bounds toView:win];
    cardView.transform = savedTransform;

    if (CGRectIsEmpty(frameInWin) || frameInWin.size.width < 120.0 || frameInWin.size.height < 34.0) {
        return NO;
    }

    CGRect cutout = DBResolveCutoutRectForWindow(win);
    CGFloat minRestingY = CGRectGetMaxY(cutout) + 8.0;
    if (frameInWin.origin.y < minRestingY - 4.0) {
        frameInWin.origin.y = minRestingY;
    }

    self.targetView = cardView;
    self.hostWindow = win;
    self.cutoutRect = cutout;
    self.cardRect = frameInWin;
    self.cardCornerRadius = DBResolveCornerRadius(cardView);

    // Mount directly inside the active banner window so iOS 26 never hides it
    UIView *canvas = [[UIView alloc] initWithFrame:win.bounds];
    canvas.backgroundColor = [UIColor clearColor];
    canvas.userInteractionEnabled = NO;
    canvas.accessibilityElementsHidden = YES;
    canvas.layer.zPosition = onTop ? 999.0 : 0.0;

    // Subtle dark neck root emerging from the black Dynamic Island hardware
    CAShapeLayer *islandBridge = [CAShapeLayer layer];
    islandBridge.fillColor = [UIColor blackColor].CGColor;
    [canvas.layer addSublayer:islandBridge];

    // Liquid Glass frosted material masked to the unified droplet + metaball neck path
    UIBlurEffect *blur = [UIBlurEffect effectWithStyle:UIBlurEffectStyleSystemUltraThinMaterial];
    UIVisualEffectView *glass = [[UIVisualEffectView alloc] initWithEffect:blur];
    glass.frame = canvas.bounds;
    glass.userInteractionEnabled = NO;

    UIView *tint = [[UIView alloc] initWithFrame:glass.bounds];
    BOOL isDark = (win.traitCollection.userInterfaceStyle == UIUserInterfaceStyleDark);
    tint.backgroundColor = isDark
        ? [UIColor colorWithWhite:1.0 alpha:0.08]
        : [UIColor colorWithWhite:1.0 alpha:0.22];
    tint.userInteractionEnabled = NO;
    [glass.contentView addSubview:tint];

    CAShapeLayer *maskLayer = [CAShapeLayer layer];
    maskLayer.fillColor = [UIColor whiteColor].CGColor;
    glass.layer.mask = maskLayer;
    [canvas addSubview:glass];

    // Liquid Glass specular rim stroke tracing the droplet & liquid bridge
    CAShapeLayer *rimLayer = [CAShapeLayer layer];
    rimLayer.fillColor = [UIColor clearColor].CGColor;
    rimLayer.strokeColor = [UIColor colorWithWhite:1.0 alpha:(isDark ? 0.34 : 0.65)].CGColor;
    rimLayer.lineWidth = 1.15;
    rimLayer.shadowColor = [UIColor blackColor].CGColor;
    rimLayer.shadowOpacity = 0.25;
    rimLayer.shadowRadius = 10.0;
    rimLayer.shadowOffset = CGSizeMake(0.0, 4.0);
    [canvas.layer addSublayer:rimLayer];

    if (onTop) {
        [win addSubview:canvas];
    } else {
        UIView *topBranch = cardView;
        while (topBranch.superview && topBranch.superview != win) {
            topBranch = topBranch.superview;
        }
        if (topBranch.superview == win) {
            [win insertSubview:canvas belowSubview:topBranch];
        } else {
            [win addSubview:canvas];
        }
    }

    self.canvasView = canvas;
    self.islandBridgeLayer = islandBridge;
    self.glassView = glass;
    self.glassTintView = tint;
    self.glassMaskLayer = maskLayer;
    self.specularRimLayer = rimLayer;
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
    if (![self setupCanvasForView:view onTop:NO]) return;

    self.duration = gEntryDuration;
    self.startedAt = CACurrentMediaTime();
    [self renderProgress:0.0];
    [self startDisplayLink];
}

- (void)startExitForView:(UIView *)view {
    [self stop];
    self.exiting = YES;
    if (![self setupCanvasForView:view onTop:YES]) return;

    UIImage *snap = DBSnapshotView(self.targetView);
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

    self.targetView.alpha = 0.0;

    self.duration = fmax(0.28, gEntryDuration * 0.62);
    self.startedAt = CACurrentMediaTime();
    [self renderProgress:0.0];
    [self startDisplayLink];
}

- (void)tick:(CADisplayLink *)link {
    CFTimeInterval elapsed = CACurrentMediaTime() - self.startedAt;
    CGFloat rawT = (self.duration > 0.0) ? (CGFloat)(elapsed / self.duration) : 1.0;

    if (rawT >= 1.0) {
        [self renderProgress:1.0];
        [self stop];
        return;
    }
    [self renderProgress:rawT];
}

- (void)renderProgress:(CGFloat)rawT {
    CGFloat amp = (CGFloat)gAmplitude;
    CGFloat yP, wP;

    if (!self.exiting) {
        // Drop downward first, then bloom outward horizontally like a liquid droplet
        CGFloat freq = 8.8 + (amp - 1.0) * 1.6;
        yP = DBSpring(rawT, 0.72, freq);
        wP = DBSpring(DBClamp01((rawT - 0.06) / 0.94), 0.76, freq * 0.94);
    } else {
        // Squeeze horizontally first, then suck upward into the Dynamic Island
        CGFloat e = DBEaseInOutCubic(rawT);
        yP = 1.0 - e;
        wP = 1.0 - DBEaseInOutCubic(DBClamp01(rawT * 1.18));
    }

    CGFloat cYP = DBClamp01(yP);
    CGFloat cWP = DBClamp01(wP);

    CGFloat startW = CGRectGetWidth(self.cutoutRect) * 0.76;
    CGFloat startH = CGRectGetHeight(self.cutoutRect) * 0.88;
    CGFloat curW = DBLerp(startW, CGRectGetWidth(self.cardRect), cWP);
    CGFloat curH = DBLerp(startH, CGRectGetHeight(self.cardRect), cYP);
    CGFloat curMidX = DBLerp(CGRectGetMidX(self.cutoutRect), CGRectGetMidX(self.cardRect), cWP);
    CGFloat curMinY = DBLerp(CGRectGetMinY(self.cutoutRect) + 2.0, CGRectGetMinY(self.cardRect), yP);
    CGRect curRect = CGRectMake(curMidX - curW * 0.5, curMinY, curW, curH);

    CGFloat startRadius = startH * 0.5;
    CGFloat curRadius = fmin(curH * 0.5, DBLerp(startRadius, self.cardCornerRadius, cWP));

    // Unified Liquid Glass silhouette: expanding droplet capsule + curved metaball neck
    UIBezierPath *combinedPath = [UIBezierPath bezierPathWithRoundedRect:curRect cornerRadius:curRadius];

    CGFloat neckPhase = 0.0;
    if (!self.exiting) {
        if (rawT > 0.01 && rawT < 0.58) {
            neckPhase = sin(((rawT - 0.01) / 0.57) * M_PI);
        }
    } else {
        if (rawT > 0.14 && rawT < 0.92) {
            neckPhase = sin(((rawT - 0.14) / 0.78) * M_PI);
        }
    }

    UIBezierPath *neckPath = nil;
    if (neckPhase > 0.01 && CGRectGetMinY(curRect) > CGRectGetMinY(self.cutoutRect) + 1.0) {
        CGFloat topY = CGRectGetMidY(self.cutoutRect);
        CGFloat botY = CGRectGetMinY(curRect) + fmin(curRadius * 0.65, 20.0);
        CGFloat topHalfW = CGRectGetWidth(self.cutoutRect) * 0.36 * (0.45 + 0.55 * neckPhase);
        CGFloat botHalfW = fmin(curW * 0.32, CGRectGetWidth(self.cutoutRect) * 0.54) * (0.45 + 0.55 * neckPhase);
        CGFloat pinchHalfW = fmax(4.0, fmin(topHalfW, botHalfW) * (0.24 + 0.34 * neckPhase) * amp);
        CGFloat midY = (topY + botY) * 0.50;

        neckPath = [UIBezierPath bezierPath];
        [neckPath moveToPoint:CGPointMake(curMidX - topHalfW, topY)];
        [neckPath addLineToPoint:CGPointMake(curMidX + topHalfW, topY)];
        [neckPath addCurveToPoint:CGPointMake(curMidX + botHalfW, botY)
                    controlPoint1:CGPointMake(curMidX + pinchHalfW, midY)
                    controlPoint2:CGPointMake(curMidX + pinchHalfW, midY)];
        [neckPath addLineToPoint:CGPointMake(curMidX - botHalfW, botY)];
        [neckPath addCurveToPoint:CGPointMake(curMidX - topHalfW, topY)
                    controlPoint1:CGPointMake(curMidX - pinchHalfW, midY)
                    controlPoint2:CGPointMake(curMidX - pinchHalfW, midY)];
        [neckPath closePath];

        [combinedPath appendPath:neckPath];
    }

    // Transform the live banner (entry) or snapshot (exit) so the card physically emerges from the Island
    CGFloat scaleX = fmax(0.18, curW / fmax(1.0, CGRectGetWidth(self.cardRect)));
    CGFloat scaleY = fmax(0.18, curH / fmax(1.0, CGRectGetHeight(self.cardRect)));
    CGFloat dx = CGRectGetMidX(curRect) - CGRectGetMidX(self.cardRect);
    CGFloat dy = CGRectGetMidY(curRect) - CGRectGetMidY(self.cardRect);

    CGAffineTransform transform = CGAffineTransformConcat(
        CGAffineTransformMakeScale(scaleX, scaleY),
        CGAffineTransformMakeTranslation(dx, dy)
    );

    [CATransaction begin];
    [CATransaction setDisableActions:YES];

    self.glassMaskLayer.path = combinedPath.CGPath;
    self.specularRimLayer.path = combinedPath.CGPath;

    if (neckPath) {
        self.islandBridgeLayer.path = neckPath.CGPath;
        self.islandBridgeLayer.opacity = (float)(neckPhase * 0.55);
    } else {
        self.islandBridgeLayer.path = NULL;
        self.islandBridgeLayer.opacity = 0.0f;
    }

    if (!self.exiting) {
        // Liquid Glass shell stays bright through the stretch, then dissolves into the native iOS 26 glass banner
        CGFloat glassFade = 1.0 - DBClamp01((rawT - 0.56) / 0.40);
        self.glassView.alpha = glassFade;
        self.specularRimLayer.opacity = (float)glassFade;

        self.targetView.transform = transform;
        self.targetView.alpha = DBClamp01((rawT - 0.08) / 0.36);
    } else {
        CGFloat glassAlpha = DBClamp01(1.0 - pow(rawT, 2.2));
        self.glassView.alpha = glassAlpha;
        self.specularRimLayer.opacity = (float)glassAlpha;

        if (self.exitSnapshotView) {
            self.exitSnapshotView.transform = transform;
            self.exitSnapshotView.alpha = DBClamp01(1.0 - rawT * 1.35);
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
    if (now - gLastTriggerTime < 0.22) return;
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
    if (attempt < 12) {
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
    if (attempt < 12) {
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

// Fallback hook for iOS 15-26 banner presentations (strictly filtered to banner windows only)
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
