import AppKit
import Testing
@testable import SopranoTabCore

struct KeyParsingTests {
    @Test("modifier aliases, symbols and spacing parse to one canonical spelling")
    func modifierAliases() {
        #expect(ModifierSet(settingsText: "alt") == .option)
        #expect(ModifierSet(settingsText: "⌥") == .option)
        #expect(ModifierSet(settingsText: " Cmd + SHIFT ") == [.command, .shift])
        #expect(ModifierSet(settingsText: "function+ctrl") == [.function, .control])

        let all: ModifierSet = [.command, .option, .control, .shift, .function]
        #expect(all.settingsText == "control+option+shift+command+fn")
        #expect(all.symbols == "⌃⌥⇧⌘fn")
        #expect(ModifierSet(settingsText: all.settingsText) == all)
    }

    @Test("empty, unknown or dangling modifier parts are rejected")
    func modifierRejections() {
        #expect(ModifierSet(settingsText: "") == nil)
        #expect(ModifierSet(settingsText: "  ") == nil)
        #expect(ModifierSet(settingsText: "hyper") == nil)
        #expect(ModifierSet(settingsText: "option+") == nil)
        #expect(ModifierSet(settingsText: "option+meta") == nil)
    }

    @Test("every named key round-trips through its settings spelling")
    func namedKeyRoundTrip() {
        for key in NamedKey.allCases {
            let spec = KeySpec.named(key)
            #expect(KeySpec(settingsText: spec.settingsText) == spec)
            #expect(KeySpec(settingsText: spec.settingsText.uppercased()) == spec)
        }
        #expect(KeySpec(settingsText: "w")?.settingsText == "w")
    }

    @Test("key aliases map to their named keys")
    func keyAliases() {
        #expect(KeySpec(settingsText: "enter") == .named(.return))
        #expect(KeySpec(settingsText: "Esc") == .named(.escape))
        #expect(KeySpec(settingsText: "backspace") == .named(.delete))
        #expect(KeySpec(settingsText: "`") == .named(.keyAboveTab))
        #expect(KeySpec(settingsText: "grave") == .named(.keyAboveTab))
        #expect(KeySpec(settingsText: "backtick") == .named(.keyAboveTab))
        #expect(KeySpec(settingsText: "section") == .named(.keyAboveTab))
        #expect(KeySpec(settingsText: "spacebar") == .named(.space))
    }

    @Test("single characters are lowercased; empty and multi-character text is rejected")
    func characterKeys() {
        #expect(KeySpec(settingsText: "W") == .character("w"))
        #expect(KeySpec(settingsText: "ü") == .character("ü"))
        #expect(KeySpec(settingsText: "") == nil)
        #expect(KeySpec(settingsText: " ") == nil)
        #expect(KeySpec(settingsText: "ww") == nil)
        #expect(KeySpec(settingsText: "ctrl") == nil)
    }

    @Test("symbols show glyphs for named keys and uppercase characters")
    func symbols() {
        #expect(KeySpec.named(.tab).symbol == "⇥")
        #expect(KeySpec.named(.return).symbol == "↩")
        #expect(KeySpec.named(.keyAboveTab).symbol == "`")
        #expect(KeySpec.named(.f12).symbol == "F12")
        #expect(KeySpec.character("w").symbol == "W")
    }

    @Test("named keys match by key code, including keypad Enter for return")
    func namedMatching() {
        let returnKey = KeySpec.named(.return)
        #expect(returnKey.matches(KeyEvent(kind: .keyDown, keyCode: 0x24, modifiers: [])))
        #expect(returnKey.matches(KeyEvent(kind: .keyDown, keyCode: 0x4C, modifiers: [.function])))
        #expect(!returnKey.matches(KeyEvent(kind: .keyDown, keyCode: 0x30, modifiers: [], characters: "\r")))
    }

    @Test("characters match the typed character case-insensitively and never without characters")
    func characterMatching() {
        let close = KeySpec.character("w")
        #expect(close.matches(KeyEvent(kind: .keyDown, keyCode: 0x0D, modifiers: [], characters: "w")))
        #expect(close.matches(KeyEvent(kind: .keyDown, keyCode: 0x0D, modifiers: [.shift], characters: "W")))
        #expect(close.matches(KeyEvent(kind: .keyDown, keyCode: 0x06, modifiers: [], characters: "w")))
        #expect(!close.matches(KeyEvent(kind: .keyDown, keyCode: 0x0D, modifiers: [], characters: "z")))
        #expect(!close.matches(KeyEvent(kind: .flagsChanged, keyCode: 0x0D, modifiers: [], characters: nil)))
    }
}
