import AppKit
import Testing
@testable import SopranoTab
@testable import SopranoTabCore

@MainActor
struct FixtureScenarioTests {
    private static let screenSizes = [FixtureScenario.defaultScreenSize, CGSize(width: 800, height: 500), CGSize(width: 3008, height: 1692)]

    private func window(_ id: WindowID, in snapshot: WindowSnapshot) -> WindowInfo? {
        snapshot.windows.first { $0.id == .window(id) }
    }

    @Test("every scenario has unique item ids")
    func uniqueIDs() {
        for scenario in FixtureScenario.allCases {
            let ids = scenario.snapshot().windows.map(\.id)
            #expect(Set(ids).count == ids.count, "\(scenario)")
        }
    }

    @Test("window frames stay inside their display at every screen size")
    func framesInsideScreens() {
        for scenario in FixtureScenario.allCases {
            for size in Self.screenSizes {
                let snapshot = scenario.snapshot(screenSize: size)
                for item in snapshot.windows where !item.isWindowlessApp {
                    let screen = item.displayID.flatMap(snapshot.screen(withID:))
                    #expect(screen != nil, "\(scenario) \(item.title)")
                    if let screen {
                        #expect(screen.frame.contains(item.frame), "\(scenario) \(size) \(item.title)")
                        #expect(Geometry.displayID(for: item.frame, in: snapshot.screens) == screen.id)
                    }
                }
            }
        }
    }

    @Test("spaces and window space references point at existing displays and spaces")
    func spacesConsistent() {
        for scenario in FixtureScenario.allCases {
            let snapshot = scenario.snapshot()
            let displayIDs = Set(snapshot.screens.map(\.id))
            for space in snapshot.spaces {
                #expect(displayIDs.contains(space.displayID), "\(scenario)")
            }
            let indexes = snapshot.spaces.map(\.index)
            #expect(indexes == Array(1...snapshot.spaces.count), "\(scenario)")
            for display in displayIDs {
                #expect(snapshot.spaces.filter { $0.displayID == display && $0.isVisible }.count == 1, "\(scenario)")
            }
            for item in snapshot.windows {
                let spaces = item.spaceIDs.map { id in snapshot.spaces.first { $0.id == id } }
                #expect(spaces.allSatisfy { $0 != nil }, "\(scenario) \(item.title)")
                #expect(spaces.compactMap { $0?.index } == item.spaceIndexes)
                #expect(spaces.compactMap { $0?.displayID }.allSatisfy { $0 == item.displayID })
            }
        }
    }

    @Test("focus orders are a permutation with windowless apps after every window")
    func focusOrdersArePermutation() {
        for scenario in FixtureScenario.allCases {
            let items = scenario.snapshot().windows
            #expect(items.map(\.lastFocusOrder).sorted() == Array(0..<items.count), "\(scenario)")
            #expect(Set(items.map(\.creationOrder)).count == items.count, "\(scenario)")
            let lastWindow = items.filter { !$0.isWindowlessApp }.map(\.lastFocusOrder).max() ?? -1
            let firstWindowless = items.filter(\.isWindowlessApp).map(\.lastFocusOrder).min() ?? Int.max
            #expect(lastWindow < firstWindowless, "\(scenario)")
        }
    }

    @Test("z-indexes are unique and only on-screen windows of visible spaces have one")
    func zIndexes() {
        for scenario in FixtureScenario.allCases {
            let snapshot = scenario.snapshot()
            let ranked = snapshot.windows.compactMap(\.zIndex)
            #expect(Set(ranked).count == ranked.count, "\(scenario)")
            for item in snapshot.windows where item.zIndex != nil {
                #expect(!item.isMinimized && !item.isHidden && !item.isWindowlessApp)
                #expect(item.isOnAllSpaces || item.spaceIDs.contains(where: snapshot.visibleSpaceIDs.contains))
            }
        }
    }

    @Test("the focused window belongs to the frontmost app, which alone is active")
    func focusConsistent() {
        for scenario in FixtureScenario.allCases {
            let snapshot = scenario.snapshot()
            if let focused = snapshot.focusedWindowID {
                #expect(window(focused, in: snapshot)?.app.pid == snapshot.frontmostPID, "\(scenario)")
                #expect(window(focused, in: snapshot)?.lastFocusOrder == 0, "\(scenario)")
            }
            for item in snapshot.windows {
                #expect(item.app.isActive == (item.app.pid == snapshot.frontmostPID), "\(scenario)")
            }
        }
    }

