#import <UIKit/UIKit.h>
#import <QuartzCore/QuartzCore.h>
#import <CoreFoundation/CoreFoundation.h>
#import <objc/runtime.h>
#import <math.h>

#pragma mark - Private SpringBoard / BannerKit Declarations

@protocol BNPresentable <NSObject>
@optional
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
@property (nonatomic, weak) UIWindow *sourceWindow;
@property (nonatomic, strong) DBDropletEffectWindow *effectWindow;
@property (nonatomic, strong) UIView *canvasView;
@property (nonatomic, strong) CAShapeLayer *bodyLayer;
@property (nonatomic, strong) CAShapeLayer *neckLayer;
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

static inline CGFloat DBClamp01(CGFloat x) {
    return x < 0.0 ? 0.0 : (x > 1.0 ? 1.0 : x);
}

static inline CGFloat DBLerp(CGFloat a, CGFloat b, CGFloat t) {
    return a + (b - a) * t;
}

// Smooth critically-damped-like spring overshoot curve for natural droplet snap
static inline CGFloat DBDropletEase(CGFloat t, CGFloat amp) {
    t = DBClamp01(t);
    if (t >= 1.0) return 1.0;
    CGFloat zeta = 0.78;
    CGFloat omega = 9.2 + (amp - 1.0) * 1.6;
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

    // Dynamic Island devices (safeAreaInsets.top >= 54pt in portrait)
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

    // Non-notched fallback (emerge from top-center edge)
    CGFloat fallbackW = 104.0;
    CGFloat fallbackH = 24.0;
    return CGRectMake(midX - fallbackW * 0.5, 4.0, fallbackW, fallbackH);
}

