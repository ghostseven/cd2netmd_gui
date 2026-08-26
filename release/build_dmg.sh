#!/usr/bin/env bash

set -euo pipefail

APP_NAME="NetMD Wizard"

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

APP_PATH="${SCRIPT_DIR}/netmd_wizard_mac_/${APP_NAME}.app"
BACKGROUND="${SCRIPT_DIR}/assets/dmg-background.tiff"

DIST_DIR="${SCRIPT_DIR}/dist"
STAGING_DIR="${SCRIPT_DIR}/build/dmg-staging"

DMG_TEMP="${DIST_DIR}/${APP_NAME}-temp.dmg"
DMG_FINAL="${DIST_DIR}/${APP_NAME}.dmg"

VOLUME_NAME="${APP_NAME}"

WINDOW_WIDTH=660
WINDOW_HEIGHT=400

APP_X=170
APP_Y=200

APPLICATIONS_X=490
APPLICATIONS_Y=200

echo "==> Creating DMG for ${APP_NAME}"

if [ ! -d "$APP_PATH" ]; then
    echo "ERROR: Application not found:"
    echo "       $APP_PATH"
    exit 1
fi

if [ ! -f "$BACKGROUND" ]; then
    echo "ERROR: Background image not found:"
    echo "       $BACKGROUND"
    exit 1
fi

rm -rf "$STAGING_DIR"
rm -f "$DMG_TEMP"
rm -f "$DMG_FINAL"

mkdir -p "$STAGING_DIR"
mkdir -p "$DIST_DIR"

echo "==> Preparing contents"

ditto "$APP_PATH" "${STAGING_DIR}/${APP_NAME}.app"

ln -s /Applications "${STAGING_DIR}/Applications"

mkdir -p "${STAGING_DIR}/.background"
cp "$BACKGROUND" "${STAGING_DIR}/.background/background.tiff"

echo "==> Creating temporary writable DMG"

hdiutil create \
    -volname "$VOLUME_NAME" \
    -srcfolder "$STAGING_DIR" \
    -ov \
    -format UDRW \
    "$DMG_TEMP"

echo "==> Mounting DMG"

MOUNT_OUTPUT=$(hdiutil attach \
    -readwrite \
    -noverify \
    -noautoopen \
    "$DMG_TEMP")

DEVICE=$(echo "$MOUNT_OUTPUT" | grep '^/dev/' | head -1 | awk '{print $1}')
MOUNT_DIR="/Volumes/${VOLUME_NAME}"

echo "==> Configuring Finder layout"

osascript <<EOF
tell application "Finder"

    tell disk "${VOLUME_NAME}"

        open

        set current view of container window to icon view

        set toolbar visible of container window to false
        set statusbar visible of container window to false

        set bounds of container window to {100, 100, $((100 + WINDOW_WIDTH)), $((100 + WINDOW_HEIGHT))}

        set viewOptions to the icon view options of container window

        set arrangement of viewOptions to not arranged
        set icon size of viewOptions to 96
        set text size of viewOptions to 13

        set background picture of viewOptions to file ".background:background.tiff"

        set position of item "${APP_NAME}.app" of container window to {$APP_X, $APP_Y}
        set position of item "Applications" of container window to {$APPLICATIONS_X, $APPLICATIONS_Y}

        close

        open

        update without registering applications

        delay 2

    end tell

end tell
EOF

echo "==> Saving Finder metadata"

sync
sleep 2

echo "==> Unmounting"

hdiutil detach "$DEVICE"

echo "==> Compressing final DMG"

hdiutil convert \
    "$DMG_TEMP" \
    -format UDZO \
    -imagekey zlib-level=9 \
    -o "$DMG_FINAL"

rm -f "$DMG_TEMP"
rm -rf "$STAGING_DIR"

echo
echo "========================================"
echo "DMG created successfully"
echo
echo "$DMG_FINAL"
echo "========================================"