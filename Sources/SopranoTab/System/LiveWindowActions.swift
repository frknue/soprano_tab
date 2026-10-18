import AppKit
import ApplicationServices
import OSLog
import SopranoTabCore

private let actionsLog = Logger(subsystem: "com.soprano.tab", category: "actions")

/// Window and app actions on the live desktop, through Accessibility and SkyLight.
@MainActor
final class LiveWindowActions: WindowActing {
    /// `AXFullScreen` has no public SDK constant.
    private static let fullScreenAttribute = "AXFullScreen"
    /// How long macOS needs to animate a window out of fullscreen before it accepts
    /// close and minimize.
    private static let fullscreenExitDelay: Duration = .milliseconds(750)
    private static let finderBundleID = "com.apple.finder"

    private let source: LiveWindowSource

    init(source: LiveWindowSource) {
        self.source = source
    }

    // MARK: - Focus

    func focus(_ item: WindowInfo) {
        let pid = item.app.pid
        let runningApp = NSRunningApplication(processIdentifier: pid)
        guard let windowID = item.windowID else {
            focusWindowlessApp(item.app, runningApp: runningApp)
            return
        }
        if runningApp?.isHidden == true { runningApp?.unhide() }
        guard let window = source.axWindow(for: windowID) else {
            runningApp?.activate(options: [])
            return
        }
        if AX.bool(window, kAXMinimizedAttribute) == true {
            AX.set(window, kAXMinimizedAttribute, NSNumber(value: false))
        }
        // The SkyLight front-process call switches to the window's Space; without the
        // symbol, plain activation is the best the public API offers.
        if !PrivateAPIs.setFrontProcess(pid: pid, windowID: windowID) {
            runningApp?.activate(options: [])
        }
        PrivateAPIs.makeKeyWindow(pid: pid, windowID: windowID)
        AX.perform(window, kAXRaiseAction)
    }

    /// Activates an app the catalog lists without windows. An app that really has no
    /// window is opened again, which sends it the reopen event (Finder, Notes and most
    /// document apps answer it with a new window).
    private func focusWindowlessApp(_ app: AppInfo, runningApp: NSRunningApplication?) {
        if runningApp?.isHidden == true { runningApp?.unhide() }
        runningApp?.activate(options: [])
        let hasWindows = source.snapshot.windows.contains { $0.app.pid == app.pid && !$0.isWindowlessApp }
        guard !hasWindows else { return }
        guard let bundleURL = runningApp?.bundleURL ?? app.bundlePath.map({ URL(fileURLWithPath: $0) }) else {
            return
        }
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true
        NSWorkspace.shared.openApplication(at: bundleURL, configuration: configuration) { _, error in
            if let error {
                actionsLog.error("Reopening \(bundleURL.path, privacy: .public) failed: \(error.localizedDescription, privacy: .public)")
            }
        }
    }

    // MARK: - Window actions

    func close(_ item: WindowInfo) {
        guard let windowID = item.windowID, let window = source.axWindow(for: windowID) else { return }
        afterLeavingFullscreen(window, isFullscreen: item.isFullscreen, windowID: windowID) { window in
            guard let button = AX.element(window, kAXCloseButtonAttribute) else { return }
            AX.perform(button, kAXPressAction)
        }
    }

    func toggleMinimize(_ item: WindowInfo) {
        guard let windowID = item.windowID, let window = source.axWindow(for: windowID) else { return }
        let isMinimized = AX.bool(window, kAXMinimizedAttribute) ?? item.isMinimized
        if isMinimized {
            AX.set(window, kAXMinimizedAttribute, NSNumber(value: false))
            return
        }
        afterLeavingFullscreen(window, isFullscreen: item.isFullscreen, windowID: windowID) { window in
            AX.set(window, kAXMinimizedAttribute, NSNumber(value: true))
        }
    }

    func toggleFullscreen(_ item: WindowInfo) {
        guard let windowID = item.windowID, let window = source.axWindow(for: windowID) else { return }
        let isFullscreen = AX.bool(window, Self.fullScreenAttribute) ?? item.isFullscreen
        AX.set(window, Self.fullScreenAttribute, NSNumber(value: !isFullscreen))
    }

    /// Runs `action` on the window now, or — for a fullscreen window — leaves fullscreen
    /// first and runs it on a freshly resolved element once the exit animation is over.
    private func afterLeavingFullscreen(
        _ window: AXUIElement,
        isFullscreen: Bool,
        windowID: WindowID,
        action: @escaping @MainActor (AXUIElement) -> Void
    ) {
        guard AX.bool(window, Self.fullScreenAttribute) ?? isFullscreen else {
            action(window)
            return
        }
        AX.set(window, Self.fullScreenAttribute, NSNumber(value: false))
        Task { @MainActor [weak self] in
            try? await Task.sleep(for: Self.fullscreenExitDelay)
            guard let window = self?.source.axWindow(for: windowID) else { return }
            action(window)
        }
    }

    // MARK: - App actions

    func quitApp(_ item: WindowInfo) {
        if item.app.bundleID == Self.finderBundleID && !Self.finderCanQuit { return }
        NSRunningApplication(processIdentifier: item.app.pid)?.terminate()
    }

    /// Finder offers Quit only after `defaults write com.apple.finder QuitMenuItem -bool true`.
    private static var finderCanQuit: Bool {
        UserDefaults(suiteName: finderBundleID)?.bool(forKey: "QuitMenuItem") == true
    }

    func toggleHideApp(_ item: WindowInfo) {
        guard let runningApp = NSRunningApplication(processIdentifier: item.app.pid) else { return }
        if runningApp.isHidden {
            runningApp.unhide()
        } else {
            runningApp.hide()
        }
    }

    // MARK: - Cursor

    func moveCursor(toCenterOf item: WindowInfo) {
        guard !item.frame.isEmpty else { return }
        CGWarpMouseCursorPosition(CGPoint(x: item.frame.midX, y: item.frame.midY))
        // Warping detaches the cursor from the mouse for a moment; reattach at once.
        CGAssociateMouseAndMouseCursorPosition(1)
    }
}
