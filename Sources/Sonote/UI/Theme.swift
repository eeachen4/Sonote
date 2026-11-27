import SwiftUI

enum AppTheme {
    // Doubao Work ultra-clean light palette
    static let canvasWhite = Color.white
    static let leftPaneBg = Color(red: 0.984, green: 0.986, blue: 0.992)   // #FAFAFC
    static let divider = Color(red: 0.935, green: 0.940, blue: 0.952)      // #EFF0F3

    static let textPrimary = Color(red: 0.10, green: 0.11, blue: 0.14)     // #1A1C24
    static let textSecondary = Color(red: 0.52, green: 0.56, blue: 0.62)   // #858F9E
    static let textMuted = Color(red: 0.68, green: 0.71, blue: 0.76)

    static let brandPrimary = Color(red: 0.13, green: 0.43, blue: 0.97)    // #216EF7
    static let brandSoftFill = Color(red: 0.915, green: 0.948, blue: 1.0)  // #E9F2FF (Pause button / Mind-map pills)
    static let mindMapNodeFill = Color(red: 0.937, green: 0.958, blue: 0.996) // #EFF4FE
    static let mindMapLine = Color(red: 0.89, green: 0.92, blue: 0.98)

    static let neutralPill = Color(red: 0.949, green: 0.953, blue: 0.961)  // #F2F3F5
    static let softCardBg = Color(red: 0.973, green: 0.976, blue: 0.982)   // #F8F9FA
    static let skeletonBg = Color(red: 0.925, green: 0.933, blue: 0.945)   // #ECEEF1
    static let subtleBorder = Color(red: 0.90, green: 0.91, blue: 0.93)

    static let recordingRed = Color(red: 0.93, green: 0.26, blue: 0.28)
    static let successGreen = Color(red: 0.12, green: 0.68, blue: 0.43)
    static let warningAmber = Color(red: 0.90, green: 0.58, blue: 0.12)
}

/// Horizontal row of fine rounded dots that gently animate with real-time audio amplitude,
/// matching Doubao Work's signature recording waveform bar.
struct DoubaoDottedWaveformView: View {
    let level: Float
    let isActive: Bool
    let isPaused: Bool

    @State private var history: [Float] = Array(repeating: 0.0, count: 52)
    private let dotCount = 52

    var body: some View {
        HStack(spacing: 4) {
            ForEach(0..<dotCount, id: \.self) { index in
                let sample = history[index]
                let activeHeight: CGFloat = isActive && !isPaused
                    ? max(3.5, min(22, 3.5 + CGFloat(sample) * 20.0))
                    : 3.5
                Capsule()
                    .fill(sample > 0.08 && isActive && !isPaused
                          ? AppTheme.brandPrimary.opacity(0.65)
                          : Color(red: 0.72, green: 0.75, blue: 0.79))
                    .frame(width: 2.5, height: activeHeight)
                    .animation(.easeOut(duration: 0.12), value: sample)
            }
        }
        .frame(height: 24)
        .onChange(of: level) { _, newVal in
            var next = history
            next.removeFirst()
            // Add slight organic variation when signal is live
            let jitter = newVal > 0.02 ? Float.random(in: 0.82...1.18) : 1.0
            next.append(min(1.0, newVal * jitter))
            history = next
        }
    }
}

/// Subtle airy light-ray wash in the top-right corner of the completed document page,
/// matching Doubao Work's post-recording summary canvas.
struct DoubaoSoftLightBackdrop: View {
    var body: some View {
        ZStack {
            AppTheme.canvasWhite
            LinearGradient(
                colors: [
                    Color(red: 0.93, green: 0.94, blue: 0.96).opacity(0.55),
                    Color.white.opacity(0.0)
                ],
                startPoint: .topTrailing,
                endPoint: .center
            )
            RadialGradient(
                colors: [
                    Color(red: 0.90, green: 0.93, blue: 0.98).opacity(0.32),
                    Color.clear
                ],
                center: UnitPoint(x: 0.85, y: 0.08),
                startRadius: 20,
                endRadius: 360
            )
        }
        .ignoresSafeArea()
    }
}

struct SkeletonPill: View {
    let width: CGFloat?
    let height: CGFloat
    var fill: Color = AppTheme.skeletonBg
    var cornerRadius: CGFloat = 6

    @State private var pulse = false

    var body: some View {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            .fill(fill)
            .frame(maxWidth: width == nil ? .infinity : width, minHeight: height, maxHeight: height)
            .opacity(pulse ? 0.62 : 1.0)
            .animation(.easeInOut(duration: 1.35).repeatForever(autoreverses: true), value: pulse)
            .onAppear { pulse = true }
    }
}

struct RecordingPulseDot: View {
    let isActive: Bool
    let isPaused: Bool
    @State private var pulse = false

    var body: some View {
        ZStack {
            if isActive && !isPaused {
                Circle()
                    .fill(AppTheme.brandPrimary.opacity(0.28))
                    .frame(width: 12, height: 12)
                    .scaleEffect(pulse ? 1.4 : 0.85)
                    .opacity(pulse ? 0.15 : 0.8)
                    .animation(.easeInOut(duration: 1.0).repeatForever(autoreverses: true), value: pulse)
            }
            Circle()
                .fill(isPaused ? AppTheme.warningAmber : (isActive ? AppTheme.brandPrimary : AppTheme.textMuted))
                .frame(width: 7, height: 7)
        }
        .onAppear { pulse = true }
    }
}
