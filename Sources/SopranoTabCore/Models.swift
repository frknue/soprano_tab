import CoreGraphics
import Foundation

// The desktop as the switcher sees it. Every geometry value in Core uses global
// Quartz coordinates: origin at the top-left of the primary display, y grows down
// (the space CGWindowList, AX and CGEvent use). AppKit converts at its boundary
// with `Geometry`.

/// A real window's CGWindowID.
public typealias WindowID = UInt32
/// A Mission Control Space (CGSSpaceID / ManagedSpaceID).
public typealias SpaceID = UInt64
/// A display (CGDirectDisplayID).
public typealias DisplayID = UInt32

/// Identity of one switcher item: a real window, or a running app without windows.
public enum ItemID: Hashable, Sendable {
    case window(WindowID)
    case windowlessApp(pid_t)
}

/// A running app that owns windows (or could: windowless regular apps are items too).
public struct AppInfo: Hashable, Sendable {
    public var pid: pid_t
    public var bundleID: String?
    public var name: String
    /// The app bundle's path, for icon lookup and relaunching; nil when unknown.
    public var bundlePath: String?
    /// The frontmost app.
    public var isActive: Bool
    /// Hidden with ⌘H.
    public var isHidden: Bool
    /// Monotonic counter assigned when the catalog first saw the app (higher = later).
    public var launchOrder: Int

    public init(
        pid: pid_t,
        bundleID: String?,
        name: String,
        bundlePath: String? = nil,
        isActive: Bool = false,
        isHidden: Bool = false,
        launchOrder: Int = 0
    ) {
        self.pid = pid
        self.bundleID = bundleID
        self.name = name
        self.bundlePath = bundlePath
        self.isActive = isActive
        self.isHidden = isHidden
        self.launchOrder = launchOrder
    }
}

/// One switcher item before filtering: a window, or a windowless app's placeholder.
public struct WindowInfo: Hashable, Sendable, Identifiable {
    public var id: ItemID
    public var app: AppInfo
    /// The window title; empty when the window has none.
    public var title: String
    /// Window frame in global Quartz coordinates; `.zero` for windowless apps.
    public var frame: CGRect
    /// Spaces the window is on; empty for windowless apps, background tabs and when unknown.
    public var spaceIDs: [SpaceID]
    /// 1-based Mission Control index of each entry in `spaceIDs`, same order.
    public var spaceIndexes: [Int]
    /// Visible on every Space ("Assign To: All Desktops").
    public var isOnAllSpaces: Bool
    /// The display holding most of the window; nil for windowless apps and when unknown.
    public var displayID: DisplayID?
    public var isMinimized: Bool
    public var isFullscreen: Bool
    /// A native macOS tab that is not the selected tab of its tab group.
    public var isBackgroundTab: Bool
    /// Recency rank: 0 = most recently focused. Windowless apps rank after every window.
    public var lastFocusOrder: Int
    /// Monotonic counter assigned when the catalog first saw the window (higher = newer).
    public var creationOrder: Int
    /// Front-to-back rank among on-screen windows (0 = frontmost); nil when not on screen.
    public var zIndex: Int?

    public init(
        id: ItemID,
        app: AppInfo,
        title: String,
        frame: CGRect = .zero,
        spaceIDs: [SpaceID] = [],
        spaceIndexes: [Int] = [],
        isOnAllSpaces: Bool = false,
        displayID: DisplayID? = nil,
        isMinimized: Bool = false,
        isFullscreen: Bool = false,
        isBackgroundTab: Bool = false,
        lastFocusOrder: Int = 0,
        creationOrder: Int = 0,
        zIndex: Int? = nil
    ) {
        self.id = id
        self.app = app
        self.title = title
        self.frame = frame
        self.spaceIDs = spaceIDs
        self.spaceIndexes = spaceIndexes
        self.isOnAllSpaces = isOnAllSpaces
        self.displayID = displayID
        self.isMinimized = isMinimized
        self.isFullscreen = isFullscreen
        self.isBackgroundTab = isBackgroundTab
        self.lastFocusOrder = lastFocusOrder
        self.creationOrder = creationOrder
        self.zIndex = zIndex
    }

    public var windowID: WindowID? {
        if case .window(let id) = id { return id }
        return nil
    }

    public var isWindowlessApp: Bool { windowID == nil }

    /// The owning app is hidden (⌘H).
    public var isHidden: Bool { app.isHidden }

    /// The window title, or the app name when the window has no title.
    public var displayTitle: String {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? app.name : trimmed
    }
}

/// A connected display.
public struct ScreenInfo: Hashable, Sendable {
    public var id: DisplayID
    /// Full display frame, global Quartz coordinates.
    public var frame: CGRect
    /// The frame minus menu bar and Dock, global Quartz coordinates.
    public var visibleFrame: CGRect
    /// Backing scale factor (2 on Retina).
    public var scale: CGFloat
    /// The display showing the active menu bar.
    public var hasMenuBar: Bool

    public init(id: DisplayID, frame: CGRect, visibleFrame: CGRect, scale: CGFloat = 2, hasMenuBar: Bool = false) {
        self.id = id
        self.frame = frame
        self.visibleFrame = visibleFrame
        self.scale = scale
        self.hasMenuBar = hasMenuBar
    }
}

/// A Mission Control Space.
public struct SpaceInfo: Hashable, Sendable {
    public var id: SpaceID
    /// 1-based Mission Control order across all displays (display order, then Space order).
    public var index: Int
    public var displayID: DisplayID
    /// The current Space of its display.
    public var isVisible: Bool
    /// A fullscreen app's Space.
    public var isFullscreen: Bool

    public init(id: SpaceID, index: Int, displayID: DisplayID, isVisible: Bool, isFullscreen: Bool = false) {
        self.id = id
        self.index = index
        self.displayID = displayID
        self.isVisible = isVisible
        self.isFullscreen = isFullscreen
    }
}

/// Everything the switcher needs to know about the desktop at one moment.
public struct WindowSnapshot: Equatable, Sendable {
    /// Every known window plus one entry per windowless regular app; unordered, unfiltered.
    /// Never contains Soprano Tab's own windows.
    public var windows: [WindowInfo]
    public var screens: [ScreenInfo]
    public var spaces: [SpaceInfo]
    /// Mouse location, global Quartz coordinates.
    public var mouseLocation: CGPoint
    /// The frontmost app's pid.
    public var frontmostPID: pid_t?
    /// The frontmost app's focused window.
    public var focusedWindowID: WindowID?

    public init(
        windows: [WindowInfo] = [],
        screens: [ScreenInfo] = [],
        spaces: [SpaceInfo] = [],
        mouseLocation: CGPoint = .zero,
        frontmostPID: pid_t? = nil,
        focusedWindowID: WindowID? = nil
    ) {
        self.windows = windows
        self.screens = screens
        self.spaces = spaces
        self.mouseLocation = mouseLocation
        self.frontmostPID = frontmostPID
        self.focusedWindowID = focusedWindowID
    }

    public static let empty = WindowSnapshot()

    public var visibleSpaceIDs: Set<SpaceID> {
        Set(spaces.filter(\.isVisible).map(\.id))
    }

    public func screen(withID id: DisplayID) -> ScreenInfo? {
        screens.first { $0.id == id }
    }

    /// The screen containing `point`, if any.
    public func screen(containing point: CGPoint) -> ScreenInfo? {
        screens.first { $0.frame.contains(point) }
    }
}
