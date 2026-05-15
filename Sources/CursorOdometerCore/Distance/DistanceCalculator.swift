import CoreGraphics

/// Pure (`Sendable`, `nonisolated`) integration of two cursor samples into a
/// physical-distance delta.
public struct DistanceCalculator: Sendable {
    private let geometry: any DisplayGeometryProviding

    public init(geometry: any DisplayGeometryProviding) {
        self.geometry = geometry
    }

    /// Distance in `Distance` (Int64 micrometers), in the destination display's
    /// physical millimeters. Uses the "nearest-display rule".
    public func distance(from a: CGPoint, to b: CGPoint) -> Distance {
        guard let dPoints = sanitisedDistance(from: a, to: b) else { return .zero }
        let mmPerPoint = mmPerPoint(at: b) ?? mmPerPoint(at: a) ?? primaryFallbackMMPerPoint
        let mm = Double(dPoints) * mmPerPoint
        return .millimeters(mm)
    }

    /// Distance expressed as a `Double` in millimeters. Convenience for tests.
    public func distanceMM(from a: CGPoint, to b: CGPoint) -> Double {
        guard let dPoints = sanitisedDistance(from: a, to: b) else { return 0 }
        let mmPerPoint = mmPerPoint(at: b) ?? mmPerPoint(at: a) ?? primaryFallbackMMPerPoint
        return Double(dPoints) * mmPerPoint
    }

    /// Identify the display attribution for the destination point.
    /// We prefer the destination's display.
    public func displayUUID(for point: CGPoint) -> DisplayUUID? {
        geometry.display(at: point)?.uuid
    }

    // MARK: - private

    private func sanitisedDistance(from a: CGPoint, to b: CGPoint) -> CGFloat? {
        guard a.x.isFinite, a.y.isFinite, b.x.isFinite, b.y.isFinite else { return nil }
        let d = a.distance(to: b)
        guard d.isFinite else { return nil }
        return d
    }

    private func mmPerPoint(at point: CGPoint) -> Double? {
        geometry.display(at: point).map { $0.millimetersPerPoint }
    }

    private var primaryFallbackMMPerPoint: Double {
        geometry.displays.first(where: { $0.isPrimary })?.millimetersPerPoint
            ?? geometry.displays.first?.millimetersPerPoint
            ?? 0.2309  // Retina-typical fallback (110 PPI logical)
    }
}
