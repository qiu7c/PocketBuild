#import <Foundation/Foundation.h>

NS_INLINE NSString *PBPackagesDirectory(void) {
    NSString *support = NSSearchPathForDirectoriesInDomains(NSApplicationSupportDirectory, NSUserDomainMask, YES).firstObject;
    return [support stringByAppendingPathComponent:@"PocketBuild/Packages"];
}

NS_INLINE NSString *PBInstalledPackage(NSString *identifier) {
    NSString *registry = [PBPackagesDirectory() stringByAppendingPathComponent:@"installed.plist"];
    NSString *digest = [NSDictionary dictionaryWithContentsOfFile:registry][identifier][@"sha256"];
    return digest ? [[PBPackagesDirectory() stringByAppendingPathComponent:identifier]
        stringByAppendingPathComponent:digest] : nil;
}
