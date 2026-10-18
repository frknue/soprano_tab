import CoreGraphics
import SopranoTabCore

/// Fake desktops for the snapshot harness and the tests. Every id, title and frame is
/// fixed, so the same scenario always renders the same switcher.
enum FixtureScenario: String, CaseIterable {
    /// One laptop screen, 3 Spaces, 11 windows over 8 apps plus windowless Notes and Music.
    case standard
    /// 40 windows over 12 apps on two Spaces.
    case crowded
    /// Only windowless apps, including a windowless Finder (hidden by the default exception).
    case windowless
    /// No windows at all.
    case empty
    /// The laptop screen plus a 2560 × 1440 display to its right, windows on both.
    case multiScreen

    /// A 14" MacBook Pro at its default scaling.
    static let defaultScreenSize = CGSize(width: 1512, height: 982)
    static let menuBarHeight: CGFloat = 33

    /// The scenario's desktop. `screenSize` sizes the laptop (primary) screen; window
    /// frames scale with its visible frame so they always stay on screen.
    func snapshot(screenSize: CGSize = FixtureScenario.defaultScreenSize) -> WindowSnapshot {
        let laptop = ScreenInfo(
            id: FixtureDisplay.laptop,
            frame: CGRect(origin: .zero, size: screenSize),
            visibleFrame: CGRect(
                x: 0,
                y: Self.menuBarHeight,
                width: screenSize.width,
                height: screenSize.height - Self.menuBarHeight
            ),
            scale: 2,
            hasMenuBar: true
        )
        switch self {
        case .standard: return FixtureDesktops.standard(laptop: laptop)
        case .crowded: return FixtureDesktops.crowded(laptop: laptop)
        case .windowless: return FixtureDesktops.windowless(laptop: laptop)
        case .empty: return FixtureDesktops.empty(laptop: laptop)
        case .multiScreen: return FixtureDesktops.multiScreen(laptop: laptop)
        }
    }
}

/// Display ids used by the scenarios.
enum FixtureDisplay {
    static let laptop: DisplayID = 1
    static let external: DisplayID = 2
}

/// The fixture apps. Pids are stable so tests can refer to them.
enum FixtureApps {
    static let soprano = AppInfo(pid: 501, bundleID: "com.soprano.app", name: "Soprano", launchOrder: 1)
    static let safari = AppInfo(pid: 502, bundleID: "com.apple.Safari", name: "Safari", launchOrder: 2)
    static let finder = AppInfo(pid: 503, bundleID: "com.apple.finder", name: "Finder", launchOrder: 0)
    static let mail = AppInfo(pid: 504, bundleID: "com.apple.mail", name: "Mail", isHidden: true, launchOrder: 3)
    static let slack = AppInfo(pid: 505, bundleID: "com.tinyspeck.slackmacgap", name: "Slack", launchOrder: 4)
    static let systemSettings = AppInfo(
        pid: 506, bundleID: "com.apple.systempreferences", name: "System Settings", launchOrder: 5
    )
    static let sopranoGit = AppInfo(pid: 507, bundleID: "com.soprano.git", name: "Soprano Git", launchOrder: 6)
    static let stickies = AppInfo(pid: 508, bundleID: "com.apple.Stickies", name: "Stickies", launchOrder: 7)
    static let notes = AppInfo(pid: 509, bundleID: "com.apple.Notes", name: "Notes", launchOrder: 8)
    static let music = AppInfo(pid: 510, bundleID: "com.apple.Music", name: "Music", launchOrder: 9)
    static let calendar = AppInfo(pid: 511, bundleID: "com.apple.iCal", name: "Calendar", launchOrder: 10)
    static let xcode = AppInfo(pid: 512, bundleID: "com.apple.dt.Xcode", name: "Xcode", launchOrder: 11)
    static let figma = AppInfo(pid: 513, bundleID: "com.figma.Desktop", name: "Figma", launchOrder: 12)
    static let preview = AppInfo(pid: 514, bundleID: "com.apple.Preview", name: "Preview", launchOrder: 13)
}

/// Maps frames laid out on a reference visible frame into a screen's visible frame, so
/// one layout serves every `--screen` size. Floors origin and size, which keeps every
/// placed frame inside the target.
private struct Placement {
    let reference: CGRect
    let target: CGRect

