#import "DBRootListController.h"
#import <UIKit/UIKit.h>
#import <CoreFoundation/CoreFoundation.h>
#import <objc/message.h>
#import <math.h>

static NSString *const kDBPrefsDomain = @"com.billie.dropletbanner";
static NSString *const kDBPrefsChangedNotif = @"com.billie.dropletbanner/prefsChanged";
static NSString *const kDBTestPreviewNotif = @"com.billie.dropletbanner/testPreview";

#pragma mark - Private App Workspace Protocols (Zero External Dependencies)

@protocol DBLSApplicationProxy <NSObject>
@optional
- (NSString *)applicationIdentifier;
- (NSString *)bundleIdentifier;
- (NSString *)localizedName;
- (NSString *)applicationType;
- (NSArray *)appTags;
@end

@protocol DBLSApplicationWorkspace <NSObject>
@optional
+ (id<DBLSApplicationWorkspace>)defaultWorkspace;
- (NSArray<id<DBLSApplicationProxy>> *)allInstalledApplications;
- (NSArray<id<DBLSApplicationProxy>> *)allApplications;
@end

@interface UIImage (DBPrefsAppIcon)
+ (UIImage *)_applicationIconImageForBundleIdentifier:(NSString *)bundleIdentifier format:(int)format scale:(CGFloat)scale;
@end

#pragma mark - Preference & Color Utilities

static void DBPrefsSetObject(NSString *key, id value) {
    CFPreferencesSetAppValue((__bridge CFStringRef)key, (__bridge CFPropertyListRef)value, (__bridge CFStringRef)kDBPrefsDomain);
    CFPreferencesAppSynchronize((__bridge CFStringRef)kDBPrefsDomain);
}

static id DBPrefsCopyObject(NSString *key) {
    CFPreferencesAppSynchronize((__bridge CFStringRef)kDBPrefsDomain);
    return CFBridgingRelease(CFPreferencesCopyAppValue((__bridge CFStringRef)key, (__bridge CFStringRef)kDBPrefsDomain));
}

static void DBPrefsPostNotification(NSString *notifName) {
    CFNotificationCenterPostNotification(
        CFNotificationCenterGetDarwinNotifyCenter(),
        (__bridge CFStringRef)notifName,
        NULL,
        NULL,
        YES
    );
}

static UIColor *DBPrefsColorFromHex(NSString *hex) {
    if (![hex isKindOfClass:[NSString class]] || hex.length == 0) {
        return [UIColor colorWithRed:0.039 green:0.518 blue:1.0 alpha:1.0];
    }
    NSString *clean = [[hex stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]] uppercaseString];
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
    return [UIColor colorWithRed:((rgb >> 16) & 0xFF) / 255.0
                           green:((rgb >> 8) & 0xFF) / 255.0
                            blue:(rgb & 0xFF) / 255.0
                           alpha:1.0];
}

static NSString *DBPrefsHexFromColor(UIColor *color) {
    if (!color) return @"#0A84FF";
    CGFloat r = 0, g = 0, b = 0, a = 1;
    if (![color getRed:&r green:&g blue:&b alpha:&a]) {
        CGFloat w = 0;
        if ([color getWhite:&w alpha:&a]) {
            r = g = b = w;
        }
    }
    int ri = (int)lround(fmin(fmax(r, 0.0), 1.0) * 255.0);
    int gi = (int)lround(fmin(fmax(g, 0.0), 1.0) * 255.0);
    int bi = (int)lround(fmin(fmax(b, 0.0), 1.0) * 255.0);
    return [NSString stringWithFormat:@"#%02X%02X%02X", ri, gi, bi];
}

#pragma mark - Styled Action Button Cell

@implementation DBButtonCell

- (instancetype)initWithStyle:(UITableViewCellStyle)style reuseIdentifier:(NSString *)reuseIdentifier specifier:(PSSpecifier *)specifier {
    self = [super initWithStyle:style reuseIdentifier:reuseIdentifier specifier:specifier];
    if (self) {
        [self db_styleForSpecifier:specifier];
    }
    return self;
}

