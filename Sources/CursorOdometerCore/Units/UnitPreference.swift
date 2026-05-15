/// All supported display units (built-in: pixels, inches,
/// cm, meters, feet, miles, kilometers + Pro custom units).
public enum UnitPreference: Hashable, Sendable, Codable {
    case millimeters
    case centimeters
    case meters
    case kilometers
    case inches
    case feet
    case yards
    case miles
    case marathons          // 42.195 km
    case eiffelTowers       // 330 m
    case footballFields     // 109.7 m (American)
    case manhattanLengths   // ~21.6 km tip-to-tip
    case custom(id: String) // looked up against `SettingsValues.customUnits`
}

/// User-defined unit. "Custom Unit Definer is the killer feature
/// for content marketing".
public struct CustomUnit: Hashable, Sendable, Codable, Identifiable {
    public let id: String
    public var name: String           // singular, e.g. "banana"
    public var pluralName: String     // e.g. "bananas"
    public var metersPerUnit: Double  // e.g. 0.18

    public init(id: String, name: String, pluralName: String, metersPerUnit: Double) {
        self.id = id
        self.name = name
        self.pluralName = pluralName
        self.metersPerUnit = metersPerUnit
    }

    /// Suggested seeds shown on the empty-state of the unit definer.
    /// "Try: bus length, football field, banana, my cat".
    public static let suggestions: [CustomUnit] = [
        CustomUnit(id: "banana", name: "banana", pluralName: "bananas", metersPerUnit: 0.18),
        CustomUnit(id: "bus",    name: "bus length", pluralName: "bus lengths", metersPerUnit: 12.0),
        CustomUnit(id: "field",  name: "football field", pluralName: "football fields", metersPerUnit: 109.7),
        CustomUnit(id: "cat",    name: "my cat", pluralName: "cats", metersPerUnit: 0.46),
        CustomUnit(id: "subway", name: "subway car", pluralName: "subway cars", metersPerUnit: 18.4)
    ]
}

/// Hard-coded conversion to meters for the built-in units. Custom units
/// resolve against `CustomUnit.metersPerUnit`.
public extension UnitPreference {
    var metersPerUnit: Double? {
        switch self {
        case .millimeters:      return 0.001
        case .centimeters:      return 0.01
        case .meters:           return 1
        case .kilometers:       return 1_000
        case .inches:           return 0.0254
        case .feet:             return 0.3048
        case .yards:            return 0.9144
        case .miles:            return 1609.344
        case .marathons:        return 42_195
        case .eiffelTowers:     return 330
        case .footballFields:   return 109.7
        case .manhattanLengths: return 21_600
        case .custom:           return nil  // resolved externally
        }
    }

    /// Standard unit suffix for the formatter. Returns `nil` for custom,
    /// which must be resolved against `CustomUnit`.
    var shortLabel: String? {
        switch self {
        case .millimeters:      return "mm"
        case .centimeters:      return "cm"
        case .meters:           return "m"
        case .kilometers:       return "km"
        case .inches:           return "in"
        case .feet:             return "ft"
        case .yards:            return "yd"
        case .miles:            return "mi"
        case .marathons:        return "marathons"
        case .eiffelTowers:     return "Eiffel Towers"
        case .footballFields:   return "football fields"
        case .manhattanLengths: return "Manhattans"
        case .custom:           return nil
        }
    }
}
