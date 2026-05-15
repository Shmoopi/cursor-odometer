/// Distance stored as **integer micrometers** (Int64).
/// A `Double` would accumulate floating-point drift over millions of additions;
/// `Decimal` is overkill and slow. Int64 micrometers gives ±9.2×10^12 m of range
/// (~60× the distance to Pluto) with zero drift.
public struct Distance: Hashable, Sendable, Comparable {
    public let micrometers: Int64

    public init(micrometers: Int64) {
        self.micrometers = micrometers
    }

    public static let zero = Distance(micrometers: 0)

    // MARK: Constructors from common units (used at I/O boundary, not in hot loop).

    public static func millimeters(_ mm: Double) -> Distance {
        Distance(micrometers: Int64((mm * 1_000).rounded()))
    }

    public static func meters(_ m: Double) -> Distance {
        Distance(micrometers: Int64((m * 1_000_000).rounded()))
    }

    public static func points(_ pts: Double, mmPerPoint: Double) -> Distance {
        Distance(micrometers: Int64((pts * mmPerPoint * 1_000).rounded()))
    }

    // MARK: Conversions out (formatting boundary).

    public var meters: Double { Double(micrometers) / 1_000_000 }
    public var millimeters: Double { Double(micrometers) / 1_000 }
    public var kilometers: Double { Double(micrometers) / 1_000_000_000 }

    // MARK: Arithmetic (saturating, never overflows).

    public static func + (lhs: Distance, rhs: Distance) -> Distance {
        Distance(micrometers: lhs.micrometers.addingReportingOverflow(rhs.micrometers).0)
    }

    public static func += (lhs: inout Distance, rhs: Distance) {
        lhs = lhs + rhs
    }

    public static func - (lhs: Distance, rhs: Distance) -> Distance {
        Distance(micrometers: lhs.micrometers.subtractingReportingOverflow(rhs.micrometers).0)
    }

    public static func < (lhs: Distance, rhs: Distance) -> Bool {
        lhs.micrometers < rhs.micrometers
    }
}

/// Bias-free accumulator for summing many sub-µm deltas. Each individual
/// `Distance.millimeters(_:)` rounds to the nearest µm, which biases summed
/// totals by up to ~0.5 µm per delta. Hot loops (the aggregator, perf tests)
/// should use `DistanceAccumulator` to track the carry and obtain exact totals.
public struct DistanceAccumulator: Sendable {
    /// Carry in fractional µm, in `[0, 1)`.
    private var carry: Double = 0
    private var integer: Int64 = 0

    public init() {}

    /// Add `mm` millimeters, preserving sub-µm precision via running carry.
    public mutating func addMillimeters(_ mm: Double) {
        guard mm.isFinite else { return }
        let totalUM = mm * 1_000 + carry
        let intPart = totalUM.rounded(.down)
        integer = integer &+ Int64(intPart)
        carry = totalUM - intPart
    }

    /// Settle the carry into the integer total and return the result.
    public mutating func settle() -> Distance {
        if carry >= 0.5 {
            integer = integer &+ 1
            carry -= 1
        }
        return Distance(micrometers: integer)
    }

    /// Read-only snapshot without consuming the carry.
    public var distance: Distance {
        Distance(micrometers: integer + (carry >= 0.5 ? 1 : 0))
    }
}
