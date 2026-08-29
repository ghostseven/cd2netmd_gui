#!/bin/bash
# notarize_and_release.sh
#
# Signs every executable/dylib in the .app with a Developer ID identity
# (hardened runtime + secure timestamp), packages a DMG, submits it for
# notarization, and staples the approval ticket to both the .app and DMG.
#
# One-time setup required before running this (see guide):
#   1. A "Developer ID Application" certificate installed in your keychain
#   2. `xcrun notarytool store-credentials <PROFILE_NAME> ...` already run
#
# Usage:
#   ./notarize_and_release.sh <path-to.app> <"Developer ID Application: Name (TEAMID)"> <keychain-profile-name> <dmg-output-name>
#
# Example:
#   ./notarize_and_release.sh \
#       "release/netmd_wizard_mac_2.1.6/NetMD Wizard.app" \
#       "Developer ID Application: Jane Doe (ABCD123456)" \
#       "netmd-wizard-profile" \
#       "NetMD Wizard"

set -euo pipefail

APP_PATH="$1"
SIGN_IDENTITY="$2"
KEYCHAIN_PROFILE="$3"
DMG_NAME="$4"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ENTITLEMENTS="${SCRIPT_DIR}/entitlements.plist"

if [[ ! -d "${APP_PATH}" ]]; then
    echo "error: ${APP_PATH} not found" >&2
    exit 1
fi

if [[ ! -f "${ENTITLEMENTS}" ]]; then
    echo "error: entitlements.plist not found at ${ENTITLEMENTS}" >&2
    exit 1
fi

echo "=== Signing all Mach-O binaries with Developer ID (hardened runtime) ==="

# Sign every dylib and executable found inside the bundle, innermost
# first. --deep is deliberately NOT used on the recursive find pass;
# we want explicit control over every file rather than relying on
# codesign's own (sometimes inconsistent) traversal.

find "${APP_PATH}" -type f \( -name "*.dylib" -o -perm +111 \) ! -path "*/Resources/*" | while read -r f; do
    # Skip non Mach-O files that happen to have the executable bit set
    if file "$f" | grep -q "Mach-O"; then
        echo "Signing: $f"
        codesign --force \
                  --options runtime \
                  --timestamp \
                  --entitlements "${ENTITLEMENTS}" \
                  --sign "${SIGN_IDENTITY}" \
                  "$f"
    fi
done

# Sign framework bundles as units (their own Versions/Current symlink
# structure needs bundle-level signing, not just the inner binary)
find "${APP_PATH}/Contents/Frameworks" -maxdepth 1 -name "*.framework" 2>/dev/null | while read -r fw; do
    echo "Signing framework: $fw"
    codesign --force \
              --options runtime \
              --timestamp \
              --entitlements "${ENTITLEMENTS}" \
              --sign "${SIGN_IDENTITY}" \
              "$fw"
done

echo "=== Signing the app bundle itself ==="
codesign --force \
          --options runtime \
          --timestamp \
          --entitlements "${ENTITLEMENTS}" \
          --sign "${SIGN_IDENTITY}" \
          "${APP_PATH}"

echo "=== Verifying signature ==="
codesign --verify --deep --strict --verbose=4 "${APP_PATH}"
spctl --assess --type execute -v "${APP_PATH}" || echo "(spctl will still say 'rejected' until notarized -- expected at this stage)"

echo "=== Building DMG ==="
DMG_DIR="$(mktemp -d)"
cp -R "${APP_PATH}" "${DMG_DIR}/"
ln -s /Applications "${DMG_DIR}/Applications"
hdiutil create -volname "${DMG_NAME}" \
                -srcfolder "${DMG_DIR}" \
                -ov -format UDZO \
                "${DMG_NAME}.dmg"
rm -rf "${DMG_DIR}"

echo "=== Signing the DMG itself ==="
codesign --force --sign "${SIGN_IDENTITY}" --timestamp "${DMG_NAME}.dmg"

echo "=== Submitting for notarization (this can take a few minutes) ==="
xcrun notarytool submit "${DMG_NAME}.dmg" \
    --keychain-profile "${KEYCHAIN_PROFILE}" \
    --wait

echo "=== Stapling notarization ticket ==="
xcrun stapler staple "${DMG_NAME}.dmg"
xcrun stapler staple "${APP_PATH}"

echo "=== Final verification ==="
spctl --assess --type execute -v "${APP_PATH}"
spctl --assess --type open --context context:primary-signature -v "${DMG_NAME}.dmg"

echo "Done. ${DMG_NAME}.dmg is ready for distribution."
