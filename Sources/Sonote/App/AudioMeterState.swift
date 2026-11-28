import Foundation
import SwiftUI

/// Isolated, ~25 Hz throttled audio level store so real-time audio buffer callbacks
/// only re-render the two compact waveform views instead of invalidating `AppState` across the entire app.
@MainActor
public final class AudioMeterState: ObservableObject {
    @Published public var systemLevel: Float = 0
    @Published public var micLevel: Float = 0

    public var combinedLevel: Float {
        max(systemLevel, micLevel)
    }

    private let lock = NSLock()
    private nonisolated(unsafe) var pendingSystem: Float = 0
    private nonisolated(unsafe) var pendingMic: Float = 0
    private nonisolated(unsafe) var lastDispatchTime: TimeInterval = 0
    private nonisolated(unsafe) var isScheduled: Bool = false

    public init() {}

    /// Thread-safe ingestion callable directly from audio capture callbacks (~50-100 Hz).
    public nonisolated func ingest(system: Float? = nil, mic: Float? = nil) {
        let now = ProcessInfo.processInfo.systemUptime
        var shouldSchedule = false

        lock.lock()
        if let system {
            pendingSystem = pendingSystem * 0.45 + system * 0.55
        }
        if let mic {
            pendingMic = pendingMic * 0.45 + mic * 0.55
        }
        if !isScheduled && (now - lastDispatchTime) >= 0.04 {
            isScheduled = true
            lastDispatchTime = now
            shouldSchedule = true
        }
        lock.unlock()

        if shouldSchedule {
            Task { @MainActor [weak self] in
                self?.flushOnMain()
            }
        }
    }

    private func flushOnMain() {
        lock.lock()
        let sys = pendingSystem
        let mic = pendingMic
        isScheduled = false
        lock.unlock()

        if abs(systemLevel - sys) > 0.002 || (sys == 0 && systemLevel != 0) {
            systemLevel = sys
        }
        if abs(micLevel - mic) > 0.002 || (mic == 0 && micLevel != 0) {
            micLevel = mic
        }
    }

    public func reset() {
        lock.lock()
        pendingSystem = 0
        pendingMic = 0
        isScheduled = false
        lock.unlock()
        systemLevel = 0
        micLevel = 0
    }
}

/// Dedicated waveform wrapper observing only `AudioMeterState` so parent views stay unaffected.
struct MeteredDottedWaveformView: View {
    @ObservedObject var meters: AudioMeterState
    let isActive: Bool
    let isPaused: Bool

    var body: some View {
        DoubaoDottedWaveformView(
            level: meters.combinedLevel,
            isActive: isActive,
            isPaused: isPaused
        )
    }
}

/// Dedicated mini waveform wrapper for the floating capsule observing only `AudioMeterState`.
struct MeteredMiniDottedWaveformView: View {
    @ObservedObject var meters: AudioMeterState
    let isActive: Bool
    let isPaused: Bool

    var body: some View {
        MiniDottedWaveformView(
            level: meters.combinedLevel,
            isActive: isActive,
            isPaused: isPaused
        )
    }
}
