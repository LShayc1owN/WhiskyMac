#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SYMBOL_OUTPUT="$(mktemp -d /private/tmp/whisky-symbols.XXXXXX)"
trap 'rm -rf "$SYMBOL_OUTPUT"' EXIT

# SwiftPM's CLI copies resources without compiling asset catalogs.
xcrun actool --compile "$SYMBOL_OUTPUT" --platform macosx \
  --minimum-deployment-target 15.0 --target-device mac \
  "$ROOT/Assets/Symbols/WhiskyMac.xcassets"
cp "$SYMBOL_OUTPUT/Assets.car" "$ROOT/Sources/Whisk/WhiskyMacSymbols.bundle/Contents/Resources/Assets.car"
