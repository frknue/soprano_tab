import AppKit
import SopranoTabCore

/// One switcher item in any of the three styles. Tile views are reused across updates:
/// text, icons and badges are rebuilt only when the tile's content changes, so a selection
/// or hover change only restyles fills, frames and lamps.
final class TileView: FlippedView {
    static let lampSide: CGFloat = 10
    static let lampGap: CGFloat = 6
    /// The app icon beside the title in a thumbnail tile's title strip.
    static let stripIconSide: CGFloat = 16
    static let railWidth: CGFloat = 2
    static let selectionFrameWidth: CGFloat = 2

    private(set) var index = 0
    private(set) var itemID: ItemID?
    private(set) var isSelected = false
    private(set) var isHovered = false
    /// The control lamps showing, in order: none unless hovered, close / minimize /
    /// fullscreen on a window's tile, quit alone on a windowless app's tile.
    private(set) var controls: [TileControl] = []

    var onClick: ((Int) -> Void)?
    var onControl: ((Int, TileControl) -> Void)?

    private let imageArea = TileImageView()
    private let stripIcon = TileImageView()
    private let titleLabel = SwitcherText.label()
    private let appNameLabel = SwitcherText.label()
    private let rail = FlippedView()
    private let lamps: [(control: TileControl, view: FlippedView)] = TileControl.allCases.map { (control: $0, view: FlippedView()) }
    private var chips: [ChipView] = []

    private var content: Content?
    private var style = SwitcherStyle.thumbnails
    private var imageFrame = CGRect.zero
    private var titleFrame = CGRect.zero
    private var colors = AppTheme.missionControl.colors

    /// What the tile shows apart from selection and hover; a change rebuilds text and icons.
    private struct Content: Equatable {
        var id: ItemID
        var title: String
        var highlightedRanges: [NSRange]
        var appName: String
        var badges: TileBadges
        var isWindowlessApp: Bool
        var style: SwitcherStyle
        var themeID: String
        var truncation: TitleTruncation
        var icon: ObjectIdentifier?
        var imageSize: CGSize
        var scale: CGFloat
    }

