#!/usr/bin/env bash
# Build a Mac App Store archive. Requires:
#   • a valid `3rd Party Mac Developer Application` identity in the keychain
#   • DEVELOPMENT_TEAM in Configs/local.xcconfig
#   • a matching provisioning profile installed
#
# Output: build/archive/CursorOdometer-MAS.xcarchive

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

if [ ! -d "CursorOdometer.xcodeproj" ]; then
    echo "==> Project not generated. Running bootstrap…"
    "$ROOT/Scripts/bootstrap.sh"
fi

ARCHIVE_PATH="build/archive/CursorOdometer-MAS.xcarchive"
mkdir -p build/archive

echo "==> Archiving CursorOdometer-MAS scheme into $ARCHIVE_PATH …"
xcodebuild \
    -project CursorOdometer.xcodeproj \
    -scheme CursorOdometer-MAS \
    -configuration Release-MAS \
    -destination "platform=macOS,arch=arm64" \
    -archivePath "$ARCHIVE_PATH" \
    archive

cat <<EOF

==> Archive ready: $ARCHIVE_PATH

Next:
  • Validate:     xcodebuild -exportArchive -archivePath "$ARCHIVE_PATH" \\
                              -exportOptionsPlist Scripts/ExportOptions-MAS.plist \\
                              -exportPath build/export-mas
  • Upload:       xcrun altool --upload-app -f build/export-mas/CursorOdometer.pkg \\
                              -t macos -u <APPLE_ID> -p <APP_SPECIFIC_PASSWORD>
  • Or via Transporter app (recommended for first submission).
EOF
