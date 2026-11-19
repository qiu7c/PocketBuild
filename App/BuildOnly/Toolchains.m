#import "Toolchains.h"
#import "PackagePaths.h"
#import "../ArchiveImport.h"
#import <CommonCrypto/CommonDigest.h>
#import <dlfcn.h>

NSNotificationName const PBPackagesChanged = @"PocketBuild.PackagesChanged";

static NSError *PackageError(NSString *message) {
    return [NSError errorWithDomain:@"PocketBuild.Toolchains" code:1
        userInfo:@{NSLocalizedDescriptionKey:message}];
}

@interface PBToolchains ()
@property NSArray<NSDictionary *> *catalog;
@property BOOL busy;
@property double progress;
@property NSString *message;
@property NSURLSession *session;
@property NSURLSessionTask *task;
@property NSDictionary *installing;
@property NSProgress *extraction;
@end

@implementation PBToolchains
+ (instancetype)shared {
    static PBToolchains *store;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ store = [self new]; });
    return store;
}
- (instancetype)init {
    if ((self = [super init])) {
        NSString *path = [PBPackagesDirectory() stringByAppendingPathComponent:@"catalog.plist"];
        _catalog = [NSArray arrayWithContentsOfFile:path] ?: @[];
        _message = @"请加载资源清单，选择需要的组件。";
        _session = [NSURLSession sessionWithConfiguration:NSURLSessionConfiguration.defaultSessionConfiguration
            delegate:self delegateQueue:NSOperationQueue.mainQueue];
    }
    return self;
}
- (void)publish {
    [NSNotificationCenter.defaultCenter postNotificationName:PBPackagesChanged object:self];
}
- (void)loadManifest:(NSURL *)url {
    if (self.busy || self.buildRunning) return;
    if (!url.host.length || ![@[@"https",@"http"] containsObject:url.scheme.lowercaseString]) {
        self.message = @"请填写有效的 HTTPS 或局域网 HTTP 清单地址";
        [self publish];
        return;
    }
    self.busy = YES;
    self.message = @"正在读取资源清单";
    self.progress = 0;
    [self publish];
    self.task = [self.session dataTaskWithURL:url completionHandler:^(NSData *data, NSURLResponse *response, NSError *failure) {
        NSError *error = failure;
        NSInteger statusCode = [(NSHTTPURLResponse *)response statusCode];
        if (!error && statusCode != 200) error = PackageError([NSString stringWithFormat:@"清单返回 HTTP %ld",(long)statusCode]);
        id manifest = data ? [NSJSONSerialization JSONObjectWithData:data options:0 error:&error] : nil;
        NSArray *entries = [manifest isKindOfClass:NSDictionary.class] ? manifest[@"packages"] : nil;
        NSMutableArray *resolved = [NSMutableArray array];
        NSMutableSet *identifiers = [NSMutableSet set];
        if (!error && (![entries isKindOfClass:NSArray.class] || !entries.count)) error = PackageError(@"清单需要 packages 数组");
        if (!error) for (id entry in entries) {
            if (![entry isKindOfClass:NSDictionary.class] ||
                ![@[@"support",@"sdk16",@"sdk26"] containsObject:entry[@"id"]] ||
                [identifiers containsObject:entry[@"id"]] ||
                ![entry[@"sha256"] isKindOfClass:NSString.class] ||
                [entry[@"sha256"] rangeOfString:@"^[0-9a-f]{64}$" options:NSRegularExpressionSearch].location == NSNotFound ||
                ![entry[@"url"] isKindOfClass:NSString.class] ||
                ![entry[@"title"] isKindOfClass:NSString.class]) {
                error = PackageError(@"资源清单条目无效");
                break;
            }
            NSURL *download = [NSURL URLWithString:entry[@"url"] relativeToURL:url].absoluteURL;
            if (![@[@"https", @"http"] containsObject:download.scheme.lowercaseString]) {
                error = PackageError(@"资源地址需要 HTTP 或 HTTPS");
                break;
            }
            NSMutableDictionary *item = [entry mutableCopy];
            item[@"url"] = download.absoluteString;
            [resolved addObject:item];
            [identifiers addObject:entry[@"id"]];
        }
        if (!error) {
            NSFileManager *files = NSFileManager.defaultManager;
            NSString *directory = PBPackagesDirectory();
            if (![files createDirectoryAtPath:directory withIntermediateDirectories:YES attributes:nil error:&error] ||
                ![resolved writeToFile:[directory stringByAppendingPathComponent:@"catalog.plist"] atomically:YES]) {
                if (!error) error = PackageError(@"清单保存失败");
            } else {
                self.catalog = resolved;
            }
        }
        self.busy = NO;
        self.task = nil;
        self.message = error ? error.localizedDescription : @"资源清单已更新";
        [self publish];
    }];
    [self.task resume];
}
- (NSDictionary *)status {
    NSDictionary *installed = [NSDictionary dictionaryWithContentsOfFile:
        [PBPackagesDirectory() stringByAppendingPathComponent:@"installed.plist"]] ?: @{};
    return @{@"busy":@(self.busy), @"progress":@(self.progress), @"message":self.message,
        @"catalog":self.catalog, @"installed":installed,
        @"compilerBundled":@([NSBundle.mainBundle pathForResource:@"PBCompiler" ofType:@"framework" inDirectory:@"Frameworks"] != nil),
        @"compilerLoaded":@(NSClassFromString(@"CompilerController") != Nil)};
}
- (void)install:(NSString *)identifier {
    if (self.busy || self.buildRunning) return;
    self.installing = nil;
    for (NSDictionary *item in self.catalog) if ([item[@"id"] isEqual:identifier]) self.installing = item;
    if (![self.installing[@"id"] isEqual:identifier]) {
        self.message = @"请先加载包含该组件的资源清单";
        [self publish];
        return;
    }
    self.busy = YES;
    self.progress = 0;
    self.message = [@"正在下载 " stringByAppendingString:self.installing[@"title"]];
    self.extraction = nil;
    self.task = [self.session downloadTaskWithURL:[NSURL URLWithString:self.installing[@"url"]]];
    [self.task resume];
    [self publish];
}
- (void)cancel {
    [self.task cancel];
    [self.extraction cancel];
}
- (void)URLSession:(NSURLSession *)session downloadTask:(NSURLSessionDownloadTask *)task
    didWriteData:(int64_t)bytesWritten totalBytesWritten:(int64_t)written totalBytesExpectedToWrite:(int64_t)expected {
    self.progress = expected > 0 ? (double)written / expected : 0;
    [self publish];
}
- (void)URLSession:(NSURLSession *)session downloadTask:(NSURLSessionDownloadTask *)task
    didFinishDownloadingToURL:(NSURL *)location {
    NSString *archive = [NSTemporaryDirectory() stringByAppendingPathComponent:NSUUID.UUID.UUIDString];
    NSError *error = nil;
    NSInteger status = [(NSHTTPURLResponse *)task.response statusCode];
    if (status != 200) error = PackageError([NSString stringWithFormat:@"下载返回 HTTP %ld",(long)status]);
    if (!error) [NSFileManager.defaultManager moveItemAtURL:location toURL:[NSURL fileURLWithPath:archive] error:&error];
    if (error) {
        self.busy = NO;
        self.message = error.localizedDescription;
        self.task = nil;
        [self publish];
        return;
    }
    self.message = @"正在校验和解压";
    self.task = nil;
    self.extraction = [NSProgress progressWithTotalUnitCount:1];
    NSDictionary *item = self.installing;
    NSProgress *cancellation = self.extraction;
    [self publish];
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED,0), ^{
        __block NSError *failure = nil;
        NSInputStream *stream = [NSInputStream inputStreamWithFileAtPath:archive];
        [stream open];
        CC_SHA256_CTX digest;
        CC_SHA256_Init(&digest);
        uint8_t buffer[65536];
        NSInteger count;
        while ((count = [stream read:buffer maxLength:sizeof(buffer)]) > 0 && !cancellation.cancelled) {
            CC_SHA256_Update(&digest, buffer, (CC_LONG)count);
        }
        [stream close];
        unsigned char hash[CC_SHA256_DIGEST_LENGTH];
        CC_SHA256_Final(hash,&digest);
        NSMutableString *actual = [NSMutableString string];
        for (NSUInteger i=0; i<sizeof(hash); i++) [actual appendFormat:@"%02x",hash[i]];
        if (count < 0 || cancellation.cancelled || ![actual isEqual:item[@"sha256"]]) failure = PackageError(@"资源校验失败或安装已取消");
        NSString *parent = [PBPackagesDirectory() stringByAppendingPathComponent:item[@"id"]];
        NSString *destination = [parent stringByAppendingPathComponent:item[@"sha256"]];
        NSString *staging = [parent stringByAppendingPathComponent:NSUUID.UUID.UUIDString];
        NSFileManager *files = NSFileManager.defaultManager;
        if (!failure) [files createDirectoryAtPath:parent withIntermediateDirectories:YES attributes:nil error:&failure];
        if (!failure && !TMCExtractArchive([NSURL fileURLWithPath:archive], [NSURL fileURLWithPath:staging],
            nil, cancellation, nil, &failure)) {
            if (!failure) failure = PackageError(@"资源解压失败");
        }
        if (!failure) {
            NSString *identifier = item[@"id"];
            NSString *required = [identifier isEqual:@"support"] ? @"logos/bin/logos.pl" : @"SDKSettings.plist";
            if (![files fileExistsAtPath:[staging stringByAppendingPathComponent:required]]) failure = PackageError(@"资源包目录结构无效");
            if ([identifier hasPrefix:@"sdk"]) {
                NSDictionary *metadata = [NSDictionary dictionaryWithContentsOfFile:[staging stringByAppendingPathComponent:@"SDKSettings.plist"]];
                NSString *version = [identifier isEqual:@"sdk16"] ? @"16.4" : @"26.0";
                if (![metadata[@"Version"] isEqual:version]) failure = PackageError(@"SDK 版本与资源清单不一致");
            }
        }
        if (!failure && cancellation.cancelled) failure = PackageError(@"安装已取消");
        if (!failure) {
            if ([files fileExistsAtPath:destination]) [files removeItemAtPath:staging error:nil];
            else [files moveItemAtPath:staging toPath:destination error:&failure];
        }
        [files removeItemAtPath:archive error:nil];
        [files removeItemAtPath:staging error:nil];
        dispatch_async(dispatch_get_main_queue(), ^{
            if (!failure) {
                NSString *registry = [PBPackagesDirectory() stringByAppendingPathComponent:@"installed.plist"];
                NSMutableDictionary *installed = [[NSDictionary dictionaryWithContentsOfFile:registry] mutableCopy] ?: [NSMutableDictionary dictionary];
                installed[item[@"id"]] = @{@"path":[item[@"id"] stringByAppendingPathComponent:item[@"sha256"]],
                    @"sha256":item[@"sha256"],@"title":item[@"title"]};
                if (![installed writeToFile:registry atomically:YES]) failure = PackageError(@"安装记录保存失败");
            }
            self.busy = NO;
            self.extraction = nil;
            self.message = failure ? failure.localizedDescription : [item[@"title"] stringByAppendingString:@"已安装"];
            [self publish];
        });
    });
}
- (void)URLSession:(NSURLSession *)session task:(NSURLSessionTask *)task didCompleteWithError:(NSError *)error {
    if (!error || task != self.task) return;
    self.task = nil;
    self.busy = NO;
    self.message = error.localizedDescription;
    [self publish];
}
- (BOOL)remove:(NSString *)identifier error:(NSError **)error {
    if (self.busy || self.buildRunning) {
        if (error) *error = PackageError(@"组件正在使用，请在任务结束后移除");
        return NO;
    }
    NSString *registry = [PBPackagesDirectory() stringByAppendingPathComponent:@"installed.plist"];
    NSMutableDictionary *installed = [[NSDictionary dictionaryWithContentsOfFile:registry] mutableCopy] ?: [NSMutableDictionary dictionary];
    NSString *path = PBInstalledPackage(identifier);
    [installed removeObjectForKey:identifier];
    if (![installed writeToFile:registry atomically:YES]) {
        if (error) *error = PackageError(@"安装记录保存失败");
        return NO;
    }
    if (path) [NSFileManager.defaultManager removeItemAtPath:path error:nil];
    [self publish];
    return YES;
}
- (BOOL)loadCompiler:(NSError **)error {
    if (NSClassFromString(@"CompilerController")) return YES;
    NSString *root = [NSBundle.mainBundle pathForResource:@"PBCompiler" ofType:@"framework" inDirectory:@"Frameworks"];
    if (!root) {
        if (error) *error = PackageError(@"App 中缺少编译核心，请重新安装 PocketBuild。");
        return NO;
    }
    const char *failure = NULL;
    void *handle = dlopen([[root stringByAppendingPathComponent:@"PBCompiler"] fileSystemRepresentation],RTLD_NOW | RTLD_GLOBAL);
    if (!handle) failure = dlerror();
    if (!handle || !NSClassFromString(@"CompilerController")) {
        NSString *details = failure ? @(failure) : @"CompilerController 类未加载";
        if (error) *error = PackageError([@"编译核心加载失败，请确认安装包内的所有框架均已正确签名。\n" stringByAppendingString:details]);
        return NO;
    }
    return YES;
}
@end
