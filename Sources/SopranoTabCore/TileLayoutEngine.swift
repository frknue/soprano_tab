import CoreGraphics
import Foundation

extension TileLayout {
    /// Lays out the panel for `input` (docs/ARCHITECTURE.md → Layout). Every frame is
    /// integral; the panel stays within 90% × 80% of the screen and is at least 360 wide
    /// (unless 90% of the screen is narrower). Rows that do not fit scroll inside
    /// `contentFrame`; `.auto` picks the largest size that fits without scrolling.
    public static func compute(_ input: TileLayoutInput) -> TileLayout {
        let frame = PanelFrame(screenSize: input.screenSize, showsSearchField: input.showsSearchField)
        guard !input.itemSizes.isEmpty else {
            let resolved = input.size == .auto ? SwitcherSize.large : input.size
            return frame.layout(resolvedSize: resolved, tiles: TileGrid(), contentHeight: TileMetrics.emptyContentHeight)
        }
        let resolved: SwitcherSize
        if input.size == .auto {
            let fitting = [SwitcherSize.large, .medium, .small].first { size in
                TileGrid(input: input, size: size, frame: frame).height <= frame.maxContentHeight
            }
            resolved = fitting ?? .small
        } else {
            resolved = input.size
        }
        let grid = TileGrid(input: input, size: resolved, frame: frame)
        return frame.layout(resolvedSize: resolved, tiles: grid, contentHeight: min(grid.height, frame.maxContentHeight))
    }
}

/// Fixed metrics, in points.
private enum TileMetrics {
    static let padding: CGFloat = 16
    static let headerHeight: CGFloat = 24
    static let searchHeight: CGFloat = 30
    static let stripGap: CGFloat = 8
    static let spacing: CGFloat = 8
    static let minPanelWidth: CGFloat = 360
    static let emptyContentHeight: CGFloat = 80
    static let defaultAspect: CGFloat = 16.0 / 10.0
    static let aspectRange: ClosedRange<CGFloat> = 0.625...2.0
    static let minThumbnailWidth: CGFloat = 140
    /// Title strip (4 + 18 + 4) plus the image's 6 pt bottom inset, plus 1 pt of image.
    static let minThumbnailHeight: CGFloat = 33

    static func thumbnailRows(_ size: SwitcherSize) -> Int {
        switch size {
        case .small, .auto: 6
        case .medium: 4
        case .large: 3
        }
    }

    static func iconSide(_ size: SwitcherSize) -> CGFloat {
        switch size {
        case .small, .auto: 64
        case .medium: 96
        case .large: 128
        }
    }

    static func titleRowHeight(_ size: SwitcherSize) -> CGFloat {
        switch size {
        case .small, .auto: 28
        case .medium: 34
        case .large: 40
        }
    }

    static func titleWidthFraction(_ size: SwitcherSize) -> CGFloat {
        switch size {
        case .small, .auto: 0.4
        case .medium: 0.5
        case .large: 0.6
        }
    }
}

/// The panel's chrome for one screen: the size limits and the strips above the content.
private struct PanelFrame {
    let maxPanelWidth: CGFloat
    let maxPanelHeight: CGFloat
    let maxContentWidth: CGFloat
    let maxContentHeight: CGFloat
    /// Panel y of the content area.
    let contentTop: CGFloat
    let showsSearchField: Bool

    init(screenSize: CGSize, showsSearchField: Bool) {
        let padding = TileMetrics.padding
        maxPanelWidth = max((screenSize.width * 0.9).rounded(.down), 0)
        maxPanelHeight = max((screenSize.height * 0.8).rounded(.down), 0)
        var top = padding + TileMetrics.headerHeight + TileMetrics.stripGap
        if showsSearchField { top += TileMetrics.searchHeight + TileMetrics.stripGap }
        contentTop = top
        self.showsSearchField = showsSearchField
        maxContentWidth = max(maxPanelWidth - 2 * padding, 1)
        maxContentHeight = max(maxPanelHeight - top - padding, 1)
    }

    /// Content width: the widest row, widened to the minimum panel width, capped at 90%.
    func contentWidth(rowWidth: CGFloat) -> CGFloat {
        let wanted = max(rowWidth, TileMetrics.minPanelWidth - 2 * TileMetrics.padding)
        return min(wanted, maxContentWidth)
    }

    func layout(resolvedSize: SwitcherSize, tiles: TileGrid, contentHeight: CGFloat) -> TileLayout {
        let padding = TileMetrics.padding
        let width = contentWidth(rowWidth: tiles.widestRow)
        let panelSize = CGSize(width: width + 2 * padding, height: contentTop + contentHeight + padding)
        let header = CGRect(x: padding, y: padding, width: width, height: TileMetrics.headerHeight)
        let search = showsSearchField
            ? CGRect(x: padding, y: header.maxY + TileMetrics.stripGap, width: width, height: TileMetrics.searchHeight)
            : nil
        return TileLayout(
            resolvedSize: resolvedSize,
            panelSize: panelSize,
            headerFrame: header,
            searchFieldFrame: search,
            contentFrame: CGRect(x: padding, y: contentTop, width: width, height: contentHeight),
            contentSize: CGSize(width: width, height: tiles.items.isEmpty ? contentHeight : tiles.height),
            tileFrames: tiles.centered(in: width),
            imageFrames: tiles.items.map(\.image),
            titleFrames: tiles.items.map(\.title),
            rows: tiles.rows
        )
    }
}