    /// The reference is the default laptop's visible frame.
    static func laptop(_ screen: ScreenInfo) -> Placement {
        let size = FixtureScenario.defaultScreenSize
        let menuBar = FixtureScenario.menuBarHeight
        return Placement(
            reference: CGRect(x: 0, y: menuBar, width: size.width, height: size.height - menuBar),
            target: screen.visibleFrame
        )
    }

    func frame(_ x: CGFloat, _ y: CGFloat, _ width: CGFloat, _ height: CGFloat) -> CGRect {
        let scaleX = target.width / reference.width
        let scaleY = target.height / reference.height
        return CGRect(
            x: (target.minX + (x - reference.minX) * scaleX).rounded(.down),
            y: (target.minY + (y - reference.minY) * scaleY).rounded(.down),
            width: (width * scaleX).rounded(.down),
            height: (height * scaleY).rounded(.down)
        )
    }
}

/// Accumulates windows in creation order.
private struct DesktopBuilder {
    let screens: [ScreenInfo]
    let spaces: [SpaceInfo]
    private(set) var windows: [WindowInfo] = []

    init(screens: [ScreenInfo], spaces: [SpaceInfo]) {
        self.screens = screens
        self.spaces = spaces
    }

    /// `space` nil with `onAllSpaces` puts the window on every Space ("All Desktops").
    mutating func window(
        _ id: WindowID,
        _ app: AppInfo,
        _ title: String,
        frame: CGRect,
        display: DisplayID,
        space: SpaceID?,
        onAllSpaces: Bool = false,
        minimized: Bool = false,
        fullscreen: Bool = false,
        focus: Int,
        zIndex: Int?
    ) {
        let spaceIDs = space.map { [$0] } ?? []
        let spaceIndexes = spaceIDs.compactMap { id in spaces.first { $0.id == id }?.index }
        windows.append(WindowInfo(
            id: .window(id),
            app: app,
            title: title,
            frame: frame,
            spaceIDs: spaceIDs,
            spaceIndexes: spaceIndexes,
            isOnAllSpaces: onAllSpaces,
            displayID: display,
            isMinimized: minimized,
            isFullscreen: fullscreen,
            lastFocusOrder: focus,
            creationOrder: windows.count,
            zIndex: zIndex
        ))
    }

    mutating func windowless(_ app: AppInfo, focus: Int) {
        windows.append(WindowInfo(
            id: .windowlessApp(app.pid),
            app: app,
            title: "",
            lastFocusOrder: focus,
            creationOrder: windows.count
        ))
    }

    /// Marks the frontmost app's items active and puts the mouse in the middle of the
    /// first screen's visible frame.
    func snapshot(frontmost: pid_t?, focused: WindowID?) -> WindowSnapshot {
        var items = windows
        for index in items.indices {
            items[index].app.isActive = items[index].app.pid == frontmost
        }
        let visible = screens.first?.visibleFrame ?? .zero
        return WindowSnapshot(
            windows: items,
            screens: screens,
            spaces: spaces,
            mouseLocation: CGPoint(x: visible.midX.rounded(), y: visible.midY.rounded()),
            frontmostPID: frontmost,
            focusedWindowID: focused
        )
    }
}

