// UnitsTab.swift — primary/secondary unit pickers + Custom Unit Definer.
// "Custom Unit Definer is the killer feature for content marketing."
// UI must be effortless: three fields, one button, immediate preview.

import SwiftUI
import CursorOdometerCore

struct UnitsTab: View {
    @EnvironmentObject private var store: AppStore
    @State private var newUnitName: String = ""
    @State private var newUnitPlural: String = ""
    @State private var newUnitMeters: String = ""

    var body: some View {
        Form {
            Section("Display") {
                Picker("Primary unit", selection: $store.settings.primaryUnit) {
                    ForEach(orderedBuiltInUnits, id: \.self) { unit in
                        Text(label(for: unit)).tag(unit)
                    }
                    if !store.customUnits.isEmpty {
                        Divider()
                        ForEach(store.customUnits) { custom in
                            Text(custom.pluralName)
                                .tag(UnitPreference.custom(id: custom.id))
                        }
                    }
                }

                Toggle("Show secondary unit",
                       isOn: Binding(
                        get: { store.settings.secondaryUnit != nil },
                        set: { store.settings.secondaryUnit = $0 ? .kilometers : nil }
                       ))

                if store.settings.secondaryUnit != nil {
                    Picker("Secondary",
                           selection: Binding(
                            get: { store.settings.secondaryUnit ?? UnitPreference.meters },
                            set: { store.settings.secondaryUnit = $0 }
                           )) {
                        ForEach(orderedBuiltInUnits, id: \.self) { unit in
                            Text(label(for: unit)).tag(unit)
                        }
                    }
                }
            }

            Section {
                Text("Define your own ruler. We've seen \"banana,\" \"my cat,\" \"bus length,\" \"Manhattan,\" and one user who measures only in iPhone diagonals.")
                    .font(.metaCaption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                TextField("Name (singular)", text: $newUnitName, prompt: Text("banana"))
                TextField("Plural", text: $newUnitPlural, prompt: Text("bananas"))
                TextField("Meters per unit", text: $newUnitMeters, prompt: Text("0.18"))

                if !newUnitName.isEmpty,
                   let m = Double(newUnitMeters), m > 0 {
                    HStack {
                        Image(systemName: "eye")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                        Text("Today's distance:")
                            .font(.metaCaption)
                            .foregroundStyle(.secondary)
                        let formatter = DistanceFormatter(customUnits:
                            store.customUnits + [
                                CustomUnit(id: "preview",
                                           name: newUnitName,
                                           pluralName: newUnitPlural.isEmpty ? newUnitName + "s" : newUnitPlural,
                                           metersPerUnit: m)
                            ]
                        )
                        let f = formatter.format(store.todayDistance, in: .custom(id: "preview"))
                        Spacer()
                        Text(f.fullText)
                            .font(.numeralInline)
                            .monospacedDigit()
                            .foregroundStyle(.primary)
                    }
                }

                HStack {
                    Spacer()
                    Button("Add Unit") { addCustomUnit() }
                        .buttonStyle(.borderedProminent)
                        .disabled(!canSubmit)
                }

                VStack(alignment: .leading, spacing: 6) {
                    Text("Quick start")
                        .font(.metaCaption)
                        .foregroundStyle(.secondary)
                    SuggestionFlow(suggestions: CustomUnit.suggestions) { suggestion in
                        newUnitName = suggestion.name
                        newUnitPlural = suggestion.pluralName
                        newUnitMeters = String(suggestion.metersPerUnit)
                    }
                }
                .padding(.top, 2)
            } header: {
                Text("Custom Unit")
            }

            if !store.customUnits.isEmpty {
                Section("Your custom units") {
                    ForEach(store.customUnits) { unit in
                        CustomUnitRow(unit: unit) {
                            store.customUnits.removeAll { $0.id == unit.id }
                        }
                    }
                }
            }
        }
        .formStyle(.grouped)
    }

    private var orderedBuiltInUnits: [UnitPreference] {
        [.millimeters, .centimeters, .meters, .kilometers,
         .inches, .feet, .yards, .miles,
         .marathons, .eiffelTowers, .footballFields, .manhattanLengths]
    }

    private func label(for unit: UnitPreference) -> String {
        unit.shortLabel ?? "—"
    }

    private var canSubmit: Bool {
        !newUnitName.trimmingCharacters(in: .whitespaces).isEmpty &&
        Double(newUnitMeters).map { $0 > 0 } == true
    }

    private func addCustomUnit() {
        guard let m = Double(newUnitMeters), m > 0 else { return }
        let id = newUnitName.lowercased().replacingOccurrences(of: " ", with: "-")
        let plural = newUnitPlural.isEmpty ? newUnitName + "s" : newUnitPlural
        let unit = CustomUnit(id: id, name: newUnitName, pluralName: plural, metersPerUnit: m)
        store.customUnits.append(unit)
        newUnitName = ""
        newUnitPlural = ""
        newUnitMeters = ""
    }
}

private struct CustomUnitRow: View {
    let unit: CustomUnit
    let onDelete: () -> Void

    var body: some View {
        HStack(spacing: Space.s2) {
            Image(systemName: "ruler")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Color.colorPrimary)
                .frame(width: 22, height: 22)
                .background(Circle().fill(Color.colorPrimary.opacity(0.10)))

            VStack(alignment: .leading, spacing: 1) {
                Text(unit.pluralName.capitalized)
                    .font(.system(size: 13, weight: .medium))
                Text("1 \(unit.name) = \(formatMeters(unit.metersPerUnit))")
                    .font(.metaCaption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button(role: .destructive, action: onDelete) {
                Image(systemName: "trash")
            }
            .buttonStyle(.borderless)
            .controlSize(.small)
        }
    }

    private func formatMeters(_ m: Double) -> String {
        if m >= 1000 { return String(format: "%.2f km", m / 1000) }
        if m >= 1 { return String(format: "%.2f m", m) }
        if m >= 0.01 { return String(format: "%.1f cm", m * 100) }
        return String(format: "%.0f mm", m * 1000)
    }
}

private struct SuggestionFlow: View {
    let suggestions: [CustomUnit]
    let onPick: (CustomUnit) -> Void

    var body: some View {
        FlowLayout(spacing: 6) {
            ForEach(suggestions, id: \.id) { sug in
                Button(sug.name) { onPick(sug) }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
            }
        }
    }
}

/// Simple wrapping flow layout. Used here so the "Quick start" pills wrap
/// rather than truncate when the suggestion list grows.
private struct FlowLayout: Layout {
    var spacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxWidth = proposal.width ?? .infinity
        var x: CGFloat = 0
        var y: CGFloat = 0
        var rowHeight: CGFloat = 0
        var totalWidth: CGFloat = 0
        for view in subviews {
            let size = view.sizeThatFits(.unspecified)
            if x + size.width > maxWidth, x > 0 {
                y += rowHeight + spacing
                x = 0
                rowHeight = 0
            }
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
            totalWidth = max(totalWidth, x)
        }
        return CGSize(width: totalWidth, height: y + rowHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x: CGFloat = bounds.minX
        var y: CGFloat = bounds.minY
        var rowHeight: CGFloat = 0
        for view in subviews {
            let size = view.sizeThatFits(.unspecified)
            if x + size.width > bounds.maxX, x > bounds.minX {
                y += rowHeight + spacing
                x = bounds.minX
                rowHeight = 0
            }
            view.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(width: size.width, height: size.height))
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
    }
}

#Preview("Units tab") {
    UnitsTab()
        .environmentObject(AppStore.preview())
        .frame(width: 580, height: 600)
}
