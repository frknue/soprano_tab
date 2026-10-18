import AppKit
import Testing
@testable import SopranoTabCore

/// Deterministic generator so the invariant sweep is reproducible.
private struct SplitMix64: RandomNumberGenerator {
    var state: UInt64

    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}

struct TileLayoutTests {
    private func layout(
        _ style: SwitcherStyle,
        _ size: SwitcherSize,
        screen: CGSize = CGSize(width: 1000, height: 1000),
        items: [CGSize],
        search: Bool = false
    ) -> TileLayout {
        TileLayout.compute(TileLayoutInput(style: style, size: size, screenSize: screen, itemSizes: items, showsSearchField: search))
    }

    private func isIntegral(_ rect: CGRect) -> Bool {
        [rect.origin.x, rect.origin.y, rect.width, rect.height].allSatisfy { $0 == $0.rounded() }
    }

    @Test("random inputs keep every layout invariant")
    func invariants() {
        var random = SplitMix64(state: 0x50_9A_A0)
        for _ in 0..<400 {
            let style = SwitcherStyle.allCases.randomElement(using: &random)!
            let size = SwitcherSize.allCases.randomElement(using: &random)!
            let screen = CGSize(
                width: CGFloat(Int.random(in: 800...3000, using: &random)) + (Bool.random(using: &random) ? 0.5 : 0),
                height: CGFloat(Int.random(in: 600...1800, using: &random))
            )
            let count = Int.random(in: 0...60, using: &random)
            let items = (0..<count).map { _ in
                Int.random(in: 0..<8, using: &random) == 0
                    ? CGSize.zero
                    : CGSize(width: Int.random(in: 1...4000, using: &random), height: Int.random(in: 1...3000, using: &random))
            }
            let search = Bool.random(using: &random)
            let result = layout(style, size, screen: screen, items: items, search: search)
            let context = "\(style) \(size) \(screen) n=\(count) search=\(search)"

            #expect(result.resolvedSize != .auto, "\(context)")
            #expect(result.tileFrames.count == count && result.imageFrames.count == count && result.titleFrames.count == count, "\(context)")
            #expect(result.rows.flatMap { Array($0) } == Array(0..<count), "\(context)")
            #expect(result.rows.allSatisfy { !$0.isEmpty }, "\(context)")

            #expect(result.panelSize.width <= (screen.width * 0.9).rounded(.down), "\(context)")
            #expect(result.panelSize.height <= (screen.height * 0.8).rounded(.down), "\(context)")
            #expect(result.panelSize.width >= 360, "\(context)")
            #expect(result.panelSize.width == result.panelSize.width.rounded(), "\(context)")
            #expect(result.panelSize.height == result.panelSize.height.rounded(), "\(context)")
            #expect(result.contentFrame.maxY + 16 == result.panelSize.height, "\(context)")
            #expect(result.contentFrame.width == result.contentSize.width, "\(context)")
            #expect(result.contentFrame.height <= result.contentSize.height, "\(context)")
            #expect(result.contentFrame.minY >= result.headerFrame.maxY, "\(context)")
            #expect((result.searchFieldFrame != nil) == search, "\(context)")

            let content = CGRect(origin: .zero, size: result.contentSize)
            let misplaced = result.tileFrames.indices.filter { index in
                let tile = result.tileFrames[index]
                let bounds = CGRect(origin: .zero, size: tile.size)
                let image = result.imageFrames[index]
                let title = result.titleFrames[index]
                return !(isIntegral(tile) && content.contains(tile)
                    && isIntegral(image) && bounds.contains(image)
                    && isIntegral(title) && bounds.contains(title))
            }
            #expect(misplaced.isEmpty, "\(context): tiles \(misplaced) not integral or not inside")
            let chrome = [result.headerFrame, result.contentFrame] + [result.searchFieldFrame].compactMap { $0 }
            #expect(chrome.allSatisfy(isIntegral), "\(context): \(chrome)")
            var overlapping: [(Int, Int)] = []
            for i in result.tileFrames.indices {
                for j in result.tileFrames.indices where j > i {
                    let overlap = result.tileFrames[i].intersection(result.tileFrames[j])
                    if !overlap.isNull, overlap.width > 0, overlap.height > 0 { overlapping.append((i, j)) }
                }
            }
            #expect(overlapping.isEmpty, "\(context): overlapping tiles \(overlapping)")
        }
    }

    @Test("auto picks the large size when few items fit")
    func autoFewItems() {
        let few = Array(repeating: CGSize(width: 1600, height: 1000), count: 3)
        #expect(layout(.thumbnails, .auto, items: few).resolvedSize == .large)
        #expect(layout(.appIcons, .auto, items: few).resolvedSize == .large)
        #expect(layout(.titles, .auto, items: few).resolvedSize == .large)
    }

    @Test("auto steps down to the largest size that fits without scrolling")
    func autoMedium() {
        // 1000 × 1000: 736 pt of content; 20 rows fit at 34 pt but not at 40 pt.
        let result = layout(.titles, .auto, items: Array(repeating: .zero, count: 20))
        #expect(result.resolvedSize == .medium)
        #expect(result.contentSize.height == result.contentFrame.height)
    }

    @Test("auto falls back to small and scrolls when nothing fits")
    func autoManyItems() {
        let many = Array(repeating: CGSize(width: 1600, height: 1000), count: 200)
        for style in SwitcherStyle.allCases {
            let result = layout(style, .auto, items: many)
            #expect(result.resolvedSize == .small, "\(style)")
            #expect(result.contentSize.height > result.contentFrame.height, "\(style)")
        }
    }

