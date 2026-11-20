#import <Foundation/Foundation.h>
#import "../App/BuildOnly/ProjectRecords.h"
#import "../App/ArchiveImport.h"

int main(int argc, const char *argv[]) {
    @autoreleasepool {
        NSCAssert(argc == 2, @"Expected a temporary workspace");
        NSString *root = @(argv[1]);
        NSFileManager *files = NSFileManager.defaultManager;
        NSString *identifier = NSUUID.UUID.UUIDString;
        NSString *directory = [root stringByAppendingPathComponent:[@"Build-" stringByAppendingString:identifier]];
        NSString *snapshot = [directory stringByAppendingPathComponent:@"snapshot"];
        NSCAssert([files createDirectoryAtPath:snapshot withIntermediateDirectories:YES attributes:nil error:nil], @"Fixture directory");
        NSCAssert([files createFileAtPath:[snapshot stringByAppendingPathComponent:@"Main.mm"] contents:NSData.data attributes:nil], @"Fixture source");
        NSString *manifest = [snapshot stringByAppendingPathComponent:@"MobileCompiler.json"];
        NSDictionary *preview = TMCInspectImportedProject(snapshot, @"Demo", nil);
        NSCAssert([preview[@"sources"] isEqual:@[@"Main.mm"]] && ![files fileExistsAtPath:manifest], @"Project preview does not write a manifest");
        NSDictionary *prepared = TMCPrepareImportedProject(snapshot, @"Demo", nil);
        NSCAssert([prepared[@"configuration"] isEqual:preview[@"configuration"]] && [files fileExistsAtPath:manifest],
            @"Preview and build use the same configuration discovery");
        NSString *project = NSUUID.UUID.UUIDString;
        NSDictionary *running = @{@"id":identifier, @"project":project, @"projectName":@"Demo",
            @"state":@"running", @"startedAt":@1, @"buildPath":directory};
        NSCAssert(PBWriteBuildJob(running, nil), @"Save before compiler starts");
        NSDictionary *reopened = PBReadBuildJob(directory);
        NSCAssert([reopened[@"project"] isEqual:project] && [reopened[@"state"] isEqual:@"interrupted"],
            @"An interrupted job must retain its owning project");

        NSString *log = [NSString stringWithFormat:@"/sdk/UIKit.h:1:2: error: a dependency diagnostic\n"
            "%@/Main.mm:7:12: error: first project error\n"
            "%@/Main.mm:8:1: error: secondary error\n", snapshot, snapshot];
        NSCAssert([log writeToFile:[directory stringByAppendingPathComponent:@"build.log"]
            atomically:YES encoding:NSUTF8StringEncoding error:nil], @"Write diagnostics fixture");
        NSDictionary *issue = PBBuildIssue(directory);
        NSCAssert([issue[@"file"] isEqual:@"Main.mm"] && [issue[@"line"] isEqual:@7] &&
            [issue[@"column"] isEqual:@12] && [issue[@"message"] isEqual:@"first project error"], @"First error maps to snapshot source");
        NSString *source = @"头部\r\n中error\r\n";
        NSRange location = PBSourceLocation(source, 2, 4);
        NSCAssert([[source substringWithRange:location] isEqual:@"e"], @"Clang columns count UTF-8 bytes");
        NSCAssert(NSEqualRanges(PBSourceLocation(source, 3, 1), NSMakeRange(source.length, 0)), @"Trailing empty line");
        NSCAssert([PBProductFiles(@[@"Demo.ipa", @"build.log", @"report.json"]) isEqual:@[@"Demo.ipa"]], @"Product list excludes logs and reports");

        NSMutableDictionary *finished = [running mutableCopy];
        finished[@"state"] = @"failed";
        finished[@"issue"] = issue;
        NSCAssert(PBWriteBuildJob(finished, nil), @"Save compiler failure");
        reopened = PBReadBuildJob(directory);
        NSCAssert([reopened[@"issue"] isEqual:issue] && [reopened[@"artifacts"] isEqual:@[@"build.log"]],
            @"Reopened job must preserve failure and enumerate actual files");

        NSArray *ordered = @[
            @{@"id":@"active", @"state":@"running"},
            @{@"id":@"new-failure", @"state":@"failed"},
            @{@"id":@"last-success", @"state":@"succeeded"},
            @{@"id":@"old-success", @"state":@"succeeded"}
        ];
        NSArray *expected = @[@"new-failure", @"old-success"];
        NSCAssert([[PBJobsToClean(ordered) valueForKey:@"id"] isEqual:expected],
            @"Project cleanup must protect the active job and the most recent success");
        puts("PASS: persistent ownership, interrupted recovery, diagnostic location and cleanup retention");
    }
}
