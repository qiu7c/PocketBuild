#import "BuildService.h"
#import "../Remote/DXRemoteHTTP.h"
#import "../Remote/DXRemoteNetwork.h"
#import "../CompilerController.h"
#import "../ArchiveImport.h"
#import "../OutputNaming.h"
#import "../SDKResources.h"
#import "ScreenAwake.h"
#import "Toolchains.h"
#import "PackagePaths.h"
#import "ProjectRecords.h"
#import "../DocumentPresentation.h"
#import <ifaddrs.h>
#import <net/if.h>
#import <errno.h>
#import <stdio.h>
#import <Security/Security.h>

NSNotificationName const PBTrialChanged = @"PocketBuild.TrialChanged";
NSNotificationName const PBBuildChanged = @"PocketBuild.BuildChanged";
NSNotificationName const PBConnectionChanged = @"PocketBuild.ConnectionChanged";

static NSError *ProjectError(NSInteger code, NSString *message) {
    return [NSError errorWithDomain:@"PocketBuild.Project" code:code
        userInfo:@{NSLocalizedDescriptionKey:message}];
}

static NSString *ProjectFile(NSString *root, NSString *relative) {
    if (!root || ![relative isKindOfClass:NSString.class] || !relative.length || relative.isAbsolutePath) return nil;
    NSString *base = root.stringByResolvingSymlinksInPath;
    NSString *target = [base stringByAppendingPathComponent:relative].stringByStandardizingPath.stringByResolvingSymlinksInPath;
    if (![target hasPrefix:[base stringByAppendingString:@"/"]] ||
        [target isEqual:[base stringByAppendingPathComponent:@".buildproject"]]) return nil;
    return target;
}

static NSDictionary *InspectBuildProject(NSString *root, NSString *name, BOOL hasManifest, BOOL prepare, NSError **error) {
    if (!hasManifest) {
        for (NSString *file in [NSFileManager.defaultManager enumeratorAtPath:root]) {
            if (![@[@"xcodeproj", @"xcworkspace", @"swift"] containsObject:file.pathExtension.lowercaseString]) continue;
            if (error) *error = ProjectError(400, @"请为受支持的 C/C++、Objective-C 或 UIKit 工程添加 MobileCompiler.json。");
            return nil;
        }
    }
    return prepare ? TMCPrepareImportedProject(root, name, error) : TMCInspectImportedProject(root, name, error);
}

static NSDictionary *BuildSummary(NSDictionary *config, NSArray<NSString *> *sources) {
    NSString *product = config[@"productType"] ?: @"tweak";
    if (![@[@"app", @"tweak"] containsObject:product]) {
        return @{@"issue":@{@"kind":@"configuration", @"message":@"productType 应为 tweak 或 app。", @"file":@"MobileCompiler.json"}};
    }
    NSUserDefaults *defaults = NSUserDefaults.standardUserDefaults;
    NSError *error = nil;
    NSDictionary *settings = TMCSDKBuildSettings(config, defaults, &error);
    if (!settings) return @{@"issue":@{@"kind":@"configuration", @"message":error.localizedDescription, @"file":@"MobileCompiler.json"}};
    NSString *sdk = settings[@"sdkVersion"];
    BOOL usesCXX = NO;
    if ([sdk isEqual:@"26.0"]) {
        for (NSString *source in sources) {
            if ([@[@"cpp", @"mm", @"xm"] containsObject:source.pathExtension.lowercaseString]) { usesCXX = YES; break; }
        }
    }
    NSDictionary *options = TMCEffectiveBuildOptions(config, defaults);
    NSMutableArray *outputs = [NSMutableArray array];
    if ([product isEqual:@"app"]) {
        [outputs addObject:@"IPA"];
    } else {
        if ([options[@"exportDylib"] boolValue]) [outputs addObject:@"dylib"];
        if ([options[@"package"] boolValue]) {
            NSDictionary *names = @{@"rootless":@"无根 DEB", @"rootful":@"有根 DEB", @"roothide":@"隐根 DEB"};
            for (NSString *scheme in options[@"packageSchemes"]) [outputs addObject:names[scheme]];
        }
    }
    NSMutableDictionary *summary = [@{@"productType":product, @"sdk":sdk, @"minimum":settings[@"deploymentTarget"],
        @"cpu":config[@"cpuArchitecture"] ?: @"arm64", @"outputs":outputs} mutableCopy];
    NSDictionary *labels = @{@"support":@"构建资源", @"sdk16":@"iOS 16.4 SDK", @"sdk26":@"iOS 26.0 SDK"};
    NSMutableArray *missing = [NSMutableArray array];
    for (NSString *required in [PBToolchains requiredPackagesForSDK:sdk usesCXX:usesCXX]) {
        if (!PBInstalledPackage(required)) [missing addObject:@{@"id":required, @"title":labels[required]}];
    }
    if (missing.count) {
        summary[@"issue"] = @{@"kind":@"components", @"components":missing, @"sdk":sdk, @"usesCXX":@(usesCXX),
            @"message":[@"缺少 " stringByAppendingString:[[missing valueForKey:@"title"] componentsJoinedByString:@"、"]]};
    }
    return summary;
}

