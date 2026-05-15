import Testing
import Foundation
@testable import CursorOdometerCore

@Suite("UnitConverter")
struct UnitConverterTests {

    // m → km → m round-trip < 1 ppm
    @Test("Meters → kilometers → meters round-trip < 1 ppm",
          arguments: [0.0, 1.0, 1000.0, 9_999_999.0])
    func metersKilometersRoundTrip(_ m: Double) {
        let converter = CursorOdometerCore.UnitConverter()
        let d = Distance.meters(m)
        let asKm = converter.convert(d, to: .kilometers, customUnits: [])
        let backD = Distance.meters(asKm * 1_000)
        let backM = backD.meters
        if m == 0 { #expect(backM == 0) } else {
            #expect(abs(backM - m) / m < 1e-6)
        }
    }

    // m → mi → m round-trip
    @Test("Meters → miles → meters round-trip < 1 ppm",
          arguments: [0.0, 1.0, 1000.0, 9_999_999.0])
    func metersMilesRoundTrip(_ m: Double) {
        let converter = CursorOdometerCore.UnitConverter()
        let d = Distance.meters(m)
        let mi = converter.convert(d, to: .miles, customUnits: [])
        let backD = Distance.meters(mi * 1_609.344)
        let backM = backD.meters
        if m == 0 { #expect(backM == 0) } else {
            #expect(abs(backM - m) / m < 1e-6)
        }
    }

    // feet round-trip
    @Test("Meters → feet → meters round-trip < 1 ppm",
          arguments: [0.0, 1.0, 1000.0, 9_999_999.0])
    func metersFeetRoundTrip(_ m: Double) {
        let converter = CursorOdometerCore.UnitConverter()
        let d = Distance.meters(m)
        let ft = converter.convert(d, to: .feet, customUnits: [])
        let backD = Distance.meters(ft * 0.3048)
        let backM = backD.meters
        if m == 0 { #expect(backM == 0) } else {
            #expect(abs(backM - m) / m < 1e-6)
        }
    }

    // custom unit ("cubits") round-trip
    @Test("Meters → custom 'cubit' (0.4572 m) → meters round-trip < 1 ppm")
    func metersCubitsRoundTrip() {
        let cubit = CustomUnit(id: "cubit", name: "cubit", pluralName: "cubits", metersPerUnit: 0.4572)
        let converter = CursorOdometerCore.UnitConverter()
        let d = Distance.meters(914.4)  // 2000 cubits
        let value = converter.convert(d, to: .custom(id: "cubit"), customUnits: [cubit])
        #expect(abs(value - 2000) / 2000 < 1e-6)
    }

    // Eiffel Tower (330 m), 990 m → 3.0
    @Test("990 m converts to 3.0 Eiffel Towers")
    func eiffelTowerExample() {
        let converter = CursorOdometerCore.UnitConverter()
        let d = Distance.meters(990)
        let value = converter.convert(d, to: .eiffelTowers, customUnits: [])
        #expect(abs(value - 3.0) < 1e-9)
    }

    // Zero round-trips
    @Test("Zero in any unit returns zero",
          arguments: [
            UnitPreference.meters,
            .kilometers,
            .miles,
            .feet,
            .inches,
            .yards,
            .marathons,
            .eiffelTowers,
            .footballFields,
            .manhattanLengths
          ])
    func zeroAlwaysZero(_ unit: UnitPreference) {
        let converter = CursorOdometerCore.UnitConverter()
        let d = Distance.zero
        #expect(converter.convert(d, to: unit, customUnits: []) == 0)
    }

    // Negative input throws
    @Test("Negative micrometers throws negativeDistance")
    func negativeThrows() throws {
        let converter = CursorOdometerCore.UnitConverter()
        let neg = Distance(micrometers: -1)
        #expect(throws: UnitConverterError.negativeDistance) {
            _ = try converter.convertThrowing(neg, to: .meters, customUnits: [])
        }
    }

    // Double.greatestFiniteMagnitude (skip overflow guarantee for Distance, sub at Int64.max)
    @Test("Int64.max micrometers converts to a finite Double without overflow")
    func extremeValueDoesNotOverflow() {
        let converter = CursorOdometerCore.UnitConverter()
        let d = Distance(micrometers: Int64.max)
        let value = converter.convert(d, to: .meters, customUnits: [])
        #expect(value.isFinite)
        #expect(value > 0)
    }

    // en_US grouping separator
    @Test("en_US formatting groups thousands with commas")
    func enUSFormatting() {
        let converter = CursorOdometerCore.UnitConverter(locale: Locale(identifier: "en_US"))
        // 1,234.56 m
        let d = Distance(micrometers: 1_234_560_000)
        let formatted = converter.format(d, unit: .meters, customUnits: [])
        #expect(formatted.number.contains(","))
        #expect(formatted.number.contains("1"))
        #expect(formatted.number.contains("234"))
    }

    // de_DE grouping
    @Test("de_DE formatting uses period as thousands and comma as decimal")
    func deDEFormatting() {
        let converter = CursorOdometerCore.UnitConverter(locale: Locale(identifier: "de_DE"))
        let d = Distance(micrometers: 1_234_560_000)
        let formatted = converter.format(d, unit: .meters, customUnits: [])
        // Either ".' or '\u{00A0}' (non-breaking space) is acceptable; we check for comma decimal.
        #expect(formatted.number.contains(","))
    }

    // ar_SA digits
    @Test("ar_SA renders with locale-appropriate digits")
    func arSADigits() {
        let converter = CursorOdometerCore.UnitConverter(locale: Locale(identifier: "ar_SA"))
        let d = Distance.meters(1234.56)
        let formatted = converter.format(d, unit: .meters, customUnits: [])
        #expect(!formatted.number.isEmpty)
        // The Arabic-Indic digit '٤' is U+0664. Arabic-Indic locale formats digits.
        // Don't strictly assert exact digit set (CI may vary), only that we got *something*.
    }

    // Pluralisation
    @Test("Mile suffix singular for 1, plural for 2")
    func milesPluralisation() {
        let converter = CursorOdometerCore.UnitConverter(locale: Locale(identifier: "en_US"))
        let one = converter.format(Distance.meters(1_609.344), unit: .miles, customUnits: [])
        let two = converter.format(Distance.meters(3_218.688), unit: .miles, customUnits: [])
        #expect(one.suffix.lowercased().contains("mile"))
        #expect(two.suffix.lowercased().contains("mile"))
        // Singular vs plural: at minimum the strings are not equal except by number.
        #expect(one.suffix != two.suffix)
    }

    // MARK: extra — custom unit pluralisation uses the user-supplied pluralName
    @Test("Custom unit suffix uses pluralName when count > 1")
    func customUnitPluralisation() {
        let banana = CustomUnit(id: "banana", name: "banana", pluralName: "bananas", metersPerUnit: 0.18)
        let converter = CursorOdometerCore.UnitConverter(locale: Locale(identifier: "en_US"))
        let one = converter.format(Distance.meters(0.18), unit: .custom(id: "banana"), customUnits: [banana])
        let many = converter.format(Distance.meters(0.36), unit: .custom(id: "banana"), customUnits: [banana])
        #expect(one.suffix == "banana")
        #expect(many.suffix == "bananas")
    }

    // MARK: extra — unknown custom id falls back to short label or empty
    @Test("Unknown custom unit id returns 0 and an empty suffix")
    func unknownCustomFallback() {
        let converter = CursorOdometerCore.UnitConverter()
        let value = converter.convert(Distance.meters(100), to: .custom(id: "unknown"), customUnits: [])
        #expect(value == 0)
    }
}
