import AppKit
import Testing
@testable import SopranoTabCore

private let visibleSpace: SpaceID = 1
private let otherSpace: SpaceID = 2

private func app(_ pid: pid_t, _ name: String, bundleID: String? = nil, hidden: Bool = false) -> AppInfo {
    AppInfo(pid: pid, bundleID: bundleID ?? "test.\(name.lowercased())", name: name, isHidden: hidden)
}

private func window(
    _ id: WindowID,
    _ app: AppInfo,
    title: String = "",
    focus: Int = 0,
    created: Int = 0,
    spaces: [SpaceID] = [visibleSpace],
    allSpaces: Bool = false,
    display: DisplayID? = 1,
    frame: CGRect = CGRect(x: 0, y: 0, width: 400, height: 300),
    minimized: Bool = false,
    fullscreen: Bool = false,
    backgroundTab: Bool = false,
    z: Int? = nil
) -> WindowInfo {
    WindowInfo(
        id: .window(id), app: app, title: title, frame: frame,
        spaceIDs: spaces, spaceIndexes: spaces.map { Int($0) }, isOnAllSpaces: allSpaces,
        displayID: display, isMinimized: minimized, isFullscreen: fullscreen,
        isBackgroundTab: backgroundTab, lastFocusOrder: focus, creationOrder: created, zIndex: z
    )
}

private func windowless(_ app: AppInfo, focus: Int = 100) -> WindowInfo {
    WindowInfo(id: .windowlessApp(app.pid), app: app, title: "", lastFocusOrder: focus)
}

private func snapshot(_ windows: [WindowInfo], frontmost: pid_t? = nil, mouse: CGPoint = .zero) -> WindowSnapshot {
    WindowSnapshot(
        windows: windows,
        screens: [ScreenInfo(id: 1, frame: CGRect(x: 0, y: 0, width: 1512, height: 982),
                             visibleFrame: CGRect(x: 0, y: 33, width: 1512, height: 949), hasMenuBar: true)],
        spaces: [
            SpaceInfo(id: visibleSpace, index: 1, displayID: 1, isVisible: true),
            SpaceInfo(id: otherSpace, index: 2, displayID: 1, isVisible: false),
            SpaceInfo(id: 3, index: 3, displayID: 1, isVisible: false),
        ],
        mouseLocation: mouse,
        frontmostPID: frontmost
    )
}

private func items(
    _ snapshot: WindowSnapshot,
    _ filters: WindowFilters = WindowFilters(),
    exceptions: [ExceptionRule] = [],
    display: DisplayID? = 1
) -> [ItemID] {
    WindowListBuilder.items(from: snapshot, filters: filters, exceptions: exceptions, switcherDisplayID: display).map(\.id)
}

struct WindowListBuilderTests {
    let safari = app(10, "Safari")
    let mail = app(20, "Mail")
    let notes = app(30, "Notes")

    @Test("hide always drops every item of the app, windowless entry included")
    func exceptionHideAlways() {
        let desktop = snapshot([window(1, safari), window(2, mail), windowless(notes)])
        let rules = [ExceptionRule(bundleID: "test.safari", hide: .always), ExceptionRule(bundleID: "test.notes", hide: .always)]
        #expect(items(desktop, exceptions: rules) == [.window(2)])
    }

    @Test("whenNoOpenWindow drops only the windowless entry")
    func exceptionWhenNoOpenWindow() {
        let finder = app(40, "Finder", bundleID: "com.apple.finder")
        let other = app(41, "Other", bundleID: "com.apple.other")
        let desktop = snapshot([window(1, finder), windowless(finder), windowless(other)])
        #expect(items(desktop, exceptions: ExceptionRule.defaults) == [.window(1), .windowlessApp(41)])
    }

    @Test("whenTitleContains drops windows whose title contains any fragment, ignoring case")
    func exceptionWhenTitleContains() {
        let desktop = snapshot([
            window(1, safari, title: "Private Browsing", focus: 0),
            window(2, safari, title: "Inbox", focus: 1),
            window(3, safari, title: "secret plans", focus: 2),
            window(4, mail, title: "Private", focus: 3),
        ])
        let rules = [ExceptionRule(bundleID: "test.safari", hide: .whenTitleContains, titleContains: ["private", "SECRET"])]
        #expect(items(desktop, exceptions: rules) == [.window(2), .window(4)])
    }

    @Test("exceptions apply before the app-under-cursor filter picks its app")
    func exceptionsBeforeApps() {
        let frame = CGRect(x: 0, y: 0, width: 500, height: 500)
        let desktop = snapshot(
            [window(1, safari, frame: frame, z: 0), window(2, mail, frame: frame, z: 1), window(3, mail, focus: 5, spaces: [otherSpace])],
            mouse: CGPoint(x: 100, y: 100)
        )
        let rules = [ExceptionRule(bundleID: "test.safari", hide: .always)]
        #expect(items(desktop, WindowFilters(apps: .appUnderCursor), exceptions: rules) == [.window(2), .window(3)])
        #expect(items(desktop, WindowFilters(apps: .appUnderCursor)) == [.window(1)])
    }