- (void)refreshCellContentsWithSpecifier:(PSSpecifier *)specifier {
    [super refreshCellContentsWithSpecifier:specifier];
    [self db_styleForSpecifier:specifier];
}

- (void)db_styleForSpecifier:(PSSpecifier *)specifier {
    NSString *btnStyle = [specifier propertyForKey:@"buttonStyle"];
    if ([btnStyle isEqualToString:@"destructive"]) {
        self.textLabel.textColor = [UIColor systemRedColor];
    } else {
        self.textLabel.textColor = [UIColor systemBlueColor];
    }
    self.textLabel.font = [UIFont systemFontOfSize:17.0 weight:UIFontWeightMedium];
}

@end

#pragma mark - Native Color Picker Swatch Cell

@interface DBColorPickerCell ()
@property (nonatomic, strong) UILabel *titleField;
@property (nonatomic, strong) UILabel *hexField;
@property (nonatomic, strong) UIView *colorSwatch;
@end

@implementation DBColorPickerCell

- (instancetype)initWithStyle:(UITableViewCellStyle)style reuseIdentifier:(NSString *)reuseIdentifier specifier:(PSSpecifier *)specifier {
    self = [super initWithStyle:style reuseIdentifier:reuseIdentifier specifier:specifier];
    if (self) {
        self.accessoryType = UITableViewCellAccessoryDisclosureIndicator;

        UILabel *title = [[UILabel alloc] init];
        title.translatesAutoresizingMaskIntoConstraints = NO;
        title.font = [UIFont systemFontOfSize:17.0 weight:UIFontWeightRegular];
        title.textColor = [UIColor labelColor];
        [self.contentView addSubview:title];
        self.titleField = title;

        UIView *swatch = [[UIView alloc] init];
        swatch.translatesAutoresizingMaskIntoConstraints = NO;
        swatch.layer.cornerRadius = 13.0;
        swatch.layer.borderWidth = 1.0;
        swatch.layer.borderColor = [UIColor colorWithWhite:1.0 alpha:0.28].CGColor;
        [self.contentView addSubview:swatch];
        self.colorSwatch = swatch;

        UILabel *hex = [[UILabel alloc] init];
        hex.translatesAutoresizingMaskIntoConstraints = NO;
        hex.font = [UIFont monospacedSystemFontOfSize:13.0 weight:UIFontWeightMedium];
        hex.textColor = [UIColor secondaryLabelColor];
        hex.textAlignment = NSTextAlignmentRight;
        [self.contentView addSubview:hex];
        self.hexField = hex;

        [NSLayoutConstraint activateConstraints:@[
            [title.leadingAnchor constraintEqualToAnchor:self.contentView.leadingAnchor constant:16.0],
            [title.centerYAnchor constraintEqualToAnchor:self.contentView.centerYAnchor],

            [swatch.trailingAnchor constraintEqualToAnchor:self.contentView.trailingAnchor constant:-10.0],
            [swatch.centerYAnchor constraintEqualToAnchor:self.contentView.centerYAnchor],
            [swatch.widthAnchor constraintEqualToConstant:26.0],
            [swatch.heightAnchor constraintEqualToConstant:26.0],

            [hex.trailingAnchor constraintEqualToAnchor:swatch.leadingAnchor constant:-10.0],
            [hex.centerYAnchor constraintEqualToAnchor:self.contentView.centerYAnchor],
            [hex.leadingAnchor constraintGreaterThanOrEqualToAnchor:title.trailingAnchor constant:8.0],
        ]];

        [self db_applySpecifier:specifier];
    }
    return self;
}

- (void)refreshCellContentsWithSpecifier:(PSSpecifier *)specifier {
    [super refreshCellContentsWithSpecifier:specifier];
    [self db_applySpecifier:specifier];
}

- (void)db_applySpecifier:(PSSpecifier *)specifier {
    self.textLabel.text = nil;
    self.detailTextLabel.text = nil;
    self.imageView.image = nil;

    self.titleField.text = [specifier propertyForKey:@"label"] ?: @"Custom Droplet Color";
    id savedHex = DBPrefsCopyObject(@"CustomDropletColorHex");
    NSString *hex = [savedHex isKindOfClass:[NSString class]] ? (NSString *)savedHex : @"#0A84FF";
    self.hexField.text = hex;
    self.colorSwatch.backgroundColor = DBPrefsColorFromHex(hex);
}

