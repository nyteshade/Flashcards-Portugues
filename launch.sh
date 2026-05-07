#!/bin/bash
set -euo pipefail

PRODUCT="FlashcardsPortuges"
SCHEME="FlashcardsPortuges"
CONFIG="Debug"
DERIVED="$(pwd)/.build/derived"

# Regenerate project.pbxproj if project.yml is newer than the project,
# or if any Sources file is newer (XcodeGen has to re-scan to pick up new files).
NEEDS_REGEN=0
if [[ "${REGEN:-0}" == "1" || ! -d "$PRODUCT.xcodeproj" ]]; then
    NEEDS_REGEN=1
elif [[ project.yml -nt "$PRODUCT.xcodeproj/project.pbxproj" ]]; then
    NEEDS_REGEN=1
elif find Sources -name "*.swift" -newer "$PRODUCT.xcodeproj/project.pbxproj" -print -quit | grep -q .; then
    NEEDS_REGEN=1
fi
if [[ "$NEEDS_REGEN" == "1" ]]; then
    echo "Regenerating Xcode project from project.yml…"
    xcodegen generate
fi

xcodebuild \
    -project "$PRODUCT.xcodeproj" \
    -scheme "$SCHEME" \
    -configuration "$CONFIG" \
    -derivedDataPath "$DERIVED" \
    -skipMacroValidation \
    -skipPackagePluginValidation \
    -quiet \
    build

APP_PATH="$DERIVED/Build/Products/$CONFIG/$PRODUCT.app"

if [[ ! -d "$APP_PATH" ]]; then
    echo "Build failed: $APP_PATH not found"
    exit 1
fi

# Reset previous app log
rm -f "$HOME/Library/Application Support/FlashcardsPortuges/log.txt"
rm -f app.log

echo "Launching $APP_PATH"
"$APP_PATH/Contents/MacOS/$PRODUCT" > app.log 2>&1 &

# Give the app a moment to boot
sleep 2

# Mirror the in-app log next to the project for convenience
cp "$HOME/Library/Application Support/FlashcardsPortuges/log.txt" "log.txt" 2>/dev/null || true
