import AppKit
import SopranoTabCore

/// What a snapshot run ended with, written by `--report` for agents to check behavior
/// without reading pixels.
struct SnapshotReport: Equatable, Encodable {
    /// The switcher is still open.
    var active: Bool
    var selectedIndex: Int?
    /// The listed items' display titles, in order (after search filtering).
    var items: [String]
    var query: String
    /// Every window action, in order (`WindowActionRecord.reportText`).
    var actions: [String]

    private enum CodingKeys: String, CodingKey {
        case active, selectedIndex, items, query, actions
    }

    /// Writes `selectedIndex` as `null` instead of omitting it.
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(active, forKey: .active)
        try container.encode(selectedIndex, forKey: .selectedIndex)
        try container.encode(items, forKey: .items)
        try container.encode(query, forKey: .query)
        try container.encode(actions, forKey: .actions)
    }

    /// Pretty-printed JSON with sorted keys.
    func jsonData() throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        return try encoder.encode(self)
    }
}

/// `SopranoTab snapshot --out <png> …` (see `usage`).
///
/// Runs the real `SwitcherController` and `SwitcherWindow` on a fixture desktop with an
/// immediate scheduler, offscreen: no Dock icon, no activation, no persisted state, no
/// permission. Presses the shortcut, replays `--keys`, applies `--search` and `--hover`,
/// then writes the panel over a drawn desktop as a PNG (and the report as JSON).
@MainActor
enum SnapshotCommand {
    /// One `--keys` token.
    enum KeyToken: Equatable {
        /// `tab`: the shortcut's trigger key again (pressed with the hold modifiers when
        /// the switcher is closed).
        case trigger
        /// `shift+tab`: the trigger key with the previous modifier held.
        case reverseTrigger
        /// `shift`: the previous modifier pressed alone, then let go.
        case previousModifier
        /// `release`: every modifier up.
        case release
        /// `left right up down return escape`.
        case named(NamedKey)
        /// A single letter or digit.
        case character(Character)
    }

    struct Options: Equatable {
        var out: URL
        var scenario: FixtureScenario = .standard
        var screenSize = FixtureScenario.defaultScreenSize
        var style: SwitcherStyle?
        var size: SwitcherSize?
        var theme: String?
        /// 0-based; `--shortcut` takes the 1-based number.
        var shortcutIndex = 0
        var settings: URL?
        var keys: [KeyToken] = []
        var search: String?
        var hover: Int?
        var preview = false
        var onboarding = false
        var accessibilityGranted = false
        var screenRecordingGranted = false
        var report: URL?
    }

    enum OptionError: Error, Equatable, CustomStringConvertible {
        case missingValue(String)
        case unknownOption(String)
        case missingOut
        case badScenario(String)
        case badScreen(String)
        case badStyle(String)
        case badSize(String)
        case badShortcut(String)
        case badHover(String)
        case unknownKeyToken(String)
        case badPermissions(String)
        case permissionsWithoutOnboarding

        var description: String {
            switch self {
            case let .missingValue(option): "\(option) needs a value"
            case let .unknownOption(option): "unknown option \(option)"
            case .missingOut: "--out <png> is required"
            case let .badScenario(value):
                "--scenario must be one of \(FixtureScenario.allCases.map(\.rawValue).joined(separator: ", ")), got \(value)"
            case let .badScreen(value): "--screen must be WIDTHxHEIGHT, at least 800x500, got \(value)"
            case let .badStyle(value): "--style must be thumbnails, appIcons or titles, got \(value)"
            case let .badSize(value): "--size must be small, medium, large or auto, got \(value)"
            case let .badShortcut(value): "--shortcut must be 1-9, got \(value)"
            case let .badHover(value): "--hover must be a tile index (0 or more), got \(value)"
            case let .unknownKeyToken(token):
                "unknown key \"\(token)\" (use tab, shift+tab, shift, release, left, right, up, down, return, escape or a letter)"
            case let .badPermissions(value):
                "--permissions must be accessibility=granted|missing,screen=granted|missing, got \(value)"
            case .permissionsWithoutOnboarding: "--permissions needs --onboarding"
            }
        }
    }

    struct RenderError: Error, CustomStringConvertible {
        var description: String
    }

