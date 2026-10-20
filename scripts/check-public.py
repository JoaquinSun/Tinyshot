#!/usr/bin/env python3
"""Check Git publication candidates without echoing potentially secret values."""

import argparse
import pathlib
import re
import subprocess
import sys


ROOT = pathlib.Path(__file__).resolve().parent.parent
BLOCKED_PARTS = {
    ".git", ".build", "dist", ".swiftpm", "DerivedData", "xcuserdata",
    ".aws", ".ssh", ".codex", ".agents", ".idea", ".vscode", "__pycache__",
    "Transfers",
}
BLOCKED_SUFFIXES = {
    ".app", ".dsym", ".xcarchive", ".xcuserstate", ".pem", ".key", ".p12",
    ".pfx", ".mobileprovision", ".log", ".crash", ".ips", ".pyc", ".pyo",
}
PATTERNS = (
    ("personal home path", re.compile(rb"/(?:Users|home)/[A-Za-z0-9_.-]+/")),
    ("Windows home path", re.compile(rb"[A-Za-z]:[\\/]+Users[\\/]+[A-Za-z0-9_. -]+[\\/]")),
    ("private key", re.compile(rb"-----BEGIN (?:[A-Z0-9]+ )?PRIVATE KEY-----")),
    ("GitHub token", re.compile(rb"\b(?:gh[pousr]_[A-Za-z0-9]{20,}|github_pat_[A-Za-z0-9_]{20,})\b")),
    ("API key", re.compile(rb"\bsk-(?:proj-|svcacct-)?[A-Za-z0-9_-]{20,}\b")),
    ("AWS access key", re.compile(rb"\b(?:AKIA|ASIA)[A-Z0-9]{16}\b")),
    ("credential in URL", re.compile(rb"https?://[^\s/:@]+:[^\s/@]+@")),
    ("assigned credential", re.compile(
        rb"(?i)\b(?:api[_-]?key|access[_-]?token|client[_-]?secret|password)\b"
        rb"\s*[:=]\s*[\"'](?!YOUR_|EXAMPLE|example|placeholder)[A-Za-z0-9_+/=-]{16,}[\"']")),
)
EMAIL = re.compile(rb"\b[A-Za-z0-9._%+-]+@([A-Za-z0-9.-]+\.[A-Za-z]{2,})\b")


def git(*args):
    return subprocess.check_output(["git", "-C", str(ROOT), *args], stderr=subprocess.PIPE)


def candidates(staged=False):
    if staged:
        entries = git("ls-files", "--stage", "-z").split(b"\0")
        result = []
        for entry in filter(None, entries):
            metadata, raw_path = entry.split(b"\t", 1)
            mode, oid, stage = metadata.split()
            if stage != b"0":
                raise ValueError("Resolve merge conflicts before publishing.")
            path = raw_path.decode("utf-8")
            if mode not in (b"100644", b"100755"):
                raise ValueError(f"Unsupported link or submodule: {path}")
            result.append((path, git("cat-file", "blob", oid.decode()), mode == b"100755"))
        return result

    paths = git("ls-files", "--cached", "--others", "--exclude-standard", "-z").split(b"\0")
    result = []
    for raw_path in sorted(set(filter(None, paths))):
        path = raw_path.decode("utf-8")
        file = ROOT / path
        if file.is_symlink():
            raise ValueError(f"Symbolic links must be reviewed separately: {path}")
        if file.is_file():
            result.append((path, file.read_bytes(), bool(file.stat().st_mode & 0o111)))
    return result


def issues_for(path, data):
    issues = []
    parts = pathlib.PurePosixPath(path).parts
    name = parts[-1]
    if any(part in BLOCKED_PARTS or pathlib.PurePosixPath(part).suffix.lower() in BLOCKED_SUFFIXES
           for part in parts):
        issues.append("generated, local or sensitive file")
    if (name == ".DS_Store" or name.startswith("._") or name == "shelf.json"
            or (name.startswith(".env") and name != ".env.example")):
        issues.append("local metadata, runtime data or environment file")
    if re.match(r"(?:截屏|截图|Screenshot|Screen Shot).*\.(?:png|jpe?g|heic|tiff?|pdf)$", name, re.I):
        issues.append("personal screenshot filename; use a reviewed synthetic asset")
    # Byte scanning also catches paths embedded in binary files.
    for label, pattern in PATTERNS:
        for match in pattern.finditer(data):
            line = data[:match.start()].count(b"\n") + 1
            issues.append(f"{label} at line {line}")
    for match in EMAIL.finditer(data):
        domain = match.group(1).lower()
        if domain in (b"example.com", b"example.org", b"example.net"):
            continue
        # Retina icon filenames resemble email addresses.
        if re.fullmatch(rb"\d+x\.(?:png|jpg|jpeg|webp)", domain):
            continue
        line = data[:match.start()].count(b"\n") + 1
        issues.append(f"email address requires privacy review at line {line}")
    return issues


def audit(files):
    if not files:
        raise ValueError("No publication candidates. Stage the source files first.")
    problems = [(path, issue) for path, data, _ in files for issue in issues_for(path, data)]
    for path, issue in problems:
        print(f"FAIL {path}: {issue}", file=sys.stderr)
    if problems:
        raise ValueError(f"Publication check failed: {len(problems)} finding(s).")
    print(f"Publication check passed: {len(files)} files. Review image contents manually.")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--staged", action="store_true", help="scan exact Git index content")
    args = parser.parse_args()
    try:
        audit(candidates(args.staged))
    except (OSError, ValueError, subprocess.CalledProcessError) as error:
        # Do not print subprocess output: it may include local or secret values.
        message = str(error) if isinstance(error, ValueError) else "Could not read Git publication candidates."
        print(message, file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
