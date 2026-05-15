#if canImport(AppKit)
import AppKit
import CoreGraphics
import Foundation

/// Production `EventSource` for macOS. Hybrid sampler:
/// `addGlobalMonitorForEvents` + `addLocalMonitorForEvents` for the hot path,
/// plus a low-rate `DispatchSourceTimer` backstop that polls
/// `NSEvent.mouseLocation` to catch `CGWarpMouseCursorPosition`, event-less
/// moves, and any global mouseMoved events the OS withholds from
/// non-accessibility-trusted (sandboxed) apps.
///
/// **Backstop poll rate (4 Hz).** Higher rates were tried
/// (30 Hz, 60 Hz) but compounded micro-tremor and sub-perceptual cursor
/// jitter into the running total — the integrator captured noise the user
/// didn't perceive as motion. The event monitors handle the hot path; the
/// backstop only needs to be fast enough to catch event-less repositioning
/// (CGWarp, bezel clamp, display attach) and to fill the gap for sandboxed
/// builds without Input Monitoring permission. 4 Hz means a 250 ms granularity
/// for unattended-from-the-app cursor motion — an acceptable trade-off.
///
/// `@unchecked Sendable` justification: the AppKit monitor callbacks fire
/// synchronously on arbitrary threads, so the class cannot be an `actor`
/// without a thread-hop on every cursor event. Mutable state (monitor tokens,
/// timer, `running` flag) is serialised by `stateQueue: DispatchQueue` (used
/// purely as a mutex via `.sync`); `continuation` is `AsyncStream.Continuation`
/// which is itself `Sendable` and threadsafe.
public final class SystemEventSource: EventSource, @unchecked Sendable {

    /// The current event stream. Replaced on every `start()` so a stop→start
    /// cycle (sleep/wake, manual pause/resume, midnight rollover edge cases)
    /// produces a fresh, live stream rather than handing consumers a
    /// permanently-finished one. Callers must re-read this property *after*
    /// `start()` returns — see `CursorSampler.start` which does exactly that.
    public private(set) var events: AsyncStream<CursorEvent>
    private var continuation: AsyncStream<CursorEvent>.Continuation
    /// Mutex for all mutable state below. Serial DispatchQueue accessed only
    /// via `.sync { … }` — chosen over `NSLock` to keep the lock scope syntactic
    /// and crash-loud if anyone reaches across an `await`.
    private let stateQueue = DispatchQueue(label: "co.cursorodometer.SystemEventSource.state")
    private var globalMonitor: Any?
    private var localMonitor: Any?
    private var pollTimer: DispatchSourceTimer?
    private var running = false
    private let backstopHz: Double

    public init(backstopHz: Double = 4.0) {
        self.backstopHz = backstopHz
        let (stream, cont) = Self.makeStream()
        self.events = stream
        self.continuation = cont
    }

    public func start() async {
        let alreadyRunning: Bool = stateQueue.sync {
            if self.running { return true }
            self.running = true
            return false
        }
        if alreadyRunning { return }

        // Replace the AsyncStream so anyone re-reading `events` after this
        // call gets a fresh, unfinished stream. The previous continuation (if
        // any) was finished by `stop()` — that's how its pump task exited.
        let (stream, cont) = Self.makeStream()
        stateQueue.sync {
            self.events = stream
            self.continuation = cont
        }

        let mask: NSEvent.EventTypeMask = [
            .mouseMoved,
            .leftMouseDragged,
            .rightMouseDragged,
            .otherMouseDragged
        ]
        // Global monitor: events from other apps. Returns a token we keep
        // until `stop()`.
        let g = NSEvent.addGlobalMonitorForEvents(matching: mask) { [weak self] event in
            self?.handle(event: event, origin: .global)
        }
        // Local monitor: events for our own windows. Must return the event
        // unchanged.
        let l = NSEvent.addLocalMonitorForEvents(matching: mask) { [weak self] event in
            self?.handle(event: event, origin: .local)
            return event
        }

        stateQueue.sync {
            self.globalMonitor = g
            self.localMonitor = l
        }

        // 4 Hz backstop poll. The NSEvent monitors above are
        // the hot path; the timer is a safety net for CGWarp / bezel-clamp /
        // sandbox-with-no-input-monitoring scenarios. Polling faster compounds
        // sub-perceptual tremor into the running total — see class doc.
        let interval = 1.0 / backstopHz
        let timer = DispatchSource.makeTimerSource(queue: .global(qos: .utility))
        timer.schedule(deadline: .now() + interval,
                       repeating: interval,
                       leeway: .milliseconds(50))
        timer.setEventHandler { [weak self] in
            self?.pollTick()
        }
        timer.activate()
        stateQueue.sync {
            self.pollTimer = timer
        }
    }