@end

#pragma mark - Custom Developer Credit Cell

@interface DBCreditCell ()
@property (nonatomic, strong) UIImageView *avatarView;
@property (nonatomic, strong) UILabel *devTitleLabel;
@property (nonatomic, strong) UILabel *devHandleLabel;
@end

@implementation DBCreditCell

- (instancetype)initWithStyle:(UITableViewCellStyle)style reuseIdentifier:(NSString *)reuseIdentifier specifier:(PSSpecifier *)specifier {
    self = [super initWithStyle:style reuseIdentifier:reuseIdentifier specifier:specifier];
    if (self) {
        self.accessoryType = UITableViewCellAccessoryNone;

        UIImageView *avatar = [[UIImageView alloc] init];
        avatar.translatesAutoresizingMaskIntoConstraints = NO;
        avatar.contentMode = UIViewContentModeScaleAspectFill;
        avatar.clipsToBounds = YES;
        avatar.layer.cornerRadius = 23.0;
        avatar.layer.borderWidth = 0.5;
        avatar.layer.borderColor = [UIColor colorWithWhite:1.0 alpha:0.22].CGColor;
        [self.contentView addSubview:avatar];
        self.avatarView = avatar;

        UILabel *titleLabel = [[UILabel alloc] init];
        titleLabel.translatesAutoresizingMaskIntoConstraints = NO;
        titleLabel.font = [UIFont systemFontOfSize:17.0 weight:UIFontWeightMedium];
        titleLabel.textColor = [UIColor labelColor];
        titleLabel.numberOfLines = 1;
        [self.contentView addSubview:titleLabel];
        self.devTitleLabel = titleLabel;

        UILabel *handleLabel = [[UILabel alloc] init];
        handleLabel.translatesAutoresizingMaskIntoConstraints = NO;
        handleLabel.font = [UIFont systemFontOfSize:13.5 weight:UIFontWeightRegular];
        handleLabel.textColor = [UIColor secondaryLabelColor];
        handleLabel.numberOfLines = 1;
        [self.contentView addSubview:handleLabel];
        self.devHandleLabel = handleLabel;

        [NSLayoutConstraint activateConstraints:@[
            [avatar.leadingAnchor constraintEqualToAnchor:self.contentView.leadingAnchor constant:16.0],
            [avatar.centerYAnchor constraintEqualToAnchor:self.contentView.centerYAnchor],
            [avatar.widthAnchor constraintEqualToConstant:46.0],
            [avatar.heightAnchor constraintEqualToConstant:46.0],

            [titleLabel.leadingAnchor constraintEqualToAnchor:avatar.trailingAnchor constant:14.0],
            [titleLabel.trailingAnchor constraintLessThanOrEqualToAnchor:self.contentView.trailingAnchor constant:-16.0],
            [titleLabel.bottomAnchor constraintEqualToAnchor:self.contentView.centerYAnchor constant:-1.0],

            [handleLabel.leadingAnchor constraintEqualToAnchor:titleLabel.leadingAnchor],
            [handleLabel.trailingAnchor constraintLessThanOrEqualToAnchor:self.contentView.trailingAnchor constant:-16.0],
            [handleLabel.topAnchor constraintEqualToAnchor:self.contentView.centerYAnchor constant:2.0],
        ]];

        [self db_applySpecifier:specifier];
    }
    return self;
}

- (void)refreshCellContentsWithSpecifier:(PSSpecifier *)specifier {
    [super refreshCellContentsWithSpecifier:specifier];
    [self db_applySpecifier:specifier];
}

