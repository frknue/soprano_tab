import AppKit
import OSLog
import SopranoTabCore

private let appLog = Logger(subsystem: "com.soprano.tab", category: "app")

/// The composition root: settings → theme → catalog → switcher → keyboard and gesture
/// taps → menu bar → login item → CLI server.
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    /// Set once the first launch asked macOS for both permissions.
    private static let didRequestPermissionsKey = "didRequestPermissions"

    private var source: LiveWindowSource?
    private var controller: SwitcherController?
    private var hotkeys: HotkeyMonitor?
    private var gestures: GestureMonitor?
    private var accessibilityPoll: Timer?
    private var menuBar: MenuBarController?
    private var cliServer: CLIServer?
    private var permissionsWindow: PermissionsWindowController?
    private var appliedStartAtLogin: Bool?

    func applicationWillFinishLaunching(_ notification: Notification) {
        NSApp.appearance = NSAppearance(named: .darkAqua)
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        guard !Self.anotherInstanceIsRunning() else {
            NSApp.terminate(nil)
            return
        }
        _ = RetroFont.registerBundledFont()

        let settings = SettingsCenter.shared
        settings.start()
        ThemeCenter.shared.start()

        let source = LiveWindowSource()
        source.start()
        let thumbnails = LiveThumbnailProvider()
        let actions = LiveWindowActions(source: source)
        let icons = LiveAppIconProvider()
        let window = SwitcherWindow()
        let controller = SwitcherController(
            source: source,
            thumbnails: thumbnails,
            actions: actions,
            icons: icons,
            presenter: window,
            environment: Self.environment()
        )
        self.source = source
        self.controller = controller

        hotkeys = HotkeyMonitor()
        startHotkeys()
        gestures = GestureMonitor()
        updateGestureTap()

        menuBar = MenuBarController(controller: controller) { [weak self] in
            self?.showPermissions()
        }
        applyLoginItem()

        let cliServer = CLIServer(controller: controller, source: source, actions: actions)
        cliServer.start()
        self.cliServer = cliServer

        settings.addObserver(self) { [weak self] in
            self?.settingsDidChange()
        }

        onboardIfNeeded()
    }

    func applicationWillTerminate(_ notification: Notification) {
        cliServer?.stop()
        accessibilityPoll?.invalidate()
        hotkeys?.stop()
        gestures?.stop()
        source?.stop()
        SettingsCenter.shared.stop()
    }

    /// Reopening from Spotlight or Finder: the permissions window while something is
    /// missing, else settings.json.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if Permissions.status.allGranted {
            SettingsCenter.shared.openInEditor()
        } else {
            showPermissions()
        }
        return false
    }

    // MARK: - Composition

    private static func environment() -> SwitcherEnvironment {
        SwitcherEnvironment(
            settings: { SettingsCenter.shared.settings },
            theme: { ThemeCenter.shared.theme(forOverride: $0) },
            schedule: { milliseconds, work in
                let scheduled = ScheduledWork(work)
                DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(milliseconds)) {
                    MainActor.assumeIsolated {
                        scheduled.run()
                    }
                }
                // Controllers cancel on the main thread.
                return { MainActor.assumeIsolated { scheduled.cancel() } }
            },
            haptic: {
                NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .now)
            }
        )
    }

    private static func anotherInstanceIsRunning() -> Bool {
        guard let bundleID = Bundle.main.bundleIdentifier else { return false }
        let ownPID = ProcessInfo.processInfo.processIdentifier
        return NSRunningApplication.runningApplications(withBundleIdentifier: bundleID)
            .contains { $0.processIdentifier != ownPID && !$0.isTerminated }
    }

    // MARK: - Settings

    private func settingsDidChange() {
        controller?.settingsDidChange()
        menuBar?.apply()
        applyLoginItem()
        updateGestureTap()
    }

    private func applyLoginItem() {
        let enabled = SettingsCenter.shared.settings.app.startAtLogin
        guard enabled != appliedStartAtLogin else { return }
        appliedStartAtLogin = enabled
        LoginItem.sync(enabled: enabled)
    }

    // MARK: - Event taps

    /// Starts the keyboard tap now, or polls every second until Accessibility is granted.
    private func startHotkeys() {
        guard let controller, let hotkeys, !hotkeys.isRunning else { return }
        if Permissions.isAccessibilityTrusted {
            do {
                try hotkeys.start { [weak controller] event in
                    controller?.handleKeyEvent(event) ?? false
                }
                accessibilityPoll?.invalidate()
                accessibilityPoll = nil
                // A gesture tap that failed for want of Accessibility can start now too.
                updateGestureTap()
                permissionsWindow?.refresh()
                return
            } catch {
                appLog.error("Could not start the keyboard tap: \(String(describing: error), privacy: .public)")
            }
        }
        guard accessibilityPoll == nil else { return }
        accessibilityPoll = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.startHotkeys()
            }
        }
    }

    /// Runs the gesture tap while `gesture.kind != .disabled`.
    private func updateGestureTap() {
        guard let controller, let gestures else { return }
        let wanted = SettingsCenter.shared.settings.gesture.kind != .disabled
        if wanted, !gestures.isRunning {
            do {
                try gestures.start { [weak controller] touches in
                    controller?.handleTouches(touches)
                }
            } catch {
                appLog.error("Could not start the gesture tap: \(String(describing: error), privacy: .public)")
            }
        } else if !wanted, gestures.isRunning {
            gestures.stop()
        }
    }

    // MARK: - Permissions

    /// The first launch asks macOS for both permissions once and opens the permissions
    /// window when either is missing; later launches open it while Accessibility (required)
    /// is missing.
    private func onboardIfNeeded() {
        let status = Permissions.status
        let defaults = UserDefaults.standard
        let isFirstLaunch = !defaults.bool(forKey: Self.didRequestPermissionsKey)
        if isFirstLaunch {
            defaults.set(true, forKey: Self.didRequestPermissionsKey)
            guard !status.allGranted else { return }
            if !status.accessibility { Permissions.requestAccessibility() }
            if !status.screenRecording { Permissions.requestScreenRecording() }
            showPermissions()
        } else if !status.accessibility {
            showPermissions()
        }
    }

    private func showPermissions() {
        let window = permissionsWindow ?? PermissionsWindowController(status: { Permissions.status })
        permissionsWindow = window
        NSApp.activate()
        window.showWindow(nil)
    }
}

/// One `SwitcherEnvironment.schedule` job; cancelling drops the work before it runs.
@MainActor
private final class ScheduledWork {
    private var work: (@MainActor () -> Void)?

    init(_ work: @escaping @MainActor () -> Void) {
        self.work = work
    }

    func run() {
        let work = self.work
        self.work = nil
        work?()
    }

    func cancel() {
        work = nil
    }
}
