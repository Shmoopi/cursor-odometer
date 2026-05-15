import Foundation

/// Errors raised by `UnitConverter` for programming-mistake inputs.
/// Negative input is a contract violation and throws.
public enum UnitConverterError: Error, Sendable, Equatable {
    case negativeDistance
}

/// Locale-aware formatter for `Distance` values. Stateless except for the
/// configured locale.
public struct UnitConverter: Sendable {
    public let locale: Locale

    public init(locale: Locale = .autoupdatingCurrent) {
        self.locale = locale
    }

    /// Convert `distance` to a numeric quantity in `unit`. Returns 0 for
    /// unknown custom unit ids (call sites should guard against this earlier
    /// in the unit-picker UI).
    public func convert(
        _ distance: Distance,
        to unit: UnitPreference,
        customUnits: [CustomUnit]
    ) -> Double {
        guard distance.micrometers >= 0 else { return 0 }
        guard let mpu = metersPerUnit(unit, customUnits: customUnits), mpu != 0 else { return 0 }
        return distance.meters / mpu
    }

    /// Throwing variant — fails with `.negativeDistance` instead of clamping.
    public func convertThrowing(
        _ distance: Distance,
        to unit: UnitPreference,
        customUnits: [CustomUnit]
    ) throws -> Double {
        if distance.micrometers < 0 { throw UnitConverterError.negativeDistance }
        guard let mpu = metersPerUnit(unit, customUnits: customUnits), mpu != 0 else { return 0 }
        return distance.meters / mpu
    }

    /// Locale-formatted number + unit suffix tuple. Suffix is manually
    /// pluralised so the count always agrees with the value (English-only at
    /// launch).
    public func format(
        _ distance: Distance,
        unit: UnitPreference,
        customUnits: [CustomUnit]
    ) -> Formatted {
        let value = convert(distance, to: unit, customUnits: customUnits)
        let suffix = formattedSuffix(value: value, unit: unit, customUnits: customUnits)
        let number = formattedNumber(value, unit: unit)
        return Formatted(number: number, suffix: suffix)
    }

    /// Tuple-like return type for `format(_:unit:)`.
    public struct Formatted: Hashable, Sendable {
        public let number: String
        public let suffix: String
        public init(number: String, suffix: String) {
            self.number = number
            self.suffix = suffix
        }
    }

    // MARK: - private

    private func metersPerUnit(_ unit: UnitPreference, customUnits: [CustomUnit]) -> Double? {
        switch unit {
        case .custom(let id):
            return customUnits.first(where: { $0.id == id })?.metersPerUnit
        default:
            return unit.metersPerUnit
        }
    }

    private func formattedNumber(_ value: Double, unit: UnitPreference) -> String {
        let formatter = NumberFormatter()
        formatter.locale = locale
        formatter.numberStyle = .decimal
        formatter.maximumFractionDigits = fractionDigits(for: unit, value: value)
        formatter.minimumFractionDigits = 0
        formatter.usesGroupingSeparator = true
        return formatter.string(from: NSNumber(value: value)) ?? "\(value)"
    }

    private func fractionDigits(for unit: UnitPreference, value: Double) -> Int {
        switch unit {
        case .meters, .millimeters, .centimeters, .inches, .feet, .yards:
            return value < 10 ? 2 : 1
        case .kilometers, .miles, .marathons, .eiffelTowers, .footballFields, .manhattanLengths:
            return 2
        case .custom:
            return 2
        }
    }

    private func formattedSuffix(
        value: Double,
        unit: UnitPreference,
        customUnits: [CustomUnit]
    ) -> String {
        if case .custom(let id) = unit {
            guard let cu = customUnits.first(where: { $0.id == id }) else { return "" }
            return abs(value - 1.0) < .ulpOfOne ? cu.name : cu.pluralName
        }
        // English-only at launch; manually pluralise so the
        // suffix always reflects count. `MeasurementFormatter` with `.medium`
        // returns abbreviations like "mi", which fail the pluralisation test.
        let isPlural = abs(value - 1.0) > .ulpOfOne
        switch unit {
        case .millimeters:      return isPlural ? "millimeters" : "millimeter"
        case .centimeters:      return isPlural ? "centimeters" : "centimeter"
        case .meters:           return isPlural ? "meters" : "meter"
        case .kilometers:       return isPlural ? "kilometers" : "kilometer"
        case .inches:           return isPlural ? "inches" : "inch"
        case .feet:             return isPlural ? "feet" : "foot"
        case .yards:            return isPlural ? "yards" : "yard"
        case .miles:            return isPlural ? "miles" : "mile"
        case .marathons:        return isPlural ? "marathons" : "marathon"
        case .eiffelTowers:     return isPlural ? "Eiffel Towers" : "Eiffel Tower"
        case .footballFields:   return isPlural ? "football fields" : "football field"
        case .manhattanLengths: return isPlural ? "Manhattans" : "Manhattan"
        case .custom:           return unit.shortLabel ?? ""
        }
    }
}
