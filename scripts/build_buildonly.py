#!/usr/bin/env python3
"""Build PocketBuild with its signed compiler core and optional data resources."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import plistlib
import shutil
import subprocess
import zipfile

ROOT = Path(__file__).resolve().parents[1]
VERSION = "0.1.0"


def compiler_source() -> str:
    source = (ROOT / "App/main.m").read_text(encoding="utf-8")
    source = source.split('\n#if TARGET_OS_SIMULATOR\n#include "../tests/RemoteSimulatorRegression.inc"')[0]
    replacements = {
        '#import "AI/Agent/TFAIBuildCheckpoint.h"': '#import "BuildOnly/BuildCache.h"',
        '#import "AI/Background/TFScreenAwake.h"': '#import "BuildOnly/ScreenAwake.h"',
    }
    omitted = {
        '#import "Remote/DXRemoteService.h"', '#import "Studio.h"', '#import "GitUI.h"',
        '#import "Incoming/TFIncoming.h"', '#import "GitAutomation.h"', '#import "StorageSpace.h"',
    }
    lines = []
    for line in source.splitlines():
        if line in replacements:
            lines.append(replacements[line])
        elif line.startswith('#import "AI/') or line in omitted:
            continue
        else:
            lines.append(line)
    source = "\n".join(lines).replace("TFAIBuild", "DXBuild") + "\n"
    if "TFAI" in source or "UIApplicationMain" in source or not source.rstrip().endswith("@end"):
        raise ValueError("Upstream compiler boundary changed. Review main.m before building.")
    # Downloaded data lives separately from the signed executable frameworks.
    source = source.replace("NSBundle.mainBundle.privateFrameworksPath", "PBCompilerFrameworks()")
    source = source.replace("NSBundle.mainBundle.bundlePath", 'PBInstalledPackage(@"support")')
    source = source.replace(
        '[[NSBundle mainBundle] pathForResource:@"commands" ofType:@"plist"]',
        '[PBInstalledPackage(@"support") stringByAppendingPathComponent:@"commands.plist"]',
    )
    # Keep the upstream compile loop; change the product-specific link and package steps.
    hooks = {
        'NSError *namingError=nil;NSString *dylibName=':
            'BOOL isApp=[config[@"productType"] isEqual:@"app"]; NSError *namingError=nil;'
            'NSDictionary *appPlan=isApp?PBPrepareAppPlan(projectDirectory,config,&namingError):nil;NSString *dylibName=',
        'if(multipleSchemes&&[config[@"package"] boolValue])':
            'if(isApp){dylibName=appPlan[@"name"];debName=@"unused.deb";}\n        if(!isApp&&multipleSchemes&&[config[@"package"] boolValue])',
        'link = [TMCPackageLinkArguments(link, packageScheme, vendorFrameworks, tweakName) mutableCopy];':
            'link = [(isApp?PBAppLinkArguments(link):TMCPackageLinkArguments(link,packageScheme,vendorFrameworks,tweakName)) mutableCopy];',
        'BOOL stripSymbols=TFShouldStripSymbols(config);':
            'BOOL stripSymbols=!isApp&&TFShouldStripSymbols(config);',
        'TMCValidateDylibSignature([NSData dataWithContentsOfFile:[build stringByAppendingPathComponent:dylibName]], &symbolError)':
            'TMCValidateMachOSignature([NSData dataWithContentsOfFile:[build stringByAppendingPathComponent:dylibName]], isApp?MH_EXECUTE:MH_DYLIB, &symbolError)',
        'BOOL shouldPackage=[config[@"package"] boolValue];':
            'BOOL shouldPackage=!isApp&&[config[@"package"] boolValue];',
        'if(toolSuccess&&!shouldPackage)': 'if(toolSuccess&&!shouldPackage&&!isApp)',
        'if(!exportDylib&&!shouldPackage)': 'if(!exportDylib&&!shouldPackage&&!isApp)',
        'report[@"namedArtifacts"]=namedArtifacts;':
            'if(isApp){report[@"productType"]=@"app";report[@"signing"]=@"ad-hoc executable; IPA requires external installation signing";'
            'if(toolSuccess){NSError *appError=nil;NSString *ipa=PBPackageApp(build,appPlan,^BOOL{return self.cancelRequested;},&appError);'
            'report[@"success"]=@(ipa!=nil);if(ipa)[namedArtifacts addObject:ipa];else {report[@"packageError"]=appError.localizedDescription?:@"IPA packaging failed";TMCLog(log,"IPA: %s\\n",[report[@"packageError"] UTF8String]);}}}\n'
            '        report[@"namedArtifacts"]=namedArtifacts;',
    }
    for old, new in hooks.items():
        if source.count(old) != 1:
            raise ValueError("Upstream App build hook changed: " + old)
        source = source.replace(old, new)
    prefix = '''#import "BuildOnly/PackagePaths.h"
#import "BuildOnly/AppBuild.h"
#import "BuildOnly/ScreenAwake.h"
// The remote service owns the foreground wake policy.
#define TFScreenAwakeSet(reason, active) ((void)0)
static NSString *PBCompilerFrameworks(void) {
    return [NSBundle bundleForClass:NSClassFromString(@"CompilerController")].bundlePath.stringByDeletingLastPathComponent;
}
'''
    return prefix + source


def zip_directory(directory: Path, output: Path) -> str:
    with zipfile.ZipFile(output, "w", zipfile.ZIP_DEFLATED) as archive:
        for path in sorted(directory.rglob("*")):
            if path.is_file():
                archive.write(path, path.relative_to(directory).as_posix())
    digest = hashlib.sha256()
    with output.open("rb") as stream:
        for chunk in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--check", action="store_true")
    parser.add_argument("--simulator", action="store_true")
    parser.add_argument("--packages", action="store_true", help="Export SDK, header and Logos resource packages.")
    parser.add_argument("--package-base-url", default="", help="Optional HTTPS/LAN directory URL for package downloads.")
    parser.add_argument("--sdk16", type=Path, default=ROOT / "Resources/SDK")
    parser.add_argument("--sdk26", type=Path, default=ROOT / "LocalSDKs/iPhoneOS26.0.sdk")
    args = parser.parse_args()
    core = compiler_source()
    if args.check:
        print("PASS: isolated compiler extraction. One IPA embeds compiler frameworks; SDK and header resources are optional.")
        return

    platform = "iphonesimulator" if args.simulator else "iphoneos"
    arch = "x86_64" if args.simulator else "arm64"
    sdk = subprocess.check_output(["xcrun", "--sdk", platform, "--show-sdk-path"], text=True).strip()
    build = ROOT / "build" / ("pocketbuild-simulator" if args.simulator else "pocketbuild-device")
    build.mkdir(parents=True, exist_ok=True)
    app = build / "PocketBuild.app"
    app.resolve().relative_to((ROOT / "build").resolve())
    if app.exists():
        shutil.rmtree(app)
    app.mkdir(parents=True)
    minimum = "-mios-simulator-version-min=15.0" if args.simulator else "-miphoneos-version-min=15.0"
    common = ["xcrun", "--sdk", platform, "clang", "-arch", arch, "-isysroot", sdk,
              minimum, "-fobjc-arc", "-fmodules", "-I" + str(ROOT / "App"), "-larchive"]
    for framework in ("UIKit", "Foundation", "Network", "Security", "CoreFoundation",
                      "QuartzCore", "CoreGraphics", "UniformTypeIdentifiers"):
        common.extend(["-framework", framework])

    toolchain = build / "toolchain"
    names = ["ios_system", "libLLVM", "clang", "lld"] + ([] if args.simulator else ["perl"])
    if toolchain.exists():
        toolchain.resolve().relative_to((ROOT / "build").resolve())
        shutil.rmtree(toolchain)
    frameworks = toolchain / "Frameworks"
    frameworks.mkdir(parents=True)
    source_root = Path(os.environ.get("DYLIX_TOOLCHAIN_ROOT", str(ROOT)))
    for name in names:
        bundle = source_root / "Vendor" / (name + ".xcframework")
        if not (bundle / "Info.plist").exists():
            raise ValueError("Run python3 scripts/fetch_toolchain.py first.")
        metadata = plistlib.loads((bundle / "Info.plist").read_bytes())
        match = next(item for item in metadata["AvailableLibraries"]
                     if item["SupportedPlatform"] == "ios" and arch in item["SupportedArchitectures"]
                     and item.get("SupportedPlatformVariant", "") == ("simulator" if args.simulator else ""))
        source = bundle / match["LibraryIdentifier"] / match["LibraryPath"]
        shutil.copytree(source, frameworks / source.name)
    (build / "CompilerCore.m").write_text(core, encoding="utf-8")
    module = frameworks / "PBCompiler.framework"
    module.mkdir()
    module_info = {
        "CFBundleExecutable":"PBCompiler", "CFBundleIdentifier":"com.qiu7c.pocketbuild.compiler",
        "CFBundleName":"PBCompiler", "CFBundlePackageType":"FMWK",
        "CFBundleShortVersionString":VERSION, "CFBundleVersion":"1", "MinimumOSVersion":"15.0",
    }
    (module / "Info.plist").write_bytes(plistlib.dumps(module_info))
    compiler_sources = [
        build / "CompilerCore.m",
        *[ROOT / "App" / name for name in (
            "BuildOnly/SDKResources.m", "RuntimeDiagnostics.m", "ArchiveImport.m", "TheosMakefile.m",
            "DebPackage.m", "OutputNaming.m", "CompatibilityRepair.m", "GlassSupport.m", "LinkSupport.m",
            "BuildOnly/BuildCache.m", "BuildOnly/AppBuild.m",
        )],
        ROOT / "Vendor/MBProgressHUD/MBProgressHUD.m",
    ]
    subprocess.run(common + [
        "-dynamiclib", "-fvisibility=hidden", "-F" + str(frameworks), "-framework", "ios_system",
        "-Wl,-needed_framework,libLLVM", "-Wl,-rpath,@loader_path/..",
        "-Wl,-install_name,@rpath/PBCompiler.framework/PBCompiler",
        *map(str, compiler_sources), "-o", str(module / "PBCompiler"),
    ], check=True)
    for name in [*names, "PBCompiler"]:
        subprocess.run(["codesign", "--force", "--sign", "-", str(frameworks / (name + ".framework"))], check=True)
    shutil.copytree(frameworks, app / "Frameworks")

    if args.packages:
        output = build / "packages"
        output.mkdir(exist_ok=True)
        entries = []
        support = build / "support"
        if support.exists():
            support.resolve().relative_to((ROOT / "build").resolve())
            shutil.rmtree(support)
        support.mkdir()
        for name in ("logos", "Include", "ClangInclude", "Perl", "VendorFrameworks", "CompatibilityRules", "SampleProject"):
            shutil.copytree(ROOT / "Resources" / name, support / name)
        commands = {name:[framework + ".framework/" + framework,"main","","no"]
                    for name,framework in (("clang","clang"),("ld64.lld","lld"))}
        for name,value in (("commands.plist",commands),("extraCommandsDictionary.plist",commands),("commandDictionary.plist",{})):
            (support / name).write_bytes(plistlib.dumps(value))
        for identifier, title, source in (
            ("support","Logos、Clang 头文件和构建资源",support),
            ("sdk16","iOS 16.4 SDK",args.sdk16),
            ("sdk26","iOS 26.0 SDK",args.sdk26),
        ):
            if identifier.startswith("sdk"):
                expected = "16.4" if identifier == "sdk16" else "26.0"
                if plistlib.loads((source / "SDKSettings.plist").read_bytes()).get("Version") != expected:
                    raise ValueError("Unexpected SDK metadata: " + str(source))
            filename = "PocketBuild-" + identifier + "-" + VERSION + ".zip"
            archive = output / filename
            digest = zip_directory(source, archive)
            url = args.package_base_url.rstrip("/") + "/" + filename if args.package_base_url else filename
            entries.append({"id":identifier,"title":title,"url":url,"sha256":digest,"bytes":archive.stat().st_size})
        (output / "PocketBuild-packages.json").write_text(
            json.dumps({"schema":1,"version":VERSION,"packages":entries},ensure_ascii=False,indent=2),encoding="utf-8")

    shutil.copytree(ROOT / "Resources/BuildWeb", app / "BuildWeb")
    shutil.copytree(ROOT / "Resources/AppTemplate", app / "AppTemplate")
    notices = app / "ThirdPartyNotices"
    notices.mkdir()
    for filename in ("LICENSE", "COPYRIGHT", "THIRD_PARTY_NOTICES.md"):
        shutil.copy2(ROOT / filename, notices / filename)
    if (ROOT / "Resources/ThirdPartyNotices").is_dir():
        shutil.copytree(ROOT / "Resources/ThirdPartyNotices", notices, dirs_exist_ok=True)
    sources = [ROOT / "App" / name for name in (
        "BuildOnly/BuildHome.m", "BuildOnly/ToolsHome.m", "BuildOnly/BuildService.m", "BuildOnly/Toolchains.m",
        "BuildOnly/ScreenAwake.m", "Remote/DXRemoteHTTP.m", "ArchiveImport.m", "TheosMakefile.m",
    )]
    subprocess.run(common + [*map(str,sources), "-o", str(app / "PocketBuild")],check=True)
    icons_info = build / "icons-info.plist"
    subprocess.run([
        "xcrun","actool","--compile",str(app),"--platform",platform,"--minimum-deployment-target","15.0",
        "--app-icon","AppIcon","--target-device","iphone","--target-device","ipad",
        "--output-partial-info-plist",str(icons_info),str(ROOT / "Resources/PocketBuild/Assets.xcassets"),
    ],check=True)
    info = {
        "CFBundleExecutable":"PocketBuild", "CFBundleIdentifier":"com.qiu7c.pocketbuild",
        "CFBundleName":"PocketBuild", "CFBundleDisplayName":"PocketBuild", "CFBundlePackageType":"APPL",
        "CFBundleShortVersionString":VERSION, "CFBundleVersion":"1", "MinimumOSVersion":"15.0",
        "CFBundleSupportedPlatforms":["iPhoneSimulator" if args.simulator else "iPhoneOS"],
        "UIDeviceFamily":[1,2], "UILaunchScreen":{}, "UIFileSharingEnabled":True,
        "LSSupportsOpeningDocumentsInPlace":True, "NSAppTransportSecurity":{"NSAllowsLocalNetworking":True},
        "NSLocalNetworkUsageDescription":"允许连接个人热点或局域网的电脑上传源码、触发编译和下载产物。",
    }
    info.update(plistlib.loads(icons_info.read_bytes()))
    (app / "Info.plist").write_bytes(plistlib.dumps(info))
    subprocess.run(["codesign","--force","--sign","-",str(app)],check=True)
    if not args.simulator:
        ipa = build / ("PocketBuild-" + VERSION + "-unsigned.ipa")
        with zipfile.ZipFile(ipa,"w",zipfile.ZIP_DEFLATED) as package:
            for file in app.rglob("*"):
                if file.is_file():
                    package.write(file,"Payload/PocketBuild.app/" + file.relative_to(app).as_posix())
        print(ipa)


if __name__ == "__main__":
    main()
