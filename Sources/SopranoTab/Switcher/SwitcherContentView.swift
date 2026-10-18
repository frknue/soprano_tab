import AppKit
import SopranoTabCore

/// The switcher panel's root view: header, search strip, the scrollable tile area and the
/// empty state, placed at the `TileLayout` frames (top-left origin, like the layout).
final class SwitcherContentView: FlippedView {
    let header = SwitcherHeaderView()
    let searchStrip = SearchStripView()
    private let scrollView = NSScrollView()
    private let tileContainer = TileContainerView()
    private let emptyLabel = SwitcherText.label()

    var onHover: ((Int?) -> Void)? {
        get { tileContainer.onHover }
        set { tileContainer.onHover = newValue }
    }

    var onClick: ((Int) -> Void)?
    var onControl: ((Int, TileControl) -> Void)?

    /// The tile views in item order; reused across updates.
    var tileViews: [TileView] { tileContainer.tiles }

    init() {
        super.init(frame: .zero)
        scrollView.drawsBackground = false
        scrollView.borderType = .noBorder
        // No scroller chrome: rows scroll with the wheel and follow the selection.
        scrollView.hasVerticalScroller = false
        scrollView.hasHorizontalScroller = false
        scrollView.verticalScrollElasticity = .none
        scrollView.contentView.drawsBackground = false
        scrollView.documentView = tileContainer
        emptyLabel.alignment = .center
        addSubview(header)
        addSubview(searchStrip)
        addSubview(scrollView)
        addSubview(emptyLabel)
        setAccessibilityRole(.group)
        setAccessibilityLabel("Window switcher")
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    /// Draws `model`; existing tile views are reconfigured in place.
    func apply(_ model: SwitcherViewModel, scale: CGFloat, searchFocused: Bool) {
        let colors = model.theme.colors
        let layout = model.layout
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        setFrameSize(layout.panelSize)
        layer?.backgroundColor = colors.bgBase.withAlphaComponent(0.97).cgColor
        layer?.borderColor = colors.borderStrong.cgColor
        layer?.borderWidth = Retro.hairline
        layer?.cornerRadius = Retro.cornerRadius

        header.frame = layout.headerFrame
        header.configure(heading: model.heading, hints: model.hints, colors: colors)

        if let search = model.search, let frame = layout.searchFieldFrame {
            searchStrip.isHidden = false
            searchStrip.frame = frame
            searchStrip.configure(state: search, focused: searchFocused, colors: colors)
        } else {
            searchStrip.isHidden = true
        }

        scrollView.frame = layout.contentFrame
        tileContainer.setFrameSize(NSSize(
            width: max(layout.contentSize.width, layout.contentFrame.width),
            height: max(layout.contentSize.height, layout.contentFrame.height)
        ))
        applyTiles(model, scale: scale)

        if model.tiles.isEmpty {
            let font = RetroFont.display(22)
            emptyLabel.isHidden = false
            emptyLabel.attributedStringValue = RetroText.display(
                model.emptyText ?? "", color: colors.textMuted, size: 22, alignment: .center
            )
            emptyLabel.frame = SwitcherText.lineFrame(
                minX: layout.contentFrame.minX,
                maxX: layout.contentFrame.maxX,
                centerY: layout.contentFrame.midY,
                font: font
            )
        } else {
            emptyLabel.isHidden = true
        }
        CATransaction.commit()
        scrollSelectionIntoView(model)
    }

    private func applyTiles(_ model: SwitcherViewModel, scale: CGFloat) {
        let layout = model.layout
        let count = min(model.tiles.count, layout.tileFrames.count, layout.imageFrames.count, layout.titleFrames.count)
        tileContainer.ensureTileCount(count) { [weak self] tile in
            tile.onClick = { index in self?.onClick?(index) }
            tile.onControl = { index, control in self?.onControl?(index, control) }
        }
        for index in 0..<count {
            tileContainer.tiles[index].configure(
                model.tiles[index],
                index: index,
                style: model.style,
                frame: layout.tileFrames[index],
                imageFrame: layout.imageFrames[index],
                titleFrame: layout.titleFrames[index],
                isSelected: index == model.selectedIndex,
                isHovered: index == model.hoveredIndex,
                showsWindowControls: model.showsWindowControls,
                theme: model.theme,
                truncation: model.titleTruncation,
                scale: scale
            )
        }
    }

    /// Swaps one tile's thumbnail.
    func updateThumbnail(_ image: CGImage, at index: Int) {
        guard tileViews.indices.contains(index) else { return }
        tileViews[index].setThumbnail(image)
    }

    private func scrollSelectionIntoView(_ model: SwitcherViewModel) {
        guard let selected = model.selectedIndex, model.layout.tileFrames.indices.contains(selected) else {
            return
        }
        let frame = model.layout.tileFrames[selected]
        let visible = scrollView.contentView.bounds
        guard frame.minY < visible.minY || frame.maxY > visible.maxY else { return }
        // Keep the selected row whole in view, moving as little as possible.
        let y = frame.minY < visible.minY ? frame.minY : frame.maxY - visible.height
        let maxY = max(0, tileContainer.frame.height - visible.height)
        scrollView.contentView.scroll(to: NSPoint(x: 0, y: min(max(0, y), maxY)))
        scrollView.reflectScrolledClipView(scrollView.contentView)
    }

    /// Renders the panel's layer tree into `context` with its top-left corner at `origin`
    /// (`context` uses a bottom-left origin). Works for a panel that was never on screen:
    /// `cacheDisplay` makes AppKit build and draw every view's layer, then Core Animation
    /// renders the tree (layer fills, borders, lamps and thumbnail layers included).
    func render(in context: CGContext, at origin: CGPoint) {
        layoutSubtreeIfNeeded()
        if let rep = bitmapImageRepForCachingDisplay(in: bounds) {
            cacheDisplay(in: bounds, to: rep)
        }
        guard let layer else { return }
        context.saveGState()
        context.setShadow(offset: CGSize(width: 0, height: -10), blur: 30, color: NSColor.black.withAlphaComponent(0.55).cgColor)
        context.beginTransparencyLayer(auxiliaryInfo: nil)
        context.translateBy(x: origin.x, y: origin.y)
        if layer.isGeometryFlipped {
            context.translateBy(x: 0, y: bounds.height)
            context.scaleBy(x: 1, y: -1)
        }
        layer.render(in: context)
        context.endTransparencyLayer()
        context.restoreGState()
    }
}

// MARK: - Header

/// The header strip: a small slanted stripe, the heading, the key hints right-aligned
/// (truncated first), and a `borderSubtle` hairline under it.
final class SwitcherHeaderView: FlippedView {
    static let stripeSize = CGSize(width: 26, height: 10)

