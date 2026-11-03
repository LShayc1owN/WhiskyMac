#!/usr/bin/env python3
"""Validate the public locations needed for WhiskyMac binary distribution."""
import json
import pathlib
import sys
from urllib.parse import urlparse

ROOT = pathlib.Path(__file__).resolve().parent.parent
config = json.loads((ROOT / "release-config.json").read_text())
missing = []
for key in ("sourceRepositoryUrl", "supportUrl", "privacyPolicyUrl"):
    value = config.get(key, "")
    parsed = urlparse(value)
    if parsed.scheme != "https" or not parsed.netloc or "nathan-poncet" in parsed.netloc + parsed.path:
        missing.append(key)
if missing:
    sys.exit("Configure your own public HTTPS locations in release-config.json: " + ", ".join(missing))
print("Release locations configured; verify that the URLs are live and host the correct release source.")
