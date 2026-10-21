import AppKit
import SopranoTabCore

/// One switcher item in any of the three styles (Folio, direction.md §11 Tab). Tile views
/// are reused across updates: icons and chips are rebuilt only when the tile's content
/// changes; a selection or hover change restyles the fill, the ring or pill, the title and
/// the window controls.
final class TileView: FlippedView {
    /// Window-control lamps: 12 pt circles, 6 apart (`--h-window-lamp`).
    static let lampSide: CGFloat = 12
    static let lampGap: CGFloat = 6
    /// Padding of the opaque corner chip the lamps sit on (`.thumb-lamps`: 6 v / 8 h).
    static let lampChipPadding = CGSize(width: 8, height: 6)
    /// The app icon beside the title in a thumbnail tile's title strip.
    static let stripIconSide: CGFloat = 16
    static let stripIconGap: CGFloat = 6
    /// Chips sit this far in from the image's bottom-left corner, this far apart.
    static let chipInset: CGFloat = 4

    private(set) var index = 0
    private(set) var itemID: ItemID?
    private(set) var isSelected = false
    private(set) var isHovered = false
    /// The window controls showing, in order: none unless hovered, close / minimize /
    /// fullscreen on a window's tile, quit alone on a windowless app's tile.
    private(set) var controls: [TileControl] = []

    /// The selected thumbnail or app-icon tile shows the accent ring (for tests).
    var showsSelectionRing: Bool { !ring.isHidden }
    /// The title as drawn, with its colour, weight and search hits (for tests).
    var titleText: NSAttributedString { titleLabel.attributedStringValue }

    var onClick: ((Int) -> Void)?
    var onControl: ((Int, TileControl) -> Void)?

    private let imageArea = TileImageView()
    private let stripIcon = TileImageView()
    private let titleLabel = SwitcherText.label()
    private let appNameLabel = SwitcherText.label()
    /// The selected tile's accent ring, `selectionRingGap` outside the tile.
    private let ring = FlippedView()
    /// The title row's hover or selection pill (with the pencil tick), the family's
    /// shared `ChromeSelectionPill`.
    private let rowBackground = ChromeRowBackgroundView(theme: .folioPaper)
    /// The lamps' corner chip over the image (thumbnails, app icons); a bare row of lamps
    /// in the titles style.
    private let lampChip = LampChipView()
    private let lamps: [(control: TileControl, view: FlippedView)] = TileControl.allCases.map { (control: $0, view: FlippedView()) }
    private var chips: [ChipView] = []

    private var tile: TileViewModel?
    private var content: Content?
    private var style = SwitcherStyle.thumbnails
    private var truncation = TitleTruncation.end
    private var imageFrame = CGRect.zero
    private var titleFrame = CGRect.zero
    private var theme = AppTheme.folioPaper

    /// What the tile shows apart from selection and hover; a change rebuilds icons and chips.
    private struct Content: Equatable {
        var id: ItemID
        var chips: [String]
        var isWindowlessApp: Bool
        var style: SwitcherStyle
        var themeID: String
        var icon: ObjectIdentifier?
        var imageSize: CGSize
        var scale: CGFloat
    }

