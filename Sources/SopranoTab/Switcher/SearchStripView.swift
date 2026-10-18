import AppKit

/// The search strip: a `bgRaised` box with a hairline (`accent` while the field has focus)
/// around a borderless body-13 field. Every edit reports the whole text through `onChange`.
final class SearchStripView: FlippedView, NSTextFieldDelegate {
    static let placeholder = "search windows"
    static let horizontalInset: CGFloat = 8

    let field = NSTextField()
    var onChange: ((String) -> Void)?
    private var colors = AppTheme.missionControl.colors

    init() {
        super.init(frame: .zero)
        field.translatesAutoresizingMaskIntoConstraints = true
        field.isBordered = false
        field.isBezeled = false
        field.drawsBackground = false
        field.focusRingType = .none
        field.font = RetroFont.body(13)
        field.usesSingleLineMode = true
        field.lineBreakMode = .byTruncatingTail
        field.cell?.isScrollable = true
        field.cell?.wraps = false
        field.delegate = self
        field.setAccessibilityLabel("Search windows")
        addSubview(field)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    func configure(state: SearchFieldState, focused: Bool, colors: ThemeColors) {
        self.colors = colors
        layer?.backgroundColor = colors.bgRaised.cgColor
        layer?.borderWidth = Retro.hairline
        layer?.cornerRadius = Retro.cornerRadius
        setFocusedLook(focused || state.isActive)
        field.textColor = colors.textPrimary
        field.placeholderAttributedString = SwitcherText.plain(
            Self.placeholder, font: RetroFont.body(13), color: colors.textMuted
        )
        // Only push the model's text when it differs, so typing keeps its caret and selection.
        if field.stringValue != state.query {
            field.stringValue = state.query
        }
        let height = SwitcherText.lineHeight(RetroFont.body(13)) + 2
        field.frame = CGRect(
            x: Self.horizontalInset,
            y: ((bounds.height - height) / 2).rounded(),
            width: max(0, bounds.width - Self.horizontalInset * 2),
            height: height
        )
    }

    /// The hairline turns `accent` while the field has focus.
    func setFocusedLook(_ focused: Bool) {
        layer?.borderColor = (focused ? colors.accent : colors.borderSubtle).cgColor
        (field.currentEditor() as? NSTextView)?.insertionPointColor = colors.accent
    }

    func controlTextDidChange(_ notification: Notification) {
        onChange?(field.stringValue)
    }
}
