import SwiftUI
import AppKit
import SonoteCore

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let promptController = FloatingPromptPanelController()
    private let capsuleController = LiveCapsulePanelController()

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
        appState.onOpenMainWindow = {
            NSApp.activate(ignoringOtherApps: true)
            for window in NSApp.windows where !(window is FloatingHUDPanel) {
                if window.canBecomeMain {
                    window.makeKeyAndOrderFront(nil)
                    break
                }
            }
        }
        appState.onHideMainWindow = {
            for window in NSApp.windows where !(window is FloatingHUDPanel) {
                if window.canBecomeMain {
                    window.orderOut(nil)
                }
            }
        }
        appState.onToggleMainWindow = {
            let mainWin = NSApp.windows.first(where: { !($0 is FloatingHUDPanel) && $0.canBecomeMain })
            if let mainWin, mainWin.isVisible && NSApp.isActive {
                mainWin.orderOut(nil)
            } else {
                appState.onOpenMainWindow?()
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
        GlobalHotKeyService.shared.unregisterAll()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        // Respect General Settings: keep running quietly in menu bar by default so auto-detection stays active
        !AppState.shared.settings.keepRunningInMenuBarOnClose
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag {
            AppState.shared.onOpenMainWindow?()
        }
        return true
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
