#!/usr/bin/env python3
"""Export audited index content with deterministic ZIP metadata, never the whole workspace."""

import pathlib
import plistlib
import re
import runpy
import subprocess
import sys
import zipfile


def main():
    root = pathlib.Path(__file__).resolve().parent.parent
    checker = runpy.run_path(str(root / "scripts/check-public.py"))
    try:
        files = checker["candidates"](staged=True)
        checker["audit"](files)
        contents = {path: data for path, data, _ in files}
        for required in ("LICENSE", "README.md", "Package.swift", "Resources/Info.plist"):
            if required not in contents:
                raise ValueError(f"Required source file missing from index: {required}")
        version = plistlib.loads(contents["Resources/Info.plist"])["CFBundleShortVersionString"]
        if not re.fullmatch(r"[0-9]+(?:\.[0-9]+){1,3}", version):
            raise ValueError("Invalid application version.")
        destination = root / "dist" / f"TinyShot-source-v{version}.zip"
        destination.parent.mkdir(exist_ok=True)
        temporary = destination.with_suffix(".zip.tmp")
        try:
            with zipfile.ZipFile(temporary, "w", compression=zipfile.ZIP_DEFLATED) as archive:
                for path, data, executable in sorted(files):
                    if pathlib.PurePosixPath(path).is_absolute() or ".." in pathlib.PurePosixPath(path).parts:
                        raise ValueError("Unsafe archive path.")
                    info = zipfile.ZipInfo(f"TinyShot/{path}", date_time=(2026, 1, 1, 0, 0, 0))
                    info.create_system = 3
                    info.external_attr = (0o100755 if executable else 0o100644) << 16
                    info.compress_type = zipfile.ZIP_DEFLATED
                    archive.writestr(info, data)
            temporary.replace(destination)
        finally:
            temporary.unlink(missing_ok=True)
        print(f"Exported {len(files)} indexed files: dist/{destination.name}")
    except (OSError, ValueError, KeyError, subprocess.CalledProcessError):
        print("Source export failed. Check the index, publication scan and application version.", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