private enum FixtureDesktops {
    static func standard(laptop: ScreenInfo) -> WindowSnapshot {
        let desk: SpaceID = 11
        let settingsSpace: SpaceID = 12
        let slackSpace: SpaceID = 13
        var builder = DesktopBuilder(screens: [laptop], spaces: [
            SpaceInfo(id: desk, index: 1, displayID: laptop.id, isVisible: true),
            SpaceInfo(id: settingsSpace, index: 2, displayID: laptop.id, isVisible: false),
            SpaceInfo(id: slackSpace, index: 3, displayID: laptop.id, isVisible: false, isFullscreen: true),
        ])
        let place = Placement.laptop(laptop)
        let display = laptop.id
        builder.window(1001, FixtureApps.soprano, "soprano-tab — claude", frame: place.frame(180, 90, 1100, 760),
                       display: display, space: desk, focus: 0, zIndex: 0)
        builder.window(1002, FixtureApps.soprano, "valkental — zsh", frame: place.frame(120, 60, 980, 700),
                       display: display, space: desk, focus: 3, zIndex: 3)
        builder.window(1003, FixtureApps.safari, "Features – AltTab", frame: place.frame(260, 110, 1180, 820),
                       display: display, space: desk, focus: 1, zIndex: 1)
        builder.window(1004, FixtureApps.safari, "Valkental/shop-theme · Pull Request #81",
                       frame: place.frame(340, 70, 1060, 760), display: display, space: desk, focus: 4, zIndex: 4)
        builder.window(1005, FixtureApps.safari, "Swift Forums – Strict Concurrency Checking",
                       frame: place.frame(300, 140, 1000, 700), display: display, space: desk, minimized: true,
                       focus: 8, zIndex: nil)
        builder.window(1006, FixtureApps.finder, "Downloads", frame: place.frame(60, 420, 760, 480),
                       display: display, space: desk, focus: 5, zIndex: 5)
        builder.window(1007, FixtureApps.mail, "Inbox – 3 unread messages", frame: place.frame(200, 100, 1100, 760),
                       display: display, space: desk, focus: 7, zIndex: nil)
        builder.window(1008, FixtureApps.slack, "soprano (Channel) - Valkental - Slack", frame: laptop.frame,
                       display: display, space: slackSpace, fullscreen: true, focus: 10, zIndex: nil)
        builder.window(1009, FixtureApps.systemSettings, "Privacy & Security", frame: place.frame(400, 160, 720, 640),
                       display: display, space: settingsSpace, focus: 9, zIndex: nil)
        builder.window(1010, FixtureApps.sopranoGit, "soprano-tab — main", frame: place.frame(90, 110, 1240, 800),
                       display: display, space: desk, focus: 2, zIndex: 2)
        builder.window(1011, FixtureApps.stickies, "Groceries", frame: place.frame(1180, 60, 300, 260),
                       display: display, space: nil, onAllSpaces: true, focus: 6, zIndex: 6)
        builder.windowless(FixtureApps.notes, focus: 11)
        builder.windowless(FixtureApps.music, focus: 12)
        return builder.snapshot(frontmost: FixtureApps.soprano.pid, focused: 1001)
    }

    private static let crowdedApps: [(app: AppInfo, titles: [String])] = [
        (FixtureApps.soprano, ["soprano-tab — claude", "valkental — zsh", "shop-theme — npm run dev", "~ — htop"]),
        (FixtureApps.safari, ["Features – AltTab", "Shopify Admin – Orders", "Swift Forums", "Apple Developer"]),
        (FixtureApps.finder, ["Downloads", "Documents", "Applications", "git"]),
        (FixtureApps.mail, ["Inbox – 3 unread messages", "Re: Weekly sync", "Invoice October", "Drafts"]),
        (FixtureApps.slack, ["soprano (Channel) - Valkental - Slack", "eric (DM) - Valkental - Slack", "Huddle"]),
        (FixtureApps.sopranoGit, ["soprano-tab — main", "soprano — main", "shop-theme — feature/h31"]),
        (FixtureApps.notes, ["Ideas", "Meeting notes", "Packing list"]),
        (FixtureApps.music, ["Music", "Miniplayer", "Equalizer"]),
        (FixtureApps.calendar, ["Calendar", "Event details", "October 2026"]),
        (FixtureApps.xcode, ["SopranoTab — SwitcherWindow.swift", "Organizer", "Devices and Simulators"]),
        (FixtureApps.figma, ["Switcher — Design 7a", "Soprano icons", "Onboarding"]),
        (FixtureApps.preview, ["brief-h31.pdf", "Screenshot 2026-10-19.png", "invoice.pdf"]),
    ]

    static func crowded(laptop: ScreenInfo) -> WindowSnapshot {
        let desk: SpaceID = 11
        let second: SpaceID = 12
        var builder = DesktopBuilder(screens: [laptop], spaces: [
            SpaceInfo(id: desk, index: 1, displayID: laptop.id, isVisible: true),
            SpaceInfo(id: second, index: 2, displayID: laptop.id, isVisible: false),
        ])
        let place = Placement.laptop(laptop)
        var zIndex = 0
        for index in 0..<40 {
            let entry = crowdedApps[index % crowdedApps.count]
            let round = index / crowdedApps.count
            let space = index % 4 == 3 ? second : desk
            let minimized = index % 13 == 12
            let onScreen = space == desk && !minimized && !entry.app.isHidden
            builder.window(
                WindowID(2001 + index),
                entry.app,
                entry.titles[round % entry.titles.count],
                frame: place.frame(
                    40 + CGFloat(index % 8) * 60,
                    50 + CGFloat(index % 6) * 40,
                    760 + CGFloat(index % 3) * 120,
                    520 + CGFloat(index % 4) * 60
                ),
                display: laptop.id,
                space: space,
                minimized: minimized,
                focus: index,
                zIndex: onScreen ? zIndex : nil
            )
            if onScreen { zIndex += 1 }
        }
        return builder.snapshot(frontmost: FixtureApps.soprano.pid, focused: 2001)
    }

