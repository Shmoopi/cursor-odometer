#!/usr/bin/env bash
# Build helper for Cursor Odometer.
#
# Fast iteration (SPM):
#   ./Scripts/build.sh test           # swift test
#   ./Scripts/build.sh build          # swift build (debug)
#   ./Scripts/build.sh build-release  # swift build -c release
#   ./Scripts/build.sh app            # wrap SPM output in a .app bundle
#   ./Scripts/build.sh clean          # rm -rf .build
#
# Full Xcode pipeline:
#   ./Scripts/build.sh xcb-bootstrap  # xcodegen generate
#   ./Scripts/build.sh xcb-build      # xcodebuild Debug build
#   ./Scripts/build.sh xcb-test       # xcodebuild test (Swift Testing + XCTest)
#   ./Scripts/build.sh xcb-clean      # rm -rf build/ + DerivedData

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

CMD="${1:-build}"

ensure_project() {
    if [ ! -d "CursorOdometer.xcodeproj" ]; then
        "$ROOT/Scripts/bootstrap.sh"
    fi
}

case "$CMD" in
    test)
        swift test --parallel
        ;;
    build)
        swift build
        ;;
    build-release)
        swift build -c release
        ;;
    app)
        # Wrap the SPM-built executable in a minimal .app bundle for quick
        # local testing. Production / App Store builds use xcodebuild
        # via `xcb-archive-mas` / `xcb-archive-direct`.
        swift build -c release
        APP="$ROOT/.build/CursorOdometer.app"
        BIN="$ROOT/.build/release/CursorOdometer"
        rm -rf "$APP"
        mkdir -p "$APP/Contents/MacOS"
        mkdir -p "$APP/Contents/Resources"
        cp "$BIN" "$APP/Contents/MacOS/CursorOdometer"
        cp "$ROOT/Sources/CursorOdometerApp/Resources/Info.plist" "$APP/Contents/Info.plist"
        echo "APPL????" > "$APP/Contents/PkgInfo"
        echo "Wrote $APP"
        ;;
    clean)
        rm -rf .build
        ;;
    xcb-bootstrap)
        "$ROOT/Scripts/bootstrap.sh"
        ;;
    xcb-build)
        ensure_project
        xcodebuild \
            -project CursorOdometer.xcodeproj \
            -scheme CursorOdometer-Direct \
            -configuration Debug \
            -destination "platform=macOS,arch=arm64" \
            build
        ;;
    xcb-test)
        ensure_project
        xcodebuild \
            -project CursorOdometer.xcodeproj \
            -scheme CursorOdometer-Direct \
            -configuration Debug \
            -destination "platform=macOS,arch=arm64" \
            test
        ;;
    xcb-archive-mas)
        "$ROOT/Scripts/archive-mas.sh"
        ;;
    xcb-archive-direct)
        "$ROOT/Scripts/archive-direct.sh"
        ;;
    xcb-clean)
        rm -rf build
        rm -rf "$HOME/Library/Developer/Xcode/DerivedData/CursorOdometer-"*
        ;;
    *)
        echo "Unknown command: $CMD"
        echo "Usage: $0 {test|build|build-release|app|clean|xcb-bootstrap|xcb-build|xcb-test|xcb-archive-mas|xcb-archive-direct|xcb-clean}"
        exit 1
        ;;
esac
