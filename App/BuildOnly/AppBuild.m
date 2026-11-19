#import "AppBuild.h"
#import "../../Vendor/libarchive-headers/archive.h"
#import "../../Vendor/libarchive-headers/archive_entry.h"
#import <sys/stat.h>

NSDictionary *PBPrepareAppPlan(NSString *root, NSDictionary *config, NSError **error) {
    NSString *problem = nil;
    NSString *name = config[@"productName"], *identifier = config[@"bundleIdentifier"];
    NSRegularExpression *names = [NSRegularExpression regularExpressionWithPattern:@"^[A-Za-z][A-Za-z0-9_-]*$" options:0 error:nil];
    NSRegularExpression *identifiers = [NSRegularExpression regularExpressionWithPattern:@"^[A-Za-z0-9-]+([.][A-Za-z0-9-]+)+$" options:0 error:nil];
    if (![name isKindOfClass:NSString.class] || ![names numberOfMatchesInString:name options:0 range:NSMakeRange(0, name.length)]) problem = @"App productName 需要以字母开头，仅使用字母、数字、下划线和短横线";
    if (![identifier isKindOfClass:NSString.class] || ![identifiers numberOfMatchesInString:identifier options:0 range:NSMakeRange(0, identifier.length)]) problem = @"请配置有效的 App bundleIdentifier，例如 com.example.demo";
    id resources = config[@"resources"] ?: @[];
    if (![resources isKindOfClass:NSArray.class]) problem = @"App resources 应为项目内的相对路径数组";
    NSString *infoPath = config[@"appInfoPlist"];
    if (infoPath && ![infoPath isKindOfClass:NSString.class]) problem = @"appInfoPlist 应为项目内 Info.plist 的相对路径";
    NSMutableDictionary *info = [NSMutableDictionary dictionary];
    NSMutableArray *copies = [NSMutableArray array];
    NSFileManager *files = NSFileManager.defaultManager;
    if (!problem) {
        NSMutableArray *inputs = [resources mutableCopy];
        if (infoPath) [inputs addObject:infoPath];
        for (id relative in inputs) {
            if (![relative isKindOfClass:NSString.class] || ![relative length] || [relative isAbsolutePath] || [[relative pathComponents] containsObject:@".."] || [relative isEqual:@"."]) { problem = @"App 资源路径需要位于项目内部"; break; }
            NSString *path = [root stringByAppendingPathComponent:relative];
            if (![path.stringByResolvingSymlinksInPath hasPrefix:[root.stringByResolvingSymlinksInPath stringByAppendingString:@"/"]]) { problem = @"App 资源路径需要位于项目内部"; break; }
            NSDictionary *attributes = [files attributesOfItemAtPath:path error:error];
            if (!attributes) return nil;
            if ([relative isEqual:infoPath]) {
                NSDictionary *plist = [NSDictionary dictionaryWithContentsOfFile:path];
                if (!plist) { problem = @"appInfoPlist 不是有效的属性列表字典"; break; }
                [info addEntriesFromDictionary:plist];
                continue;
            }
            NSString *destination = [relative stringByStandardizingPath];
            NSString *first = destination.pathComponents.firstObject;
            if ([@[@"Info.plist", name, @"_CodeSignature", @"embedded.mobileprovision", @"Frameworks", @"PlugIns"] containsObject:first]) { problem = @"App resources 与可执行文件、签名或保留目录冲突"; break; }
            NSMutableArray *entries = [NSMutableArray arrayWithObject:relative];
            if ([attributes[NSFileType] isEqual:NSFileTypeDirectory]) {
                for (NSString *child in [files enumeratorAtPath:path]) [entries addObject:[relative stringByAppendingPathComponent:child]];
            }
            for (NSString *entry in entries) {
                NSString *extension = entry.pathExtension.lowercaseString;
                NSDictionary *a = [files attributesOfItemAtPath:[root stringByAppendingPathComponent:entry] error:error];
                if (!a) return nil;
                if ([a[NSFileType] isEqual:NSFileTypeSymbolicLink] || [@[@"storyboard", @"xib", @"xcassets", @"framework", @"dylib", @"appex"] containsObject:extension]) {
                    problem = [NSString stringWithFormat:@"当前手机构建不处理此资源：%@。请使用普通图片、文本、bundle 等资源及代码创建的 UIKit 界面", entry]; break;
                }
            }
            if (problem) break;
            [copies addObject:@{@"source":path, @"destination":destination}];
        }
    }
    if (info[@"UIMainStoryboardFile"] || info[@"UILaunchStoryboardName"]) problem = @"当前 App 打包使用代码创建的 UIKit 界面；请移除 Storyboard 配置";
    if (problem) {
        if (error) *error = [NSError errorWithDomain:@"PocketBuild.App" code:1 userInfo:@{NSLocalizedDescriptionKey:problem}];
        return nil;
    }
    [info addEntriesFromDictionary:@{
        @"CFBundleExecutable":name, @"CFBundleIdentifier":identifier,
        @"CFBundleName":name, @"CFBundlePackageType":@"APPL",
        @"CFBundleSupportedPlatforms":@[@"iPhoneOS"],
        @"MinimumOSVersion":config[@"deploymentTarget"] ?: @"15.0",
    }];
    if (!info[@"CFBundleShortVersionString"]) info[@"CFBundleShortVersionString"] = @"1.0";
    if (!info[@"CFBundleVersion"]) info[@"CFBundleVersion"] = @"1";
    if (!info[@"UIDeviceFamily"]) info[@"UIDeviceFamily"] = @[@1, @2];
    if (!info[@"UILaunchScreen"]) info[@"UILaunchScreen"] = @{};
    return @{@"name":name, @"info":info, @"resources":copies};
}

