import AppKit
import SopranoTabCore

/// The selected window's preview: its image at the window's own frame with a 2 pt
/// `focusMark` frame (it marks the selection, like the tile ring), in a borderless,
/// click-through, non-activating window one level below the switcher panel.
@MainActor
final class PreviewOverlay {
    static let frameWidth: CGFloat = Chrome.focusMarkWidth
    /// Folio motion: the Tab preview fades in over 120 ms, opacity only; never under
    /// Reduce Motion.
    static let fadeInDuration: TimeInterval = 0.12

    private let window = SwitcherPanel(level: SwitcherPanel.previewLevel)
    private let imageView = FlippedView()
    private let imageLayer = CALayer()

    private(set) var image: CGImage?
    /// The previewed window's frame, global Quartz coordinates.
    private(set) var frame: CGRect?
    private var accent = AppTheme.folioPaper.colors.focusMark

    var isShown: Bool { image != nil && frame != nil }

    init() {
        window.ignoresMouseEvents = true
        window.hasShadow = false
        imageLayer.contentsGravity = .resize
        imageView.layer?.addSublayer(imageLayer)
        imageView.layer?.borderWidth = Self.frameWidth
        imageView.setAccessibilityElement(false)
        window.contentView = imageView
    }

    /// Shows `image` at `frame` (Quartz). With `onScreen` false the window is only
    /// configured, for offscreen rendering.
    func show(_ image: CGImage, frame: CGRect, theme: AppTheme, fadeIn: Bool, onScreen: Bool) {
        let wasVisible = window.isVisible
        self.image = image
        self.frame = frame
        accent = theme.colors.focusMark
        window.appearance = theme.appearance.nsAppearance
        let primaryHeight = NSScreen.screens.first?.frame.height ?? frame.maxY
        window.setFrame(Geometry.appKitRect(fromQuartz: frame, primaryHeight: primaryHeight), display: false)
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        imageLayer.frame = imageView.bounds
        imageLayer.contents = image
        imageView.layer?.borderColor = accent.cgColor
        CATransaction.commit()
        guard onScreen else { return }
        if fadeIn && !wasVisible && !SwitcherWindow.reducesMotion {
            window.alphaValue = 0
            window.orderFrontRegardless()
            NSAnimationContext.runAnimationGroup { context in
                context.duration = Self.fadeInDuration
                window.animator().alphaValue = 1
            }
        } else {
            window.alphaValue = 1
            window.orderFrontRegardless()
        }
    }

    func hide() {
        image = nil
        frame = nil
        imageLayer.contents = nil
        window.orderOut(nil)
        window.alphaValue = 1
    }

    /// Draws the preview into a snapshot context: `convert` maps the Quartz frame into the
    /// context's (bottom-left origin) coordinates.
    func draw(in context: CGContext, convert: (CGRect) -> CGRect) {
        guard let image, let frame else { return }
        let rect = convert(frame)
        context.saveGState()
        context.interpolationQuality = .high
        context.draw(image, in: rect)
        context.setStrokeColor(accent.cgColor)
        context.setLineWidth(Self.frameWidth)
        context.stroke(rect.insetBy(dx: Self.frameWidth / 2, dy: Self.frameWidth / 2))
        context.restoreGState()
    }
}