    private let stripe = RetroStripeView(layout: .slanted)
    private let headingLabel = SwitcherText.label()
    private let hintsLabel = SwitcherText.label()
    private let rule = RetroRuleView(axis: .horizontal, style: .single)

    init() {
        super.init(frame: .zero)
        stripe.translatesAutoresizingMaskIntoConstraints = true
        rule.translatesAutoresizingMaskIntoConstraints = true
        hintsLabel.alignment = .right
        hintsLabel.setAccessibilityElement(false)
        addSubview(stripe)
        addSubview(headingLabel)
        addSubview(hintsLabel)
        addSubview(rule)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    func configure(heading: String, hints: String, colors: ThemeColors) {
        stripe.colors = colors.stripe
        rule.color = colors.borderSubtle
        headingLabel.attributedStringValue = RetroText.display(heading, color: colors.textPrimary)
        hintsLabel.attributedStringValue = RetroText.display(hints, color: colors.textMuted, alignment: .right)

        let bandHeight = bounds.height - Retro.hairline
        let centerY = bandHeight / 2
        stripe.frame = CGRect(
            x: 0,
            y: (centerY - Self.stripeSize.height / 2).rounded(),
            width: Self.stripeSize.width,
            height: Self.stripeSize.height
        )
        let leading = stripe.frame.maxX + 8
        let available = max(0, bounds.width - leading)
        let headingWidth = min(SwitcherText.width(of: headingLabel.attributedStringValue), available)
        let hintsWidth = hints.isEmpty
            ? 0
            : min(SwitcherText.width(of: hintsLabel.attributedStringValue), max(0, available - headingWidth - 16))
        let font = RetroFont.display(11)
        headingLabel.frame = SwitcherText.lineFrame(minX: leading, maxX: leading + headingWidth, centerY: centerY, font: font)
        hintsLabel.frame = SwitcherText.lineFrame(minX: bounds.width - hintsWidth, maxX: bounds.width, centerY: centerY, font: font)
        hintsLabel.isHidden = hintsWidth <= 0
        rule.frame = CGRect(x: 0, y: bounds.height - Retro.hairline, width: bounds.width, height: Retro.hairline)
    }
}

// MARK: - Tile container

/// The scroll view's document: holds the tile views and reports which one the pointer is
/// over (tracking areas work while Soprano Tab is not the active app).
final class TileContainerView: FlippedView {
    private(set) var tiles: [TileView] = []
    var onHover: ((Int?) -> Void)?
    private var hoverArea: NSTrackingArea?
    private var reportedHover: Int?

