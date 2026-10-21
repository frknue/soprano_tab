import AppKit
import Testing
@testable import SopranoTab
@testable import SopranoTabCore

@MainActor
struct SwitcherModelBuilderTests {
    private let layout = TileLayout(
        resolvedSize: .medium, panelSize: .zero, headerFrame: .zero, searchFieldFrame: nil,
        contentFrame: .zero, contentSize: .zero, tileFrames: [], imageFrames: [], titleFrames: [], rows: []
    )

    private func model(
        _ session: SwitcherSession,
        settings: SopranoTabSettings = SopranoTabSettings(),
        style: SwitcherStyle = .thumbnails,
        thumbnail: CGImage? = nil
    ) -> SwitcherViewModel {
        SwitcherModelBuilder.model(
            session: session, layout: layout, settings: settings, theme: AppTheme.folioPaper,
            style: style, snapshot: SwitcherTestDesktop.snapshot(), hoveredIndex: nil,
            thumbnails: { _ in thumbnail }, icons: { _ in NSImage() }
        )
    }

    private func session(_ items: [WindowInfo] = SwitcherTestDesktop.windows) -> SwitcherSession {
        SwitcherSession(items: items, shortcutIndex: 0, focusedWindowID: nil, reverse: false)
    }

    @Test("Titles follow the titles setting and never repeat the app name")
    func titles() {
        let draft = SwitcherTestDesktop.windows[0]
        let untitled = SwitcherTestDesktop.window(9, SwitcherTestDesktop.editor, "  ", focus: 9, z: nil)
        let windowless = WindowInfo(id: .windowlessApp(400), app: AppInfo(pid: 400, bundleID: "test.notes", name: "Notes"), title: "")

        #expect(SwitcherModelBuilder.title(for: draft, content: .windowTitle) == "Draft")
        #expect(SwitcherModelBuilder.title(for: draft, content: .appName) == "Editor")
        #expect(SwitcherModelBuilder.title(for: draft, content: .appNameAndWindowTitle) == "Editor - Draft")
        #expect(SwitcherModelBuilder.title(for: untitled, content: .windowTitle) == "Editor")
        #expect(SwitcherModelBuilder.title(for: untitled, content: .appNameAndWindowTitle) == "Editor")
        #expect(SwitcherModelBuilder.title(for: windowless, content: .appNameAndWindowTitle) == "Notes")
    }

    @Test("The heading names what the shortcut lists, or search, with the count beside it")
    func headings() {
        let snapshot = SwitcherTestDesktop.snapshot()
        func heading(_ apps: AppsFilter, searching: Bool = false, count: Int) -> SwitcherHeading {
            SwitcherModelBuilder.heading(for: WindowFilters(apps: apps), snapshot: snapshot, isSearching: searching, count: count)
        }
        #expect(heading(.all, count: 5) == SwitcherHeading(subject: "All windows", count: 5))
        #expect(heading(.active, count: 2) == SwitcherHeading(subject: "Editor", count: 2))
        #expect(heading(.nonActive, count: 3) == SwitcherHeading(subject: "Other apps", count: 3))
        #expect(heading(.underCursor, count: 3) == SwitcherHeading(subject: "Under the cursor", count: 3))
        // The mouse is over windows 1, 2 and 3; window 1 (Editor) is frontmost.
        #expect(heading(.appUnderCursor, count: 2) == SwitcherHeading(subject: "Editor", count: 2))
        #expect(heading(.active, searching: true, count: 1) == SwitcherHeading(subject: "Search", count: 1))
    }

