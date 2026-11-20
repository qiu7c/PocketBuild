#!/usr/bin/env python3
"""Build PocketBuild with its signed compiler core and optional data resources."""
import argparse
from collections import deque
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
BUILD_NUMBER = "13"


def compiler_source() -> str:
    source = (ROOT / "App/CompilerCore.m").read_text(encoding="utf-8")
    if "TFAI" in source or "UIApplicationMain" in source or not source.rstrip().endswith("@end"):
        raise ValueError("CompilerCore.m must contain only the PocketBuild compiler implementation.")
    return source


def sdk_files(directory: Path):
    directory = directory.resolve()
    repository = ROOT.resolve()
    tracked_links = set()
    if (repository / ".git").exists() and directory.is_relative_to(repository):
        # Git on Windows can check symbolic links out as small files containing the target path.
        index = subprocess.check_output(
            ["git", "ls-files", "--stage", "-z", "--", directory.relative_to(repository).as_posix()], cwd=repository)
        tracked_links = {repository / Path(entry.split("\t", 1)[1])
                         for entry in index.decode("utf-8").split("\0") if entry.startswith("120000 ")}

    def resolve(relative: Path) -> Path:
        pending = deque(relative.parts)
        current = directory
        followed = 0
        while pending:
            name = pending.popleft()
            if name == "..":
                if current == directory:
                    raise ValueError(f"SDK link leaves its source directory: {relative}")
                current = current.parent
                continue
            candidate = current / name
            if candidate.is_symlink() or candidate in tracked_links:
                destination = candidate.readlink() if candidate.is_symlink() else Path(candidate.read_text(encoding="utf-8").strip())
                followed += 1
                if destination.anchor or followed > 40:
                    raise ValueError(f"Invalid SDK link: {relative}")
                pending.extendleft(reversed(destination.parts))
            else:
                current = candidate
        if not current.exists():
            raise ValueError(f"Missing SDK link target: {relative} -> {current}")
        return current

    def visit(folder: Path, name: Path, parents: tuple):
        for entry in sorted(folder.iterdir()):
            member = name / entry.name
            target = resolve(entry.relative_to(directory)) if entry.is_symlink() or entry in tracked_links else entry
            if target.is_dir():
                if target in parents:
                    raise ValueError(f"Circular SDK directory link: {member}")
                yield from visit(target, member, parents + (target,))
            elif target.is_file():
                yield target, member.as_posix()

    yield from visit(directory, Path(), (directory,))


def zip_directory(directory: Path, output: Path, *, sdk: bool = False) -> str:
    entries = sdk_files(directory) if sdk else (
        (path, path.relative_to(directory).as_posix()) for path in sorted(directory.rglob("*")) if path.is_file()
    )
    temporary = output.with_suffix(".part")
    try:
        with zipfile.ZipFile(temporary, "w", zipfile.ZIP_DEFLATED) as archive:
            for source, member in entries:
                archive.write(source, member)
        temporary.replace(output)
    finally:
        temporary.unlink(missing_ok=True)
    digest = hashlib.sha256()
    with output.open("rb") as stream:
        for chunk in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def package_entry(output: Path, base_url: str, identifier: str, title: str, source: Path, version: str = "") -> dict:
    if version and plistlib.loads((source / "SDKSettings.plist").read_bytes()).get("Version") != version:
        raise ValueError("Unexpected SDK metadata: " + str(source))
    filename = f"PocketBuild-{identifier}-{VERSION}.zip"
    archive = output / filename
    digest = zip_directory(source, archive, sdk=bool(version))
    url = base_url.rstrip("/") + "/" + filename if base_url else filename
    return {"id":identifier, "title":title, "url":url, "sha256":digest, "bytes":archive.stat().st_size}