    nonisolated static let usage = """
    usage: SopranoTab snapshot --out <png> [--scenario standard|crowded|windowless|empty|multiScreen]
                               [--screen 1512x982] [--style thumbnails|appIcons|titles]
                               [--size small|medium|large|auto] [--theme <id>] [--shortcut <1-9>]
                               [--settings <jsonc>] [--keys "<token> …"] [--search "<text>"]
                               [--hover <index>] [--preview]
                               [--onboarding [--permissions accessibility=granted|missing,screen=granted|missing]]
                               [--report <json>]
      key tokens: tab shift+tab shift release left right up down return escape <letter>
    """

    // MARK: - Options

    nonisolated static func parse(_ arguments: [String]) throws -> Options {
        var out: URL?
        var options = Options(out: URL(fileURLWithPath: "/dev/null"))
        var sawPermissions = false
        var index = 0
        func value(_ option: String) throws -> String {
            index += 1
            guard index < arguments.count else { throw OptionError.missingValue(option) }
            return arguments[index]
        }
        func fileURL(_ path: String) -> URL {
            URL(fileURLWithPath: NSString(string: path).expandingTildeInPath).standardizedFileURL
        }
        while index < arguments.count {
            let option = arguments[index]
            switch option {
            case "--out": out = fileURL(try value(option))
            case "--report": options.report = fileURL(try value(option))
            case "--settings": options.settings = fileURL(try value(option))
            case "--theme": options.theme = try value(option)
            case "--search": options.search = try value(option)
            case "--preview": options.preview = true
            case "--onboarding": options.onboarding = true
            case "--scenario":
                let text = try value(option)
                guard let scenario = FixtureScenario(rawValue: text) else { throw OptionError.badScenario(text) }
                options.scenario = scenario
            case "--screen":
                let text = try value(option)
                let parts = text.lowercased().split(separator: "x", omittingEmptySubsequences: false).map { Int($0) }
                guard parts.count == 2, let width = parts[0], let height = parts[1], width >= 800, height >= 500 else {
                    throw OptionError.badScreen(text)
                }
                options.screenSize = CGSize(width: width, height: height)
            case "--style":
                let text = try value(option)
                guard let style = SwitcherStyle(rawValue: text) else { throw OptionError.badStyle(text) }
                options.style = style
            case "--size":
                let text = try value(option)
                guard let size = SwitcherSize(rawValue: text) else { throw OptionError.badSize(text) }
                options.size = size
            case "--shortcut":
                let text = try value(option)
                guard let number = Int(text), (1...SopranoTabSettings.maxShortcuts).contains(number) else {
                    throw OptionError.badShortcut(text)
                }
                options.shortcutIndex = number - 1
            case "--hover":
                let text = try value(option)
                guard let hover = Int(text), hover >= 0 else { throw OptionError.badHover(text) }
                options.hover = hover
            case "--keys":
                options.keys = try value(option).split(whereSeparator: \.isWhitespace).map { try keyToken(String($0)) }
            case "--permissions":
                let text = try value(option)
                let granted = try permissions(text)
                options.accessibilityGranted = granted.accessibility
                options.screenRecordingGranted = granted.screen
                sawPermissions = true
            default:
                throw OptionError.unknownOption(option)
            }
            index += 1
        }
        guard let out else { throw OptionError.missingOut }
        if sawPermissions, !options.onboarding { throw OptionError.permissionsWithoutOnboarding }
        options.out = out
        return options
    }

    nonisolated static func keyToken(_ text: String) throws -> KeyToken {
        switch text.lowercased() {
        case "tab": return .trigger
        case "shift+tab": return .reverseTrigger
        case "shift": return .previousModifier
        case "release": return .release
        case "left": return .named(.left)
        case "right": return .named(.right)
        case "up": return .named(.up)
        case "down": return .named(.down)
        case "return", "enter": return .named(.return)
        case "escape", "esc": return .named(.escape)
        default:
            let lowered = text.lowercased()
            guard lowered.count == 1, let character = lowered.first, letterKeyCode(character) != nil else {
                throw OptionError.unknownKeyToken(text)
            }
            return .character(character)
        }
    }

