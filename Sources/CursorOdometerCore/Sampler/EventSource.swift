/// Source of raw cursor position events. Hides the choice between
/// `CGEventTap`, `NSEvent.addGlobalMonitorForEvents`, and polling.
/// Implemented by `SystemEventSource` (AppKit-backed)
/// and `FakeEventStream` in tests.
public protocol EventSource: Sendable {
    /// Async stream of cursor events. Producer calls `finish()` on shutdown.
    var events: AsyncStream<CursorEvent> { get }

    /// Begin emitting events. Idempotent: repeated calls are no-ops.
    func start() async

    /// Stop emitting events and tear down monitors.
    func stop() async
}

/// Hybrid sampler distinguishes the source so we can
/// collapse duplicate global+local events.
public enum CursorEventOrigin: Sendable {
    case global       // `addGlobalMonitorForEvents` (other apps)
    case local        // `addLocalMonitorForEvents` (our own windows)
    case backstop     // 4 Hz poll catching `CGWarpMouseCursorPosition`
    case synthetic    // tests
}
