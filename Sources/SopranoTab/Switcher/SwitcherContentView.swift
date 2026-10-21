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
        appearance = model.theme.appearance.nsAppearance
        // The switcher sits on `raised` so it separates from same-coloured windows behind it.
        layer?.backgroundColor = colors.raised.cgColor
        layer?.borderColor = colors.borderSubtle.cgColor
        layer?.borderWidth = Chrome.hairline
        layer?.cornerRadius = Chrome.Radius.panel
        layer?.masksToBounds = true

        header.frame = layout.headerFrame
        header.configure(heading: model.heading, hints: model.hints, theme: model.theme)

        if let search = model.search, let frame = layout.searchFieldFrame {
            searchStrip.isHidden = false
            searchStrip.frame = frame
            searchStrip.configure(state: search, focused: searchFocused, theme: model.theme)
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
            let font = ChromeFont.empty
            let margin = TileLayout.selectionRingMargin
            let area = layout.contentFrame.insetBy(dx: margin, dy: margin)
            emptyLabel.isHidden = false
            emptyLabel.attributedStringValue = SwitcherText.plain(
                model.emptyText ?? "", font: font, color: colors.textMuted, alignment: .center
            )
            emptyLabel.frame = SwitcherText.lineFrame(minX: area.minX, maxX: area.maxX, centerY: area.midY, font: font)
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
        let margin = TileLayout.selectionRingMargin
        let frame = model.layout.tileFrames[selected].insetBy(dx: -margin, dy: -margin)
        let visible = scrollView.contentView.bounds
        guard frame.minY < visible.minY || frame.maxY > visible.maxY else { return }
        // Keep the selected row whole in view, moving as little as possible.
        let y = frame.minY < visible.minY ? frame.minY : frame.maxY - visible.height
        let maxY = max(0, tileContainer.frame.height - visible.height)
        scrollView.contentView.scroll(to: NSPoint(x: 0, y: min(max(0, y), maxY)))
        scrollView.reflectScrolledClipView(scrollView.contentView)
    }

    /// Renders the panel's layer tree into `context` with its top-left corner at `origin`
    /// (`context` uses a bottom-left origin), with the e3 shadow and contact ring of the
    /// model's theme. Works for a panel that was never on screen: `cacheDisplay` makes
    /// AppKit build and draw every view's layer, then Core Animation renders the tree.
    func render(in context: CGContext, at origin: CGPoint, shadow: ThemeShadow) {
        layoutSubtreeIfNeeded()
        if let rep = bitmapImageRepForCachingDisplay(in: bounds) {
            cacheDisplay(in: bounds, to: rep)
        }
        guard let layer else { return }
        let rect = CGRect(origin: origin, size: bounds.size)
        let radius = Chrome.Radius.panel
        context.saveGState()
        context.setShadow(
            offset: CGSize(width: 0, height: -shadow.offsetY),
            blur: shadow.blur,
            color: shadow.color.withAlphaComponent(CGFloat(shadow.opacity)).cgColor
        )
        context.beginTransparencyLayer(auxiliaryInfo: nil)
        context.translateBy(x: origin.x, y: origin.y)
        if layer.isGeometryFlipped {
            context.translateBy(x: 0, y: bounds.height)
            context.scaleBy(x: 1, y: -1)
        }
        layer.render(in: context)
        context.endTransparencyLayer()
        context.restoreGState()

        context.saveGState()
        context.setStrokeColor(shadow.ring.cgColor)
        context.setLineWidth(1)
        context.addPath(CGPath(
            roundedRect: rect.insetBy(dx: -0.5, dy: -0.5),
            cornerWidth: radius + 0.5, cornerHeight: radius + 0.5, transform: nil
        ))
        context.strokePath()
        context.restoreGState()
    }
}

// MARK: - Header

/// The header strip: what the list shows in SF Pro 13 Medium ink, its count muted beside
/// it, and the key hints right-aligned as keycap + word. When the strip is too narrow,
/// whole hints drop from the end; the heading truncates only when no hint is left.
final class SwitcherHeaderView: FlippedView {
    static let countGap: CGFloat = 4
    static let hintsLeadingGap: CGFloat = 16
    static let hintGap: CGFloat = 12

    private let headingLabel = SwitcherText.label()
    private let countLabel = SwitcherText.label()
    private var hintViews: [KeyHintView] = []
    /// How many hints fit, counted from the start (for tests).
    private(set) var visibleHintCount = 0

