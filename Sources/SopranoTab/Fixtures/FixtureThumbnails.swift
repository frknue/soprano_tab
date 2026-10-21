import AppKit
import SopranoTabCore

/// Window "captures" drawn on the main actor in the theme's mode (Folio: backdrop windows
/// follow the page mode): a raised title bar with the macOS traffic lights and the title
/// over content blocks seeded by the window id, the app's colour only in a few blocks.
/// Every request is answered synchronously, so the switcher shows thumbnails on its first
/// frame.
@MainActor
final class FixtureThumbnails: ThumbnailProvider {
    private struct Entry {
        var image: CGImage
        var title: String
        var frameSize: CGSize
        var maxPixelSize: CGFloat
    }

    private let source: FixtureWindowSource
    private let colors: ThemeColors
    private var cache: [WindowID: Entry] = [:]

    init(source: FixtureWindowSource, colors: ThemeColors = AppTheme.folioPaper.colors) {
        self.source = source
        self.colors = colors
    }

    var canCapture: Bool { true }

    func cachedThumbnail(for windowID: WindowID) -> CGImage? {
        cache[windowID]?.image
    }

    /// Like the live provider, minimized windows and windows no longer in the catalog
    /// keep their cached image and get no callback.
    func requestThumbnails(
        for windows: [WindowInfo],
        maxPixelSize: CGFloat,
        update: @escaping @MainActor (WindowID, CGImage) -> Void
    ) {
        let current = source.snapshot.windows
        for requested in windows {
            guard let windowID = requested.windowID,
                  let window = current.first(where: { $0.id == requested.id }),
                  !window.isMinimized,
                  let image = thumbnail(for: window, windowID: windowID, maxPixelSize: maxPixelSize)
            else { continue }
            update(windowID, image)
        }
    }

    func prune(keeping windowIDs: Set<WindowID>) {
        cache = cache.filter { windowIDs.contains($0.key) }
    }

    private func thumbnail(for window: WindowInfo, windowID: WindowID, maxPixelSize: CGFloat) -> CGImage? {
        if let entry = cache[windowID],
           entry.title == window.title,
           entry.frameSize == window.frame.size,
           entry.maxPixelSize == maxPixelSize {
            return entry.image
        }
        guard let image = Self.render(window, maxPixelSize: maxPixelSize, colors: colors) else { return nil }
        cache[windowID] = Entry(image: image, title: window.title, frameSize: window.frame.size, maxPixelSize: maxPixelSize)
        return image
    }

    /// The window drawn into an image whose longest side is `maxPixelSize` pixels.
    static func render(_ window: WindowInfo, maxPixelSize: CGFloat, colors: ThemeColors) -> CGImage? {
        let size = window.frame.size
        guard size.width > 0, size.height > 0, maxPixelSize >= 1 else { return nil }
        let scale = maxPixelSize / max(size.width, size.height)
        guard let context = FixtureDrawing.makeContext(pointSize: size, scale: scale) else { return nil }
        FixtureDrawing.withFlippedGraphics(context) {
            draw(window, in: CGRect(origin: .zero, size: size), context: context, colors: colors)
        }
        return context.makeImage()
    }

