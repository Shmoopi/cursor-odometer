/// User-facing settings, persisted to `UserDefaults` (App Group suite).
public struct SettingsValues: Hashable, Sendable, Codable {
    public var primaryUnit: UnitPreference
    public var secondaryUnit: UnitPreference?
    public var customUnits: [CustomUnit]
    public var launchAtLogin: Bool
    public var idleThresholdSeconds: Int
    public var countMotionWhileLocked: Bool
    public var countCrossDisplayTransitions: Bool
    public var menuBarShowsTextLabel: Bool
    public var menuBarLabelFormat: MenuBarLabelFormat
    public var battleryThrottleEnabled: Bool
    public var trackedDisplays: Set<DisplayUUID>  // empty = track all
    public var displayNicknames: [DisplayUUID: String]

    public static let defaults = SettingsValues(
        primaryUnit: .meters,
        secondaryUnit: nil,
        customUnits: [],
        launchAtLogin: false,
        idleThresholdSeconds: 60,
        countMotionWhileLocked: false,
        countCrossDisplayTransitions: false,
        menuBarShowsTextLabel: false,
        menuBarLabelFormat: .glyphAndDistance,
        battleryThrottleEnabled: true,
        trackedDisplays: [],
        displayNicknames: [:]
    )

    public init(
        primaryUnit: UnitPreference,
        secondaryUnit: UnitPreference?,
        customUnits: [CustomUnit],
        launchAtLogin: Bool,
        idleThresholdSeconds: Int,
        countMotionWhileLocked: Bool,
        countCrossDisplayTransitions: Bool,
        menuBarShowsTextLabel: Bool,
        menuBarLabelFormat: MenuBarLabelFormat,
        battleryThrottleEnabled: Bool,
        trackedDisplays: Set<DisplayUUID>,
        displayNicknames: [DisplayUUID: String]
    ) {
        self.primaryUnit = primaryUnit
        self.secondaryUnit = secondaryUnit
        self.customUnits = customUnits
        self.launchAtLogin = launchAtLogin
        self.idleThresholdSeconds = idleThresholdSeconds
        self.countMotionWhileLocked = countMotionWhileLocked
        self.countCrossDisplayTransitions = countCrossDisplayTransitions
        self.menuBarShowsTextLabel = menuBarShowsTextLabel
        self.menuBarLabelFormat = menuBarLabelFormat
        self.battleryThrottleEnabled = battleryThrottleEnabled
        self.trackedDisplays = trackedDisplays
        self.displayNicknames = displayNicknames
    }
}

public enum MenuBarLabelFormat: String, Codable, Sendable, CaseIterable {
    case glyphAndDistance        // "[reel] 1.2 km today"
    case distanceOnly            // "1.2 km today"
    case distanceWithoutPeriod   // "1.2 km"
}
