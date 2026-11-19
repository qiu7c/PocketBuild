#import "BuildService.h"
#import "../Remote/DXRemoteHTTP.h"
#import "../Remote/DXRemoteNetwork.h"
#import "../CompilerController.h"
#import "../ArchiveImport.h"
#import "ScreenAwake.h"
#import "Toolchains.h"
#import "PackagePaths.h"
#import <ifaddrs.h>
#import <net/if.h>
#import <errno.h>
#import <stdio.h>
#import <Security/Security.h>

NSNotificationName const PBTrialChanged = @"PocketBuild.TrialChanged";

@interface DXBuildService ()
@property (nonatomic) DXRemoteHTTP *http;
@property (nonatomic) CompilerController *compiler;
@property (nonatomic) NSString *state, *origin, *code, *projects;
@property (nonatomic) NSMutableDictionary *job;
@property (nonatomic) NSMutableDictionary<NSString *, NSMutableDictionary *> *jobs;
@property (nonatomic) NSMutableDictionary<NSString *, NSMutableDictionary *> *uploads;
@property (nonatomic) BOOL activeCodeIsFixed;
@property (nonatomic) NSDate *startedAt, *lastRequestAt;
@property (nonatomic) NSUInteger requestCount;
@property (nonatomic) BOOL trialRunning;
@property (nonatomic) double trialProgress;
@property (nonatomic) NSString *trialMessage;
@property (nonatomic) NSString *trialWorkspace;
@end

@implementation DXBuildService

- (BOOL)fixedCodeEnabled { return [NSUserDefaults.standardUserDefaults boolForKey:@"FixedConnectionCode"]; }
- (void)setFixedCodeEnabled:(BOOL)enabled { [NSUserDefaults.standardUserDefaults setBool:enabled forKey:@"FixedConnectionCode"]; }
- (NSString *)fixedCode {
    CFTypeRef data = NULL;
    OSStatus status = SecItemCopyMatching((__bridge CFDictionaryRef)@{
        (__bridge id)kSecClass:(__bridge id)kSecClassGenericPassword,
        (__bridge id)kSecAttrService:@"com.qiu7c.pocketbuild.pairing", (__bridge id)kSecAttrAccount:@"fixed-code",
        (__bridge id)kSecReturnData:@YES}, &data);
    return status == errSecSuccess ? [[NSString alloc] initWithData:CFBridgingRelease(data) encoding:NSUTF8StringEncoding] : nil;
}
+ (NSString *)newConnectionCode:(NSError **)error {
    unsigned char bytes[16];
    OSStatus status = SecRandomCopyBytes(kSecRandomDefault, sizeof(bytes), bytes);
    if (status != errSecSuccess) {
        if (error) *error = [NSError errorWithDomain:NSOSStatusErrorDomain code:status userInfo:nil];
        return nil;
    }
    NSMutableString *code = [NSMutableString string];
    for (NSUInteger i=0; i<sizeof(bytes); i++) [code appendFormat:@"%02x",bytes[i]];
    return code;
}
- (BOOL)saveFixedCode:(NSString *)code error:(NSError **)error {
    if (!code.length) code = [DXBuildService newConnectionCode:error];
    if (!code) return NO;
    if ([code rangeOfString:@"\\A[A-Za-z0-9_-]{8,64}\\z" options:NSRegularExpressionSearch].location == NSNotFound) {
        if (error) *error = [NSError errorWithDomain:@"PocketBuild.Pairing" code:1 userInfo:@{NSLocalizedDescriptionKey:@"连接码使用 8–64 位字母、数字、下划线或短横线。"}];
        return NO;
    }
    NSDictionary *query = @{(__bridge id)kSecClass:(__bridge id)kSecClassGenericPassword,
        (__bridge id)kSecAttrService:@"com.qiu7c.pocketbuild.pairing", (__bridge id)kSecAttrAccount:@"fixed-code"};
    NSDictionary *attributes = @{(__bridge id)kSecValueData:[code dataUsingEncoding:NSUTF8StringEncoding],
        (__bridge id)kSecAttrAccessible:(__bridge id)kSecAttrAccessibleWhenUnlockedThisDeviceOnly};
    OSStatus status = SecItemUpdate((__bridge CFDictionaryRef)query, (__bridge CFDictionaryRef)attributes);
    if (status == errSecItemNotFound) {
        NSMutableDictionary *item = [query mutableCopy]; [item addEntriesFromDictionary:attributes];
        status = SecItemAdd((__bridge CFDictionaryRef)item, NULL);
    }
    if (status != errSecSuccess && error) *error = [NSError errorWithDomain:NSOSStatusErrorDomain code:status userInfo:@{NSLocalizedDescriptionKey:[NSString stringWithFormat:@"固定连接码保存失败（%d）",(int)status]}];
    return status == errSecSuccess;
}
- (NSDictionary *)latestJob { return self.job ?: @{}; }