    init() {
        super.init(frame: .zero)
        appNameLabel.alignment = .right
        titleLabel.setAccessibilityElement(false)
        appNameLabel.setAccessibilityElement(false)
        addSubview(imageArea)
        addSubview(stripIcon)
        addSubview(titleLabel)
        addSubview(appNameLabel)
        addSubview(rail)
        for (control, lamp) in lamps {
            lamp.layer?.cornerRadius = Self.lampSide / 2
            lamp.setAccessibilityElement(false)
            lamp.toolTip = control.label
            addSubview(lamp)
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
        self.style = style
        self.imageFrame = imageFrame
        self.titleFrame = titleFrame
        self.colors = theme.colors
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
            title: tile.title,
            highlightedRanges: tile.highlightedRanges,
            appName: tile.appName,
            badges: tile.badges,
            isWindowlessApp: tile.isWindowlessApp,
            style: style,
            themeID: theme.id,
            truncation: truncation,
            icon: tile.icon.map(ObjectIdentifier.init),
            imageSize: imageFrame.size,
            scale: scale
        )
        if content != self.content {
            self.content = content
            applyContent(tile, truncation: truncation, scale: scale)
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

    private func applyContent(_ tile: TileViewModel, truncation: TitleTruncation, scale: CGFloat) {
        let iconAlpha: Float = tile.isWindowlessApp ? 0.6 : 1
        let titleColor = tile.isWindowlessApp ? colors.textMuted : colors.textPrimary
        let lineBreak = SwitcherText.lineBreakMode(for: truncation)
        switch style {
        case .thumbnails:
            let fallbackSide = min(imageFrame.width, imageFrame.height / 2).rounded(.down)
            imageArea.configure(
                fill: colors.bgRaised,
                icon: SwitcherText.cgImage(tile.icon, side: fallbackSide, scale: scale),
                iconSide: fallbackSide,
                iconAlpha: iconAlpha
            )
            stripIcon.configure(
                fill: nil,
                icon: SwitcherText.cgImage(tile.icon, side: Self.stripIconSide, scale: scale),
                iconSide: Self.stripIconSide,
                iconAlpha: iconAlpha
            )
            titleLabel.attributedStringValue = SwitcherText.title(
                tile.title, highlights: tile.highlightedRanges, font: RetroFont.body(12),
                color: titleColor, highlight: colors.accent, lineBreakMode: lineBreak
            )
        case .appIcons:
            let side = min(imageFrame.width, imageFrame.height)
            imageArea.configure(
                fill: nil,
                icon: SwitcherText.cgImage(tile.icon, side: side, scale: scale),
                iconSide: side,
                iconAlpha: iconAlpha
            )
            titleLabel.attributedStringValue = SwitcherText.title(
                tile.title, highlights: tile.highlightedRanges, font: RetroFont.body(11),
                color: titleColor, highlight: colors.accent, alignment: .center, lineBreakMode: lineBreak
            )
        case .titles:
            let side = min(imageFrame.width, imageFrame.height)
            imageArea.configure(
                fill: nil,
                icon: SwitcherText.cgImage(tile.icon, side: side, scale: scale),
                iconSide: side,
                iconAlpha: iconAlpha
            )
            titleLabel.attributedStringValue = SwitcherText.title(
                tile.title, highlights: tile.highlightedRanges, font: RetroFont.body(13),
                color: titleColor, highlight: colors.accent, lineBreakMode: lineBreak
            )
            appNameLabel.attributedStringValue = SwitcherText.plain(
                tile.appName, font: RetroFont.body(11), color: colors.textMuted, alignment: .right
            )
        }
        stripIcon.isHidden = style != .thumbnails
        appNameLabel.isHidden = style != .titles
        rebuildChips(tile.badges)
    }

    private func rebuildChips(_ badges: TileBadges) {
        var texts: [String] = []
        if badges.minimized { texts.append("min") }
        if badges.hidden { texts.append("hidden") }
        if badges.fullscreen { texts.append("full") }
        if let space = badges.spaceLabel { texts.append(space) }
        while chips.count > texts.count {
            chips.removeLast().removeFromSuperview()
        }
        while chips.count < texts.count {
            let chip = ChipView()
            addSubview(chip, positioned: .below, relativeTo: lamps.first?.view)
            chips.append(chip)
        }
        for (chip, text) in zip(chips, texts) {
            chip.configure(text: text, colors: colors)
        }
    }

    /// Fills, frames, the title row's rail and the lamps: everything selection and hover change.
    private func applyState() {
        guard let layer else { return }
        let fill: NSColor
        var borderColor = colors.borderSubtle
        var borderWidth: CGFloat = 0
        switch style {
        case .thumbnails:
            fill = isSelected ? colors.bgSelectedStrong : (isHovered ? colors.bgOverlay : colors.bgPanel)
            borderWidth = isSelected ? Self.selectionFrameWidth : Retro.hairline
        case .appIcons:
            fill = isSelected ? colors.bgSelectedStrong : (isHovered ? colors.bgOverlay : .clear)
            borderWidth = isSelected ? Self.selectionFrameWidth : (isHovered ? Retro.hairline : 0)
        case .titles:
            fill = isSelected ? colors.bgSelectedStrong : (isHovered ? colors.bgOverlay : .clear)
        }
        if isSelected {
            borderColor = colors.accent
        }
        layer.backgroundColor = fill.cgColor
        layer.borderColor = borderColor.cgColor
        layer.borderWidth = borderWidth
        layer.cornerRadius = Retro.cornerRadius

        rail.isHidden = !(style == .titles && isSelected)
        rail.layer?.backgroundColor = colors.accent.cgColor

        for (control, lamp) in lamps {
            lamp.isHidden = !controls.contains(control)
            RetroLamp.light(lamp, color: control.color(in: colors))
        }
    }

    // MARK: - Layout

    private func layoutContents() {
        imageArea.frame = imageFrame
        imageArea.layoutLayers()
        rail.frame = CGRect(x: 0, y: 0, width: Self.railWidth, height: bounds.height)
        switch style {
        case .thumbnails: layoutThumbnailTile()
        case .appIcons: layoutAppIconTile()
        case .titles: layoutTitleRow()
        }
    }

    private func layoutThumbnailTile() {
        // Like a macOS title bar: lamps first, then the app icon and the title.
        var leading = titleFrame.minX
        if !controls.isEmpty {
            leading = layoutLamps(leading: leading, centerY: titleFrame.midY) + Self.lampGap
        }
        let iconSide = Self.stripIconSide
        stripIcon.frame = CGRect(x: leading, y: (titleFrame.midY - iconSide / 2).rounded(), width: iconSide, height: iconSide)
        stripIcon.layoutLayers()
        titleLabel.frame = SwitcherText.lineFrame(
            minX: stripIcon.frame.maxX + 6, maxX: titleFrame.maxX, centerY: titleFrame.midY, font: RetroFont.body(12)
        )
        layoutChipsAtImageBottomLeft()
    }

    private func layoutAppIconTile() {
        titleLabel.frame = SwitcherText.lineFrame(
            minX: titleFrame.minX, maxX: titleFrame.maxX, centerY: titleFrame.midY, font: RetroFont.body(11)
        )
        if !controls.isEmpty {
            // The title strip is too narrow for lamps and a title; they sit over the icon's
            // top-leading corner instead.
            _ = layoutLamps(leading: imageFrame.minX, centerY: imageFrame.minY + Self.lampSide / 2)
        }
        layoutChipsAtImageBottomLeft()
    }

    private func layoutTitleRow() {
        var leading = titleFrame.minX
        if !controls.isEmpty {
            leading = layoutLamps(leading: leading, centerY: titleFrame.midY) + 8
        }
        var trailing = titleFrame.maxX
        if !chips.isEmpty {
            var x = trailing
            for chip in chips.reversed() {
                x -= chip.preferredWidth
                chip.frame = CGRect(x: x, y: (titleFrame.midY - ChipView.height / 2).rounded(), width: chip.preferredWidth, height: ChipView.height)
                chip.isHidden = false
                x -= 4
            }
            trailing = x - 4
        }
        let nameWidth = min(
            SwitcherText.width(of: appNameLabel.attributedStringValue),
            max(0, (trailing - leading) / 2)
        )
        appNameLabel.frame = SwitcherText.lineFrame(
            minX: trailing - nameWidth, maxX: trailing, centerY: titleFrame.midY, font: RetroFont.body(11)
        )
        if nameWidth > 0 {
            trailing -= nameWidth + 8
        }
        titleLabel.frame = SwitcherText.lineFrame(
            minX: leading, maxX: trailing, centerY: titleFrame.midY, font: RetroFont.body(13)
        )
    }

    /// Places the shown lamps left-aligned at `leading`, like macOS window buttons; returns
    /// the trailing edge of the group.
    private func layoutLamps(leading: CGFloat, centerY: CGFloat) -> CGFloat {
        let side = Self.lampSide
        var x = leading
        for (control, lamp) in lamps where controls.contains(control) {
            lamp.frame = CGRect(x: x, y: (centerY - side / 2).rounded(), width: side, height: side)
            x += side + Self.lampGap
        }
        return x - Self.lampGap
    }

    /// Badges in a row at the image's bottom-left; chips that do not fit are hidden.
    private func layoutChipsAtImageBottomLeft() {
        let inset: CGFloat = 4
        var x = imageFrame.minX + inset
        let y = imageFrame.maxY - inset - ChipView.height
        for chip in chips {
            let fits = x + chip.preferredWidth <= imageFrame.maxX - inset
            chip.isHidden = !fits
            chip.frame = CGRect(x: x, y: y, width: chip.preferredWidth, height: ChipView.height)
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
        lamps.first { controls.contains($0.control) && $0.view.frame.insetBy(dx: -3, dy: -3).contains(point) }?.control
    }

    override func accessibilityPerformPress() -> Bool {
        onClick?(index)
        return true
    }
}

private extension TileControl {
    var label: String {
        switch self {
        case .close: "Close"
        case .minimize: "Minimize"
        case .fullscreen: "Fullscreen"
        case .quit: "Quit"
        }
    }

    func color(in colors: ThemeColors) -> NSColor {
        switch self {
        case .close: colors.danger
        case .minimize: colors.yellow
        case .fullscreen: colors.success
        case .quit: colors.danger
        }
    }
}

// MARK: - Image area

/// A tile's image rect: an optional fill (`bgRaised` for thumbnails) with the thumbnail
/// aspect-fit over it, or the app icon centered at `iconSide` when there is no thumbnail.
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

    func configure(fill: NSColor?, icon: CGImage?, iconSide: CGFloat, iconAlpha: Float) {
        layer?.backgroundColor = fill?.cgColor
        iconLayer.contents = icon
        iconLayer.opacity = iconAlpha
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

// MARK: - Badge chip

/// A status badge: display-face text in `textMuted` on `bgBase` at 0.85 with a hairline.
final class ChipView: FlippedView {
    static let height: CGFloat = 16
    static let horizontalPadding: CGFloat = 4

    private var text = NSAttributedString()
    private(set) var preferredWidth: CGFloat = 0

    init() {
        super.init(frame: .zero)
        setAccessibilityElement(false)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    func configure(text: String, colors: ThemeColors) {
        self.text = RetroText.display(text, color: colors.textMuted, lineBreakMode: .byClipping)
        preferredWidth = SwitcherText.width(of: self.text) + Self.horizontalPadding * 2
        layer?.backgroundColor = colors.bgBase.withAlphaComponent(0.85).cgColor
        layer?.borderColor = colors.borderSubtle.cgColor
        layer?.borderWidth = Retro.hairline
        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        let size = text.size()
        text.draw(at: NSPoint(x: Self.horizontalPadding, y: ((bounds.height - size.height) / 2).rounded()))
    }
}