    static func windowless(laptop: ScreenInfo) -> WindowSnapshot {
        var builder = DesktopBuilder(screens: [laptop], spaces: [
            SpaceInfo(id: 11, index: 1, displayID: laptop.id, isVisible: true),
        ])
        builder.windowless(FixtureApps.finder, focus: 0)
        builder.windowless(FixtureApps.notes, focus: 1)
        builder.windowless(FixtureApps.music, focus: 2)
        builder.windowless(FixtureApps.calendar, focus: 3)
        return builder.snapshot(frontmost: FixtureApps.finder.pid, focused: nil)
    }

    static func empty(laptop: ScreenInfo) -> WindowSnapshot {
        DesktopBuilder(screens: [laptop], spaces: [
            SpaceInfo(id: 11, index: 1, displayID: laptop.id, isVisible: true),
        ]).snapshot(frontmost: nil, focused: nil)
    }

    static func multiScreen(laptop: ScreenInfo) -> WindowSnapshot {
        let menuBar = FixtureScenario.menuBarHeight
        let externalSize = CGSize(width: 2560, height: 1440)
        let external = ScreenInfo(
            id: FixtureDisplay.external,
            frame: CGRect(x: laptop.frame.maxX, y: 0, width: externalSize.width, height: externalSize.height),
            visibleFrame: CGRect(
                x: laptop.frame.maxX,
                y: menuBar,
                width: externalSize.width,
                height: externalSize.height - menuBar
            ),
            scale: 1,
            hasMenuBar: false
        )
        let laptopDesk: SpaceID = 11
        let laptopSecond: SpaceID = 12
        let externalDesk: SpaceID = 21
        var builder = DesktopBuilder(screens: [laptop, external], spaces: [
            SpaceInfo(id: laptopDesk, index: 1, displayID: laptop.id, isVisible: true),
            SpaceInfo(id: laptopSecond, index: 2, displayID: laptop.id, isVisible: false),
            SpaceInfo(id: externalDesk, index: 3, displayID: external.id, isVisible: true),
        ])
        let onLaptop = Placement.laptop(laptop)
        let onExternal = Placement(
            reference: CGRect(x: 0, y: menuBar, width: externalSize.width, height: externalSize.height - menuBar),
            target: external.visibleFrame
        )
        builder.window(1001, FixtureApps.soprano, "soprano-tab — claude", frame: onLaptop.frame(160, 80, 1120, 780),
                       display: laptop.id, space: laptopDesk, focus: 0, zIndex: 0)
        builder.window(1002, FixtureApps.finder, "Downloads", frame: onLaptop.frame(60, 420, 760, 480),
                       display: laptop.id, space: laptopDesk, focus: 3, zIndex: 2)
        builder.window(1003, FixtureApps.mail, "Inbox – 3 unread messages", frame: onLaptop.frame(220, 120, 1080, 740),
                       display: laptop.id, space: laptopDesk, focus: 4, zIndex: nil)
        builder.window(1004, FixtureApps.safari, "Features – AltTab", frame: onExternal.frame(200, 120, 1600, 1100),
                       display: external.id, space: externalDesk, focus: 1, zIndex: 1)
        builder.window(1005, FixtureApps.sopranoGit, "soprano-tab — main", frame: onExternal.frame(900, 200, 1500, 1000),
                       display: external.id, space: externalDesk, focus: 2, zIndex: 3)
        builder.window(1006, FixtureApps.slack, "soprano (Channel) - Valkental - Slack",
                       frame: onExternal.frame(1400, 80, 1000, 900), display: external.id, space: externalDesk,
                       focus: 5, zIndex: 4)
        builder.window(1007, FixtureApps.systemSettings, "Privacy & Security", frame: onLaptop.frame(400, 160, 720, 640),
                       display: laptop.id, space: laptopSecond, focus: 6, zIndex: nil)
        builder.windowless(FixtureApps.notes, focus: 7)
        return builder.snapshot(frontmost: FixtureApps.soprano.pid, focused: 1001)
    }
}
