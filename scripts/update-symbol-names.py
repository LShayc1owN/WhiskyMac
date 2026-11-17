#!/usr/bin/env python3
"""Refresh symbol identifiers from the installed SF Symbols metadata (no artwork)."""
import plistlib
import json
from pathlib import Path

root = Path(__file__).resolve().parent.parent
metadata = Path("/Applications/SF Symbols.app/Contents/Resources/Metadata/name_availability.plist")
availability = plistlib.loads(metadata.read_bytes())
names = set(availability["symbols"])
system = Path("/System/Library/CoreServices/CoreGlyphs.bundle/Contents/Resources/symbol_order.plist")
names.update(plistlib.loads(system.read_bytes()))
output = root / "Sources/Whisk/Resources/SFSymbolNames.txt"
output.write_text("\n".join(sorted(names)) + "\n", encoding="utf-8")
print(f"Saved {len(names)} symbol names")

versions = {name: availability["year_to_release"][release].get("macOS", "99.0")
            for name, release in availability["symbols"].items()}
(root / "Sources/Whisk/Resources/SFSymbolAvailability.json").write_text(
    json.dumps(versions, sort_keys=True, separators=(",", ":")) + "\n")
