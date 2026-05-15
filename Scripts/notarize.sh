#!/usr/bin/env bash
# Submit a DMG to Apple notarization, wait for the verdict, then staple.
#
# Prerequisite: store credentials once via
#   xcrun notarytool store-credentials AC_NOTARY \\
#       --apple-id <APPLE_ID> --team-id <TEAM_ID> \\
#       --password <APP_SPECIFIC_PASSWORD>
#
# Usage:  ./Scripts/notarize.sh path/to/CursorOdometer.dmg [profile]

set -euo pipefail

DMG_PATH="${1:-}"
PROFILE="${2:-AC_NOTARY}"

if [ -z "$DMG_PATH" ] || [ ! -f "$DMG_PATH" ]; then
    echo "Usage: $0 path/to/Disk.dmg [keychain-profile]" >&2
    exit 1
fi

echo "==> Submitting $DMG_PATH for notarization (profile: $PROFILE)…"
xcrun notarytool submit "$DMG_PATH" \
    --keychain-profile "$PROFILE" \
    --wait

echo "==> Stapling ticket onto DMG…"
xcrun stapler staple "$DMG_PATH"

echo "==> Verifying staple…"
xcrun stapler validate "$DMG_PATH"
spctl --assess --type open --context context:primary-signature -v "$DMG_PATH" || true

echo "==> Notarization complete: $DMG_PATH"