    init() {
        super.init(frame: .zero)
        rowBackground.translatesAutoresizingMaskIntoConstraints = true
        // The tile's bounds are the pill: the layout already insets the row.
        rowBackground.inset = 0
        addSubview(rowBackground)
        appNameLabel.alignment = .right
        titleLabel.setAccessibilityElement(false)
        appNameLabel.setAccessibilityElement(false)
        addSubview(imageArea)
        addSubview(stripIcon)
        addSubview(titleLabel)
        addSubview(appNameLabel)
        ring.layer?.borderWidth = TileLayout.selectionRingWidth
        ring.layer?.cornerRadius = Chrome.Radius.card + TileLayout.selectionRingMargin
        ring.isHidden = true
        ring.setAccessibilityElement(false)
        addSubview(ring)
        for (control, lamp) in lamps {
            lamp.layer?.cornerRadius = Self.lampSide / 2
            lamp.layer?.borderWidth = 0.5
            lamp.setAccessibilityElement(false)
            lamp.toolTip = control.label
            lampChip.addSubview(lamp)
        }
        setAccessibilityElement(true)
        setAccessibilityRole(.button)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    // MARK: - Configuration

    func configure(
        _ tile: TileViewModel,
        index: Int,
        style: SwitcherStyle,
        frame: CGRect,
        imageFrame: CGRect,
        titleFrame: CGRect,
        isSelected: Bool,
        isHovered: Bool,
        showsWindowControls: Bool,
        theme: AppTheme,
        truncation: TitleTruncation,
        scale: CGFloat
    ) {
        self.index = index
        self.itemID = tile.id
        self.tile = tile
        self.style = style
        self.truncation = truncation
        self.imageFrame = imageFrame
        self.titleFrame = titleFrame
        self.theme = theme
        self.isSelected = isSelected
        self.isHovered = isHovered
        if showsWindowControls && isHovered {
            controls = tile.isWindowlessApp ? [.quit] : [.close, .minimize, .fullscreen]
        } else {
            controls = []
        }

        CATransaction.begin()
        CATransaction.setDisableActions(true)
        self.frame = frame
        let content = Content(
            id: tile.id,
            chips: tile.chips,
            isWindowlessApp: tile.isWindowlessApp,
            style: style,
            themeID: theme.id,
            icon: tile.icon.map(ObjectIdentifier.init),
            imageSize: imageFrame.size,
            scale: scale
        )
        if content != self.content {
            self.content = content
            applyContent(tile, scale: scale)
        }
        imageArea.thumbnail = style == .thumbnails ? tile.thumbnail : nil
        applyState()
        layoutContents()
        CATransaction.commit()

        setAccessibilityLabel("\(tile.title), \(tile.appName)")
        setAccessibilitySelected(isSelected)
    }

    /// Swaps the thumbnail layer's image; nothing else redraws.
    func setThumbnail(_ image: CGImage) {
        guard style == .thumbnails else { return }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        imageArea.thumbnail = image
        CATransaction.commit()
    }

    private func applyContent(_ tile: TileViewModel, scale: CGFloat) {
        let colors = theme.colors
        // Windowless tiles dim what the image well shows, not the title strip's icon.
        let wellAlpha: Float = tile.isWindowlessApp ? 0.6 : 1
        switch style {
        case .thumbnails:
            let fallbackSide = min(imageFrame.width, imageFrame.height / 2).rounded(.down)
            imageArea.configure(
                fill: colors.raised,
                cornerRadius: Chrome.Radius.cap,
                icon: SwitcherText.cgImage(tile.icon, side: fallbackSide, scale: scale),
                iconSide: fallbackSide,
                iconAlpha: wellAlpha
            )
            stripIcon.configure(
                fill: nil,
                cornerRadius: Chrome.Radius.cap,
                icon: SwitcherText.cgImage(tile.icon, side: Self.stripIconSide, scale: scale),
                iconSide: Self.stripIconSide,
                iconAlpha: 1
            )
        case .appIcons, .titles:
            let side = min(imageFrame.width, imageFrame.height)
            imageArea.configure(
                fill: nil,
                cornerRadius: 0,
                icon: SwitcherText.cgImage(tile.icon, side: side, scale: scale),
                iconSide: side,
                iconAlpha: wellAlpha
            )
        }
        appNameLabel.attributedStringValue = SwitcherText.plain(
            tile.appName, font: ChromeFont.meta, color: colors.textMuted, alignment: .right
        )
        stripIcon.isHidden = style != .thumbnails
        appNameLabel.isHidden = style != .titles
        rebuildChips(tile.chips)
    }

    private func rebuildChips(_ texts: [String]) {
        while chips.count > texts.count {
            chips.removeLast().removeFromSuperview()
        }
        while chips.count < texts.count {
            let chip = ChipView()
            addSubview(chip, positioned: .below, relativeTo: ring)
            chips.append(chip)
        }
        let look: ChipView.Look = style == .titles ? .row : .onImage
        for (chip, text) in zip(chips, texts) {
            chip.configure(text: text, look: look, colors: theme.colors)
        }
    }

    /// The title follows selection and hover: muted at rest, ink when hovered, ink Medium
    /// when selected (thumbnails, app icons); title rows stay ink. Windowless apps stay
    /// muted. Search hits are Semibold ink, `matchOnSelection` on the selected tile.
    private func applyTitle() {
        guard let tile else { return }
        let colors = theme.colors
        let font: NSFont
        var color: NSColor
        switch style {
        case .thumbnails, .appIcons:
            font = isSelected ? ChromeFont.labelStrong : ChromeFont.label
            color = isSelected || isHovered ? colors.textPrimary : colors.textMuted
        case .titles:
            font = ChromeFont.row
            color = colors.textPrimary
        }
        if tile.isWindowlessApp {
            color = colors.textMuted
        }
        titleLabel.attributedStringValue = SwitcherText.title(
            tile.title,
            highlights: tile.highlightedRanges,
            font: font,
            color: color,
            highlight: isSelected ? colors.matchOnSelection : colors.textPrimary,
            alignment: style == .appIcons ? .center : .natural,
            lineBreakMode: SwitcherText.lineBreakMode(for: truncation)
        )
    }

    /// Fill, ring or row pill, title, lamps: everything selection and hover change.
    private func applyState() {
        guard let layer else { return }
        let colors = theme.colors
        switch style {
        case .thumbnails, .appIcons:
            layer.backgroundColor = (isHovered ? colors.hover : colors.bgPanel).cgColor
            layer.cornerRadius = Chrome.Radius.card
        case .titles:
            layer.backgroundColor = nil
            layer.cornerRadius = 0
        }
        rowBackground.isHidden = style != .titles
        rowBackground.style = isSelected ? .selected : (isHovered ? .hover : .none)
        rowBackground.apply(theme: theme)
        // AppKit turns clipping back on for a rounded layer; the ring lies outside the tile.
        clipsToBounds = false
        layer.masksToBounds = false
        ring.isHidden = !(isSelected && style != .titles)
        ring.layer?.borderColor = colors.focusMark.cgColor
        applyTitle()

        lampChip.isHidden = controls.isEmpty
        lampChip.configure(fill: style == .titles ? nil : colors.raised, shadow: style == .titles ? nil : colors.shadowE2)
        let edge = TrafficLight.edge(for: theme.appearance)
        for (control, lamp) in lamps {
            lamp.isHidden = !controls.contains(control)
            lamp.layer?.backgroundColor = control.trafficColor.cgColor
            lamp.layer?.borderColor = edge.cgColor
        }
    }

    // MARK: - Layout

    private func layoutContents() {
        imageArea.frame = imageFrame
        imageArea.layoutLayers()
        let margin = TileLayout.selectionRingMargin
        ring.frame = bounds.insetBy(dx: -margin, dy: -margin)
        rowBackground.frame = bounds
        switch style {
        case .thumbnails: layoutThumbnailTile()
        case .appIcons: layoutAppIconTile()
        case .titles: layoutTitleRow()
        }
    }

    private func layoutThumbnailTile() {
        let iconSide = Self.stripIconSide
        stripIcon.frame = CGRect(x: titleFrame.minX, y: (titleFrame.midY - iconSide / 2).rounded(), width: iconSide, height: iconSide)
        stripIcon.layoutLayers()
        titleLabel.frame = SwitcherText.lineFrame(
            minX: stripIcon.frame.maxX + Self.stripIconGap, maxX: titleFrame.maxX,
            centerY: titleFrame.midY, font: ChromeFont.labelStrong
        )
        layoutLampChip(in: imageArea, origin: .zero, padding: Self.lampChipPadding)
        layoutChipsAtImageBottomLeft()
    }

    private func layoutAppIconTile() {
        titleLabel.frame = SwitcherText.lineFrame(
            minX: titleFrame.minX, maxX: titleFrame.maxX, centerY: titleFrame.midY, font: ChromeFont.labelStrong
        )
        layoutLampChip(in: imageArea, origin: .zero, padding: Self.lampChipPadding)
        layoutChipsAtImageBottomLeft()
    }

    private func layoutTitleRow() {
        var leading = titleFrame.minX
        if !controls.isEmpty {
            let origin = CGPoint(x: leading, y: (titleFrame.midY - Self.lampSide / 2).rounded())
            leading = layoutLampChip(in: self, origin: origin, padding: .zero) + 8
        }
        var trailing = titleFrame.maxX
        if !chips.isEmpty {
            var x = trailing
            let height = ChipView.height(.row)
            for chip in chips.reversed() {
                x -= chip.preferredWidth
                chip.frame = CGRect(x: x, y: (titleFrame.midY - height / 2).rounded(), width: chip.preferredWidth, height: height)
                chip.isHidden = false
                x -= Self.chipInset
            }
            trailing = x - Self.chipInset
        }
        let nameWidth = min(
            SwitcherText.width(of: appNameLabel.attributedStringValue),
            max(0, (trailing - leading) / 2)
        )
        appNameLabel.frame = SwitcherText.lineFrame(
            minX: trailing - nameWidth, maxX: trailing, centerY: titleFrame.midY, font: ChromeFont.meta
        )
        if nameWidth > 0 {
            trailing -= nameWidth + 8
        }
        titleLabel.frame = SwitcherText.lineFrame(
            minX: leading, maxX: trailing, centerY: titleFrame.midY, font: ChromeFont.row
        )
    }

    /// Places the lamp chip at `origin` in `parent` with the shown lamps left-aligned, like
    /// macOS window buttons; returns the chip's trailing edge.
    @discardableResult
    private func layoutLampChip(in parent: NSView, origin: CGPoint, padding: CGSize) -> CGFloat {
        if lampChip.superview !== parent {
            parent.addSubview(lampChip)
        }
        let side = Self.lampSide
        var x = padding.width
        for (control, lamp) in lamps where controls.contains(control) {
            lamp.frame = CGRect(x: x, y: padding.height, width: side, height: side)
            x += side + Self.lampGap
        }
        let width = controls.isEmpty ? 0 : x - Self.lampGap + padding.width
        lampChip.frame = CGRect(x: origin.x, y: origin.y, width: width, height: side + padding.height * 2)
        return lampChip.frame.maxX
    }

    /// Chips in a row at the image's bottom-left; chips that do not fit are hidden.
    private func layoutChipsAtImageBottomLeft() {
        let inset = Self.chipInset
        let height = ChipView.height(.onImage)
        var x = imageFrame.minX + inset
        let y = imageFrame.maxY - inset - height
        for chip in chips {
            let fits = x + chip.preferredWidth <= imageFrame.maxX - inset
            chip.isHidden = !fits
            chip.frame = CGRect(x: x, y: y, width: chip.preferredWidth, height: height)
            x += chip.preferredWidth + inset
        }
    }

    // MARK: - Pointer

    override func hitTest(_ point: NSPoint) -> NSView? {
        frame.contains(point) && !isHidden ? self : nil
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func mouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        if let control = control(at: point) {
            onControl?(index, control)
        } else {
            onClick?(index)
        }
    }

    /// The shown lamp under `point` (tile coordinates), with a few points of slack around each.
    func control(at point: CGPoint) -> TileControl? {
        guard !lampChip.isHidden else { return nil }
        return lamps.first { lamp in
            controls.contains(lamp.control)
                && lamp.view.convert(lamp.view.bounds, to: self).insetBy(dx: -3, dy: -3).contains(point)
        }?.control
    }

    override func accessibilityPerformPress() -> Bool {
        onClick?(index)
        return true
    }
}

/// The window controls' opaque corner chip (`.thumb-lamps`): `raised`, only its
/// bottom-right corner rounded, e2 shadow; it covers the thumbnail's own traffic lights.
/// In the titles style it has no fill and no shadow.
final class LampChipView: FlippedView {
    private var fill: NSColor?
    private var elevation: ThemeShadow?

