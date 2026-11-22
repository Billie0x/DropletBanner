#import "DBRootListController.h"
#import <UIKit/UIKit.h>

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
    subLabel.text = @"Dynamic Island Droplet Notifications • v1.3.0";
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

@end
