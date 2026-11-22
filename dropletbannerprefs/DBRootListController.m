#import "DBRootListController.h"
#import <UIKit/UIKit.h>

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
    // Clear built-in PSTableCell labels so only our custom credit layout renders
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
    subLabel.text = @"Dynamic Island Droplet Notifications • v1.7.0";
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