- (void)db_applySpecifier:(PSSpecifier *)specifier {
    self.textLabel.text = nil;
    self.detailTextLabel.text = nil;
    self.imageView.image = nil;

    NSString *title = [specifier propertyForKey:@"creditTitle"] ?: @"Developed by Billie";
    NSString *subtitle = [specifier propertyForKey:@"creditSubtitle"] ?: @"@Billie0x";
    NSString *avatarName = [specifier propertyForKey:@"creditAvatar"] ?: @"billie_avatar";

    self.devTitleLabel.text = title;
    self.devHandleLabel.text = subtitle;

    NSBundle *bundle = [NSBundle bundleForClass:[self class]];
    UIImage *img = [UIImage imageNamed:avatarName inBundle:bundle compatibleWithTraitCollection:nil];
    self.avatarView.image = img;
}

@end

#pragma mark - Per-App Exclusion List Controller (Zero Dependencies)

@interface DBAppEntry : NSObject
@property (nonatomic, copy) NSString *bundleID;
@property (nonatomic, copy) NSString *displayName;
@end

@implementation DBAppEntry
@end

@interface DBExcludedAppsController ()
@property (nonatomic, strong) UITableView *tableView;
@property (nonatomic, strong) UISearchController *searchController;
@property (nonatomic, strong) NSArray<DBAppEntry *> *allApps;
@property (nonatomic, strong) NSArray<DBAppEntry *> *filteredApps;
@property (nonatomic, strong) NSMutableSet<NSString *> *excludedIDs;
@property (nonatomic, strong) NSCache<NSString *, UIImage *> *iconCache;
@end

@implementation DBExcludedAppsController

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = @"Excluded Apps";
    self.view.backgroundColor = [UIColor systemGroupedBackgroundColor];

    self.iconCache = [[NSCache alloc] init];
    self.iconCache.countLimit = 120;

    id saved = DBPrefsCopyObject(@"ExcludedBundleIDs");
    self.excludedIDs = [NSMutableSet set];
    if ([saved isKindOfClass:[NSArray class]]) {
        for (id item in (NSArray *)saved) {
            if ([item isKindOfClass:[NSString class]] && ((NSString *)item).length > 0) {
                [self.excludedIDs addObject:(NSString *)item];
            }
        }
    }

    self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc]
        initWithBarButtonSystemItem:UIBarButtonSystemItemAdd
                             target:self
                             action:@selector(db_addManualBundleID)];

    self.searchController = [[UISearchController alloc] initWithSearchResultsController:nil];
    self.searchController.searchResultsUpdater = self;
    self.searchController.obscuresBackgroundDuringPresentation = NO;
    self.searchController.searchBar.placeholder = @"Search apps or bundle IDs";
    self.navigationItem.searchController = self.searchController;
    self.navigationItem.hidesSearchBarWhenScrolling = NO;
    self.definesPresentationContext = YES;

    self.tableView = [[UITableView alloc] initWithFrame:self.view.bounds style:UITableViewStyleInsetGrouped];
    self.tableView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    self.tableView.dataSource = self;
    self.tableView.delegate = self;
    self.tableView.rowHeight = 56.0;
    [self.view addSubview:self.tableView];

    [self db_loadInstalledApps];
}