    @Test("Hints are one keycap per bound key, in order, and drop unbound ones")
    func hints() {
        func pairs(_ hints: [KeyHint]) -> [String] { hints.map { "\($0.key) \($0.label)" } }
        let controls = ControlSettings()
        let shortcut = ShortcutSettings.defaults[0]
        #expect(pairs(SwitcherModelBuilder.hints(controls: controls, shortcut: shortcut, searchHint: true))
            == ["⇥ next", "⇧ back", "↩ open", "W close", "M min", "Q quit", "S search"])
        #expect(pairs(SwitcherModelBuilder.hints(controls: controls, shortcut: shortcut, searchHint: false))
            == ["⇥ next", "⇧ back", "↩ open", "W close", "M min", "Q quit"])

        var sparse = ControlSettings()
        sparse.previous = []
        sparse.close = nil
        sparse.quit = .named(.escape)
        #expect(pairs(SwitcherModelBuilder.hints(controls: sparse, shortcut: nil, searchHint: true))
            == ["↩ open", "M min", "esc quit", "S search"])
    }

    @Test("Chips follow statusIcons and spaceLabels in sentence case")
    func chips() {
        let minimized = SwitcherTestDesktop.windows[3]
        var everywhere = SwitcherTestDesktop.windows[0]
        everywhere.isOnAllSpaces = true
        var secondSpace = SwitcherTestDesktop.windows[1]
        secondSpace.spaceIDs = [2]
        secondSpace.spaceIndexes = [2]
        var hiddenFullscreen = SwitcherTestDesktop.windows[2]
        hiddenFullscreen.app.isHidden = true
        hiddenFullscreen.isFullscreen = true
        let items = [minimized, everywhere, secondSpace, hiddenFullscreen]

        var labeled = SopranoTabSettings()
        labeled.appearance.spaceLabels = true
        #expect(model(session(items), settings: labeled).tiles.map(\.chips) == [
            ["Minimized", "Space 1"],
            ["All Spaces"],
            ["Space 2"],
            ["Hidden", "Full screen", "Space 1"],
        ])

        var bare = SopranoTabSettings()
        bare.appearance.statusIcons = false
        #expect(model(session(items), settings: bare).tiles.map(\.chips) == Array(repeating: [], count: 4))
    }

    @Test("Empty lists say No windows, or No matches while a query is typed")
    func emptyText() {
        let empty = model(session([]))
        #expect(empty.tiles.isEmpty)
        #expect(empty.emptyText == "No windows")
        #expect(empty.heading == SwitcherHeading(subject: "All windows", count: 0))
        #expect(empty.search == nil)

        var searching = session()
        searching.beginSearch()
        searching.setQuery("zzzz")
        let noMatches = model(searching)
        #expect(noMatches.emptyText == "No matches")
        #expect(noMatches.search == SearchFieldState(query: "zzzz", isActive: true))
        #expect(noMatches.heading == SwitcherHeading(subject: "Search", count: 0))

        #expect(model(session()).emptyText == nil)
    }

    @Test("Search hits in the title are highlighted")
    func highlights() {
        var searching = session()
        searching.beginSearch()
        searching.setQuery("dra")
        let tiles = model(searching).tiles
        #expect(tiles.map(\.id) == [.window(1)])
        let covered = Set(tiles[0].highlightedRanges.flatMap { $0.location..<($0.location + $0.length) })
        #expect(covered == [0, 1, 2])

        #expect(model(session()).tiles.allSatisfy { $0.highlightedRanges.isEmpty })
    }

    @Test("Thumbnails reach tiles only in the thumbnails style and never for windowless apps")
    func thumbnailsPerStyle() throws {
        let context = try #require(CGContext(
            data: nil, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ))
        let image = try #require(context.makeImage())
        let windowless = WindowInfo(id: .windowlessApp(400), app: AppInfo(pid: 400, bundleID: "test.notes", name: "Notes"), title: "")
        let items = [SwitcherTestDesktop.windows[0], windowless]

        let thumbnailTiles = model(session(items), style: .thumbnails, thumbnail: image).tiles
        #expect(thumbnailTiles.map { $0.thumbnail != nil } == [true, false])
        #expect(thumbnailTiles.map(\.isWindowlessApp) == [false, true])
        #expect(model(session(items), style: .appIcons, thumbnail: image).tiles.allSatisfy { $0.thumbnail == nil })
    }
}
