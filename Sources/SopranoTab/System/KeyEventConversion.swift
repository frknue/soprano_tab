import AppKit
import Carbon
import SopranoTabCore

/// Pure conversion used by HotkeyMonitor (and its tests).
enum KeyEventConversion {
    /// The `KeyEvent` for a keyDown, keyUp or flagsChanged event; nil for any other type.
    /// Call on the main thread: `NSEvent(cgEvent:)` reads the keyboard layout there.
    /// `characters` is `NSEvent.charactersIgnoringModifiers` for key events (Shift still
    /// applies) and nil for flagsChanged. Key codes are positional ANSI codes (see
    /// `positionalKeyCode(_:keyboardType:)`).
    static func keyEvent(from event: CGEvent, type: CGEventType) -> KeyEvent? {
        let kind: KeyEvent.Kind
        switch type {
        case .keyDown: kind = .keyDown
        case .keyUp: kind = .keyUp
        case .flagsChanged: kind = .flagsChanged
        default: return nil
        }
        let characters = kind == .flagsChanged ? nil : NSEvent(cgEvent: event)?.charactersIgnoringModifiers
        return KeyEvent(
            kind: kind,
            keyCode: positionalKeyCode(
                UInt16(truncatingIfNeeded: event.getIntegerValueField(.keyboardEventKeycode)),
                keyboardType: event.getIntegerValueField(.keyboardEventKeyboardType)
            ),
            modifiers: modifiers(from: event.flags),
            characters: characters,
            isRepeat: event.getIntegerValueField(.keyboardEventAutorepeat) != 0
        )
    }

    /// On ISO keyboards macOS reports the key above Tab as `kVK_ISO_Section` (0x0A) and the
    /// extra key right of the left Shift as `kVK_ANSI_Grave` (0x32). `NamedKey.keyAboveTab`
    /// is the positional ANSI code 0x32, so ISO keyboards swap the two; every other code
    /// and every other keyboard type is unchanged.
    static func positionalKeyCode(_ keyCode: UInt16, keyboardType: Int64) -> UInt16 {
        guard KBGetLayoutType(Int16(truncatingIfNeeded: keyboardType)) == PhysicalKeyboardLayoutType(kKeyboardISO) else {
            return keyCode
        }
        switch keyCode {
        case UInt16(kVK_ISO_Section): return UInt16(kVK_ANSI_Grave)
        case UInt16(kVK_ANSI_Grave): return UInt16(kVK_ISO_Section)
        default: return keyCode
        }
    }

    /// The modifier keys in `flags`. Arrow and F keys carry `maskSecondaryFn`, so they map
    /// to `.function` too; the key router ignores it unless a hold set asks for it.
    static func modifiers(from flags: CGEventFlags) -> ModifierSet {
        var modifiers: ModifierSet = []
        if flags.contains(.maskCommand) { modifiers.insert(.command) }
        if flags.contains(.maskAlternate) { modifiers.insert(.option) }
        if flags.contains(.maskControl) { modifiers.insert(.control) }
        if flags.contains(.maskShift) { modifiers.insert(.shift) }
        if flags.contains(.maskSecondaryFn) { modifiers.insert(.function) }
        return modifiers
    }
}
