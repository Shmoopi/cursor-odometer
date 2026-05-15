// DistanceFormatter.swift — render `Distance` to display strings in the
// user's chosen unit. Pure, stateless (uses `UnitConverter`); no
// AppKit dependency. Custom units resolve against `[CustomUnit]`.
//
// Numeric formatting uses tabular figures (`.monospacedDigit()` is applied at
// the Text site) and a precision policy:
// - sub-meter values: 1 decimal of cm/mm
// - 0–999 m: 1 decimal place
// - 1+ km: 2 decimal places
// - count-style units (bananas, marathons): 0–2 dp depending on magnitude

import Foundation
import CursorOdometerCore

struct DistanceFormatter {
    let customUnits: [CustomUnit]

    init(customUnits: [CustomUnit] = []) {
        self.customUnits = customUnits
    }

    /// Returned to view code: number string + unit label (already singular/plural).
    struct Formatted: Equatable, Sendable {
        var numberText: String
        var unitLabel: String
        var fullText: String { "\(numberText) \(unitLabel)" }
    }

    func format(_ distance: Distance, in unit: UnitPreference) -> Formatted {
        let mpu: Double
        let label: String

        switch unit {
        case .custom(let id):
            guard let cu = customUnits.first(where: { $0.id == id }), cu.metersPerUnit > 0 else {
                // Fallback: meters.
                return format(distance, in: .meters)
            }
            mpu = cu.metersPerUnit
            // Pluralisation: 1.0 → singular, otherwise plural.
            let valueMeters = distance.meters
            let count = valueMeters / mpu
            label = abs(count - 1.0) < 0.0001 ? cu.name : cu.pluralName
            return Formatted(numberText: format(value: count, magnitude: .countStyle),
                             unitLabel: label)

        default:
            mpu = unit.metersPerUnit ?? 1.0
            label = unit.shortLabel ?? "m"
        }

        let value = distance.meters / mpu
        return Formatted(numberText: format(value: value, magnitude: magnitude(for: unit)),
                         unitLabel: label)
    }

    // MARK: Internal

    private enum Magnitude {
        case smallLength      // mm/cm
        case meters           // 0–999 m: one decimal
        case kilometers       // 1+ km: two decimals
        case imperialFeet     // ft / yd: one decimal
        case imperialMiles    // mi: two decimals
        case countStyle       // bananas, marathons, Eiffel Towers
    }

    private func magnitude(for unit: UnitPreference) -> Magnitude {
        switch unit {
        case .millimeters, .centimeters:           return .smallLength
        case .meters:                              return .meters
        case .kilometers:                          return .kilometers
        case .inches, .feet, .yards:               return .imperialFeet
        case .miles:                               return .imperialMiles
        case .marathons, .eiffelTowers,
             .footballFields, .manhattanLengths:  return .countStyle
        case .custom:                              return .countStyle
        }
    }

    private func format(value: Double, magnitude: Magnitude) -> String {
        let nf = NumberFormatter()
        nf.usesGroupingSeparator = true
        nf.locale = .current
        switch magnitude {
        case .smallLength:
            nf.minimumFractionDigits = 0
            nf.maximumFractionDigits = 1
        case .meters:
            nf.minimumFractionDigits = 1
            nf.maximumFractionDigits = 1
        case .kilometers:
            nf.minimumFractionDigits = 2
            nf.maximumFractionDigits = 2
        case .imperialFeet:
            nf.minimumFractionDigits = 1
            nf.maximumFractionDigits = 1
        case .imperialMiles:
            nf.minimumFractionDigits = 2
            nf.maximumFractionDigits = 2
        case .countStyle:
            // Choose precision based on magnitude so we don't say "0.00 marathons".
            if abs(value) >= 100 {
                nf.minimumFractionDigits = 0
                nf.maximumFractionDigits = 0
            } else if abs(value) >= 10 {
                nf.minimumFractionDigits = 1
                nf.maximumFractionDigits = 1
            } else {
                nf.minimumFractionDigits = 2
                nf.maximumFractionDigits = 2
            }
        }
        return nf.string(from: NSNumber(value: value)) ?? "\(value)"
    }
}
