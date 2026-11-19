"""Run native simulator screenshots and real Keychain/HTTP pairing checks on macOS."""
import json
from pathlib import Path
import subprocess
import time
import urllib.error
import urllib.request

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / "build/pocketbuild-ui"
BUNDLE = "com.qiu7c.pocketbuild"
CODE = "PocketBuild-Test-1234"
OUT.mkdir(parents=True, exist_ok=True)


def sim(*args, check=True):
    print("simctl", *args, flush=True)
    return subprocess.run(["xcrun", "simctl", *args], check=check, text=True, capture_output=True,
                          timeout=300 if args[0] == "bootstatus" else 120)


devices = json.loads(sim("list", "devices", "available", "--json").stdout)["devices"]
phones = [d for runtime, entries in sorted(devices.items(), reverse=True) if "iOS" in runtime
          for d in entries if d["name"].startswith("iPhone")]
phone = next((d for d in phones if d["name"] == "iPhone 16"), phones[0])
small = next((d for d in phones if "SE" in d["name"]), None)


def boot(device):
    uid = device["udid"]
    sim("boot", uid, check=False)
    sim("bootstatus", uid, "-b")
    sim("status_bar", uid, "override", "--time", "9:41", "--batteryState", "charged", "--batteryLevel", "100")
    sim("install", uid, str(ROOT / "build/pocketbuild-simulator/PocketBuild.app"))
    return uid


def launch(uid, screen, *extra):
    sim("terminate", uid, BUNDLE, check=False)
    result = sim("launch", uid, BUNDLE, "--ui-screen", screen, *extra,
                 "-AppleLanguages", "(zh-Hans)", "-AppleLocale", "zh_CN")
    print(result.stdout.strip(), screen, flush=True)


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
    time.sleep(3)
    sim("io", uid, "screenshot", str(OUT / (name + ".png")))


uid = boot(phone)
sim("ui", uid, "appearance", "light")
for screen in ("intro", "guide", "resources", "pairing", "home", "settings", "tools"):
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
