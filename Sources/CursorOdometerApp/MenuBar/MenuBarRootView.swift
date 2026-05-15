// MenuBarRootView.swift — menu-bar popover.
//
// A centered, single-glance surface: brand strip up top, today's distance
// hero in the middle, a 7-day sparkline for context, and the three primary
// actions across the bottom. Deeper analysis lives in the dashboard.

import SwiftUI
import AppKit
import CursorOdometerCore

struct MenuBarRootView: View {
    @EnvironmentObject private var store: AppStore
    @Environment(\.openWindow) private var openWindow
    @Environment(\.openSettings) private var openSettings

    var body: some View {
        if !store.hasOnboarded {
            OnboardingView()
                .transition(.opacity)
        } else {
            VStack(spacing: Space.s4) {
                BrandStrip()
                HeroBlock()
                if !store.weeklyTrend.isEmpty {
                    SparklineBlock()
                }
                Hairline()
                FooterRow(openDashboard: openDashboard,
                          openSettingsAction: openSettingsWindow)
            }
            .padding(.horizontal, Space.s5)
            .padding(.vertical, Space.s4)
            .frame(width: 360, alignment: .center)
            .background(PopoverSurface())
            .contextMenu { contextMenuContent }
        }
    }

    @ViewBuilder
    private var contextMenuContent: some View {
        Button(store.isTrackingPaused ? "Resume Tracking" : "Pause Tracking") {
            store.toggleTrackingPaused()
        }
        Button("Copy Today's Distance") { copyTodayDistance() }
        Button("Reset Today…", role: .destructive) { confirmAndResetToday() }
        Divider()
        Button("Quit Cursor Odometer") { NSApp.terminate(nil) }
            .keyboardShortcut("q", modifiers: .command)
    }

    private func openDashboard() {
        openWindow(id: "dashboard")
        WindowActivator.bringToFront(matching: "dashboard")
    }

    private func openSettingsWindow() {
        openSettings()
        WindowActivator.bringSettingsToFront()
    }

    private func copyTodayDistance() {
        let formatter = DistanceFormatter(customUnits: store.customUnits)
        let f = formatter.format(store.todayDistance, in: store.activeHeroUnit)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(f.fullText, forType: .string)
    }

    private func confirmAndResetToday() {
        let alert = NSAlert()
        alert.messageText = "Reset today's distance?"
        alert.informativeText = "This deletes everything Cursor Odometer recorded for today. Your lifetime total will be reduced by the same amount. This cannot be undone."
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Reset Today")
        alert.addButton(withTitle: "Cancel")
        if alert.runModal() == .alertFirstButtonReturn {
            Task { await store.resetToday() }
        }
    }
}

// MARK: - Surface

/// Subtle vertical gradient with a hairline border — gives the popover a bit
/// of depth without competing with the hero number.
private struct PopoverSurface: View {
    var body: some View {
        ZStack {
            Color.surface
            LinearGradient(
                colors: [
                    Color.colorPrimary.opacity(0.06),
                    Color.colorPrimary.opacity(0.0)
                ],
                startPoint: .top,
                endPoint: .center
            )
        }
        .overlay(alignment: .top) {
            // A faint accent line right at the top edge — a small flourish
            // that ties the popover back to the brand color.
            Rectangle()
                .fill(
                    LinearGradient(
                        colors: [.clear, Color.colorPrimary.opacity(0.45), .clear],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
                .frame(height: 1)
        }
        .accessibilityHidden(true)
    }
}

// MARK: - Brand strip

private struct BrandStrip: View {
    @EnvironmentObject private var store: AppStore

    var body: some View {
        HStack(spacing: Space.s2) {
            Spacer(minLength: 0)

            Image(systemName: "cursorarrow.motionlines")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Color.colorPrimary)

            Text("CURSOR ODOMETER")
                .font(.system(size: 10, weight: .semibold))
                .tracking(1.4)
                .foregroundStyle(.secondary)

            StatusDot(isPaused: store.isTrackingPaused)

            Spacer(minLength: 0)
        }
    }
}

private struct StatusDot: View {
    let isPaused: Bool
    @State private var pulse = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Circle()
            .fill(isPaused ? Color.secondary : Color.colorOnTrack)
            .frame(width: 6, height: 6)
            .overlay(
                Circle()
                    .stroke(isPaused ? Color.secondary.opacity(0.3)
                                     : Color.colorOnTrack.opacity(0.4),
                            lineWidth: 2)
                    .scaleEffect(pulse ? 2.4 : 1.0)
                    .opacity(pulse ? 0 : 0.7)
            )
            .accessibilityLabel(isPaused ? "Tracking paused" : "Tracking active")
            .onAppear {
                guard !reduceMotion, !isPaused else { return }
                withAnimation(.easeOut(duration: 1.6).repeatForever(autoreverses: false)) {
                    pulse = true
                }
            }
    }
}

