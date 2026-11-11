#!/usr/bin/env bash
# Builds dist/WhiskyMac.app.
#   scripts/build-app.sh [version] [native|universal]
#
# Environment:
#   CODESIGN_IDENTITY     signing identity; unset or "-" signs ad hoc
#   APP_STORE=1           the Mac App Store build: App Sandbox entitlements
#                         and the APP_STORE flag (no updater of its own)
#   PROVISIONING_PROFILE  Mac App Store profile to embed; adds the team
#                         entitlements the store requires (APP_STORE only)
#   WHISK_PACKAGE_SUBDIR optional name under dist/; keeps other development builds
#   BUILD_NUMBER          CFBundleVersion; defaults to the version
set -euo pipefail

"$(dirname "${BASH_SOURCE[0]}")/localizations.sh" check

VERSION="${1:-0.0.0}"
ARCH="${2:-native}"
BUNDLE_ID="dev.whisky.maclx"
APP_STORE="${APP_STORE:-0}"

SWIFT_FLAGS=()
if [ "$APP_STORE" = "1" ]; then
  SWIFT_FLAGS=(-Xswiftc -DAPP_STORE)
fi

# --disable-sandbox turns off SwiftPM's own sandbox, which cannot start
# inside Homebrew's build sandbox (sandbox_apply: Operation not permitted).
if [ "$ARCH" = "universal" ]; then
  swift build --disable-sandbox -c release --arch arm64 --arch x86_64 ${SWIFT_FLAGS[@]+"${SWIFT_FLAGS[@]}"}
  BINARY=".build/apple/Products/Release/Whisk"
else
  swift build --disable-sandbox -c release ${SWIFT_FLAGS[@]+"${SWIFT_FLAGS[@]}"}
  BINARY=".build/release/Whisk"
fi

# Only a single child name is accepted; never recursively remove an arbitrary
# caller-provided path. Versioned packaging leaves the running build intact.
PACKAGE_SUBDIR="${WHISK_PACKAGE_SUBDIR:-}"
case "$PACKAGE_SUBDIR" in
  .|..|*[!a-zA-Z0-9._-]*) echo "invalid WHISK_PACKAGE_SUBDIR" >&2; exit 2 ;;
esac
DIST_DIR="dist${PACKAGE_SUBDIR:+/$PACKAGE_SUBDIR}"
APP="$DIST_DIR/WhiskyMac.app"
rm -rf "$DIST_DIR"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BINARY" "$APP/Contents/MacOS/Whisk"
cp Assets/icon.icns "$APP/Contents/Resources/AppIcon.icns"
cp Packaging/PrivacyInfo.xcprivacy "$APP/Contents/Resources/PrivacyInfo.xcprivacy"
mkdir -p "$APP/Contents/Resources/Legal/docs/licenses"
cp LICENSE LICENSE-EXCEPTION-APP-STORE.md LICENSE-EXCEPTION-WHISKYMAC.md NOTICE THIRD_PARTY_NOTICES.md release-config.json \
  "$APP/Contents/Resources/Legal/"