    /// "accessibility=granted,screen=missing" → (true, false); omitted entries stay missing.
    private nonisolated static func permissions(_ text: String) throws -> (accessibility: Bool, screen: Bool) {
        var accessibility = false
        var screen = false
        for entry in text.split(separator: ",") {
            let pair = entry.split(separator: "=", omittingEmptySubsequences: false).map {
                $0.trimmingCharacters(in: .whitespaces).lowercased()
            }
            guard pair.count == 2, pair[1] == "granted" || pair[1] == "missing" else {
                throw OptionError.badPermissions(text)
            }
            let granted = pair[1] == "granted"
            switch pair[0] {
            case "accessibility": accessibility = granted
            case "screen", "screenrecording": screen = granted
            default: throw OptionError.badPermissions(text)
            }
        }
        return (accessibility, screen)
    }

    // MARK: - Running

    static func run(arguments: [String]) -> Never {
        let options: Options
        do {
            options = try parse(arguments)
        } catch {
            FileHandle.standardError.write(Data("snapshot: \(error)\n\(usage)\n".utf8))
            exit(2)
        }
        // In-memory registration domain only: nothing is written to the user's defaults.
        UserDefaults.standard.register(defaults: [
            "ApplePersistenceIgnoreState": true,
            "NSQuitAlwaysKeepsWindows": false,
        ])
        let app = NSApplication.shared
        // No Dock icon, no menu bar, never activated: nothing appears on the user's screen.
        app.setActivationPolicy(.prohibited)
        do {
            let result = try render(options)
            try writePNG(result.image, to: options.out)
            if let reportURL = options.report {
                try createParentDirectory(of: reportURL)
                try result.report.jsonData().write(to: reportURL)
            }
            print(options.out.path)
            exit(0)
        } catch {
            FileHandle.standardError.write(Data("snapshot: \(error)\n".utf8))
            exit(1)
        }
    }

    /// The testable core: the rendered image (`screen.frame` size × scale) and the report.
    static func render(_ options: Options) throws -> (image: CGImage, report: SnapshotReport) {
        let settings = try resolveSettings(options)
        let theme = harnessTheme(settings.theme)
        // Popovers and text the theme does not draw follow the app's appearance; restore it
        // afterwards so callers in the same process (tests) keep their own.
        let previousAppearance = NSApplication.shared.appearance
        NSApplication.shared.appearance = theme.appearance.nsAppearance
        defer { NSApplication.shared.appearance = previousAppearance }

        if options.onboarding {
            let accessibility = options.accessibilityGranted
            let screenRecording = options.screenRecordingGranted
            let controller = PermissionsWindowController(
                status: { PermissionStatus(accessibility: accessibility, screenRecording: screenRecording) },
                theme: theme
            )
            guard let image = controller.renderImage() else {
                throw RenderError(description: "the permissions window did not render")
            }
            return (image, SnapshotReport(active: false, selectedIndex: nil, items: [], query: "", actions: []))
        }

        guard settings.shortcuts.indices.contains(options.shortcutIndex) else {
            throw RenderError(description: "--shortcut \(options.shortcutIndex + 1): settings define \(settings.shortcuts.count) shortcuts")
        }
        let shortcut = settings.shortcuts[options.shortcutIndex]

        let source = FixtureWindowSource(scenario: options.scenario, screenSize: options.screenSize)
        let thumbnails = FixtureThumbnails(source: source, colors: theme.colors)
        let actions = RecordingWindowActions(source: source)
        SwitcherWindow.offscreen = true
        let presenter = SwitcherWindow()
        let environment = SwitcherEnvironment(
            settings: { settings },
            theme: { $0.map(harnessTheme) ?? theme },
            schedule: { _, work in
                work()
                return {}
            },
            haptic: {}
        )
        let controller = SwitcherController(
            source: source,
            thumbnails: thumbnails,
            actions: actions,
            icons: FixtureIcons(),
            presenter: presenter,
            environment: environment
        )

        var keyboard = KeyboardReplay(shortcut: shortcut, controls: settings.controls)
        for event in keyboard.events(for: .trigger, isActive: false) {
            _ = controller.handleKeyEvent(event)
        }
        // Where the panel opened; later focus changes must not move the picture.
        let screen = ScreenChooser.screen(for: settings.appearance.screen, in: source.snapshot)

        for token in options.keys {
            for event in keyboard.events(for: token, isActive: controller.isActive) {
                _ = controller.handleKeyEvent(event)
            }
        }
        if let text = options.search {
            if controller.isActive, controller.session?.isSearching == false, let searchKey = settings.controls.search {
                for event in keyboard.events(for: searchKey) {
                    _ = controller.handleKeyEvent(event)
                }
            }
            controller.searchTextDidChange(text)
        }
        if let hover = options.hover {
            presenter.onHover?(hover)
        }

        guard let screen else { throw RenderError(description: "the scenario has no screen") }
        guard let backdrop = backdrop(for: screen, snapshot: source.snapshot, colors: theme.colors) else {
            throw RenderError(description: "the backdrop did not render")
        }
        let image = presenter.renderSnapshot(screen: screen, backdrop: backdrop) ?? backdrop
        let session = controller.session
        let report = SnapshotReport(
            active: controller.isActive,
            selectedIndex: session?.selectedIndex,
            items: session?.items.map(\.displayTitle) ?? [],
            query: session?.query ?? "",
            actions: actions.log.map(\.reportText)
        )
        return (image, report)
    }

