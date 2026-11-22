#import <Preferences/PSListController.h>
#import <Preferences/PSViewController.h>
#import <Preferences/PSTableCell.h>
#import <Preferences/PSSpecifier.h>

@interface DBRootListController : PSListController <UIColorPickerViewControllerDelegate>
@end

@interface DBExcludedAppsController : PSViewController <UITableViewDataSource, UITableViewDelegate, UISearchResultsUpdating>
@end

@interface DBColorPickerCell : PSTableCell
@end

@interface DBButtonCell : PSTableCell
@end

@interface DBCreditCell : PSTableCell
@end