// MARK: - Hero block

private struct HeroBlock: View {
    @EnvironmentObject private var store: AppStore

    var body: some View {
        let formatter = DistanceFormatter(customUnits: store.customUnits)
        let f = formatter.format(store.todayDistance, in: store.activeHeroUnit)

        VStack(spacing: Space.s1) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(f.numberText)
                    .font(.system(size: 42, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(.primary)
                Button(action: { store.cycleHeroUnit() }) {
                    Text(f.unitLabel)
                        .font(.system(size: 16, weight: .medium, design: .rounded))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .help("Tap to cycle units")
            }
            .lineLimit(1)
            .minimumScaleFactor(0.6)

            Text(store.isTrackingPaused ? "today · paused" : "today")
                .font(.system(size: 11, weight: .medium))
                .tracking(0.4)
                .textCase(.uppercase)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Today: \(f.numberText) \(f.unitLabel).\(store.isTrackingPaused ? " Tracking paused." : "")")
    }
}

// MARK: - Sparkline block

private struct SparklineBlock: View {
    @EnvironmentObject private var store: AppStore

    var body: some View {
        VStack(spacing: Space.s1) {
            SparklineView(values: store.weeklyTrend, height: 28)
                .frame(maxWidth: .infinity, alignment: .center)

            Text("LAST 7 DAYS")
                .font(.system(size: 9, weight: .semibold))
                .tracking(1.2)
                .foregroundStyle(.tertiary)
        }
    }
}

// MARK: - Footer row

private struct FooterRow: View {
    let openDashboard: () -> Void
    let openSettingsAction: () -> Void

    var body: some View {
        HStack(spacing: Space.s2) {
            FooterButton(title: "Dashboard",
                         systemImage: "chart.bar.xaxis",
                         action: openDashboard)
            FooterButton(title: "Settings",
                         systemImage: "gearshape",
                         action: openSettingsAction)
            FooterButton(title: "Quit",
                         systemImage: "power") { NSApp.terminate(nil) }
        }
    }
}

private struct FooterButton: View {
    let title: String
    let systemImage: String
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            VStack(spacing: 3) {
                Image(systemName: systemImage)
                    .font(.system(size: 13, weight: .semibold))
                Text(title)
                    .font(.system(size: 11, weight: .medium))
                    .lineLimit(1)
                    .fixedSize()
            }
            .foregroundStyle(hovering ? Color.colorPrimary : Color.primary)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: Radius.sm, style: .continuous)
                    .fill(hovering ? Color.colorPrimary.opacity(0.12) : Color.primary.opacity(0.04))
                    .overlay(
                        RoundedRectangle(cornerRadius: Radius.sm, style: .continuous)
                            .strokeBorder(hovering ? Color.colorPrimary.opacity(0.45) : Color.hairline,
                                          lineWidth: 1)
                    )
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
    }
}

// MARK: - Previews

#Preview("Popover — typical") {
    let store = AppStore.preview(scenario: .typical)
    store.markOnboarded()
    return MenuBarRootView()
        .environmentObject(store)
}

#Preview("Popover — empty") {
    let store = AppStore.preview(scenario: .empty)
    store.markOnboarded()
    return MenuBarRootView()
        .environmentObject(store)
}

#Preview("Popover — dark") {
    let store = AppStore.preview(scenario: .typical)
    store.markOnboarded()
    return MenuBarRootView()
        .environmentObject(store)
        .preferredColorScheme(.dark)
}
