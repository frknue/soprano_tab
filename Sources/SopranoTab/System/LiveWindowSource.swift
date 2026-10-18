import AppKit
import ApplicationServices
import SopranoTabCore

/// The live window catalog.
///
/// Threading: all state lives on the main actor. Every Accessibility read and observer
/// registration (IPC into the target app) runs on that app's serial background queue with
/// a 0.25 s messaging timeout, so a hung app delays only its own queue, never the main
/// thread or other apps. Results come back to the main actor and are merged there; the
/// snapshot is rebuilt from WindowServer data (CGWindowList, SkyLight Spaces, NSScreen,
/// NSWorkspace; no AX) and published through `onChange` at most every ~50 ms. The
/// AXObserver run-loop sources sit on the main run loop, so the C callback runs on the
/// main thread and only maps the element to a known window (`CFEqual`, no IPC) and queues
/// reads.
///
/// Observed AX notifications. App element: window created, focused window changed, main
/// window changed, application hidden, application shown. Each window element: UI element
/// destroyed, title changed, miniaturized, deminiaturized, moved, resized.
@MainActor
final class LiveWindowSource: WindowSource {
    private(set) var snapshot: WindowSnapshot = .empty
    var onChange: (() -> Void)?

    private static let publishInterval: TimeInterval = 0.05
    private static let subscribeAttempts = 10
    private static let subscribeRetryDelay: TimeInterval = 0.5

    private let ownPID = ProcessInfo.processInfo.processIdentifier
    private var isRunning = false
    private var apps: [pid_t: AppRecord] = [:]
    private var nextAppSerial = 0
    private var nextLaunchOrder = 0
    private var creationOrders: [WindowID: Int] = [:]
    private var nextCreationOrder = 0
    private var focusOrder = FocusOrder()
    /// Bumped on every Space change; remote-token probing runs once per app per value.
    private var spaceGeneration = 0
    private var windowServer = WindowServerState()
    private var notificationObservers: [(center: NotificationCenter, token: NSObjectProtocol)] = []
    private var publishScheduled = false
    private var lastPublishTime: TimeInterval = 0

    init() {}

    // MARK: - WindowSource

    func start() {
        guard !isRunning else { return }
        isRunning = true
        observeNotifications()
        captureWindowServer()
        seedOrders()
        syncRunningApps()
        publish(notify: true)
    }

    func stop() {
        guard isRunning else { return }
        isRunning = false
        for observer in notificationObservers {
            observer.center.removeObserver(observer.token)
        }
        notificationObservers = []
        for app in apps.values {
            app.detach()
        }
        apps = [:]
        publishScheduled = false
    }

    func refresh() {
        guard isRunning else { return }
        syncRunningApps()
        for app in apps.values {
            ensureSubscribed(app)
            app.needsFullRead = true
            scheduleRead(app)
        }
        publish(notify: false)
    }

    // MARK: - Elements for window actions

    /// The AX element of a known window; nil when unknown or gone.
    func axWindow(for windowID: WindowID) -> AXUIElement? {
        for app in apps.values {
            if let window = app.windows[windowID] { return window.element }
        }
        return nil
    }

    func axApplication(for pid: pid_t) -> AXUIElement {
        if let app = apps[pid] { return app.element }
        let element = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(element, AXReader.messagingTimeout)
        return element
    }

    // MARK: - Apps

    private func syncRunningApps() {
        let running = NSWorkspace.shared.runningApplications.filter {
            $0.processIdentifier > 0 && $0.processIdentifier != ownPID
                && !$0.isTerminated && $0.activationPolicy != .prohibited
        }
        let pids = Set(running.map(\.processIdentifier))
        for pid in Array(apps.keys) where !pids.contains(pid) {
            removeApp(pid)
        }
        let added = running
            .filter { apps[$0.processIdentifier] == nil }
            .sorted { ($0.launchDate ?? .distantPast) < ($1.launchDate ?? .distantPast) }
        for application in added {
            addApp(application)
        }
    }

    private func addApp(_ application: NSRunningApplication) {
        nextAppSerial += 1
        nextLaunchOrder += 1
        let app = AppRecord(
            serial: nextAppSerial,
            running: application,
            launchOrder: nextLaunchOrder,
            source: self
        )
        apps[app.pid] = app
        ensureSubscribed(app)
        app.needsFullRead = true
        scheduleRead(app)
    }

    private func removeApp(_ pid: pid_t) {
        guard let app = apps.removeValue(forKey: pid) else { return }
        app.detach()
        for windowID in app.windows.keys {
            focusOrder.remove(windowID)
        }
        focusOrder.removeApp(pid)
    }

