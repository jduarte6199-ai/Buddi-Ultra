#!/bin/bash
#
# Build Buddi Ultra from source and install it to /Applications.
# Requirements: macOS 14+, Xcode (App Store, free). First run of Xcode
# must have accepted the license (open Xcode once, or `sudo xcodebuild -license`).
#
# Usage: ./install.sh
#
set -euo pipefail
cd "$(dirname "$0")"

echo "Building Buddi (Release)..."
xcodebuild -project buddi.xcodeproj -scheme buddi -configuration Release build \
    CODE_SIGN_STYLE=Manual CODE_SIGN_IDENTITY="-" CODE_SIGNING_REQUIRED=NO \
    DEVELOPMENT_TEAM="" -quiet

APP=$(ls -d ~/Library/Developer/Xcode/DerivedData/buddi-*/Build/Products/Release/buddi.app 2>/dev/null | head -1)
if [ -z "$APP" ]; then
    echo "Build output not found." >&2
    exit 1
fi

# Consistent ad-hoc signature across the bundle (mixed signatures crash at launch).
codesign --force --deep -s - "$APP"

echo "Installing to /Applications..."
osascript -e 'tell application "buddi" to quit' 2>/dev/null || true
sleep 1
rm -rf /Applications/buddi.app
ditto "$APP" /Applications/buddi.app

open /Applications/buddi.app
echo "Done. Buddi is running from /Applications/buddi.app."
echo "Building locally means no Gatekeeper 'damaged app' issues."
