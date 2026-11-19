"""macOS check of production App link arguments and IPA packager, using Xcode tools.

This does not run the embedded iOS compiler frameworks or install on a phone.
"""
import json
from pathlib import Path
import plistlib
import shutil
import subprocess
import tempfile
import zipfile

ROOT = Path(__file__).resolve().parents[1]


def main():
    sdk = subprocess.check_output(["xcrun", "--sdk", "iphoneos", "--show-sdk-path"], text=True).strip()
    with tempfile.TemporaryDirectory(prefix="pocketbuild-app-") as temporary:
        folder = Path(temporary)
        project, build = folder / "project", folder / "build"
        shutil.copytree(ROOT / "Resources/AppTemplate", project)
        build.mkdir()
        (project / "assets").mkdir()
        (project / "assets/message.txt").write_text("hello 中文", encoding="utf-8")
        (project / "Main.storyboard").write_text("unsupported fixture")
        (project / "Info.plist").write_bytes(plistlib.dumps({"CFBundleDisplayName": "示例 App"}))
        config = json.loads((project / "MobileCompiler.json").read_text())
        config.update(resources=["assets"], appInfoPlist="Info.plist")
        (project / "MobileCompiler.json").write_text(json.dumps(config))
        tests = folder / "AppTests"
        subprocess.run(["xcrun", "--sdk", "macosx", "clang", "-fobjc-arc", "-fblocks",
                        "-framework", "Foundation", "-larchive", str(ROOT / "tests/PocketBuildAppTests.m"),
                        str(ROOT / "App/BuildOnly/AppBuild.m"), "-o", str(tests)], check=True)
        subprocess.run(["xcrun", "--sdk", "iphoneos", "clang", "-arch", "arm64", "-isysroot", sdk,
                        "-miphoneos-version-min=15.0", "-fobjc-arc", "-c", str(project / "main.m"),
                        "-o", str(build / "main.o")], check=True)
        arguments = json.loads(subprocess.check_output([str(tests), "link", str(project), str(build), sdk], text=True))
        subprocess.run(["xcrun", "--sdk", "iphoneos", "ld", *arguments[1:]], check=True)
        subprocess.run([str(tests), "package", str(project), str(build), sdk], check=True)
        with zipfile.ZipFile(build / "HelloPocket-unsigned.ipa") as ipa:
            prefix = "Payload/HelloPocket.app/"
            metadata = plistlib.loads(ipa.read(prefix + "Info.plist"))
            assert metadata["CFBundleIdentifier"] == "com.example.hellopocket"
            assert metadata["CFBundleDisplayName"] == "示例 App"
            assert ipa.read(prefix + "assets/message.txt").decode("utf-8") == "hello 中文"
            assert ipa.getinfo(prefix + "HelloPocket").external_attr >> 16 & 0o111
            assert prefix + "main.m" not in ipa.namelist()
            assert prefix + "Main.storyboard" not in ipa.namelist()
        print("PASS: generated IPA metadata, executable permissions and resource layout")


if __name__ == "__main__":
    main()
