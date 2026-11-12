#!/usr/bin/env python3
"""Drives the release APK on an Android emulator, the way a person would.

It installs the app on a clean device set to Portuguese, then walks through
the things that matter most and are impossible to check off-device:

  1. the first launch asks for access to the files
  2. "Allow access" opens Android's settings page, and flipping the switch
     there really grants "All files access"
  3. back in the app, the folders show the PDFs on the device
  4. a PDF opens and renders
  5. long-pressing a word shows the Copy menu - in Portuguese, the case that
     used to replace the document with a grey box - and Copy works
  6. another app can hand a PDF over with an "open with" intent

Every step saves a screenshot and prints what is on screen, and the device
log is checked for errors at the end.

    python3 tool/e2e_android.py path/to/app.apk
"""
from __future__ import annotations

import os
import re
import subprocess
import sys
import time
import xml.etree.ElementTree as ET

PACKAGE = "com.toolodfview.app"
ACTIVITY = f"{PACKAGE}/.MainActivity"
SHOT_DIR = os.environ.get("SHOT_DIR", "docs/screenshots")
SAMPLE = "integration_test/assets/sample.pdf"
ON_DEVICE = "/sdcard/Download/Relatorio.pdf"

step_number = 0


def adb(*args: str, check: bool = True, timeout: int = 120) -> str:
    result = subprocess.run(
        ["adb", *args], capture_output=True, timeout=timeout, check=False
    )
    out = result.stdout.decode("utf-8", "replace")
    if check and result.returncode != 0:
        err = result.stderr.decode("utf-8", "replace")
        raise RuntimeError(f"adb {' '.join(args)} failed: {out}{err}")
    return out


def shell(command: str, check: bool = True) -> str:
    return adb("shell", command, check=check)


def log(message: str) -> None:
    print(message, flush=True)


# --- Reading the screen ----------------------------------------------------


def dump() -> ET.Element | None:
    """The accessibility tree of what is on screen, or None if unavailable."""
    shell("uiautomator dump /sdcard/window_dump.xml", check=False)
    xml = adb("exec-out", "cat", "/sdcard/window_dump.xml", check=False)
    start = xml.find("<?xml")
    if start < 0:
        return None
    try:
        return ET.fromstring(xml[start:])
    except ET.ParseError:
        return None


def labelled_nodes(root: ET.Element) -> list[tuple[str, tuple[int, int, int, int], ET.Element]]:
    found = []
    for node in root.iter("node"):
        label = (node.get("text") or node.get("content-desc") or "").strip()
        match = re.match(r"\[(\d+),(\d+)\]\[(\d+),(\d+)\]", node.get("bounds", ""))
        if label and match:
            found.append((label, tuple(int(g) for g in match.groups()), node))
    return found


def on_screen() -> list[str]:
    root = dump()
    return [] if root is None else [label for label, _, _ in labelled_nodes(root)]


def find(text: str, exact: bool = False) -> tuple[int, int, int, int] | None:
    """Bounds of the smallest element labelled [text] (or containing it)."""
    root = dump()
    if root is None:
        return None
    matches = [
        b
        for label, b, _ in labelled_nodes(root)
        if (label == text if exact else text in label)
    ]
    if not matches:
        return None
    return min(matches, key=lambda b: (b[2] - b[0]) * (b[3] - b[1]))


def wait_for(
    text: str, seconds: int = 40, exact: bool = False
) -> tuple[int, int, int, int]:
    deadline = time.time() + seconds
    while time.time() < deadline:
        bounds = find(text, exact)
        if bounds:
            return bounds
        time.sleep(1)
    shot("failure")
    raise AssertionError(
        f'"{text}" never appeared. On screen: {on_screen()}'
    )


def tap(text: str, seconds: int = 40, exact: bool = False) -> None:
    left, top, right, bottom = wait_for(text, seconds, exact)
    shell(f"input tap {(left + right) // 2} {(top + bottom) // 2}")
    time.sleep(1.5)


