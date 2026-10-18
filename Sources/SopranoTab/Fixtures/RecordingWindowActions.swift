import CoreGraphics
import SopranoTabCore

/// One window action, as the fixtures saw it.
enum WindowActionRecord: Equatable {
    case focus(ItemID), close(ItemID), toggleMinimize(ItemID), toggleFullscreen(ItemID)
    case quitApp(pid_t), toggleHideApp(pid_t), moveCursor(ItemID)

    /// The snapshot report's spelling: "focus window 1003", "focus app 509", "quitApp 502".
    var reportText: String {
        switch self {
        case .focus(let id): "focus \(Self.text(id))"
        case .close(let id): "close \(Self.text(id))"
        case .toggleMinimize(let id): "toggleMinimize \(Self.text(id))"
        case .toggleFullscreen(let id): "toggleFullscreen \(Self.text(id))"
        case .quitApp(let pid): "quitApp \(pid)"
        case .toggleHideApp(let pid): "toggleHideApp \(pid)"
        case .moveCursor(let id): "moveCursor \(Self.text(id))"
        }
    }

    private static func text(_ id: ItemID) -> String {
        switch id {
        case .window(let windowID): "window \(windowID)"
        case .windowlessApp(let pid): "app \(pid)"
        }
    }
}

/// Window actions that log every call and apply its effect to the fixture catalog, so
/// the switcher sees the same catalog changes it would see live.
@MainActor
final class RecordingWindowActions: WindowActing {
    private let source: FixtureWindowSource
    private(set) var log: [WindowActionRecord] = []

    init(source: FixtureWindowSource) {
        self.source = source
    }

    /// Ranks the item first (windows before windowless apps, which always rank after
    /// every window) and makes its app frontmost.
    func focus(_ item: WindowInfo) {
        log.append(.focus(item.id))
        source.mutate { snapshot in
            guard snapshot.windows.contains(where: { $0.id == item.id }) else { return }
            let ranked = snapshot.windows.indices.sorted { lhs, rhs in
                let left = snapshot.windows[lhs]
                let right = snapshot.windows[rhs]
                if left.isWindowlessApp != right.isWindowlessApp { return !left.isWindowlessApp }
                if (left.id == item.id) != (right.id == item.id) { return left.id == item.id }
                return left.lastFocusOrder < right.lastFocusOrder
            }
            for (order, index) in ranked.enumerated() {
                snapshot.windows[index].lastFocusOrder = order
            }
            for index in snapshot.windows.indices {
                snapshot.windows[index].app.isActive = snapshot.windows[index].app.pid == item.app.pid
            }
            snapshot.frontmostPID = item.app.pid
            snapshot.focusedWindowID = item.windowID
        }
    }

    func close(_ item: WindowInfo) {
        log.append(.close(item.id))
        source.mutate { snapshot in
            snapshot.windows.removeAll { $0.id == item.id }
            if let windowID = item.windowID, snapshot.focusedWindowID == windowID {
                snapshot.focusedWindowID = nil
            }
        }
    }

    func toggleMinimize(_ item: WindowInfo) {
        log.append(.toggleMinimize(item.id))
        guard !item.isWindowlessApp else { return }
        source.mutate { snapshot in
            guard let index = snapshot.windows.firstIndex(where: { $0.id == item.id }) else { return }
            snapshot.windows[index].isMinimized.toggle()
        }
    }

    func toggleFullscreen(_ item: WindowInfo) {
        log.append(.toggleFullscreen(item.id))
        guard !item.isWindowlessApp else { return }
        source.mutate { snapshot in
            guard let index = snapshot.windows.firstIndex(where: { $0.id == item.id }) else { return }
            snapshot.windows[index].isFullscreen.toggle()
        }
    }

    /// Removes every item of the app, windows and windowless entry alike.
    func quitApp(_ item: WindowInfo) {
        let pid = item.app.pid
        log.append(.quitApp(pid))
        source.mutate { snapshot in
            let focused = snapshot.focusedWindowID
            let focusedBelongsToApp = snapshot.windows.contains {
                $0.app.pid == pid && $0.windowID != nil && $0.windowID == focused
            }
            snapshot.windows.removeAll { $0.app.pid == pid }
            if focusedBelongsToApp { snapshot.focusedWindowID = nil }
            if snapshot.frontmostPID == pid {
                snapshot.frontmostPID = nil
                snapshot.focusedWindowID = nil
            }
        }
    }

    /// Flips the app's hidden state on all its items, from the state of `item`'s app.
    func toggleHideApp(_ item: WindowInfo) {
        let pid = item.app.pid
        log.append(.toggleHideApp(pid))
        source.mutate { snapshot in
            let current = snapshot.windows.first { $0.app.pid == pid }?.app.isHidden ?? item.app.isHidden
            for index in snapshot.windows.indices where snapshot.windows[index].app.pid == pid {
                snapshot.windows[index].app.isHidden = !current
            }
        }
    }

    func moveCursor(toCenterOf item: WindowInfo) {
        log.append(.moveCursor(item.id))
        guard !item.isWindowlessApp else { return }
        source.mutate { snapshot in
            snapshot.mouseLocation = CGPoint(x: item.frame.midX, y: item.frame.midY)
        }
    }
}
