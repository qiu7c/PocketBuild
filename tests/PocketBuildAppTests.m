#import <Foundation/Foundation.h>
#import "../App/BuildOnly/AppBuild.h"
#import "../App/DylibSignature.h"

static void Check(BOOL value, NSString *message) {
    if (!value) { NSLog(@"FAIL: %@", message); exit(1); }
}

int main(int argc, char **argv) { @autoreleasepool {
    if (argc != 5) return 2;
    NSString *mode = @(argv[1]), *root = @(argv[2]), *build = @(argv[3]), *sdk = @(argv[4]);
    NSDictionary *config = [NSJSONSerialization JSONObjectWithData:[NSData dataWithContentsOfFile:[root stringByAppendingPathComponent:@"MobileCompiler.json"]] options:0 error:nil];
    NSError *error = nil;
    NSDictionary *plan = PBPrepareAppPlan(root, config, &error);
    Check(plan != nil, error.localizedDescription);
    Check([plan[@"info"][@"CFBundleExecutable"] isEqual:@"HelloPocket"], @"executable name");
    Check([plan[@"info"][@"CFBundleIdentifier"] isEqual:@"com.example.hellopocket"], @"bundle identifier");
    if ([mode isEqual:@"link"]) {
        NSArray *args = PBAppLinkArguments(@[@"ld64.lld", @"-dylib", @"-arch", @"arm64", @"-platform_version", @"ios", @"15.0", @"16.4",
            @"-syslibroot", sdk, @"-lSystem", @"-lobjc", @"-lc++", @"-framework", @"Foundation", @"-framework", @"UIKit",
            @"-undefined", @"dynamic_lookup", @"-install_name", @"@rpath/Test.dylib", @"-rpath", @"/var/jb/Library/Frameworks",
            [build stringByAppendingPathComponent:@"main.o"], @"-o", [build stringByAppendingPathComponent:@"HelloPocket"]]);
        Check(![args containsObject:@"-dylib"] && ![args containsObject:@"dynamic_lookup"] && ![args containsObject:@"-install_name"], @"App link mode");
        Check(![args containsObject:@"/var/jb/Library/Frameworks"] && [args containsObject:@"_main"], @"App entry point");
        NSData *json = [NSJSONSerialization dataWithJSONObject:args options:0 error:nil];
        fwrite(json.bytes, 1, json.length, stdout);
        return 0;
    }
    NSData *executable = [NSData dataWithContentsOfFile:[build stringByAppendingPathComponent:@"HelloPocket"]];
    Check(TMCValidateMachOSignature(executable, MH_EXECUTE, &error), error.localizedDescription);
    Check(!TMCValidateDylibSignature(executable, nil), @"executable must not validate as dylib");
    NSString *ipa = PBPackageApp(build, plan, ^BOOL { return NO; }, &error);
    Check([ipa isEqual:@"HelloPocket-unsigned.ipa"], error.localizedDescription);

    NSMutableDictionary *bad = [config mutableCopy];
    bad[@"bundleIdentifier"] = @"invalid id";
    Check(!PBPrepareAppPlan(root, bad, nil), @"invalid identifier rejected");
    bad = [config mutableCopy]; bad[@"resources"] = @[@"../outside"];
    Check(!PBPrepareAppPlan(root, bad, nil), @"resource escape rejected");
    bad = [config mutableCopy]; bad[@"resources"] = @[@"Main.storyboard"];
    Check(!PBPrepareAppPlan(root, bad, nil), @"Storyboard is explicitly unsupported");

    NSString *cancelBuild = [build stringByAppendingPathComponent:@"cancel"];
    [NSFileManager.defaultManager createDirectoryAtPath:cancelBuild withIntermediateDirectories:YES attributes:nil error:nil];
    [NSFileManager.defaultManager copyItemAtPath:[build stringByAppendingPathComponent:@"HelloPocket"] toPath:[cancelBuild stringByAppendingPathComponent:@"HelloPocket"] error:nil];
    error = nil;
    Check(!PBPackageApp(cancelBuild, plan, ^BOOL { return YES; }, &error), @"cancel packaging");
    Check(![NSFileManager.defaultManager fileExistsAtPath:[cancelBuild stringByAppendingPathComponent:ipa]], @"no partial IPA after cancellation");
    puts("PASS: App plan, executable signature, IPA packaging and cancellation");
    return 0;
} }
