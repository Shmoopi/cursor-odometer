// swift-tools-version: 6.0
// CursorOdometer — A native macOS menu-bar utility that measures cursor distance.
// Swift 6, strict concurrency, macOS 14 minimum, optimised for macOS 26.

import PackageDescription

let package = Package(
    name: "CursorOdometer",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .library(
            name: "CursorOdometerCore",
            targets: ["CursorOdometerCore"]
        ),
        .executable(
            name: "CursorOdometer",
            targets: ["CursorOdometerApp"]
        )
    ],
    targets: [
        // The headless measurement core. AppKit-free where possible so it can
        // be tested without a host app.
        .target(
            name: "CursorOdometerCore",
            path: "Sources/CursorOdometerCore",
            swiftSettings: [
                .unsafeFlags(["-warnings-as-errors"], .when(configuration: .release))
            ]
        ),
        // The menu-bar application. SwiftUI + AppKit shell.
        // Resources are owned by the xcodegen-generated project (see
        // `project.yml`); SPM excludes them from its own bundle because:
        //   • Info.plist is forbidden as an SPM resource
        //   • the asset catalog and PrivacyInfo.xcprivacy require app-bundle
        //     processing that SPM's executable target doesn't perform
        //   • the entitlement files only matter when xcodebuild signs
        // SPM still produces a working executable for fast `swift test`
        // cycles; production / signed / sandboxed / notarized builds run
        // through `xcodebuild` via the generated `CursorOdometer.xcodeproj`.
        .executableTarget(
            name: "CursorOdometerApp",
            dependencies: ["CursorOdometerCore"],
            path: "Sources/CursorOdometerApp",
            exclude: [
                "Resources/Info.plist",
                "Resources/CursorOdometer.entitlements",
                "Resources/CursorOdometer-Direct.entitlements",
                "Resources/PrivacyInfo.xcprivacy",
                "Resources/Assets.xcassets"
            ]
        ),
        // Comprehensive Swift Testing suite
        .testTarget(
            name: "CursorOdometerCoreTests",
            dependencies: ["CursorOdometerCore"],
            path: "Tests/CursorOdometerCoreTests"
        )
    ]
)