    func configure(fill: NSColor?, shadow: ThemeShadow?) {
        self.fill = fill
        elevation = shadow
        applyShadow()
        needsDisplay = true
    }

    /// `ThemeShadow` reads the layer tree's flipping to cast downward, so it is applied
    /// again whenever the chip moves between the image well and the title row.
    override func viewDidMoveToSuperview() {
        super.viewDidMoveToSuperview()
        applyShadow()
    }

    private func applyShadow() {
        guard let layer else { return }
        if let elevation {
            elevation.apply(to: layer)
            // Flush in the image's corner: the shadow without the contact ring.
            layer.borderWidth = 0
        } else {
            layer.shadowOpacity = 0
        }
    }

    override func layout() {
        super.layout()
        layer?.shadowPath = fill == nil ? nil : Self.shape(in: bounds).cgPath
    }

    override func draw(_ dirtyRect: NSRect) {
        guard let fill else { return }
        fill.setFill()
        Self.shape(in: bounds).fill()
    }

    /// `rect` with only the bottom-right corner rounded (flipped view coordinates).
    private static func shape(in rect: NSRect) -> NSBezierPath {
        let radius = min(Chrome.Radius.control, rect.width / 2, rect.height / 2)
        let path = NSBezierPath()
        path.move(to: NSPoint(x: rect.minX, y: rect.minY))
        path.line(to: NSPoint(x: rect.maxX, y: rect.minY))
        path.line(to: NSPoint(x: rect.maxX, y: rect.maxY - radius))
        path.appendArc(from: NSPoint(x: rect.maxX, y: rect.maxY), to: NSPoint(x: rect.maxX - radius, y: rect.maxY), radius: radius)
        path.line(to: NSPoint(x: rect.minX, y: rect.maxY))
        path.close()
        return path
    }
}

/// The real macOS traffic-light colours (not theme tokens), with their 0.5 pt inset edge.
enum TrafficLight {
    static let close = NSColor.fromHex("#ff5f57")
    static let minimize = NSColor.fromHex("#febc2e")
    static let zoom = NSColor.fromHex("#28c840")

