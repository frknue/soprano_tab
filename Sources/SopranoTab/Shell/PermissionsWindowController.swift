import AppKit
import SopranoTabCore

/// The onboarding window: a serif "Permissions" headline, then one row per privacy grant
/// with its status mark (success dot when granted, danger diamond when missing), what it
/// enables and a button to the matching System Settings pane. Polls every second while
/// visible, so a mark turns as soon as the user grants access.
@MainActor
final class PermissionsWindowController: NSWindowController, NSWindowDelegate {
    static let contentSize = NSSize(width: 560, height: 200)

    private let status: @MainActor () -> PermissionStatus
    /// nil follows `ThemeCenter.shared`.
    private let fixedTheme: AppTheme?
    private let backgroundView = ThemedBackgroundView(
        frame: NSRect(origin: .zero, size: PermissionsWindowController.contentSize)
    )
    private let heading = NSTextField(labelWithString: "Permissions")
    private let rule = ChromeRuleView(axis: .horizontal)
    private let accessibilityRow: PermissionRowView
    private let screenRecordingRow: PermissionRowView
    private var pollTimer: Timer?

    init(status: @escaping @MainActor () -> PermissionStatus, theme: AppTheme? = nil) {
        self.status = status
        fixedTheme = theme
        let theme = theme ?? ThemeCenter.shared.theme
        accessibilityRow = PermissionRowView(
            kind: .accessibility,
            name: "Accessibility",
            detail: "Switch and focus windows. Required.",
            theme: theme
        )
        screenRecordingRow = PermissionRowView(
            kind: .screenRecording,
            name: "Screen recording",
            detail: "Thumbnails and previews. Without it, Soprano Tab shows app icons.",
            theme: theme
        )

        let window = NSWindow(
            contentRect: NSRect(origin: .zero, size: Self.contentSize),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = "Soprano Tab Permissions"
        window.isReleasedWhenClosed = false
        super.init(window: window)
        window.contentView = backgroundView
        window.delegate = self
        buildLayout()
        apply(theme: theme)
        refresh()
        window.center()

        if fixedTheme == nil {
            ThemeCenter.shared.addObserver(self) { [weak self] in
                self?.apply(theme: ThemeCenter.shared.theme)
            }
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    override func showWindow(_ sender: Any?) {
        refresh()
        super.showWindow(sender)
        window?.makeKeyAndOrderFront(sender)
        startPolling()
    }

    func windowWillClose(_ notification: Notification) {
        pollTimer?.invalidate()
        pollTimer = nil
    }

    /// Re-reads the status and updates the marks and buttons.
    func refresh() {
        let current = status()
        accessibilityRow.granted = current.accessibility
        screenRecordingRow.granted = current.screenRecording
    }

    /// Renders the window's content without ordering it front (snapshot harness, tests).
    func renderImage() -> CGImage? {
        guard let window, let view = window.contentView else { return nil }
        refresh()
        view.wantsLayer = true
        // Twice: the first pass sizes the wrapping descriptions, the second their rows.
        view.layoutSubtreeIfNeeded()
        view.layoutSubtreeIfNeeded()
        view.displayIfNeeded()
        view.display()
        CATransaction.flush()
        guard let layer = view.layer else { return nil }

        let scale = max(1, window.backingScaleFactor)
        let size = view.bounds.size
        guard let colorSpace = CGColorSpace(name: CGColorSpace.sRGB),
              let context = CGContext(
                  data: nil,
                  width: Int(size.width * scale),
                  height: Int(size.height * scale),
                  bitsPerComponent: 8,
                  bytesPerRow: 0,
                  space: colorSpace,
                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
              )
        else { return nil }
        context.scaleBy(x: scale, y: scale)
        if layer.isGeometryFlipped {
            context.translateBy(x: 0, y: size.height)
            context.scaleBy(x: 1, y: -1)
        }
        layer.render(in: context)
        return context.makeImage()
    }

    private func startPolling() {
        guard pollTimer == nil else { return }
        pollTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.refresh()
            }
        }
    }

    private func apply(theme: AppTheme) {
        window?.appearance = theme.appearance.nsAppearance
        backgroundView.color = theme.colors.bgBase
        window?.backgroundColor = theme.colors.bgBase
        heading.setChromeText("Permissions", font: ChromeFont.headline, color: theme.colors.textPrimary)
        rule.color = theme.colors.borderSubtle
        accessibilityRow.apply(theme: theme)
        screenRecordingRow.apply(theme: theme)
    }

    private func buildLayout() {
        let rows: [NSView] = [accessibilityRow, rule, screenRecordingRow]
        heading.translatesAutoresizingMaskIntoConstraints = false
        backgroundView.addSubview(heading)
        for view in rows {
            view.translatesAutoresizingMaskIntoConstraints = false
            backgroundView.addSubview(view)
        }
        let inset: CGFloat = 20
        NSLayoutConstraint.activate([
            heading.topAnchor.constraint(equalTo: backgroundView.topAnchor, constant: inset),
            heading.leadingAnchor.constraint(equalTo: backgroundView.leadingAnchor, constant: inset),
            heading.trailingAnchor.constraint(equalTo: backgroundView.trailingAnchor, constant: -inset),

            accessibilityRow.topAnchor.constraint(equalTo: heading.bottomAnchor, constant: 16),
            rule.topAnchor.constraint(equalTo: accessibilityRow.bottomAnchor, constant: 12),
            rule.heightAnchor.constraint(equalToConstant: Chrome.hairline),
            screenRecordingRow.topAnchor.constraint(equalTo: rule.bottomAnchor, constant: 12),
        ])
        for view in rows {
            NSLayoutConstraint.activate([
                view.leadingAnchor.constraint(equalTo: backgroundView.leadingAnchor, constant: inset),
                view.trailingAnchor.constraint(equalTo: backgroundView.trailingAnchor, constant: -inset),
            ])
        }
    }
}

/// One permission: status mark, name, what it enables, and the System Settings button
/// (ink while the grant is missing, so the next step is obvious).
@MainActor
private final class PermissionRowView: NSView {

