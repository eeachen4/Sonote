import SwiftUI
import AppKit
import SonoteCore

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let promptController = FloatingPromptPanelController()
    private let capsuleController = LiveCapsulePanelController()
    private let subtitleController = LiveSubtitlePanelController()

    func applicationDidFinishLaunching(_ notification: Notification) {
        let appState = AppState.shared
        ThemeManager.shared.sync(with: appState.settings)
        ThemeManager.shared.applyNSAppAppearance()

        appState.onShowMeetingPrompt = { [weak self] detected in
            self?.promptController.showMeetingDetected(detected, appState: appState)
        }
        appState.onShowMeetingEndPrompt = { [weak self] ended in
            self?.promptController.showMeetingEnded(ended, appState: appState)
        }
        appState.onHidePromptPanel = { [weak self] in
            self?.promptController.hide()
        }
        appState.onUpdateCapsuleVisibility = { [weak self] visible in
            self?.capsuleController.setVisible(visible, appState: appState)
        }
        appState.onUpdateSubtitleVisibility = { [weak self] visible in
            self?.subtitleController.setVisible(visible, appState: appState)
        }
        appState.onOpenMainWindow = { [weak self] in
            self?.bringMainWindowToFront()
        }
        appState.onHideMainWindow = { [weak self] in
            if let mainWin = self?.findMainWindow() {
                mainWin.orderOut(nil)
            }
        }
        appState.onToggleMainWindow = { [weak self] in
            guard let self else { return }
            if let mainWin = self.findMainWindow(), mainWin.isVisible && !mainWin.isMiniaturized && NSApp.isActive {
                mainWin.orderOut(nil)
            } else {
                self.bringMainWindowToFront()
            }
        }

        // System-wide global hotkeys (works even when Tencent Meeting / Feishu is fullscreen)
        let hotKeys = GlobalHotKeyService.shared
        hotKeys.onToggleRecording = {
            Task { @MainActor in
                if appState.isRecordingOrPaused {
                    await appState.stopRecordingAndFinalize(generateFinalSummary: true)
                } else {
                    await appState.startNewMeeting()
                }
            }
        }
        hotKeys.onToggleWindow = {
            Task { @MainActor in
                if appState.isCapsuleVisible {
                    appState.expandFromMiniWindowToMain()
                } else {
                    appState.onToggleMainWindow?()
                }
            }
        }
        hotKeys.configure(
            enabled: appState.settings.enableGlobalHotKeys,
            preset: appState.settings.globalHotKeyPreset
        )
    }

    func applicationWillTerminate(_ notification: Notification) {
        AppState.shared.flushPendingPersistence()
        GlobalHotKeyService.shared.unregisterAll()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        // Respect General Settings: keep running quietly in menu bar by default so auto-detection stays active
        !AppState.shared.settings.keepRunningInMenuBarOnClose
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag {
            bringMainWindowToFront()
        }
        return true
    }

    private func findMainWindow() -> NSWindow? {
        if let tracked = AppState.shared.trackedMainWindow {
            return tracked
        }
        if let identified = NSApp.windows.first(where: { $0.identifier?.rawValue == "sonote-main-window" }) {
            AppState.shared.registerMainWindow(identified)
            return identified
        }
        // Fallback heuristic that strictly excludes FloatingHUDPanel, Settings, and MenuBarExtra windows
        return NSApp.windows.first { win in
            guard !(win is FloatingHUDPanel), win.canBecomeMain else { return false }
            let cls = NSStringFromClass(type(of: win))
            if cls.contains("Settings") || cls.contains("MenuBar") || cls.contains("StatusBar") {
                return false
            }
            return win.title == "Sonote"
        }
    }

    private func bringMainWindowToFront() {
        NSApp.activate(ignoringOtherApps: true)
        if let mainWin = findMainWindow() {
            if mainWin.isMiniaturized {
                mainWin.deminiaturize(nil)
            }
            // When expanding from the floating capsule into live 2-column view, ensure comfortable workspace width
            if AppState.shared.isRecordingOrPaused && mainWin.frame.width < 920 {
                let screen = mainWin.screen?.visibleFrame ?? NSScreen.main?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
                let targetW = min(1040, max(920, screen.width - 120))
                let targetH = min(680, max(580, screen.height - 120))
                let frame = NSRect(
                    x: screen.midX - targetW / 2,
                    y: screen.midY - targetH / 2,
                    width: targetW,
                    height: targetH
                )
                mainWin.setFrame(frame, display: true, animate: true)
            }
            mainWin.makeKeyAndOrderFront(nil)
            mainWin.orderFrontRegardless()
            if !mainWin.isVisible, let openSwiftUI = AppState.shared.swiftUIOpenMainWindow {
                openSwiftUI()
            }
        } else if let openSwiftUI = AppState.shared.swiftUIOpenMainWindow {
            openSwiftUI()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) { [weak self] in
                NSApp.activate(ignoringOtherApps: true)
                if let win = self?.findMainWindow() {
                    win.makeKeyAndOrderFront(nil)
                    win.orderFrontRegardless()
                }
            }
        }
    }
}

@main
struct SonoteApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var appState = AppState.shared
    @ObservedObject private var theme = ThemeManager.shared

    var body: some Scene {
        Window("Sonote", id: "main") {
            MainWindowView(appState: appState)
                .tint(AppTheme.brandPrimary)
                .preferredColorScheme(theme.preferredColorScheme)
        }
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: 860, height: 560)
        .commands {
            CommandGroup(after: .newItem) {
                Button(appState.isRecordingOrPaused ? L("结束并生成纪要", "Stop & Summarize") : L("开始新录音", "Start Recording")) {
                    Task {
                        if appState.isRecordingOrPaused {
                            await appState.stopRecordingAndFinalize(generateFinalSummary: true)
                        } else {
                            await appState.startNewMeeting()
                        }
                    }
                }
                .keyboardShortcut("r", modifiers: [.command, .shift])

                Button(L("模拟加入会议提醒", "Simulate Meeting Prompt")) {
                    appState.triggerSimulatedMeetingPrompt()
                }
                .keyboardShortcut("m", modifiers: [.command, .shift])
            }
        }

        MenuBarExtra {
            MenuBarView(appState: appState)
                .tint(AppTheme.brandPrimary)
                .preferredColorScheme(theme.preferredColorScheme)
        } label: {
            HStack(spacing: 4) {
                Image(systemName: appState.isRecording ? "waveform.circle.fill" : "waveform")
                if let timer = appState.menuBarTimerLabel {
                    Text(timer)
                        .monospacedDigit()
                }
            }
        }
        .menuBarExtraStyle(.window)

        Settings {
            SettingsView(appState: appState)
                .tint(AppTheme.brandPrimary)
                .preferredColorScheme(theme.preferredColorScheme)
        }
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.contentSize)
    }
}
