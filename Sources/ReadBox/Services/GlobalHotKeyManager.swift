import Foundation
import AppKit
import Carbon.HIToolbox

/// Utilities for formatting and converting macOS global hotkey combinations (Carbon HIToolbox <-> AppKit).
public enum GlobalHotKeyFormatter {
    public static func carbonModifiers(from flags: NSEvent.ModifierFlags) -> UInt32 {
        var mask: UInt32 = 0
        let clean = flags.intersection(.deviceIndependentFlagsMask)
        if clean.contains(.command) { mask |= UInt32(cmdKey) }
        if clean.contains(.option)  { mask |= UInt32(optionKey) }
        if clean.contains(.control) { mask |= UInt32(controlKey) }
        if clean.contains(.shift)   { mask |= UInt32(shiftKey) }
        return mask
    }

    public static func isValidHotKey(keyCode: UInt32, carbonModifiers: UInt32) -> Bool {
        // Must include at least Command, Option, or Control (Shift alone breaks normal typing)
        let allowedPrimary = UInt32(cmdKey | optionKey | controlKey)
        guard (carbonModifiers & allowedPrimary) != 0 else { return false }
        // Disallow bare modifier keyCodes & Escape
        let disallowed: Set<UInt32> = [
            UInt32(kVK_Escape),
            UInt32(kVK_Command), UInt32(kVK_RightCommand),
            UInt32(kVK_Shift), UInt32(kVK_RightShift),
            UInt32(kVK_Option), UInt32(kVK_RightOption),
            UInt32(kVK_Control), UInt32(kVK_RightControl),
            UInt32(kVK_CapsLock), UInt32(kVK_Function)
        ]
        return !disallowed.contains(keyCode)
    }

    public static func displayString(keyCode: UInt32, carbonModifiers: UInt32) -> String {
        var result = ""
        if (carbonModifiers & UInt32(controlKey)) != 0 { result += "⌃" }
        if (carbonModifiers & UInt32(optionKey))  != 0 { result += "⌥" }
        if (carbonModifiers & UInt32(shiftKey))   != 0 { result += "⇧" }
        if (carbonModifiers & UInt32(cmdKey))     != 0 { result += "⌘" }
        result += keyLabel(for: keyCode)
        return result
    }

    public static func keyLabel(for keyCode: UInt32) -> String {
        switch Int(keyCode) {
        case kVK_ANSI_A: return "A"
        case kVK_ANSI_B: return "B"
        case kVK_ANSI_C: return "C"
        case kVK_ANSI_D: return "D"
        case kVK_ANSI_E: return "E"
        case kVK_ANSI_F: return "F"
        case kVK_ANSI_G: return "G"
        case kVK_ANSI_H: return "H"
        case kVK_ANSI_I: return "I"
        case kVK_ANSI_J: return "J"
        case kVK_ANSI_K: return "K"
        case kVK_ANSI_L: return "L"
        case kVK_ANSI_M: return "M"
        case kVK_ANSI_N: return "N"
        case kVK_ANSI_O: return "O"
        case kVK_ANSI_P: return "P"
        case kVK_ANSI_Q: return "Q"
        case kVK_ANSI_R: return "R"
        case kVK_ANSI_S: return "S"
        case kVK_ANSI_T: return "T"
        case kVK_ANSI_U: return "U"
        case kVK_ANSI_V: return "V"
        case kVK_ANSI_W: return "W"
        case kVK_ANSI_X: return "X"
        case kVK_ANSI_Y: return "Y"
        case kVK_ANSI_Z: return "Z"
        case kVK_ANSI_0: return "0"
        case kVK_ANSI_1: return "1"
        case kVK_ANSI_2: return "2"
        case kVK_ANSI_3: return "3"
        case kVK_ANSI_4: return "4"
        case kVK_ANSI_5: return "5"
        case kVK_ANSI_6: return "6"
        case kVK_ANSI_7: return "7"
        case kVK_ANSI_8: return "8"
        case kVK_ANSI_9: return "9"
        case kVK_Space: return "Space"
        case kVK_Return: return "↩"
        case kVK_Tab: return "⇥"
        case kVK_Delete: return "⌫"
        case kVK_ANSI_Minus: return "-"
        case kVK_ANSI_Equal: return "="
        case kVK_ANSI_LeftBracket: return "["
        case kVK_ANSI_RightBracket: return "]"
        case kVK_ANSI_Semicolon: return ";"
        case kVK_ANSI_Quote: return "'"
        case kVK_ANSI_Comma: return ","
        case kVK_ANSI_Period: return "."
        case kVK_ANSI_Slash: return "/"
        case kVK_ANSI_Backslash: return "\\"
        case kVK_ANSI_Grave: return "`"
        case kVK_F1: return "F1"
        case kVK_F2: return "F2"
        case kVK_F3: return "F3"
        case kVK_F4: return "F4"
        case kVK_F5: return "F5"
        case kVK_F6: return "F6"
        case kVK_F7: return "F7"
        case kVK_F8: return "F8"
        case kVK_F9: return "F9"
        case kVK_F10: return "F10"
        case kVK_F11: return "F11"
        case kVK_F12: return "F12"
        default: return "Key(\(keyCode))"
        }
    }
}