def export_sdk_packages(args, output: Path, extra=()):
    output.mkdir(parents=True, exist_ok=True)
    entries = list(extra)
    for identifier, source, version in (("sdk16", args.sdk16, "16.4"), ("sdk26", args.sdk26, "26.0")):
        entries.append(package_entry(output, args.package_base_url, identifier, f"iOS {version} SDK", source, version))
    manifest = output / "PocketBuild-packages.json"
    manifest.write_text(json.dumps({"schema":1, "version":VERSION, "packages":entries},
        ensure_ascii=False, indent=2), encoding="utf-8")
    return manifest


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--check", action="store_true")
    parser.add_argument("--simulator", action="store_true")
    outputs = parser.add_mutually_exclusive_group()
    outputs.add_argument("--packages", action="store_true", help="Export SDK, header and Logos resource packages.")
    outputs.add_argument("--sdk-packages-only", action="store_true", help="Repack SDK downloads without Xcode or an IPA build.")
    parser.add_argument("--package-base-url", default="", help="Optional HTTPS/LAN directory URL for package downloads.")
    parser.add_argument("--sdk16", type=Path, default=ROOT / "Resources/SDK")
    parser.add_argument("--sdk26", type=Path, default=ROOT / "LocalSDKs/iPhoneOS26.0.sdk")
    args = parser.parse_args()
    if args.sdk_packages_only:
        print(export_sdk_packages(args, ROOT / "build/sdk-packages"))
        return
    compiler_source()
    if args.check:
        print("PASS: standalone compiler source. One IPA embeds compiler frameworks; SDK and header resources are optional.")
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
    module = frameworks / "PBCompiler.framework"
    module.mkdir()
    module_info = {
        "CFBundleExecutable":"PBCompiler", "CFBundleIdentifier":"com.qiu7c.pocketbuild.compiler",
        "CFBundleName":"PBCompiler", "CFBundlePackageType":"FMWK",
        "CFBundleShortVersionString":VERSION, "CFBundleVersion":BUILD_NUMBER, "MinimumOSVersion":"15.0",
    }
    (module / "Info.plist").write_bytes(plistlib.dumps(module_info))
    compiler_sources = [
        ROOT / "App/CompilerCore.m",
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

    commands = {name:[framework + ".framework/" + framework,"main","","no"]
                for name,framework in (("clang","clang"),("ld64.lld","lld"))}
    # ios_system bootstraps from the main bundle before merging the optional command list.
    (app / "commandDictionary.plist").write_bytes(plistlib.dumps({}))
    (app / "extraCommandsDictionary.plist").write_bytes(plistlib.dumps(commands))

    if args.packages:
        output = build / "packages"
        output.mkdir(exist_ok=True)
        support = build / "support"
        if support.exists():
            support.resolve().relative_to((ROOT / "build").resolve())
            shutil.rmtree(support)
        support.mkdir()
        for name in ("logos", "Include", "ClangInclude", "Perl", "VendorFrameworks", "CompatibilityRules", "SampleProject"):
            shutil.copytree(ROOT / "Resources" / name, support / name)
        for name,value in (("commands.plist",commands),("extraCommandsDictionary.plist",commands),("commandDictionary.plist",{})):
            (support / name).write_bytes(plistlib.dumps(value))
        entry = package_entry(output, args.package_base_url, "support", "Logos、Clang 头文件和构建资源", support)
        export_sdk_packages(args, output, (entry,))

    shutil.copytree(ROOT / "Resources/BuildWeb", app / "BuildWeb")
    shutil.copy2(ROOT / "Resources/PocketBuild/Assets.xcassets/AppIcon.appiconset/icon-120.png", app / "BuildWeb/brand.png")
    shutil.copytree(ROOT / "Resources/AppTemplate", app / "AppTemplate")
    shutil.copy2(ROOT / "Resources/PocketBuild/PocketBuild-icon-square.png", app / "BrandMark.png")
    shutil.copy2(ROOT / "Resources/PocketBuild/PackageCatalog.json", app / "PackageCatalog.json")
    notices = app / "ThirdPartyNotices"
    notices.mkdir()
    for filename in ("LICENSE", "COPYRIGHT", "THIRD_PARTY_NOTICES.md"):
        shutil.copy2(ROOT / filename, notices / filename)
    if (ROOT / "Resources/ThirdPartyNotices").is_dir():
        shutil.copytree(ROOT / "Resources/ThirdPartyNotices", notices, dirs_exist_ok=True)
    sources = [ROOT / "App" / name for name in (
        "BuildOnly/BuildHome.m", "BuildOnly/ToolsHome.m", "BuildOnly/BuildService.m", "BuildOnly/Toolchains.m",
        "BuildOnly/ScreenAwake.m", "BuildOnly/Appearance.m", "BuildOnly/ConnectionSettings.m", "BuildOnly/Welcome.m",
        "BuildOnly/Workspace.m", "BuildOnly/BuildRecords.m", "BuildOnly/BuildBackground.m",
        "BuildOnly/SettingsHome.m", "BuildOnly/StoragePage.m",
        "BuildOnly/ProjectRecords.m", "BuildOnly/ConnectionDiagnostics.m", "BuildOnly/SourceEditor.m",
        "BuildOnly/SDKResources.m", "DebPackage.m", "OutputNaming.m",
        "Remote/DXRemoteHTTP.m", "ArchiveImport.m", "TheosMakefile.m",
    )]
    simulated = []
    if args.simulator:
        entitlements = build / "simulated-entitlements.plist"
        entitlements.write_bytes(plistlib.dumps({
            "application-identifier":"PBLOCAL01.com.qiu7c.pocketbuild",
            "keychain-access-groups":["PBLOCAL01.com.qiu7c.pocketbuild"],
        }))
        simulated = ["-Xlinker","-sectcreate","-Xlinker","__TEXT","-Xlinker","__entitlements","-Xlinker",str(entitlements)]
    subprocess.run(common + simulated + ["-framework","AVFAudio", *map(str,sources), "-o", str(app / "PocketBuild")],check=True)
    icons_info = build / "icons-info.plist"
    subprocess.run([
        "xcrun","actool","--compile",str(app),"--platform",platform,"--minimum-deployment-target","15.0",
        "--app-icon","AppIcon","--target-device","iphone","--target-device","ipad",
        "--output-partial-info-plist",str(icons_info),str(ROOT / "Resources/PocketBuild/Assets.xcassets"),
    ],check=True)
    info = {
        "CFBundleExecutable":"PocketBuild", "CFBundleIdentifier":"com.qiu7c.pocketbuild",
        "CFBundleName":"PocketBuild", "CFBundleDisplayName":"PocketBuild", "CFBundlePackageType":"APPL",
        "CFBundleDevelopmentRegion":"zh_CN", "CFBundleLocalizations":["zh-Hans"],
        "CFBundleShortVersionString":VERSION, "CFBundleVersion":BUILD_NUMBER, "MinimumOSVersion":"15.0",
        "CFBundleSupportedPlatforms":["iPhoneSimulator" if args.simulator else "iPhoneOS"],
        "UIDeviceFamily":[1,2], "UILaunchScreen":{}, "UIFileSharingEnabled":True,
        "UIBackgroundModes":["audio"],
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