    /// Creates the app's observer and registers its app-level notifications, unless that
    /// already succeeded or is underway. Retried by `refresh()` after a failure (no
    /// Accessibility access yet, app gone unresponsive).
    private func ensureSubscribed(_ app: AppRecord) {
        guard app.subscription == .idle || app.subscription == .failed else { return }
        app.attachObserver()
        guard app.observer != nil else {
            app.subscription = .failed
            return
        }
        subscribe(app, attempt: 0)
    }

    private func subscribe(_ app: AppRecord, attempt: Int) {
        guard let observer = app.observer else {
            app.subscription = .failed
            return
        }
        app.subscription = .pending
        let job = SubscribeJob(app: app.element, observer: observer, refcon: app.refcon, context: app.context)
        let pid = app.pid
        let serial = app.serial
        app.queue.async {
            let status = AXReader.subscribe(job)
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    self.subscriptionFinished(pid: pid, serial: serial, status: status, attempt: attempt)
                }
            }
        }
    }

    private func subscriptionFinished(pid: pid_t, serial: Int, status: AXError, attempt: Int) {
        guard isRunning, let app = apps[pid], app.serial == serial else { return }
        switch status {
        case .success:
            app.subscription = .subscribed
            // Windows of a freshly launched app become readable once it answers AX.
            app.needsFullRead = true
            scheduleRead(app)
        case .cannotComplete where attempt + 1 < Self.subscribeAttempts:
            // Not answering yet (still launching): retry shortly.
            DispatchQueue.main.asyncAfter(deadline: .now() + Self.subscribeRetryDelay) {
                MainActor.assumeIsolated {
                    guard self.isRunning, let app = self.apps[pid], app.serial == serial else { return }
                    self.subscribe(app, attempt: attempt + 1)
                }
            }
        default:
            app.subscription = .failed
        }
    }

    // MARK: - AX reads

    /// Starts the app's pending read unless one is in flight; the completion re-checks, so
    /// requests arriving meanwhile coalesce into one follow-up read.
    private func scheduleRead(_ app: AppRecord) {
        guard isRunning, !app.readInFlight, app.needsFullRead || !app.dirtyWindowIDs.isEmpty else { return }
        let full = app.needsFullRead
        let job = ReadJob(
            pid: app.pid,
            serial: app.serial,
            generation: spaceGeneration,
            app: app.element,
            observer: app.observer,
            refcon: app.refcon,
            context: app.context,
            full: full,
            dirty: full ? [] : app.dirtyWindowIDs.compactMap { app.windows[$0] },
            registeredWindowIDs: app.registeredWindowIDs,
            probeCandidates: full && app.probedGeneration != spaceGeneration ? probeCandidates(for: app) : []
        )
        app.needsFullRead = false
        app.dirtyWindowIDs = []
        app.readInFlight = true
        app.queue.async {
            let result = AXReader.read(job)
            DispatchQueue.main.async {
                MainActor.assumeIsolated { self.apply(result) }
            }
        }
    }

    private func apply(_ result: ReadResult) {
        guard isRunning, let app = apps[result.pid], app.serial == result.serial else { return }
        app.readInFlight = false
        app.registeredWindowIDs.formUnion(result.registeredWindowIDs)
        if result.full {
            if let windows = result.windows {
                mergeWindowList(windows, into: app)
                if result.probed { app.probedGeneration = result.generation }
            }
            app.hasRead = true
            if result.focusKnown {
                app.focusedWindowID = result.focusedWindowID
                // The frontmost app's focused window is by definition the latest focus.
                if let windowID = result.focusedWindowID, frontmostPID == app.pid {
                    focusOrder.focus(windowID)
                }
            }
        } else {
            for window in result.updated where app.windows[window.id] != nil {
                app.windows[window.id] = window
            }
            for windowID in result.goneWindowIDs {
                forgetWindow(windowID, of: app)
            }
        }
        scheduleRead(app)
        schedulePublish()
    }

    /// Replaces the app's windows with a full read. A known window AX no longer lists is
    /// kept while it sits on a Space that is not visible (AX omits other Spaces' windows)
    /// or is minimized there; anything else it omitted is gone (closed or ordered out).
    private func mergeWindowList(_ windows: [AXWindowRecord], into app: AppRecord) {
        var next: [WindowID: AXWindowRecord] = [:]
        for window in windows {
            next[window.id] = window
            _ = creationOrder(of: window.id)
        }
        let visibleSpaceIDs = Set(windowServer.spaces.filter(\.isVisible).map(\.id))
        for (windowID, window) in app.windows where next[windowID] == nil {
            if keepsOmittedWindow(window, pid: app.pid, visibleSpaceIDs: visibleSpaceIDs) {
                next[windowID] = window
            } else {
                focusOrder.remove(windowID)
                app.registeredWindowIDs.remove(windowID)
            }
        }
        app.windows = next
    }

    private func keepsOmittedWindow(_ window: AXWindowRecord, pid: pid_t, visibleSpaceIDs: Set<SpaceID>) -> Bool {
        guard let cg = windowServer.windows[window.id], cg.pid == pid, cg.layer == 0 else { return false }
        if window.isMinimized { return true }
        let spaces = PrivateAPIs.spaces(forWindow: window.id)
        return !spaces.isEmpty && spaces.allSatisfy { !visibleSpaceIDs.contains($0) }
    }

    /// Layer-0 windows of the app that sit only on Spaces that are not visible and that the
    /// catalog has no AX element for: what a remote-token probe can recover.
    private func probeCandidates(for app: AppRecord) -> Set<WindowID> {
        let visibleSpaceIDs = Set(windowServer.spaces.filter(\.isVisible).map(\.id))
        var candidates = Set<WindowID>()
        for window in windowServer.windows.values
        where window.pid == app.pid && window.layer == 0 && app.windows[window.id] == nil && window.hasListableSize {
            let spaces = PrivateAPIs.spaces(forWindow: window.id)
            if !spaces.isEmpty, spaces.allSatisfy({ !visibleSpaceIDs.contains($0) }) {
                candidates.insert(window.id)
            }
        }
        return candidates
    }

    private func forgetWindow(_ windowID: WindowID, of app: AppRecord) {
        app.windows[windowID] = nil
        app.registeredWindowIDs.remove(windowID)
        focusOrder.remove(windowID)
    }

    // MARK: - Notifications

    private func observeNotifications() {
        let workspace = NSWorkspace.shared.notificationCenter
        let names: [Notification.Name] = [
            NSWorkspace.didLaunchApplicationNotification,
            NSWorkspace.didTerminateApplicationNotification,
            NSWorkspace.didActivateApplicationNotification,
            NSWorkspace.didHideApplicationNotification,
            NSWorkspace.didUnhideApplicationNotification,
            NSWorkspace.activeSpaceDidChangeNotification,
        ]
        for name in names {
            let token = workspace.addObserver(forName: name, object: nil, queue: .main) { [weak self] note in
                let pid = (note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication)?.processIdentifier
                MainActor.assumeIsolated {
                    self?.handleWorkspaceNotification(name, pid: pid)
                }
            }
            notificationObservers.append((center: workspace, token: token))
        }
        let screens = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.spacesDidChange()
            }
        }
        notificationObservers.append((center: NotificationCenter.default, token: screens))
    }

    private func handleWorkspaceNotification(_ name: Notification.Name, pid: pid_t?) {
        guard isRunning else { return }
        switch name {
        case NSWorkspace.didLaunchApplicationNotification:
            syncRunningApps()
        case NSWorkspace.didTerminateApplicationNotification:
            if let pid { removeApp(pid) }
        case NSWorkspace.didActivateApplicationNotification:
            guard let pid, pid != ownPID else { break }
            if apps[pid] == nil { syncRunningApps() }
            focusOrder.activate(pid)
            if let app = apps[pid] {
                if let windowID = app.focusedWindowID { focusOrder.focus(windowID) }
                // Confirms the focused window (it may have changed while inactive).
                app.needsFullRead = true
                scheduleRead(app)
            }
        case NSWorkspace.activeSpaceDidChangeNotification:
            spacesDidChange()
            return
        default:
            break
        }
        schedulePublish()
    }

    /// A Space or display change: AX now lists other windows, and windows on newly hidden
    /// Spaces may need a remote-token probe.
    private func spacesDidChange() {
        guard isRunning else { return }
        spaceGeneration += 1
        captureWindowServer()
        for app in apps.values {
            app.needsFullRead = true
            scheduleRead(app)
        }
        schedulePublish()
    }

    /// Called from the AXObserver callback on the main thread.
    fileprivate func handleAXNotification(_ name: String, element: AXUIElement, pid: pid_t) {
        guard isRunning, let app = apps[pid] else { return }
        let windowID = app.windowID(of: element)
        switch name {
        case kAXFocusedWindowChangedNotification, kAXMainWindowChangedNotification:
            if let windowID {
                app.focusedWindowID = windowID
                if frontmostPID == pid { focusOrder.focus(windowID) }
            } else {
                app.needsFullRead = true
            }
        case kAXUIElementDestroyedNotification:
            if let windowID { forgetWindow(windowID, of: app) }
        case kAXTitleChangedNotification, kAXWindowMiniaturizedNotification,
             kAXWindowDeminiaturizedNotification, kAXWindowResizedNotification:
            if let windowID {
                app.dirtyWindowIDs.insert(windowID)
            } else {
                app.needsFullRead = true
            }
        case kAXWindowMovedNotification, kAXApplicationHiddenNotification, kAXApplicationShownNotification:
            // Frames come from CGWindowList and hidden state from NSRunningApplication.
            break
        default:
            // kAXWindowCreatedNotification
            app.needsFullRead = true
        }
        scheduleRead(app)
        schedulePublish()
    }

    // MARK: - Publishing

    private var frontmostPID: pid_t? {
        NSWorkspace.shared.frontmostApplication?.processIdentifier
    }

    private func schedulePublish() {
        guard isRunning, !publishScheduled else { return }
        publishScheduled = true
        let delay = max(0, lastPublishTime + Self.publishInterval - ProcessInfo.processInfo.systemUptime)
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
            MainActor.assumeIsolated {
                guard self.publishScheduled else { return }
                self.publishScheduled = false
                guard self.isRunning else { return }
                self.publish(notify: true)
            }
        }
    }

    /// Rebuilds the snapshot from fresh WindowServer state; `onChange` fires when it changed
    /// and `notify` is set (`refresh()` returns the new snapshot directly instead).
    private func publish(notify: Bool) {
        captureWindowServer()
        lastPublishTime = ProcessInfo.processInfo.systemUptime
        let next = makeSnapshot()
        guard next != snapshot else { return }
        snapshot = next
        if notify { onChange?() }
    }

    private func creationOrder(of windowID: WindowID) -> Int {
        if let order = creationOrders[windowID] { return order }
        nextCreationOrder += 1
        creationOrders[windowID] = nextCreationOrder
        return nextCreationOrder
    }

    /// Initial creation order (ascending CGWindowID) and focus order (on-screen z-order,
    /// then the rest; apps: the frontmost, then by their frontmost on-screen window).
    private func seedOrders() {
        let layerZero = windowServer.order.filter { windowServer.windows[$0]?.layer == 0 }
        for windowID in layerZero.sorted() {
            _ = creationOrder(of: windowID)
        }
        var appOrder: [pid_t] = frontmostPID.map { [$0] } ?? []
        appOrder += windowServer.onScreen.compactMap { windowServer.windows[$0]?.pid }
        focusOrder = FocusOrder(
            zOrderedWindows: windowServer.onScreen,
            remainingWindows: layerZero,
            appsByRecency: appOrder.filter { $0 != ownPID }
        )
    }

    private func captureWindowServer() {
        var state = WindowServerState()
        for window in Self.windowList([.optionAll]) {
            state.windows[window.id] = window
            state.order.append(window.id)
        }
        state.onScreen = Self.windowList([.optionOnScreenOnly, .excludeDesktopElements])
            .filter { $0.layer == 0 }
            .map(\.id)
        let primaryHeight = NSScreen.screens.first?.frame.height ?? 0
        let uuids = Self.displayUUIDs()
        var displayIDsByUUID: [String: DisplayID] = [:]
        for (displayID, uuid) in uuids { displayIDsByUUID[uuid] = displayID }
        state.screens = Self.screens(primaryHeight: primaryHeight, uuids: uuids)
        state.spaces = SpaceCatalog.spaces(
            from: PrivateAPIs.managedDisplaySpaces(),
            displayIDForUUID: { displayIDsByUUID[$0.uppercased()] },
            mainDisplayID: CGMainDisplayID()
        )
        state.mouseLocation = Geometry.quartzPoint(fromAppKit: NSEvent.mouseLocation, primaryHeight: primaryHeight)
        windowServer = state
        // An empty list means CGWindowList failed, not that every window closed.
        if !state.windows.isEmpty {
            creationOrders = creationOrders.filter { state.windows[$0.key] != nil }
            focusOrder.prune(keeping: Set(state.windows.keys))
        }
    }

    private func makeSnapshot() -> WindowSnapshot {
        let state = windowServer
        let frontmost = frontmostPID
        let spacesByID = Dictionary(state.spaces.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let onScreen = Set(state.onScreen)
        var windows: [WindowInfo] = []
        var windowless: [(app: AppRecord, info: AppInfo)] = []
        for app in apps.values {
            let info = app.info(isActive: app.pid == frontmost)
            var listsWindow = false
            for record in app.windows.values {
                guard let cg = state.windows[record.id], cg.pid == app.pid, cg.layer == 0,
                      record.isMinimized || cg.hasListableSize
                else { continue }
                let spaceIDs = PrivateAPIs.spaces(forWindow: record.id)
                let spaces = spaceIDs.compactMap { spacesByID[$0] }
                windows.append(WindowInfo(
                    id: .window(record.id),
                    app: info,
                    title: record.title,
                    frame: cg.bounds,
                    spaceIDs: spaces.map(\.id),
                    spaceIndexes: spaces.map(\.index),
                    isOnAllSpaces: spaceIDs.count > 1,
                    displayID: Geometry.displayID(for: cg.bounds, in: state.screens),
                    isMinimized: record.isMinimized,
                    isFullscreen: record.isFullscreen || spaces.contains(where: \.isFullscreen),
                    isBackgroundTab: !record.isMinimized && !info.isHidden && spaceIDs.isEmpty
                        && !onScreen.contains(record.id),
                    creationOrder: creationOrder(of: record.id)
                ))
                listsWindow = true
            }
            if !listsWindow, app.hasRead, app.running.activationPolicy == .regular {
                windowless.append((app: app, info: info))
            }
        }

        let ranks = focusOrder.windowRanks
        windows.sort { Self.precedes($0, $1, ranks: ranks) }
        let listedIDs = Set(windows.compactMap(\.windowID))
        var zRanks: [WindowID: Int] = [:]
        for windowID in state.onScreen where listedIDs.contains(windowID) && zRanks[windowID] == nil {
            zRanks[windowID] = zRanks.count
        }
        for index in windows.indices {
            windows[index].lastFocusOrder = index
            windows[index].zIndex = windows[index].windowID.flatMap { zRanks[$0] }
        }

        windowless.sort { lhs, rhs in
            switch (focusOrder.appRank(of: lhs.app.pid), focusOrder.appRank(of: rhs.app.pid)) {
            case let (left?, right?) where left != right: return left < right
            case (_?, nil): return true
            case (nil, _?): return false
            default:
                return lhs.app.launchOrder != rhs.app.launchOrder
                    ? lhs.app.launchOrder > rhs.app.launchOrder
                    : lhs.app.pid < rhs.app.pid
            }
        }
        for entry in windowless {
            windows.append(WindowInfo(
                id: .windowlessApp(entry.app.pid),
                app: entry.info,
                title: "",
                lastFocusOrder: windows.count
            ))
        }

        return WindowSnapshot(
            windows: windows,
            screens: state.screens,
            spaces: state.spaces,
            mouseLocation: state.mouseLocation,
            frontmostPID: frontmost,
            focusedWindowID: frontmost.flatMap { apps[$0]?.focusedWindowID }
        )
    }

    /// Focus recency first; windows never focused follow, newest first.
    private static func precedes(_ lhs: WindowInfo, _ rhs: WindowInfo, ranks: [WindowID: Int]) -> Bool {
        let left = lhs.windowID ?? 0
        let right = rhs.windowID ?? 0
        switch (ranks[left], ranks[right]) {
        case let (leftRank?, rightRank?) where leftRank != rightRank: return leftRank < rightRank
        case (_?, nil): return true
        case (nil, _?): return false
        default:
            return lhs.creationOrder != rhs.creationOrder ? lhs.creationOrder > rhs.creationOrder : left < right
        }
    }

    // MARK: - WindowServer

    private static func windowList(_ options: CGWindowListOption) -> [CGWindowEntry] {
        guard let list = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]] else { return [] }
        return list.compactMap { info in
            guard let id = (info[kCGWindowNumber as String] as? NSNumber)?.uint32Value,
                  let pid = (info[kCGWindowOwnerPID as String] as? NSNumber)?.int32Value,
                  let layer = (info[kCGWindowLayer as String] as? NSNumber)?.intValue,
                  let boundsInfo = info[kCGWindowBounds as String] as? NSDictionary,
                  let bounds = CGRect(dictionaryRepresentation: boundsInfo as CFDictionary)
            else { return nil }
            return CGWindowEntry(id: id, pid: pid, layer: layer, bounds: bounds)
        }
    }

    /// Active displays' UUID strings (uppercased), as CGSCopyManagedDisplaySpaces names them.
    private static func displayUUIDs() -> [DisplayID: String] {
        var count: UInt32 = 0
        guard CGGetActiveDisplayList(0, nil, &count) == .success, count > 0 else { return [:] }
        var displayIDs = [CGDirectDisplayID](repeating: 0, count: Int(count))
        guard CGGetActiveDisplayList(count, &displayIDs, &count) == .success else { return [:] }
        var result: [DisplayID: String] = [:]
        for displayID in displayIDs.prefix(Int(count)) {
            guard let uuid = CGDisplayCreateUUIDFromDisplayID(displayID)?.takeRetainedValue(),
                  let string = CFUUIDCreateString(nil, uuid)
            else { continue }
            result[displayID] = (string as String).uppercased()
        }
        return result
    }

    /// NSScreen in Quartz coordinates. The menu bar's display comes from SkyLight; when it is
    /// unknown (or "Main"), the primary screen has it.
    private static func screens(primaryHeight: CGFloat, uuids: [DisplayID: String]) -> [ScreenInfo] {
        let menuBarUUID = PrivateAPIs.activeMenuBarDisplayIdentifier()?.uppercased()
        var screens = NSScreen.screens.compactMap { screen -> ScreenInfo? in
            guard let number = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber else {
                return nil
            }
            let displayID = number.uint32Value
            return ScreenInfo(
                id: displayID,
                frame: Geometry.quartzRect(fromAppKit: screen.frame, primaryHeight: primaryHeight),
                visibleFrame: Geometry.quartzRect(fromAppKit: screen.visibleFrame, primaryHeight: primaryHeight),
                scale: screen.backingScaleFactor,
                hasMenuBar: menuBarUUID != nil && uuids[displayID] == menuBarUUID
            )
        }
        if !screens.isEmpty, !screens.contains(where: \.hasMenuBar) {
            screens[0].hasMenuBar = true
        }
        return screens
    }
}

