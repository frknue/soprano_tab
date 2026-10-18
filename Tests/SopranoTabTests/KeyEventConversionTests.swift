import AppKit
import Carbon
import Testing
@testable import SopranoTab
@testable import SopranoTabCore

/// Main actor: `NSEvent(cgEvent:)` reads the keyboard layout, which aborts off the main
/// thread. Production converts inside the tap callback on the main run loop.
@MainActor
struct KeyEventConversionTests {
    private let tabKeyCode: CGKeyCode = 0x30
    private let shiftKeyCode: CGKeyCode = 0x38

    private func keyboardEvent(
        keyCode: CGKeyCode,
        keyDown: Bool = true,
        flags: CGEventFlags = [],
        autorepeat: Bool = false
    ) throws -> CGEvent {
        let event = try #require(CGEvent(keyboardEventSource: nil, virtualKey: keyCode, keyDown: keyDown))
        event.flags = flags
        event.setIntegerValueField(.keyboardEventAutorepeat, value: autorepeat ? 1 : 0)
        return event
    }

    /// The first hardware keyboard type in 0...255 with `layout`.
    private func keyboardType(withLayout layout: PhysicalKeyboardLayoutType) throws -> Int64 {
        try #require((0...255).first { KBGetLayoutType(Int16($0)) == layout }.map { Int64($0) })
    }

    @Test("a key down becomes a keyDown event with its key code and characters")
    func keyDown() throws {
        let event = try keyboardEvent(keyCode: tabKeyCode, flags: .maskAlternate)
        let converted = try #require(KeyEventConversion.keyEvent(from: event, type: .keyDown))
        #expect(converted.kind == .keyDown)
        #expect(converted.keyCode == 0x30)
        #expect(converted.modifiers == [.option])
        #expect(converted.characters == "\t")
        #expect(converted.isRepeat == false)
    }

    @Test("a key up becomes a keyUp event")
    func keyUp() throws {
        let event = try keyboardEvent(keyCode: tabKeyCode, keyDown: false)
        let converted = try #require(KeyEventConversion.keyEvent(from: event, type: .keyUp))
        #expect(converted.kind == .keyUp)
        #expect(converted.keyCode == 0x30)
        #expect(converted.modifiers.isEmpty)
    }

    @Test("an autorepeated key down is marked as a repeat")
    func autorepeat() throws {
        let event = try keyboardEvent(keyCode: tabKeyCode, autorepeat: true)
        let converted = try #require(KeyEventConversion.keyEvent(from: event, type: .keyDown))
        #expect(converted.isRepeat)
    }

    @Test("a flags change carries the new modifiers and no characters")
    func flagsChanged() throws {
        let event = try keyboardEvent(keyCode: shiftKeyCode, flags: [.maskShift, .maskCommand])
        event.type = .flagsChanged
        let converted = try #require(KeyEventConversion.keyEvent(from: event, type: .flagsChanged))
        #expect(converted.kind == .flagsChanged)
        #expect(converted.keyCode == 0x38)
        #expect(converted.modifiers == [.shift, .command])
        #expect(converted.characters == nil)
    }

    @Test("events other than key and flag changes are not converted")
    func otherTypes() throws {
        let event = try keyboardEvent(keyCode: tabKeyCode)
        #expect(KeyEventConversion.keyEvent(from: event, type: .mouseMoved) == nil)
        #expect(KeyEventConversion.keyEvent(from: event, type: .tapDisabledByTimeout) == nil)
    }

    @Test("every modifier flag maps to its modifier, fn included")
    func modifierFlags() {
        #expect(KeyEventConversion.modifiers(from: .maskCommand) == [.command])
        #expect(KeyEventConversion.modifiers(from: .maskAlternate) == [.option])
        #expect(KeyEventConversion.modifiers(from: .maskControl) == [.control])
        #expect(KeyEventConversion.modifiers(from: .maskShift) == [.shift])
        #expect(KeyEventConversion.modifiers(from: .maskSecondaryFn) == [.function])
        #expect(
            KeyEventConversion.modifiers(from: [.maskCommand, .maskAlternate, .maskControl, .maskShift, .maskSecondaryFn])
                == [.command, .option, .control, .shift, .function]
        )
    }

    @Test("flags that are not modifier keys are ignored")
    func nonModifierFlags() {
        #expect(KeyEventConversion.modifiers(from: []).isEmpty)
        #expect(KeyEventConversion.modifiers(from: [.maskAlphaShift, .maskNumericPad, .maskHelp]).isEmpty)
        #expect(KeyEventConversion.modifiers(from: [.maskNumericPad, .maskSecondaryFn]) == [.function])
    }

    @Test("ISO keyboards swap the section key and the grave key to their positional codes")
    func isoPositionalKeyCodes() throws {
        let iso = try keyboardType(withLayout: PhysicalKeyboardLayoutType(kKeyboardISO))
        #expect(KeyEventConversion.positionalKeyCode(0x0A, keyboardType: iso) == 0x32)
        #expect(KeyEventConversion.positionalKeyCode(0x32, keyboardType: iso) == 0x0A)
        #expect(KeyEventConversion.positionalKeyCode(0x30, keyboardType: iso) == 0x30)
        #expect(KeyEventConversion.positionalKeyCode(0x00, keyboardType: iso) == 0x00)
    }

    @Test("ANSI keyboards keep every key code")
    func ansiPositionalKeyCodes() throws {
        let ansi = try keyboardType(withLayout: PhysicalKeyboardLayoutType(kKeyboardANSI))
        #expect(KeyEventConversion.positionalKeyCode(0x0A, keyboardType: ansi) == 0x0A)
        #expect(KeyEventConversion.positionalKeyCode(0x32, keyboardType: ansi) == 0x32)
        #expect(KeyEventConversion.positionalKeyCode(0x30, keyboardType: ansi) == 0x30)
    }

    @Test("a key down from an ISO keyboard reports the key above Tab as its positional code")
    func isoKeyDown() throws {
        let iso = try keyboardType(withLayout: PhysicalKeyboardLayoutType(kKeyboardISO))
        let event = try keyboardEvent(keyCode: 0x0A, flags: .maskCommand)
        event.setIntegerValueField(.keyboardEventKeyboardType, value: iso)
        let converted = try #require(KeyEventConversion.keyEvent(from: event, type: .keyDown))
        #expect(converted.keyCode == 0x32)
        #expect(converted.keyCode == NamedKey.keyAboveTab.keyCodes.first)
        #expect(converted.modifiers == [.command])
    }
}