    @Test("active and nonActive split by the frontmost pid, windowless entries included")
    func activeAndNonActive() {
        let desktop = snapshot(
            [window(1, safari, focus: 0), window(2, mail, focus: 1), windowless(notes), window(3, safari, focus: 2)],
            frontmost: 10
        )
        #expect(items(desktop, WindowFilters(apps: .active)) == [.window(1), .window(3)])
        #expect(items(desktop, WindowFilters(apps: .nonActive)) == [.window(2), .windowlessApp(30)])
    }

    @Test("underCursor keeps unminimized windows on visible Spaces containing the mouse")
    func underCursor() {
        let frame = CGRect(x: 0, y: 0, width: 500, height: 500)
        let desktop = snapshot(
            [
                window(1, safari, focus: 0, frame: frame),
                window(2, mail, focus: 1, frame: frame, minimized: true),
                window(3, mail, focus: 2, spaces: [otherSpace], frame: frame),
                window(4, mail, focus: 3, frame: CGRect(x: 600, y: 0, width: 100, height: 100)),
                window(5, notes, focus: 4, spaces: [otherSpace], allSpaces: true, frame: frame),
                windowless(app(50, "Music")),
            ],
            mouse: CGPoint(x: 10, y: 10)
        )
        #expect(items(desktop, WindowFilters(apps: .underCursor)) == [.window(1), .window(5)])
    }

    @Test("appUnderCursor lists every window of the frontmost window's app under the mouse")
    func appUnderCursor() {
        let frame = CGRect(x: 0, y: 0, width: 500, height: 500)
        let desktop = snapshot(
            [
                window(1, safari, focus: 0, frame: frame, z: 2),
                window(2, mail, focus: 1, frame: frame, z: 1),
                window(3, mail, focus: 2, spaces: [otherSpace], frame: CGRect(x: 900, y: 0, width: 10, height: 10)),
                windowless(notes),
            ],
            mouse: CGPoint(x: 10, y: 10)
        )
        #expect(items(desktop, WindowFilters(apps: .appUnderCursor)) == [.window(2), .window(3)])
        let nothingUnderMouse = snapshot(desktop.windows, mouse: CGPoint(x: 2000, y: 2000))
        #expect(items(nothingUnderMouse, WindowFilters(apps: .appUnderCursor)).isEmpty)
    }

    @Test("windowless entries never pass the cursor filters")
    func windowlessVersusCursorFilters() {
        let desktop = snapshot([windowless(notes)], frontmost: 30, mouse: .zero)
        #expect(items(desktop, WindowFilters(apps: .underCursor)).isEmpty)
        #expect(items(desktop, WindowFilters(apps: .appUnderCursor)).isEmpty)
        #expect(items(desktop, WindowFilters(apps: .active)) == [.windowlessApp(30)])
    }

    @Test("visible Spaces keep all-Spaces windows, minimized windows and windowless entries without Spaces")
    func spacesFilter() {
        let desktop = snapshot([
            window(1, safari, focus: 0),
            window(2, safari, focus: 1, spaces: [otherSpace]),
            window(3, safari, focus: 2, spaces: [otherSpace], allSpaces: true),
            window(4, mail, focus: 3, spaces: [], minimized: true),
            window(5, mail, focus: 4, spaces: [otherSpace], minimized: true),
            window(6, mail, focus: 5, spaces: []),
            window(7, mail, focus: 6, spaces: [otherSpace, visibleSpace]),
            windowless(notes),
        ])
        let visible = items(desktop, WindowFilters(spaces: .visible, windowlessApps: .show))
        let nonVisible = items(desktop, WindowFilters(spaces: .nonVisible, windowlessApps: .show))
        #expect(visible == [.window(1), .window(3), .window(4), .window(7), .windowlessApp(30)])
        #expect(nonVisible == [.window(2), .window(5), .window(6)])
    }

    @Test("showingSwitcher keeps the switcher's display and items without a display")
    func screensFilter() {
        let desktop = snapshot([
            window(1, safari, focus: 0, display: 1),
            window(2, safari, focus: 1, display: 2),
            window(3, mail, focus: 2, display: nil),
            windowless(notes),
        ])
        let filters = WindowFilters(screens: .showingSwitcher, windowlessApps: .show)
        #expect(items(desktop, filters, display: 2) == [.window(2), .window(3), .windowlessApp(30)])
        #expect(items(desktop, WindowFilters(windowlessApps: .show), display: 2).count == 4)
    }

    @Test("singleWindow drops background tabs and separateWindows keeps them")
    func tabsFilter() {
        let desktop = snapshot([window(1, safari, focus: 0), window(2, safari, focus: 1, spaces: [], backgroundTab: true)])
        #expect(items(desktop, WindowFilters(tabs: .singleWindow)) == [.window(1)])
        #expect(items(desktop, WindowFilters(tabs: .separateWindows)) == [.window(1), .window(2)])
    }