// MARK: - Main-actor state

/// One CGWindowList entry.
private struct CGWindowEntry {
    let id: WindowID
    let pid: pid_t
    let layer: Int
    /// Global Quartz coordinates.
    let bounds: CGRect

    /// At least 100 × 50, the smallest window the switcher lists (unless minimized).
    var hasListableSize: Bool { bounds.width >= 100 && bounds.height >= 50 }
}

/// The WindowServer side of the catalog, captured on the main thread without AX.
private struct WindowServerState {
    var windows: [WindowID: CGWindowEntry] = [:]
    /// Every window id in CGWindowList order (front to back).
    var order: [WindowID] = []
    /// Layer-0 windows on screen, front to back.
    var onScreen: [WindowID] = []
    var screens: [ScreenInfo] = []
    var spaces: [SpaceInfo] = []
    var mouseLocation: CGPoint = .zero
}

/// The refcon of an app's AXObserver: which app the callback is for, and the catalog.
@MainActor
private final class ObserverContext {
    let pid: pid_t
    weak var source: LiveWindowSource?

    init(pid: pid_t, source: LiveWindowSource) {
        self.pid = pid
        self.source = source
    }
}

/// A tracked app: its AX element, observer, serial AX queue and known windows.
@MainActor
private final class AppRecord {
    enum Subscription { case idle, pending, subscribed, failed }