    @Test("standard has the special windows the switcher must handle")
    func standardSpecialWindows() throws {
        let snapshot = FixtureScenario.standard.snapshot()
        let windows = snapshot.windows.filter { !$0.isWindowlessApp }
        #expect(snapshot.screens.count == 1)
        #expect(snapshot.spaces.count == 3)
        #expect((10...13).contains(windows.count))

        let focused = try #require(snapshot.focusedWindowID.flatMap { window($0, in: snapshot) })
        #expect(focused.app.name == "Soprano")
        #expect(windows.filter { $0.app.name == "Soprano" }.count == 2)

        let safari = windows.filter { $0.app.name == "Safari" }
        #expect(safari.count == 3)
        #expect(safari.filter(\.isMinimized).count == 1)

        #expect(windows.filter { $0.app.name == "Mail" }.allSatisfy { $0.isHidden })
        #expect(windows.contains { $0.app.name == "Finder" })
        #expect(windows.contains { $0.app.name == "Soprano Git" })

        let slack = try #require(windows.first { $0.app.name == "Slack" })
        let slackSpace = try #require(snapshot.spaces.first { slack.spaceIDs.contains($0.id) })
        #expect(slack.isFullscreen)
        #expect(slackSpace.isFullscreen && slackSpace.index == 3 && !slackSpace.isVisible)

        let settings = try #require(windows.first { $0.app.name == "System Settings" })
        #expect(settings.spaceIndexes == [2])

        #expect(windows.first { $0.app.name == "Stickies" }?.isOnAllSpaces == true)

        let windowless = snapshot.windows.filter(\.isWindowlessApp).map(\.app.name)
        #expect(Set(windowless) == ["Notes", "Music"])
    }

    @Test("crowded has 40 windows over 12 apps")
    func crowded() {
        let windows = FixtureScenario.crowded.snapshot().windows
        #expect(windows.count == 40)
        #expect(windows.allSatisfy { !$0.isWindowlessApp })
        #expect(Set(windows.map(\.app.pid)).count == 12)
    }

    @Test("windowless has only windowless apps, Finder among them")
    func windowless() {
        let snapshot = FixtureScenario.windowless.snapshot()
        #expect(!snapshot.windows.isEmpty)
        #expect(snapshot.windows.allSatisfy { $0.isWindowlessApp })
        #expect(snapshot.windows.contains { $0.app.bundleID == "com.apple.finder" })
        #expect(snapshot.focusedWindowID == nil)
    }

    @Test("empty has no items but a screen")
    func empty() {
        let snapshot = FixtureScenario.empty.snapshot()
        #expect(snapshot.windows.isEmpty)
        #expect(snapshot.screens.count == 1)
    }

    @Test("multiScreen puts an external display to the laptop's right with windows on both")
    func multiScreen() throws {
        let snapshot = FixtureScenario.multiScreen.snapshot()
        #expect(snapshot.screens.count == 2)
        let laptop = try #require(snapshot.screens.first { $0.hasMenuBar })
        let external = try #require(snapshot.screens.first { !$0.hasMenuBar })
        #expect(external.frame.size == CGSize(width: 2560, height: 1440))
        #expect(external.frame.minX == laptop.frame.maxX)
        let displays = Set(snapshot.windows.compactMap(\.displayID))
        #expect(displays == [laptop.id, external.id])
    }

    @Test("the screen size sizes the laptop screen below a menu bar")
    func screenSize() {
        let size = CGSize(width: 1920, height: 1200)
        let screen = FixtureScenario.standard.snapshot(screenSize: size).screens[0]
        #expect(screen.frame == CGRect(origin: .zero, size: size))
        #expect(screen.visibleFrame == CGRect(x: 0, y: 33, width: 1920, height: 1167))
    }

    @Test("a fixture source reports every snapshot change")
    func sourceReportsChanges() {
        let source = FixtureWindowSource(scenario: .standard)
        var changes = 0
        source.onChange = { changes += 1 }
        source.refresh()
        #expect(changes == 0)
        source.mutate { $0.windows.removeAll() }
        source.snapshot = .empty
        #expect(changes == 2)
        #expect(source.snapshot == .empty)
    }