- (void)db_loadInstalledApps {
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        NSMutableDictionary<NSString *, DBAppEntry *> *entriesByID = [NSMutableDictionary dictionary];

        Class wsClass = NSClassFromString(@"LSApplicationWorkspace");
        id<DBLSApplicationWorkspace> workspace = nil;
        if (wsClass && [wsClass respondsToSelector:@selector(defaultWorkspace)]) {
            workspace = ((id (*)(id, SEL))objc_msgSend)(wsClass, @selector(defaultWorkspace));
        }

        NSArray<id<DBLSApplicationProxy>> *proxies = nil;
        if (workspace) {
            if ([workspace respondsToSelector:@selector(allInstalledApplications)]) {
                proxies = [workspace allInstalledApplications];
            } else if ([workspace respondsToSelector:@selector(allApplications)]) {
                proxies = [workspace allApplications];
            }
        }

        for (id<DBLSApplicationProxy> proxy in proxies) {
            NSString *bid = nil;
            if ([proxy respondsToSelector:@selector(applicationIdentifier)]) {
                bid = [proxy applicationIdentifier];
            }
            if (bid.length == 0 && [proxy respondsToSelector:@selector(bundleIdentifier)]) {
                bid = [proxy bundleIdentifier];
            }
            if (bid.length == 0) continue;

            NSString *appType = [proxy respondsToSelector:@selector(applicationType)] ? [proxy applicationType] : nil;
            NSArray *tags = [proxy respondsToSelector:@selector(appTags)] ? [proxy appTags] : nil;
            BOOL isHidden = [tags isKindOfClass:[NSArray class]] && [tags containsObject:@"hidden"];
            BOOL isUser = [appType isEqualToString:@"User"];
            BOOL isVisibleSystem = ([appType isEqualToString:@"System"] && !isHidden && ![bid hasPrefix:@"com.apple.Internal"]);

            if (!isUser && !isVisibleSystem && ![self.excludedIDs containsObject:bid]) {
                continue;
            }

            NSString *name = [proxy respondsToSelector:@selector(localizedName)] ? [proxy localizedName] : nil;
            if (name.length == 0) {
                name = bid;
            }

            DBAppEntry *entry = [[DBAppEntry alloc] init];
            entry.bundleID = bid;
            entry.displayName = name;
            entriesByID[bid] = entry;
        }

        // Ensure any manually added bundle IDs are always shown even if not currently installed
        for (NSString *excludedBid in self.excludedIDs) {
            if (!entriesByID[excludedBid]) {
                DBAppEntry *entry = [[DBAppEntry alloc] init];
                entry.bundleID = excludedBid;
                entry.displayName = excludedBid;
                entriesByID[excludedBid] = entry;
            }
        }

        NSArray<DBAppEntry *> *sorted = [entriesByID.allValues sortedArrayUsingComparator:^NSComparisonResult(DBAppEntry *a, DBAppEntry *b) {
            BOOL aExcl = [self.excludedIDs containsObject:a.bundleID];
            BOOL bExcl = [self.excludedIDs containsObject:b.bundleID];
            if (aExcl != bExcl) {
                return aExcl ? NSOrderedAscending : NSOrderedDescending;
            }
            return [a.displayName localizedCaseInsensitiveCompare:b.displayName];
        }];

        dispatch_async(dispatch_get_main_queue(), ^{
            self.allApps = sorted;
            [self db_applyFilter];
        });
    });
}

- (void)db_applyFilter {
    NSString *query = [self.searchController.searchBar.text stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    if (query.length == 0) {
        self.filteredApps = self.allApps ?: @[];
    } else {
        NSMutableArray<DBAppEntry *> *matches = [NSMutableArray array];
        for (DBAppEntry *entry in self.allApps) {
            if ([entry.displayName localizedCaseInsensitiveContainsString:query] ||
                [entry.bundleID localizedCaseInsensitiveContainsString:query]) {
                [matches addObject:entry];
            }
        }
        self.filteredApps = matches;
    }
    [self.tableView reloadData];
}

- (void)db_saveExcludedIDs {
    NSArray<NSString *> *list = [self.excludedIDs.allObjects sortedArrayUsingSelector:@selector(compare:)];
    DBPrefsSetObject(@"ExcludedBundleIDs", list);
    DBPrefsPostNotification(kDBPrefsChangedNotif);
}

- (void)db_addManualBundleID {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Exclude Bundle ID"
                                                                   message:@"Enter an app's bundle identifier (e.g. com.apple.Maps) to always use the stock iOS banner animation."
                                                            preferredStyle:UIAlertControllerStyleAlert];
    [alert addTextFieldWithConfigurationHandler:^(UITextField *tf) {
        tf.placeholder = @"com.example.app";
        tf.autocapitalizationType = UITextAutocapitalizationTypeNone;
        tf.autocorrectionType = UITextAutocorrectionTypeNo;
    }];
    [alert addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];
    [alert addAction:[UIAlertAction actionWithTitle:@"Exclude" style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
        NSString *text = [alert.textFields.firstObject.text stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
        if (text.length > 0) {
            [self.excludedIDs addObject:text];
            [self db_saveExcludedIDs];
            [self db_loadInstalledApps];
        }
    }]];
    [self presentViewController:alert animated:YES completion:nil];
}