- (BOOL)prepareCompiler:(NSError **)error {
    if (self.compiler) return YES;
    if (![PBToolchains.shared loadCompiler:error]) return NO;
    Class controller = NSClassFromString(@"CompilerController");
    self.compiler = [controller new];
    [self.compiler loadViewIfNeeded];
    return YES;
}

- (BOOL)runTrialWithSDK:(NSString *)sdk usesCXX:(BOOL)usesCXX error:(NSError **)error {
    PBToolchains *store = PBToolchains.shared;
    NSString *reason = nil;
    if (store.buildRunning || store.busy) {
        reason = @"请等当前构建或组件安装结束。";
    } else {
        for (NSString *identifier in [PBToolchains requiredPackagesForSDK:sdk usesCXX:usesCXX]) {
            if (!PBInstalledPackage(identifier)) {
                reason = @"请先安装此用途缺少的组件。";
                break;
            }
        }
    }
    if (reason) {
        if (error) *error = [NSError errorWithDomain:@"PocketBuild.Trial" code:1
            userInfo:@{NSLocalizedDescriptionKey:reason}];
        return NO;
    }
    if (![self prepareCompiler:error]) return NO;

    NSFileManager *files = NSFileManager.defaultManager;
    NSString *workspace = self.trialWorkspace;
    NSString *project = [workspace stringByAppendingPathComponent:@"project"];
    NSString *template = [NSBundle.mainBundle pathForResource:@"AppTemplate" ofType:nil];
    if ([files fileExistsAtPath:workspace] && ![files removeItemAtPath:workspace error:error]) return NO;
    if (![files createDirectoryAtPath:workspace withIntermediateDirectories:YES attributes:nil error:error]) return NO;
    if (![files copyItemAtPath:template toPath:project error:error]) {
        [files removeItemAtPath:workspace error:nil];
        return NO;
    }

    NSString *manifestPath = [project stringByAppendingPathComponent:@"MobileCompiler.json"];
    NSData *templateConfig = [NSData dataWithContentsOfFile:manifestPath options:0 error:error];
    NSMutableDictionary *config = templateConfig ?
        [NSJSONSerialization JSONObjectWithData:templateConfig options:NSJSONReadingMutableContainers error:error] : nil;
    if (!config) {
        [files removeItemAtPath:workspace error:nil];
        return NO;
    }
    config[@"sdkVersion"] = sdk;
    if (usesCXX) {
        NSString *source = @"#include <type_traits>\nstatic_assert(std::is_integral<int>::value);\nint pocketbuild_trial_cpp() { return 42; }\n";
        if (![source writeToFile:[project stringByAppendingPathComponent:@"trial.cpp"] atomically:YES
            encoding:NSUTF8StringEncoding error:error]) {
            [files removeItemAtPath:workspace error:nil];
            return NO;
        }
        config[@"sources"] = @[@"main.m", @"trial.cpp"];
    }
    NSData *configured = [NSJSONSerialization dataWithJSONObject:config options:0 error:error];
    if (![configured writeToFile:manifestPath options:NSDataWritingAtomic error:error]) {
        [files removeItemAtPath:workspace error:nil];
        return NO;
    }

    self.compiler.importedProject = project;
    self.compiler.importedSource = nil;
    self.compiler.trialWorkspace = workspace;
    self.compiler.checkpointCacheDirectory = [workspace stringByAppendingPathComponent:@"checkpoints"];
    self.trialRunning = YES;
    self.trialProgress = 0;
    self.trialMessage = [NSString stringWithFormat:@"正在使用 iOS %@ SDK 试编译 UIKit 示例…", sdk];
    store.buildRunning = YES;
    TFScreenAwakeSet(@"trial-build", YES);

    __weak typeof(self) weak = self;
    self.compiler.buildProgress = ^(NSString *stage, double progress) {
        if (!weak.compiler.cancelRequested) weak.trialMessage = stage;
        weak.trialProgress = progress;
        [NSNotificationCenter.defaultCenter postNotificationName:PBTrialChanged object:weak];
    };
    self.compiler.buildCompletion = ^(BOOL success) {
        DXBuildService *service = weak;
        CompilerController *compiler = service.compiler;
        if (compiler.cancelRequested) {
            service.trialMessage = @"试编译已取消。";
        } else if (success) {
            service.trialMessage = [NSString stringWithFormat:@"试编译通过。iOS %@ SDK 已完成编译、链接和 IPA 打包。", sdk];
        } else {
            NSString *path = [compiler.lastBuild stringByAppendingPathComponent:@"build.log"];
            NSString *log = [NSString stringWithContentsOfFile:path encoding:NSUTF8StringEncoding error:nil];
            NSMutableArray<NSString *> *errors = [NSMutableArray array];
            for (NSString *line in [log componentsSeparatedByCharactersInSet:NSCharacterSet.newlineCharacterSet]) {
                if ([line containsString:@"error:"]) [errors addObject:[line stringByReplacingOccurrencesOfString:workspace withString:@"试编译"]];
                if (errors.count == 3) break;
            }
            NSString *detail = errors.count ? [errors componentsJoinedByString:@"\n"] : compiler.console.text;
            NSData *reportData = [NSData dataWithContentsOfFile:[compiler.lastBuild stringByAppendingPathComponent:@"report.json"]];
            NSDictionary *report = reportData ? [NSJSONSerialization JSONObjectWithData:reportData options:0 error:nil] : nil;
            service.trialMessage = [NSString stringWithFormat:@"试编译失败。\n%@", report[@"packageError"] ?: detail];
        }
        [files changeCurrentDirectoryPath:NSHomeDirectory()];
        NSError *cleanupError = nil;
        if ([files removeItemAtPath:workspace error:&cleanupError]) {
            service.trialMessage = [service.trialMessage stringByAppendingString:@"\n临时工程、缓存和产物已清理。"];
        } else {
            service.trialMessage = [service.trialMessage stringByAppendingFormat:@"\n清理失败：%@", cleanupError.localizedDescription];
        }
        compiler.trialWorkspace = nil;
        compiler.checkpointCacheDirectory = nil;
        compiler.lastBuild = nil;
        compiler.lastPackage = nil;
        compiler.importedProject = nil;
        compiler.buildProgress = nil;
        compiler.buildCompletion = nil;
        service.trialRunning = NO;
        TFScreenAwakeSet(@"trial-build", NO);
        store.buildRunning = NO;
    };
    [self.compiler runProof];
    return YES;
}

