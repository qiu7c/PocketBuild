#import "ProjectRecords.h"

NSString *PBBuildStateTitle(NSString *state) {
    return state ? (@{@"running":@"正在编译", @"succeeded":@"编译成功", @"failed":@"编译失败",
        @"cancelled":@"已取消", @"interrupted":@"已中断", @"idle":@"无构建任务"}[state] ?: state) : @"无构建任务";
}

NSRange PBSourceLocation(NSString *text, NSUInteger line, NSUInteger byteColumn) {
    NSUInteger start = 0, end = 0, next = 0;
    for (NSUInteger number = 1; number < MAX(line, 1U) && start < text.length; number++) {
        [text getLineStart:nil end:&next contentsEnd:nil forRange:NSMakeRange(start, 1)];
        start = next;
    }
    if (start == text.length) return NSMakeRange(start, 0);
    [text getLineStart:nil end:nil contentsEnd:&end forRange:NSMakeRange(start, 1)];
    NSUInteger target = byteColumn ? byteColumn - 1 : 0;
    __block NSRange selected = NSMakeRange(end, 0);
    __block NSUInteger bytes = 0;
    [text enumerateSubstringsInRange:NSMakeRange(start, end - start) options:NSStringEnumerationByComposedCharacterSequences
        usingBlock:^(NSString *character, NSRange range, NSRange enclosing, BOOL *stop) {
            bytes += [character lengthOfBytesUsingEncoding:NSUTF8StringEncoding];
            if (bytes > target) { selected = range; *stop = YES; }
        }];
    return byteColumn ? selected : NSMakeRange(start, end - start);
}
#import "../DocumentPresentation.h"

NSString *PBDocumentsDirectory(void) {
    return NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES).firstObject;
}

NSArray<NSString *> *PBStoredBuildDirectories(void) {
    NSString *documents = PBDocumentsDirectory();
    NSMutableArray<NSString *> *paths = [NSMutableArray array];
    for (NSString *name in [NSFileManager.defaultManager contentsOfDirectoryAtPath:documents error:nil]) {
        if (![name hasPrefix:@"Build-"] || !TMCDocumentUUID([name substringFromIndex:6])) continue;
        NSString *path = [documents stringByAppendingPathComponent:name];
        if (TMCRegularDocument(path, YES)) [paths addObject:path];
    }
    return paths;
}

NSArray<NSString *> *PBBuildArtifacts(NSString *directory) {
    NSMutableArray<NSString *> *results = [NSMutableArray array];
    for (NSString *name in [NSFileManager.defaultManager contentsOfDirectoryAtPath:directory error:nil]) {
        if ([name hasPrefix:@"."] || ![@[@"ipa", @"dylib", @"deb", @"log", @"json"] containsObject:name.pathExtension.lowercaseString]) continue;
        if (TMCRegularDocument([directory stringByAppendingPathComponent:name], NO)) [results addObject:name];
    }
    return [results sortedArrayUsingSelector:@selector(localizedStandardCompare:)];
}

NSArray<NSString *> *PBProductFiles(NSArray<NSString *> *files) {
    NSMutableArray *products = [NSMutableArray array];
    for (NSString *file in files) {
        if ([@[@"ipa", @"dylib", @"deb"] containsObject:file.pathExtension.lowercaseString]) [products addObject:file];
    }
    return products;
}

BOOL PBWriteBuildJob(NSDictionary *job, NSError **error) {
    NSMutableDictionary *record = [job mutableCopy];
    NSString *path = [record[@"buildPath"] stringByAppendingPathComponent:@".pocketbuild-job.json"];
    [record removeObjectForKey:@"buildPath"];
    NSData *data = [NSJSONSerialization dataWithJSONObject:record options:0 error:error];
    return data && [data writeToFile:path options:NSDataWritingAtomic error:error];
}

NSDictionary *PBReadBuildJob(NSString *directory) {
    NSDictionary *saved = TMCDocumentJSON([directory stringByAppendingPathComponent:@".pocketbuild-job.json"]);
    BOOL needsReport = !saved.count || [saved[@"state"] isEqual:@"running"];
    NSDictionary *report = needsReport ? TMCDocumentJSON([directory stringByAppendingPathComponent:@"report.json"]) : nil;
    if (!saved.count && !report.count &&
        !TMCRegularDocument([directory stringByAppendingPathComponent:@".build-in-progress.json"], NO)) return nil;

    NSMutableDictionary *job = [saved mutableCopy];
    if (!saved.count) {
        NSDate *created = [NSFileManager.defaultManager attributesOfItemAtPath:directory error:nil][NSFileCreationDate];
        job = [@{@"id":[directory.lastPathComponent substringFromIndex:6],
                 @"projectName":report[@"projectName"] ?: @"旧构建",
                 @"startedAt":report[@"startedAt"] ?: @(created.timeIntervalSince1970)} mutableCopy];
    }
    if (!job[@"state"] || [job[@"state"] isEqual:@"running"]) {
        if ([report[@"cancelled"] boolValue]) job[@"state"] = @"cancelled";
        else if ([report[@"success"] boolValue]) job[@"state"] = @"succeeded";
        else if (report[@"success"] && ![report[@"interrupted"] boolValue]) job[@"state"] = @"failed";
        else job[@"state"] = @"interrupted";
        if (report[@"finishedAt"]) job[@"finishedAt"] = report[@"finishedAt"];
    }
    if (!job[@"issue"] && [job[@"state"] isEqual:@"interrupted"]) {
        job[@"issue"] = @{@"kind":@"interrupted", @"message":@"上次构建在结束前退出。可用当前源码重新构建。"};
    }
    job[@"id"] = [directory.lastPathComponent substringFromIndex:6];
    job[@"buildPath"] = directory;
    job[@"artifacts"] = PBBuildArtifacts(directory);
    return job;
}

