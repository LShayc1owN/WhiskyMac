#!/usr/bin/env bash
# Compile the Xcode catalog into the resources consumed by native SwiftPM.
set -euo pipefail

MODE="${1:-check}"
case "$MODE" in
  generate|check) ;;
  *) echo "usage: $0 generate|check" >&2; exit 2 ;;
esac

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
RESOURCES="$ROOT/Sources/Whisk/Resources"
COMPILED="$(mktemp -d "${TMPDIR:-/tmp}/whisky-localizations.XXXXXX")"
trap 'rm -rf "$COMPILED"' EXIT

xcrun xcstringstool compile "$RESOURCES/Localizable.xcstrings" --output-directory "$COMPILED"

STALE=0
for directory in "$COMPILED"/*.lproj; do
  language="$(basename "$directory")"
  for extension in strings stringsdict; do
    generated="$directory/Localizable.$extension"
    committed="$RESOURCES/$language/Localizable.$extension"
    if [ "$MODE" = generate ]; then
      if [ -f "$generated" ]; then
        mkdir -p "$RESOURCES/$language"
        cp "$generated" "$committed"
      elif [ -f "$committed" ]; then
        rm "$committed"
      fi
    elif [ -f "$generated" ] && [ -f "$committed" ]; then
      if ! diff -u "$committed" "$generated"; then STALE=1; fi
    elif [ -f "$generated" ] || [ -f "$committed" ]; then
      echo "Missing or obsolete generated resource: $committed" >&2
      STALE=1
    fi
  done
done

# A language removed from the catalog must not remain available at runtime.
for directory in "$RESOURCES"/*.lproj; do
  language="$(basename "$directory")"
  if [ ! -d "$COMPILED/$language" ]; then
    for extension in strings stringsdict; do
      committed="$directory/Localizable.$extension"
      if [ -f "$committed" ]; then
        if [ "$MODE" = generate ]; then
          rm "$committed"
        else
          echo "Obsolete generated resource: $committed" >&2
          STALE=1
        fi
      fi
    done
  fi
done

if [ "$STALE" != 0 ]; then
  echo "Run ./scripts/localizations.sh generate and commit the generated resources." >&2
  exit 1
fi
echo "Localizations: $MODE passed."
