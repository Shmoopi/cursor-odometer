// CursorOdometerApp.swift — the `@main` entry point.
// MenuBarExtra root, dashboard window, settings scene, AppDelegate adaptor.
// `LSUIElement = YES` in Info.plist keeps us out of the Dock by default.

import SwiftUI
import AppKit
import OSLog
import ServiceManagement
import CursorOdometerCore

@main
struct CursorOdometerApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @StateObject private var store = AppStore.live()

    var body: some Scene {
        // MARK: Menu-bar surface (primary)
        MenuBarExtra {
            MenuBarRootView()
                .environmentObject(store)
                .onAppear { delegate.store = store }
        } label: {
            MenuBarLabel()
                .environmentObject(store)
                .onAppear { delegate.store = store }
        }
        .menuBarExtraStyle(.window)

        // MARK: Dashboard window
        Window("Dashboard", id: "dashboard") {
            DashboardView()
                .environmentObject(store)
                .onAppear {
                    // Ensure the dashboard front-most when summoned via the
                    // window-id system (e.g., menu-bar action or cmd-D).
                    WindowActivator.bringToFront(matching: "dashboard")
                }
        }
        .defaultSize(width: 1080, height: 720)
        .windowResizability(.contentMinSize)

        // MARK: Settings scene
        Settings {
            SettingsView()
                .environmentObject(store)
                .onAppear { WindowActivator.bringSettingsToFront() }
        }
    }
}

/// AppDelegate handles the bits SwiftUI doesn't reach: launch-at-login
/// registration, sleep/wake notifications, accessory activation policy.
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private static let logger = Logger(subsystem: "net.shmoopi.cursorodometer",
                                       category: "lifecycle")

    private var sleepObserver: NSObjectProtocol?
    private var wakeObserver: NSObjectProtocol?
    private var screenSleepObserver: NSObjectProtocol?
    private var screenWakeObserver: NSObjectProtocol?

    /// The view-state hub. Held weakly because SwiftUI owns the lifetime via
    /// `@StateObject`; the delegate just forwards lifecycle events into it.
    weak var store: AppStore?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Stay accessory even when the dashboard window is open.
        // This avoids the Dock-icon-pop and lets users command-tab past us.
        NSApp.setActivationPolicy(.accessory)

        registerSleepWakeObservers()
    }

    func applicationWillTerminate(_ notification: Notification) {
        // Flush on terminate. The aggregator hooks this
        // through its own observer; we just mirror the lifecycle here.
        if let s = sleepObserver { NSWorkspace.shared.notificationCenter.removeObserver(s) }
        if let w = wakeObserver { NSWorkspace.shared.notificationCenter.removeObserver(w) }
        if let s = screenSleepObserver { NSWorkspace.shared.notificationCenter.removeObserver(s) }
        if let w = screenWakeObserver { NSWorkspace.shared.notificationCenter.removeObserver(w) }
    }

    /// Sleep/wake plumbing. Forwards lifecycle events to the
    /// `AppStore`; the store currently mirrors them to `isTrackingPaused`
    /// while the real sampler/aggregator pause-resume is being wired up.
    private func registerSleepWakeObservers() {
        let nc = NSWorkspace.shared.notificationCenter
        sleepObserver = nc.addObserver(forName: NSWorkspace.willSleepNotification,
                                       object: nil,
                                       queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.store?.handleSystemSleep()
            }
        }
        wakeObserver = nc.addObserver(forName: NSWorkspace.didWakeNotification,
                                      object: nil,
                                      queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.store?.handleSystemWake()
            }
        }
        screenSleepObserver = nc.addObserver(forName: NSWorkspace.screensDidSleepNotification,
                                             object: nil,
                                             queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.store?.handleScreensSleep()
            }
        }
        // Symmetric to screensDidSleep — without this, an overnight display
        // sleep would leave the sampler stopped indefinitely (the only path
        // to restart it would be a full system sleep+wake cycle).
        screenWakeObserver = nc.addObserver(forName: NSWorkspace.screensDidWakeNotification,
                                            object: nil,
                                            queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.store?.handleScreensWake()
            }
        }
    }

    // MARK: Login item helper

    /// Registers (or unregisters) the app as a login item via SMAppService.
    /// Called from Settings → General.
    static func setLaunchAtLogin(_ enabled: Bool) {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            // Always log — `Logger` redacts user data by default and is cheap;
            // production wiring will additionally surface a non-blocking
            // notification. No `#if DEBUG` guard so we still get
            // signal in TestFlight / shipped builds via Console.app.
            logger.error("setLaunchAtLogin(\(enabled, privacy: .public)) failed: \(error.localizedDescription, privacy: .public)")
        }
    }
}