    init() {
        super.init(frame: .zero)
        addSubview(headingLabel)
        addSubview(countLabel)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    func configure(heading: SwitcherHeading, hints: [KeyHint], theme: AppTheme) {
        let colors = theme.colors
        let headingFont = ChromeFont.sans(size: 13, weight: .medium)
        let countFont = ChromeFont.sans(size: 13, tabular: true)
        headingLabel.attributedStringValue = SwitcherText.plain(heading.subject, font: headingFont, color: colors.textPrimary)
        countLabel.attributedStringValue = SwitcherText.plain("· \(heading.count)", font: countFont, color: colors.textMuted)
        headingLabel.setAccessibilityLabel("\(heading.subject), \(heading.count)")
        countLabel.setAccessibilityElement(false)

        while hintViews.count > hints.count {
            hintViews.removeLast().removeFromSuperview()
        }
        while hintViews.count < hints.count {
            let view = KeyHintView(theme: theme)
            addSubview(view)
            hintViews.append(view)
        }
        for (view, hint) in zip(hintViews, hints) {
            view.configure(hint, theme: theme)
        }

        let centerY = bounds.height / 2
        let headingWidth = SwitcherText.width(of: headingLabel.attributedStringValue)
        let countWidth = SwitcherText.width(of: countLabel.attributedStringValue)
        let headingBlock = headingWidth + Self.countGap + countWidth
        let widths = hintViews.map(\.preferredWidth)
        var count = widths.count
        while count > 0 {
            let hintsWidth = widths.prefix(count).reduce(0, +) + Self.hintGap * CGFloat(count - 1)
            if headingBlock + Self.hintsLeadingGap + hintsWidth <= bounds.width { break }
            count -= 1
        }
        visibleHintCount = count

        // The text cell pads 2 pt on each side; pull the label back so the glyphs start at 0.
        let subjectMaxX = min(headingWidth, max(0, bounds.width - countWidth - Self.countGap)) - 2
        headingLabel.frame = SwitcherText.lineFrame(minX: -2, maxX: subjectMaxX + 2, centerY: centerY, font: headingFont)
        let countMinX = subjectMaxX + Self.countGap - 2
        countLabel.frame = SwitcherText.lineFrame(
            minX: countMinX, maxX: min(bounds.width, countMinX + countWidth), centerY: centerY, font: countFont
        )
        var x = bounds.width
        for (index, view) in hintViews.enumerated().reversed() {
            view.isHidden = index >= count
            guard index < count else { continue }
            x -= view.preferredWidth
            view.frame = CGRect(
                x: x, y: (centerY - Chrome.keycapHeightSmall / 2).rounded(),
                width: view.preferredWidth, height: Chrome.keycapHeightSmall
            )
            x -= Self.hintGap
        }
    }
}

/// One header hint: a 16 pt muted keycap and its word in SF Pro 11 muted, 5 apart.
final class KeyHintView: FlippedView {
    static let gap: CGFloat = 5

    private let cap: ChromeKeycapView
    private let word = SwitcherText.label()
    private(set) var preferredWidth: CGFloat = 0

    init(theme: AppTheme) {
        cap = ChromeKeycapView(legend: "", theme: theme, style: .small, tone: .muted)
        super.init(frame: .zero)
        cap.translatesAutoresizingMaskIntoConstraints = true
        addSubview(cap)
        addSubview(word)
        setAccessibilityElement(false)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    func configure(_ hint: KeyHint, theme: AppTheme) {
        cap.legend = hint.key
        cap.apply(theme: theme)
        word.attributedStringValue = SwitcherText.plain(hint.label, font: ChromeFont.meta, color: theme.colors.textMuted)
        let capWidth = cap.intrinsicContentSize.width
        let wordWidth = SwitcherText.width(of: word.attributedStringValue) - 4
        preferredWidth = capWidth + Self.gap + wordWidth
        let height = Chrome.keycapHeightSmall
        cap.frame = CGRect(x: 0, y: 0, width: capWidth, height: height)
        // The label cell sits its glyphs a point low; centre them on the cap's legend.
        word.frame = SwitcherText.lineFrame(
            minX: capWidth + Self.gap - 2, maxX: preferredWidth + 2, centerY: height / 2 - 1, font: ChromeFont.meta
        )
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

    /// A title with the search hits Semibold in `highlight`.
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
        let matchFont = ChromeFont.sans(size: font.pointSize, weight: .semibold)
        for range in highlights where range.location != NSNotFound && range.location < length {
            let clamped = NSRange(location: range.location, length: min(range.length, length - range.location))
            string.addAttributes([.foregroundColor: highlight, .font: matchFont], range: clamped)
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
