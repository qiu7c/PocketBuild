#import "../SDKResources.h"
#import "PackagePaths.h"

NSDictionary *TMCSDKBuildSettings(NSDictionary *config, NSUserDefaults *defaults, NSError **error) {
    id sdk = config[@"sdkVersion"] ?: [defaults objectForKey:@"StudioSDKVersion"] ?: @"16.4";
    id minimum = config[@"deploymentTarget"] ?: [defaults objectForKey:@"StudioDeploymentTarget"] ?: @"15.0";
    BOOL validSDK = [sdk isKindOfClass:NSString.class] && [@[@"16.4",@"26.0"] containsObject:sdk];
    BOOL validMinimum = [minimum isKindOfClass:NSString.class] &&
        [minimum rangeOfString:@"^[0-9]{1,2}[.][0-9]{1,2}([.][0-9]{1,2})?$"
            options:NSRegularExpressionSearch].location != NSNotFound;
    if (validSDK && validMinimum && !config[@"deploymentTarget"] &&
        [minimum compare:sdk options:NSNumericSearch] == NSOrderedDescending) minimum = @"15.0";
    if (!validSDK || !validMinimum || [minimum compare:@"15.0" options:NSNumericSearch] == NSOrderedAscending ||
        [minimum compare:sdk options:NSNumericSearch] == NSOrderedDescending) {
        if (error) *error = [NSError errorWithDomain:@"PocketBuild.SDK" code:1
            userInfo:@{NSLocalizedDescriptionKey:@"请选择 SDK 16.4 或 26.0，并填写对应范围内的最低 iOS 版本（至少 15.0）。"}];
        return nil;
    }
    return @{@"sdkVersion":sdk,@"deploymentTarget":minimum};
}
NSString *TMCPrepareSelectedSDK(NSBundle *bundle, NSString *cacheRoot, NSString *version, NSError **error) {
    NSString *path = PBInstalledPackage([version isEqual:@"26.0"] ? @"sdk26" : @"sdk16");
    if (!path) {
        if (error) *error = [NSError errorWithDomain:@"PocketBuild.SDK" code:2
            userInfo:@{NSLocalizedDescriptionKey:[NSString stringWithFormat:@"请先在工具链管理中安装 iOS %@ SDK。",version]}];
    }
    return path;
}
NSString *TMCPrepareSDK(NSBundle *bundle, NSString *cacheRoot, NSError **error) {
    return TMCPrepareSelectedSDK(bundle, cacheRoot, @"16.4", error);
}
BOOL TMCSDKIsInstalled(NSBundle *bundle, NSString *cacheRoot, NSString *version) {
    return PBInstalledPackage([version isEqual:@"26.0"] ? @"sdk26" : @"sdk16") != nil;
}