    /// Distinguishes a relaunched app reusing a pid from its predecessor's late results.
    let serial: Int
    let running: NSRunningApplication
    let pid: pid_t
    let element: AXUIElement
    let launchOrder: Int
    let context: ObserverContext
    /// Every AX call into this app runs here.
    let queue: DispatchQueue
    private(set) var observer: AXObserver?
    var subscription = Subscription.idle
    var windows: [WindowID: AXWindowRecord] = [:]
    /// Windows whose per-window notifications are registered.
    var registeredWindowIDs: Set<WindowID> = []
    var focusedWindowID: WindowID?
    /// A full read finished once; until then the app gets no windowless entry.
    var hasRead = false
    var readInFlight = false
    var needsFullRead = false
    var dirtyWindowIDs: Set<WindowID> = []
    /// The Space generation of the last remote-token probe.
    var probedGeneration = -1

    init(serial: Int, running: NSRunningApplication, launchOrder: Int, source: LiveWindowSource) {
        let pid = running.processIdentifier
        let element = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(element, AXReader.messagingTimeout)
        self.serial = serial
        self.running = running
        self.pid = pid
        self.element = element
        self.launchOrder = launchOrder
        context = ObserverContext(pid: pid, source: source)
        queue = DispatchQueue(label: "com.soprano.tab.ax.\(pid)", qos: .userInitiated)
    }