NSDictionary *PBBuildIssue(NSString *directory) {
    NSDictionary *report = TMCDocumentJSON([directory stringByAppendingPathComponent:@"report.json"]);
    NSString *logPath = [directory stringByAppendingPathComponent:@"build.log"];
    NSFileHandle *file = [NSFileHandle fileHandleForReadingAtPath:logPath];
    NSData *start = [file readDataUpToLength:512 * 1024 error:nil];
    [file closeAndReturnError:nil];
    NSString *log = start.length ? [[NSString alloc] initWithData:start encoding:NSUTF8StringEncoding] : @"";
    for (NSUInteger trim = 1; !log && trim < 4 && trim < start.length; trim++) {
        log = [[NSString alloc] initWithData:[start subdataWithRange:NSMakeRange(0, start.length - trim)]
            encoding:NSUTF8StringEncoding];
    }
    NSRegularExpression *pattern = [NSRegularExpression regularExpressionWithPattern:
        @"^(.+?):([0-9]+):([0-9]+): (?:fatal )?error: (.+)$"
        options:NSRegularExpressionAnchorsMatchLines error:nil];
    NSString *root = [directory stringByAppendingPathComponent:@"snapshot"].stringByStandardizingPath;
    NSString *snapshot = [root stringByAppendingString:@"/"];
    __block NSString *firstMessage = nil;
    __block NSDictionary *located = nil;
    [pattern enumerateMatchesInString:log ?: @"" options:0 range:NSMakeRange(0, log.length)
        usingBlock:^(NSTextCheckingResult *match, NSMatchingFlags flags, BOOL *stop) {
        if (!match) return;
        NSString *message = [log substringWithRange:[match rangeAtIndex:4]];
        if (!firstMessage) firstMessage = message;
        NSString *source = [log substringWithRange:[match rangeAtIndex:1]];
        if (!source.isAbsolutePath) source = [root stringByAppendingPathComponent:source];
        source = source.stringByStandardizingPath;
        if ([source hasPrefix:snapshot] && TMCRegularDocument(source, NO)) {
            located = @{@"kind":@"compiler", @"message":message, @"file":[source substringFromIndex:snapshot.length],
                @"line":@([[log substringWithRange:[match rangeAtIndex:2]] integerValue]),
                @"column":@([[log substringWithRange:[match rangeAtIndex:3]] integerValue])};
            *stop = YES;
        }
    }];
    if (located) return located;
    if (firstMessage) return @{@"kind":@"compiler", @"message":firstMessage};
    for (NSString *line in [log componentsSeparatedByString:@"\n"]) {
        if ([line hasPrefix:@"ld64.lld: error:"] || [line hasPrefix:@"error:"]) {
            return @{@"kind":@"compiler", @"message":line};
        }
    }
    return @{@"kind":@"build", @"message":report[@"packageError"] ?: @"构建失败，请查看完整日志。"};
}

NSArray<NSDictionary *> *PBJobsToClean(NSArray<NSDictionary *> *jobs) {
    NSMutableArray *deletable = [NSMutableArray array];
    BOOL keptSuccess = NO;
    for (NSDictionary *job in jobs) {
        if ([job[@"state"] isEqual:@"running"]) continue;
        if (!keptSuccess && [job[@"state"] isEqual:@"succeeded"]) {
            keptSuccess = YES;
            continue;
        }
        [deletable addObject:job];
    }
    return deletable;
}

unsigned long long PBAllocatedBytes(NSArray<NSString *> *paths) {
    unsigned long long size = 0;
    NSArray *keys = @[NSURLIsRegularFileKey, NSURLTotalFileAllocatedSizeKey, NSURLFileSizeKey];
    for (NSString *path in paths) {
        NSDirectoryEnumerator<NSURL *> *files = [NSFileManager.defaultManager enumeratorAtURL:[NSURL fileURLWithPath:path]
            includingPropertiesForKeys:keys options:0 errorHandler:nil];
        for (NSURL *file in files) {
            NSDictionary *values = [file resourceValuesForKeys:keys error:nil];
            if (![values[NSURLIsRegularFileKey] boolValue]) continue;
            NSNumber *length = values[NSURLTotalFileAllocatedSizeKey] ?: values[NSURLFileSizeKey];
            size += length.unsignedLongLongValue;
        }
    }
    return size;
}