NSArray<NSString *> *PBAppLinkArguments(NSArray<NSString *> *arguments) {
    NSMutableArray *result = [NSMutableArray array];
    for (NSUInteger i = 0; i < arguments.count; i++) {
        NSString *arg = arguments[i];
        if ([arg isEqual:@"-dylib"]) continue;
        if ([@[@"-install_name", @"-undefined", @"-rpath"] containsObject:arg]) { i++; continue; }
        [result addObject:arg];
    }
    [result addObjectsFromArray:@[@"-execute", @"-e", @"_main", @"-pie", @"-adhoc_codesign", @"-rpath", @"@executable_path/Frameworks"]];
    return result;
}

NSString *PBPackageApp(NSString *build, NSDictionary *plan, BOOL (^cancelled)(void), NSError **error) {
    NSFileManager *files = NSFileManager.defaultManager;
    NSString *name = plan[@"name"];
    NSString *payload = [build stringByAppendingPathComponent:@"Payload"];
    NSString *app = [payload stringByAppendingPathComponent:[name stringByAppendingString:@".app"]];
    NSString *output = [build stringByAppendingPathComponent:[name stringByAppendingString:@"-unsigned.ipa"]];
    if (![files createDirectoryAtPath:app withIntermediateDirectories:YES attributes:nil error:error]) return nil;
    NSString *executable = [app stringByAppendingPathComponent:name];
    if (![files copyItemAtPath:[build stringByAppendingPathComponent:name] toPath:executable error:error] ||
        ![files setAttributes:@{NSFilePosixPermissions:@0755} ofItemAtPath:executable error:error]) return nil;
    NSData *plist = [NSPropertyListSerialization dataWithPropertyList:plan[@"info"] format:NSPropertyListXMLFormat_v1_0 options:0 error:error];
    if (!plist || ![plist writeToFile:[app stringByAppendingPathComponent:@"Info.plist"] options:NSDataWritingAtomic error:error]) return nil;
    for (NSDictionary *resource in plan[@"resources"]) {
        NSString *target = [app stringByAppendingPathComponent:resource[@"destination"]];
        if (![files createDirectoryAtPath:target.stringByDeletingLastPathComponent withIntermediateDirectories:YES attributes:nil error:error] ||
            ![files copyItemAtPath:resource[@"source"] toPath:target error:error]) return nil;
    }
    struct archive *zip = archive_write_new();
    archive_write_set_format_zip(zip);
    BOOL ok = archive_write_open_filename(zip, output.fileSystemRepresentation) == ARCHIVE_OK;
    NSString *problem = nil;
    unsigned char buffer[65536];
    for (NSString *relative in [files enumeratorAtPath:payload]) {
        if (!ok) break;
        if (cancelled()) { ok = NO; problem = @"App 打包已取消"; break; }
        NSString *path = [payload stringByAppendingPathComponent:relative];
        NSDictionary *attributes = [files attributesOfItemAtPath:path error:error];
        if (!attributes) { ok = NO; break; }
        BOOL directory = [attributes[NSFileType] isEqual:NSFileTypeDirectory];
        struct archive_entry *entry = archive_entry_new();
        archive_entry_set_pathname(entry, [[@"Payload" stringByAppendingPathComponent:relative] UTF8String]);
        archive_entry_set_filetype(entry, directory ? AE_IFDIR : AE_IFREG);
        archive_entry_set_perm(entry, directory || [path isEqual:executable] ? 0755 : 0644);
        archive_entry_set_size(entry, directory ? 0 : [attributes[NSFileSize] longLongValue]);
        ok = archive_write_header(zip, entry) == ARCHIVE_OK;
        archive_entry_free(entry);
        if (ok && !directory) {
            FILE *input = fopen(path.fileSystemRepresentation, "rb");
            if (!input) { ok = NO; problem = [@"无法读取 App 资源：" stringByAppendingString:relative]; break; }
            size_t count;
            while ((count = fread(buffer, 1, sizeof(buffer), input)) > 0) {
                if (cancelled() || archive_write_data(zip, buffer, count) != (la_ssize_t)count) { ok = NO; break; }
            }
            if (ferror(input)) ok = NO;
            fclose(input);
        }
    }
    if (!ok && !problem && archive_error_string(zip)) problem = @(archive_error_string(zip));
    if (archive_write_close(zip) != ARCHIVE_OK) ok = NO;
    archive_write_free(zip);
    if (!ok) {
        [files removeItemAtPath:output error:nil];
        if (error && !*error) *error = [NSError errorWithDomain:@"PocketBuild.App" code:2 userInfo:@{NSLocalizedDescriptionKey:problem ?: @"IPA 打包失败或已取消"}];
        return nil;
    }
    return output.lastPathComponent;
}