    var refcon: UnsafeMutableRawPointer {
        Unmanaged.passUnretained(context).toOpaque()
    }

    /// Creates the observer (local, no IPC) and puts its source on the main run loop.
    func attachObserver() {
        guard observer == nil, let created = AXReader.makeObserver(pid: pid) else { return }
        CFRunLoopAddSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(created), .commonModes)
        observer = created
    }

    /// Removes the observer's run-loop source: no callback arrives after this.
    func detach() {
        if let observer {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(observer), .commonModes)
        }
        observer = nil
        context.source = nil
    }

    /// The known window `element` stands for (`CFEqual`, no IPC).
    func windowID(of element: AXUIElement) -> WindowID? {
        windows.first { CFEqual($0.value.element, element) }?.key
    }

    func info(isActive: Bool) -> AppInfo {
        AppInfo(
            pid: pid,
            bundleID: running.bundleIdentifier,
            name: running.localizedName ?? running.bundleURL?.deletingPathExtension().lastPathComponent ?? "",
            bundlePath: running.bundleURL?.path,
            isActive: isActive,
            isHidden: running.isHidden,
            launchOrder: launchOrder
        )
    }
}

// MARK: - Background AX work

/// A window as AX reported it. AXUIElement is an immutable handle that is safe to use
/// from any thread.
private struct AXWindowRecord: @unchecked Sendable {
    let id: WindowID
    let element: AXUIElement
    let title: String
    let isMinimized: Bool
    /// `AXFullScreen`.
    let isFullscreen: Bool
}

