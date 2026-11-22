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
- (NSString *)requesterIdentifier;
- (NSString *)requestIdentifier;
@end

@interface SBNotificationBannerDestination : NSObject
- (void)presentableWillAppearAsBanner:(id<BNPresentable>)presentable;
- (void)presentableWillDisappearAsBanner:(id<BNPresentable>)presentable withReason:(NSString *)reason;
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
    gAmplitude = ampObj ? fmin(fmax([ampObj doubleValue], 0.35), 1.60) : 1.0;
}

static void DBPrefsChangedCallback(CFNotificationCenterRef center, void *observer, CFStringRef name, const void *object, CFDictionaryRef userInfo) {
    DBLoadPreferences();
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

#pragma mark - Droplet Animator

@interface DBDropletAnimator : NSObject
@property (nonatomic, weak) UIView *contentView;
@property (nonatomic, weak) CALayer *maskedNativeLayer;
@property (nonatomic, weak) UIWindow *sourceWindow;
@property (nonatomic, strong) DBDropletEffectWindow *effectWindow;
@property (nonatomic, strong) UIView *canvasView;
@property (nonatomic, strong) CAShapeLayer *bodyLayer;
@property (nonatomic, strong) CAShapeLayer *neckLayer;
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

static inline CGFloat DBClamp01(CGFloat x) {
    return x < 0.0 ? 0.0 : (x > 1.0 ? 1.0 : x);
}

static inline CGFloat DBLerp(CGFloat a, CGFloat b, CGFloat t) {
    return a + (b - a) * t;
}

static inline CGFloat DBDropletEase(CGFloat t, CGFloat amp) {
    t = DBClamp01(t);
    if (t >= 1.0) return 1.0;
    CGFloat zeta = 0.74;
    CGFloat omega = 9.8 + (amp - 1.0) * 1.8;
    CGFloat decay = exp(-zeta * omega * t);
    CGFloat osc = cos(omega * sqrt(1.0 - zeta * zeta) * t);
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
    if (topInset >= 54.0) {
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

    // Non-notched fallback
    CGFloat fallbackW = 104.0;
    CGFloat fallbackH = 24.0;
    return CGRectMake(midX - fallbackW * 0.5, 4.0, fallbackW, fallbackH);
}

static CGFloat DBResolveCornerRadius(UIView *view) {
    CGFloat r = view.layer.cornerRadius;
    if (r >= 12.0) return r;
    for (UIView *sub in view.subviews) {
        if (sub.layer.cornerRadius >= 12.0 && CGRectGetWidth(sub.bounds) > CGRectGetWidth(view.bounds) * 0.75) {
            return sub.layer.cornerRadius;
        }
    }
    return 24.0;
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

- (BOOL)setupOverlayForView:(UIView *)view {
    UIWindow *win = view.window;
    if (!win) return NO;

    CGSize winSize = win.bounds.size;
    if (winSize.width > winSize.height || winSize.width < 250.0) return NO;

    CGRect cutout = DBResolveCutoutRectForWindow(win);
    CGRect frameInWin = [view convertRect:view.bounds toCoordinateSpace:win.coordinateSpace];
    if (CGRectIsEmpty(frameInWin) || frameInWin.size.width < 120.0 || frameInWin.size.height < 30.0) {
        return NO;
    }

    // If BannerKit is still starting its slide-in above the top edge, aim for the true resting banner Y
    CGFloat restingMinY = CGRectGetMaxY(cutout) + 8.0;
    if (frameInWin.origin.y < restingMinY - 4.0) {
        frameInWin.origin.y = restingMinY;
    }

    self.contentView = view;
    self.sourceWindow = win;
    self.cutoutRect = cutout;
    self.cardRect = frameInWin;
    self.cardCornerRadius = DBResolveCornerRadius(view);
    self.surfaceColor = [[UIColor secondarySystemBackgroundColor] resolvedColorWithTraitCollection:view.traitCollection];

    DBDropletEffectWindow *overlay = nil;
    if (win.windowScene) {
        overlay = [[DBDropletEffectWindow alloc] initWithWindowScene:win.windowScene];
    } else {
        overlay = [[DBDropletEffectWindow alloc] initWithFrame:win.bounds];
    }
    overlay.frame = win.bounds;
    overlay.backgroundColor = [UIColor clearColor];
    overlay.windowLevel = win.windowLevel + 1.0;
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

    self.duration = gEntryDuration;

    // Mask the native banner while the liquid droplet emerges from the island, then fade it in cleanly
    self.maskedNativeLayer = view.layer;
    CAKeyframeAnimation *opacityAnim = [CAKeyframeAnimation animationWithKeyPath:@"opacity"];
    opacityAnim.values = @[ @(0.0), @(0.0), @(1.0) ];
    opacityAnim.keyTimes = @[ @(0.0), @(0.42), @(0.88) ];
    opacityAnim.duration = self.duration;
    opacityAnim.removedOnCompletion = YES;
    [view.layer addAnimation:opacityAnim forKey:kOpacityAnimKey];

    self.startedAt = CACurrentMediaTime();
    [self renderProgress:0.0];
    self.effectWindow.hidden = NO;
    [self startDisplayLink];
}

- (void)startExitForView:(UIView *)view {
    [self stop];
    self.exiting = YES;
    if (![self setupOverlayForView:view]) return;

    UIImage *snap = DBSnapshotView(view);
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

    self.duration = fmax(0.24, gEntryDuration * 0.62);

    self.maskedNativeLayer = view.layer;
    CAKeyframeAnimation *hideAnim = [CAKeyframeAnimation animationWithKeyPath:@"opacity"];
    hideAnim.values = @[ @(0.0), @(0.0) ];
    hideAnim.keyTimes = @[ @(0.0), @(1.0) ];
    hideAnim.duration = self.duration + 0.08;
    hideAnim.removedOnCompletion = YES;
    [view.layer addAnimation:hideAnim forKey:kOpacityAnimKey];

    self.startedAt = CACurrentMediaTime();
    [self renderProgress:0.0];
    self.effectWindow.hidden = NO;
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
    CGFloat p = self.exiting ? (1.0 - DBEaseInOutCubic(rawT)) : DBDropletEase(rawT, amp);
    CGFloat clampedP = DBClamp01(p);

    CGFloat curW = DBLerp(CGRectGetWidth(self.cutoutRect), CGRectGetWidth(self.cardRect), clampedP);
    CGFloat curH = DBLerp(CGRectGetHeight(self.cutoutRect), CGRectGetHeight(self.cardRect), clampedP);
    CGFloat curMidX = DBLerp(CGRectGetMidX(self.cutoutRect), CGRectGetMidX(self.cardRect), clampedP);
    CGFloat curMinY = DBLerp(CGRectGetMinY(self.cutoutRect), CGRectGetMinY(self.cardRect), p);
    CGRect curRect = CGRectMake(curMidX - curW * 0.5, curMinY, curW, curH);

    CGFloat cutoutRadius = CGRectGetHeight(self.cutoutRect) * 0.5;
    CGFloat curRadius = DBLerp(cutoutRadius, self.cardCornerRadius, clampedP);

    UIBezierPath *bodyPath = [UIBezierPath bezierPathWithRoundedRect:curRect cornerRadius:curRadius];

    // Liquid neck connecting Dynamic Island cutout to the dropping banner body
    CGFloat neckPhase = 0.0;
    if (clampedP > 0.02 && clampedP < 0.70) {
        CGFloat n = (clampedP - 0.02) / 0.68;
        neckPhase = sin(n * M_PI);
    }

    UIBezierPath *neckPath = nil;
    if (neckPhase > 0.01 && CGRectGetMinY(curRect) > CGRectGetMinY(self.cutoutRect) + 2.0) {
        CGFloat topY = CGRectGetMidY(self.cutoutRect);
        CGFloat botY = CGRectGetMinY(curRect) + fmin(curRadius * 0.55, 16.0);
        CGFloat topHalfW = CGRectGetWidth(self.cutoutRect) * 0.40 * (0.50 + 0.50 * neckPhase);
        CGFloat botHalfW = fmin(curW * 0.34, CGRectGetWidth(self.cutoutRect) * 0.56) * (0.45 + 0.55 * neckPhase);
        CGFloat pinchHalfW = fmax(5.0, fmin(topHalfW, botHalfW) * (0.28 + 0.32 * (1.0 - clampedP)) * amp);
        CGFloat midY = (topY + botY) * 0.52;

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
    }

    // Morph droplet fill color from pitch black (Dynamic Island) toward banner surface color
    CGFloat sr = 0.12, sg = 0.12, sb = 0.13, sa = 1.0;
    if (self.surfaceColor) {
        [self.surfaceColor getRed:&sr green:&sg blue:&sb alpha:&sa];
    }
    CGFloat colorMix = DBClamp01((clampedP - 0.18) / 0.52);
    UIColor *bodyColor = [UIColor colorWithRed:sr * colorMix green:sg * colorMix blue:sb * colorMix alpha:0.96];

    [CATransaction begin];
    [CATransaction setDisableActions:YES];

    self.bodyLayer.path = bodyPath.CGPath;
    self.bodyLayer.fillColor = bodyColor.CGColor;

    if (neckPath) {
        self.neckLayer.path = neckPath.CGPath;
        self.neckLayer.fillColor = [UIColor blackColor].CGColor;
        self.neckLayer.opacity = (float)DBClamp01(neckPhase * 1.15);
    } else {
        self.neckLayer.path = NULL;
        self.neckLayer.opacity = 0.0f;
    }

    if (!self.exiting) {
        // Hold opaque droplet during stretch, then dissolve smoothly into the revealed native banner
        CGFloat shellFade = 1.0 - DBClamp01((rawT - 0.45) / 0.45);
        self.bodyLayer.opacity = (float)shellFade;
    } else {
        self.bodyLayer.opacity = (float)DBClamp01(1.0 - rawT * 1.05);
        if (self.exitSnapshotView) {
            self.exitSnapshotView.layer.bounds = CGRectMake(0, 0, curW, curH);
            self.exitSnapshotView.layer.position = CGPointMake(curMidX, CGRectGetMidY(curRect));
            self.exitSnapshotView.layer.cornerRadius = curRadius;
            self.exitSnapshotView.layer.opacity = (float)DBClamp01((clampedP - 0.18) / 0.52);
        }
    }

    [CATransaction commit];
}

@end

#pragma mark - Banner View Extraction & Tracking

static DBDropletAnimator *gActiveAnimator = nil;

static UIView *DBExtractBannerView(id<BNPresentable> presentable) {
    if (!presentable) return nil;
    UIViewController *vc = nil;

    // 1. Primary path used by SpringBoard's SBNotificationBannerDestination (iOS 15-17+)
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

    // 2. BannerKit fallback
    if (!vc && [presentable respondsToSelector:@selector(viewController)]) {
        vc = [presentable viewController];
    }

    // 3. Presentable itself is a UIViewController
    if (!vc && [presentable isKindOfClass:[UIViewController class]]) {
        vc = (UIViewController *)presentable;
    }

    if (!vc) return nil;
    return vc.viewIfLoaded ?: vc.view;
}

static void DBScheduleEntryAnimation(id<BNPresentable> presentable, NSInteger attempt) {
    UIView *bannerView = DBExtractBannerView(presentable);
    if (bannerView && bannerView.window && !CGRectIsEmpty(bannerView.bounds)) {
        if (!gActiveAnimator) {
            gActiveAnimator = [[DBDropletAnimator alloc] init];
        }
        [gActiveAnimator startEntryForView:bannerView];
        return;
    }
    if (attempt < 4) {
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.016 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            DBScheduleEntryAnimation(presentable, attempt + 1);
        });
    }
}

#pragma mark - SpringBoard Hooks

%hook SBNotificationBannerDestination

- (void)presentableWillAppearAsBanner:(id<BNPresentable>)presentable {
    %orig;
    if (!gEnabled || UIAccessibilityIsReduceMotionEnabled()) return;

    dispatch_async(dispatch_get_main_queue(), ^{
        DBScheduleEntryAnimation(presentable, 0);
    });
}

- (void)presentableWillDisappearAsBanner:(id<BNPresentable>)presentable withReason:(NSString *)reason {
    if (gEnabled && gAnimateDismiss && !UIAccessibilityIsReduceMotionEnabled()) {
        BOOL isInteractive = (reason && ([reason.lowercaseString containsString:@"gesture"] ||
                                         [reason.lowercaseString containsString:@"drag"] ||
                                         [reason.lowercaseString containsString:@"tap"] ||
                                         [reason.lowercaseString containsString:@"action"]));
        if (!isInteractive) {
            UIView *bannerView = DBExtractBannerView(presentable);
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
}
