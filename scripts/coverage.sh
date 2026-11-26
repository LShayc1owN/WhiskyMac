#!/usr/bin/env bash
# Runs the test suite with code coverage, prints a per-file report for the
# app sources and leaves an LCOV export in .build/coverage.lcov. Needs a
# full Xcode toolchain, like `swift test` itself. Run from the repository
# root; CI runs it on every push and archives both outputs.
set -euo pipefail

codecov="$(swift test --show-codecov-path "$@")"
profile_dir="$(dirname "$codecov")"
work="$(mktemp -d "${TMPDIR:-/tmp}/whisk-coverage.XXXXXXXX")"
trap 'rm -f "$work/start" "$work/current.profdata"; rmdir "$work"' EXIT
touch "$work/start"
test_status=0
swift test --enable-code-coverage "$@" || test_status=$?

profdata="$profile_dir/default.profdata"
if (( test_status != 0 )); then
  # SwiftPM can leave only raw profiles after a test failure. Never use a
  # previous run's merged report to explain a failed build or test run.
  profiles=()
  for raw in "$profile_dir"/*.profraw; do
    if [[ -f "$raw" && "$raw" -nt "$work/start" ]]; then profiles+=("$raw"); fi
  done
  if (( ${#profiles[@]} == 0 )); then exit "$test_status"; fi
  profdata="$work/current.profdata"
  xcrun llvm-profdata merge -sparse "${profiles[@]}" -o "$profdata"
  echo "Test command failed ($test_status). Reporting coverage from this run's recorded profiles." >&2
fi
bundle="$(find "$(dirname "$(dirname "$codecov")")" -maxdepth 1 -name '*.xctest' | head -n 1)"
binary="$bundle/Contents/MacOS/$(basename "$bundle" .xctest)"
ignore='(/Tests/|/\.build/)'

xcrun llvm-cov export "$binary" -instr-profile "$profdata" -ignore-filename-regex="$ignore" -format=lcov \
  > .build/coverage.lcov
xcrun llvm-cov report "$binary" -instr-profile "$profdata" -ignore-filename-regex="$ignore" -use-color=false

# The gate measures what a unit test can reach. Four files stay out of
# it because exercising them has side effects no test may have: the
# composition root (status item, timers, global shortcuts), the Carbon
# hot key, the paste simulation that sends ⌘V, and the entry point. They
# are still in the report above.
untestable='AppDelegate\.swift|HotKey\.swift|PasteSimulator\.swift|WhiskyMacMain\.swift'
report="$(xcrun llvm-cov report "$binary" -instr-profile "$profdata" \
  -ignore-filename-regex="(/Tests/|/\.build/|$untestable)" -use-color=false)"
# Both UI generations remain in TOTAL. Show what each runtime exercised.
awk '
  function show(name) {
    if (lines[name]) printf "  %s: %d/%d lines (%.2f%%)\n", name, hit[name], lines[name], 100*hit[name]/lines[name]
  }
  /\.swift[[:space:]]/ {
    name = "Shared"
    if ($0 ~ /App\/UI\/MacOS15\//) name = "macOS 15 UI"
    if ($0 ~ /App\/UI\/MacOS26\//) name = "macOS 26 UI"
    lines[name] += $(NF-5)
    hit[name] += $(NF-5) - $(NF-4)
  }
  END { show("Shared"); show("macOS 15 UI"); show("macOS 26 UI") }
' <<< "$report"
gated="$(awk '$1 == "TOTAL" { print $10 }' <<< "$report" | tr -d '%')"
echo "Coverage gate: ${gated}% of testable lines (minimum ${COVERAGE_MIN:-not set})"
if (( test_status != 0 )); then exit "$test_status"; fi
if [[ -n "${WHISK_COVERAGE_OUTPUT:-}" ]]; then
  printf '%s\n' "$binary" "$profdata" "(/Tests/|/\.build/|$untestable)" > "$WHISK_COVERAGE_OUTPUT/paths.txt"
fi
if [ -n "${COVERAGE_MIN:-}" ]; then
  awk -v got="$gated" -v min="$COVERAGE_MIN" 'BEGIN { exit (got + 0 >= min + 0) ? 0 : 1 }' || {
    echo "Line coverage of the testable code fell under ${COVERAGE_MIN}%." >&2
    exit 1
  }
fi
