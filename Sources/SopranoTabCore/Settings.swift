import Foundation

// Resolved settings: ~/.config/soprano-tab/settings.json applied over these defaults by
// `SettingsResolver` (SettingsResolver.swift). Defaults follow AltTab's. The raw values
// are the settings.json spellings.

/// Which apps' windows a shortcut lists.
public enum AppsFilter: String, CaseIterable, Sendable {
    case all
    /// The frontmost app only.
    case active
    /// Every app except the frontmost one.
    case nonActive
    /// Windows whose frame contains the mouse.
    case underCursor
    /// Windows of the app owning the frontmost window under the mouse.
    case appUnderCursor
}

public enum SpacesFilter: String, CaseIterable, Sendable {
    case all
    case visible
    case nonVisible
}

public enum ScreensFilter: String, CaseIterable, Sendable {
    case all
    /// Only windows on the display the switcher opens on.
    case showingSwitcher
}

/// How minimized, hidden, fullscreen windows and windowless apps appear.
public enum ShowPolicy: String, CaseIterable, Sendable {
    case show
    case hide
    case showAtTheEnd
}

public enum WindowOrder: String, CaseIterable, Sendable {
    case recentlyFocused
    case recentlyCreated
    case alphabetical
    case space
}

public enum AppGrouping: String, CaseIterable, Sendable {
    case allWindows
    case oneWindowPerApp
}

public enum TabGrouping: String, CaseIterable, Sendable {
    /// Hide background tabs of native macOS tab groups.
    case singleWindow
    case separateWindows
}

/// What releasing the hold modifier does.
public enum ReleaseAction: String, CaseIterable, Sendable {
    /// Focus the selected window and close the switcher.
    case focus
    /// Keep the switcher open; Return focuses, Escape cancels.
    case hold
    /// Keep the switcher open and start search.
    case search
}

public enum SwitcherStyle: String, CaseIterable, Sendable {
    case thumbnails
    case appIcons
    case titles
}

public enum SwitcherSize: String, CaseIterable, Sendable {
    case small
    case medium
    case large
    /// The largest size at which every item fits without scrolling.
    case auto
}

/// The display the switcher opens on.
public enum ScreenChoice: String, CaseIterable, Sendable {
    /// The display of the focused window (else the one with the mouse).
    case active
    case withMouse
    case withMenuBar
}

public enum TitleTruncation: String, CaseIterable, Sendable {
    case start
    case middle
    case end
}

public enum TitleContent: String, CaseIterable, Sendable {
    case windowTitle
    case appName
    case appNameAndWindowTitle
}

public enum CursorFollowsFocus: String, CaseIterable, Sendable {
    case never
    case always
    case differentScreen
}

public enum GestureKind: String, CaseIterable, Sendable {
    case disabled
    case threeFingerHorizontal
    case threeFingerVertical
    case fourFingerHorizontal
    case fourFingerVertical
}

public enum MenuBarIcon: String, CaseIterable, Sendable {
    case outlined
    case filled
    case hidden
}

public enum ExceptionHide: String, CaseIterable, Sendable {
    case never
    case always
    /// Hide the app's windowless entry (the app stays listed while it has windows).
    case whenNoOpenWindow
    /// Hide windows whose title contains one of `ExceptionRule.titleContains`.
    case whenTitleContains
}

public enum ExceptionIgnore: String, CaseIterable, Sendable {
    case never
    /// Shortcuts pass through to the app while it is frontmost.
    case always
    /// Shortcuts pass through while the app's focused window is fullscreen.
    case whenFullscreen
}

/// Which windows a shortcut lists and in what order.
public struct WindowFilters: Equatable, Sendable {
    public var apps: AppsFilter = .all
    public var spaces: SpacesFilter = .all
    public var screens: ScreensFilter = .all
    public var minimized: ShowPolicy = .show
    public var hidden: ShowPolicy = .show
    public var fullscreen: ShowPolicy = .show
    public var windowlessApps: ShowPolicy = .showAtTheEnd
    public var order: WindowOrder = .recentlyFocused
    public var grouping: AppGrouping = .allWindows
    public var tabs: TabGrouping = .singleWindow