static CGFloat DBResolveCornerRadius(UIView *view) {
    CGFloat r = view.layer.cornerRadius;
    if (r >= 10.0) return r;
    for (UIView *sub in view.subviews) {
        if (sub.layer.cornerRadius >= 10.0 && CGRectGetWidth(sub.bounds) > CGRectGetWidth(view.bounds) * 0.75) {
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

    if (self.contentView && !self.exiting) {
        self.contentView.transform = CGAffineTransformIdentity;
        self.contentView.alpha = 1.0;
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
    // Skip landscape or degenerate layouts (fall back to native animation)
    if (winSize.width > winSize.height || winSize.width < 250.0) return NO;

    CGRect frameInWin = [view convertRect:view.bounds toView:win];
    if (CGRectIsEmpty(frameInWin) || frameInWin.size.width < 120.0 || frameInWin.size.height < 30.0) {
        return NO;
    }

    self.contentView = view;
    self.sourceWindow = win;
    self.cutoutRect = DBResolveCutoutRectForWindow(win);
    self.cardRect = frameInWin;
    self.cardCornerRadius = DBResolveCornerRadius(view);

    DBDropletEffectWindow *overlay = nil;
    if (win.windowScene) {
        overlay = [[DBDropletEffectWindow alloc] initWithWindowScene:win.windowScene];
    } else {
        overlay = [[DBDropletEffectWindow alloc] initWithFrame:win.bounds];
    }
    overlay.frame = win.bounds;
    overlay.backgroundColor = [UIColor clearColor];
    overlay.windowLevel = win.windowLevel - 0.5;
    overlay.userInteractionEnabled = NO;

    UIView *canvas = [[UIView alloc] initWithFrame:overlay.bounds];
    canvas.backgroundColor = [UIColor clearColor];
    canvas.userInteractionEnabled = NO;
    [overlay addSubview:canvas];

    CAShapeLayer *neck = [CAShapeLayer layer];
    neck.fillColor = [UIColor blackColor].CGColor;
    [canvas.layer addSublayer:neck];

    CAShapeLayer *body = [CAShapeLayer layer];
    body.fillColor = [UIColor blackColor].CGColor;
    [canvas.layer addSublayer:body];

    overlay.hidden = NO;

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

    self.startedAt = CACurrentMediaTime();
    self.duration = gEntryDuration;
    [self renderProgress:0.0];
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

    // Place overlay above banner during retraction so snapshot smoothly pulls into island
    self.effectWindow.windowLevel = self.sourceWindow.windowLevel + 1.0;

    UIImageView *snapView = [[UIImageView alloc] initWithImage:snap];
    snapView.frame = self.cardRect;
    snapView.layer.cornerRadius = self.cardCornerRadius;
    snapView.layer.cornerCurve = kCACornerCurveContinuous;
    snapView.clipsToBounds = YES;
    [self.canvasView addSubview:snapView];
    self.exitSnapshotView = snapView;

    view.alpha = 0.0;

    self.startedAt = CACurrentMediaTime();
    self.duration = fmax(0.22, gEntryDuration * 0.58);
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
    CGFloat p = self.exiting ? (1.0 - DBEaseInOutCubic(rawT)) : DBDropletEase(rawT, amp);
    CGFloat clampedP = DBClamp01(p);

    // Current droplet rect interpolated between cutout and resting banner card
    CGFloat curW = DBLerp(CGRectGetWidth(self.cutoutRect), CGRectGetWidth(self.cardRect), clampedP);
    CGFloat curH = DBLerp(CGRectGetHeight(self.cutoutRect), CGRectGetHeight(self.cardRect), clampedP);
    CGFloat curMidX = DBLerp(CGRectGetMidX(self.cutoutRect), CGRectGetMidX(self.cardRect), clampedP);
    CGFloat curMinY = DBLerp(CGRectGetMinY(self.cutoutRect), CGRectGetMinY(self.cardRect), p);
    CGRect curRect = CGRectMake(curMidX - curW * 0.5, curMinY, curW, curH);

    CGFloat cutoutRadius = CGRectGetHeight(self.cutoutRect) * 0.5;
    CGFloat curRadius = DBLerp(cutoutRadius, self.cardCornerRadius, clampedP);

    // Draw liquid droplet body (fades out once native banner reveals)
    UIBezierPath *bodyPath = [UIBezierPath bezierPathWithRoundedRect:curRect cornerRadius:curRadius];
    self.bodyLayer.path = bodyPath.CGPath;

    // Draw gooey neck bridging cutout bottom to dropping banner top during stretch phase (0.05 -> 0.58)
    CGFloat neckPhase = 0.0;
    if (clampedP > 0.03 && clampedP < 0.62) {
        CGFloat n = (clampedP - 0.03) / 0.59;
        neckPhase = sin(n * M_PI);
    }

    if (neckPhase > 0.01 && CGRectGetMinY(curRect) > CGRectGetMinY(self.cutoutRect) + 2.0) {
        CGFloat topY = CGRectGetMidY(self.cutoutRect);
        CGFloat botY = CGRectGetMinY(curRect) + fmin(curRadius * 0.55, 14.0);
        CGFloat topHalfW = CGRectGetWidth(self.cutoutRect) * 0.36 * (0.55 + 0.45 * neckPhase);
        CGFloat botHalfW = fmin(curW * 0.32, CGRectGetWidth(self.cutoutRect) * 0.52) * (0.45 + 0.55 * neckPhase);
        CGFloat pinchHalfW = fmax(4.0, fmin(topHalfW, botHalfW) * (0.28 + 0.30 * (1.0 - clampedP)) * amp);
        CGFloat midY = (topY + botY) * 0.52;

        UIBezierPath *neckPath = [UIBezierPath bezierPath];
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

        self.neckLayer.path = neckPath.CGPath;
        self.neckLayer.opacity = (float)DBClamp01(neckPhase * 1.15);
    } else {
        self.neckLayer.path = NULL;
        self.neckLayer.opacity = 0.0f;
    }

    // Transform native banner (entry) or snapshot (exit) to ride inside the droplet
    CGFloat scaleX = fmax(0.15, curW / fmax(1.0, CGRectGetWidth(self.cardRect)));
    CGFloat scaleY = fmax(0.15, curH / fmax(1.0, CGRectGetHeight(self.cardRect)));
    CGFloat dx = CGRectGetMidX(curRect) - CGRectGetMidX(self.cardRect);
    CGFloat dy = CGRectGetMidY(curRect) - CGRectGetMidY(self.cardRect);

    CGAffineTransform t = CGAffineTransformConcat(
        CGAffineTransformMakeScale(scaleX, scaleY),
        CGAffineTransformMakeTranslation(dx, dy)
    );

    if (!self.exiting) {
        // Reveal native banner smoothly from p = 0.22 to 0.72 while dark droplet shell dissolves behind it
        CGFloat reveal = DBClamp01((clampedP - 0.20) / 0.48);
        CGFloat shellFade = 1.0 - DBClamp01((clampedP - 0.35) / 0.38);

        self.bodyLayer.opacity = (float)shellFade;
        self.contentView.transform = t;
        self.contentView.alpha = reveal;
    } else {
        CGFloat snapAlpha = DBClamp01((clampedP - 0.15) / 0.55);
        CGFloat shellAlpha = DBClamp01(1.0 - rawT * 1.15);

        self.bodyLayer.opacity = (float)shellAlpha;
        self.exitSnapshotView.transform = t;
        self.exitSnapshotView.alpha = snapAlpha;
    }
}

@end

#pragma mark - Active Animator Tracking

static DBDropletAnimator *gActiveAnimator = nil;

static UIView *DBExtractBannerView(id<BNPresentable> presentable) {
    if (!presentable) return nil;
    if ([presentable respondsToSelector:@selector(viewController)]) {
        UIViewController *vc = [presentable viewController];
        if (vc && vc.isViewLoaded && vc.view) {
            return vc.view;
        }
    }
    return nil;
}

#pragma mark - SpringBoard Hooks

%hook SBNotificationBannerDestination

- (void)presentableWillAppearAsBanner:(id<BNPresentable>)presentable {
    %orig;
    if (!gEnabled || UIAccessibilityIsReduceMotionEnabled()) return;

    // Wait one runloop turn so BannerKit finishes laying out the resting banner frame
    dispatch_async(dispatch_get_main_queue(), ^{
        UIView *bannerView = DBExtractBannerView(presentable);
        if (!bannerView || !bannerView.window) return;

        if (!gActiveAnimator) {
            gActiveAnimator = [[DBDropletAnimator alloc] init];
        }
        [gActiveAnimator startEntryForView:bannerView];
    });
}

- (void)presentableWillDisappearAsBanner:(id<BNPresentable>)presentable withReason:(NSString *)reason {
    if (gEnabled && gAnimateDismiss && !UIAccessibilityIsReduceMotionEnabled()) {
        // Do not hijack interactive user swipe-up/tap dismissals
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
