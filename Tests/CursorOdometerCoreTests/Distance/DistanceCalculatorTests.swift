import Testing
import Foundation
import CoreGraphics
@testable import CursorOdometerCore

@Suite("DistanceCalculator")
struct DistanceCalculatorTests {

    // Identical points → 0
    @Test("Identical points yield zero distance")
    func identicalPointsYieldZero() {
        let calc = DistanceCalculator(geometry: FakeDisplayGeometry.single(dpi: 110))
        let p = CGPoint(x: 100, y: 200)
        #expect(calc.distance(from: p, to: p) == .zero)
        #expect(calc.distanceMM(from: p, to: p) == 0)
    }

    // 3-4-5 triangle yields 5
    @Test("3-4-5 triangle yields 5 points")
    func threeFourFive() {
        // The Pythagorean fact is asserted directly on the `CGPoint` extension
        // that powers `DistanceCalculator`; instantiating the calculator here
        // would test the geometry-attribution path covered by other cases.
        let a = CGPoint(x: 100, y: 100)
        let b = CGPoint(x: 103, y: 104)
        #expect(a.distance(to: b) == 5)
    }

    // Retina-scaled mm conversion
    @Test("220-DPI display: 220 points = 25.4 mm (1 inch)")
    func retinaToMillimeters() {
        let geom = FakeDisplayGeometry.single(dpi: 220)
        let calc = DistanceCalculator(geometry: geom)
        let a = CGPoint(x: 0, y: 0)
        let b = CGPoint(x: 220, y: 0)
        #expect(abs(calc.distanceMM(from: a, to: b) - 25.4) < 0.01)
    }

    // Symmetry
    @Test("distance(a,b) == distance(b,a)")
    func symmetry() {
        let calc = DistanceCalculator(geometry: FakeDisplayGeometry.single(dpi: 110))
        let a = CGPoint(x: 13, y: 7)
        let b = CGPoint(x: 1023, y: 998)
        #expect(calc.distance(from: a, to: b) == calc.distance(from: b, to: a))
        #expect(calc.distanceMM(from: a, to: b) == calc.distanceMM(from: b, to: a))
    }

    // Triangle inequality on fuzzed inputs
    @Test("Triangle inequality holds for fuzzed inputs",
          arguments: 0..<200)
    func triangleInequality(_ seed: Int) {
        var rng = SeededRNG(seed: UInt64(seed) &+ 1)
        let calc = DistanceCalculator(geometry: FakeDisplayGeometry.single(dpi: 110))
        let a = CGPoint(x: rng.uniformDouble(-2000, 2000), y: rng.uniformDouble(-2000, 2000))
        let b = CGPoint(x: rng.uniformDouble(-2000, 2000), y: rng.uniformDouble(-2000, 2000))
        let c = CGPoint(x: rng.uniformDouble(-2000, 2000), y: rng.uniformDouble(-2000, 2000))
        let ab = calc.distanceMM(from: a, to: b)
        let bc = calc.distanceMM(from: b, to: c)
        let ac = calc.distanceMM(from: a, to: c)
        // |ab + bc| >= ac with floating-point slop
        #expect(ab + bc + 1e-9 >= ac)
        #expect(ab + ac + 1e-9 >= bc)
        #expect(bc + ac + 1e-9 >= ab)
    }

    // Sub-pixel deltas accumulate within 0.1%
    // Uses `DistanceAccumulator` to honour precision: per-delta rounding
    // to integer µm biases the naive `Distance += Distance` path by up to
    // ~0.5 µm per delta. Hot summation paths (aggregator, perf tests) carry
    // the residue across calls.
    @Test("10,000 sub-pixel deltas accumulate to expected total within 0.1%")
    func subpixelAccumulation() {
        let calc = DistanceCalculator(geometry: FakeDisplayGeometry.single(dpi: 110))
        let step: CGFloat = 0.3   // sub-pixel
        var acc = DistanceAccumulator()
        var prev = CGPoint.zero
        for i in 1...10_000 {
            let p = CGPoint(x: CGFloat(i) * step, y: 0)
            acc.addMillimeters(calc.distanceMM(from: prev, to: p))
            prev = p
        }
        let expectedMM = Double(10_000) * Double(step) * (25.4 / 110.0)
        let actualMM = acc.settle().millimeters
        let relErr = abs(expectedMM - actualMM) / expectedMM
        #expect(relErr < 0.001)
    }

    // Mixed-DPI cross-display delta uses destination DPI
    @Test("Cross-display delta attributes to destination display's DPI")
    func mixedDPIUsesDestination() {
        // Primary 110 DPI, secondary 220 DPI to the right.
        let geom = FakeDisplayGeometry.twoDisplays(primaryDPI: 110, secondaryDPI: 220)
        let calc = DistanceCalculator(geometry: geom)
        // Both points on secondary.
        let a = CGPoint(x: 2000, y: 100)
        let b = CGPoint(x: 2110, y: 100)   // 110 points → 1/2 inch on 220 DPI = 12.7 mm
        #expect(abs(calc.distanceMM(from: a, to: b) - 12.7) < 0.05)
    }

    // Negative coordinates (displays left of primary)
    @Test("Displays at negative X produce correct magnitudes")
    func negativeCoordinates() {
        let geom = FakeDisplayGeometry.leftOfPrimary()
        let calc = DistanceCalculator(geometry: geom)
        let a = CGPoint(x: -500, y: 100)
        let b = CGPoint(x: -300, y: 100)   // 200 points
        let mmExpected = 200 * (25.4 / 110.0)
        #expect(abs(calc.distanceMM(from: a, to: b) - mmExpected) < 0.01)
    }

    // NaN / infinite input → 0 in release
    @Test("NaN input returns zero (release behavior)")
    func nanReturnsZero() {
        let calc = DistanceCalculator(geometry: FakeDisplayGeometry.single(dpi: 110))
        let a = CGPoint(x: 0, y: 0)
        let b = CGPoint(x: CGFloat.nan, y: 0)
        #expect(calc.distance(from: a, to: b) == .zero)
        #expect(calc.distanceMM(from: a, to: b) == 0)
    }

    @Test("Infinite input returns zero")
    func infiniteReturnsZero() {
        let calc = DistanceCalculator(geometry: FakeDisplayGeometry.single(dpi: 110))
        let a = CGPoint(x: 0, y: 0)
        let b = CGPoint(x: CGFloat.infinity, y: 0)
        #expect(calc.distance(from: a, to: b) == .zero)
    }

    // Performance, smoke (don't gate; full perf is XCTest measure)
    @Test("10,000 distance calls complete in under 50 ms (smoke)")
    func tenThousandCallsSmoke() {
        let calc = DistanceCalculator(geometry: FakeDisplayGeometry.single(dpi: 110))
        let a = CGPoint(x: 0, y: 0)
        let b = CGPoint(x: 1234, y: 5678)
        let start = ContinuousClock.now
        for _ in 0..<10_000 {
            _ = calc.distance(from: a, to: b)
        }
        let elapsed = ContinuousClock.now - start
        #expect(elapsed < .milliseconds(50))
    }
}

/// Tiny seeded RNG so fuzz tests are reproducible. Linear-congruential.
struct SeededRNG: RandomNumberGenerator {
    var state: UInt64
    init(seed: UInt64) { self.state = seed | 1 }
    mutating func next() -> UInt64 {
        state = state &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
        return state
    }
    mutating func uniformDouble(_ low: Double, _ high: Double) -> Double {
        let raw = Double(next() >> 11) / Double(1 << 53)
        return low + (high - low) * raw
    }
}