private struct SubscribeJob: @unchecked Sendable {
    let app: AXUIElement
    let observer: AXObserver
    let refcon: UnsafeMutableRawPointer
    /// Keeps `refcon` alive while the job runs.
    let context: ObserverContext
}

private struct ReadJob: @unchecked Sendable {
    let pid: pid_t
    let serial: Int
    let generation: Int
    let app: AXUIElement
    let observer: AXObserver?
    let refcon: UnsafeMutableRawPointer
    /// Keeps `refcon` alive while the job runs.
    let context: ObserverContext
    /// Re-list every window (kAXWindows, focused window, probe) instead of `dirty` only.
    let full: Bool
    let dirty: [AXWindowRecord]
    let registeredWindowIDs: Set<WindowID>
    /// Windows to recover by remote-token probing when AX does not list them.
    let probeCandidates: Set<WindowID>
}

private struct ReadResult: Sendable {
    let pid: pid_t
    let serial: Int
    let generation: Int
    let full: Bool
    /// Full read: the windows AX listed plus probed ones; nil when kAXWindows failed.
    var windows: [AXWindowRecord]?
    var probed = false
    var focusedWindowID: WindowID?
    var focusKnown = false
    /// Partial read: re-read windows, and windows that are gone or no longer qualify.
    var updated: [AXWindowRecord] = []
    var goneWindowIDs: [WindowID] = []
    var registeredWindowIDs: Set<WindowID> = []
}