/// Tiles packed into rows, before horizontal centering.
private struct TileGrid {
    struct Item {
        var size: CGSize
        var image: CGRect
        var title: CGRect
    }

    var items: [Item] = []
    var rows: [Range<Int>] = []
    var rowWidths: [CGFloat] = []
    var rowHeight: CGFloat = 0
    var rowSpacing: CGFloat = 0
    var columnSpacing: CGFloat = 0

    init() {}

    init(input: TileLayoutInput, size: SwitcherSize, frame: PanelFrame) {
        switch input.style {
        case .thumbnails:
            let rowsPerScreen = CGFloat(TileMetrics.thumbnailRows(size))
            let fill = (frame.maxContentHeight - (rowsPerScreen - 1) * TileMetrics.spacing) / rowsPerScreen
            let height = max(fill.rounded(.down), TileMetrics.minThumbnailHeight)
            let imageHeight = height - 32
            items = input.itemSizes.map { itemSize in
                let aspect = Self.aspect(of: itemSize)
                let natural = (imageHeight * aspect).rounded(.down) + 12
                let width = min(max(natural, TileMetrics.minThumbnailWidth), frame.maxContentWidth.rounded(.down))
                return Item(
                    size: CGSize(width: width, height: height),
                    image: CGRect(x: 6, y: 26, width: width - 12, height: imageHeight),
                    title: CGRect(x: 6, y: 4, width: width - 12, height: 18)
                )
            }
            pack(rowHeight: height, spacing: TileMetrics.spacing, maxWidth: frame.maxContentWidth)
        case .appIcons:
            let icon = TileMetrics.iconSide(size)
            let width = icon + 24
            let height = 8 + icon + 6 + 18 + 8
            let item = Item(
                size: CGSize(width: width, height: height),
                image: CGRect(x: 12, y: 8, width: icon, height: icon),
                title: CGRect(x: 4, y: 8 + icon + 6, width: width - 8, height: 18)
            )
            items = Array(repeating: item, count: input.itemSizes.count)
            pack(rowHeight: height, spacing: TileMetrics.spacing, maxWidth: frame.maxContentWidth)
        case .titles:
            let height = TileMetrics.titleRowHeight(size)
            let natural = min(max(input.screenSize.width * TileMetrics.titleWidthFraction(size), 420), 1100)
            let width = min(natural, frame.maxContentWidth).rounded(.down)
            let titleX = 8 + (height - 8) + 8
            let item = Item(
                size: CGSize(width: width, height: height),
                image: CGRect(x: 8, y: 4, width: height - 8, height: height - 8),
                title: CGRect(x: titleX, y: ((height - 18) / 2).rounded(.down), width: max(width - titleX - 8, 0), height: 18)
            )
            items = Array(repeating: item, count: input.itemSizes.count)
            rowHeight = height
            rows = items.indices.map { $0..<($0 + 1) }
            rowWidths = Array(repeating: width, count: items.count)
        }
    }

    /// Total content height of every row.
    var height: CGFloat {
        guard !rows.isEmpty else { return 0 }
        return CGFloat(rows.count) * rowHeight + CGFloat(rows.count - 1) * rowSpacing
    }

    var widestRow: CGFloat { rowWidths.max() ?? 0 }

    /// Window aspect clamped to 0.625…2.0; `.zero` and degenerate sizes count as 16:10.
    private static func aspect(of size: CGSize) -> CGFloat {
        guard size.width > 0, size.height > 0 else { return TileMetrics.defaultAspect }
        let range = TileMetrics.aspectRange
        return min(max(size.width / size.height, range.lowerBound), range.upperBound)
    }

    /// Greedy left-to-right rows: a tile starts a new row when it would exceed `maxWidth`.
    private mutating func pack(rowHeight: CGFloat, spacing: CGFloat, maxWidth: CGFloat) {
        self.rowHeight = rowHeight
        rowSpacing = spacing
        columnSpacing = spacing
        var start = 0
        var width: CGFloat = 0
        for (index, item) in items.enumerated() {
            let widened = index == start ? item.size.width : width + spacing + item.size.width
            if index > start, widened > maxWidth {
                rows.append(start..<index)
                rowWidths.append(width)
                start = index
                width = item.size.width
            } else {
                width = widened
            }
        }
        rows.append(start..<items.count)
        rowWidths.append(width)
    }

    /// Tile frames in content coordinates, each row centered in `contentWidth`.
    func centered(in contentWidth: CGFloat) -> [CGRect] {
        var frames: [CGRect] = []
        frames.reserveCapacity(items.count)
        for (rowIndex, row) in rows.enumerated() {
            let y = CGFloat(rowIndex) * (rowHeight + rowSpacing)
            var x = max(((contentWidth - rowWidths[rowIndex]) / 2).rounded(.down), 0)
            for index in row {
                let size = items[index].size
                frames.append(CGRect(x: x, y: y, width: size.width, height: size.height))
                x += size.width + columnSpacing
            }
        }
        return frames
    }
}
