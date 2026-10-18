import AppKit
import Testing
@testable import SopranoTabCore

struct SwitcherKeyRouterTests {
    @Test("Option-Tab activates the first shortcut forwards and holds")
    func optionTabActivatesFirstShortcut() {
        var router = makeRouter()
        let decision = router.handle(down(.tab, [.option]), triggersEnabled: true)
        #expect(decision == KeyDecision(action: .activate(shortcut: 0, reverse: false), consume: true))
        #expect(router.state == .active(shortcut: 0, holding: true, searching: false))
    }

    @Test("Option-Shift-Tab activates in reverse")
    func optionShiftTabActivatesReversed() {
        var router = makeRouter()
        let decision = router.handle(down(.tab, [.option, .shift]), triggersEnabled: true)
        #expect(decision == KeyDecision(action: .activate(shortcut: 0, reverse: true), consume: true))
    }

    @Test("Option and the key above Tab activates the second shortcut")
    func optionGraveActivatesSecondShortcut() {
        var router = makeRouter()
        let decision = router.handle(down(.keyAboveTab, [.option]), triggersEnabled: true)
        #expect(decision.action == .activate(shortcut: 1, reverse: false))
        #expect(router.state == .active(shortcut: 1, holding: true, searching: false))
    }

    @Test("Only the first matching shortcut activates")
    func firstMatchingShortcutWins() {
        let shortcuts = [
            ShortcutSettings(hold: .option, key: .named(.tab)),
            ShortcutSettings(hold: .option, key: .named(.tab)),
        ]
        var router = SwitcherKeyRouter(shortcuts: shortcuts, controls: ControlSettings())
        #expect(router.handle(down(.tab, [.option]), triggersEnabled: true).action == .activate(shortcut: 0, reverse: false))
    }

    @Test("Extra modifiers other than previous pass through, the function flag does not count")
    func extraModifiersPassThrough() {
        var router = makeRouter()
        #expect(router.handle(down(.tab, [.command]), triggersEnabled: true) == .passThrough)
        #expect(router.handle(down(.tab, [.option, .command]), triggersEnabled: true) == .passThrough)
        #expect(router.handle(down(.tab, [.option, .control]), triggersEnabled: true) == .passThrough)
        #expect(router.state == .idle)
        #expect(router.handle(down(.tab, [.option, .function]), triggersEnabled: true).action == .activate(shortcut: 0, reverse: false))
    }

    @Test("A hold that includes fn requires it")
    func functionInHoldIsCompared() {
        var router = SwitcherKeyRouter(
            shortcuts: [ShortcutSettings(hold: [.option, .function], key: .named(.tab))],
            controls: ControlSettings()
        )
        #expect(router.handle(down(.tab, [.option]), triggersEnabled: true) == .passThrough)
        #expect(router.handle(down(.tab, [.option, .function]), triggersEnabled: true).action == .activate(shortcut: 0, reverse: false))
    }

    @Test("Disabled triggers and key repeats never activate")
    func disabledTriggersAndRepeatsPassThrough() {
        var router = makeRouter()
        #expect(router.handle(down(.tab, [.option]), triggersEnabled: false) == .passThrough)
        #expect(router.handle(down(.tab, [.option], repeat: true), triggersEnabled: true) == .passThrough)
        #expect(router.state == .idle)
    }

    @Test("Tab while active advances, repeats included, shift reverses")
    func tabWhileActiveAdvances() {
        var router = activeRouter()
        #expect(router.handle(down(.tab, [.option]), triggersEnabled: true) == KeyDecision(action: .advance(reverse: false), consume: true))
        #expect(router.handle(down(.tab, [.option], repeat: true), triggersEnabled: true).action == .advance(reverse: false))
        #expect(router.handle(down(.tab, [.option, .shift]), triggersEnabled: true).action == .advance(reverse: true))
        // Triggers disabled only stop activation, not an open switcher.
        #expect(router.handle(down(.tab, [.option]), triggersEnabled: false).action == .advance(reverse: false))
    }

    @Test("Pressing shift alone steps back once per press")
    func shiftAloneStepsBackOncePerPress() {
        var router = activeRouter()
        let press = router.handle(flags([.option, .shift]), triggersEnabled: true)
        #expect(press == KeyDecision(action: .advance(reverse: true), consume: false))
        #expect(router.handle(flags([.option, .shift, .control]), triggersEnabled: true) == .passThrough)
        #expect(router.handle(flags([.option]), triggersEnabled: true) == .passThrough)
        #expect(router.handle(flags([.option, .shift]), triggersEnabled: true).action == .advance(reverse: true))
    }

    @Test("Shift held through activation does not step again")
    func shiftHeldFromActivationDoesNotStep() {
        var router = makeRouter()
        _ = router.handle(down(.tab, [.option, .shift]), triggersEnabled: true)
        #expect(router.handle(flags([.option, .shift, .control]), triggersEnabled: true) == .passThrough)
    }

