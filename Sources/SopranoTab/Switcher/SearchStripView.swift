import AppKit

/// The search strip, Folio `.search-field`: a `raised` field with a `borderStrong` edge
/// (`fieldFocusEdge` while the field has focus, never accent), a muted magnifier and a
/// borderless SF Pro 12 field with the accent caret. Every edit reports the whole text
/// through `onChange`.
final class SearchStripView: FlippedView, NSTextFieldDelegate {
    static let placeholder = "Search windows"
    static let leadingInset: CGFloat = 8
    static let trailingInset: CGFloat = 6
    static let iconSide: CGFloat = 13
    static let iconGap: CGFloat = 6

    let field = NSTextField()
    var onChange: ((String) -> Void)?
    private let surface: ChromeFieldView
    private let icon = NSImageView()
    private var theme = AppTheme.folioPaper

    init() {
        surface = ChromeFieldView(theme: theme)
        super.init(frame: .zero)
        surface.translatesAutoresizingMaskIntoConstraints = true
        icon.image = NSImage(systemSymbolName: "magnifyingglass", accessibilityDescription: nil)?
            .withSymbolConfiguration(.init(pointSize: Self.iconSide, weight: .regular))
        icon.imageScaling = .scaleProportionallyDown
        icon.setAccessibilityElement(false)
        field.translatesAutoresizingMaskIntoConstraints = true
        field.usesSingleLineMode = true
        field.lineBreakMode = .byTruncatingTail
        field.cell?.isScrollable = true
        field.cell?.wraps = false
        field.delegate = self
        field.setAccessibilityLabel("Search windows")
        addSubview(surface)
        addSubview(icon)
        addSubview(field)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    func configure(state: SearchFieldState, focused: Bool, theme: AppTheme) {
        self.theme = theme
        let colors = theme.colors
        surface.apply(theme: theme)
        surface.frame = bounds
        setFocusedLook(focused || state.isActive)
        ChromeFieldView.styleEmbedded(field, colors: colors, font: ChromeFont.label)
        field.placeholderAttributedString = SwitcherText.plain(
            Self.placeholder, font: ChromeFont.label, color: colors.textMuted
        )
        icon.contentTintColor = colors.textMuted
        // Only push the model's text when it differs, so typing keeps its caret and selection.
        if field.stringValue != state.query {
            field.stringValue = state.query
        }
        icon.frame = CGRect(
            x: Self.leadingInset,
            y: ((bounds.height - Self.iconSide) / 2).rounded(),
            width: Self.iconSide,
            height: Self.iconSide
        )
        let fieldX = icon.frame.maxX + Self.iconGap
        let height = SwitcherText.lineHeight(ChromeFont.label) + 2
        field.frame = CGRect(
            x: fieldX,
            y: ((bounds.height - height) / 2).rounded(),
            width: max(0, bounds.width - fieldX - Self.trailingInset),
            height: height
        )
    }

    /// The edge takes `fieldFocusEdge` while the field has focus; the caret is accent.
    func setFocusedLook(_ focused: Bool) {
        surface.isFocused = focused
        ChromeFieldView.styleEditor(of: field, colors: theme.colors)
    }

    func controlTextDidBeginEditing(_ notification: Notification) {
        ChromeFieldView.styleEditor(of: field, colors: theme.colors)
    }

    func controlTextDidChange(_ notification: Notification) {
        onChange?(field.stringValue)
    }
}
