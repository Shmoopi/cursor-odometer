import Foundation
import CoreGraphics

public extension CGPoint {
    /// Euclidean distance to `other` in the same coordinate space (points).
    /// Pythagorean.
    func distance(to other: CGPoint) -> CGFloat {
        let dx = other.x - x
        let dy = other.y - y
        return sqrt(dx * dx + dy * dy)
    }
}