    @Test("Releasing option emits release once and keeps the switcher active")
    func releasingHoldEmitsReleaseOnce() {
        var router = activeRouter()
        #expect(router.handle(flags([]), triggersEnabled: true) == KeyDecision(action: .release, consume: false))
        #expect(router.state == .active(shortcut: 0, holding: false, searching: false))
        #expect(router.handle(flags([.control]), triggersEnabled: true) == .passThrough)
        #expect(router.handle(flags([]), triggersEnabled: true) == .passThrough)
        #expect(router.state == .active(shortcut: 0, holding: false, searching: false))
    }

    @Test("Every control key maps to its command")
    func controlKeysMapToCommands() {
        let cases: [(KeyEvent, SwitcherCommand)] = [
            (down(.return), .focusSelected),
            (down(.escape), .cancel),
            (down(.left), .moveLeft),
            (down(.right), .moveRight),
            (down(.up), .moveUp),
            (down(.down), .moveDown),
            (letter("w"), .closeWindow),
            (letter("m"), .toggleMinimize),
            (letter("f"), .toggleFullscreen),
            (letter("q"), .quitApp),
            (letter("h"), .toggleHideApp),
            (letter("s"), .beginSearch),
        ]
        for (event, command) in cases {
            var router = activeRouter()
            #expect(router.handle(event, triggersEnabled: true) == KeyDecision(action: .command(command), consume: true))
        }
    }

    @Test("Vim keys move and win over hide on h")
    func vimKeysWinOverActions() {
        var controls = ControlSettings()
        controls.vimKeys = true
        let cases: [(KeyEvent, SwitcherCommand)] = [
            (letter("h"), .moveLeft),
            (letter("j"), .moveDown),
            (letter("k"), .moveUp),
            (letter("l"), .moveRight),
            (letter("w"), .closeWindow),
        ]
        for (event, command) in cases {
            var router = activeRouter(controls: controls)
            #expect(router.handle(event, triggersEnabled: true).action == .command(command))
        }
    }

    @Test("Key repeats only navigate: a held W closes one window, a held arrow keeps moving")
    func repeatsOnlyNavigate() {
        var router = activeRouter()
        #expect(router.handle(letter("w"), triggersEnabled: true).action == .command(.closeWindow))
        var repeated = letter("w")
        repeated.isRepeat = true
        #expect(router.handle(repeated, triggersEnabled: true) == KeyDecision(action: nil, consume: true))
        #expect(router.handle(down(.escape, repeat: true), triggersEnabled: true) == KeyDecision(action: nil, consume: true))
        #expect(router.handle(down(.right, repeat: true), triggersEnabled: true) == KeyDecision(action: .command(.moveRight), consume: true))
    }

    @Test("Arrows do nothing when arrow keys are off, but are still swallowed")
    func arrowsDisabled() {
        var controls = ControlSettings()
        controls.arrowKeys = false
        var router = activeRouter(controls: controls)
        #expect(router.handle(down(.left), triggersEnabled: true) == KeyDecision(action: nil, consume: true))
    }

    @Test("A disabled control key does nothing")
    func disabledControlDoesNothing() {
        var controls = ControlSettings()
        controls.close = nil
        var router = activeRouter(controls: controls)
        #expect(router.handle(letter("w"), triggersEnabled: true) == KeyDecision(action: nil, consume: true))
    }

    @Test("Unknown keys are swallowed without an action while active")
    func unknownKeySwallowed() {
        var router = activeRouter()
        #expect(router.handle(letter("z"), triggersEnabled: true) == KeyDecision(action: nil, consume: true))
        #expect(router.handle(down(.f5), triggersEnabled: true) == KeyDecision(action: nil, consume: true))
    }

    @Test("Idle keys that are not shortcuts pass through")
    func idleKeysPassThrough() {
        var router = makeRouter()
        #expect(router.handle(letter("w"), triggersEnabled: true) == .passThrough)
        #expect(router.handle(down(.return), triggersEnabled: true) == .passThrough)
        #expect(router.handle(flags([.option]), triggersEnabled: true) == .passThrough)
    }

    @Test("Search mode passes text through but keeps focus, cancel, arrows and the trigger")
    func searchingPassesTextThrough() {
        var router = activeRouter()
        #expect(router.handle(letter("s"), triggersEnabled: true).action == .command(.beginSearch))
        #expect(router.state == .active(shortcut: 0, holding: true, searching: true))
        #expect(router.handle(letter("w"), triggersEnabled: true) == .passThrough)
        #expect(router.handle(letter("q"), triggersEnabled: true) == .passThrough)
        #expect(router.handle(down(.delete), triggersEnabled: true) == .passThrough)
        #expect(router.handle(down(.return), triggersEnabled: true).action == .command(.focusSelected))
        #expect(router.handle(down(.escape), triggersEnabled: true).action == .command(.cancel))
        #expect(router.handle(down(.down), triggersEnabled: true).action == .command(.moveDown))
        #expect(router.handle(down(.tab, [.option]), triggersEnabled: true).action == .advance(reverse: false))
        // Shift is typing capitals now, not stepping back.
        #expect(router.handle(flags([.option, .shift]), triggersEnabled: true) == .passThrough)
    }