static NSArray<NSString *> *ProjectFiles(NSString *root) {
    NSMutableArray *list = [NSMutableArray array];
    NSDirectoryEnumerator *enumerator = [NSFileManager.defaultManager enumeratorAtPath:root];
    for (NSString *relative in enumerator) {
        NSString *type = enumerator.fileAttributes[NSFileType];
        if ([relative isEqual:@".git"] || [relative hasPrefix:@".git/"] || [type isEqual:NSFileTypeSymbolicLink]) {
            [enumerator skipDescendants];
            continue;
        }
        if (![relative isEqual:@".buildproject"] && [type isEqual:NSFileTypeRegular]) [list addObject:relative];
    }
    return [list sortedArrayUsingSelector:@selector(compare:)];
}

@interface DXBuildService ()
@property (nonatomic) DXRemoteHTTP *http;
@property (nonatomic) CompilerController *compiler;
@property (nonatomic) NSString *state, *origin, *code, *projects;
@property (nonatomic) NSMutableDictionary *job;
@property (nonatomic) NSMutableDictionary<NSString *, NSMutableDictionary *> *jobs;
@property (nonatomic) NSMutableDictionary<NSString *, NSMutableDictionary *> *uploads;
@property (nonatomic) BOOL activeCodeIsFixed;
@property (nonatomic) NSDate *startedAt, *lastRequestAt;
@property (nonatomic) NSDate *lastHTTPAt, *lastRejectedAt;
@property (nonatomic) NSString *lastPeer, *requestedAddress;
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

- (NSDictionary *)connectionDiagnostics {
    return @{@"listener":self.state, @"address":self.origin ?: self.requestedAddress ?: @"",
        @"ready":@(self.startedAt != nil), @"httpAt":@(self.lastHTTPAt.timeIntervalSince1970),
        @"authorizedAt":@(self.lastRequestAt.timeIntervalSince1970),
        @"rejectedAt":@(self.lastRejectedAt.timeIntervalSince1970), @"peer":self.lastPeer ?: @""};
}

- (NSArray<NSDictionary *> *)recordedBuilds {
    return [self.jobs.allValues sortedArrayUsingDescriptors:@[[NSSortDescriptor sortDescriptorWithKey:@"startedAt" ascending:NO]]];
}

- (NSDictionary *)recordedBuild:(NSString *)identifier {
    return self.jobs[identifier];
}

- (NSArray<NSDictionary *> *)projectList {
    NSMutableDictionary *recent = [NSMutableDictionary dictionary];
    for (NSDictionary *job in self.recordedBuilds) {
        NSString *identifier = job[@"project"];
        if (identifier && !recent[identifier]) recent[identifier] = job[@"finishedAt"] ?: job[@"startedAt"];
    }
    NSMutableArray<NSDictionary *> *projects = [NSMutableArray array];
    for (NSString *identifier in [NSFileManager.defaultManager contentsOfDirectoryAtPath:self.projects error:nil]) {
        NSString *root = [self projectRoot:identifier];
        if (!root) continue;
        NSDictionary *metadata = [NSDictionary dictionaryWithContentsOfFile:[root stringByAppendingPathComponent:@".buildproject"]];
        if (!metadata) continue;
        NSDictionary *manifest = TMCDocumentJSON([root stringByAppendingPathComponent:@"MobileCompiler.json"]);
        NSString *product = manifest.count ? ([manifest[@"productType"] isEqual:@"app"] ? @"app" : @"tweak") : (metadata[@"productType"] ?: @"tweak");
        [projects addObject:@{@"id":identifier, @"name":metadata[@"name"] ?: identifier,
            @"productType":product, @"lastBuildAt":recent[identifier] ?: @0}];
    }
    return [projects sortedArrayUsingDescriptors:@[[NSSortDescriptor sortDescriptorWithKey:@"lastBuildAt" ascending:NO],
        [NSSortDescriptor sortDescriptorWithKey:@"name" ascending:YES selector:@selector(localizedStandardCompare:)]]];
}

- (NSString *)projectRoot:(NSString *)identifier {
    if (!TMCDocumentUUID(identifier)) return nil;
    NSString *root = [self.projects stringByAppendingPathComponent:identifier];
    return TMCRegularDocument(root, YES) && TMCRegularDocument([root stringByAppendingPathComponent:@".buildproject"], NO) ? root : nil;
}