- (void)cancelTrial {
    if (!self.trialRunning) return;
    self.compiler.cancelRequested = YES;
    self.trialMessage = @"正在取消，等待当前编译步骤结束…";
    [NSNotificationCenter.defaultCenter postNotificationName:PBTrialChanged object:self];
}

+ (instancetype)shared {
    static DXBuildService *service;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ service = [self new]; });
    return service;
}

+ (NSArray<NSDictionary *> *)interfaces {
    NSMutableArray *result = [NSMutableArray array];
    struct ifaddrs *interfaces = NULL;
    if (getifaddrs(&interfaces) != 0) return result;
    for (struct ifaddrs *item = interfaces; item; item = item->ifa_next) {
        if (!item->ifa_addr || item->ifa_addr->sa_family != AF_INET) continue;
        char bytes[INET_ADDRSTRLEN];
        struct sockaddr_in *address = (struct sockaddr_in *)item->ifa_addr;
        if (!inet_ntop(AF_INET, &address->sin_addr, bytes, sizeof(bytes))) continue;
        NSString *ip = @(bytes), *name = @(item->ifa_name);
        if (DXRemoteInterfaceAllowed(ip, name, (item->ifa_flags & IFF_UP) != 0, @"wifi")) {
            [result addObject:@{@"address": ip, @"interface": name}];
        }
    }
    freeifaddrs(interfaces);
    return [result sortedArrayUsingComparator:^NSComparisonResult(NSDictionary *a, NSDictionary *b) {
        BOOL aHotspot = [a[@"interface"] hasPrefix:@"bridge"];
        BOOL bHotspot = [b[@"interface"] hasPrefix:@"bridge"];
        if (aHotspot != bHotspot) return aHotspot ? NSOrderedAscending : NSOrderedDescending;
        return [a[@"interface"] compare:b[@"interface"]];
    }];
}