    @Test("overflowing rows scroll: the panel stops growing and the content holds every row")
    func scrolling() {
        let result = layout(.titles, .small, items: Array(repeating: .zero, count: 100))
        #expect(result.contentFrame.height == 736)
        #expect(result.contentSize.height == 2800)
        #expect(result.panelSize.height == 800)
        #expect(result.tileFrames.last == CGRect(x: 0, y: 2772, width: 420, height: 28))
    }

    @Test("thumbnail tiles follow the window's aspect within 0.625…2 and at least 140 wide")
    func thumbnailMetrics() {
        // 1000 × 1000 screen: 736 pt of content height, large = 3 rows of 240.
        let sizes = [CGSize(width: 1600, height: 1000), .zero, CGSize(width: 500, height: 1000), CGSize(width: 4000, height: 1000)]
        let large = layout(.thumbnails, .large, items: sizes)
        #expect(large.tileFrames.map(\.size) == [
            CGSize(width: 344, height: 240), CGSize(width: 344, height: 240),
            CGSize(width: 142, height: 240), CGSize(width: 428, height: 240),
        ])
        #expect(large.imageFrames[0] == CGRect(x: 6, y: 26, width: 332, height: 208))
        #expect(large.titleFrames[0] == CGRect(x: 6, y: 4, width: 332, height: 18))

        let small = layout(.thumbnails, .small, items: [CGSize(width: 500, height: 1000)])
        #expect(small.tileFrames[0].size == CGSize(width: 140, height: 116))
        #expect(small.imageFrames[0] == CGRect(x: 6, y: 26, width: 128, height: 84))
    }

    @Test("thumbnail rows fill greedily and each row is centered in the widest row")
    func thumbnailRows() {
        let result = layout(.thumbnails, .large, items: Array(repeating: CGSize(width: 1600, height: 1000), count: 5))
        #expect(result.rows == [0..<2, 2..<4, 4..<5])
        #expect(result.contentSize == CGSize(width: 696, height: 736))
        #expect(result.panelSize.width == 728)
        #expect(result.tileFrames[1] == CGRect(x: 352, y: 0, width: 344, height: 240))
        #expect(result.tileFrames[4] == CGRect(x: 176, y: 496, width: 344, height: 240))
    }

    @Test("app icon tiles wrap the icon with a title below")
    func appIconMetrics() {
        let medium = layout(.appIcons, .medium, items: [.zero])
        #expect(medium.tileFrames == [CGRect(x: 104, y: 0, width: 120, height: 136)])
        #expect(medium.imageFrames == [CGRect(x: 12, y: 8, width: 96, height: 96)])
        #expect(medium.titleFrames == [CGRect(x: 4, y: 110, width: 112, height: 18)])
        #expect(medium.panelSize.width == 360)
        #expect(layout(.appIcons, .small, items: [.zero]).tileFrames[0].size == CGSize(width: 88, height: 104))
        #expect(layout(.appIcons, .large, items: [.zero]).tileFrames[0].size == CGSize(width: 152, height: 168))
    }

    @Test("title rows are one per line, sized from the screen width within 420…1100")
    func titleMetrics() {
        let wide = layout(.titles, .large, screen: CGSize(width: 2000, height: 1200), items: [.zero, .zero])
        #expect(wide.tileFrames == [CGRect(x: 0, y: 0, width: 1100, height: 40), CGRect(x: 0, y: 40, width: 1100, height: 40)])
        #expect(wide.rows == [0..<1, 1..<2])
        #expect(wide.imageFrames[0] == CGRect(x: 8, y: 4, width: 32, height: 32))
        #expect(wide.titleFrames[0] == CGRect(x: 48, y: 11, width: 1044, height: 18))

        let narrow = layout(.titles, .small, screen: CGSize(width: 800, height: 800), items: [.zero])
        #expect(narrow.tileFrames[0].size == CGSize(width: 420, height: 28))
        #expect(narrow.imageFrames[0] == CGRect(x: 8, y: 4, width: 20, height: 20))
        #expect(narrow.titleFrames[0] == CGRect(x: 36, y: 5, width: 376, height: 18))

        let medium = layout(.titles, .medium, screen: CGSize(width: 1200, height: 800), items: [.zero])
        #expect(medium.tileFrames[0].size == CGSize(width: 600, height: 34))
    }

    @Test("the search strip sits below the header and pushes the content down")
    func searchStrip() {
        let plain = layout(.thumbnails, .large, items: [.zero])
        #expect(plain.headerFrame == CGRect(x: 16, y: 16, width: 344, height: 24))
        #expect(plain.searchFieldFrame == nil)
        #expect(plain.contentFrame.origin == CGPoint(x: 16, y: 48))

        let searching = layout(.thumbnails, .large, items: [.zero], search: true)
        // Shorter tiles are narrower, so the panel falls back to its 360 pt minimum.
        #expect(searching.searchFieldFrame == CGRect(x: 16, y: 48, width: 328, height: 30))
        #expect(searching.contentFrame.origin == CGPoint(x: 16, y: 86))
        // 800 − 86 − 16 = 698 pt of content: (698 − 16) / 3 = 227.
        #expect(searching.tileFrames[0].height == 227)
    }

    @Test("no items give an 80 pt content area at the minimum width")
    func emptyList() {
        let result = layout(.thumbnails, .auto, items: [])
        #expect(result.resolvedSize == .large)
        #expect(result.tileFrames.isEmpty && result.rows.isEmpty)
        #expect(result.panelSize == CGSize(width: 360, height: 144))
        #expect(result.contentFrame == CGRect(x: 16, y: 48, width: 328, height: 80))
        #expect(layout(.titles, .small, items: []).resolvedSize == .small)
    }
}