    public init(
        apps: AppsFilter = .all,
        spaces: SpacesFilter = .all,
        screens: ScreensFilter = .all,
        minimized: ShowPolicy = .show,
        hidden: ShowPolicy = .show,
        fullscreen: ShowPolicy = .show,
        windowlessApps: ShowPolicy = .showAtTheEnd,
        order: WindowOrder = .recentlyFocused,
        grouping: AppGrouping = .allWindows,
        tabs: TabGrouping = .singleWindow
    ) {
        self.apps = apps
        self.spaces = spaces
        self.screens = screens
        self.minimized = minimized
        self.hidden = hidden
        self.fullscreen = fullscreen
        self.windowlessApps = windowlessApps
        self.order = order
        self.grouping = grouping
        self.tabs = tabs
    }
}

/// Per-shortcut appearance; nil keeps the global `appearance` value.
public struct AppearanceOverrides: Equatable, Sendable {
    public var style: SwitcherStyle?
    public var size: SwitcherSize?
    /// A Soprano theme id ("folio", "folio-paper", …) or "soprano".
    public var theme: String?
    public var previewSelectedWindow: Bool?

    public init(style: SwitcherStyle? = nil, size: SwitcherSize? = nil, theme: String? = nil, previewSelectedWindow: Bool? = nil) {
        self.style = style
        self.size = size
        self.theme = theme
        self.previewSelectedWindow = previewSelectedWindow
    }
}

/// One switcher shortcut: hold `hold`, press `key`.
public struct ShortcutSettings: Equatable, Sendable {
    public var hold: ModifierSet
    public var key: KeySpec
    public var filters: WindowFilters
    public var onRelease: ReleaseAction
    public var overrides: AppearanceOverrides

    public init(
        hold: ModifierSet,
        key: KeySpec,
        filters: WindowFilters = WindowFilters(),
        onRelease: ReleaseAction = .focus,
        overrides: AppearanceOverrides = AppearanceOverrides()
    ) {
        self.hold = hold
        self.key = key
        self.filters = filters
        self.onRelease = onRelease
        self.overrides = overrides
    }

    /// AltTab's two default shortcuts: ⌥⇥ for every app, ⌥` for the active app.
    public static let defaults: [ShortcutSettings] = [
        ShortcutSettings(hold: .option, key: .named(.tab)),
        ShortcutSettings(hold: .option, key: .named(.keyAboveTab), filters: WindowFilters(apps: .active)),
    ]

    /// Filters a shortcut at `index` starts from when settings.json omits them
    /// (AltTab: 1 all apps, 2 active app, 3 non-active apps, the rest all apps).
    public static func defaultFilters(forIndex index: Int) -> WindowFilters {
        switch index {
        case 1: WindowFilters(apps: .active)
        case 2: WindowFilters(apps: .nonActive)
        default: WindowFilters()
        }
    }
}

/// Trackpad swipe trigger. It has its own filters, like a shortcut.
public struct GestureSettings: Equatable, Sendable {
    public var kind: GestureKind = .disabled
    public var filters = WindowFilters()
    public var hapticFeedback = true

    public init(kind: GestureKind = .disabled, filters: WindowFilters = WindowFilters(), hapticFeedback: Bool = true) {
        self.kind = kind
        self.filters = filters
        self.hapticFeedback = hapticFeedback
    }
}

/// Keys while the switcher is open ("shortcuts when active"). nil disables one.
public struct ControlSettings: Equatable, Sendable {
    public var focus: KeySpec? = .named(.return)
    /// Pressing this modifier alone, or holding it with the trigger key, steps backwards.
    public var previous: ModifierSet = .shift
    public var cancel: KeySpec? = .named(.escape)
    public var close: KeySpec? = .character("w")
    public var minimize: KeySpec? = .character("m")
    public var fullscreen: KeySpec? = .character("f")
    public var quit: KeySpec? = .character("q")
    public var hide: KeySpec? = .character("h")
    public var search: KeySpec? = .character("s")
    public var arrowKeys = true
    /// h/j/k/l move; they win over action keys bound to the same letters.
    public var vimKeys = false

