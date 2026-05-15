import CoreGraphics

/// Identifies a physical display across reboots and dock-disconnects.
/// `CGDisplayCreateUUIDFromDisplayID` is the primary key,
/// fall back to `IODisplayConnect` registry-id only if the UUID is `nil` (rare).
public struct DisplayUUID: Hashable, Sendable, RawRepresentable, Codable {
    public let rawValue: String

    public init(rawValue: String) {
        self.rawValue = rawValue
    }

    public init(_ string: String) {
        self.rawValue = string
    }

    /// Stable, deterministic value for tests.
    public static let primary = DisplayUUID("primary-test-display")
}

/// One display's geometry — used by the distance calculator to translate
/// points → physical millimeters.
public struct DisplayInfo: Hashable, Sendable {
    public let uuid: DisplayUUID
    public let displayName: String
    public let frame: CGRect           // global points, BL origin
    public let physicalSize: CGSize    // millimeters; (0,0) when unknown
    public let backingScaleFactor: CGFloat
    public let isPrimary: Bool

    public init(
        uuid: DisplayUUID,
        displayName: String,
        frame: CGRect,
        physicalSize: CGSize,
        backingScaleFactor: CGFloat,
        isPrimary: Bool
    ) {
        self.uuid = uuid
        self.displayName = displayName
        self.frame = frame
        self.physicalSize = physicalSize
        self.backingScaleFactor = backingScaleFactor
        self.isPrimary = isPrimary
    }

    /// Millimeters per point, averaged across X and Y. Falls back to a
    /// density-aware estimate when EDID physical size is missing (Sidecar,
    /// AirPlay, virtual displays) **or** when the reported size yields a
    /// mm/pt outside the plausible range for any real Mac display.
    /// CGDisplayScreenSize is unreliable on some external monitors that
    /// report bogus EDIDs — not just 0×0.
    public var millimetersPerPoint: Double {
        // Plausibility range for a real Mac display, in mm/point:
        //   • 0.10 ≈ 254 DPI logical (denser than any current Mac panel)
        //   • 0.50 ≈ 50 DPI logical (a wall projector, but still bounded)
        // Anything outside this is a wrong-EDID signal, not a real display.
        let minPlausible = 0.10
        let maxPlausible = 0.50

        if physicalSize.width > 0, physicalSize.height > 0,
           frame.size.width > 0, frame.size.height > 0 {
            let x = physicalSize.width / frame.size.width
            let y = physicalSize.height / frame.size.height
            let avg = Double((x + y) / 2.0)
            if avg >= minPlausible && avg <= maxPlausible {
                return avg
            }
        }
        return fallbackMillimetersPerPoint
    }

    /// Density-aware fallback used when EDID is missing or bogus. Retina
    /// panels (backingScaleFactor ≥ 1.5) are ~110 logical PPI → 0.231 mm/pt;
    /// classic displays are 96 PPI → 0.2646 mm/pt. The previous 96-DPI-only
    /// fallback under-counted distance by ~12% on Retina hardware.
    private var fallbackMillimetersPerPoint: Double {
        backingScaleFactor >= 1.5 ? 0.2309 : 0.2646
    }

    /// `true` when the reported EDID size is missing or implausible and we
    /// fell back to a density-aware estimate. Surface as "Estimated" badge
    /// in the per-display Settings list.
    public var hasEstimatedSize: Bool {
        guard physicalSize.width > 0, physicalSize.height > 0,
              frame.size.width > 0, frame.size.height > 0
        else { return true }
        let x = physicalSize.width / frame.size.width
        let y = physicalSize.height / frame.size.height
        let avg = Double((x + y) / 2.0)
        return avg < 0.10 || avg > 0.50
    }
}
