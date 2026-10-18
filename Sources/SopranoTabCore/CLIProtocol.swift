import CoreGraphics
import Foundation

// Messages between `SopranoTab <command>` and the running app, JSON over the
// CFMessagePort "<bundle id>.cli" (CLIServer / CLIClient in the app target).

public enum CLIRequest: Codable, Equatable, Sendable {
    case list(detailed: Bool)
    case focus(windowID: WindowID)
    case focusLastFocusOrder(Int)
    /// 0-based shortcut index.
    case show(shortcut: Int)
    case hide
}

/// One window in `list` output. Brief lists carry `id` and `title` only; the detailed
/// fields match AltTab's `--detailed-list`.
public struct CLIWindow: Codable, Equatable, Sendable {
    public struct Point: Codable, Equatable, Sendable {
        public var x: Double
        public var y: Double

        public init(x: Double, y: Double) {
            self.x = x
            self.y = y
        }
    }

    public struct Size: Codable, Equatable, Sendable {
        public var width: Double
        public var height: Double

        public init(width: Double, height: Double) {
            self.width = width
            self.height = height
        }
    }

    public var id: WindowID
    public var title: String
    public var appName: String?
    public var appBundleId: String?
    public var spaceIndexes: [Int]?
    public var lastFocusOrder: Int?
    public var creationOrder: Int?
    public var isTabbed: Bool?
    public var isHidden: Bool?
    public var isFullscreen: Bool?
    public var isMinimized: Bool?
    public var isOnAllSpaces: Bool?
    public var position: Point?
    public var size: Size?

    public init(window: WindowInfo, detailed: Bool) {
        id = window.windowID ?? 0
        title = window.displayTitle
        guard detailed else { return }
        appName = window.app.name
        appBundleId = window.app.bundleID
        spaceIndexes = window.spaceIndexes
        lastFocusOrder = window.lastFocusOrder
        creationOrder = window.creationOrder
        isTabbed = window.isBackgroundTab
        isHidden = window.isHidden
        isFullscreen = window.isFullscreen
        isMinimized = window.isMinimized
        isOnAllSpaces = window.isOnAllSpaces
        position = Point(x: window.frame.minX, y: window.frame.minY)
        size = Size(width: window.frame.width, height: window.frame.height)
    }
}

public struct CLIResponse: Codable, Equatable, Sendable {
    public var ok: Bool
    public var error: String?
    public var windows: [CLIWindow]?

    public init(ok: Bool, error: String? = nil, windows: [CLIWindow]? = nil) {
        self.ok = ok
        self.error = error
        self.windows = windows
    }
}
