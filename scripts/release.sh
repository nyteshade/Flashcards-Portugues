#!/bin/bash
# RELEASE (notarized) — slow path. Use for hand-offs to other Macs.
# For everyday "build and install on this Mac" workflow, use
# ./scripts/deploy.sh instead — it's ad-hoc signed, no Apple round-trip,
# typically ~3-5x faster end-to-end.
#
# Notarization is per-build, not one-time. Every submission goes to
# Apple's queue independently; expect 2-15 min per run.
#
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

    echo "▸ Submitting to Apple notary service…"
    SUBMIT_JSON=$(xcrun notarytool submit "$ZIP_PATH" \
        --keychain-profile "$NOTARY_PROFILE" \
        --output-format json)
    SUBMIT_ID=$(echo "$SUBMIT_JSON" | /usr/bin/python3 -c 'import json,sys; print(json.load(sys.stdin).get("id",""))')
    if [[ -z "$SUBMIT_ID" ]]; then
        echo "ERROR: Could not extract notarytool submission id." >&2
        echo "$SUBMIT_JSON" >&2
        exit 1
    fi
    echo "  submission id: $SUBMIT_ID"
    echo "▸ Polling Apple for status every 15s (typically 2–10 min)…"

    POLL_INTERVAL=15
    POLL_COUNT=0
    while true; do
        sleep "$POLL_INTERVAL"
        POLL_COUNT=$((POLL_COUNT + 1))
        STATUS_JSON=$(xcrun notarytool info "$SUBMIT_ID" \
            --keychain-profile "$NOTARY_PROFILE" \
            --output-format json 2>/dev/null || echo "{}")
        STATUS=$(echo "$STATUS_JSON" | /usr/bin/python3 -c 'import json,sys; print(json.load(sys.stdin).get("status","Unknown"))')
        ELAPSED=$((POLL_COUNT * POLL_INTERVAL))
        printf "  [%s] +%3ds  status: %s\n" "$(date +%H:%M:%S)" "$ELAPSED" "$STATUS"
        case "$STATUS" in
            Accepted)
                echo "✓ Apple accepted the submission."
                break
                ;;
            Invalid|Rejected)
                echo "ERROR: Notarization $STATUS. Fetching log…" >&2
                xcrun notarytool log "$SUBMIT_ID" \
                    --keychain-profile "$NOTARY_PROFILE" 2>&1 | head -80 >&2 || true
                exit 1
                ;;
            "In Progress"|Pending|Unknown)
                # keep polling
                ;;
            *)
                echo "WARNING: unrecognized notary status '$STATUS' — continuing to poll." >&2
                ;;
        esac
        # Hard safety cap: 30 minutes. Apple usually finishes well under
        # 10, but the queue spikes around major releases. Fail loud
        # rather than hang the script forever.
        if [[ "$ELAPSED" -ge 1800 ]]; then
            echo "ERROR: Notarization did not complete within 30 minutes." >&2
            echo "  Submission id $SUBMIT_ID is still pending; check later with:" >&2
            echo "  xcrun notarytool info $SUBMIT_ID --keychain-profile $NOTARY_PROFILE" >&2
            exit 1
        fi
    done

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