    @Test("fixture thumbnails answer at once, skip minimized windows and fit the size")
    func thumbnails() throws {
        let source = FixtureWindowSource(scenario: .standard)
        let thumbnails = FixtureThumbnails(source: source)
        let windows = source.snapshot.windows.filter { !$0.isWindowlessApp }
        var delivered: [WindowID: CGImage] = [:]
        thumbnails.requestThumbnails(for: windows, maxPixelSize: 300) { delivered[$0] = $1 }

        #expect(thumbnails.canCapture)
        let minimized = try #require(windows.first(where: \.isMinimized)?.windowID)
        #expect(delivered[minimized] == nil)
        #expect(delivered.count == windows.count - 1)
        for image in delivered.values {
            #expect(max(image.width, image.height) == 300)
        }
        let first = try #require(windows.first?.windowID)
        #expect(thumbnails.cachedThumbnail(for: first) != nil)
        thumbnails.prune(keeping: [])
        #expect(thumbnails.cachedThumbnail(for: first) == nil)
    }

    @Test("fixture icons are cached per app")
    func icons() {
        let icons = FixtureIcons()
        let first = icons.icon(for: FixtureApps.safari)
        #expect(icons.icon(for: FixtureApps.safari) === first)
        #expect(icons.icon(for: FixtureApps.finder) !== first)
        #expect(first.size == NSSize(width: 128, height: 128))
    }

    @Test("recorded close and quit remove items from the catalog")
    func closeAndQuit() throws {
        let source = FixtureWindowSource(scenario: .standard)
        let actions = RecordingWindowActions(source: source)
        let finder = try #require(window(1006, in: source.snapshot))
        actions.close(finder)
        #expect(window(1006, in: source.snapshot) == nil)

        let safari = try #require(window(1003, in: source.snapshot))
        actions.quitApp(safari)
        #expect(!source.snapshot.windows.contains { $0.app.pid == FixtureApps.safari.pid })
        #expect(actions.log == [.close(.window(1006)), .quitApp(FixtureApps.safari.pid)])
    }

    @Test("recorded toggles flip minimized, fullscreen and the app's hidden state")
    func toggles() throws {
        let source = FixtureWindowSource(scenario: .standard)
        let actions = RecordingWindowActions(source: source)
        let soprano = try #require(window(1001, in: source.snapshot))
        actions.toggleMinimize(soprano)
        actions.toggleFullscreen(soprano)
        #expect(window(1001, in: source.snapshot)?.isMinimized == true)
        #expect(window(1001, in: source.snapshot)?.isFullscreen == true)

        let mail = try #require(window(1007, in: source.snapshot))
        actions.toggleHideApp(mail)
        #expect(source.snapshot.windows.filter { $0.app.pid == mail.app.pid }.allSatisfy { !$0.isHidden })
        actions.toggleHideApp(soprano)
        #expect(source.snapshot.windows.filter { $0.app.pid == soprano.app.pid }.allSatisfy { $0.isHidden })
        #expect(actions.log == [
            .toggleMinimize(.window(1001)), .toggleFullscreen(.window(1001)),
            .toggleHideApp(mail.app.pid), .toggleHideApp(soprano.app.pid),
        ])
    }

    @Test("recorded focus ranks the window first and makes its app frontmost")
    func focus() throws {
        let source = FixtureWindowSource(scenario: .standard)
        let actions = RecordingWindowActions(source: source)
        var changes = 0
        source.onChange = { changes += 1 }
        let settings = try #require(window(1009, in: source.snapshot))
        actions.focus(settings)

        let snapshot = source.snapshot
        #expect(changes == 1)
        #expect(window(1009, in: snapshot)?.lastFocusOrder == 0)
        #expect(window(1001, in: snapshot)?.lastFocusOrder == 1)
        #expect(snapshot.windows.map(\.lastFocusOrder).sorted() == Array(0..<snapshot.windows.count))
        #expect(snapshot.frontmostPID == settings.app.pid)
        #expect(snapshot.focusedWindowID == 1009)
        #expect(snapshot.windows.filter(\.app.isActive).allSatisfy { $0.app.pid == settings.app.pid })
        #expect(actions.log == [.focus(.window(1009))])
    }

    @Test("report text names the item kind")
    func reportText() {
        #expect(WindowActionRecord.focus(.window(1003)).reportText == "focus window 1003")
        #expect(WindowActionRecord.focus(.windowlessApp(509)).reportText == "focus app 509")
        #expect(WindowActionRecord.quitApp(502).reportText == "quitApp 502")
    }
}
