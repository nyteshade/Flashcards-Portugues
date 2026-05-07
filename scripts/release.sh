#!/bin/bash
# Builds a Release .app, signs it with a Developer ID Application
# certificate, and (optionally) submits it for notarization + staples
# the ticket. Designed for "build on Mac A, run on Mac B" hand-off.
#
# Required env vars:
#   DEVELOPMENT_TEAM   — your 10-char Apple Team ID (e.g. ABCD123XYZ)
#
# Optional env vars:
#   NOTARY_PROFILE     — keychain profile from `xcrun notarytool store-credentials`.
#                        If unset, the script signs only and skips notarization.
#                        That's fine for hand-off between your own Macs as long
#                        as both trust the cert; required if you want any other
#                        Mac to open the app without right-click → Open dance.
#   SCHEME             — defaults to FlashcardsPortuges
#   CONFIG             — defaults to Release

set -euo pipefail

SCHEME="${SCHEME:-FlashcardsPortuges}"
CONFIG="${CONFIG:-Release}"
PROJECT="FlashcardsPortuges.xcodeproj"
DERIVED="$(pwd)/.build/release"
APP_PATH="$DERIVED/Build/Products/$CONFIG/$SCHEME.app"
DIST_DIR="$(pwd)/dist"

if [[ -z "${DEVELOPMENT_TEAM:-}" ]]; then
    echo "ERROR: DEVELOPMENT_TEAM env var not set." >&2
    echo "Find yours via: security find-identity -v -p codesigning | grep 'Developer ID Application'" >&2
    exit 1
fi

# 1. Regenerate Xcode project so Release config picks up the entitlements file.
echo "▸ Regenerating Xcode project…"
xcodegen generate >/dev/null

# 2. Build Release. Code signing settings live in project.yml for the app
# target so SPM dependency targets don't try to apply them. We do force
# manual signing here because Developer ID is incompatible with
# CODE_SIGN_STYLE=Automatic. Absolute paths so SPM target build dirs
# resolve them correctly.
ENTITLEMENTS="$(pwd)/FlashcardsPortuges.entitlements"

echo "▸ Building $SCHEME ($CONFIG)…"
xcodebuild \
    -project "$PROJECT" \
    -scheme "$SCHEME" \
    -configuration "$CONFIG" \
    -derivedDataPath "$DERIVED" \
    -skipMacroValidation \
    -skipPackagePluginValidation \
    DEVELOPMENT_TEAM="$DEVELOPMENT_TEAM" \
    CODE_SIGN_STYLE=Manual \
    CODE_SIGN_IDENTITY="Developer ID Application" \
    OTHER_CODE_SIGN_FLAGS="--timestamp --options=runtime" \
    clean build

if [[ ! -d "$APP_PATH" ]]; then
    echo "ERROR: Build did not produce $APP_PATH" >&2
    exit 1
fi

# 3. Verify the signature is internally consistent before going further.
echo "▸ Verifying signature…"
codesign --verify --deep --strict --verbose=2 "$APP_PATH"

mkdir -p "$DIST_DIR"
ZIP_PATH="$DIST_DIR/$SCHEME.zip"

if [[ -n "${NOTARY_PROFILE:-}" ]]; then
    echo "▸ Zipping for notarization…"
    rm -f "$ZIP_PATH"
    /usr/bin/ditto -c -k --keepParent "$APP_PATH" "$ZIP_PATH"

    echo "▸ Submitting to Apple notary service (this can take 1–10 minutes)…"
    xcrun notarytool submit "$ZIP_PATH" \
        --keychain-profile "$NOTARY_PROFILE" \
        --wait

    echo "▸ Stapling ticket to .app…"
    xcrun stapler staple "$APP_PATH"

    echo "▸ Re-zipping stapled .app…"
    rm -f "$ZIP_PATH"
    /usr/bin/ditto -c -k --keepParent "$APP_PATH" "$ZIP_PATH"

    echo "▸ Final Gatekeeper check…"
    spctl --assess --verbose=4 --type execute "$APP_PATH"

    echo
    echo "✓ Notarized + stapled."
    echo "  App:  $APP_PATH"
    echo "  Zip:  $ZIP_PATH"
else
    echo "▸ Zipping (signed, NOT notarized)…"
    rm -f "$ZIP_PATH"
    /usr/bin/ditto -c -k --keepParent "$APP_PATH" "$ZIP_PATH"

    echo
    echo "✓ Signed only (no notarization)."
    echo "  App:  $APP_PATH"
    echo "  Zip:  $ZIP_PATH"
    echo
    echo "On the receiving Mac the first launch will need:"
    echo "  - System Settings → Privacy & Security → 'Open Anyway' (one click), or"
    echo "  - xattr -d com.apple.quarantine '<path-to-FlashcardsPortuges.app>' (one shot)"
    echo
    echo "Set NOTARY_PROFILE=<your-profile> to skip the dance entirely."
fi
