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

    @Test("hover shows a window's close, minimize and full-screen controls, and a windowless app's quit control alone")
    func controlsFollowHover() {
        let window = SwitcherWindow()
        window.present(model(tiles: threeTiles(), selectedIndex: 0, hoveredIndex: 1), on: screen)
        #expect(window.tileViews.map(\.controls) == [[], [.close, .minimize, .fullscreen], []])

        window.update(model(tiles: threeTiles(), selectedIndex: 0, hoveredIndex: 2))
        #expect(window.tileViews.map(\.controls) == [[], [], [.quit]])

        // The lone quit lamp sits on the corner chip at the image's top-left (image at
        // tile-local (6, 22), chip padding 8 × 6), so the title keeps its full width.
        let windowless = window.tileViews[2]
        let padding = TileView.lampChipPadding
        let lampCenter = CGPoint(x: 6 + padding.width + TileView.lampSide / 2, y: 22 + padding.height + TileView.lampSide / 2)
        #expect(windowless.control(at: lampCenter) == .quit)
        #expect(windowless.control(at: CGPoint(x: 6 + TileView.lampSide / 2, y: 11)) == nil)
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
        window.present(model(tiles: [], selectedIndex: nil, emptyText: "No windows"), on: screen)

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

    @Test("only the selected thumbnail or app-icon tile shows the ring; title rows never do")
    func ringFollowsSelection() {
        let window = SwitcherWindow()
        window.present(model(tiles: threeTiles(), selectedIndex: 1, hoveredIndex: 0), on: screen)
        #expect(window.tileViews.map(\.showsSelectionRing) == [false, true, false])

        window.update(model(tiles: threeTiles(), selectedIndex: 0, style: .appIcons))
        #expect(window.tileViews.map(\.showsSelectionRing) == [true, false, false])

        window.update(model(tiles: threeTiles(), selectedIndex: 0, style: .titles))
        #expect(window.tileViews.map(\.showsSelectionRing) == [false, false, false])
    }

    @Test("titles are muted at rest, ink when hovered, ink Medium when selected, muted for windowless apps")
    func titleFollowsState() {
        let colors = AppTheme.folioPaper.colors
        let window = SwitcherWindow()
        let tiles = threeTiles() + [tile(.window(4), title: "Draft", app: "Editor", thumbnail: nil)]
        window.present(model(tiles: tiles, selectedIndex: 0, hoveredIndex: 1), on: screen)

        func look(_ index: Int) -> (color: NSColor?, font: NSFont?) {
            let text = window.tileViews[index].titleText
            return (text.attribute(.foregroundColor, at: 0, effectiveRange: nil) as? NSColor,
                    text.attribute(.font, at: 0, effectiveRange: nil) as? NSFont)
        }
        #expect(look(0).color == colors.textPrimary && look(0).font == ChromeFont.labelStrong)
        #expect(look(1).color == colors.textPrimary && look(1).font == ChromeFont.label)
        #expect(look(2).color == colors.textMuted)
        #expect(look(3).color == colors.textMuted && look(3).font == ChromeFont.label)
    }

    @Test("search hits are Semibold, matchOnSelection on the selected tile and ink elsewhere")
    func searchHitsFollowSelection() {
        let colors = AppTheme.folioPaper.colors
        let hit = [NSRange(location: 0, length: 2)]
        let tiles = [
            tile(.window(1), title: "main.swift", app: "Soprano", thumbnail: nil, highlights: hit),
            tile(.window(2), title: "makefile", app: "Editor", thumbnail: nil, highlights: hit),
        ]
        let window = SwitcherWindow()
        window.present(model(tiles: tiles, selectedIndex: 0), on: screen)

        func hitLook(_ index: Int) -> (color: NSColor?, font: NSFont?) {
            let text = window.tileViews[index].titleText
            return (text.attribute(.foregroundColor, at: 0, effectiveRange: nil) as? NSColor,
                    text.attribute(.font, at: 0, effectiveRange: nil) as? NSFont)
        }
        let semibold = ChromeFont.sans(size: 12, weight: .semibold)
        #expect(hitLook(0).color == colors.matchOnSelection && hitLook(0).font == semibold)
        #expect(hitLook(1).color == colors.textPrimary && hitLook(1).font == semibold)
        let rest = window.tileViews[1].titleText.attribute(.foregroundColor, at: 3, effectiveRange: nil) as? NSColor
        #expect(rest == colors.textMuted)
    }

    // MARK: - Fixtures

    private func threeTiles() -> [TileViewModel] {
        [
            tile(.window(1), title: "main.swift", app: "Soprano", thumbnail: solidImage()),
            tile(.window(2), title: "Inbox", app: "Mail", thumbnail: nil),
            tile(.windowlessApp(30), title: "Notes", app: "Notes", thumbnail: nil, windowless: true),
        ]
    }

    private func tile(
        _ id: ItemID, title: String, app: String, thumbnail: CGImage?, windowless: Bool = false,
        highlights: [NSRange] = []
    ) -> TileViewModel {
        TileViewModel(
            id: id,
            title: title,
            highlightedRanges: highlights,
            appName: app,
            icon: nil,
            thumbnail: thumbnail,
            chips: [],
            isWindowlessApp: windowless
        )
    }

    private func model(
        tiles: [TileViewModel],
        selectedIndex: Int?,
        hoveredIndex: Int? = nil,
        style: SwitcherStyle = .thumbnails,
        emptyText: String? = nil
    ) -> SwitcherViewModel {
        let layout = TileLayout.compute(TileLayoutInput(
            style: style,
            size: .auto,
            screenSize: screen.visibleFrame.size,
            itemSizes: tiles.map { _ in CGSize(width: 1200, height: 800) }
        ))
        return SwitcherViewModel(
            theme: .folioPaper,
            style: style,
            layout: layout,
            tiles: tiles,
            selectedIndex: selectedIndex,
            hoveredIndex: hoveredIndex,
            heading: SwitcherHeading(subject: "All windows", count: tiles.count),
            hints: [KeyHint(key: "⇥", label: "next"), KeyHint(key: "⇧", label: "back")],
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