    /// Adds or removes tile views at the end so exactly `count` exist; `prepare` runs once
    /// for each new view.
    func ensureTileCount(_ count: Int, prepare: (TileView) -> Void) {
        while tiles.count > count {
            tiles.removeLast().removeFromSuperview()
        }
        while tiles.count < count {
            let tile = TileView()
            prepare(tile)
            addSubview(tile)
            tiles.append(tile)
        }
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let hoverArea {
            removeTrackingArea(hoverArea)
        }
        let area = NSTrackingArea(
            rect: .zero,
            options: [.mouseEnteredAndExited, .mouseMoved, .activeAlways, .inVisibleRect],
            owner: self
        )
        addTrackingArea(area)
        hoverArea = area
    }

    override func mouseEntered(with event: NSEvent) {
        reportHover(at: convert(event.locationInWindow, from: nil))
    }

    override func mouseMoved(with event: NSEvent) {
        reportHover(at: convert(event.locationInWindow, from: nil))
    }

    override func mouseExited(with event: NSEvent) {
        report(nil)
    }

    private func reportHover(at point: NSPoint) {
        report(tiles.firstIndex { !$0.isHidden && $0.frame.contains(point) })
    }

    private func report(_ index: Int?) {
        guard index != reportedHover else { return }
        reportedHover = index
        onHover?(index)
    }
}

// MARK: - Shared helpers

/// A layer-backed view with a top-left origin, the coordinate space `TileLayout` uses.
class FlippedView: NSView {
    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    override var isFlipped: Bool { true }
}

/// Text and image helpers shared by the switcher views.
@MainActor
enum SwitcherText {
    /// A single-line, non-editable label laid out by frame.
    static func label() -> NSTextField {
        let label = NSTextField(labelWithString: "")
        label.translatesAutoresizingMaskIntoConstraints = true
        label.lineBreakMode = .byTruncatingTail
        label.maximumNumberOfLines = 1
        label.usesSingleLineMode = true
        label.cell?.wraps = false
        label.cell?.truncatesLastVisibleLine = true
        return label
    }

    static func lineBreakMode(for truncation: TitleTruncation) -> NSLineBreakMode {
        switch truncation {
        case .start: .byTruncatingHead
        case .middle: .byTruncatingMiddle
        case .end: .byTruncatingTail
        }
    }

    /// A title with the search hits in `highlight`.
    static func title(
        _ text: String,
        highlights: [NSRange],
        font: NSFont,
        color: NSColor,
        highlight: NSColor,
        alignment: NSTextAlignment = .natural,
        lineBreakMode: NSLineBreakMode
    ) -> NSAttributedString {
        let string = NSMutableAttributedString(
            attributedString: plain(text, font: font, color: color, alignment: alignment, lineBreakMode: lineBreakMode)
        )
        let length = string.length
        for range in highlights where range.location != NSNotFound && range.location < length {
            let clamped = NSRange(location: range.location, length: min(range.length, length - range.location))
            string.addAttribute(.foregroundColor, value: highlight, range: clamped)
        }
        return string
    }

    static func plain(
        _ text: String,
        font: NSFont,
        color: NSColor,
        alignment: NSTextAlignment = .natural,
        lineBreakMode: NSLineBreakMode = .byTruncatingTail
    ) -> NSAttributedString {
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = alignment
        paragraph.lineBreakMode = lineBreakMode
        return NSAttributedString(string: text, attributes: [
            .font: font,
            .foregroundColor: color,
            .paragraphStyle: paragraph,
        ])
    }

    /// The width a label needs to show `text` untruncated, including the text cell's
    /// 2 pt padding on each side.
    static func width(of text: NSAttributedString) -> CGFloat {
        text.length == 0 ? 0 : ceil(text.size().width) + 4
    }

    static func lineHeight(_ font: NSFont) -> CGFloat {
        ceil(font.ascender - font.descender + font.leading)
    }

    /// A one-line label frame spanning `minX…maxX`, vertically centered on `centerY`.
    static func lineFrame(minX: CGFloat, maxX: CGFloat, centerY: CGFloat, font: NSFont) -> CGRect {
        let height = lineHeight(font) + 1
        return CGRect(x: minX, y: (centerY - height / 2).rounded(), width: max(0, maxX - minX), height: height)
    }

    /// `image` rasterized for a `side`-point square at `scale`.
    static func cgImage(_ image: NSImage?, side: CGFloat, scale: CGFloat) -> CGImage? {
        guard let image, side > 0 else { return nil }
        var rect = CGRect(x: 0, y: 0, width: side * scale, height: side * scale)
        return image.cgImage(forProposedRect: &rect, context: nil, hints: nil)
    }
}
