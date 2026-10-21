import AppKit
@testable import SopranoTab
@testable import SopranoTabCore

/// A presenter that draws nothing and remembers what the controller asked for.
@MainActor
final class RecordingPresenter: SwitcherPresenting {
    struct PreviewCall: Equatable {
        var hasImage: Bool
        var frame: CGRect?
        var fadeIn: Bool
    }

    private(set) var isPresented = false
    /// The last model presented or updated.
    private(set) var model: SwitcherViewModel?
    /// The screen of the last `present`.
    private(set) var screen: ScreenInfo?
    private(set) var presentCount = 0
    private(set) var dismissCount = 0
    private(set) var previewCalls: [PreviewCall] = []
    private(set) var isSearchFocused = false
    private(set) var thumbnailUpdates: [ItemID] = []

    var onHover: ((Int?) -> Void)?
    var onClick: ((Int) -> Void)?
    var onControl: ((Int, TileControl) -> Void)?
    var onQueryChange: ((String) -> Void)?

    func present(_ model: SwitcherViewModel, on screen: ScreenInfo) {
        isPresented = true
        self.model = model
        self.screen = screen
        presentCount += 1
    }

    func update(_ model: SwitcherViewModel) {
        self.model = model
    }

    func updateThumbnail(_ image: CGImage, for id: ItemID) {
        thumbnailUpdates.append(id)
    }

    func dismiss(animated: Bool) {
        isPresented = false
        dismissCount += 1
    }

    func showPreview(_ image: CGImage?, frame: CGRect?, fadeIn: Bool) {
        previewCalls.append(PreviewCall(hasImage: image != nil, frame: frame, fadeIn: fadeIn))
    }

    func setSearchFocused(_ focused: Bool) {
        isSearchFocused = focused
    }

    /// Nothing is drawn, so there is nothing to render.
    func renderSnapshot(screen: ScreenInfo, backdrop: CGImage?) -> CGImage? {
        nil
    }
}

/// Holds scheduled work until a test fires it; cancelled work never runs.
@MainActor
final class ManualScheduler {
    private final class Entry {
        let milliseconds: Int
        let work: @MainActor () -> Void
        var isCancelled = false

        init(milliseconds: Int, work: @escaping @MainActor () -> Void) {
            self.milliseconds = milliseconds
            self.work = work
        }
    }

    private var entries: [Entry] = []

    /// Delays of the work still waiting, in scheduling order.
    var pendingDelays: [Int] {
        entries.filter { !$0.isCancelled }.map(\.milliseconds)
    }

    func schedule(_ milliseconds: Int, _ work: @escaping @MainActor () -> Void) -> () -> Void {
        let entry = Entry(milliseconds: milliseconds, work: work)
        entries.append(entry)
        return { entry.isCancelled = true }
    }

    /// Runs every pending, uncancelled piece of work (work scheduled meanwhile waits).
    func fireAll() {
        let due = entries
        entries = []
        for entry in due where !entry.isCancelled {
            entry.work()
        }
    }
}

/// A small desktop: one screen, three apps, five windows. Focus order 1, 3, 2, 4, 5 with
/// window 1 (Editor "Draft") focused, so the default list is [1, 3, 2, 4, 5] and ⌥⇥ selects
/// window 3 (Browser "Docs"). Window 4 is minimized.
enum SwitcherTestDesktop {
    static let screen = ScreenInfo(
        id: 1,
        frame: CGRect(x: 0, y: 0, width: 1512, height: 982),
        visibleFrame: CGRect(x: 0, y: 33, width: 1512, height: 949),
        scale: 2,
        hasMenuBar: true
    )
    static let editor = AppInfo(pid: 100, bundleID: "test.editor", name: "Editor", isActive: true)
    static let browser = AppInfo(pid: 200, bundleID: "test.browser", name: "Browser")
    static let terminal = AppInfo(pid: 300, bundleID: "test.terminal", name: "Terminal")

    static func window(
        _ id: WindowID,
        _ app: AppInfo,
        _ title: String,
        focus: Int,
        z: Int?,
        frame: CGRect = CGRect(x: 100, y: 100, width: 800, height: 500),
        minimized: Bool = false
    ) -> WindowInfo {
        WindowInfo(
            id: .window(id), app: app, title: title, frame: frame,
            spaceIDs: [1], spaceIndexes: [1], displayID: 1,
            isMinimized: minimized, lastFocusOrder: focus, creationOrder: Int(id), zIndex: z
        )
    }

    static let windows: [WindowInfo] = [
        window(1, editor, "Draft", focus: 0, z: 0),
        window(2, editor, "Notes doc", focus: 2, z: 2, frame: CGRect(x: 200, y: 150, width: 900, height: 600)),
        window(3, browser, "Docs", focus: 1, z: 1, frame: CGRect(x: 300, y: 120, width: 1000, height: 700)),
        window(4, browser, "News", focus: 3, z: nil, minimized: true),
        window(5, terminal, "Shell", focus: 4, z: 3, frame: CGRect(x: 50, y: 400, width: 600, height: 400)),
    ]

    static func snapshot(windows: [WindowInfo] = windows) -> WindowSnapshot {
        WindowSnapshot(
            windows: windows,
            screens: [screen],
            spaces: [SpaceInfo(id: 1, index: 1, displayID: 1, isVisible: true)],
            mouseLocation: CGPoint(x: 700, y: 500),
            frontmostPID: editor.pid,
            focusedWindowID: 1
        )
    }
}