- (instancetype)init {
    if ((self = [super init])) {
        _state = @"已停止";
        _uploads = [NSMutableDictionary dictionary];
        _jobs = [NSMutableDictionary dictionary];
        _trialWorkspace = [NSTemporaryDirectory() stringByAppendingPathComponent:@"PocketBuild-Trial"].stringByStandardizingPath;
        [NSFileManager.defaultManager removeItemAtPath:_trialWorkspace error:nil];
        NSString *documents = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES).firstObject;
        _projects = [documents stringByAppendingPathComponent:@"Projects"];
        [NSFileManager.defaultManager createDirectoryAtPath:_projects withIntermediateDirectories:YES attributes:nil error:nil];
        _http = [[DXRemoteHTTP alloc] initWithQueue:dispatch_get_main_queue()];
        __weak typeof(self) weak = self;
        _http.handler = ^NSDictionary *(NSDictionary *request) {
            return [weak handle:request];
        };
        _http.stateChanged = ^(NSString *state) {
            BOOL running = [state isEqual:@"running"];
            weak.state = running ? @"运行中" : @"监听失败，请检查地址和端口";
            if (running && !weak.startedAt) weak.startedAt = NSDate.date;
            if (!running) {
                weak.origin = nil;
                weak.code = nil;
                weak.startedAt = nil;
                TFScreenAwakeSet(@"remote-build", NO);
            }
            if (weak.changed) weak.changed();
        };
    }
    return self;
}

- (void)startAddress:(NSString *)address port:(NSUInteger)port {
    [self stop];
    NSError *error = nil;
    self.activeCodeIsFixed = self.fixedCodeEnabled;
    NSString *code = self.activeCodeIsFixed ? self.fixedCode : [DXBuildService newConnectionCode:&error];
    if (self.activeCodeIsFixed && !code && [self saveFixedCode:@"" error:&error]) code = self.fixedCode;
    if (!code) {
        self.state = error.localizedDescription ?: @"无法取得连接码";
        if (self.changed) self.changed();
        return;
    }
    if (![self.http startAddress:address port:port error:&error]) {
        self.state = error.localizedDescription;
    } else {
        self.code = code;
        self.origin = self.http.origin;
        self.state = @"正在启动";
        self.requestCount = 0;
        self.lastRequestAt = nil;
        TFScreenAwakeSet(@"remote-build", YES);
    }
    if (self.changed) self.changed();
}

- (void)stop {
    [self.http stop];
    for (NSDictionary *upload in self.uploads.allValues) {
        [NSFileManager.defaultManager removeItemAtPath:upload[@"temporary"] error:nil];
    }
    [self.uploads removeAllObjects];
    self.origin = nil;
    self.code = nil;
    self.startedAt = nil;
    self.state = @"已停止";
    TFScreenAwakeSet(@"remote-build", NO);
    if (self.changed) self.changed();
}

static NSDictionary *Failure(NSInteger status, NSString *message) {
    return DXRemoteResponse(status, @{@"error": message});
}

