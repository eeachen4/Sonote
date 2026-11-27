import Foundation
import Carbon.HIToolbox

/// System-wide global hotkey service backed by Carbon `RegisterEventHotKey`.
/// Works even when meeting apps (Tencent Meeting / Feishu / Zoom) are fullscreen,
/// and requires NO Accessibility permissions.
@MainActor
public final class GlobalHotKeyService {
    public static let shared = GlobalHotKeyService()

    public enum Action: UInt32 {
        case toggleRecording = 1
        case toggleWindow = 2
    }

    public var onToggleRecording: (() -> Void)?
    public var onToggleWindow: (() -> Void)?

    private var eventHandlerRef: EventHandlerRef?
    private var hotKeyRefs: [EventHotKeyRef?] = []
    private let signature: OSType = 0x54544D4E // 'TTMN'

    private init() {
        installEventHandlerIfNeeded()
    }

    public func configure(enabled: Bool, preset: GlobalHotKeyModifierPreset) {
        unregisterAll()
        guard enabled else { return }
        installEventHandlerIfNeeded()

        let modifiers = preset.carbonModifiers
        registerHotKey(keyCode: UInt32(kVK_ANSI_R), modifiers: modifiers, id: Action.toggleRecording.rawValue)
        registerHotKey(keyCode: UInt32(kVK_ANSI_M), modifiers: modifiers, id: Action.toggleWindow.rawValue)
    }

    public func unregisterAll() {
        for ref in hotKeyRefs {
            if let ref {
                UnregisterEventHotKey(ref)
            }
        }
        hotKeyRefs.removeAll()
    }

    private func registerHotKey(keyCode: UInt32, modifiers: UInt32, id: UInt32) {
        var hotKeyRef: EventHotKeyRef?
        let hotKeyID = EventHotKeyID(signature: signature, id: id)
        let status = RegisterEventHotKey(
            keyCode,
            modifiers,
            hotKeyID,
            GetApplicationEventTarget(),
            0,
            &hotKeyRef
        )
        if status == noErr, let ref = hotKeyRef {
            hotKeyRefs.append(ref)
        }
    }

    private func installEventHandlerIfNeeded() {
        guard eventHandlerRef == nil else { return }
        var eventSpec = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )
        let selfPtr = Unmanaged.passUnretained(self).toOpaque()
        var handler: EventHandlerRef?
        let status = InstallEventHandler(
            GetApplicationEventTarget(),
            { _, event, userData -> OSStatus in
                guard let event, let userData else { return noErr }
                var hotKeyID = EventHotKeyID()
                let err = GetEventParameter(
                    event,
                    EventParamName(kEventParamDirectObject),
                    EventParamType(typeEventHotKeyID),
                    nil,
                    MemoryLayout<EventHotKeyID>.size,
                    nil,
                    &hotKeyID
                )
                guard err == noErr else { return err }
                let service = Unmanaged<GlobalHotKeyService>.fromOpaque(userData).takeUnretainedValue()
                let actionID = hotKeyID.id
                Task { @MainActor in
                    service.handleHotKey(id: actionID)
                }
                return noErr
            },
            1,
            &eventSpec,
            selfPtr,
            &handler
        )
        if status == noErr {
            eventHandlerRef = handler
        }
    }

    private func handleHotKey(id: UInt32) {
        switch Action(rawValue: id) {
        case .toggleRecording:
            onToggleRecording?()
        case .toggleWindow:
            onToggleWindow?()
        case nil:
            break
        }
    }
}

public extension GlobalHotKeyModifierPreset {
    var carbonModifiers: UInt32 {
        switch self {
        case .optionShift:
            return UInt32(optionKey | shiftKey)
        case .controlOption:
            return UInt32(controlKey | optionKey)
        case .controlShift:
            return UInt32(controlKey | shiftKey)
        }
    }
}