/// Window actions that are asked but never happen (Finder refusing to quit, a window
/// answering close with a "Save changes?" sheet): records each call, leaves the catalog alone.
@MainActor
final class RefusingWindowActions: WindowActing {
    private(set) var log: [WindowActionRecord] = []

    func focus(_ item: WindowInfo) { log.append(.focus(item.id)) }
    func close(_ item: WindowInfo) { log.append(.close(item.id)) }
    func toggleMinimize(_ item: WindowInfo) { log.append(.toggleMinimize(item.id)) }
    func toggleFullscreen(_ item: WindowInfo) { log.append(.toggleFullscreen(item.id)) }
    func quitApp(_ item: WindowInfo) { log.append(.quitApp(item.app.pid)) }
    func toggleHideApp(_ item: WindowInfo) { log.append(.toggleHideApp(item.app.pid)) }
    func moveCursor(toCenterOf item: WindowInfo) { log.append(.moveCursor(item.id)) }
}

/// A `SwitcherController` on fixtures with a recording presenter and a manual scheduler,
/// plus helpers that type like a person at the keyboard. Actions go to `actions` (which
/// applies them to the fixture source), or to `refusingActions` when `refusesActions`.
@MainActor
final class SwitcherHarness {
    /// Settings and haptic ticks the environment closures read and write.
    private final class State {
        var settings: SopranoTabSettings
        var haptics = 0

        init(settings: SopranoTabSettings) {
            self.settings = settings
        }
    }

    let source: FixtureWindowSource
    let thumbnails: FixtureThumbnails
    let actions: RecordingWindowActions
    let refusingActions: RefusingWindowActions
    let presenter: RecordingPresenter
    let scheduler: ManualScheduler
    let controller: SwitcherController
    private let state: State

    init(
        snapshot: WindowSnapshot = SwitcherTestDesktop.snapshot(),
        settings: SopranoTabSettings = SopranoTabSettings(),
        refusesActions: Bool = false
    ) {
        let source = FixtureWindowSource(snapshot: snapshot)
        let thumbnails = FixtureThumbnails(source: source)
        let actions = RecordingWindowActions(source: source)
        let refusingActions = RefusingWindowActions()
        let presenter = RecordingPresenter()
        let scheduler = ManualScheduler()
        let state = State(settings: settings)
        let environment = SwitcherEnvironment(
            settings: { state.settings },
            theme: { _ in AppTheme.folioPaper },
            schedule: { milliseconds, work in scheduler.schedule(milliseconds, work) },
            haptic: { state.haptics += 1 }
        )
        self.source = source
        self.thumbnails = thumbnails
        self.actions = actions
        self.refusingActions = refusingActions
        self.presenter = presenter
        self.scheduler = scheduler
        self.state = state
        controller = SwitcherController(
            source: source,
            thumbnails: thumbnails,
            actions: refusesActions ? refusingActions as WindowActing : actions,
            icons: FixtureIcons(),
            presenter: presenter,
            environment: environment
        )
    }

    /// Changing settings takes effect through `controller.settingsDidChange()`.
    var settings: SopranoTabSettings {
        get { state.settings }
        set { state.settings = newValue }
    }

    var hapticCount: Int { state.haptics }

    var selectedID: ItemID? { controller.session?.selectedItem?.id }

    /// Option goes down, then Tab (down and up) with Option held; returns whether the Tab
    /// press was swallowed.
    @discardableResult
    func pressOptionTab() -> Bool {
        _ = controller.handleKeyEvent(Self.flags(.option))
        return press(.tab, holding: .option)
    }

    /// One named key, down and up; returns whether the keyDown was swallowed.
    @discardableResult
    func press(_ key: NamedKey, holding modifiers: ModifierSet = []) -> Bool {
        let code = key.keyCodes[0]
        let consumed = controller.handleKeyEvent(KeyEvent(kind: .keyDown, keyCode: code, modifiers: modifiers))
        _ = controller.handleKeyEvent(KeyEvent(kind: .keyUp, keyCode: code, modifiers: modifiers))
        return consumed
    }

    /// One letter key, down and up; returns whether the keyDown was swallowed.
    @discardableResult
    func type(_ letter: Character, holding modifiers: ModifierSet = []) -> Bool {
        let code = Self.letterKeyCodes[letter] ?? 0
        let characters = String(letter)
        let consumed = controller.handleKeyEvent(
            KeyEvent(kind: .keyDown, keyCode: code, modifiers: modifiers, characters: characters)
        )
        _ = controller.handleKeyEvent(KeyEvent(kind: .keyUp, keyCode: code, modifiers: modifiers, characters: characters))
        return consumed
    }

    /// Modifiers change so that exactly `modifiers` stay down (default: everything released).
    func setModifiers(_ modifiers: ModifierSet = []) {
        _ = controller.handleKeyEvent(Self.flags(modifiers))
    }

    private static func flags(_ modifiers: ModifierSet) -> KeyEvent {
        KeyEvent(kind: .flagsChanged, keyCode: 0x3A, modifiers: modifiers)
    }

    /// ANSI virtual key codes of the letters the tests type.
    private static let letterKeyCodes: [Character: UInt16] = [
        "a": 0x00, "s": 0x01, "f": 0x03, "h": 0x04, "x": 0x07, "q": 0x0C, "w": 0x0D, "e": 0x0E, "m": 0x2E,
    ]
}