    @Test("recentlyFocused orders by focus rank, then window id")
    func recentlyFocusedOrder() {
        let desktop = snapshot([window(9, safari, focus: 1), window(3, mail, focus: 0), window(5, safari, focus: 1)])
        #expect(items(desktop, WindowFilters(order: .recentlyFocused)) == [.window(3), .window(5), .window(9)])
    }

    @Test("recentlyCreated orders newest first, then focus rank, then window id")
    func recentlyCreatedOrder() {
        let desktop = snapshot([
            window(1, safari, focus: 0, created: 1),
            window(2, mail, focus: 3, created: 5),
            window(3, safari, focus: 2, created: 5),
            window(4, mail, focus: 2, created: 5),
        ])
        #expect(items(desktop, WindowFilters(order: .recentlyCreated)) == [.window(3), .window(4), .window(2), .window(1)])
    }

    @Test("alphabetical orders by app name, then natural title order, then window id")
    func alphabeticalOrder() {
        let desktop = snapshot([
            window(1, safari, title: "Doc 10", focus: 0),
            window(2, safari, title: "Doc 2", focus: 1),
            window(3, mail, title: "Zed", focus: 2),
            window(5, safari, title: "Doc 2", focus: 3),
            window(4, mail, title: "", focus: 4),
        ])
        // The untitled Mail window sorts by its display title "Mail".
        #expect(items(desktop, WindowFilters(order: .alphabetical)) == [.window(4), .window(3), .window(2), .window(5), .window(1)])
    }

    @Test("space order puts all-Spaces windows first and unknown Spaces last, then focus rank")
    func spaceOrder() {
        let desktop = snapshot([
            window(1, safari, focus: 0, spaces: [3]),
            window(2, safari, focus: 1, spaces: [], minimized: true),
            window(3, mail, focus: 2, spaces: [3], allSpaces: true),
            window(4, mail, focus: 3, spaces: [3, 2]),
            window(5, safari, focus: 4, spaces: [1]),
            window(6, mail, focus: 0, spaces: [3]),
        ])
        #expect(items(desktop, WindowFilters(order: .space)) == [.window(3), .window(5), .window(4), .window(1), .window(6), .window(2)])
    }

    @Test("oneWindowPerApp keeps each app's first item after ordering")
    func oneWindowPerApp() {
        let desktop = snapshot([
            window(1, safari, focus: 0, created: 1),
            window(2, safari, focus: 1, created: 9),
            window(3, mail, focus: 2, created: 4),
            window(4, mail, focus: 3, created: 2),
        ])
        #expect(items(desktop, WindowFilters(order: .recentlyCreated, grouping: .oneWindowPerApp)) == [.window(2), .window(3)])
        #expect(items(desktop, WindowFilters(grouping: .oneWindowPerApp)) == [.window(1), .window(3)])
    }

    @Test("showAtTheEnd moves matching items to one tail group in sorted order")
    func showAtTheEndTail() {
        let hiddenMail = app(20, "Mail", hidden: true)
        let desktop = snapshot([
            window(1, safari, focus: 0),
            window(2, safari, focus: 1, minimized: true),
            window(3, hiddenMail, focus: 2),
            window(4, safari, focus: 3),
            windowless(notes, focus: 4),
            window(5, safari, focus: 5, fullscreen: true),
        ])
        let filters = WindowFilters(minimized: .showAtTheEnd, hidden: .showAtTheEnd, fullscreen: .show, windowlessApps: .showAtTheEnd)
        #expect(items(desktop, filters) == [.window(1), .window(4), .window(5), .window(2), .window(3), .windowlessApp(30)])
    }

    @Test("hide wins over showAtTheEnd, and showAtTheEnd wins over show")
    func showPolicyPrecedence() {
        let hiddenMail = app(20, "Mail", hidden: true)
        let desktop = snapshot([
            window(1, hiddenMail, focus: 0, minimized: true),
            window(2, safari, focus: 1, minimized: true, fullscreen: true),
            window(3, safari, focus: 2),
        ])
        let filters = WindowFilters(minimized: .showAtTheEnd, hidden: .hide, fullscreen: .show)
        #expect(items(desktop, filters) == [.window(3), .window(2)])
        let swapped = WindowFilters(minimized: .show, hidden: .show, fullscreen: .showAtTheEnd)
        #expect(items(desktop, swapped) == [.window(1), .window(3), .window(2)])
    }

    @Test("the show policies run after grouping, so a hidden first window removes its app")
    func showPolicyAfterGrouping() {
        let desktop = snapshot([window(1, safari, focus: 0, minimized: true), window(2, safari, focus: 1), window(3, mail, focus: 2)])
        let filters = WindowFilters(minimized: .hide, grouping: .oneWindowPerApp)
        #expect(items(desktop, filters) == [.window(3)])
    }

    @Test("windowless entries go to the end by default")
    func windowlessDefaultTail() {
        let desktop = snapshot([windowless(notes, focus: 0), window(1, safari, focus: 1)])
        #expect(items(desktop) == [.window(1), .windowlessApp(30)])
        #expect(items(desktop, WindowFilters(windowlessApps: .hide)) == [.window(1)])
    }
}
