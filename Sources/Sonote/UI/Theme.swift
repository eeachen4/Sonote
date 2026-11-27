import SwiftUI
import AppKit
import SonoteCore

// MARK: - Live Theme, Appearance & Interface Language Controller

@MainActor
public final class ThemeManager: ObservableObject {
    public static let shared = ThemeManager()

    @Published public var appearance: AppAppearanceMode = .light
    @Published public var accent: AppAccentTheme = .cobaltBlue
    @Published public var language: AppInterfaceLanguage = .system
    @Published public var fontScale: AppFontScale = .standard

    public var isEnglish: Bool {
        language.resolvedIsEnglish
    }

    public var preferredColorScheme: ColorScheme? {
        switch appearance {
        case .system: return nil
        case .light: return .light
        case .dark: return .dark
        }
    }

    public var nsAppearance: NSAppearance? {
        switch appearance {
        case .system: return nil
        case .light: return NSAppearance(named: .aqua)
        case .dark: return NSAppearance(named: .darkAqua)
        }
    }

    public func sync(with settings: AppSettings) {
        let isEn = settings.interfaceLanguage.resolvedIsEnglish
        AppTheme.activeAccent = settings.accentTheme
        AppTheme.activeFontScale = settings.fontScale
        AppTheme.activeIsEnglish = isEn
        SonoteLocale.isEnglish = isEn

        if appearance != settings.appearanceMode {
            appearance = settings.appearanceMode
        }
        if accent != settings.accentTheme {
            accent = settings.accentTheme
        }
        if language != settings.interfaceLanguage {
            language = settings.interfaceLanguage
        }
        if fontScale != settings.fontScale {
            fontScale = settings.fontScale
        }
        applyNSAppAppearance()
    }

    public func applyNSAppAppearance() {
        NSApp?.appearance = nsAppearance
    }

    public func l(_ zh: String, _ en: String) -> String {
        isEnglish ? en : zh
    }
}

/// Concise live bilingual string lookup reflecting General Settings -> Interface Language.
@MainActor
func L(_ zh: String, _ en: String) -> String {
    AppTheme.activeIsEnglish ? en : zh
}

// MARK: - Adaptive Light / Dark + Dynamic Accent Palette

enum AppTheme {
    @MainActor static var activeAccent: AppAccentTheme = .cobaltBlue
    @MainActor static var activeFontScale: AppFontScale = .standard
    @MainActor static var activeIsEnglish: Bool = false

    @MainActor
    static func scaled(_ baseSize: CGFloat) -> CGFloat {
        (baseSize * CGFloat(activeFontScale.multiplier)).rounded(.toNearestOrAwayFromZero)
    }

