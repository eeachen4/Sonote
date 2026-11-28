import Foundation

/// Thread-safe, pause-aware monotonic recording clock shared between the UI timer
/// and `TranscriptionCoordinator` so transcript timestamps remain strictly aligned
/// with the `.m4a` backup audio across arbitrary pause/resume cycles.
public final class RecordingClock: @unchecked Sendable {
    private let lock = NSLock()
    private var startedAt: Date?
    private var pauseStartedAt: Date?
    private var accumulatedPausedSeconds: TimeInterval = 0

    public init() {}

    public func start(at date: Date = Date()) {
        lock.withLock {
            startedAt = date
            pauseStartedAt = nil
            accumulatedPausedSeconds = 0
        }
    }

    public func pause(at date: Date = Date()) {
        lock.withLock {
            guard startedAt != nil, pauseStartedAt == nil else { return }
            pauseStartedAt = date
        }
    }

    public func resume(at date: Date = Date()) {
        lock.withLock {
            guard let pauseStart = pauseStartedAt else { return }
            accumulatedPausedSeconds += max(0, date.timeIntervalSince(pauseStart))
            pauseStartedAt = nil
        }
    }

    public func elapsed(at date: Date = Date()) -> TimeInterval {
        lock.withLock {
            guard let start = startedAt else { return 0 }
            let activePause = pauseStartedAt.map { max(0, date.timeIntervalSince($0)) } ?? 0
            return max(0, date.timeIntervalSince(start) - accumulatedPausedSeconds - activePause)
        }
    }

    public func reset() {
        lock.withLock {
            startedAt = nil
            pauseStartedAt = nil
            accumulatedPausedSeconds = 0
        }
    }
}
