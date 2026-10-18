import Foundation

/// Turns raw key events into switcher actions: when a shortcut opens the switcher, what
/// each key does while it is open, and which events the event tap swallows.
///
/// See docs/ARCHITECTURE.md → Core APIs → Input for the rules.
public struct SwitcherKeyRouter: Sendable {
    public private(set) var state: KeyRouterState = .idle

    private let shortcuts: [ShortcutSettings]
    private let controls: ControlSettings
    /// Modifiers after the previous event, to tell a new `previous` press from one still held.
    private var lastModifiers: ModifierSet = []
    /// Key codes whose keyDown was consumed and whose keyUp has not arrived yet. Survives
    /// `reset()` so the keyUp of the key that closed the switcher is swallowed too.
    private var consumedKeyDowns: Set<UInt16> = []

    public init(shortcuts: [ShortcutSettings], controls: ControlSettings) {
        self.shortcuts = shortcuts
        self.controls = controls
    }

    /// `triggersEnabled == false` (exception "ignore shortcuts") lets activations pass through.
    public mutating func handle(_ event: KeyEvent, triggersEnabled: Bool) -> KeyDecision {
        let previousModifiers = lastModifiers
        lastModifiers = event.modifiers
        switch event.kind {
        case .keyDown:
            let decision = keyDown(event, triggersEnabled: triggersEnabled)
            if decision.consume {
                consumedKeyDowns.insert(event.keyCode)
            } else {
                consumedKeyDowns.remove(event.keyCode)
            }
            return decision
        case .keyUp:
            return KeyDecision(consume: consumedKeyDowns.remove(event.keyCode) != nil)
        case .flagsChanged:
            return flagsChanged(event, previousModifiers: previousModifiers)
        }
    }

    /// Active for `shortcut` with nothing held (menu, CLI `show`, gesture).
    public mutating func activateWithoutHold(shortcut: Int) {
        state = .active(shortcut: shortcut, holding: false, searching: false)
    }

    public mutating func setSearching(_ searching: Bool) {
        guard case let .active(shortcut, holding, _) = state else { return }
        state = .active(shortcut: shortcut, holding: holding, searching: searching)
    }

    /// The switcher closed (focus, cancel, click, hide).
    public mutating func reset() {
        state = .idle
    }

    // MARK: - Key down

    private mutating func keyDown(_ event: KeyEvent, triggersEnabled: Bool) -> KeyDecision {
        guard case let .active(shortcut, _, searching) = state else {
            return activation(event, triggersEnabled: triggersEnabled)
        }
        if shortcuts.indices.contains(shortcut), shortcuts[shortcut].key.matches(event) {
            return KeyDecision(action: .advance(reverse: holdsPrevious(event.modifiers)), consume: true)
        }
        if let command = command(for: event, searching: searching) {
            // Repeats only navigate: holding W closes exactly one window.
            let moves: [SwitcherCommand] = [.moveLeft, .moveRight, .moveUp, .moveDown]
            if event.isRepeat, !moves.contains(command) {
                return KeyDecision(consume: true)
            }
            if command == .beginSearch {
                setSearching(true)
            }
            return KeyDecision(action: .command(command), consume: true)
        }
        // Searching: the search field takes the key. Otherwise nothing leaks to the app behind.
        return KeyDecision(consume: !searching)
    }

    /// Idle: the first shortcut whose hold is down (plus nothing or `previous`) and whose
    /// key is pressed opens the switcher.
    private mutating func activation(_ event: KeyEvent, triggersEnabled: Bool) -> KeyDecision {
        guard triggersEnabled, !event.isRepeat else { return .passThrough }
        for (index, shortcut) in shortcuts.enumerated() {
            let modifiers = Self.comparable(event.modifiers, against: shortcut.hold)
            guard modifiers.isSuperset(of: shortcut.hold), shortcut.key.matches(event) else { continue }
            let extra = modifiers.subtracting(shortcut.hold)
            let reverse = !extra.isEmpty && extra == Self.comparable(controls.previous, against: shortcut.hold)
            guard extra.isEmpty || reverse else { continue }
            state = .active(shortcut: index, holding: true, searching: false)
            return KeyDecision(action: .activate(shortcut: index, reverse: reverse), consume: true)
        }
        return .passThrough
    }

    /// The control command for a key while active. Searching keeps only focus, cancel and
    /// arrows; vim keys win over the action keys bound to the same letters.
    private func command(for event: KeyEvent, searching: Bool) -> SwitcherCommand? {
        if controls.focus?.matches(event) == true { return .focusSelected }
        if controls.cancel?.matches(event) == true { return .cancel }
        if controls.arrowKeys {
            let arrows: [(NamedKey, SwitcherCommand)] = [
                (.left, .moveLeft), (.right, .moveRight), (.up, .moveUp), (.down, .moveDown),
            ]
            if let hit = arrows.first(where: { KeySpec.named($0.0).matches(event) }) { return hit.1 }
        }
        if searching { return nil }
        if controls.vimKeys {
            let vim: [(Character, SwitcherCommand)] = [
                ("h", .moveLeft), ("j", .moveDown), ("k", .moveUp), ("l", .moveRight),
            ]
            if let hit = vim.first(where: { KeySpec.character($0.0).matches(event) }) { return hit.1 }
        }
        let actions: [(KeySpec?, SwitcherCommand)] = [
            (controls.close, .closeWindow),
            (controls.minimize, .toggleMinimize),
            (controls.fullscreen, .toggleFullscreen),
            (controls.quit, .quitApp),
            (controls.hide, .toggleHideApp),
            (controls.search, .beginSearch),
        ]
        return actions.first(where: { $0.0?.matches(event) == true })?.1
    }

    // MARK: - Modifiers

    private mutating func flagsChanged(_ event: KeyEvent, previousModifiers: ModifierSet) -> KeyDecision {
        guard case let .active(shortcut, holding, searching) = state else { return .passThrough }
        if holding, shortcuts.indices.contains(shortcut) {
            let hold = shortcuts[shortcut].hold
            if !Self.comparable(event.modifiers, against: hold).isSuperset(of: hold) {
                state = .active(shortcut: shortcut, holding: false, searching: searching)
                return KeyDecision(action: .release, consume: false)
            }
        }
        if !searching, !holdsPrevious(previousModifiers), holdsPrevious(event.modifiers) {
            return KeyDecision(action: .advance(reverse: true), consume: false)
        }
        return .passThrough
    }

    private func holdsPrevious(_ modifiers: ModifierSet) -> Bool {
        let previous = controls.previous
        return !previous.isEmpty && Self.comparable(modifiers, against: previous).isSuperset(of: previous)
    }

    /// `.function` rides along with arrow and F keys, so it only counts when `reference`
    /// includes it.
    private static func comparable(_ modifiers: ModifierSet, against reference: ModifierSet) -> ModifierSet {
        reference.contains(.function) ? modifiers : modifiers.subtracting(.function)
    }
}