    public func stop() async {
        let (g, l, t, cont): (Any?, Any?, DispatchSourceTimer?, AsyncStream<CursorEvent>.Continuation?) = stateQueue.sync {
            let wasRunning = self.running
            let result = (self.globalMonitor, self.localMonitor, self.pollTimer,
                          wasRunning ? self.continuation : nil)
            self.globalMonitor = nil
            self.localMonitor = nil
            self.pollTimer = nil
            self.running = false
            return result
        }

        if let g { NSEvent.removeMonitor(g) }
        if let l { NSEvent.removeMonitor(l) }
        t?.cancel()
        // Finish the *current* continuation so the pump task iterating over
        // the snapshot of `events` it captured at start() can exit cleanly.
        // The next `start()` will install a fresh continuation.
        cont?.finish()
    }

    private static func makeStream() -> (AsyncStream<CursorEvent>, AsyncStream<CursorEvent>.Continuation) {
        var continuation: AsyncStream<CursorEvent>.Continuation!
        let stream = AsyncStream<CursorEvent>(bufferingPolicy: .unbounded) { c in
            continuation = c
        }
        return (stream, continuation)
    }

    // MARK: - private

    /// Returns the continuation that is currently live (if the source is
    /// running). Reads through `stateQueue` so the producer callbacks
    /// (`handle`, `pollTick`) never race with a `start()`-time swap.
    /// Returning `nil` when not running means in-flight timer fires after
    /// `stop()` quietly drop instead of yielding into a stale continuation.
    private func liveContinuation() -> AsyncStream<CursorEvent>.Continuation? {
        stateQueue.sync { running ? continuation : nil }
    }

    private func handle(event: NSEvent, origin: CursorEventOrigin) {
        guard let cont = liveContinuation() else { return }
        let location = NSEvent.mouseLocation
        let displayUUID = currentDisplayUUID(at: location)
        cont.yield(CursorEvent(
            location: location,
            displayUUID: displayUUID,
            timestamp: event.timestamp
        ))
    }

    private func pollTick() {
        guard let cont = liveContinuation() else { return }
        let location = NSEvent.mouseLocation
        let displayUUID = currentDisplayUUID(at: location)
        let now = ProcessInfo.processInfo.systemUptime
        cont.yield(CursorEvent(
            location: location,
            displayUUID: displayUUID,
            timestamp: now
        ))
    }

    private func currentDisplayUUID(at point: CGPoint) -> DisplayUUID? {
        // Walk NSScreen.screens, find which contains the point.
        // This is the only place outside DisplayGeometry where NSScreen is allowed.
        for screen in NSScreen.screens where screen.frame.contains(point) {
            if let n = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber {
                let displayID = CGDirectDisplayID(n.uint32Value)
                if let uuid = CGDisplayCreateUUIDFromDisplayID(displayID)?.takeRetainedValue() {
                    let cf = CFUUIDCreateString(nil, uuid) as String
                    return DisplayUUID(cf)
                }
            }
        }
        return nil
    }
}
#endif