    /// The harness resolves themes against a light system appearance, so it never reads
    /// Soprano's settings or the Mac's mode: the default (`soprano`), `folio` and
    /// `folio-paper` render Folio Paper; `folio-ink` and the third-party themes are dark.
    static func harnessTheme(_ id: String) -> AppTheme {
        AppTheme.theme(for: id == "soprano" ? AppTheme.folioId : id, appearance: .light)
    }

    /// Defaults or `--settings`, then the flag overrides.
    private static func resolveSettings(_ options: Options) throws -> SopranoTabSettings {
        var settings = SopranoTabSettings.defaults
        let knownThemeIDs = Set(AppTheme.options.map(\.id))
        if let url = options.settings {
            let text: String
            do {
                text = try String(contentsOf: url, encoding: .utf8)
            } catch {
                throw RenderError(description: "cannot read \(url.path): \(error.localizedDescription)")
            }
            let resolution = SettingsResolver.resolve(text: text, knownThemeIDs: knownThemeIDs)
            guard let resolved = resolution.settings else {
                let message = resolution.issues.map(issueText).joined(separator: "; ")
                throw RenderError(description: "\(url.path): \(message)")
            }
            for issue in resolution.issues {
                FileHandle.standardError.write(Data("snapshot: \(url.lastPathComponent): \(issueText(issue))\n".utf8))
            }
            settings = resolved
        }
        if let theme = options.theme {
            guard theme == "soprano" || knownThemeIDs.contains(theme) else {
                throw RenderError(description: "unknown theme \(theme) (soprano, \(AppTheme.options.map(\.id).joined(separator: ", ")))")
            }
            settings.theme = theme
        }
        if let style = options.style { settings.appearance.style = style }
        if let size = options.size { settings.appearance.size = size }
        if options.preview { settings.appearance.previewSelectedWindow = true }
        return settings
    }

    private static func issueText(_ issue: ConfigIssue) -> String {
        issue.line.map { "line \($0): \(issue.message)" } ?? issue.message
    }

    // MARK: - Backdrop

    /// A deterministic desktop for `screen` in the theme's mode (Folio `--desktop-wallpaper`
    /// and `--menubar-bg`, tokens.css): a warm vertical wash with two soft glows, a menu
    /// bar strip, and every on-screen window of the visible Spaces drawn back to front with
    /// the `--shadow-window` drop shadow.
    static func backdrop(for screen: ScreenInfo, snapshot: WindowSnapshot, colors: ThemeColors) -> CGImage? {
        let size = screen.frame.size
        guard let context = FixtureDrawing.makeContext(pointSize: size, scale: screen.scale) else { return nil }
        let wallpaper = Wallpaper(appearance: colors.appearance)
        FixtureDrawing.withFlippedGraphics(context) {
            wallpaper.draw(in: CGRect(origin: .zero, size: size), context: context)
        }

        let visibleSpaces = snapshot.visibleSpaceIDs
        let onScreen = snapshot.windows
            .filter { window in
                guard !window.isWindowlessApp, !window.isMinimized, !window.app.isHidden, window.zIndex != nil,
                      window.isOnAllSpaces || window.spaceIDs.contains(where: visibleSpaces.contains)
                else { return false }
                return window.frame.intersects(screen.frame)
            }
            .sorted { ($0.zIndex ?? 0) > ($1.zIndex ?? 0) }
        FixtureDrawing.withFlippedGraphics(context) {
            for window in onScreen {
                let rect = window.frame.offsetBy(dx: -screen.frame.minX, dy: -screen.frame.minY)
                drawWindowShadow(rect, wallpaper: wallpaper, in: context)
                FixtureThumbnails.draw(window, in: rect, context: context, colors: colors)
            }
        }
        let menuBarHeight = screen.visibleFrame.minY - screen.frame.minY
        if menuBarHeight > 0 {
            context.setFillColor(wallpaper.menuBar.cgColor)
            context.fill(CGRect(x: 0, y: 0, width: size.width, height: menuBarHeight))
        }
        return context.makeImage()
    }