- (NSDictionary *)projectDetails:(NSString *)identifier {
    NSString *root = [self projectRoot:identifier];
    if (!root) return nil;
    NSDictionary *metadata = [NSDictionary dictionaryWithContentsOfFile:[root stringByAppendingPathComponent:@".buildproject"]];
    NSError *error = nil;
    BOOL hasManifest = TMCRegularDocument(ProjectFile(root, @"MobileCompiler.json"), NO);
    NSDictionary *inspection = InspectBuildProject(root, metadata[@"name"], hasManifest, NO, &error);
    if (!inspection) {
        NSMutableDictionary *issue = [@{@"kind":@"configuration", @"message":error.localizedDescription ?: @"无法读取项目配置。"} mutableCopy];
        if (hasManifest) issue[@"file"] = @"MobileCompiler.json";
        return @{@"issue":issue, @"hasManifest":@(hasManifest)};
    }
    NSMutableDictionary *config = [inspection[@"configuration"] mutableCopy];
    if ([inspection[@"generatedManifest"] boolValue] && [metadata[@"productType"] isEqual:@"app"]) config[@"productType"] = @"app";
    NSMutableDictionary *details = [BuildSummary(config, inspection[@"sources"]) mutableCopy];
    details[@"hasManifest"] = @(hasManifest);
    return details;
}

- (NSArray<NSString *> *)sourceFilesForProject:(NSString *)identifier {
    NSString *root = [self projectRoot:identifier];
    return root ? ProjectFiles(root) : @[];
}

- (NSString *)sourceForProject:(NSString *)identifier path:(NSString *)path error:(NSError **)error {
    NSString *file = ProjectFile([self projectRoot:identifier], path);
    if (!TMCRegularDocument(file, NO)) {
        if (error) *error = ProjectError(404, @"源码文件不存在。");
        return nil;
    }
    NSString *text = [NSString stringWithContentsOfFile:file encoding:NSUTF8StringEncoding error:nil];
    if (!text && error) *error = ProjectError(400, @"该文件无法作为 UTF-8 文本打开。");
    return text;
}

- (BOOL)saveSource:(NSString *)text forProject:(NSString *)identifier path:(NSString *)path expected:(NSString *)original error:(NSError **)error {
    NSString *file = ProjectFile([self projectRoot:identifier], path);
    NSString *current = TMCRegularDocument(file, NO) ? [NSString stringWithContentsOfFile:file encoding:NSUTF8StringEncoding error:nil] : nil;
    if (![current isEqualToString:original]) {
        if (error) *error = ProjectError(409, @"文件已在另一端改动或移除。可先复制本次修改，再重新打开最新源码。");
        return NO;
    }
    if (![text writeToFile:file atomically:YES encoding:NSUTF8StringEncoding error:error]) return NO;
    [NSNotificationCenter.defaultCenter postNotificationName:PBBuildChanged object:self];
    return YES;
}

- (NSDictionary *)diagnosticSourceForBuild:(NSString *)identifier error:(NSError **)error {
    NSDictionary *job = [self recordedBuild:identifier];
    NSDictionary *issue = job[@"issue"] ?: (job[@"buildPath"] ? PBBuildIssue(job[@"buildPath"]) : nil);
    NSString *relative = issue[@"file"];
    NSString *file = ProjectFile([job[@"buildPath"] stringByAppendingPathComponent:@"snapshot"], relative);
    NSString *snapshot = TMCRegularDocument(file, NO) ? [NSString stringWithContentsOfFile:file encoding:NSUTF8StringEncoding error:nil] : nil;
    if (!snapshot) {
        if (error) *error = ProjectError(404, @"该错误对应的源码快照不可用，可打开当前源码或查看完整日志。");
        return nil;
    }
    NSString *current = [self sourceForProject:job[@"project"] path:relative error:nil];
    return @{@"path":relative, @"text":snapshot, @"snapshot":@(![snapshot isEqualToString:current]),
        @"currentAvailable":@(current != nil), @"line":issue[@"line"] ?: @1, @"column":issue[@"column"] ?: @0};
}

- (BOOL)renameProject:(NSString *)identifier name:(NSString *)name error:(NSError **)error {
    NSString *root = [self projectRoot:identifier];
    NSString *trimmed = [name isKindOfClass:NSString.class] ?
        [name stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet] : nil;
    if (!root || !trimmed.length || trimmed.length > 120) {
        if (error) *error = ProjectError(root ? 400 : 404, root ? @"项目名需要 1–120 个字符。" : @"项目不存在。");
        return NO;
    }
    NSString *metadataPath = [root stringByAppendingPathComponent:@".buildproject"];
    NSMutableDictionary *metadata = [[NSDictionary dictionaryWithContentsOfFile:metadataPath] mutableCopy];
    metadata[@"name"] = trimmed;
    if (![metadata writeToURL:[NSURL fileURLWithPath:metadataPath] error:error]) return NO;
    [NSNotificationCenter.defaultCenter postNotificationName:PBBuildChanged object:self];
    return YES;
}

