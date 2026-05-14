#!/bin/bash
# Fast everyday deploy: ad-hoc-signed Release build → /Applications → launch.
# No Apple round-trip. Suitable for THIS Mac only — Gatekeeper on another
# machine will block the binary with no Open button.
#
# To distribute to anyone else, use ./scripts/release.sh which does the
# Developer ID + notarize + staple pipeline. That round-trip is per-build
# (~5-15 min each); reserve it for actual handoffs.
#
# Override the defaults via env vars: SCHEME, CONFIG. Use CONFIG=Debug if
# you want a debuggable build at /Applications (slower runtime, larger
# binary, but symbols are useful for crashes).

set -euo pipefail

SCHEME="${SCHEME:-FlashcardsPortuges}"
CONFIG="${CONFIG:-Release}"
PROJECT="FlashcardsPortuges.xcodeproj"
# Share derived data with launch.sh so SPM package checkouts +
# compiled intermediates are reused across Debug (launch.sh) and
# Release (deploy.sh) runs. First-ever build still has to compile
# everything; subsequent runs are incremental in tens of seconds.
DERIVED="$(pwd)/.build/derived"
APP_PATH="$DERIVED/Build/Products/$CONFIG/$SCHEME.app"
INSTALL_PATH="/Applications/$SCHEME.app"

echo "▸ Regenerating Xcode project from project.yml…"
xcodegen generate >/dev/null

echo "▸ Building $SCHEME ($CONFIG, ad-hoc signed)…"
xcodebuild \
    -project "$PROJECT" \
    -scheme "$SCHEME" \
    -configuration "$CONFIG" \
    -derivedDataPath "$DERIVED" \
    -skipMacroValidation \
    -skipPackagePluginValidation \
    CODE_SIGN_STYLE=Automatic \
    CODE_SIGN_IDENTITY="-" \
    -quiet \
    build

if [[ ! -d "$APP_PATH" ]]; then
    echo "ERROR: Build did not produce $APP_PATH" >&2
    exit 1
fi

echo "▸ Quitting any running instance…"
osascript -e "tell application \"$SCHEME\" to quit" 2>/dev/null || true
sleep 1
pkill -x "$SCHEME" 2>/dev/null || true
sleep 1

echo "▸ Installing to $INSTALL_PATH (clean overwrite)…"
rm -rf "$INSTALL_PATH"
/usr/bin/ditto "$APP_PATH" "$INSTALL_PATH"

echo "▸ Ad-hoc re-signing in place…"
codesign --force --deep --sign - "$INSTALL_PATH" 2>&1 | tail -2

echo "▸ Verifying signature…"
codesign --verify --deep --strict --verbose=2 "$INSTALL_PATH" 2>&1 | tail -2

echo "▸ Launching…"
open "$INSTALL_PATH"

echo
echo "✓ Deployed (ad-hoc, not notarized)."
echo "  Good for this Mac. To hand to anyone else:"
echo "    DEVELOPMENT_TEAM=4HK2NGRWKW NOTARY_PROFILE=NOTARY_FLASHCARDS ./scripts/release.sh"