- (void)db_toggleSwitch:(UISwitch *)sender {
    NSInteger idx = sender.tag;
    if (idx < 0 || idx >= (NSInteger)self.filteredApps.count) return;
    DBAppEntry *entry = self.filteredApps[idx];
    if (sender.isOn) {
        [self.excludedIDs addObject:entry.bundleID];
    } else {
        [self.excludedIDs removeObject:entry.bundleID];
    }
    [self db_saveExcludedIDs];
}

- (UIImage *)db_iconForBundleID:(NSString *)bundleID {
    if (!bundleID) return nil;
    UIImage *cached = [self.iconCache objectForKey:bundleID];
    if (cached) return cached;

    UIImage *icon = nil;
    if ([UIImage respondsToSelector:@selector(_applicationIconImageForBundleIdentifier:format:scale:)]) {
        @try {
            icon = [UIImage _applicationIconImageForBundleIdentifier:bundleID format:0 scale:[UIScreen mainScreen].scale];
        } @catch (NSException *exception) {}
    }
    if (!icon) {
        icon = [UIImage systemImageNamed:@"app.fill"];
    }
    if (icon) {
        [self.iconCache setObject:icon forKey:bundleID];
    }
    return icon;
}

#pragma mark - UISearchResultsUpdating

- (void)updateSearchResultsForSearchController:(UISearchController *)searchController {
    [self db_applyFilter];
}

#pragma mark - UITableViewDataSource / Delegate

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
    return 1;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    return (NSInteger)self.filteredApps.count;
}

- (NSString *)tableView:(UITableView *)tableView titleForFooterInSection:(NSInteger)section {
    return @"Toggle any app on to bypass DropletBanner and keep the stock iOS notification animation for that app. Tap + in the top right to add a bundle ID manually.";
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    static NSString *const kCellID = @"DBExcludedAppCell";
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:kCellID];
    if (!cell) {
        cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:kCellID];
        cell.selectionStyle = UITableViewCellSelectionStyleNone;
        cell.textLabel.font = [UIFont systemFontOfSize:16.0 weight:UIFontWeightMedium];
        cell.detailTextLabel.font = [UIFont systemFontOfSize:12.0 weight:UIFontWeightRegular];
        cell.detailTextLabel.textColor = [UIColor secondaryLabelColor];
    }

    DBAppEntry *entry = self.filteredApps[indexPath.row];
    cell.textLabel.text = entry.displayName;
    cell.detailTextLabel.text = entry.bundleID;
    cell.imageView.image = [self db_iconForBundleID:entry.bundleID];
    cell.imageView.layer.cornerRadius = 7.0;
    cell.imageView.clipsToBounds = YES;

    UISwitch *toggle = [cell.accessoryView isKindOfClass:[UISwitch class]]
        ? (UISwitch *)cell.accessoryView
        : [[UISwitch alloc] init];
    toggle.tag = indexPath.row;
    toggle.on = [self.excludedIDs containsObject:entry.bundleID];
    [toggle removeTarget:self action:@selector(db_toggleSwitch:) forControlEvents:UIControlEventValueChanged];
    [toggle addTarget:self action:@selector(db_toggleSwitch:) forControlEvents:UIControlEventValueChanged];
    cell.accessoryView = toggle;

    return cell;
}

@end

#pragma mark - Root Preferences Controller

@implementation DBRootListController

- (NSArray *)specifiers {
    if (!_specifiers) {
        _specifiers = [self loadSpecifiersFromPlistName:@"Root" target:self];
    }
    return _specifiers;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    [self db_setupHeaderView];
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    [self reloadSpecifierID:@"ExcludedAppsLink" animated:NO];
    [self reloadSpecifierID:@"CustomDropletColorCell" animated:NO];
}