    let kind: Permissions.Kind
    var granted = false {
        didSet { restyle() }
    }

    private let mark = ChromeStatusMark()
    private let nameLabel = NSTextField(labelWithString: "")
    private let detailLabel = NSTextField(wrappingLabelWithString: "")
    private let button: ChromeButton
    private let name: String
    private var theme: AppTheme

    init(kind: Permissions.Kind, name: String, detail: String, theme: AppTheme) {
        self.kind = kind
        self.name = name
        self.theme = theme
        button = ChromeButton(title: "Open System Settings", theme: theme)
        super.init(frame: .zero)
        button.target = self
        button.action = #selector(openSettings)
        detailLabel.stringValue = detail
        detailLabel.font = ChromeFont.label
        detailLabel.isSelectable = false

        mark.setAccessibilityElement(false)
        for view in [mark, nameLabel, detailLabel] {
            view.translatesAutoresizingMaskIntoConstraints = false
        }
        nameLabel.lineBreakMode = .byTruncatingTail
        button.setContentHuggingPriority(.required, for: .horizontal)
        button.setContentCompressionResistancePriority(.required, for: .horizontal)
        detailLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        addSubview(mark)
        addSubview(nameLabel)
        addSubview(detailLabel)
        addSubview(button)

        NSLayoutConstraint.activate([
            mark.leadingAnchor.constraint(equalTo: leadingAnchor),
            mark.centerYAnchor.constraint(equalTo: nameLabel.centerYAnchor),
            mark.widthAnchor.constraint(equalToConstant: Chrome.statusMark),
            mark.heightAnchor.constraint(equalToConstant: Chrome.statusMark),

            nameLabel.topAnchor.constraint(equalTo: topAnchor),
            nameLabel.leadingAnchor.constraint(equalTo: mark.trailingAnchor, constant: 8),
            nameLabel.trailingAnchor.constraint(lessThanOrEqualTo: button.leadingAnchor, constant: -16),

            detailLabel.topAnchor.constraint(equalTo: nameLabel.bottomAnchor, constant: 4),
            detailLabel.leadingAnchor.constraint(equalTo: nameLabel.leadingAnchor),
            detailLabel.trailingAnchor.constraint(equalTo: button.leadingAnchor, constant: -16),
            detailLabel.bottomAnchor.constraint(equalTo: bottomAnchor),

            button.trailingAnchor.constraint(equalTo: trailingAnchor),
            button.centerYAnchor.constraint(equalTo: centerYAnchor),
            button.topAnchor.constraint(greaterThanOrEqualTo: topAnchor),
            button.bottomAnchor.constraint(lessThanOrEqualTo: bottomAnchor),
        ])
        restyle()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    func apply(theme: AppTheme) {
        self.theme = theme
        button.apply(theme: theme)
        restyle()
    }

    override func layout() {
        super.layout()
        // A wrapping label reports its height for `preferredMaxLayoutWidth`; feed it the
        // width it got, then lay out again with the matching height.
        let width = detailLabel.frame.width
        if width > 0, detailLabel.preferredMaxLayoutWidth != width {
            detailLabel.preferredMaxLayoutWidth = width
            needsLayout = true
        }
    }

    private func restyle() {
        let colors = theme.colors
        mark.shape = granted ? .dot : .diamond
        mark.color = granted ? colors.success : colors.danger
        nameLabel.setChromeText(name, font: ChromeFont.row, color: colors.textPrimary)
        detailLabel.textColor = colors.textMuted
        // A missing grant gets the ink button, so the next step is obvious.
        button.kind = granted ? .standard : .ink
        setAccessibilityLabel("\(name), \(granted ? "granted" : "missing")")
    }

    @objc private func openSettings() {
        Permissions.openSettings(for: kind)
    }
}

/// The window's base fill, drawn through its layer so offscreen renders include it.
@MainActor
private final class ThemedBackgroundView: NSView {
    var color: NSColor = .black {
        didSet { layer?.backgroundColor = color.cgColor }
    }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.backgroundColor = color.cgColor
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }
}
