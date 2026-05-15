// Typography.swift — design tokens.
// SF Pro Display/Text for chrome, SF Pro Rounded for unit suffixes & section
// headers, SF Mono with `.monospacedDigit()` for ALL distance numerals.
// Tabular figures are non-negotiable — they are the rolling-odometer feel.

import SwiftUI

// MARK: - Font roles

extension Font {
    // Hero numerals — popover (56pt) and dashboard (88pt). Tracking values come
    // from the design token table; we approximate via `.kerning` at the Text site.
    static let heroNumber: Font = .system(size: 56, weight: .semibold, design: .monospaced)
    static let heroNumberDashboard: Font = .system(size: 88, weight: .semibold, design: .monospaced)

    /// 22pt SF Pro Rounded Medium — paired with the numeric hero. The rounded
    /// face humanises the precision; a Reeder body × aircraft instrument readout.
    static let heroUnit: Font = .system(size: 22, weight: .medium, design: .rounded)

    /// 13pt SF Pro Semibold, uppercase tracking +0.6 (apply via `.tracking()`).
    static let sectionTitle: Font = .system(size: 13, weight: .semibold, design: .default)

    /// 13pt SF Pro Regular — every standard label.
    static let bodyLabel: Font = .system(size: 13, weight: .regular, design: .default)

    /// 11pt SF Pro Regular — footnotes, per-display rows, captions.
    static let metaCaption: Font = .system(size: 11, weight: .regular, design: .default)

    /// 13pt SF Mono Regular — inline numbers (delta value, sparkline tooltip).
    /// Always pair with `.monospacedDigit()` on the Text view.
    static let numeralInline: Font = .system(size: 13, weight: .regular, design: .monospaced)
}

// MARK: - Text view helpers

extension Text {
    /// Render a section title in our house style: SF Pro Semibold, uppercase,
    /// +0.6 tracking, secondary color.
    func sectionTitleStyle() -> some View {
        self
            .font(.sectionTitle)
            .textCase(.uppercase)
            .tracking(0.6)
            .foregroundStyle(.secondary)
    }

    /// Render a hero number. Tabular digits, kerning -1.5 to mimic the
    /// design's negative tracking, primary color.
    func heroNumberStyle() -> some View {
        self
            .font(.heroNumber)
            .monospacedDigit()
            .kerning(-1.5)
            .foregroundStyle(.primary)
    }

    /// Render a dashboard hero number (88pt). Stronger negative kerning.
    func heroDashboardStyle() -> some View {
        self
            .font(.heroNumberDashboard)
            .monospacedDigit()
            .kerning(-2.0)
            .foregroundStyle(.primary)
    }

    /// Render a unit suffix next to a hero number.
    func heroUnitStyle() -> some View {
        self
            .font(.heroUnit)
            .foregroundStyle(.secondary)
    }
}

// MARK: - Dynamic Type clamps

extension View {
    /// Clamp Dynamic Type at `xxxLarge` to prevent hero clipping.
    /// Apply only to the hero number; the rest of the UI scales freely.
    func heroDynamicTypeClamp() -> some View {
        self.dynamicTypeSize(...DynamicTypeSize.xxxLarge)
    }
}

// MARK: - Previews

#Preview("Typography ladder") {
    VStack(alignment: .leading, spacing: Space.s4) {
        Text("CURSOR ODOMETER · TODAY").sectionTitleStyle()

        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Text("1,247.3").heroNumberStyle()
            Text("m").heroUnitStyle()
        }

        VStack(alignment: .leading, spacing: 4) {
            Text("Body label — 13pt SF Pro Regular").font(.bodyLabel)
            Text("Meta caption — 11pt").font(.metaCaption).foregroundStyle(.secondary)
            Text("Inline numeral 312 m").font(.numeralInline).monospacedDigit()
        }

        Divider().background(Color.hairline)

        Text("88.8 km").heroDashboardStyle()
    }
    .padding(Space.s5)
    .frame(width: 360)
    .background(Color.surface)
}