def shot(name: str) -> None:
    os.makedirs(SHOT_DIR, exist_ok=True)
    path = os.path.join(SHOT_DIR, f"{name}.png")
    png = subprocess.run(
        ["adb", "exec-out", "screencap", "-p"], capture_output=True, timeout=60
    ).stdout
    with open(path, "wb") as out:
        out.write(png)
    try:  # keep the repository small: half-size, optimised
        from PIL import Image

        image = Image.open(path)
        image = image.resize((image.width // 2, image.height // 2), Image.LANCZOS)
        image.convert("RGB").save(path, optimize=True)
    except Exception as error:  # noqa: BLE001 - a full-size shot is fine too
        log(f"  (screenshot kept full size: {error})")


def step(title: str) -> None:
    global step_number
    step_number += 1
    log(f"\n=== {step_number}. {title}")


def done(name: str) -> None:
    shot(f"{step_number:02d}_{name}")
    log(f"  on screen: {on_screen()}")


# --- The walk-through ------------------------------------------------------


def main() -> int:
    apk = sys.argv[1]
    adb("wait-for-device")

    step("Install on a clean device, set to Portuguese")
    adb("uninstall", PACKAGE, check=False)
    adb("install", "-r", apk, timeout=300)
    adb("push", SAMPLE, ON_DEVICE)
    shell(f"cmd locale set-app-locales {PACKAGE} --user 0 --locales pt-PT", check=False)
    shell("logcat -c", check=False)
    size = re.search(r"(\d+)x(\d+)", shell("wm size"))
    width, height = int(size.group(1)), int(size.group(2))
    density = int(re.search(r"(\d+)\s*$", shell("wm density").strip()).group(1)) / 160
    log(f"  screen {width}x{height}, density {density}")
    ops = shell(f"appops get {PACKAGE} MANAGE_EXTERNAL_STORAGE", check=False)
    assert ": allow" not in ops, "storage access must start out denied"

    step("First launch asks for access to the files")
    shell(f"am start -n {ACTIVITY}")
    wait_for("Permita o acesso aos seus PDF", 90)
    done("first_launch")

    step('"Permitir acesso" opens the Android settings page')
    tap("Permitir acesso")
    deadline = time.time() + 30
    focus = ""
    while time.time() < deadline:
        focus = shell("dumpsys window | grep -E 'mCurrentFocus|mFocusedApp'", check=False)
        if "settings" in focus.lower():
            break
        time.sleep(1)
    assert "settings" in focus.lower(), f"Settings did not open; focus: {focus}"
    done("settings_page")

    step("Flipping the switch grants All files access")
    root = dump()
    switch = None
    if root is not None:
        for node in root.iter("node"):
            if "Switch" in node.get("class", "") or node.get("checkable") == "true":
                match = re.match(
                    r"\[(\d+),(\d+)\]\[(\d+),(\d+)\]", node.get("bounds", "")
                )
                if match:
                    switch = tuple(int(g) for g in match.groups())
                    break
    assert switch, f"No switch on the settings page: {on_screen()}"
    shell(f"input tap {(switch[0] + switch[2]) // 2} {(switch[1] + switch[3]) // 2}")
    time.sleep(2)
    ops = shell(f"appops get {PACKAGE} MANAGE_EXTERNAL_STORAGE", check=False)
    log(f"  appops: {ops.strip()}")
    assert ": allow" in ops, "the switch did not grant access"
    done("access_granted_in_settings")

    step("Back in the app, the folders are there")
    shell("input keyevent KEYCODE_BACK")
    wait_for("Todos os PDF do dispositivo")
    done("folders")

    step("The Download folder lists the PDF")
    tap("Download")
    wait_for("Relatorio.pdf")
    done("download_folder")

    step("The PDF opens and renders")
    tap("Relatorio.pdf")
    wait_for("1 / 12", 60)
    time.sleep(4)
    done("pdf_open")

    step("Long-pressing a word shows the Copy menu, in Portuguese")
    title = wait_for("Relatorio.pdf")
    app_bar_bottom = (title[1] + title[3]) / 2 + 32 * density
    margin = 6 * density
    page_width = width - 2 * margin
    page_height = page_width * 842 / 595
    x = int(margin + page_width * 0.40)
    y = int(app_bar_bottom + margin + page_height * 0.241)
    log(f"  long-press at {x},{y}")
    shell(f"input swipe {x} {y} {x} {y} 1200")
    # Exactly "Copiar": the menu item, not the "Copiar texto" toolbar button.
    wait_for("Copiar", 20, exact=True)
    done("copy_menu")

    step("Copy works and the document is still there")
    tap("Copiar", exact=True)
    wait_for("Texto copiado", 15)
    done("text_copied")
    assert find("1 / 12"), "the page indicator disappeared after copying"

    step("The toolbar copies the text of the page")
    time.sleep(4)  # let the previous message leave the screen
    tap("Copiar texto", exact=True)
    tap("Copiar o texto desta página")
    wait_for("Texto da página copiado", 20)
    done("page_text_copied")

    step('Another app can open a PDF with "open with"')
    shell(f"am force-stop {PACKAGE}")
    rows = shell(
        "content query --uri content://media/external/file "
        "--projection _id:_display_name",
        check=False,
    )
    match = re.search(r"_id=(\d+), _display_name=Relatorio\.pdf", rows)
    uri = (
        f"content://media/external/file/{match.group(1)}"
        if match
        else f"file://{ON_DEVICE}"
    )
    log(f"  opening {uri}")
    shell(
        "am start -a android.intent.action.VIEW -t application/pdf "
        f"-d {uri} -n {ACTIVITY}"
    )
    wait_for("1 / 12", 60)
    time.sleep(3)
    done("opened_from_another_app")
    assert not find("Permita o acesso"), "asked for access while opening a file"

    step("The device log is clean")
    logcat = adb("logcat", "-d", check=False)
    problems = [
        line
        for line in logcat.splitlines()
        if "ToolPDF View error" in line
        or f"Process: {PACKAGE}" in line
        or re.search(r"\sE[ /]+flutter\s*[:(]", line)
    ]
    for line in problems[:40]:
        log(f"  {line}")
    assert not problems, f"{len(problems)} error lines in the device log"
    log("  no errors")

    log("\nAll end-to-end checks passed.")
    return 0


if __name__ == "__main__":
    try:
        sys.exit(main())
    except Exception as error:  # noqa: BLE001 - report, then fail the job
        log(f"\nFAILED: {error}")
        try:
            log(f"on screen: {on_screen()}")
            tail = adb("logcat", "-d", "-t", "400", check=False)
            for line in tail.splitlines():
                if "flutter" in line.lower() or PACKAGE in line or "AndroidRuntime" in line:
                    log(f"  log: {line}")
        except Exception:  # noqa: BLE001
            pass
        sys.exit(1)
