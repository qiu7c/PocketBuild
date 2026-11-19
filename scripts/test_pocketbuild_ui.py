"""Run native simulator screenshots and real Keychain/HTTP pairing checks on macOS."""
import json
from pathlib import Path
import shutil
import subprocess
import time
import urllib.error
import urllib.request

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / "build/pocketbuild-ui"
BUNDLE = "com.qiu7c.pocketbuild"
CODE = "PocketBuild-Test-1234"
OUT.mkdir(parents=True, exist_ok=True)

# UI/Keychain/HTTP checks never load the compiler. Install the real App executable
# and its compiler facade without copying hundreds of MB of unused LLVM binaries.
# The separate device build verifies the complete IPA and embedded toolchain.
source_app = ROOT / "build/pocketbuild-simulator/PocketBuild.app"
ui_app = ROOT / "build/pocketbuild-ui-install/PocketBuild.app"
shutil.copytree(source_app, ui_app, ignore=shutil.ignore_patterns("Frameworks"), dirs_exist_ok=True)
shutil.copytree(source_app / "Frameworks/PBCompiler.framework", ui_app / "Frameworks/PBCompiler.framework", dirs_exist_ok=True)
subprocess.run(["codesign", "--force", "--sign", "-", str(ui_app)], check=True)


def sim(*args, check=True):
    print("simctl", *args, flush=True)
    return subprocess.run(["xcrun", "simctl", *args], check=check, text=True, capture_output=True,
                          timeout=300 if args[0] == "bootstatus" else 120)


devices = json.loads(sim("list", "devices", "available", "--json").stdout)["devices"]
sdk = subprocess.check_output(["xcrun", "--sdk", "iphonesimulator", "--show-sdk-version"], text=True).strip()
runtime_id = "com.apple.CoreSimulator.SimRuntime.iOS-" + sdk.replace(".", "-")
print("Testing runtime:", runtime_id, flush=True)
phones = [d for runtime, entries in devices.items() if runtime == runtime_id
          for d in entries if d["name"].startswith("iPhone")]
assert phones, "Install the simulator runtime matching the selected Xcode SDK: " + sdk
phone = next((d for d in phones if d["name"] == "iPhone 16"), phones[0])
small = next((d for d in phones if "SE" in d["name"]), None)


def boot(device):
    uid = device["udid"]
    sim("boot", uid, check=False)
    sim("bootstatus", uid, "-b")
    sim("status_bar", uid, "override", "--time", "9:41", "--batteryState", "charged", "--batteryLevel", "100")
    sim("install", uid, str(ui_app))
    return uid


def launch(uid, screen, *extra):
    container = Path(sim("get_app_container", uid, BUNDLE, "data").stdout.strip())
    ready = container / "tmp/pocketbuild-ui-ready.json"
    sim("terminate", uid, BUNDLE, check=False)
    ready.unlink(missing_ok=True)
    result = sim("launch", uid, BUNDLE, "--ui-screen", screen, *extra,
                 "-AppleLanguages", "(zh-Hans)", "-AppleLocale", "zh_CN")
    print(result.stdout.strip(), screen, flush=True)
    deadline = time.monotonic() + 60
    while not ready.exists():
        if time.monotonic() >= deadline:
            sim("io", uid, "screenshot", str(OUT / ("failed-" + screen + ".png")), check=False)
            logs = sim("spawn", uid, "log", "show", "--last", "3m", "--style", "compact",
                       "--predicate", 'process == "PocketBuild"', check=False)
            (OUT / ("failed-" + screen + ".log")).write_text(logs.stdout + logs.stderr, encoding="utf-8")
            for report in (Path.home() / "Library/Logs/DiagnosticReports").glob("PocketBuild*"):
                if report.is_file():
                    shutil.copy2(report, OUT / report.name)
            raise AssertionError("Native screen did not appear: " + screen)
        time.sleep(.1)
    appeared = json.loads(ready.read_text())
    expected = {"intro":"PBWelcomeController", "guide":"PBWelcomeController", "resources":"PBWelcomeController",
                "pairing":"PBWelcomeController", "home":"DXBuildHomeController", "running":"DXBuildHomeController",
                "settings":"PBConnectionController", "tools":"PBToolsController"}[screen]
    assert appeared["controller"] == expected and appeared["width"] > 0, appeared


def request(code, expected=200):
    req = urllib.request.Request("http://127.0.0.1:8787/api/v1/workspace",
                                 data=b'{"action":"device"}',
                                 headers={"Authorization": "Bearer " + code, "Content-Type": "application/json"})
    opener = urllib.request.build_opener(urllib.request.ProxyHandler({}))
    deadline = time.monotonic() + 20
    while True:
        try:
            with opener.open(req, timeout=2) as response:
                assert response.status == expected, response.status
                return json.load(response)
        except urllib.error.HTTPError as error:
            assert error.code == expected, (error.code, error.read())
            return
        except (urllib.error.URLError, TimeoutError):
            if time.monotonic() >= deadline:
                raise
            time.sleep(.25)


def screenshot(uid, name):
    time.sleep(1.2)
    sim("io", uid, "screenshot", str(OUT / (name + ".png")))


uid = boot(phone)
sim("ui", uid, "appearance", "light")
for screen in ("resources", "intro", "guide", "pairing", "home", "settings", "tools"):
    launch(uid, screen)
    screenshot(uid, "light-" + screen)

launch(uid, "running", "--ui-fixed-code", CODE)
assert request(CODE)["name"] == "PocketBuild"
request("wrong-connection-code", expected=401)
screenshot(uid, "light-running")
launch(uid, "running")
assert request(CODE)["name"] == "PocketBuild", "Fixed code must survive application restart"
launch(uid, "running", "--ui-restart-service")
time.sleep(3)
assert request(CODE)["name"] == "PocketBuild", "Fixed code must survive service restart"
launch(uid, "running", "--ui-pairing-check")
time.sleep(3)
assert request("PocketBuild-Test-Next")["name"] == "PocketBuild"
request(CODE, expected=401)
launch(uid, "running", "--ui-random-code")
request("PocketBuild-Test-Next", expected=401)
print("PASS: Keychain persistence, service restart, credential validation, delayed activation and random mode", flush=True)

sim("ui", uid, "appearance", "dark")
for screen in ("intro", "settings", "tools"):
    launch(uid, screen)
    screenshot(uid, "dark-" + screen)
launch(uid, "running", "--ui-fixed-code", CODE)
request(CODE)
screenshot(uid, "dark-running")
sim("terminate", uid, BUNDLE)
if small:
    sim("shutdown", uid)
    uid = boot(small)
    sim("ui", uid, "appearance", "light")
    for screen in ("intro", "pairing", "running"):
        launch(uid, screen, "--ui-fixed-code", CODE)
        screenshot(uid, "small-" + screen)
    sim("terminate", uid, BUNDLE)
(OUT / "result.json").write_text(json.dumps({"phone":phone["name"], "small":small and small["name"],
    "pairing":"passed", "screenshots":len(list(OUT.glob("*.png")))}, indent=2), encoding="utf-8")
print("PASS: native screens captured", flush=True)