    public init() {}
}

public struct MouseSettings: Equatable, Sendable {
    /// Hovering a tile selects it (tiles always highlight and show controls on hover).
    public var hoverSelects = false
    public var cursorFollowsFocus: CursorFollowsFocus = .never

    public init(hoverSelects: Bool = false, cursorFollowsFocus: CursorFollowsFocus = .never) {
        self.hoverSelects = hoverSelects
        self.cursorFollowsFocus = cursorFollowsFocus
    }
}

public struct AppearanceSettings: Equatable, Sendable {
    public var style: SwitcherStyle = .thumbnails
    public var size: SwitcherSize = .auto
    public var screen: ScreenChoice = .active
    public var titles: TitleContent = .windowTitle
    public var titleTruncation: TitleTruncation = .end
    /// Close / minimize / full-screen controls in the macOS traffic-light colours on the
    /// hovered tile (AltTab's coloured circles), a quit control on a windowless app's tile.
    public var windowControls = true
    /// "Space 2" / "All Spaces" chips on tiles.
    public var spaceLabels = false
    /// "Minimized" / "Hidden" / "Full screen" chips on tiles.
    public var statusIcons = true
    /// A quick tap switches without ever showing the panel when it is shorter than this.
    public var showDelayMs = 100
    public var fadeOut = false
    /// Show the selected window full size behind the switcher.
    public var previewSelectedWindow = false
    public var previewFadeIn = true
    /// "S search" hint in the panel header.
    public var searchHint = true
    /// Refresh thumbnails as windows change, so the first show is instant and windows on
    /// other Spaces keep a recent image. Off: capture only while the switcher is open.
    public var captureInBackground = true

    public init() {}

    public static let showDelayRange = 0...2000
}

/// An app-specific exception (AltTab's blacklist).
public struct ExceptionRule: Equatable, Sendable {
    /// A bundle identifier; a value ending in "." matches every identifier with that prefix.
    public var bundleID: String
    public var hide: ExceptionHide
    public var titleContains: [String]
    public var ignoreShortcuts: ExceptionIgnore

    public init(bundleID: String, hide: ExceptionHide = .never, titleContains: [String] = [], ignoreShortcuts: ExceptionIgnore = .never) {
        self.bundleID = bundleID
        self.hide = hide
        self.titleContains = titleContains
        self.ignoreShortcuts = ignoreShortcuts
    }

    /// AltTab's default exceptions: Finder without windows is hidden; remote desktops and
    /// virtual machines keep the shortcut while fullscreen.
    public static let defaults: [ExceptionRule] = [
        ExceptionRule(bundleID: "com.apple.finder", hide: .whenNoOpenWindow),
        ExceptionRule(bundleID: "com.apple.ScreenSharing", ignoreShortcuts: .whenFullscreen),
        ExceptionRule(bundleID: "com.microsoft.rdc.macos", ignoreShortcuts: .whenFullscreen),
        ExceptionRule(bundleID: "com.teamviewer.TeamViewer", ignoreShortcuts: .whenFullscreen),
        ExceptionRule(bundleID: "org.virtualbox.app.VirtualBoxVM", ignoreShortcuts: .whenFullscreen),
        ExceptionRule(bundleID: "com.parallels.", ignoreShortcuts: .whenFullscreen),
        ExceptionRule(bundleID: "com.citrix.XenAppViewer", ignoreShortcuts: .whenFullscreen),
        ExceptionRule(bundleID: "com.citrix.receiver.icaviewer.mac", ignoreShortcuts: .whenFullscreen),
        ExceptionRule(bundleID: "com.nicesoftware.dcvviewer", ignoreShortcuts: .whenFullscreen),
        ExceptionRule(bundleID: "com.vmware.fusion", ignoreShortcuts: .whenFullscreen),
        ExceptionRule(bundleID: "com.utmapp.UTM", ignoreShortcuts: .whenFullscreen),
        ExceptionRule(bundleID: "com.McAfee.McAfeeSafariHost", hide: .always),
    ]
}

