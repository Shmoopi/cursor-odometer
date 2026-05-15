import Foundation
@testable import CursorOdometerCore

/// `EventSource` driven by hand-crafted `CursorEvent`s.
/// Mirrors `SystemEventSource`'s lifecycle contract: each `start()` swaps in
/// a fresh `AsyncStream` + continuation so a stop→start cycle yields a live
/// stream rather than re-handing consumers a finished one.
public final class FakeEventStream: EventSource, @unchecked Sendable {
    public private(set) var events: AsyncStream<CursorEvent>
    private var continuation: AsyncStream<CursorEvent>.Continuation
    /// Serial queue used purely as an async-safe mutex via `.sync`. NSLock
    /// is unavailable from `async` contexts under Swift 6 concurrency rules,
    /// so we mirror the SystemEventSource pattern.
    private let stateQueue = DispatchQueue(label: "co.cursorodometer.FakeEventStream.state")
    private var startCount = 0
    private var stopCount = 0
    /// `true` between `start()` and `stop()`.
    private var running = false

    public init() {
        let (stream, cont) = Self.makeStream()
        self.events = stream
        self.continuation = cont
    }

    public func emit(_ event: CursorEvent) {
        let cont = stateQueue.sync { continuation }
        cont.yield(event)
    }

    public func finish() {
        let cont = stateQueue.sync { continuation }
        cont.finish()
    }

    public func start() async {
        stateQueue.sync {
            startCount += 1
            // If previously stopped, install a fresh stream + continuation so
            // the next pump task iterates over a live source.
            if !running {
                let (stream, cont) = Self.makeStream()
                self.events = stream
                self.continuation = cont
                self.running = true
            }
        }
    }

    public func stop() async {
        let cont: AsyncStream<CursorEvent>.Continuation? = stateQueue.sync {
            stopCount += 1
            guard running else { return nil }
            running = false
            return continuation
        }
        cont?.finish()
    }

    private static func makeStream() -> (AsyncStream<CursorEvent>, AsyncStream<CursorEvent>.Continuation) {
        var continuation: AsyncStream<CursorEvent>.Continuation!
        let stream = AsyncStream<CursorEvent>(bufferingPolicy: .unbounded) { c in
            continuation = c
        }
        return (stream, continuation)
    }

    /// Count of `start()` invocations — used to assert idempotence.
    public var startInvocations: Int {
        stateQueue.sync { startCount }
    }

    /// Count of `stop()` invocations.
    public var stopInvocations: Int {
        stateQueue.sync { stopCount }
    }
}
