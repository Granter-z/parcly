#!/usr/bin/env python3
"""P45 reproducibility gate: exact SDK, matching Dart cache and unchanged lock."""
import hashlib
import json
import os
from pathlib import Path
import subprocess
import sys

REVISION = "00b0c91f06209d9e4a41f71b7a512d6eb3b9c694"
LOCK_SHA256 = "956981f554bb63318109639552c683a032bf3764583c70e0d6879e7f68bc7383"
root = Path(__file__).resolve().parents[1]
flutter = os.environ.get("FLUTTER_BIN", "flutter")
try:
    sdk = json.loads(subprocess.check_output([flutter, "--version", "--machine"], text=True))
    assert sdk["frameworkVersion"] == "3.41.9", sdk
    assert sdk["frameworkRevision"] == REVISION, sdk
    assert sdk["dartSdkVersion"].split()[0] == "3.11.5", sdk
    assert sdk["engineRevision"] == "42d3d75a56efe1a2e9902f52dc8006099c45d937", sdk
    cache = Path(sdk["flutterRoot"]) / "bin/cache"
    for stamp in ["engine.stamp", "engine-dart-sdk.stamp"]:
        assert (cache / stamp).read_text().strip() == sdk["engineRevision"], stamp
    dart = Path(sdk["flutterRoot"]) / "bin/cache/dart-sdk/bin/dart"
    actual_dart = subprocess.check_output([str(dart), "--version"], text=True, stderr=subprocess.STDOUT)
    assert "Dart SDK version: 3.11.5 " in actual_dart, actual_dart
    metadata = (root / ".metadata").read_text()
    assert 'revision: "' + REVISION + '"' in metadata, "Project metadata revision differs"
    actual_lock = hashlib.sha256((root / "pubspec.lock").read_bytes()).hexdigest()
    assert actual_lock == LOCK_SHA256, "Original lock changed: " + actual_lock
except (AssertionError, OSError, subprocess.CalledProcessError, ValueError, KeyError) as error:
    sys.exit("P45 toolchain gate FAILED: " + str(error))
print(json.dumps({"flutter": sdk["frameworkVersion"], "revision": sdk["frameworkRevision"],
                  "dart": actual_dart.strip(), "root": sdk["flutterRoot"], "lock_sha256": actual_lock}, indent=2))