/// The AX side, run on each app's queue. Nonisolated: never touches catalog state.
private enum AXReader {
    static let messagingTimeout: Float = 0.25
    /// The remote-token probe gives up after this long (an app that stopped answering).
    static let probeTimeLimit: TimeInterval = 1.5
    static let probeElementIDs: Range<UInt64> = 0 ..< 1000

    static let appNotifications = [
        kAXWindowCreatedNotification,
        kAXFocusedWindowChangedNotification,
        kAXMainWindowChangedNotification,
        kAXApplicationHiddenNotification,
        kAXApplicationShownNotification,
    ]
    static let windowNotifications = [
        kAXUIElementDestroyedNotification,
        kAXTitleChangedNotification,
        kAXWindowMiniaturizedNotification,
        kAXWindowDeminiaturizedNotification,
        kAXWindowMovedNotification,
        kAXWindowResizedNotification,
    ]
    static let fullScreenAttribute = "AXFullScreen"
    static let windowAttributes = [
        kAXRoleAttribute, kAXSubroleAttribute, kAXTitleAttribute, kAXMinimizedAttribute, fullScreenAttribute,
    ]

    enum WindowRead {
        case window(AXWindowRecord)
        /// Not a standard window or dialog, or no CGWindowID.
        case rejected
        case gone
        /// The app did not answer.
        case unavailable
    }

    /// The observer for `pid`; its callback runs wherever its source is scheduled (the main
    /// run loop) and hands the notification to the catalog on the main actor.
    static func makeObserver(pid: pid_t) -> AXObserver? {
        var observer: AXObserver?
        let status = AXObserverCreate(pid, { _, element, notification, refcon in
            guard let refcon else { return }
            let context = Unmanaged<ObserverContext>.fromOpaque(refcon).takeUnretainedValue()
            let name = notification as String
            // AXUIElement is an immutable handle; the callback already runs on the main thread.
            nonisolated(unsafe) let element = element
            MainActor.assumeIsolated {
                context.source?.handleAXNotification(name, element: element, pid: context.pid)
            }
        }, &observer)
        return status == .success ? observer : nil
    }

    /// Registers the app-level notifications; the first hard failure, else `.success`.
    static func subscribe(_ job: SubscribeJob) -> AXError {
        for name in appNotifications {
            let status = AXObserverAddNotification(job.observer, job.app, name as CFString, job.refcon)
            switch status {
            case .success, .notificationAlreadyRegistered, .notificationUnsupported:
                continue
            default:
                return status
            }
        }
        return .success
    }

