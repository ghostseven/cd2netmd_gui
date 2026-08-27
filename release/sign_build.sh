#!/usr/bin/env bash

cd "$(cd "$(dirname "$0")" && pwd)/netmd_wizard_mac_/NetMD Wizard.app"

# Remove any stale signature data to start clean
find . -name "_CodeSignature" -type d -exec rm -rf {} + 2>/dev/null
find . -name "*.DS_Store" -delete 2>/dev/null

# Sign every dylib in Frameworks/ (including Qt's own, which macdeployqt already signed once, but re-sign to be safe since order matters)
find Contents/Frameworks -name "*.dylib" -exec codesign --force --sign - {} \;

# Sign Qt .framework bundles (each is its own nested bundle)
find Contents/Frameworks -maxdepth 1 -name "*.framework" -exec codesign --force --deep --sign - {} \;

# Sign any PlugIns
find Contents/PlugIns -type f -perm +111 -exec codesign --force --sign - {} \; 2>/dev/null

# Sign the helper binaries
codesign --force --sign - "Contents/MacOS/atracdenc"
codesign --force --sign - "Contents/MacOS/ffmpeg"

# Sign the main executable
codesign --force --sign - "Contents/MacOS/netmd_wizard"

# Sign the whole bundle as a unit — this is the step that actually generates Contents/_CodeSignature/CodeResources
codesign --force --deep --sign - .

#Check this validates, last line will be rejected but that is expected.  
codesign --verify --deep --strict --verbose=4 .
spctl --assess --type execute -v .