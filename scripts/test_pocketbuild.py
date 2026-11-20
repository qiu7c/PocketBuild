"""Regression checks for PocketBuild's one-IPA and optional-resource packaging."""
import importlib.util
import json
from pathlib import Path
import plistlib
import tempfile
import unittest
from unittest.mock import patch
import zipfile

SCRIPT = Path(__file__).with_name("build_buildonly.py")
spec = importlib.util.spec_from_file_location("pocketbuild_build", SCRIPT)
build = importlib.util.module_from_spec(spec)
spec.loader.exec_module(build)


class PocketBuildPackagingTests(unittest.TestCase):
    def test_compiler_extraction(self):
        source = build.compiler_source()
        self.assertIn("PBCompilerFrameworks()", source)
        self.assertIn('PBInstalledPackage(@"support")', source)
        self.assertNotIn("TFAI", source)
        self.assertNotIn("UIApplicationMain", source)
        self.assertTrue(source.rstrip().endswith("@end"))

    def test_one_ipa_embeds_core_and_exports_only_data_packages(self):
        original_root = build.ROOT
        commands = []
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder)
            (root / "App").mkdir()
            (root / "App/main.m").write_text((original_root / "App/main.m").read_text(encoding="utf-8"), encoding="utf-8")
            for name in ("logos", "Include", "ClangInclude", "Perl", "VendorFrameworks", "CompatibilityRules", "SampleProject", "BuildWeb", "AppTemplate"):
                path = root / "Resources" / name
                path.mkdir(parents=True)
                (path / "fixture.txt").write_text(name)
            for name in ("LICENSE", "COPYRIGHT", "THIRD_PARTY_NOTICES.md"):
                (root / name).write_text(name)
            (root / "Resources/PocketBuild").mkdir()
            (root / "Resources/PocketBuild/PocketBuild-icon-square.png").write_bytes(b"brand fixture")
            icons = root / "Resources/PocketBuild/Assets.xcassets/AppIcon.appiconset"
            icons.mkdir(parents=True)
            (icons / "icon-120.png").write_bytes(b"web icon fixture")
            catalog = (original_root / "Resources/PocketBuild/PackageCatalog.json").read_bytes()
            (root / "Resources/PocketBuild/PackageCatalog.json").write_bytes(catalog)
            for name, version in (("Resources/SDK", "16.4"), ("LocalSDKs/iPhoneOS26.0.sdk", "26.0")):
                path = root / name
                path.mkdir(parents=True)
                (path / "SDKSettings.plist").write_bytes(plistlib.dumps({"Version":version}))
            for name in ("ios_system", "libLLVM", "clang", "lld", "perl"):
                bundle = root / "Vendor" / (name + ".xcframework")
                source = bundle / "ios-arm64" / (name + ".framework")
                source.mkdir(parents=True)
                (source / name).write_bytes(b"framework fixture")
                (bundle / "Info.plist").write_bytes(plistlib.dumps({"AvailableLibraries":[{
                    "SupportedPlatform":"ios", "SupportedArchitectures":["arm64"],
                    "LibraryIdentifier":"ios-arm64", "LibraryPath":name + ".framework",
                }]}))

            def apple_tool(command, **kwargs):
                commands.append(command)
                if "clang" in command:
                    target = Path(command[command.index("-o") + 1])
                    target.write_bytes(b"Mach-O fixture")
                if "actool" in command:
                    target = Path(command[command.index("--output-partial-info-plist") + 1])
                    target.write_bytes(plistlib.dumps({"CFBundleIcons": {"CFBundlePrimaryIcon":{"CFBundleIconName":"AppIcon"}}}))
                return None

            with patch.object(build, "ROOT", root), patch("sys.argv", [str(SCRIPT), "--packages"]),                  patch.object(build.subprocess, "check_output", return_value=str(root / "SDK") + "\n"),                  patch.object(build.subprocess, "run", side_effect=apple_tool),                  patch.dict(build.os.environ, {"DYLIX_TOOLCHAIN_ROOT":str(root)}):
                build.main()
            output = root / "build/pocketbuild-device"
            ipas = list(output.glob("*.ipa"))
            self.assertEqual([p.name for p in ipas], ["PocketBuild-0.1.0-unsigned.ipa"])
            with zipfile.ZipFile(ipas[0]) as archive:
                names = archive.namelist()
                for framework in ("PBCompiler", "ios_system", "libLLVM", "clang", "lld", "perl"):
                    self.assertIn("Payload/PocketBuild.app/Frameworks/" + framework + ".framework/" + framework, names)
                self.assertFalse(any("SDK.zip" in name or "SDK26.zip" in name or "ClangInclude/" in name for name in names))
                info = plistlib.loads(archive.read("Payload/PocketBuild.app/Info.plist"))
                self.assertIn("Payload/PocketBuild.app/BrandMark.png", names)
                self.assertEqual(archive.read("Payload/PocketBuild.app/BuildWeb/brand.png"), b"web icon fixture")
                bundled = json.loads(archive.read("Payload/PocketBuild.app/PackageCatalog.json"))
                self.assertEqual({item["id"] for item in bundled["packages"]}, {"support", "sdk16", "sdk26"})
                self.assertTrue(all(item["url"].startswith("https://") for item in bundled["packages"]))
                self.assertEqual(info["CFBundleIdentifier"], "com.qiu7c.pocketbuild")
                self.assertEqual(info["UIBackgroundModes"], ["audio"])
                self.assertEqual(info["CFBundleIcons"]["CFBundlePrimaryIcon"]["CFBundleIconName"], "AppIcon")
                self.assertEqual(plistlib.loads(archive.read("Payload/PocketBuild.app/commandDictionary.plist")), {})
                bootstrap_commands = plistlib.loads(archive.read("Payload/PocketBuild.app/extraCommandsDictionary.plist"))
                self.assertEqual(set(bootstrap_commands), {"clang", "ld64.lld"})
            manifest = json.loads((output / "packages/PocketBuild-packages.json").read_text(encoding="utf-8"))
            self.assertEqual({item["id"] for item in manifest["packages"]}, {"support","sdk16","sdk26"})
            for item in manifest["packages"]:
                self.assertEqual(len(item["sha256"]), 64)
                self.assertTrue((output / "packages" / item["url"]).exists())
            app_command = next(cmd for cmd in commands if "clang" in cmd and "-dynamiclib" not in cmd)
            self.assertFalse(any("/App/AI/" in part.replace("\\", "/") for part in app_command))
            signatures = [cmd[-1] for cmd in commands if cmd[0] == "codesign"]
            self.assertEqual(len(signatures), 7)


if __name__ == "__main__":
    unittest.main()
