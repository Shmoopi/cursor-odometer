import CoreGraphics

/// Translates a screen point to a display, and a display to its mm-per-point
/// constant. Acts as a testability seam for `DisplayRegistry`.
public protocol DisplayGeometryProviding: Sendable {
    /// Average millimeters per point for the **primary** display, used as a
    /// fallback when no display is identified.
    var pointsPerMillimeter: Double { get }

    /// Identify which display contains a point.
    func display(at point: CGPoint) -> DisplayInfo?

    /// All currently-attached displays.
    var displays: [DisplayInfo] { get }
}

/// Convenience defaults so simple call-sites don't need a registry.
public extension DisplayGeometryProviding {
    var pointsPerMillimeter: Double {
        guard let primary = displays.first(where: { $0.isPrimary }) ?? displays.first else {
            return 1.0 / 0.2309  // Retina-typical fallback (110 PPI logical)
        }
        return 1.0 / primary.millimetersPerPoint
    }
}