    private static func dynamic(light: NSColor, dark: NSColor) -> Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            let match = appearance.bestMatch(from: [.darkAqua, .aqua])
            return match == .darkAqua ? dark : light
        })
    }

    static func accentColor(for theme: AppAccentTheme) -> Color {
        let l = theme.lightRGB
        let d = theme.darkRGB
        return dynamic(
            light: NSColor(srgbRed: l.r, green: l.g, blue: l.b, alpha: 1.0),
            dark: NSColor(srgbRed: d.r, green: d.g, blue: d.b, alpha: 1.0)
        )
    }

    // Surfaces (Doubao-clean light canvas + refined Linear-grade charcoal dark mode)
    static let canvasWhite = dynamic(
        light: NSColor(srgbRed: 1.0, green: 1.0, blue: 1.0, alpha: 1.0),
        dark: NSColor(srgbRed: 0.082, green: 0.090, blue: 0.114, alpha: 1.0)       // #15171D
    )
    static let elevatedSurface = dynamic(
        light: NSColor(srgbRed: 1.0, green: 1.0, blue: 1.0, alpha: 1.0),
        dark: NSColor(srgbRed: 0.118, green: 0.129, blue: 0.161, alpha: 1.0)       // #1E2129
    )
    static let leftPaneBg = dynamic(
        light: NSColor(srgbRed: 0.984, green: 0.986, blue: 0.992, alpha: 1.0),    // #FAFAFC
        dark: NSColor(srgbRed: 0.102, green: 0.110, blue: 0.137, alpha: 1.0)      // #1A1C23
    )
    static let divider = dynamic(
        light: NSColor(srgbRed: 0.935, green: 0.940, blue: 0.952, alpha: 1.0),    // #EFF0F3
        dark: NSColor(srgbRed: 0.165, green: 0.180, blue: 0.220, alpha: 1.0)      // #2A2E38
    )

    static let textPrimary = dynamic(
        light: NSColor(srgbRed: 0.10, green: 0.11, blue: 0.14, alpha: 1.0),       // #1A1C24
        dark: NSColor(srgbRed: 0.945, green: 0.953, blue: 0.973, alpha: 1.0)      // #F1F3F8
    )
    static let textSecondary = dynamic(
        light: NSColor(srgbRed: 0.52, green: 0.56, blue: 0.62, alpha: 1.0),       // #858F9E
        dark: NSColor(srgbRed: 0.61, green: 0.65, blue: 0.72, alpha: 1.0)         // #9CA6B8
    )
    static let textMuted = dynamic(
        light: NSColor(srgbRed: 0.68, green: 0.71, blue: 0.76, alpha: 1.0),
        dark: NSColor(srgbRed: 0.45, green: 0.49, blue: 0.56, alpha: 1.0)
    )

    // Dynamic Accent-Derived Brand Tokens
    @MainActor
    static var brandPrimary: Color {
        accentColor(for: activeAccent)
    }

    @MainActor
    static var brandSoftFill: Color {
        let l = activeAccent.lightRGB
        let d = activeAccent.darkRGB
        return dynamic(
            light: NSColor(srgbRed: l.r, green: l.g, blue: l.b, alpha: 0.11),
            dark: NSColor(srgbRed: d.r, green: d.g, blue: d.b, alpha: 0.20)
        )
    }

    @MainActor
    static var mindMapNodeFill: Color {
        let l = activeAccent.lightRGB
        let d = activeAccent.darkRGB
        return dynamic(
            light: NSColor(srgbRed: l.r, green: l.g, blue: l.b, alpha: 0.08),
            dark: NSColor(srgbRed: d.r, green: d.g, blue: d.b, alpha: 0.15)
        )
    }

    @MainActor
    static var mindMapLine: Color {
        let l = activeAccent.lightRGB
        let d = activeAccent.darkRGB
        return dynamic(
            light: NSColor(srgbRed: l.r, green: l.g, blue: l.b, alpha: 0.22),
            dark: NSColor(srgbRed: d.r, green: d.g, blue: d.b, alpha: 0.32)
        )
    }

    static let neutralPill = dynamic(
        light: NSColor(srgbRed: 0.949, green: 0.953, blue: 0.961, alpha: 1.0),    // #F2F3F5
        dark: NSColor(srgbRed: 0.165, green: 0.180, blue: 0.220, alpha: 1.0)       // #2A2E38
    )
    static let softCardBg = dynamic(
        light: NSColor(srgbRed: 0.973, green: 0.976, blue: 0.982, alpha: 1.0),    // #F8F9FA
        dark: NSColor(srgbRed: 0.125, green: 0.137, blue: 0.173, alpha: 1.0)       // #20232C
    )
    static let skeletonBg = dynamic(
        light: NSColor(srgbRed: 0.925, green: 0.933, blue: 0.945, alpha: 1.0),    // #ECEEF1
        dark: NSColor(srgbRed: 0.155, green: 0.169, blue: 0.212, alpha: 1.0)
    )
    static let subtleBorder = dynamic(
        light: NSColor(srgbRed: 0.90, green: 0.91, blue: 0.93, alpha: 1.0),
        dark: NSColor(srgbRed: 0.20, green: 0.22, blue: 0.27, alpha: 1.0)
    )
    static let inputBackground = dynamic(
        light: NSColor(srgbRed: 1.0, green: 1.0, blue: 1.0, alpha: 1.0),            // #FFFFFF crisp editable field
        dark: NSColor(srgbRed: 0.075, green: 0.082, blue: 0.106, alpha: 1.0)      // #13151B recessed dark well
    )
    static let inputBorder = dynamic(
        light: NSColor(srgbRed: 0.82, green: 0.84, blue: 0.88, alpha: 1.0),       // #D1D6E0 clearer than card border
        dark: NSColor(srgbRed: 0.25, green: 0.27, blue: 0.34, alpha: 1.0)
    )
    static let inputHoverBorder = dynamic(
        light: NSColor(srgbRed: 0.70, green: 0.73, blue: 0.79, alpha: 1.0),
        dark: NSColor(srgbRed: 0.34, green: 0.37, blue: 0.46, alpha: 1.0)
    )
    static let inlineCodeBg = dynamic(
        light: NSColor(srgbRed: 0.94, green: 0.95, blue: 0.97, alpha: 1.0),
        dark: NSColor(srgbRed: 0.17, green: 0.19, blue: 0.24, alpha: 1.0)
    )
    static let waveformInactive = dynamic(
        light: NSColor(srgbRed: 0.72, green: 0.75, blue: 0.79, alpha: 1.0),
        dark: NSColor(srgbRed: 0.34, green: 0.37, blue: 0.44, alpha: 1.0)
    )

    static let recordingRed = dynamic(
        light: NSColor(srgbRed: 0.93, green: 0.26, blue: 0.28, alpha: 1.0),
        dark: NSColor(srgbRed: 0.98, green: 0.38, blue: 0.40, alpha: 1.0)
    )
    static let successGreen = dynamic(
        light: NSColor(srgbRed: 0.12, green: 0.68, blue: 0.43, alpha: 1.0),
        dark: NSColor(srgbRed: 0.22, green: 0.80, blue: 0.54, alpha: 1.0)
    )
    static let warningAmber = dynamic(
        light: NSColor(srgbRed: 0.90, green: 0.58, blue: 0.12, alpha: 1.0),
        dark: NSColor(srgbRed: 0.96, green: 0.69, blue: 0.24, alpha: 1.0)
    )
}

