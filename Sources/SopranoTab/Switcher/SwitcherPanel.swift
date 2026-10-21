import AppKit

/// The borderless, non-activating panel the switcher and its preview live in. It floats
/// over every app and Space (fullscreen ones too), never hides when another app is active,
/// stays out of the window cycle, and becomes key only while `allowsKey` is set (the search
/// field has focus), so showing it never activates Soprano Tab. Its appearance follows the
/// switcher's theme (set on every draw).
final class SwitcherPanel: NSPanel {
    /// The level the switcher panel uses; the preview sits one below it.
    static let switcherLevel = NSWindow.Level.popUpMenu
    static let previewLevel = NSWindow.Level(rawValue: NSWindow.Level.popUpMenu.rawValue - 1)

    /// Set while the search field should receive typing.
    var allowsKey = false

    init(level: NSWindow.Level) {
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: 1, height: 1),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: true
        )
        self.level = level
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient, .ignoresCycle]
        hidesOnDeactivate = false
        isFloatingPanel = true
        isReleasedWhenClosed = false
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        isMovable = false
        animationBehavior = .none
        acceptsMouseMovedEvents = true
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    override var canBecomeKey: Bool { allowsKey }
    override var canBecomeMain: Bool { false }
}