- (void)setPreferenceValue:(id)value specifier:(PSSpecifier *)specifier {
    [super setPreferenceValue:value specifier:specifier];

    NSString *key = [specifier propertyForKey:@"key"];
    if ([key isEqualToString:@"PhysicsPreset"]) {
        NSInteger preset = [value integerValue];
        if (preset == 0) {
            DBPrefsSetObject(@"EntryDuration", @(0.34));
            DBPrefsSetObject(@"DropletAmplitude", @(0.75));
        } else if (preset == 1) {
            DBPrefsSetObject(@"EntryDuration", @(0.48));
            DBPrefsSetObject(@"DropletAmplitude", @(1.00));
        } else if (preset == 2) {
            DBPrefsSetObject(@"EntryDuration", @(0.58));
            DBPrefsSetObject(@"DropletAmplitude", @(1.38));
        }
        if (preset >= 0 && preset <= 2) {
            DBPrefsPostNotification(kDBPrefsChangedNotif);
            [self reloadSpecifierID:@"EntryDuration" animated:YES];
            [self reloadSpecifierID:@"DropletAmplitude" animated:YES];
        }
    } else if ([key isEqualToString:@"EntryDuration"] || [key isEqualToString:@"DropletAmplitude"]) {
        id curPreset = DBPrefsCopyObject(@"PhysicsPreset");
        if (!curPreset || [curPreset integerValue] != 3) {
            DBPrefsSetObject(@"PhysicsPreset", @(3));
            DBPrefsPostNotification(kDBPrefsChangedNotif);
            [self reloadSpecifierID:@"PhysicsPreset" animated:NO];
        }
    }
}

- (NSString *)excludedAppsSummary:(PSSpecifier *)specifier {
    id saved = DBPrefsCopyObject(@"ExcludedBundleIDs");
    NSUInteger count = [saved isKindOfClass:[NSArray class]] ? ((NSArray *)saved).count : 0;
    if (count == 0) return @"None";
    if (count == 1) return @"1 App";
    return [NSString stringWithFormat:@"%lu Apps", (unsigned long)count];
}

- (void)triggerTestPreview:(PSSpecifier *)specifier {
    DBPrefsPostNotification(kDBTestPreviewNotif);
}

- (void)openCustomColorPicker:(PSSpecifier *)specifier {
    UIColorPickerViewController *picker = [[UIColorPickerViewController alloc] init];
    picker.delegate = self;
    picker.supportsAlpha = NO;
    picker.title = @"Droplet Color";

    id savedHex = DBPrefsCopyObject(@"CustomDropletColorHex");
    NSString *hex = [savedHex isKindOfClass:[NSString class]] ? (NSString *)savedHex : @"#0A84FF";
    picker.selectedColor = DBPrefsColorFromHex(hex);

    [self presentViewController:picker animated:YES completion:nil];
}

- (void)colorPickerViewController:(UIColorPickerViewController *)viewController didSelectColor:(UIColor *)color continuously:(BOOL)continuously {
    NSString *hex = DBPrefsHexFromColor(color);
    DBPrefsSetObject(@"CustomDropletColorHex", hex);
    DBPrefsSetObject(@"DropletColorMode", @(2));
    DBPrefsPostNotification(kDBPrefsChangedNotif);
    [self reloadSpecifierID:@"CustomDropletColorCell" animated:NO];
    [self reloadSpecifierID:@"DropletColorMode" animated:NO];
}

- (void)colorPickerViewControllerDidFinish:(UIColorPickerViewController *)viewController {
    NSString *hex = DBPrefsHexFromColor(viewController.selectedColor);
    DBPrefsSetObject(@"CustomDropletColorHex", hex);
    DBPrefsSetObject(@"DropletColorMode", @(2));
    DBPrefsPostNotification(kDBPrefsChangedNotif);
    [self reloadSpecifierID:@"CustomDropletColorCell" animated:NO];
    [self reloadSpecifierID:@"DropletColorMode" animated:NO];
}

