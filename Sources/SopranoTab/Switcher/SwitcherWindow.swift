import AppKit
import SopranoTabCore

/// The switcher's on-screen presence: the panel (header, search strip, tiles), the preview
/// overlay, and offscreen rendering for the snapshot harness.
@MainActor
final class SwitcherWindow: SwitcherPresenting {
    /// Keeps every window off screen while still laying it out, for the snapshot harness
    /// and tests. A process whose activation policy is `.prohibited` (a plain command-line
    /// process, the test runner) is treated the same way.
    static var offscreen = false

    static let fadeOutDuration: TimeInterval = 0.15

    /// Folio motion: every fade is 0 under Reduce Motion.
    static var reducesMotion: Bool {
        NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
    }

    private(set) var isPresented = false
    var onHover: ((Int?) -> Void)?
    var onClick: ((Int) -> Void)?
    var onControl: ((Int, TileControl) -> Void)?
    var onQueryChange: ((String) -> Void)?

    private let panel: SwitcherPanel
    private let content = SwitcherContentView()
    private let preview = PreviewOverlay()
    private var model: SwitcherViewModel?
    private var screen: ScreenInfo?
    private var isSearchFocused = false
    /// Bumped on every present and dismiss so a stale fade-out completion does nothing.
    private var generation = 0

    init() {
        // Windows need the shared application, which a test runner has not created yet.
        _ = NSApplication.shared
        panel = SwitcherPanel(level: SwitcherPanel.switcherLevel)
        panel.contentView = content
        content.onHover = { [weak self] index in self?.onHover?(index) }
        content.onClick = { [weak self] index in self?.onClick?(index) }
        content.onControl = { [weak self] index, control in self?.onControl?(index, control) }
        content.searchStrip.onChange = { [weak self] text in self?.onQueryChange?(text) }
    }

    /// The panel's tile views in item order (for tests).
    var tileViews: [TileView] { content.tileViews }

    private var isOffscreen: Bool {
        Self.offscreen || NSApplication.shared.activationPolicy() == .prohibited
    }

    // MARK: - SwitcherPresenting

    func present(_ model: SwitcherViewModel, on screen: ScreenInfo) {
        generation += 1
        self.screen = screen
        isPresented = true
        draw(model)
        guard !isOffscreen else { return }
        // A zero-length group also cancels a fade-out still running from the last dismissal.
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0
            panel.animator().alphaValue = 1
        }
        panel.orderFrontRegardless()
    }

    func update(_ model: SwitcherViewModel) {
        draw(model)
    }

    func updateThumbnail(_ image: CGImage, for id: ItemID) {
        guard let index = model?.tiles.firstIndex(where: { $0.id == id }) else { return }
        model?.tiles[index].thumbnail = image
        content.updateThumbnail(image, at: index)
    }

    func dismiss(animated: Bool) {
        preview.hide()
        setSearchFocused(false)
        guard isPresented else { return }
        isPresented = false
        generation += 1
        let dismissal = generation
        guard animated, panel.isVisible, !isOffscreen, !Self.reducesMotion else {
            panel.orderOut(nil)
            return
        }
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = Self.fadeOutDuration
            panel.animator().alphaValue = 0
        }, completionHandler: { [weak self] in
            // AppKit runs animation completions on the main thread.
            MainActor.assumeIsolated { self?.finishDismissal(dismissal) }
        })
    }

    func showPreview(_ image: CGImage?, frame: CGRect?, fadeIn: Bool) {
        guard let image, let frame else {
            preview.hide()
            return
        }
        let theme = model?.theme ?? .folioPaper
        preview.show(image, frame: frame, theme: theme, fadeIn: fadeIn, onScreen: !isOffscreen && isPresented)
    }

    func setSearchFocused(_ focused: Bool) {
        isSearchFocused = focused
        panel.allowsKey = focused
        if !isOffscreen {
            if focused {
                // A non-activating panel becomes key without activating Soprano Tab: the
                // app behind keeps its focus while typing reaches the field.
                panel.makeKey()
                panel.makeFirstResponder(content.searchStrip.field)
            } else if panel.firstResponder !== panel {
                panel.makeFirstResponder(nil)
            }
        }
        content.searchStrip.setFocusedLook(focused || model?.search?.isActive == true)
    }

    func renderSnapshot(screen: ScreenInfo, backdrop: CGImage?) -> CGImage? {
        guard isPresented, let model else { return nil }
        let scale = max(1, screen.scale)
        let size = screen.frame.size
        let pixelWidth = Int((size.width * scale).rounded())
        let pixelHeight = Int((size.height * scale).rounded())
        guard pixelWidth > 0, pixelHeight > 0,
              let colorSpace = CGColorSpace(name: CGColorSpace.sRGB),
              let context = CGContext(
                  data: nil,
                  width: pixelWidth,
                  height: pixelHeight,
                  bitsPerComponent: 8,
                  bytesPerRow: 0,
                  space: colorSpace,
                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
              )
        else { return nil }
        context.scaleBy(x: scale, y: scale)
        let bounds = CGRect(origin: .zero, size: size)
        if let backdrop {
            context.draw(backdrop, in: bounds)
        } else {
            context.setFillColor(model.theme.colors.bgBase.cgColor)
            context.fill(bounds)
        }
        // Quartz rects (top-left origin, global) → this context (bottom-left origin, screen-local).
        let local = { (rect: CGRect) -> CGRect in
            CGRect(
                x: rect.minX - screen.frame.minX,
                y: size.height - (rect.maxY - screen.frame.minY),
                width: rect.width,
                height: rect.height
            )
        }
        preview.draw(in: context, convert: local)
        let panelRect = local(Self.panelFrame(size: model.layout.panelSize, centeredIn: screen.visibleFrame))
        content.render(in: context, at: panelRect.origin, shadow: model.theme.colors.shadowE3)
        return context.makeImage()
    }

    // MARK: - Drawing

    private func draw(_ model: SwitcherViewModel) {
        self.model = model
        let scale = screen?.scale ?? panel.backingScaleFactor
        if let screen {
            let primaryHeight = NSScreen.screens.first?.frame.height ?? screen.frame.maxY
            let quartz = Self.panelFrame(size: model.layout.panelSize, centeredIn: screen.visibleFrame)
            let frame = Geometry.appKitRect(fromQuartz: quartz, primaryHeight: primaryHeight)
            if panel.frame != frame {
                panel.setFrame(frame, display: false)
            }
        }
        panel.appearance = model.theme.appearance.nsAppearance
        content.apply(model, scale: scale, searchFocused: isSearchFocused)
        panel.invalidateShadow()
    }

    /// The panel's frame (Quartz), centered on `visibleFrame` on whole points.
    static func panelFrame(size: CGSize, centeredIn visibleFrame: CGRect) -> CGRect {
        CGRect(
            x: (visibleFrame.midX - size.width / 2).rounded(),
            y: (visibleFrame.midY - size.height / 2).rounded(),
            width: size.width,
            height: size.height
        )
    }

    private func finishDismissal(_ dismissal: Int) {
        guard dismissal == generation, !isPresented else { return }
        panel.orderOut(nil)
        panel.alphaValue = 1
    }
}
