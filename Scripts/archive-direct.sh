#!/usr/bin/env bash
# Build a Direct (notarized DMG) archive and produce a signed .dmg.
# Requires:
#   • a valid `Developer ID Application` identity in the keychain
#   • DEVELOPMENT_TEAM in Configs/local.xcconfig
#
# Output:
#   build/archive/CursorOdometer-Direct.xcarchive
#   build/dmg/CursorOdometer-<version>.dmg

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

if [ ! -d "CursorOdometer.xcodeproj" ]; then
    echo "==> Project not generated. Running bootstrap…"
    "$ROOT/Scripts/bootstrap.sh"
fi

ARCHIVE_PATH="build/archive/CursorOdometer-Direct.xcarchive"
EXPORT_PATH="build/export-direct"
DMG_DIR="build/dmg"
VERSION=$(awk -F' = ' '/MARKETING_VERSION/{print $2}' Configs/Shared.xcconfig | tr -d ' ')
DMG_PATH="$DMG_DIR/CursorOdometer-${VERSION}.dmg"

mkdir -p build/archive "$DMG_DIR"

echo "==> Archiving CursorOdometer-Direct scheme…"
xcodebuild \
    -project CursorOdometer.xcodeproj \
    -scheme CursorOdometer-Direct \
    -configuration Release-Direct \
    -destination "platform=macOS,arch=arm64" \
    -archivePath "$ARCHIVE_PATH" \
    archive

echo "==> Exporting signed .app from archive…"
mkdir -p "$EXPORT_PATH"
xcodebuild -exportArchive \
    -archivePath "$ARCHIVE_PATH" \
    -exportOptionsPlist Scripts/ExportOptions-Direct.plist \
    -exportPath "$EXPORT_PATH"

APP_PATH="$EXPORT_PATH/CursorOdometer.app"
if [ ! -d "$APP_PATH" ]; then
    echo "ERROR: expected $APP_PATH after export" >&2
    exit 1
fi

echo "==> Creating DMG at $DMG_PATH …"
rm -f "$DMG_PATH"
hdiutil create -volname "Cursor Odometer" \
    -srcfolder "$APP_PATH" \
    -ov \
    -format UDZO \
    "$DMG_PATH"

echo "==> Signing DMG…"
codesign --sign "Developer ID Application" --options runtime --timestamp "$DMG_PATH"

cat <<EOF

==> Direct DMG ready: $DMG_PATH
==> Archive: $ARCHIVE_PATH

Next: notarize.
  ./Scripts/notarize.sh "$DMG_PATH"
EOF