    static func edge(for appearance: AppTheme.Appearance) -> NSColor {
        NSColor.black.withAlphaComponent(appearance == .light ? 0.12 : 0.30)
    }
}

private extension TileControl {
    var label: String {
        switch self {
        case .close: "Close"
        case .minimize: "Minimize"
        case .fullscreen: "Full screen"
        case .quit: "Quit"
        }
    }

    var trafficColor: NSColor {
        switch self {
        case .close, .quit: TrafficLight.close
        case .minimize: TrafficLight.minimize
        case .fullscreen: TrafficLight.zoom
        }
    }
}

// MARK: - Image area

/// A tile's image rect: an optional fill (`raised` for thumbnails, clipped to its corner
/// radius) with the thumbnail aspect-fit over it, or the app icon centered at `iconSide`
/// when there is no thumbnail.
final class TileImageView: FlippedView {
    private let imageLayer = CALayer()
    private let iconLayer = CALayer()
    private var iconSide: CGFloat = 0

    var thumbnail: CGImage? {
        didSet {
            guard thumbnail !== oldValue else { return }
            imageLayer.contents = thumbnail
            imageLayer.isHidden = thumbnail == nil
            iconLayer.isHidden = thumbnail != nil
        }
    }

    init() {
        super.init(frame: .zero)
        for sublayer in [imageLayer, iconLayer] {
            sublayer.contentsGravity = .resizeAspect
            sublayer.minificationFilter = .trilinear
            layer?.addSublayer(sublayer)
        }
        imageLayer.isHidden = true
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    func configure(fill: NSColor?, cornerRadius: CGFloat, icon: CGImage?, iconSide: CGFloat, iconAlpha: Float) {
        layer?.backgroundColor = fill?.cgColor
        layer?.cornerRadius = cornerRadius
        // A rounded well clips its thumbnail and the window-control chip in its corner.
        clipsToBounds = cornerRadius > 0
        layer?.masksToBounds = cornerRadius > 0
        iconLayer.contents = icon
        iconLayer.opacity = iconAlpha
        imageLayer.opacity = iconAlpha
        self.iconSide = iconSide
    }

    /// Sublayer frames follow the view's bounds; called after every frame change.
    func layoutLayers() {
        imageLayer.frame = bounds
        iconLayer.frame = CGRect(
            x: ((bounds.width - iconSide) / 2).rounded(),
            y: ((bounds.height - iconSide) / 2).rounded(),
            width: iconSide,
            height: iconSide
        )
    }
}

// MARK: - Chip

/// A tile chip: "Minimized", "Hidden", "Full screen", the Space. On an image it is the
/// Folio `.tile-chip` (16 pt, `bgBase` at 90 %, ink 11 Medium); in a title row the `.chip`
/// (18 pt, `bgOverlay`, muted 11 Medium).
final class ChipView: FlippedView {
    enum Look {
        case onImage
        case row
    }

    static func height(_ look: Look) -> CGFloat {
        look == .onImage ? 16 : Chrome.chipHeight
    }

    private static func padding(_ look: Look) -> CGFloat {
        look == .onImage ? 5 : 6
    }

    private var text = NSAttributedString()
    private var look = Look.onImage
    private(set) var preferredWidth: CGFloat = 0

    init() {
        super.init(frame: .zero)
        setAccessibilityElement(false)
        layer?.cornerRadius = Chrome.Radius.cap
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    func configure(text: String, look: Look, colors: ThemeColors) {
        self.look = look
        let color = look == .onImage ? colors.textPrimary : colors.textMuted
        self.text = ChromeText.attributed(
            text, font: ChromeFont.sans(size: 11, weight: .medium), color: color, lineBreakMode: .byClipping
        )
        preferredWidth = ceil(self.text.size().width) + Self.padding(look) * 2
        let fill = look == .onImage ? colors.bgBase.withAlphaComponent(0.9) : colors.bgOverlay
        layer?.backgroundColor = fill.cgColor
        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        let size = text.size()
        text.draw(at: NSPoint(x: Self.padding(look), y: ((bounds.height - size.height) / 2).rounded()))
    }
}
