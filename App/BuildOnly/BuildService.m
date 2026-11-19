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

@interface DXBuildService ()
@property (nonatomic) DXRemoteHTTP *http;
@property (nonatomic) CompilerController *compiler;
@property (nonatomic) NSString *state, *origin, *code, *projects;
@property (nonatomic) NSMutableDictionary *job;
@property (nonatomic) NSMutableDictionary<NSString *, NSMutableDictionary *> *jobs;
@property (nonatomic) NSMutableDictionary<NSString *, NSMutableDictionary *> *uploads;
@end

@implementation DXBuildService

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
            if (!running) {
                weak.origin = nil;
                weak.code = nil;
                TFScreenAwakeSet(@"remote-build", NO);
            }
            if (weak.changed) weak.changed();
        };
    }
    return self;
}

- (void)startAddress:(NSString *)address port:(NSUInteger)port {
    [self stop];
    unsigned char bytes[16];
    if (SecRandomCopyBytes(kSecRandomDefault, sizeof(bytes), bytes) != errSecSuccess) {
        self.state = @"无法生成连接码";
        if (self.changed) self.changed();
        return;
    }
    NSMutableString *code = [NSMutableString string];
    for (NSUInteger i = 0; i < sizeof(bytes); i++) [code appendFormat:@"%02x", bytes[i]];
    NSError *error = nil;
    if (![self.http startAddress:address port:port error:&error]) {
        self.state = error.localizedDescription;
    } else {
        self.code = code;
        self.origin = self.http.origin;
        self.state = @"正在启动";
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
        if ([self.job[@"state"] isEqual:@"running"]) return Failure(409, @"当前构建尚未结束");
        if (PBToolchains.shared.busy) return Failure(409, @"工具链正在安装，请稍后再构建");
        if (![PBToolchains.shared loadCompiler:&error]) return Failure(409, error.localizedDescription);
        if (!PBInstalledPackage(@"support")) return Failure(409, @"请在手机工具链管理中安装构建资源");
        if (!self.compiler) {
            Class controller = NSClassFromString(@"CompilerController");
            self.compiler = [controller new];
            [self.compiler loadViewIfNeeded];
        }
        NSString *manifest = [root stringByAppendingPathComponent:@"MobileCompiler.json"];
        if (![files fileExistsAtPath:manifest]) {
            for (NSString *file in [files enumeratorAtPath:root]) {
                if ([@[@"xcodeproj", @"xcworkspace", @"swift"] containsObject:file.pathExtension.lowercaseString]) return Failure(400, @"此工程需要先配置 MobileCompiler.json。手机当前支持 Objective-C/C/C++ 和代码创建的 UIKit App；Swift 和完整 Xcode 工程构建尚未接入");
            }
        }
        if (!TMCPrepareImportedProject(root, @"Plugin", &error)) return Failure(400, error.localizedDescription);
        NSDictionary *configuration = [NSJSONSerialization JSONObjectWithData:[NSData dataWithContentsOfFile:manifest] options:0 error:nil];
        if (configuration[@"productType"] && ![@[@"app", @"tweak"] containsObject:configuration[@"productType"]]) return Failure(400, @"productType 应为 tweak 或 app");
        NSString *sdk = configuration[@"sdkVersion"] ?: @"16.4";
        NSString *sdkID = [sdk isEqual:@"26.0"] ? @"sdk26" : @"sdk16";
        if (!PBInstalledPackage(sdkID)) return Failure(409, [NSString stringWithFormat:@"请先安装 iOS %@ SDK", sdk]);
        NSString *copy = [NSTemporaryDirectory() stringByAppendingPathComponent:NSUUID.UUID.UUIDString];
        if (![files copyItemAtPath:root toPath:copy error:&error]) return Failure(500, error.localizedDescription);
        PBToolchains.shared.buildRunning = YES;
        NSString *buildID = NSUUID.UUID.UUIDString;
        self.job = [@{@"id":buildID, @"state": @"running", @"project": identifier, @"artifacts": @[]} mutableCopy];
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
