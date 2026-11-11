#!/usr/bin/env python3
"""Refresh symbol identifiers from the installed SF Symbols metadata (no artwork)."""
import plistlib
from pathlib import Path

root = Path(__file__).resolve().parent.parent
metadata = Path("/Applications/SF Symbols.app/Contents/Resources/Metadata/name_availability.plist")
names = set(plistlib.loads(metadata.read_bytes())["symbols"])
system = Path("/System/Library/CoreServices/CoreGlyphs.bundle/Contents/Resources/symbol_order.plist")
names.update(plistlib.loads(system.read_bytes()))
output = root / "Sources/Whisk/Resources/SFSymbolNames.txt"
output.write_text("\n".join(sorted(names)) + "\n", encoding="utf-8")
print(f"Saved {len(names)} symbol names")