- (BOOL)deleteProject:(NSString *)identifier error:(NSError **)error {
    NSString *root = [self projectRoot:identifier];
    if (!root) {
        if (error) *error = ProjectError(404, @"项目不存在。");
        return NO;
    }
    if ([self.job[@"project"] isEqual:identifier] && [self.job[@"state"] isEqual:@"running"]) {
        if (error) *error = ProjectError(409, @"请等该项目的构建结束。");
        return NO;
    }
    if (![NSFileManager.defaultManager removeItemAtPath:root error:error]) return NO;
    [NSNotificationCenter.defaultCenter postNotificationName:PBBuildChanged object:self];
    return YES;
}

- (BOOL)deleteBuild:(NSString *)identifier error:(NSError **)error {
    NSDictionary *job = [self recordedBuild:identifier];
    if (!job) {
        if (error) *error = ProjectError(404, @"构建记录不存在。");
        return NO;
    }
    if ([job[@"state"] isEqual:@"running"]) {
        if (error) *error = ProjectError(409, @"请等这次构建结束。");
        return NO;
    }
    NSString *directory = job[@"buildPath"];
    if (TMCRegularDocument(directory, YES) && ![NSFileManager.defaultManager removeItemAtPath:directory error:error]) return NO;
    [self discardBuildRecordsAtPaths:@[directory]];
    return YES;
}

- (BOOL)assignBuild:(NSString *)buildID toProject:(NSString *)identifier error:(NSError **)error {
    NSString *root = [self projectRoot:identifier];
    NSMutableDictionary *job = self.jobs[buildID];
    if (!root || !job || [self projectRoot:job[@"project"]]) {
        if (error) *error = ProjectError(409, @"请选择一个存在的项目和一条未归档记录。");
        return NO;
    }
    NSMutableDictionary *updated = [job mutableCopy];
    updated[@"project"] = identifier;
    if (!PBWriteBuildJob(updated, error)) return NO;
    [job addEntriesFromDictionary:updated];
    [NSNotificationCenter.defaultCenter postNotificationName:PBBuildChanged object:self];
    return YES;
}

- (BOOL)cleanOldBuildsForProject:(NSString *)identifier error:(NSError **)error {
    if (PBToolchains.shared.buildRunning) {
        if (error) *error = ProjectError(409, @"请等当前构建结束。");
        return NO;
    }
    NSArray *jobs = [self.recordedBuilds filteredArrayUsingPredicate:
        [NSPredicate predicateWithFormat:@"project == %@", identifier]];
    NSMutableArray *removedPaths = [NSMutableArray array];
    BOOL success = YES;
    NSFileManager *files = NSFileManager.defaultManager;
    for (NSDictionary *job in PBJobsToClean(jobs)) {
        NSString *path = job[@"buildPath"];
        if (!TMCRegularDocument(path, YES)) { [removedPaths addObject:path]; continue; }
        NSString *name = TMCDocumentJSON([path stringByAppendingPathComponent:@".dylix-published-name.json"])[@"name"];
        NSString *exports = [PBDocumentsDirectory() stringByAppendingPathComponent:@"构建产物"];
        if (name.length && [name isEqual:name.lastPathComponent] && ![name hasPrefix:@"."] && TMCRegularDocument(exports, YES)) {
            NSString *folder = [exports stringByAppendingPathComponent:name];
            if (TMCRegularDocument(folder, YES)) {
                NSArray *published = [PBBuildArtifacts(path) filteredArrayUsingPredicate:
                    [NSPredicate predicateWithFormat:@"self ENDSWITH[c] '.deb' OR self ENDSWITH[c] '.dylib'"]];
                for (NSString *exported in [published arrayByAddingObjectsFromArray:@[@"构建日志.txt", @"构建报告.json"]]) {
                    NSString *copy = [folder stringByAppendingPathComponent:exported];
                    if (TMCRegularDocument(copy, NO) && ![files removeItemAtPath:copy error:error]) { success = NO; break; }
                }
                if (!success) break;
                if ([files contentsOfDirectoryAtPath:folder error:nil].count == 0) [files removeItemAtPath:folder error:nil];
            }
        }
        if (![files removeItemAtPath:path error:error]) { success = NO; break; }
        [removedPaths addObject:path];
    }
    [self discardBuildRecordsAtPaths:removedPaths];
    return success;
}