public struct AppBehaviorSettings: Equatable, Sendable {
    /// Registered as a login item (SMAppService) whenever this is true.
    public var startAtLogin = true
    public var menuBarIcon: MenuBarIcon = .outlined

    public init(startAtLogin: Bool = true, menuBarIcon: MenuBarIcon = .outlined) {
        self.startAtLogin = startAtLogin
        self.menuBarIcon = menuBarIcon
    }
}

public struct SopranoTabSettings: Equatable, Sendable {
    /// A Soprano theme id ("folio" follows macOS), or "soprano" to follow the theme and
    /// appearance in ~/.config/soprano/settings.json.
    public var theme = "soprano"
    /// 1...9 shortcuts; index 0 is "shortcut 1".
    public var shortcuts = ShortcutSettings.defaults
    public var gesture = GestureSettings()
    public var controls = ControlSettings()
    public var mouse = MouseSettings()
    public var appearance = AppearanceSettings()
    public var exceptions = ExceptionRule.defaults
    public var app = AppBehaviorSettings()

    public init() {}

    public static let defaults = SopranoTabSettings()
    public static let maxShortcuts = 9

    /// Effective style for a shortcut (`gestureIndex` for the gesture).
    public func style(forShortcut index: Int) -> SwitcherStyle {
        overrides(forShortcut: index).style ?? appearance.style
    }

    public func size(forShortcut index: Int) -> SwitcherSize {
        overrides(forShortcut: index).size ?? appearance.size
    }

    public func previewSelectedWindow(forShortcut index: Int) -> Bool {
        overrides(forShortcut: index).previewSelectedWindow ?? appearance.previewSelectedWindow
    }

    /// The theme id override for a shortcut, nil to use `theme`.
    public func themeOverride(forShortcut index: Int) -> String? {
        overrides(forShortcut: index).theme
    }

    /// Filters for a shortcut index, or the gesture's for `gestureIndex`.
    public func filters(forShortcut index: Int) -> WindowFilters {
        if index == Self.gestureIndex { return gesture.filters }
        return shortcuts.indices.contains(index) ? shortcuts[index].filters : WindowFilters()
    }

    public func onRelease(forShortcut index: Int) -> ReleaseAction {
        if index == Self.gestureIndex { return .focus }
        return shortcuts.indices.contains(index) ? shortcuts[index].onRelease : .focus
    }

    /// The pseudo shortcut index the trackpad gesture opens the switcher with.
    public static let gestureIndex = maxShortcuts

    private func overrides(forShortcut index: Int) -> AppearanceOverrides {
        shortcuts.indices.contains(index) ? shortcuts[index].overrides : AppearanceOverrides()
    }
}

/// A problem found while resolving settings.json. Issues never block startup: a bad
/// value keeps its default and is reported (Soprano's `ConfigIssue`).
public struct ConfigIssue: Equatable, Identifiable, Sendable {
    public enum Severity: Equatable, Sendable {
        /// The document could not be read at all; the last good settings stay in force.
        case error
        /// One key was ignored; everything else applied.
        case warning
    }

    public let severity: Severity
    public let message: String
    /// 1-based line in settings.json, when the problem has a position.
    public var line: Int?

    public init(severity: Severity, message: String, line: Int? = nil) {
        self.severity = severity
        self.message = message
        self.line = line
    }

    public var id: String { "\(severity)-\(line ?? 0)-\(message)" }
}

/// The result of resolving settings.json text.
public struct SettingsResolution: Equatable, Sendable {
    /// nil when the document could not be parsed (keep the last good settings);
    /// `issues` then holds one `.error`.
    public var settings: SopranoTabSettings?
    public var issues: [ConfigIssue]

    public init(settings: SopranoTabSettings?, issues: [ConfigIssue]) {
        self.settings = settings
        self.issues = issues
    }
}
