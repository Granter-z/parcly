#!/usr/bin/env python3
"""Scan the public tree for real-looking phones, waybills, and pickup codes.

Prints only path:line and rule names. Never prints the matched text.

Synthetic exceptions are either an exact allowlist entry or a tightly
limited demo pattern (all-same digits, leading-zero padding with a short
suffix, wholly monotonic digits, or a very short pickup placeholder).
Unique-digit counts and local sequential windows are not proof of a
synthetic token.
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
    "__pycache__",
}
DEFAULT_ROOTS = ("test", "docs", "lib", "README.md", "CLAUDE.md")

# Optional ASCII space, hyphen, or dot between digits after the leading 13x.
PHONE_RE = re.compile(
    r"(^|[^0-9])(?:(?:\+|＋)?86[ .-]?)?1[3-9][0-9](?:[ .-]?[0-9]){8}([^0-9]|$)"
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
    "JD",
)
# Prefix plus 8–18 digits, optional hyphens between prefix and digit groups.
# 不能用 \b：Python 的 Unicode \b 把中文当 word 字符，
# 「运单号JT...」「取件码3-5-6036请领取」这类中文紧贴的写法会漏检。
# 这里用 ASCII 标识符边界，中文相邻仍能命中。
_ASCII_ID_BOUNDARY = r"A-Za-z0-9_"
WAYBILL_RE = re.compile(
    r"(?<![%s])(?:%s)(?:-?\d){8,18}(?![%s])"
    % (_ASCII_ID_BOUNDARY, "|".join(WAYBILL_PREFIXES), _ASCII_ID_BOUNDARY),
    re.IGNORECASE,
)
PICKUP_RE = re.compile(
    r"(?<![%s])\d{1,2}-\d{1,2}-\d{1,6}(?![%s])"
    % (_ASCII_ID_BOUNDARY, _ASCII_ID_BOUNDARY)
)


def load_allowlist() -> set[str]:
    tokens: set[str] = set()
    if not ALLOWLIST_PATH.is_file():
        return tokens
    for raw in ALLOWLIST_PATH.read_text(encoding="utf-8").splitlines():
        line = raw.strip()
        if not line or line.startswith("#"):
            continue
        tokens.add(normalize_token(line))
    return tokens


def normalize_token(value: str) -> str:
    return re.sub(r"[^a-z0-9]", "", value.lower())


def digits_of(value: str) -> str:
    return re.sub(r"\D", "", value)


def is_all_same_digits(digits: str) -> bool:
    return len(digits) >= 3 and len(set(digits)) == 1


def is_leading_zero_demo(digits: str) -> bool:
    """All zeros, or a long zero pad plus at most two final non-zero digits."""
    return bool(re.fullmatch(r"0+[1-9]{0,2}", digits)) and len(digits) >= 3


def is_wholly_sequential(digits: str) -> bool:
    """The whole digit string, or the whole string after leading zeros, is ±1.

    A wrap from 9 to 0 (or 0 to 9) is allowed only when it applies to the
    entire remainder. Local sequential windows are not accepted.
    """
    candidates = [digits]
    stripped = digits.lstrip("0")
    if stripped and stripped != digits:
        candidates.append(stripped)
    for text in candidates:
        if len(text) < 4:
            continue
        if all((int(a) + 1) % 10 == int(b) for a, b in zip(text, text[1:])):
            return True
        if all((int(a) - 1) % 10 == int(b) for a, b in zip(text, text[1:])):
            return True
    return False


def is_short_pickup_placeholder(value: str) -> bool:
    parts = value.split("-")
    if len(parts) != 3:
        return False
    if not all(part.isdigit() for part in parts):
        return False
    if len(parts[-1]) != 1:
        return False
    if any(len(part) > 2 for part in parts):
        return False
    return sum(len(part) for part in parts) <= 5


def is_clear_calendar_date(value: str) -> bool:
    """US/EU dates where one component cannot be a month, and the year is 19xx/20xx.

    Forms where both leading groups are 1–12 remain ambiguous with pickup
    codes (e.g. 11-4-2015) and are still treated as potential pickup codes.
    """
    parts = value.split("-")
    if len(parts) != 3:
        return False
    month_or_day, other, year_s = parts
    if not re.fullmatch(r"(?:19|20)\d{2}", year_s):
        return False
    try:
        a = int(month_or_day)
        b = int(other)
    except ValueError:
        return False
    if 1 <= a <= 12 and 13 <= b <= 31:
        return True
    if 13 <= a <= 31 and 1 <= b <= 12:
        return True
    return False


def is_synthetic_waybill(value: str) -> bool:
    digits = digits_of(value)
    if not digits:
        return False
    return is_all_same_digits(digits) or is_leading_zero_demo(digits) or is_wholly_sequential(digits)


def is_synthetic_pickup(value: str) -> bool:
    digits = digits_of(value)
    if not digits:
        return False
    if is_all_same_digits(digits) or is_wholly_sequential(digits) or is_short_pickup_placeholder(value):
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
        try:
            rel = path.resolve().relative_to(REPO).as_posix()
        except ValueError:
            rel = str(path)
        for lineno, line in enumerate(lines, 1):
            if PHONE_RE.search(line):
                hits.append((rel, lineno, "phone"))
            for match in WAYBILL_RE.finditer(line):
                token = match.group(0)
                if normalize_token(token) in allowlist or is_synthetic_waybill(token):
                    continue
                hits.append((rel, lineno, "waybill"))
            for match in PICKUP_RE.finditer(line):
                token = match.group(0)
                if is_clear_calendar_date(token):
                    continue
                if normalize_token(token) in allowlist or is_synthetic_pickup(token):
                    continue
                hits.append((rel, lineno, "pickup_code"))
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