cp docs/licenses/* "$APP/Contents/Resources/Legal/docs/licenses/"

# The SwiftPM resource bundle must ship inside the app: views resolve
# bundled icons from Contents/Resources.
RESOURCE_BUNDLE="$(dirname "$BINARY")/Whisk_Whisk.bundle"
if [ -d "$RESOURCE_BUNDLE" ]; then
  cp -R "$RESOURCE_BUNDLE" "$APP/Contents/Resources/"
  # Some toolchains write a CFBundleExecutable into the resource bundle's
  # plist; App Store validation then looks for that file (ITMS-90261).
  /usr/libexec/PlistBuddy -c "Delete :CFBundleExecutable" \
    "$APP/Contents/Resources/Whisk_Whisk.bundle/Contents/Info.plist" 2>/dev/null || true
else
  echo "error: required resource bundle $RESOURCE_BUNDLE is missing" >&2
  exit 1
fi

# The toolchain stamps App Store uploads expect; absent without Xcode,
# which only the packaged builds need.
DT_KEYS=""
if XCODE_VERSION="$(xcodebuild -version 2>/dev/null)"; then
  SDK_VERSION="$(xcrun --sdk macosx --show-sdk-version)"
  SDK_BUILD="$(xcrun --sdk macosx --show-sdk-build-version)"
  XCODE_NUMBER="$(echo "$XCODE_VERSION" | awk 'NR==1 {split($2, v, "."); printf "%d%d%d", v[1], v[2], v[3] + 0}')"
  XCODE_BUILD="$(echo "$XCODE_VERSION" | awk 'NR==2 {print $3}')"
  DT_KEYS="$(cat <<PLIST
    <key>DTCompiler</key>
    <string>com.apple.compilers.llvm.clang.1_0</string>
    <key>DTPlatformBuild</key>
    <string>${SDK_BUILD}</string>
    <key>DTPlatformName</key>
    <string>macosx</string>
    <key>DTPlatformVersion</key>
    <string>${SDK_VERSION}</string>
    <key>DTSDKBuild</key>
    <string>${SDK_BUILD}</string>
    <key>DTSDKName</key>
    <string>macosx${SDK_VERSION}</string>
    <key>DTXcode</key>
    <string>${XCODE_NUMBER}</string>
    <key>DTXcodeBuild</key>
    <string>${XCODE_BUILD}</string>
    <key>BuildMachineOSBuild</key>
    <string>$(sw_vers -buildVersion)</string>
PLIST
)"
fi

cat > "$APP/Contents/Info.plist" << PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleDevelopmentRegion</key>
    <string>en</string>
    <key>CFBundleLocalizations</key>
    <array>
        <string>en</string>
        <string>fr</string>
        <string>de</string>
        <string>it</string>
        <string>zh-Hans</string>
    </array>
    <key>CFBundleName</key>
    <string>WhiskyMac</string>
    <key>CFBundleDisplayName</key>
    <string>WhiskyMac</string>
    <key>CFBundleIdentifier</key>
    <string>${BUNDLE_ID}</string>
    <key>CFBundleExecutable</key>
    <string>Whisk</string>
    <key>CFBundleIconFile</key>
    <string>AppIcon</string>
    <key>CFBundleInfoDictionaryVersion</key>
    <string>6.0</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>${VERSION}</string>
    <key>CFBundleVersion</key>
    <string>${BUILD_NUMBER:-$VERSION}</string>
    <key>CFBundleSupportedPlatforms</key>
    <array>
        <string>MacOSX</string>
    </array>
    <key>LSApplicationCategoryType</key>
    <string>public.app-category.productivity</string>
    <key>LSMinimumSystemVersion</key>
    <string>15.0</string>
    <key>LSUIElement</key>
    <true/>
    <key>NSPrincipalClass</key>
    <string>NSApplication</string>
    <key>ITSAppUsesNonExemptEncryption</key>
    <false/>
    <key>NSHumanReadableCopyright</key>
    <string>Whisk © 2026 Nathan Poncet and contributors; WhiskyMac modifications © 2026 LinShay (琳曦). GPL-3.0-or-later.</string>
${DT_KEYS}
</dict>
</plist>
PLIST
plutil -lint "$APP/Contents/Info.plist" > /dev/null

# The App Store build is sandboxed. With a provisioning profile at hand
# it also carries the application and team identifiers the store checks
# against that profile; without one, the bare sandbox entitlements let
# the build run locally under an ad-hoc signature, for testing.
SIGN_OPTIONS=()
if [ "$APP_STORE" = "1" ]; then
  ENTITLEMENTS="$DIST_DIR/Whisk.entitlements"
  cp Packaging/AppStore.entitlements "$ENTITLEMENTS"
  if [ -n "${PROVISIONING_PROFILE:-}" ]; then
    cp "$PROVISIONING_PROFILE" "$APP/Contents/embedded.provisionprofile"
    TEAM_ID="$(security cms -D -i "$PROVISIONING_PROFILE" | plutil -extract TeamIdentifier.0 raw -o - -)"
    # PlistBuddy, not plutil: plutil reads the dots as nested keys.
    /usr/libexec/PlistBuddy -c "Add :com.apple.application-identifier string ${TEAM_ID}.${BUNDLE_ID}" "$ENTITLEMENTS"
    /usr/libexec/PlistBuddy -c "Add :com.apple.developer.team-identifier string ${TEAM_ID}" "$ENTITLEMENTS"
  fi
  SIGN_OPTIONS=(--entitlements "$ENTITLEMENTS")
fi

# Ad hoc by default; a real identity (CODESIGN_IDENTITY) signs with the
# hardened runtime and a secure timestamp, as notarization requires. The
# resource bundle is signed on its own first: nested content must be
# signed before the bundle that carries it.
IDENTITY="${CODESIGN_IDENTITY:--}"
# Desktop and File Provider folders re-attach Finder metadata that
# codesign rejects. Sign a clean copy in a temp dir, then place the signed
# app back and archive the clean copy.
SIGN_DIR="$(mktemp -d /private/tmp/whisky-mac-sign.XXXXXX)"
trap 'rm -rf "$SIGN_DIR"' EXIT
ditto --norsrc "$APP" "$SIGN_DIR/WhiskyMac.app"
xattr -cr "$SIGN_DIR/WhiskyMac.app"
if [ "$IDENTITY" = "-" ]; then
  codesign --force --sign - "$SIGN_DIR/WhiskyMac.app/Contents/Resources/Whisk_Whisk.bundle" 2>/dev/null || true
  codesign --force --sign - ${SIGN_OPTIONS[@]+"${SIGN_OPTIONS[@]}"} "$SIGN_DIR/WhiskyMac.app"
else
  codesign --force --timestamp --sign "$IDENTITY" "$SIGN_DIR/WhiskyMac.app/Contents/Resources/Whisk_Whisk.bundle"
  codesign --force --options runtime --timestamp --sign "$IDENTITY" ${SIGN_OPTIONS[@]+"${SIGN_OPTIONS[@]}"} "$SIGN_DIR/WhiskyMac.app"
fi

codesign --verify --deep --strict "$SIGN_DIR/WhiskyMac.app"
rm -rf "$APP"
ditto --norsrc "$SIGN_DIR/WhiskyMac.app" "$APP"
ditto -c -k --norsrc --keepParent "$SIGN_DIR/WhiskyMac.app" "$DIST_DIR/WhiskyMac.zip"
echo "built $APP and $DIST_DIR/WhiskyMac.zip (version $VERSION, build ${BUILD_NUMBER:-$VERSION}, $ARCH, identity: $IDENTITY, app store: $APP_STORE)"