    static func read(_ job: ReadJob) -> ReadResult {
        var result = ReadResult(pid: job.pid, serial: job.serial, generation: job.generation, full: job.full)
        var fresh: [AXWindowRecord] = []
        if job.full {
            if let elements = windowElements(of: job.app) {
                var windows: [AXWindowRecord] = elements.compactMap { element in
                    if case .window(let window) = readWindow(element, knownID: nil) { return window }
                    return nil
                }
                let missing = job.probeCandidates.subtracting(windows.map(\.id))
                if !missing.isEmpty {
                    windows += probe(pid: job.pid, windowIDs: missing)
                    result.probed = true
                }
                result.windows = windows
                fresh = windows
            }
            readFocusedWindow(of: job.app, into: &result)
        } else {
            for window in job.dirty {
                switch readWindow(window.element, knownID: window.id) {
                case .window(let updated):
                    result.updated.append(updated)
                case .rejected, .gone:
                    result.goneWindowIDs.append(window.id)
                case .unavailable:
                    break
                }
            }
        }
        if let observer = job.observer {
            for window in fresh where !job.registeredWindowIDs.contains(window.id) {
                if register(window, observer: observer, refcon: job.refcon) {
                    result.registeredWindowIDs.insert(window.id)
                }
            }
        }
        return result
    }

    /// kAXWindows of the app; nil when the app did not answer.
    private static func windowElements(of app: AXUIElement) -> [AXUIElement]? {
        var value: CFTypeRef?
        switch AXUIElementCopyAttributeValue(app, kAXWindowsAttribute as CFString, &value) {
        case .success:
            let items = value as? [AnyObject] ?? []
            return items.compactMap { item in
                CFGetTypeID(item) == AXUIElementGetTypeID() ? unsafeDowncast(item, to: AXUIElement.self) : nil
            }
        case .noValue:
            return []
        default:
            return nil
        }
    }

    private static func readFocusedWindow(of app: AXUIElement, into result: inout ReadResult) {
        var value: CFTypeRef?
        switch AXUIElementCopyAttributeValue(app, kAXFocusedWindowAttribute as CFString, &value) {
        case .success:
            result.focusKnown = true
            if let value, CFGetTypeID(value) == AXUIElementGetTypeID() {
                result.focusedWindowID = PrivateAPIs.windowID(of: unsafeDowncast(value, to: AXUIElement.self))
            }
        case .noValue:
            result.focusKnown = true
        default:
            break
        }
    }

    /// One batched AX round trip for role, subrole, title, minimized and fullscreen.
    static func readWindow(_ element: AXUIElement, knownID: WindowID?) -> WindowRead {
        AXUIElementSetMessagingTimeout(element, messagingTimeout)
        var values: CFArray?
        switch AXUIElementCopyMultipleAttributeValues(element, windowAttributes as CFArray, [], &values) {
        case .success:
            break
        case .invalidUIElement:
            return .gone
        default:
            return .unavailable
        }
        guard let values = values as? [AnyObject], values.count == windowAttributes.count else { return .unavailable }
        guard values[0] as? String == kAXWindowRole,
              let subrole = values[1] as? String,
              subrole == kAXStandardWindowSubrole || subrole == kAXDialogSubrole,
              let windowID = knownID ?? PrivateAPIs.windowID(of: element)
        else { return .rejected }
        return .window(AXWindowRecord(
            id: windowID,
            element: element,
            title: values[2] as? String ?? "",
            isMinimized: values[3] as? Bool ?? false,
            isFullscreen: values[4] as? Bool ?? false
        ))
    }

    /// Recovers windows kAXWindows omits (other Spaces) through remote-token elements:
    /// element ids 0..<1000, keeping standard windows and dialogs whose CGWindowID is one
    /// of `windowIDs`. Stops once all are found.
    private static func probe(pid: pid_t, windowIDs: Set<WindowID>) -> [AXWindowRecord] {
        var remaining = windowIDs
        var found: [AXWindowRecord] = []
        let deadline = ProcessInfo.processInfo.systemUptime + probeTimeLimit
        for elementID in probeElementIDs {
            guard !remaining.isEmpty, ProcessInfo.processInfo.systemUptime < deadline else { break }
            guard let element = PrivateAPIs.axElement(pid: pid, elementID: elementID) else { continue }
            AXUIElementSetMessagingTimeout(element, messagingTimeout)
            guard let windowID = PrivateAPIs.windowID(of: element), remaining.contains(windowID),
                  case .window(let window) = readWindow(element, knownID: windowID)
            else { continue }
            remaining.remove(windowID)
            found.append(window)
        }
        return found
    }

    /// Registers the per-window notifications; true once element-destroyed is registered.
    private static func register(_ window: AXWindowRecord, observer: AXObserver, refcon: UnsafeMutableRawPointer) -> Bool {
        var registered = false
        for name in windowNotifications {
            let status = AXObserverAddNotification(observer, window.element, name as CFString, refcon)
            if name == kAXUIElementDestroyedNotification {
                registered = status == .success || status == .notificationAlreadyRegistered
            }
        }
        return registered
    }
}