- (BOOL)prepareCompiler:(NSError **)error {
    if (self.compiler) return YES;
    if (![PBToolchains.shared loadCompiler:error]) return NO;
    Class controller = NSClassFromString(@"CompilerController");
    self.compiler = [controller new];
    [self.compiler loadViewIfNeeded];
    return YES;
}

- (NSDictionary *)startProjectBuild:(NSString *)identifier error:(NSError **)error {
    PBToolchains *store = PBToolchains.shared;
    if (store.buildRunning || store.busy) {
        if (error) *error = ProjectError(409, store.buildRunning ? @"当前构建尚未结束。" : @"组件正在安装。");
        return nil;
    }
    NSString *root = [self projectRoot:identifier];
    if (!root) {
        if (error) *error = ProjectError(404, @"项目不存在。");
        return nil;
    }

    NSFileManager *files = NSFileManager.defaultManager;
    NSString *buildID = NSUUID.UUID.UUIDString;
    NSString *directory = [PBDocumentsDirectory() stringByAppendingPathComponent:[@"Build-" stringByAppendingString:buildID]];
    if (![files createDirectoryAtPath:directory withIntermediateDirectories:NO attributes:nil error:error]) return nil;
    TMCDocumentHide(directory);
    NSDictionary *metadata = [NSDictionary dictionaryWithContentsOfFile:[root stringByAppendingPathComponent:@".buildproject"]];
    NSMutableDictionary *job = [@{@"id":buildID, @"project":identifier, @"projectName":metadata[@"name"] ?: identifier,
        @"state":@"running", @"buildPath":directory, @"artifacts":@[], @"startedAt":@(NSDate.date.timeIntervalSince1970)} mutableCopy];
    if (!PBWriteBuildJob(job, error)) {
        [files removeItemAtPath:directory error:nil];
        return nil;
    }
    self.job = job;
    self.jobs[buildID] = job;
    NSString *snapshot = [directory stringByAppendingPathComponent:@"snapshot"];
    NSError *failure = nil;
    NSDictionary *issue = nil;

    if (![files copyItemAtPath:root toPath:snapshot error:&failure]) {
        [files removeItemAtPath:snapshot error:nil];
        issue = @{@"kind":@"storage", @"message":failure.localizedDescription ?: @"无法保存源码快照。"};
    } else {
        NSString *manifest = [snapshot stringByAppendingPathComponent:@"MobileCompiler.json"];
        BOOL hasManifest = [files fileExistsAtPath:manifest];
        NSDictionary *prepared = InspectBuildProject(snapshot, job[@"projectName"], hasManifest, YES, &failure);
        if (!prepared) {
            NSMutableDictionary *problem = [@{@"kind":@"configuration", @"message":failure.localizedDescription ?: @"工程配置无法读取。"} mutableCopy];
            if (hasManifest) problem[@"file"] = @"MobileCompiler.json";
            issue = problem;
        }
        if (!issue) {
            NSMutableDictionary *config = [prepared[@"configuration"] mutableCopy];
            if (!hasManifest && [metadata[@"productType"] isEqual:@"app"]) {
                config[@"productType"] = @"app";
                config[@"productName"] = @"ImportedApp";
                config[@"bundleIdentifier"] = [@"local.pocketbuild.app" stringByAppendingString:[identifier substringToIndex:8].lowercaseString];
                config[@"package"] = @NO;
                NSData *data = [NSJSONSerialization dataWithJSONObject:config options:0 error:&failure];
                if (!data || ![data writeToFile:manifest options:NSDataWritingAtomic error:&failure]) {
                    issue = @{@"kind":@"storage", @"message":failure.localizedDescription ?: @"无法写入构建配置。"};
                }
            }
            if (!issue) {
                NSDictionary *summary = BuildSummary(config, prepared[@"sources"]);
                issue = summary[@"issue"];
                job[@"productType"] = summary[@"productType"];
                job[@"sdk"] = summary[@"sdk"];
                job[@"cpu"] = summary[@"cpu"];
            }
            if (!hasManifest && (![issue[@"kind"] isEqual:@"storage"])) {
                NSString *projectManifest = [root stringByAppendingPathComponent:@"MobileCompiler.json"];
                if (![files fileExistsAtPath:projectManifest]) {
                    [[NSData dataWithContentsOfFile:manifest] writeToFile:projectManifest options:NSDataWritingAtomic error:nil];
                }
            }
        }
    }
    if (!issue && ![self prepareCompiler:&failure]) {
        issue = @{@"kind":@"compiler", @"message":failure.localizedDescription ?: @"编译核心无法启动。"};
    }
    if (issue) {
        job[@"state"] = @"failed";
        job[@"issue"] = issue;
        job[@"finishedAt"] = @(NSDate.date.timeIntervalSince1970);
        PBWriteBuildJob(job, nil);
        if (self.changed) self.changed();
        [NSNotificationCenter.defaultCenter postNotificationName:PBBuildChanged object:self];
        return job;
    }

    store.buildRunning = YES;
    self.compiler.projectBuildDirectory = directory;
    self.compiler.importedProject = snapshot;
    self.compiler.importedSource = nil;
    self.compiler.lastBuild = nil;
    self.compiler.buildProgress = ^(NSString *stage, double progress) {
        job[@"stage"] = stage ?: @"";
        job[@"progress"] = @(progress);
        [NSNotificationCenter.defaultCenter postNotificationName:PBBuildChanged object:nil];
    };
    __weak typeof(self) weak = self;
    self.compiler.buildCompletion = ^(BOOL success) {
        DXBuildService *service = weak;
        BOOL cancelled = service.compiler.cancelRequested;
        job[@"state"] = cancelled ? @"cancelled" : success ? @"succeeded" : @"failed";
        job[@"finishedAt"] = @(NSDate.date.timeIntervalSince1970);
        job[@"artifacts"] = PBBuildArtifacts(directory);
        if (success && !cancelled) {
            job[@"progress"] = @1;
            job[@"stage"] = @"构建完成";
        } else if (!cancelled) {
            job[@"issue"] = PBBuildIssue(directory);
        }
        PBWriteBuildJob(job, nil);
        service.compiler.projectBuildDirectory = nil;
        service.compiler.importedProject = nil;
        service.compiler.buildProgress = nil;
        service.compiler.buildCompletion = nil;
        store.buildRunning = NO;
        if (service.changed) service.changed();
        [NSNotificationCenter.defaultCenter postNotificationName:PBBuildChanged object:service];
    };
    [self.compiler runProof];
    [NSNotificationCenter.defaultCenter postNotificationName:PBBuildChanged object:self];
    return job;
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

- (void)cancelBuild {
    if ([self.job[@"state"] isEqual:@"running"]) self.compiler.cancelRequested = YES;
}

- (void)discardBuildRecordsAtPaths:(NSArray<NSString *> *)paths {
    for (NSString *identifier in self.jobs.allKeys) {
        NSDictionary *job = self.jobs[identifier];
        if (![paths containsObject:job[@"buildPath"] ?: @""]) continue;
        if (job == self.job) self.job = nil;
        [self.jobs removeObjectForKey:identifier];
    }
    if (!self.job) self.job = (NSMutableDictionary *)self.recordedBuilds.firstObject;
    if (self.changed) self.changed();
    [NSNotificationCenter.defaultCenter postNotificationName:PBBuildChanged object:self];
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
        NSString *documents = PBDocumentsDirectory();
        _projects = [documents stringByAppendingPathComponent:@"Projects"];
        [NSFileManager.defaultManager createDirectoryAtPath:_projects withIntermediateDirectories:YES attributes:nil error:nil];
        for (NSString *path in PBStoredBuildDirectories()) {
            NSDictionary *record = PBReadBuildJob(path);
            if (record[@"id"]) _jobs[record[@"id"]] = [record mutableCopy];
        }
        _job = (NSMutableDictionary *)self.recordedBuilds.firstObject;
        _http = [[DXRemoteHTTP alloc] initWithQueue:dispatch_get_main_queue()];
        __weak typeof(self) weak = self;
        _http.handler = ^NSDictionary *(NSDictionary *request) {
            return [weak handle:request];
        };
        _http.stateChanged = ^(NSString *state) {
            BOOL running = [state isEqual:@"running"];
            NSError *error = weak.http.listenerError;
            weak.state = running ? @"运行中" : error ?
                [NSString stringWithFormat:@"监听失败 · %@ (%ld)", error.domain, (long)error.code] :
                @"监听失败，请检查地址和端口";
            if ([error.domain isEqual:NSPOSIXErrorDomain]) {
                if (error.code == EADDRINUSE) weak.state = @"监听失败：端口已占用";
                else if (error.code == EADDRNOTAVAIL) weak.state = @"监听失败：手机当前没有这个 IP 地址";
            }
            if (running && !weak.startedAt) weak.startedAt = NSDate.date;
            if (!running) {
                weak.origin = nil;
                weak.code = nil;
                weak.startedAt = nil;
                TFScreenAwakeSet(@"remote-build", NO);
            }
            if (weak.changed) weak.changed();
            [NSNotificationCenter.defaultCenter postNotificationName:PBConnectionChanged object:weak];
        };
    }
    return self;
}