- (void)resetToDefaults:(PSSpecifier *)specifier {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Reset DropletBanner"
                                                                   message:@"Restore all toggles, sliders, colors, and excluded apps to their default values?"
                                                            preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];
    [alert addAction:[UIAlertAction actionWithTitle:@"Reset" style:UIAlertActionStyleDestructive handler:^(UIAlertAction *action) {
        NSArray<NSString *> *keys = @[
            @"Enabled", @"AnimateDismiss", @"PhysicsPreset", @"EntryDuration", @"DropletAmplitude",
            @"DropletColorMode", @"TintDropletWithAppIcon", @"CustomDropletColorHex",
            @"BloomRimEnabled", @"BloomRimWidth", @"BloomRimDuration",
            @"IslandRecoilEnabled", @"IslandRecoilIntensity",
            @"HapticsEnabled", @"HapticStrength",
            @"PauseInLowPowerMode", @"PauseInLandscape",
            @"ExcludedAppsEnabled", @"ExcludedBundleIDs"
        ];
        for (NSString *k in keys) {
            CFPreferencesSetAppValue((__bridge CFStringRef)k, NULL, (__bridge CFStringRef)kDBPrefsDomain);
        }
        CFPreferencesAppSynchronize((__bridge CFStringRef)kDBPrefsDomain);
        DBPrefsPostNotification(kDBPrefsChangedNotif);
        [self reloadSpecifiers];
    }]];
    [self presentViewController:alert animated:YES completion:nil];
}

- (void)db_setupHeaderView {
    NSBundle *bundle = [NSBundle bundleForClass:[self class]];
    UIImage *iconImage = [UIImage imageNamed:@"header_icon" inBundle:bundle compatibleWithTraitCollection:nil];
    if (!iconImage) {
        iconImage = [UIImage imageNamed:@"icon" inBundle:bundle compatibleWithTraitCollection:nil];
    }

    UIView *header = [[UIView alloc] initWithFrame:CGRectMake(0, 0, self.view.bounds.size.width, 138.0)];
    header.backgroundColor = [UIColor clearColor];

    UIImageView *iconView = [[UIImageView alloc] initWithImage:iconImage];
    iconView.translatesAutoresizingMaskIntoConstraints = NO;
    iconView.contentMode = UIViewContentModeScaleAspectFit;
    iconView.layer.shadowColor = [UIColor blackColor].CGColor;
    iconView.layer.shadowOpacity = 0.28;
    iconView.layer.shadowRadius = 12.0;
    iconView.layer.shadowOffset = CGSizeMake(0, 5);
    [header addSubview:iconView];

    UILabel *titleLabel = [[UILabel alloc] init];
    titleLabel.translatesAutoresizingMaskIntoConstraints = NO;
    titleLabel.text = @"DropletBanner";
    titleLabel.font = [UIFont systemFontOfSize:20.0 weight:UIFontWeightSemibold];
    titleLabel.textColor = [UIColor labelColor];
    titleLabel.textAlignment = NSTextAlignmentCenter;
    [header addSubview:titleLabel];

    UILabel *subLabel = [[UILabel alloc] init];
    subLabel.translatesAutoresizingMaskIntoConstraints = NO;
    subLabel.text = @"Dynamic Island Droplet Notifications • v1.8.0";
    subLabel.font = [UIFont systemFontOfSize:12.5 weight:UIFontWeightRegular];
    subLabel.textColor = [UIColor secondaryLabelColor];
    subLabel.textAlignment = NSTextAlignmentCenter;
    [header addSubview:subLabel];

    [NSLayoutConstraint activateConstraints:@[
        [iconView.topAnchor constraintEqualToAnchor:header.topAnchor constant:16.0],
        [iconView.centerXAnchor constraintEqualToAnchor:header.centerXAnchor],
        [iconView.widthAnchor constraintEqualToConstant:64.0],
        [iconView.heightAnchor constraintEqualToConstant:64.0],

        [titleLabel.topAnchor constraintEqualToAnchor:iconView.bottomAnchor constant:10.0],
        [titleLabel.centerXAnchor constraintEqualToAnchor:header.centerXAnchor],

        [subLabel.topAnchor constraintEqualToAnchor:titleLabel.bottomAnchor constant:3.0],
        [subLabel.centerXAnchor constraintEqualToAnchor:header.centerXAnchor],
    ]];

    self.table.tableHeaderView = header;
}

- (void)openDeveloperLink:(PSSpecifier *)specifier {
    NSString *urlString = [specifier propertyForKey:@"creditURL"] ?: @"https://github.com/Billie0x";
    NSURL *url = [NSURL URLWithString:urlString];
    if (url) {
        [[UIApplication sharedApplication] openURL:url options:@{} completionHandler:nil];
    }
}

@end
