#import <Foundation/Foundation.h>

NSDictionary *PBPrepareAppPlan(NSString *root, NSDictionary *config, NSError **error);
NSArray<NSString *> *PBAppLinkArguments(NSArray<NSString *> *arguments);
NSString *PBPackageApp(NSString *build, NSDictionary *plan, BOOL (^cancelled)(void), NSError **error);
