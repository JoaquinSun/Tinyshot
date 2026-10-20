#!/usr/bin/env python3
"""Build, strip, sign and audit a universal macOS application ZIP."""

import hashlib
import os
import pathlib
import plistlib
import re
import runpy
import shutil
import subprocess
import sys
import tempfile
import zipfile


ROOT = pathlib.Path(__file__).resolve().parent.parent


def run(*args, capture=False):
    return subprocess.run(args, cwd=ROOT, check=True, text=True,
                          stdout=subprocess.PIPE if capture else None).stdout


def main():
    if sys.platform != "darwin":
        raise ValueError("Application packaging requires macOS.")
    version = plistlib.loads((ROOT / "Resources/Info.plist").read_bytes())["CFBundleShortVersionString"]
    if not re.fullmatch(r"[0-9]+(?:\.[0-9]+){1,3}", version):
        raise ValueError("Invalid application version.")
    os.environ["CLANG_MODULE_CACHE_PATH"] = str(pathlib.Path(tempfile.gettempdir()) / "tinyshot-clang-cache")
    os.environ["SWIFTPM_MODULECACHE_OVERRIDE"] = str(pathlib.Path(tempfile.gettempdir()) / "tinyshot-module-cache")
    binaries = []
    for arch in ("arm64", "x86_64"):
        options = ["swift", "build", "-c", "release", "--disable-sandbox",
                   "--triple", f"{arch}-apple-macosx13.0",
                   "--scratch-path", str(ROOT / ".build/distribution" / arch),
                   "--cache-path", str(ROOT / ".build/cache"),
                   "--config-path", str(ROOT / ".build/config"),
                   "--security-path", str(ROOT / ".build/security"),
                   "--manifest-cache", "local", "-debug-info-format", "none"]
        # Source locations can otherwise survive in optimized Mach-O files.
        for original, replacement in ((str(ROOT), "/src/TinyShot"),
                                      (str(pathlib.Path.home()), "/build-user"),
                                      (str(pathlib.Path(tempfile.gettempdir()).resolve()), "/tmp")):
            options += ["-Xswiftc", "-file-prefix-map", "-Xswiftc", f"{original}={replacement}"]
        print(f"Building {arch} release…", flush=True)
        run(*options)
        directory = run(*options, "--show-bin-path", capture=True).strip()
        binaries.append(str(pathlib.Path(directory) / "TinyShot"))

    output = ROOT / "dist"
    output.mkdir(exist_ok=True)
    destination = output / f"TinyShot-v{version}-universal.zip"
    checker = runpy.run_path(str(ROOT / "scripts/check-public.py"))
    with tempfile.TemporaryDirectory(prefix="tinyshot-release-", dir=output) as temporary:
        payload = pathlib.Path(temporary)
        application = payload / "TinyShot.app"
        executable = application / "Contents/MacOS/TinyShot"
        executable.parent.mkdir(parents=True)
        resources = application / "Contents/Resources"
        resources.mkdir()
        run("xcrun", "lipo", "-create", *binaries, "-output", str(executable))
        run("xcrun", "strip", "-S", "-x", str(executable))
        executable.chmod(0o755)
        shutil.copyfile(ROOT / "Resources/Info.plist", application / "Contents/Info.plist")
        run("swift", "scripts/make-icon.swift", str(payload / "AppIcon.iconset"), str(resources / "AppIcon.icns"))
        # Icon source renders are build intermediates, not release payload.
        shutil.rmtree(payload / "AppIcon.iconset")
        run("codesign", "--force", "--sign", "-", "--timestamp=none", str(application))
        run("codesign", "--verify", "--deep", "--strict", str(application))
        run("xcrun", "lipo", str(executable), "-verify_arch", "arm64", "x86_64")
        shutil.copyfile(ROOT / "LICENSE", payload / "LICENSE")
        (payload / "README.txt").write_text(
            f"TinyShot {version} — macOS 通用版（Apple Silicon / Intel）\n\n"
            "需要 macOS 13 或更新版本；原生 Liquid Glass 需要 macOS 26。\n"
            "将 TinyShot.app 拖入「应用程序」文件夹后打开。\n"
            "此版本为本地签名，尚未经过 Apple 公证。如被 macOS 拦截，\n"
            "在确认下载来源后，到「系统设置 → 隐私与安全性」选择「仍要打开」。\n"
            "首次使用：按 ⇧⌘5 → 选项，关闭「显示浮动缩略图」，并确认截图保存位置。\n\n"
            "默认成功拖放后直接删除原图，不进废纸篓，可在设置中关闭；\n"
            "点击卡片 × 同样直接删除原图，复制和收起不会删除原图。\n\n"
            "源码与说明：https://github.com/JoaquinSun/Tinyshot\n"
            "Apple 打开应用说明：https://support.apple.com/en-us/102445\n",
            encoding="utf-8")
        files = sorted(file for file in payload.rglob("*") if file.is_file())
        for file in files:
            data = file.read_bytes()
            for label, pattern in checker["PATTERNS"]:
                if pattern.search(data):
                    raise ValueError(f"Release privacy scan failed: {file.relative_to(payload)} ({label}).")
            if b"/var/folders/" in data or b"/private/var/folders/" in data:
                raise ValueError(f"Release contains a local temporary path: {file.relative_to(payload)}.")
        pending = destination.with_suffix(".zip.tmp")
        try:
            with zipfile.ZipFile(pending, "w", compression=zipfile.ZIP_DEFLATED) as archive:
                for file in files:
                    info = zipfile.ZipInfo(file.relative_to(payload).as_posix(), (2026, 1, 1, 0, 0, 0))
                    info.create_system = 3
                    info.external_attr = (0o100755 if file == executable else 0o100644) << 16
                    info.compress_type = zipfile.ZIP_DEFLATED
                    archive.writestr(info, file.read_bytes())
            with zipfile.ZipFile(pending) as archive:
                if archive.testzip() is not None:
                    raise ValueError("Release ZIP integrity check failed.")
            pending.replace(destination)
        finally:
            pending.unlink(missing_ok=True)
    digest = hashlib.sha256(destination.read_bytes()).hexdigest()
    (output / "SHA256SUMS.txt").write_text(f"{digest}  {destination.name}\n", encoding="utf-8")
    print(f"Verified universal release: dist/{destination.name}")
    print(f"SHA256: {digest}")


if __name__ == "__main__":
    try:
        main()
    except (OSError, ValueError, KeyError, subprocess.CalledProcessError) as error:
        print(f"Packaging failed: {error}", file=sys.stderr)
        sys.exit(1)