    private static func drawWindowShadow(_ rect: CGRect, wallpaper: Wallpaper, in context: CGContext) {
        context.saveGState()
        // Shadow offsets are in device space (y up): negative drops it below the window.
        context.setShadow(offset: CGSize(width: 0, height: -wallpaper.shadowOffset), blur: wallpaper.shadowBlur, color: wallpaper.shadow.cgColor)
        context.setFillColor(wallpaper.shadowRing.cgColor)
        context.fill(rect.insetBy(dx: -1, dy: -1))
        context.restoreGState()
    }

    /// Folio's desktop per mode.
    private struct Wallpaper {
        var linear: [(UInt32, CGFloat)]
        /// Glows: colour, centre (fractions of the screen), radius (fraction of the width).
        var glows: [(UInt32, CGPoint, CGFloat)]
        var menuBar: NSColor
        var shadow: NSColor
        var shadowRing: NSColor
        var shadowOffset: CGFloat
        var shadowBlur: CGFloat

        init(appearance: AppTheme.Appearance) {
            if appearance == .light {
                linear = [(0xE8DFCF, 0), (0xDCCFB9, 0.52), (0xCDBDA3, 1)]
                glows = [(0xF4EDE0, CGPoint(x: 0.18, y: 0.08), 0.6), (0xC9B79A, CGPoint(x: 0.85, y: 0.95), 0.45)]
                menuBar = NSColor(srgbRed: 246 / 255, green: 242 / 255, blue: 234 / 255, alpha: 0.82)
                shadow = NSColor(srgbRed: 43 / 255, green: 38 / 255, blue: 32 / 255, alpha: 0.20)
                shadowRing = NSColor(srgbRed: 43 / 255, green: 38 / 255, blue: 32 / 255, alpha: 0.10)
                shadowOffset = 18
                shadowBlur = 48
            } else {
                linear = [(0x24211D, 0), (0x1B1916, 0.55), (0x141210, 1)]
                glows = [(0x3A332B, CGPoint(x: 0.20, y: 0), 0.55), (0x4A3524, CGPoint(x: 0.88, y: 1), 0.4)]
                menuBar = NSColor(srgbRed: 29 / 255, green: 27 / 255, blue: 24 / 255, alpha: 0.78)
                shadow = NSColor.black.withAlphaComponent(0.60)
                shadowRing = NSColor.black.withAlphaComponent(0.50)
                shadowOffset = 20
                shadowBlur = 56
            }
        }

        /// Draws into a top-left-origin context.
        func draw(in rect: CGRect, context: CGContext) {
            let space = CGColorSpace(name: CGColorSpace.sRGB)
            let colors = linear.map { FixturePalette.color(hex: $0.0).cgColor } as CFArray
            if let gradient = CGGradient(colorsSpace: space, colors: colors, locations: linear.map(\.1)) {
                context.drawLinearGradient(
                    gradient,
                    start: CGPoint(x: rect.midX, y: rect.minY),
                    end: CGPoint(x: rect.midX, y: rect.maxY),
                    options: [.drawsBeforeStartLocation, .drawsAfterEndLocation]
                )
            }
            for (hex, center, radius) in glows {
                let color = FixturePalette.color(hex: hex)
                let stops = [color.cgColor, color.withAlphaComponent(0).cgColor] as CFArray
                guard let gradient = CGGradient(colorsSpace: space, colors: stops, locations: [0, 1]) else { continue }
                let point = CGPoint(x: rect.minX + rect.width * center.x, y: rect.minY + rect.height * center.y)
                context.drawRadialGradient(
                    gradient, startCenter: point, startRadius: 0, endCenter: point,
                    endRadius: rect.width * radius, options: []
                )
            }
        }
    }

    // MARK: - Output

    static func writePNG(_ image: CGImage, to url: URL) throws {
        try createParentDirectory(of: url)
        let rep = NSBitmapImageRep(cgImage: image)
        guard let data = rep.representation(using: .png, properties: [:]) else {
            throw RenderError(description: "PNG encoding failed")
        }
        try data.write(to: url)
    }

