#!/usr/bin/env python3
"""Scan the public tree for real-looking phones, waybills, and pickup codes.

Prints only path:line and rule names. Never prints the matched text.
"""
from __future__ import annotations

import re
import sys
from pathlib import Path

REPO = Path(__file__).resolve().parent.parent
ALLOWLIST_PATH = REPO / "tools" / "pii_allowlist.txt"

TEXT_SUFFIXES = {".dart", ".md", ".txt", ".json", ".yml", ".yaml", ".csv", ".html", ".xml"}
SKIP_DIRS = {
    ".git",
    "build",
    ".dart_tool",
    ".pub-cache",
    ".pub",
    "private",
    "fixtures_private",
    "real_world",
    "pii_check_fixtures",
    ".idea",
    ".vscode",
    "android",
    "ios",
    "plugins",
}
DEFAULT_ROOTS = ("test", "docs", "lib", "README.md", "CLAUDE.md")

PHONE_RE = re.compile(
    r"(^|[^0-9])(?:(?:\+|＋)?86[ -]?)?1[3-9][0-9](?:[ -]?[0-9]){8}([^0-9]|$)"
)
WAYBILL_PREFIXES = (
    "YTO",
    "STO",
    "ZTO",
    "EMS",
    "JT",
    "YT",
    "ST",
    "YD",
    "ZT",
    "SF",
    "HT",
)
WAYBILL_RE = re.compile(
    r"\b(?:%s)\d{8,18}\b" % "|".join(WAYBILL_PREFIXES),
    re.IGNORECASE,
)
PICKUP_RE = re.compile(r"\b\d{1,2}-\d{1,2}-\d{1,6}\b")


def load_allowlist() -> set[str]:
    tokens: set[str] = set()
    if not ALLOWLIST_PATH.is_file():
        return tokens
    for raw in ALLOWLIST_PATH.read_text(encoding="utf-8").splitlines():
        line = raw.strip()
        if not line or line.startswith("#"):
            continue
        tokens.add(line.lower())
    return tokens


def digits_of(value: str) -> str:
    return re.sub(r"\D", "", value)


def is_sequential(digits: str) -> bool:
    candidates = [digits]
    stripped = digits.lstrip("0")
    if stripped and stripped != digits:
        candidates.append(stripped)
    for text in candidates:
        if len(text) < 4:
            continue
        if all(int(b) == int(a) + 1 for a, b in zip(text, text[1:])):
            return True
        if all(int(b) == int(a) - 1 for a, b in zip(text, text[1:])):
            return True
    # Any window of 8+ digits with a constant ±1 step.
    if len(digits) >= 8:
        for step in (1, -1):
            run = 1
            for a, b in zip(digits, digits[1:]):
                if int(b) == int(a) + step:
                    run += 1
                    if run >= 8:
                        return True
                else:
                    run = 1
    return False


def is_repeat_block(digits: str) -> bool:
    if len(digits) < 4:
        return False
    for size in range(1, 5):
        if len(digits) % size == 0 and digits == digits[:size] * (len(digits) // size):
            return True
    return False


def is_synthetic_waybill(value: str) -> bool:
    digits = digits_of(value)
    if not digits:
        return False
    if len(set(digits)) <= 3:
        return True
    if is_sequential(digits) or is_repeat_block(digits):
        return True
    return False


def is_synthetic_pickup(value: str) -> bool:
    digits = digits_of(value)
    parts = value.split("-")
    if len(set(digits)) <= 2:
        return True
    if is_sequential(digits):
        return True
    if len(parts) == 3 and len(parts[-1]) <= 1 and sum(len(part) for part in parts) <= 5:
        return True
    return False


def iter_files(roots: list[Path]) -> list[Path]:
    files: list[Path] = []
    for root in roots:
        if not root.exists():
            continue
        if root.is_file():
            files.append(root)
            continue
        for path in root.rglob("*"):
            if not path.is_file():
                continue
            # Only skip ignored/fixture dirs that appear below the search root.
            # An explicit root inside tools/pii_check_fixtures must still be scanned.
            try:
                rel_parts = path.relative_to(root).parts
            except ValueError:
                rel_parts = path.parts
            if any(part in SKIP_DIRS for part in rel_parts):
                continue
            if path.suffix.lower() not in TEXT_SUFFIXES and path.name not in {
                "README",
                "CLAUDE.md",
            }:
                continue
            files.append(path)
    return files


def collect_hits(files: list[Path], allowlist: set[str]) -> list[tuple[str, int, str]]:
    hits: list[tuple[str, int, str]] = []
    for path in files:
        try:
            lines = path.read_text(encoding="utf-8").splitlines()
        except (UnicodeDecodeError, OSError):
            continue
        rel = path.as_posix()
        try:
            rel = path.resolve().relative_to(REPO).as_posix()
        except ValueError:
            rel = str(path)
        for lineno, line in enumerate(lines, 1):
            if PHONE_RE.search(line):
                hits.append((rel, lineno, "phone"))
            for match in WAYBILL_RE.finditer(line):
                token = match.group(0)
                if token.lower() in allowlist or is_synthetic_waybill(token):
                    continue
                hits.append((rel, lineno, "waybill"))
            for match in PICKUP_RE.finditer(line):
                token = match.group(0)
                if token.lower() in allowlist or is_synthetic_pickup(token):
                    continue
                hits.append((rel, lineno, "pickup_code"))
    # Stable unique rows
    seen: set[tuple[str, int, str]] = set()
    unique: list[tuple[str, int, str]] = []
    for hit in hits:
        if hit in seen:
            continue
        seen.add(hit)
        unique.append(hit)
    return unique


def resolve_roots(args: list[str]) -> list[Path]:
    if args:
        roots: list[Path] = []
        for item in args:
            path = Path(item)
            if not path.is_absolute():
                path = (Path.cwd() / path).resolve()
            roots.append(path)
        return roots
    return [(REPO / item) for item in DEFAULT_ROOTS]


def main(argv: list[str]) -> int:
    allowlist = load_allowlist()
    roots = resolve_roots(argv)
    hits = collect_hits(iter_files(roots), allowlist)
    if hits:
        print("PII check failed")
        for rel, lineno, rule in hits:
            print(f"{rel}:{lineno}  {rule}")
        return 1
    print("OK：未发现未允许的真实形态手机号 / 运单号 / 取件码")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
