#!/usr/bin/env bash
# Launch the packaged app briefly without clipboard polling or user history.
set -euo pipefail

ARCHIVE="${1:-dist/WhiskyMac.zip}"
VERIFY_DIR="$(mktemp -d /private/tmp/whisk-may-smoke.XXXXXX)"
trap 'rm -rf "$VERIFY_DIR"' EXIT

ditto -x -k "$ARCHIVE" "$VERIFY_DIR"
APP="$VERIFY_DIR/WhiskyMac.app"
codesign --verify --deep --strict "$APP"
test -f "$APP/Contents/Resources/Whisk_Whisk.bundle/en.lproj/Localizable.strings"
OUTPUT="$(WHISK_MAY_DATA_DIR="$VERIFY_DIR/data" "$APP/Contents/MacOS/Whisk" --smoke-test)"
verify_output() {
  local output="$1"
  case "$output" in
    *"smoke test passed (distribution: mayDevelopment, bundle: dev.whisky.maclx)"*) ;;
    *) echo "WhiskyMac smoke test failed: $output" >&2; return 1 ;;
  esac
  local resources
  resources="$(printf '%s\n' "$output" | sed -n 's/^resources: //p')"
  # Foundation may spell /private/tmp as /tmp. Compare file identity.
  if [ ! "$resources" -ef "$APP/Contents/Resources/Whisk_Whisk.bundle" ]; then
    echo "App did not load its own packaged resource bundle: $output" >&2
    return 1
  fi
  printf '%s\n' "$output"
}
verify_output "$OUTPUT"
OUTPUT="$(WHISK_MAY_DATA_DIR="$VERIFY_DIR/preferences-data" "$APP/Contents/MacOS/Whisk" --smoke-test --smoke-preferences)"
verify_output "$OUTPUT"
printf '%s\n' "$OUTPUT" | grep -Fx "preference smoke passed: runtime language, accent, Dock windows and menu mapping"

# Each launch uses fresh preferences and history, including the English fallback.
for language in en fr zh-Hans de it es; do
  case "$language" in
    fr) copy_label="Copier"; count_label="1 élément" ;;
    de) copy_label="Kopieren"; count_label="1 Eintrag" ;;
    it) copy_label="Copia"; count_label="1 elemento" ;;
    zh-Hans) copy_label="拷贝"; count_label="1 项" ;;
    *) copy_label="Copy"; count_label="1 item" ;;
  esac
  OUTPUT="$(WHISK_MAY_DATA_DIR="$VERIFY_DIR/data-$language" "$APP/Contents/MacOS/Whisk" \
    --smoke-test -AppleLanguages "($language)" -AppleLocale "$language")"
  verify_output "$OUTPUT"
  printf '%s\n' "$OUTPUT" | grep -Fx "localized copy: $copy_label"
  printf '%s\n' "$OUTPUT" | grep -Fx "localized count: $count_label"
done

# Optional Finder-equivalent launch through LaunchServices.
if [ "${WHISK_SMOKE_FINDER:-0}" = "1" ]; then
  /usr/bin/open -n -W --stdout "$VERIFY_DIR/finder.stdout" --stderr "$VERIFY_DIR/finder.stderr" \
    --env "WHISK_MAY_DATA_DIR=$VERIFY_DIR/finder-data" "$APP" --args --smoke-test
  verify_output "$(cat "$VERIFY_DIR/finder.stdout")"
fi