    private static func createParentDirectory(of url: URL) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
    }

    // MARK: - Keys

    /// ANSI virtual key codes for letters and digits (`kVK_ANSI_*`).
    nonisolated static func letterKeyCode(_ character: Character) -> UInt16? {
        let codes: [Character: UInt16] = [
            "a": 0x00, "s": 0x01, "d": 0x02, "f": 0x03, "h": 0x04, "g": 0x05, "z": 0x06, "x": 0x07,
            "c": 0x08, "v": 0x09, "b": 0x0B, "q": 0x0C, "w": 0x0D, "e": 0x0E, "r": 0x0F, "y": 0x10,
            "t": 0x11, "1": 0x12, "2": 0x13, "3": 0x14, "4": 0x15, "6": 0x16, "5": 0x17, "9": 0x19,
            "7": 0x1A, "8": 0x1C, "0": 0x1D, "o": 0x1F, "u": 0x20, "i": 0x22, "p": 0x23, "l": 0x25,
            "j": 0x26, "k": 0x28, "n": 0x2D, "m": 0x2E,
        ]
        return codes[character]
    }

    /// Turns tokens into the events the keyboard tap would deliver, tracking which
    /// modifiers are held between tokens.
    struct KeyboardReplay {
        let shortcut: ShortcutSettings
        let previous: ModifierSet
        private(set) var held: ModifierSet = []

        init(shortcut: ShortcutSettings, controls: ControlSettings) {
            self.shortcut = shortcut
            previous = controls.previous
        }

        mutating func events(for token: KeyToken, isActive: Bool) -> [KeyEvent] {
            switch token {
            case .trigger:
                guard isActive else {
                    // Closed: press the hold modifiers first, like a real ⌥⇥.
                    held = shortcut.hold
                    return [Self.flagsChanged(held, key: held)] + press(shortcut.key, modifiers: held)
                }
                return press(shortcut.key, modifiers: held)
            case .reverseTrigger:
                // No separate flagsChanged: a lone previous-modifier press steps back too.
                return press(shortcut.key, modifiers: held.union(previous))
            case .previousModifier:
                guard !previous.isEmpty else { return [] }
                return [Self.flagsChanged(held.union(previous), key: previous), Self.flagsChanged(held, key: previous)]
            case .release:
                let wasHeld = held
                held = []
                return [KeyEvent(kind: .flagsChanged, keyCode: Self.modifierKeyCode(wasHeld), modifiers: [])]
            case .named(let key):
                return press(.named(key), modifiers: held)
            case .character(let character):
                return press(.character(character), modifiers: held)
            }
        }

        /// A control key (e.g. the search key) with the currently held modifiers.
        func events(for key: KeySpec) -> [KeyEvent] {
            press(key, modifiers: held)
        }

        private func press(_ key: KeySpec, modifiers: ModifierSet) -> [KeyEvent] {
            let keyCode: UInt16
            let characters: String?
            var modifiers = modifiers
            switch key {
            case .named(let named):
                keyCode = named.keyCodes.first ?? 0
                characters = nil
                if [.left, .right, .up, .down].contains(named) { modifiers.insert(.function) }
            case .character(let character):
                keyCode = SnapshotCommand.letterKeyCode(character) ?? 0
                characters = String(character)
            }
            return [
                KeyEvent(kind: .keyDown, keyCode: keyCode, modifiers: modifiers, characters: characters),
                KeyEvent(kind: .keyUp, keyCode: keyCode, modifiers: modifiers, characters: characters),
            ]
        }

        /// A flagsChanged event for pressing or releasing `key`, leaving `modifiers` held.
        private static func flagsChanged(_ modifiers: ModifierSet, key: ModifierSet) -> KeyEvent {
            KeyEvent(kind: .flagsChanged, keyCode: modifierKeyCode(key), modifiers: modifiers)
        }

        /// The left-hand key code of one modifier in `modifiers`.
        private static func modifierKeyCode(_ modifiers: ModifierSet) -> UInt16 {
            if modifiers.contains(.option) { return 0x3A }
            if modifiers.contains(.command) { return 0x37 }
            if modifiers.contains(.control) { return 0x3B }
            if modifiers.contains(.shift) { return 0x38 }
            if modifiers.contains(.function) { return 0x3F }
            return 0x3A
        }
    }
}