/// Horizontal row of fine rounded dots that gently animate with real-time audio amplitude.
struct DoubaoDottedWaveformView: View {
    let level: Float
    let isActive: Bool
    let isPaused: Bool

    @ObservedObject private var theme = ThemeManager.shared
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
                          ? AppTheme.accentColor(for: theme.accent).opacity(0.70)
                          : AppTheme.waveformInactive)
                    .frame(width: 2.5, height: activeHeight)
                    .animation(.easeOut(duration: 0.12), value: sample)
            }
        }
        .frame(height: 24)
        .onChange(of: level) { _, newVal in
            var next = history
            next.removeFirst()
            let jitter = newVal > 0.02 ? Float.random(in: 0.82...1.18) : 1.0
            next.append(min(1.0, newVal * jitter))
            history = next
        }
    }
}

/// Subtle airy light-ray wash in the top-right corner, automatically adapting to Light & Dark themes
/// and tinted subtly by the user's selected Accent Theme.
struct DoubaoSoftLightBackdrop: View {
    @Environment(\.colorScheme) private var colorScheme
    @ObservedObject private var theme = ThemeManager.shared

    var body: some View {
        let accent = AppTheme.accentColor(for: theme.accent)
        ZStack {
            AppTheme.canvasWhite
            LinearGradient(
                colors: colorScheme == .dark
                    ? [accent.opacity(0.10), Color.clear]
                    : [Color(red: 0.93, green: 0.94, blue: 0.96).opacity(0.55), Color.clear],
                startPoint: .topTrailing,
                endPoint: .center
            )
            RadialGradient(
                colors: colorScheme == .dark
                    ? [accent.opacity(0.14), Color.clear]
                    : [accent.opacity(0.10), Color.clear],
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
    @ObservedObject private var theme = ThemeManager.shared
    @State private var pulse = false

    var body: some View {
        let brand = AppTheme.accentColor(for: theme.accent)
        ZStack {
            if isActive && !isPaused {
                Circle()
                    .fill(brand.opacity(0.28))
                    .frame(width: 12, height: 12)
                    .scaleEffect(pulse ? 1.4 : 0.85)
                    .opacity(pulse ? 0.15 : 0.8)
                    .animation(.easeInOut(duration: 1.0).repeatForever(autoreverses: true), value: pulse)
            }
            Circle()
                .fill(isPaused ? AppTheme.warningAmber : (isActive ? brand : AppTheme.textMuted))
                .frame(width: 7, height: 7)
        }
        .onAppear { pulse = true }
    }
}
