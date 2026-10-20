import AppKit
import Testing
@testable import SopranoTab
@testable import SopranoTabCore

@MainActor
struct SwitcherWindowTests {
    private let screen = ScreenInfo(
        id: 1,
        frame: CGRect(x: 0, y: 0, width: 1512, height: 982),
        visibleFrame: CGRect(x: 0, y: 33, width: 1512, height: 949),
        scale: 2
    )

    init() {
        SwitcherWindow.offscreen = true
    }

    @Test("presenting three tiles renders a screen-sized image at the screen's scale")
    func presentRendersScreenSizedSnapshot() throws {
        let window = SwitcherWindow()
        window.present(model(tiles: threeTiles(), selectedIndex: 0), on: screen)

        #expect(window.isPresented)
        #expect(window.tileViews.count == 3)
        let image = try #require(window.renderSnapshot(screen: screen, backdrop: nil))
        #expect(image.width == 3024)
        #expect(image.height == 1964)
    }

    @Test("an update with a new selection reuses the tile views and moves the selection")
    func selectionUpdateReusesTiles() {
        let window = SwitcherWindow()
        window.present(model(tiles: threeTiles(), selectedIndex: 0), on: screen)
        let before = window.tileViews
        #expect(before.map(\.isSelected) == [true, false, false])

        window.update(model(tiles: threeTiles(), selectedIndex: 2))

        #expect(window.tileViews.count == 3)
        #expect(zip(before, window.tileViews).allSatisfy { $0 === $1 })
        #expect(window.tileViews.map(\.isSelected) == [false, false, true])
    }

    @Test("hover shows a window's close, minimize and fullscreen lamps, and a windowless app's quit lamp alone")
    func controlsFollowHover() {
        let window = SwitcherWindow()
        window.present(model(tiles: threeTiles(), selectedIndex: 0, hoveredIndex: 1), on: screen)
        #expect(window.tileViews.map(\.controls) == [[], [.close, .minimize, .fullscreen], []])

        window.update(model(tiles: threeTiles(), selectedIndex: 0, hoveredIndex: 2))
        #expect(window.tileViews.map(\.controls) == [[], [], [.quit]])

        // The lone quit lamp starts the title strip (tile-local (6, 4, w − 12, 18), flipped),
        // like macOS window buttons.
        let windowless = window.tileViews[2]
        let lampCenter = CGPoint(x: 6 + TileView.lampSide / 2, y: 4 + 18 / 2)
        #expect(windowless.control(at: lampCenter) == .quit)
    }

    @Test("tiles read as title and app name to VoiceOver")
    func tilesHaveAccessibilityLabels() {
        let window = SwitcherWindow()
        window.present(model(tiles: threeTiles(), selectedIndex: 0), on: screen)

        #expect(window.tileViews.first?.accessibilityLabel() == "main.swift, Soprano")
    }

    @Test("an empty model renders the empty state")
    func emptyModelRenders() throws {
        let window = SwitcherWindow()
        window.present(model(tiles: [], selectedIndex: nil, emptyText: "no windows"), on: screen)

        #expect(window.tileViews.isEmpty)
        let image = try #require(window.renderSnapshot(screen: screen, backdrop: nil))
        #expect(image.width == 3024)
    }

    @Test("dismissing hides the panel and stops snapshots")
    func dismissStopsSnapshots() {
        let window = SwitcherWindow()
        window.present(model(tiles: threeTiles(), selectedIndex: 0), on: screen)

        window.dismiss(animated: true)

        #expect(!window.isPresented)
        #expect(window.renderSnapshot(screen: screen, backdrop: nil) == nil)
    }

    // MARK: - Fixtures

    private func threeTiles() -> [TileViewModel] {
        [
            tile(.window(1), title: "main.swift", app: "Soprano", thumbnail: solidImage()),
            tile(.window(2), title: "Inbox", app: "Mail", thumbnail: nil),
            tile(.windowlessApp(30), title: "Notes", app: "Notes", thumbnail: nil, windowless: true),
        ]
    }

    private func tile(_ id: ItemID, title: String, app: String, thumbnail: CGImage?, windowless: Bool = false) -> TileViewModel {
        TileViewModel(
            id: id,
            title: title,
            highlightedRanges: [],
            appName: app,
            icon: nil,
            thumbnail: thumbnail,
            badges: TileBadges(),
            isWindowlessApp: windowless
        )
    }

    private func model(
        tiles: [TileViewModel],
        selectedIndex: Int?,
        hoveredIndex: Int? = nil,
        emptyText: String? = nil
    ) -> SwitcherViewModel {
        let layout = TileLayout.compute(TileLayoutInput(
            style: .thumbnails,
            size: .auto,
            screenSize: screen.visibleFrame.size,
            itemSizes: tiles.map { _ in CGSize(width: 1200, height: 800) }
        ))
        return SwitcherViewModel(
            theme: .missionControl,
            style: .thumbnails,
            layout: layout,
            tiles: tiles,
            selectedIndex: selectedIndex,
            hoveredIndex: hoveredIndex,
            heading: "all windows · \(tiles.count)",
            hints: "⇥ next  ⇧ back",
            search: nil,
            showsWindowControls: true,
            titleTruncation: .end,
            emptyText: emptyText
        )
    }

    private func solidImage() -> CGImage? {
        let context = CGContext(
            data: nil, width: 120, height: 80, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )
        context?.setFillColor(CGColor(red: 0.2, green: 0.4, blue: 0.8, alpha: 1))
        context?.fill(CGRect(x: 0, y: 0, width: 120, height: 80))
        return context?.makeImage()
    }
}