- (NSDictionary *)handle:(NSDictionary *)request {
    NSString *route = request[@"path"], *method = request[@"method"];
    if ([method isEqual:@"GET"] && [@[@"/", @"/app.js", @"/style.css"] containsObject:route]) {
        NSString *name = [route isEqual:@"/"] ? @"index.html" : [route substringFromIndex:1];
        NSString *file = [NSBundle.mainBundle.bundlePath stringByAppendingPathComponent:
            [@"BuildWeb" stringByAppendingPathComponent:name]];
        NSString *type = [name hasSuffix:@".js"] ? @"application/javascript; charset=utf-8" :
            [name hasSuffix:@".css"] ? @"text/css; charset=utf-8" : @"text/html; charset=utf-8";
        return @{@"status": @200, @"type": type, @"filePath": file};
    }
    NSString *authorization = request[@"headers"][@"authorization"];
    if (!self.code || ![authorization isEqual:[@"Bearer " stringByAppendingString:self.code]]) {
        return Failure(401, @"连接码无效，请查看手机上的当前连接码");
    }
    self.requestCount++;
    self.lastRequestAt = NSDate.date;
    NSURLComponents *components = [NSURLComponents componentsWithString:route];
    NSMutableDictionary *query = [NSMutableDictionary dictionary];
    for (NSURLQueryItem *item in components.queryItems) query[item.name] = item.value;
    if ([method isEqual:@"GET"] && [components.path isEqual:@"/download"]) {
        NSString *file = query[@"file"];
        NSDictionary *job = query[@"job"] ? self.jobs[query[@"job"]] : self.job;
        NSArray *artifacts = job[@"artifacts"] ?: @[];
        if (![artifacts containsObject:file]) return Failure(404, @"产物不存在");
        return @{@"status": @200, @"filePath": [job[@"buildPath"] stringByAppendingPathComponent:file],
            @"headers": @{@"Content-Disposition": @"attachment"}};
    }
    if (![method isEqual:@"POST"] || ![route isEqual:@"/api/v1/workspace"]) return Failure(404, @"接口不存在");
    NSError *error = nil;
    id body = [NSJSONSerialization JSONObjectWithData:request[@"body"] options:0 error:&error];
    if (![body isKindOfClass:NSDictionary.class] || ![body[@"action"] isKindOfClass:NSString.class]) {
        return Failure(400, @"请求需要 JSON action");
    }
    NSString *action = body[@"action"];
    NSFileManager *files = NSFileManager.defaultManager;
    if ([action isEqual:@"device"]) {
        return DXRemoteResponse(200, @{@"name":@"PocketBuild",
            @"version":[NSBundle.mainBundle objectForInfoDictionaryKey:@"CFBundleShortVersionString"] ?: @"0.1.0",
            @"build":[NSBundle.mainBundle objectForInfoDictionaryKey:@"CFBundleVersion"],
            @"systemVersion":UIDevice.currentDevice.systemVersion,
            @"capabilities":@[@"tweak", @"app-uikit", @"chunked-upload", @"build-jobs"],
            @"tools":PBToolchains.shared.status});
    }
    if ([action isEqual:@"projects"]) {
        NSMutableArray *projects = [NSMutableArray array];
        for (NSString *identifier in [files contentsOfDirectoryAtPath:self.projects error:nil]) {
            if (![[NSUUID alloc] initWithUUIDString:identifier]) continue;
            NSString *root = [self.projects stringByAppendingPathComponent:identifier];
            NSDictionary *metadata = [NSDictionary dictionaryWithContentsOfFile:[root stringByAppendingPathComponent:@".buildproject"]];
            [projects addObject:@{@"id": identifier, @"name": metadata[@"name"] ?: identifier}];
        }
        return DXRemoteResponse(200, @{@"projects": projects});
    }
    if ([action isEqual:@"create"]) {
        NSString *name = body[@"name"];
        if (![name isKindOfClass:NSString.class] || !name.length) return Failure(400, @"请填写项目名称");
        NSString *product = body[@"productType"] ?: @"tweak";
        if (![@[@"tweak", @"app"] containsObject:product]) return Failure(400, @"productType 应为 tweak 或 app");
        NSString *identifier = NSUUID.UUID.UUIDString;
        NSString *root = [self.projects stringByAppendingPathComponent:identifier];
        if (![files createDirectoryAtPath:root withIntermediateDirectories:NO attributes:nil error:&error]) return Failure(500, error.localizedDescription);
        if ([product isEqual:@"app"]) {
            NSString *template = [NSBundle.mainBundle.bundlePath stringByAppendingPathComponent:@"AppTemplate"];
            for (NSString *file in [files contentsOfDirectoryAtPath:template error:&error]) {
                if (![files copyItemAtPath:[template stringByAppendingPathComponent:file] toPath:[root stringByAppendingPathComponent:file] error:&error]) break;
            }
            if (error) { [files removeItemAtPath:root error:nil]; return Failure(500, error.localizedDescription); }
        }
        if (![@{@"name": name} writeToFile:[root stringByAppendingPathComponent:@".buildproject"] atomically:YES]) {
            [files removeItemAtPath:root error:nil];
            return Failure(500, @"项目记录保存失败");
        }
        return DXRemoteResponse(200, @{@"id": identifier, @"name": name});
    }
    if ([action isEqual:@"tools"]) return DXRemoteResponse(200, PBToolchains.shared.status);
    NSString *jobID = body[@"job_id"];
    if (jobID && (![jobID isKindOfClass:NSString.class] || !self.jobs[jobID])) return Failure(404, @"构建任务不存在；任务编号在手机 App 重启后失效");
    NSMutableDictionary *requestedJob = jobID ? self.jobs[jobID] : self.job;
    if ([action isEqual:@"job"]) {
        NSMutableDictionary *job = [requestedJob mutableCopy] ?: [@{@"state": @"idle"} mutableCopy];
        if (job[@"buildPath"]) {
            NSString *path = [job[@"buildPath"] stringByAppendingPathComponent:@"build.log"];
            job[@"log"] = [NSString stringWithContentsOfFile:path encoding:NSUTF8StringEncoding error:nil] ?: @"";
        }
        [job removeObjectForKey:@"buildPath"];
        return DXRemoteResponse(200, job);
    }
    if ([action isEqual:@"cancel"]) {
        if (![requestedJob[@"state"] isEqual:@"running"]) return DXRemoteResponse(200, @{@"state":requestedJob[@"state"] ?: @"idle"});
        self.compiler.cancelRequested = YES;
        return DXRemoteResponse(200, @{@"state": @"cancelling"});
    }

    if ([@[@"upload_chunk",@"upload_finish",@"upload_abort"] containsObject:action]) {
        NSString *uploadID = body[@"upload"];
        if (![uploadID isKindOfClass:NSString.class]) return Failure(400, @"上传标识无效");
        NSMutableDictionary *upload = self.uploads[uploadID];
        if (!upload) return Failure(404, @"上传任务已不存在，请重新上传");
        NSString *temporary = upload[@"temporary"];
        if ([action isEqual:@"upload_abort"]) {
            [files removeItemAtPath:temporary error:nil];
            [self.uploads removeObjectForKey:uploadID];
            return DXRemoteResponse(200, @{@"aborted":@YES});
        }
        if ([action isEqual:@"upload_chunk"]) {
            NSNumber *offset = body[@"offset"];
            NSString *encoded = body[@"data"];
            if (![offset isKindOfClass:NSNumber.class] || ![encoded isKindOfClass:NSString.class] ||
                offset.doubleValue < 0 || offset.doubleValue != offset.unsignedLongLongValue) {
                return Failure(400, @"分块参数无效");
            }
            if (![offset isEqualToNumber:upload[@"offset"]]) return Failure(409, @"分块位置不一致，请重新上传");
            NSData *chunk = [[NSData alloc] initWithBase64EncodedString:encoded options:0];
            if (!chunk || !chunk.length) return Failure(400, @"分块内容无效");
            NSFileHandle *file = [NSFileHandle fileHandleForWritingToURL:[NSURL fileURLWithPath:temporary] error:&error];
            BOOL written = file && [file seekToOffset:offset.unsignedLongLongValue error:&error] &&
                [file writeData:chunk error:&error];
            [file closeAndReturnError:nil];
            if (!written) {
                [files removeItemAtPath:temporary error:nil];
                [self.uploads removeObjectForKey:uploadID];
                return Failure(500, error.localizedDescription ?: @"写入分块失败");
            }
            upload[@"offset"] = @(offset.unsignedLongLongValue + chunk.length);
            return DXRemoteResponse(200, @{@"offset":upload[@"offset"]});
        }
        NSNumber *size = body[@"size"];
        if (![size isKindOfClass:NSNumber.class] || ![size isEqualToNumber:upload[@"offset"]]) return Failure(409, @"文件长度不一致，请重新上传");
        if (rename(temporary.fileSystemRepresentation, [upload[@"target"] fileSystemRepresentation]) != 0) {
            return Failure(500, [NSError errorWithDomain:NSPOSIXErrorDomain code:errno userInfo:nil].localizedDescription);
        }
        [self.uploads removeObjectForKey:uploadID];
        return DXRemoteResponse(200, @{@"saved":@YES});
    }

    NSString *identifier = body[@"project"];
    if (![identifier isKindOfClass:NSString.class] || ![[NSUUID alloc] initWithUUIDString:identifier]) {
        return Failure(400, @"请选择项目");
    }
    NSString *root = [self.projects stringByAppendingPathComponent:identifier];
    if (![files fileExistsAtPath:[root stringByAppendingPathComponent:@".buildproject"]]) return Failure(404, @"项目不存在");
    if ([action isEqual:@"files"]) {
        NSMutableArray *list = [NSMutableArray array];
        NSDirectoryEnumerator *enumerator = [files enumeratorAtPath:root];
        for (NSString *relative in enumerator) {
            NSDictionary *attributes = [files attributesOfItemAtPath:[root stringByAppendingPathComponent:relative] error:nil];
            if ([relative isEqual:@".git"] || [relative hasPrefix:@".git/"] || [attributes[NSFileType] isEqual:NSFileTypeSymbolicLink]) {
                [enumerator skipDescendants];
                continue;
            }
            if ([relative isEqual:@".buildproject"] || ![attributes[NSFileType] isEqual:NSFileTypeRegular]) continue;
            [list addObject:relative];
        }
        return DXRemoteResponse(200, @{@"files": [list sortedArrayUsingSelector:@selector(compare:)]});
    }
    if ([action isEqual:@"build"]) {
        if (PBToolchains.shared.buildRunning) return Failure(409, @"当前构建尚未结束");
        if (PBToolchains.shared.busy) return Failure(409, @"工具链正在安装，请稍后再构建");
        NSString *manifest = [root stringByAppendingPathComponent:@"MobileCompiler.json"];
        if (![files fileExistsAtPath:manifest]) {
            for (NSString *file in [files enumeratorAtPath:root]) {
                if ([@[@"xcodeproj", @"xcworkspace", @"swift"] containsObject:file.pathExtension.lowercaseString]) return Failure(400, @"此工程需要先配置 MobileCompiler.json。手机当前支持 Objective-C/C/C++ 和代码创建的 UIKit App；Swift 和完整 Xcode 工程构建尚未接入");
            }
        }
        NSDictionary *prepared = TMCPrepareImportedProject(root, @"Plugin", &error);
        if (!prepared) return Failure(400, error.localizedDescription);
        NSDictionary *configuration = [NSJSONSerialization JSONObjectWithData:[NSData dataWithContentsOfFile:manifest] options:0 error:nil];
        if (configuration[@"productType"] && ![@[@"app", @"tweak"] containsObject:configuration[@"productType"]]) return Failure(400, @"productType 应为 tweak 或 app");
        NSString *sdk = configuration[@"sdkVersion"] ?: @"16.4";
        BOOL usesCXX = NO;
        if ([sdk isEqual:@"26.0"]) {
            for (NSString *source in prepared[@"sources"]) {
                if ([@[@"cpp", @"mm", @"xm"] containsObject:source.pathExtension.lowercaseString]) {
                    usesCXX = YES;
                    break;
                }
            }
        }
        NSMutableArray<NSString *> *missing = [NSMutableArray array];
        NSDictionary *titles = @{@"support":@"构建资源", @"sdk16":@"iOS 16.4 SDK", @"sdk26":@"iOS 26.0 SDK"};
        for (NSString *required in [PBToolchains requiredPackagesForSDK:sdk usesCXX:usesCXX]) {
            if (!PBInstalledPackage(required)) [missing addObject:titles[required]];
        }
        if (missing.count) return Failure(409, [NSString stringWithFormat:@"请在手机组件库安装：%@。", [missing componentsJoinedByString:@"、"]]);
        if (![self prepareCompiler:&error]) return Failure(409, error.localizedDescription);
        NSString *copy = [NSTemporaryDirectory() stringByAppendingPathComponent:NSUUID.UUID.UUIDString];
        if (![files copyItemAtPath:root toPath:copy error:&error]) return Failure(500, error.localizedDescription);
        PBToolchains.shared.buildRunning = YES;
        NSString *buildID = NSUUID.UUID.UUIDString;
        self.job = [@{@"id":buildID, @"state": @"running", @"project": identifier, @"artifacts": @[], @"startedAt":@(NSDate.date.timeIntervalSince1970)} mutableCopy];
        self.jobs[buildID] = self.job;
        self.compiler.importedProject = copy;
        self.compiler.importedSource = nil;
        self.compiler.lastBuild = nil;
        self.compiler.buildProgress = ^(NSString *stage, double progress) {
            DXBuildService.shared.job[@"stage"] = stage ?: @"";
            DXBuildService.shared.job[@"progress"] = @(progress);
        };
        self.compiler.buildCompletion = ^(BOOL success) {
            DXBuildService *service = DXBuildService.shared;
            service.job[@"state"] = service.compiler.cancelRequested ? @"cancelled" : success ? @"succeeded" : @"failed";
            service.job[@"finishedAt"] = @(NSDate.date.timeIntervalSince1970);
            if (success) { service.job[@"progress"]=@1; service.job[@"stage"]=@"构建完成"; }
            PBToolchains.shared.buildRunning = NO;
            NSMutableArray *artifacts = [NSMutableArray array];
            for (NSString *name in [files contentsOfDirectoryAtPath:service.compiler.lastBuild error:nil]) {
                if ([@[@"deb", @"dylib", @"ipa", @"json", @"log"] containsObject:name.pathExtension]) [artifacts addObject:name];
            }
            service.job[@"artifacts"] = artifacts;
            [files removeItemAtPath:copy error:nil];
            if (service.changed) service.changed();
        };
        [self.compiler runProof];
        self.job[@"buildPath"] = self.compiler.lastBuild;
        return DXRemoteResponse(200, @{@"id":buildID, @"state": self.job[@"state"]});
    }

    NSString *relative = body[@"path"];
    if (![relative isKindOfClass:NSString.class] || !relative.length || relative.isAbsolutePath) return Failure(400, @"文件路径无效");
    NSString *target = [root stringByAppendingPathComponent:relative].stringByResolvingSymlinksInPath;
    if (![target hasPrefix:[root stringByAppendingString:@"/"]] ||
        [target isEqual:[root stringByAppendingPathComponent:@".buildproject"]]) return Failure(400, @"文件路径超出项目");
    if ([action isEqual:@"upload_begin"]) {
        if (![files createDirectoryAtPath:target.stringByDeletingLastPathComponent
            withIntermediateDirectories:YES attributes:nil error:&error]) return Failure(500, error.localizedDescription);
        NSString *uploadID = NSUUID.UUID.UUIDString;
        NSString *temporary = [NSTemporaryDirectory() stringByAppendingPathComponent:uploadID];
        if (![files createFileAtPath:temporary contents:NSData.data attributes:nil]) return Failure(500, @"无法建立上传暂存文件");
        self.uploads[uploadID] = [@{@"temporary":temporary,@"target":target,@"offset":@0} mutableCopy];
        return DXRemoteResponse(200, @{@"upload":uploadID});
    }
    if ([action isEqual:@"read"]) {
        NSString *content = [NSString stringWithContentsOfFile:target encoding:NSUTF8StringEncoding error:&error];
        return content ? DXRemoteResponse(200, @{@"content": content}) : Failure(400, @"该文件不是 UTF-8 文本，或已不存在");
    }
    if ([action isEqual:@"write"] || [action isEqual:@"upload"]) {
        NSData *data = nil;
        if ([action isEqual:@"write"] && [body[@"content"] isKindOfClass:NSString.class]) {
            data = [body[@"content"] dataUsingEncoding:NSUTF8StringEncoding];
        } else if ([action isEqual:@"upload"] && [body[@"data"] isKindOfClass:NSString.class]) {
            data = [[NSData alloc] initWithBase64EncodedString:body[@"data"] options:0];
        }
        if (!data) return Failure(400, @"文件内容无效");
        BOOL saved = [files createDirectoryAtPath:target.stringByDeletingLastPathComponent
            withIntermediateDirectories:YES attributes:nil error:&error] &&
            [data writeToFile:target options:NSDataWritingAtomic error:&error];
        return saved ? DXRemoteResponse(200, @{@"saved": @YES}) : Failure(500, error.localizedDescription);
    }
    return Failure(404, @"未知操作");
}
@end