- (void)startAddress:(NSString *)address port:(NSUInteger)port {
    [self stop];
    self.requestedAddress = [NSString stringWithFormat:@"http://%@:%lu", address, (unsigned long)port];
    NSError *error = nil;
    self.activeCodeIsFixed = self.fixedCodeEnabled;
    NSString *code = self.activeCodeIsFixed ? self.fixedCode : [DXBuildService newConnectionCode:&error];
    if (self.activeCodeIsFixed && !code && [self saveFixedCode:@"" error:&error]) code = self.fixedCode;
    if (!code) {
        self.state = error.localizedDescription ?: @"无法取得连接码";
        if (self.changed) self.changed();
        [NSNotificationCenter.defaultCenter postNotificationName:PBConnectionChanged object:self];
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
    [NSNotificationCenter.defaultCenter postNotificationName:PBConnectionChanged object:self];
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
    self.requestedAddress = nil;
    self.lastHTTPAt = nil;
    self.lastRequestAt = nil;
    self.lastRejectedAt = nil;
    self.lastPeer = nil;
    self.requestCount = 0;
    self.state = @"已停止";
    TFScreenAwakeSet(@"remote-build", NO);
    if (self.changed) self.changed();
    [NSNotificationCenter.defaultCenter postNotificationName:PBConnectionChanged object:self];
}

static NSDictionary *Failure(NSInteger status, NSString *message) {
    return DXRemoteResponse(status, @{@"error": message});
}

- (NSDictionary *)handle:(NSDictionary *)request {
    NSString *route = request[@"path"], *method = request[@"method"];
    self.lastHTTPAt = NSDate.date;
    self.lastPeer = request[@"peer"];
    if ([method isEqual:@"GET"] && [@[@"/", @"/app.js", @"/style.css", @"/brand.png"] containsObject:route]) {
        if ([route isEqual:@"/"]) [NSNotificationCenter.defaultCenter postNotificationName:PBConnectionChanged object:self];
        NSString *name = [route isEqual:@"/"] ? @"index.html" : [route substringFromIndex:1];
        NSString *file = [NSBundle.mainBundle.bundlePath stringByAppendingPathComponent:
            [@"BuildWeb" stringByAppendingPathComponent:name]];
        NSString *type = [name hasSuffix:@".js"] ? @"application/javascript; charset=utf-8" :
            [name hasSuffix:@".css"] ? @"text/css; charset=utf-8" :
            [name hasSuffix:@".png"] ? @"image/png" : @"text/html; charset=utf-8";
        return @{@"status": @200, @"type": type, @"filePath": file};
    }
    NSString *authorization = request[@"headers"][@"authorization"];
    if (!self.code || ![authorization isEqual:[@"Bearer " stringByAppendingString:self.code]]) {
        if ([route isEqual:@"/api/v1/workspace"] || authorization.length) {
            self.lastRejectedAt = self.lastHTTPAt;
            [NSNotificationCenter.defaultCenter postNotificationName:PBConnectionChanged object:self];
        }
        return Failure(401, @"连接码无效，请查看手机上的当前连接码");
    }
    self.requestCount++;
    self.lastRequestAt = NSDate.date;
    [NSNotificationCenter.defaultCenter postNotificationName:PBConnectionChanged object:self];
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
            @"tools":PBToolchains.shared.status, @"connection":self.connectionDiagnostics});
    }
    if ([action isEqual:@"projects"]) return DXRemoteResponse(200, @{@"projects":self.projectList});
    if ([action isEqual:@"create"]) {
        NSString *name = [body[@"name"] isKindOfClass:NSString.class] ?
            [body[@"name"] stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet] : nil;
        if (!name.length || name.length > 120) return Failure(400, @"项目名需要 1–120 个字符。");
        NSString *product = body[@"productType"] ?: @"tweak";
        if (![@[@"tweak", @"app"] containsObject:product]) return Failure(400, @"productType 应为 tweak 或 app");
        NSString *identifier = NSUUID.UUID.UUIDString;
        NSString *root = [self.projects stringByAppendingPathComponent:identifier];
        if (![files createDirectoryAtPath:root withIntermediateDirectories:NO attributes:nil error:&error]) return Failure(500, error.localizedDescription);
        if ([product isEqual:@"app"] && ![body[@"empty"] isEqual:@YES]) {
            NSString *template = [NSBundle.mainBundle.bundlePath stringByAppendingPathComponent:@"AppTemplate"];
            for (NSString *file in [files contentsOfDirectoryAtPath:template error:&error]) {
                if (![files copyItemAtPath:[template stringByAppendingPathComponent:file] toPath:[root stringByAppendingPathComponent:file] error:&error]) break;
            }
            if (error) { [files removeItemAtPath:root error:nil]; return Failure(500, error.localizedDescription); }
        }
        if (![@{@"name":name, @"productType":product} writeToFile:[root stringByAppendingPathComponent:@".buildproject"] atomically:YES]) {
            [files removeItemAtPath:root error:nil];
            return Failure(500, @"项目记录保存失败");
        }
        [NSNotificationCenter.defaultCenter postNotificationName:PBBuildChanged object:self];
        return DXRemoteResponse(200, @{@"id":identifier, @"name":name, @"productType":product});
    }
    if ([action isEqual:@"tools"]) return DXRemoteResponse(200, PBToolchains.shared.status);
    NSString *jobID = body[@"job_id"];
    if (jobID && (![jobID isKindOfClass:NSString.class] || !self.jobs[jobID])) return Failure(404, @"构建记录不存在或已清理。");
    NSMutableDictionary *requestedJob = jobID ? self.jobs[jobID] : self.job;
    if ([action isEqual:@"job"]) {
        if (!jobID && body[@"project"]) {
            if (![self projectRoot:body[@"project"]]) return Failure(404, @"项目不存在。");
            requestedJob = (NSMutableDictionary *)[[self.recordedBuilds filteredArrayUsingPredicate:
                [NSPredicate predicateWithFormat:@"project == %@", body[@"project"]]] firstObject];
        }
        NSMutableDictionary *job = [requestedJob mutableCopy] ?: [@{@"state": @"idle"} mutableCopy];
        if ([self.job[@"state"] isEqual:@"running"]) job[@"activeJobId"] = self.job[@"id"];
        if (job[@"buildPath"]) {
            NSString *path = [job[@"buildPath"] stringByAppendingPathComponent:@"build.log"];
            job[@"log"] = [NSString stringWithContentsOfFile:path encoding:NSUTF8StringEncoding error:nil] ?: @"";
            job[@"products"] = PBProductFiles(job[@"artifacts"]);
        }
        [job removeObjectForKey:@"buildPath"];
        return DXRemoteResponse(200, job);
    }
    if ([action isEqual:@"history"]) {
        if (![self projectRoot:body[@"project"]]) return Failure(404, @"项目不存在。");
        NSMutableArray *history = [NSMutableArray array];
        for (NSDictionary *job in self.recordedBuilds) {
            if (![job[@"project"] isEqual:body[@"project"]]) continue;
            NSMutableDictionary *entry = [job mutableCopy];
            [entry removeObjectForKey:@"buildPath"];
            [history addObject:entry];
        }
        return DXRemoteResponse(200, @{@"builds":history});
    }
    if ([action isEqual:@"diagnostic_source"]) {
        if (!jobID) return Failure(400, @"请选择构建记录");
        NSDictionary *source = [self diagnosticSourceForBuild:jobID error:&error];
        return source ? DXRemoteResponse(200, source) : Failure(error.code, error.localizedDescription);
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
    NSString *root = [self projectRoot:identifier];
    if (!root) return Failure(404, @"项目不存在");
    if ([action isEqual:@"rename_project"]) {
        if (![self renameProject:identifier name:body[@"name"] error:&error]) return Failure(
            [error.domain isEqual:@"PocketBuild.Project"] ? error.code : 500, error.localizedDescription ?: @"无法保存项目名。");
        return DXRemoteResponse(200, @{@"id":identifier, @"name":[body[@"name"] stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet]});
    }
    if ([action isEqual:@"files"]) {
        NSUserDefaults *defaults = NSUserDefaults.standardUserDefaults;
        NSDictionary *buildDefaults = @{
            @"sdkVersion":[defaults stringForKey:@"StudioSDKVersion"] ?: @"16.4",
            @"deploymentTarget":[defaults stringForKey:@"StudioDeploymentTarget"] ?: @"15.0",
            @"exportDylib":[defaults objectForKey:@"StudioExportDylib"] ?: @YES,
            @"package":[defaults objectForKey:@"StudioPackageEnabled"] ?: @YES,
            @"packageSchemes":[defaults arrayForKey:@"StudioPackageSchemes"] ?: @[@"rootless"]
        };
        return DXRemoteResponse(200, @{@"files":ProjectFiles(root), @"buildDefaults":buildDefaults,
            @"summary":[self projectDetails:identifier] ?: @{}});
    }
    if ([action isEqual:@"build"]) {
        NSDictionary *result = [self startProjectBuild:identifier error:&error];
        if (!result) return Failure([error.domain isEqual:@"PocketBuild.Project"] ? error.code : 500,
            error.localizedDescription ?: @"无法创建构建记录。");
        NSMutableDictionary *response = [result mutableCopy];
        [response removeObjectForKey:@"buildPath"];
        return DXRemoteResponse(200, response);
    }

    NSString *relative = body[@"path"];
    NSString *target = ProjectFile(root, relative);
    if (!target) return Failure(400, @"文件路径无效或超出项目");
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
