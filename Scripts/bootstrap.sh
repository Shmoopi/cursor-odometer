#!/usr/bin/env bash
# Bootstrap script: install xcodegen if missing, then regenerate the
# Xcode project from `project.yml`. Safe to run repeatedly.
#
# Usage:  ./Scripts/bootstrap.sh

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

# 1. xcodegen
if ! command -v xcodegen >/dev/null 2>&1; then
    if ! command -v brew >/dev/null 2>&1; then
        echo "ERROR: xcodegen is not installed and Homebrew is unavailable." >&2
        echo "Install Homebrew (https://brew.sh) or xcodegen manually:" >&2
        echo "  brew install xcodegen" >&2
        exit 1
    fi
    echo "==> Installing xcodegen via Homebrew…"
    brew install xcodegen
fi

XCODEGEN_VERSION="$(xcodegen --version 2>&1 | head -1)"
echo "==> xcodegen: $XCODEGEN_VERSION"

# 2. local.xcconfig stub (gitignored) so signing settings can be filled
# in without modifying the committed YAML.
if [ ! -f "Configs/local.xcconfig" ]; then
    cp Configs/local.xcconfig.example Configs/local.xcconfig
    echo "==> Created Configs/local.xcconfig (gitignored). Fill in DEVELOPMENT_TEAM."
fi

# 3. Generate the Xcode project.
echo "==> Generating CursorOdometer.xcodeproj…"
xcodegen generate --spec project.yml --quiet

# 4. Sanity-check the result.
if [ ! -d "CursorOdometer.xcodeproj" ]; then
    echo "ERROR: xcodegen ran but CursorOdometer.xcodeproj does not exist." >&2
    exit 1
fi

cat <<'EOF'

==> Bootstrap complete.

Next steps:
  • Open the project:        open CursorOdometer.xcodeproj
  • Build via SPM (fast):    swift build
  • Run all 75 tests:        swift test
  • Build via xcodebuild:    ./Scripts/build.sh xcb-test
  • Archive MAS:             ./Scripts/archive-mas.sh
  • Archive Direct + DMG:    ./Scripts/archive-direct.sh
  • Notarize Direct DMG:     ./Scripts/notarize.sh path/to/CursorOdometer.dmg

Reminders:
  • Edit project.yml — never CursorOdometer.xcodeproj directly.
  • DEVELOPMENT_TEAM lives in Configs/local.xcconfig (gitignored).
EOF
