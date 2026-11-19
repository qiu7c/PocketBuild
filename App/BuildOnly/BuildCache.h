#import <Foundation/Foundation.h>
NSString *DXBuildInputFingerprint(NSString *root,NSDictionary *config);
BOOL DXBuildRestoreObject(NSString *fingerprint,NSArray *arguments,NSString *root,NSString *build,NSString *object,NSString *cache);
void DXBuildSaveObject(NSString *fingerprint,NSArray *arguments,NSString *root,NSString *build,NSString *object,NSString *cache);
