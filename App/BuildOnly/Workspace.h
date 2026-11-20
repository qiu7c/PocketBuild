#import <UIKit/UIKit.h>

UINavigationController *PBNavigation(UIViewController *root);
UIViewController *PBWorkspace(void);
BOOL PBOpenComponents(UIViewController *from);
UIViewController *PBBuildsHome(void);
UIViewController *PBProjectBuilds(NSString *identifier);
UIViewController *PBBuildResult(NSString *identifier);
UIViewController *PBConnectionDiagnostics(void);
UIViewController *PBSettingsHome(void);
UIViewController *PBStoragePage(void);
UIViewController *PBTextPage(NSString *title, NSString *text);
