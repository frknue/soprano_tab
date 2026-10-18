import AppKit
import SopranoTabCore

// Seams between the live macOS layer (System/), the switcher (Switcher/) and the
// fixtures (Fixtures/). The switcher only ever talks to these protocols, so the
// snapshot harness and the tests run it on fixtures without any permission.

/// The window catalog.
@MainActor
protocol WindowSource: AnyObject {
    /// The latest catalog. Cheap: no IPC, no AX calls.
    var snapshot: WindowSnapshot { get }
    /// Called on the main actor after the catalog changed (coalesced, at most every ~50 ms).
    var onChange: (() -> Void)? { get set }
    /// Begins observing apps, windows, Spaces and screens.
    func start()
    func stop()
    /// Re-reads the volatile state (frames, Spaces, minimized/fullscreen, z-order, mouse,
    /// focus) for every known window now; the switcher calls it right before it opens.
    /// Stays under ~30 ms for 50 windows; anything slower is refreshed asynchronously
    /// and reported through `onChange`.
    func refresh()
}

/// Window images.
@MainActor
protocol ThumbnailProvider: AnyObject {
    /// Whether captures can succeed (Screen Recording granted, or fixtures).
    var canCapture: Bool { get }
    /// The last captured image of a window, if any.
    func cachedThumbnail(for windowID: WindowID) -> CGImage?
    /// Captures fresh images whose longest side is at most `maxPixelSize` pixels, off the
    /// main thread, and calls `update` on the main actor as each one arrives. Windows that
    /// cannot be captured (minimized, closed) keep their cached image and get no callback.
    func requestThumbnails(
        for windows: [WindowInfo],
        maxPixelSize: CGFloat,
        update: @escaping @MainActor (WindowID, CGImage) -> Void
    )
    /// Drops cached images of windows that no longer exist.
    func prune(keeping windowIDs: Set<WindowID>)
}

/// Window and app actions.
@MainActor
protocol WindowActing: AnyObject {
    /// Brings the window forward, switching Space, unhiding its app and unminimizing it
    /// as needed. For a windowless app: activates it, reopening it so it creates a window.
    func focus(_ item: WindowInfo)
    func close(_ item: WindowInfo)
    func toggleMinimize(_ item: WindowInfo)
    func toggleFullscreen(_ item: WindowInfo)
    func quitApp(_ item: WindowInfo)
    func toggleHideApp(_ item: WindowInfo)
    /// Warps the mouse to the center of the window (cursor follows focus).
    func moveCursor(toCenterOf item: WindowInfo)
}

/// App icons.
@MainActor
protocol AppIconProvider: AnyObject {
    func icon(for app: AppInfo) -> NSImage
}

/// The system-wide keyboard tap.
@MainActor
protocol KeyboardEventTap: AnyObject {
    var isRunning: Bool { get }
    /// Starts intercepting keyDown, keyUp and flagsChanged for every app. `handler` runs on
    /// the main thread and returns true to swallow the event. Throws when Accessibility
    /// access is missing or the tap cannot be created.
    func start(handler: @escaping @MainActor (KeyEvent) -> Bool) throws
    func stop()
}

/// The system-wide trackpad tap.
@MainActor
protocol GestureEventTap: AnyObject {
    var isRunning: Bool { get }
    /// Starts listening to trackpad gesture events; `handler` gets every touch of each
    /// event on the main thread. Listen-only: events are never swallowed.
    func start(handler: @escaping @MainActor ([TouchSample]) -> Void) throws
    func stop()
}

enum EventTapError: Error, Equatable {
    case accessibilityDenied
    case tapCreationFailed
}