    /// Draws `window` filling `rect` in a top-left-origin point space whose current
    /// AppKit graphics context is flipped (`FixtureDrawing.withFlippedGraphics`). Sizes
    /// are in the window's own points, scaled to `rect`, so a window looks the same as a
    /// thumbnail and on the snapshot backdrop.
    static func draw(_ window: WindowInfo, in rect: CGRect, context: CGContext, colors: ThemeColors) {
        let size = window.frame.size
        guard size.width > 0, size.height > 0, rect.width > 0, rect.height > 0 else { return }
        context.saveGState()
        defer { context.restoreGState() }
        context.translateBy(x: rect.minX, y: rect.minY)
        context.scaleBy(x: rect.width / size.width, y: rect.height / size.height)
        let bounds = CGRect(origin: .zero, size: size)
        context.clip(to: bounds)

        var random = SeededRandom(seed: UInt64(window.windowID ?? 0))
        _ = random.next()
        let appColor = FixturePalette.color(for: window.app)
        let ink = colors.textPrimary

        context.setFillColor(colors.bgBase.cgColor)
        context.fill(bounds)

        // Title bar: raised, the macOS traffic lights, centered title, one hairline.
        let titleBarHeight: CGFloat = 28
        context.setFillColor(colors.raised.cgColor)
        context.fill(CGRect(x: 0, y: 0, width: size.width, height: titleBarHeight))
        context.setFillColor(colors.borderSubtle.cgColor)
        context.fill(CGRect(x: 0, y: titleBarHeight - 1, width: size.width, height: 1))
        for (index, color) in [TrafficLight.close, TrafficLight.minimize, TrafficLight.zoom].enumerated() {
            context.setFillColor(color.cgColor)
            context.fillEllipse(in: CGRect(x: 12 + CGFloat(index) * 20, y: 8, width: 12, height: 12))
        }
        FixtureDrawing.drawText(
            window.displayTitle,
            font: .systemFont(ofSize: 13, weight: .semibold),
            color: colors.textPrimary,
            centeredIn: CGRect(x: 76, y: 0, width: max(0, size.width - 152), height: titleBarHeight)
        )

        var content = CGRect(x: 0, y: titleBarHeight, width: size.width, height: size.height - titleBarHeight)
        // Optional sidebar with short list rows.
        if random.next() % 3 != 0, content.width > 320 {
            let sidebarWidth = (content.width * (0.18 + CGFloat(random.next() % 8) / 100)).rounded()
            let sidebar = CGRect(x: 0, y: content.minY, width: sidebarWidth, height: content.height)
            context.setFillColor(colors.bgPanel.cgColor)
            context.fill(sidebar)
            var rowY = sidebar.minY + 16
            while rowY + 12 < sidebar.maxY - 12 {
                let width = (sidebar.width - 32) * (0.4 + CGFloat(random.next() % 50) / 100)
                context.setFillColor(ink.withAlphaComponent(0.16).cgColor)
                context.fill(CGRect(x: 16, y: rowY, width: width, height: 10))
                rowY += 26
            }
            content = CGRect(x: sidebarWidth, y: content.minY, width: content.width - sidebarWidth, height: content.height)
        }

        // Main area: rows of text-like bars and the occasional accent block.
        let inset: CGFloat = 20
        var y = content.minY + inset
        while y < content.maxY - inset {
            let roll = random.next() % 10
            let height: CGFloat
            let color: NSColor
            let widthFraction: CGFloat
            if roll == 0 {
                height = 40 + CGFloat(random.next() % 80)
                color = appColor.withAlphaComponent(0.35)
                widthFraction = 0.5 + CGFloat(random.next() % 45) / 100
            } else {
                height = 8 + CGFloat(random.next() % 8)
                color = ink.withAlphaComponent(0.12 + CGFloat(random.next() % 20) / 100)
                widthFraction = 0.3 + CGFloat(random.next() % 65) / 100
            }
            let available = content.width - inset * 2
            let bar = CGRect(x: content.minX + inset, y: y, width: available * widthFraction, height: min(height, content.maxY - inset - y))
            context.setFillColor(color.cgColor)
            context.fill(bar)
            y += height + (roll == 0 ? 18 : 10)
        }

        context.setStrokeColor(colors.borderStrong.cgColor)
        context.setLineWidth(1)
        context.stroke(bounds.insetBy(dx: 0.5, dy: 0.5))
    }
}

/// SplitMix64: a tiny deterministic generator, so a window's content never changes
/// between runs.
private struct SeededRandom {
    private var state: UInt64

    init(seed: UInt64) {
        state = seed &+ 0x9E37_79B9_7F4A_7C15
    }

    mutating func next() -> UInt64 {
        state = state &+ 0x9E37_79B9_7F4A_7C15
        var value = state
        value = (value ^ (value >> 30)) &* 0xBF58_476D_1CE4_E5B9
        value = (value ^ (value >> 27)) &* 0x94D0_49BB_1331_11EB
        return value ^ (value >> 31)
    }
}
