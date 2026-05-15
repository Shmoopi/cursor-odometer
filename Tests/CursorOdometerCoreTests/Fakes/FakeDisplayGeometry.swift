import Foundation
import CoreGraphics
@testable import CursorOdometerCore

/// Configurable `DisplayGeometryProviding` for tests.
/// (`NSScreen` is forbidden in tests; only this fake is allowed).
public struct FakeDisplayGeometry: DisplayGeometryProviding, Sendable {
    public let displays: [DisplayInfo]

    public init(displays: [DisplayInfo]) {
        self.displays = displays
    }

    /// Convenience: a single primary display at given DPI, frame `(0,0)-(1920,1080)`.
    public static func single(dpi: Double, uuid: DisplayUUID = .primary, name: String = "Test Display") -> FakeDisplayGeometry {
        let frame = CGRect(x: 0, y: 0, width: 1920, height: 1080)
        let mmPerPoint = 25.4 / dpi
        let physical = CGSize(width: frame.size.width * mmPerPoint,
                              height: frame.size.height * mmPerPoint)
        let info = DisplayInfo(
            uuid: uuid,
            displayName: name,
            frame: frame,
            physicalSize: physical,
            backingScaleFactor: 2.0,
            isPrimary: true
        )
        return FakeDisplayGeometry(displays: [info])
    }

    /// Two-display layout for cross-display teleport tests. Secondary placed
    /// to the right of primary.
    public static func twoDisplays(primaryDPI: Double, secondaryDPI: Double) -> FakeDisplayGeometry {
        let primaryFrame = CGRect(x: 0, y: 0, width: 1920, height: 1080)
        let primaryMM = 25.4 / primaryDPI
        let primary = DisplayInfo(
            uuid: DisplayUUID("primary"),
            displayName: "Primary",
            frame: primaryFrame,
            physicalSize: CGSize(width: primaryFrame.size.width * primaryMM,
                                 height: primaryFrame.size.height * primaryMM),
            backingScaleFactor: 2.0,
            isPrimary: true
        )

        let secondaryFrame = CGRect(x: 1920, y: 0, width: 1920, height: 1080)
        let secondaryMM = 25.4 / secondaryDPI
        let secondary = DisplayInfo(
            uuid: DisplayUUID("secondary"),
            displayName: "Secondary",
            frame: secondaryFrame,
            physicalSize: CGSize(width: secondaryFrame.size.width * secondaryMM,
                                 height: secondaryFrame.size.height * secondaryMM),
            backingScaleFactor: 1.0,
            isPrimary: false
        )

        return FakeDisplayGeometry(displays: [primary, secondary])
    }

    /// Display at given negative origin (for "displays left of primary" test).
    public static func leftOfPrimary() -> FakeDisplayGeometry {
        let leftFrame = CGRect(x: -1920, y: 0, width: 1920, height: 1080)
        let mmPerPoint = 25.4 / 110.0
        let left = DisplayInfo(
            uuid: DisplayUUID("left"),
            displayName: "Left",
            frame: leftFrame,
            physicalSize: CGSize(width: leftFrame.size.width * mmPerPoint,
                                 height: leftFrame.size.height * mmPerPoint),
            backingScaleFactor: 1.0,
            isPrimary: false
        )

        let primaryFrame = CGRect(x: 0, y: 0, width: 1920, height: 1080)
        let primary = DisplayInfo(
            uuid: DisplayUUID("primary"),
            displayName: "Primary",
            frame: primaryFrame,
            physicalSize: CGSize(width: primaryFrame.size.width * mmPerPoint,
                                 height: primaryFrame.size.height * mmPerPoint),
            backingScaleFactor: 1.0,
            isPrimary: true
        )

        return FakeDisplayGeometry(displays: [left, primary])
    }

    public func display(at point: CGPoint) -> DisplayInfo? {
        displays.first { $0.frame.contains(point) }
    }
}
