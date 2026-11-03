#!/usr/bin/env bash
# Packages the Mac App Store variant of Whisk as dist/WhiskyMac.pkg and, on
# request, validates it against App Store Connect or uploads it there,
# where it lands in TestFlight until it is submitted for review.
#   scripts/build-appstore-pkg.sh <version> [validate|upload]
#
# Environment:
#   CODESIGN_IDENTITY     "Apple Distribution: …"; unset signs ad hoc, for a
#                         local check of the package
#   PKG_SIGN_IDENTITY     "3rd Party Mac Developer Installer: …"; unset
#                         leaves the package unsigned (local check only)
#   PROVISIONING_PROFILE  the Mac App Store profile to embed
#   BUILD_NUMBER          CFBundleVersion, higher with every upload
#   ARCH                  native or universal (default)
#   ASC_KEY_ID, ASC_ISSUER_ID, ASC_KEY_P8
#                         App Store Connect API key, for validate/upload
set -euo pipefail

VERSION="${1:?usage: build-appstore-pkg.sh <version> [validate|upload]}"
ACTION="${2:-}"
case "$ACTION" in validate|upload|"") ;; *) echo "unknown action: $ACTION" >&2; exit 2 ;; esac

if [ -n "$ACTION" ]; then
  python3 scripts/check-release-config.py
fi

APP_STORE=1 ./scripts/build-app.sh "$VERSION" "${ARCH:-universal}"

# A store-signed app only launches with the receipt the store adds, so
# the smoke test is for the ad-hoc local build alone.
if [ "${CODESIGN_IDENTITY:--}" = "-" ]; then
  ./dist/WhiskyMac.app/Contents/MacOS/Whisk --smoke-test | grep -q "distribution: appStore"
fi

rm -f dist/WhiskyMac.pkg
SIGN=()
if [ -n "${PKG_SIGN_IDENTITY:-}" ]; then
  SIGN=(--sign "$PKG_SIGN_IDENTITY" --timestamp)
fi
productbuild --component dist/WhiskyMac.app /Applications ${SIGN[@]+"${SIGN[@]}"} dist/WhiskyMac.pkg
pkgutil --check-signature dist/WhiskyMac.pkg | head -3
echo "built dist/WhiskyMac.pkg (version $VERSION, build ${BUILD_NUMBER:-$VERSION})"

if [ -z "$ACTION" ]; then
  exit 0
fi

: "${ASC_KEY_ID:?ASC_KEY_ID missing}" "${ASC_ISSUER_ID:?ASC_ISSUER_ID missing}" "${ASC_KEY_P8:?ASC_KEY_P8 missing}"
# altool finds the key by name under ./private_keys.
mkdir -p private_keys
cp "$ASC_KEY_P8" "private_keys/AuthKey_${ASC_KEY_ID}.p8"
trap 'rm -rf private_keys' EXIT

xcrun altool --validate-app -f dist/WhiskyMac.pkg -t macos --apiKey "$ASC_KEY_ID" --apiIssuer "$ASC_ISSUER_ID"
if [ "$ACTION" = "upload" ]; then
  xcrun altool --upload-app -f dist/WhiskyMac.pkg -t macos --apiKey "$ASC_KEY_ID" --apiIssuer "$ASC_ISSUER_ID"
  echo "uploaded: the build appears in App Store Connect once processed"
fi
