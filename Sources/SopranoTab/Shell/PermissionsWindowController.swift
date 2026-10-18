import AppKit
import SopranoTabCore

/// The onboarding window: one row per privacy grant with its lamp, what it enables and a
/// key to the matching System Settings pane. Polls every second while visible, so lamps
/// light up as soon as the user grants access.
@MainActor
final class PermissionsWindowController: NSWindowController, NSWindowDelegate {
    static let contentSize = NSSize(width: 560, height: 200)

    private let status: @MainActor () -> PermissionStatus
    /// nil follows `ThemeCenter.shared`.
    private let fixedTheme: AppTheme?
    private let backgroundView = ThemedBackgroundView(
        frame: NSRect(origin: .zero, size: PermissionsWindowController.contentSize)
    )
    private let heading: RetroHeadingView
    private let rule = RetroRuleView(axis: .horizontal, style: .single)
    private let accessibilityRow: PermissionRowView
    private let screenRecordingRow: PermissionRowView
    private var pollTimer: Timer?

    init(status: @escaping @MainActor () -> PermissionStatus, theme: AppTheme? = nil) {
        self.status = status
        fixedTheme = theme
        let theme = theme ?? ThemeCenter.shared.theme
        heading = RetroHeadingView(title: "permissions", theme: theme)
        accessibilityRow = PermissionRowView(
            kind: .accessibility,
            name: "accessibility",
            detail: "switch and focus windows, required",
            theme: theme
        )
        screenRecordingRow = PermissionRowView(
            kind: .screenRecording,
            name: "screen recording",
            detail: "thumbnails and previews; without it Soprano Tab shows app icons",
            theme: theme
        )

        let window = NSWindow(
            contentRect: NSRect(origin: .zero, size: Self.contentSize),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = "Soprano Tab Permissions"
        window.appearance = NSAppearance(named: .darkAqua)
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

    /// Re-reads the status and relights the lamps.
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
        backgroundView.color = theme.colors.bgBase
        window?.backgroundColor = theme.colors.bgBase
        heading.apply(theme: theme)
        rule.color = theme.colors.borderSubtle
        accessibilityRow.apply(theme: theme)
        screenRecordingRow.apply(theme: theme)
    }

    private func buildLayout() {
        let rows: [NSView] = [accessibilityRow, rule, screenRecordingRow]
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
            rule.heightAnchor.constraint(equalToConstant: Retro.hairline),
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

/// One permission: lamp, name, what it enables, and the System Settings key.
@MainActor
private final class PermissionRowView: NSView {
    static let lampSize: CGFloat = 10

    let kind: Permissions.Kind
    var granted = false {
        didSet { restyle() }
    }

    private let lamp = NSView()
    private let nameLabel = NSTextField(labelWithString: "")
    private let detailLabel = NSTextField(wrappingLabelWithString: "")
    private let button: RetroButton
    private let name: String
    private var theme: AppTheme

    init(kind: Permissions.Kind, name: String, detail: String, theme: AppTheme) {
        self.kind = kind
        self.name = name
        self.theme = theme
        button = RetroButton(title: "Open System Settings", theme: theme)
        super.init(frame: .zero)
        button.target = self
        button.action = #selector(openSettings)
        detailLabel.stringValue = detail
        detailLabel.font = RetroFont.body(12)
        detailLabel.isSelectable = false

        lamp.wantsLayer = true
        lamp.layer?.cornerRadius = Self.lampSize / 2
        for view in [lamp, nameLabel, detailLabel] {
            view.translatesAutoresizingMaskIntoConstraints = false
        }
        nameLabel.lineBreakMode = .byTruncatingTail
        button.setContentHuggingPriority(.required, for: .horizontal)
        button.setContentCompressionResistancePriority(.required, for: .horizontal)
        detailLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        addSubview(lamp)
        addSubview(nameLabel)
        addSubview(detailLabel)
        addSubview(button)

        NSLayoutConstraint.activate([
            lamp.leadingAnchor.constraint(equalTo: leadingAnchor),
            lamp.centerYAnchor.constraint(equalTo: nameLabel.centerYAnchor),
            lamp.widthAnchor.constraint(equalToConstant: Self.lampSize),
            lamp.heightAnchor.constraint(equalToConstant: Self.lampSize),

            nameLabel.topAnchor.constraint(equalTo: topAnchor),
            nameLabel.leadingAnchor.constraint(equalTo: lamp.trailingAnchor, constant: 10),
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
        RetroLamp.light(lamp, color: granted ? colors.success : colors.danger)
        nameLabel.setRetroText(name, color: colors.textPrimary)
        detailLabel.textColor = colors.textMuted
        // A missing grant lights the key, so the next step is obvious.
        button.kind = granted ? .standard : .prominent
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