/// Zero-dependency system-wide macOS global hotkey listener powered by Carbon `RegisterEventHotKey`.
/// Works across all applications (Safari, Chrome, WeChat, etc.) without requiring Accessibility permission.
@MainActor
public final class GlobalHotKeyManager {
    private var hotKeyRef: EventHotKeyRef?
    private var eventHandlerRef: EventHandlerRef?
    private var onTrigger: (() -> Void)?

    private let signature: OSType = 0x52424F58 // 'RBOX'
    private let hotKeyIdValue: UInt32 = 1

    public init() {}

    deinit {
        if let hotKeyRef {
            UnregisterEventHotKey(hotKeyRef)
        }
        if let eventHandlerRef {
            RemoveEventHandler(eventHandlerRef)
        }
    }

    @discardableResult
    public func register(keyCode: UInt32, modifiers: UInt32, handler: @escaping () -> Void) -> Bool {
        unregister()
        guard GlobalHotKeyFormatter.isValidHotKey(keyCode: keyCode, carbonModifiers: modifiers) else {
            return false
        }

        self.onTrigger = handler
        installHandlerIfNeeded()

        let hotKeyID = EventHotKeyID(signature: signature, id: hotKeyIdValue)
        var ref: EventHotKeyRef?
        let status = RegisterEventHotKey(
            keyCode,
            modifiers,
            hotKeyID,
            GetApplicationEventTarget(),
            0,
            &ref
        )
        if status == noErr, let ref {
            self.hotKeyRef = ref
            return true
        }
        return false
    }

    public func unregister() {
        if let ref = hotKeyRef {
            UnregisterEventHotKey(ref)
            hotKeyRef = nil
        }
    }

    private func installHandlerIfNeeded() {
        guard eventHandlerRef == nil else { return }

        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )

        let selfPtr = Unmanaged.passUnretained(self).toOpaque()
        let callback: EventHandlerUPP = { _, eventRef, userData in
            guard let userData, let eventRef else { return OSStatus(eventNotHandledErr) }
            var hkID = EventHotKeyID()
            let err = GetEventParameter(
                eventRef,
                EventParamName(kEventParamDirectObject),
                EventParamType(typeEventHotKeyID),
                nil,
                MemoryLayout<EventHotKeyID>.size,
                nil,
                &hkID
            )
            guard err == noErr else { return err }
            let manager = Unmanaged<GlobalHotKeyManager>.fromOpaque(userData).takeUnretainedValue()
            if hkID.signature == manager.signature && hkID.id == manager.hotKeyIdValue {
                DispatchQueue.main.async {
                    manager.onTrigger?()
                }
                return noErr
            }
            return OSStatus(eventNotHandledErr)
        }

        InstallEventHandler(
            GetApplicationEventTarget(),
            callback,
            1,
            &eventType,
            selfPtr,
            &eventHandlerRef
        )
    }
}