    @Test("setSearching toggles search only while active")
    func setSearchingTogglesWhileActive() {
        var router = makeRouter()
        router.setSearching(true)
        #expect(router.state == .idle)
        router.activateWithoutHold(shortcut: 1)
        router.setSearching(true)
        #expect(router.state == .active(shortcut: 1, holding: false, searching: true))
        router.setSearching(false)
        #expect(router.state == .active(shortcut: 1, holding: false, searching: false))
    }

    @Test("A keyUp is consumed exactly when its keyDown was, even after the switcher closes")
    func keyUpPairsWithKeyDown() {
        var router = makeRouter()
        #expect(router.handle(up(.tab, [.option]), triggersEnabled: true) == .passThrough)
        _ = router.handle(down(.tab, [.option]), triggersEnabled: true)
        #expect(router.handle(up(.tab, [.option]), triggersEnabled: true) == KeyDecision(action: nil, consume: true))
        #expect(router.handle(up(.tab, [.option]), triggersEnabled: true) == .passThrough)

        _ = router.handle(letter("s"), triggersEnabled: true)
        _ = router.handle(letter("a"), triggersEnabled: true)
        #expect(router.handle(up(keyCode: 0, characters: "a"), triggersEnabled: true) == .passThrough)
        #expect(router.handle(up(keyCode: 1, characters: "s"), triggersEnabled: true).consume)

        _ = router.handle(down(.return), triggersEnabled: true)
        router.reset()
        #expect(router.handle(up(.return), triggersEnabled: true).consume)
    }

    @Test("Reset returns to idle so the next trigger activates again")
    func resetReturnsToIdle() {
        var router = activeRouter()
        router.reset()
        #expect(router.state == .idle)
        #expect(router.handle(letter("w"), triggersEnabled: true) == .passThrough)
        #expect(router.handle(down(.tab, [.option]), triggersEnabled: true).action == .activate(shortcut: 0, reverse: false))
    }

    @Test("Activated without a hold, plain Tab advances and nothing releases")
    func activateWithoutHoldAdvancesOnPlainTab() {
        var router = makeRouter()
        router.activateWithoutHold(shortcut: 0)
        #expect(router.state == .active(shortcut: 0, holding: false, searching: false))
        #expect(router.handle(down(.tab), triggersEnabled: true) == KeyDecision(action: .advance(reverse: false), consume: true))
        #expect(router.handle(flags([.option]), triggersEnabled: true) == .passThrough)
        #expect(router.handle(flags([]), triggersEnabled: true) == .passThrough)
    }

    // MARK: - Helpers

    private func makeRouter(controls: ControlSettings = ControlSettings()) -> SwitcherKeyRouter {
        SwitcherKeyRouter(shortcuts: ShortcutSettings.defaults, controls: controls)
    }

    /// Active for shortcut 0 with option held, as after ⌥⇥.
    private func activeRouter(controls: ControlSettings = ControlSettings()) -> SwitcherKeyRouter {
        var router = makeRouter(controls: controls)
        _ = router.handle(down(.tab, [.option]), triggersEnabled: true)
        return router
    }

    private func down(_ key: NamedKey, _ modifiers: ModifierSet = [], repeat isRepeat: Bool = false) -> KeyEvent {
        KeyEvent(kind: .keyDown, keyCode: key.keyCodes[0], modifiers: modifiers, isRepeat: isRepeat)
    }

    private func up(_ key: NamedKey, _ modifiers: ModifierSet = []) -> KeyEvent {
        KeyEvent(kind: .keyUp, keyCode: key.keyCodes[0], modifiers: modifiers)
    }

    private func up(keyCode: UInt16, characters: String) -> KeyEvent {
        KeyEvent(kind: .keyUp, keyCode: keyCode, modifiers: [], characters: characters)
    }

    /// A letter key with its US key code, held with option as during ⌥⇥.
    private func letter(_ character: String) -> KeyEvent {
        let codes: [String: UInt16] = [
            "a": 0, "s": 1, "f": 3, "h": 4, "z": 6, "q": 12, "w": 13, "l": 37, "j": 38, "k": 40, "m": 46,
        ]
        return KeyEvent(kind: .keyDown, keyCode: codes[character] ?? 0, modifiers: [.option], characters: character)
    }

    private func flags(_ modifiers: ModifierSet) -> KeyEvent {
        KeyEvent(kind: .flagsChanged, keyCode: 0, modifiers: modifiers)
    }
}
