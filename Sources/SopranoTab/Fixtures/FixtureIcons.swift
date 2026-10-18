import AppKit
import SopranoTabCore

/// Fake app icons: square tiles in the app's color with its initial. Deterministic, so
/// snapshots of the same scenario are byte-stable.
@MainActor
final class FixtureIcons: AppIconProvider {
    private var cache: [pid_t: NSImage] = [:]

    init() {}

    func icon(for app: AppInfo) -> NSImage {
        if let cached = cache[app.pid] { return cached }
        let image = Self.makeIcon(for: app)
        cache[app.pid] = image
        return image
    }

    private static let pointSide: CGFloat = 128
    private static let pixelScale: CGFloat = 2

    private static func makeIcon(for app: AppInfo) -> NSImage {
        let side = pointSide
        let size = NSSize(width: side, height: side)
        guard let context = FixtureDrawing.makeContext(pointSize: size, scale: pixelScale) else {
            return NSImage(size: size)
        }
        FixtureDrawing.withFlippedGraphics(context) {
            let rect = CGRect(origin: .zero, size: size)
            context.setFillColor(FixturePalette.color(for: app).cgColor)
            context.fill(rect)
            // A darker band along the bottom gives the flat tile some depth.
            context.setFillColor(NSColor.black.withAlphaComponent(0.18).cgColor)
            context.fill(CGRect(x: 0, y: side * 0.78, width: side, height: side * 0.22))
            context.setStrokeColor(NSColor.black.withAlphaComponent(0.35).cgColor)
            context.setLineWidth(2)
            context.stroke(rect.insetBy(dx: 1, dy: 1))

            let initial = app.name.first.map { String($0).uppercased() } ?? "?"
            FixtureDrawing.drawText(
                initial,
                font: .systemFont(ofSize: side * 0.56, weight: .bold),
                color: NSColor.white.withAlphaComponent(0.95),
                centeredIn: CGRect(x: 0, y: 0, width: side, height: side * 0.9)
            )
        }
        guard let image = context.makeImage() else { return NSImage(size: size) }
        return NSImage(cgImage: image, size: size)
    }
}

/// The colors fixture apps are drawn in: known bundle ids get their brand-like color,
/// anything else a stable color derived from its name.
enum FixturePalette {
    private static let colorsByBundleID: [String: UInt32] = [
        "com.soprano.app": 0xFF8019,
        "com.soprano.git": 0xE0A526,
        "com.apple.Safari": 0x1E88E5,
        "com.apple.finder": 0x3FA9F5,
        "com.apple.mail": 0x2F7BEA,
        "com.tinyspeck.slackmacgap": 0x611F69,
        "com.apple.systempreferences": 0x7A7F87,
        "com.apple.Stickies": 0xE8C547,
        "com.apple.Notes": 0xF2C230,
        "com.apple.Music": 0xFA3C55,
        "com.apple.iCal": 0xE5483C,
        "com.apple.dt.Xcode": 0x1C7CD6,
        "com.figma.Desktop": 0x9B51E0,
        "com.apple.Preview": 0x4A90A4,
    ]

    /// Fallback hues for apps without an entry, picked by a hash of the name.
    private static let fallback: [UInt32] = [0x2BB673, 0xD9534F, 0x5C6BC0, 0x00897B, 0xC0782F, 0x8E6CC4]

    static func color(for app: AppInfo) -> NSColor {
        if let bundleID = app.bundleID, let hex = colorsByBundleID[bundleID] {
            return color(hex: hex)
        }
        // FNV-1a over the name: stable across runs, unlike `hashValue`.
        var hash: UInt32 = 2_166_136_261
        for byte in app.name.utf8 {
            hash = (hash ^ UInt32(byte)) &* 16_777_619
        }
        return color(hex: fallback[Int(hash % UInt32(fallback.count))])
    }

    static func color(hex: UInt32) -> NSColor {
        NSColor(
            srgbRed: CGFloat((hex >> 16) & 0xFF) / 255,
            green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255,
            alpha: 1
        )
    }
}

/// Bitmap helpers shared by the fixture drawings and the snapshot backdrop.
@MainActor
enum FixtureDrawing {
    /// An sRGB bitmap context of `pointSize × scale` pixels whose user space is points
    /// with a top-left origin (y grows down, like Quartz screen coordinates).
    static func makeContext(pointSize: CGSize, scale: CGFloat) -> CGContext? {
        let width = max(1, Int((pointSize.width * scale).rounded()))
        let height = max(1, Int((pointSize.height * scale).rounded()))
        guard let context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }
        context.translateBy(x: 0, y: CGFloat(height))
        context.scaleBy(x: CGFloat(width) / max(pointSize.width, 1), y: -CGFloat(height) / max(pointSize.height, 1))
        return context
    }

    /// Runs `draw` with `context` as the current flipped AppKit graphics context, so
    /// `NSString` drawing lands upright in the top-left-origin user space.
    static func withFlippedGraphics(_ context: CGContext, _ draw: () -> Void) {
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: true)
        draw()
        NSGraphicsContext.restoreGraphicsState()
    }

    /// Draws one line of text centered in `rect`, truncated at the end when too wide.
    /// Requires a flipped current graphics context (`withFlippedGraphics`).
    static func drawText(_ text: String, font: NSFont, color: NSColor, centeredIn rect: CGRect) {
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = .center
        paragraph.lineBreakMode = .byTruncatingTail
        let attributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: color,
            .paragraphStyle: paragraph,
        ]
        let string = NSAttributedString(string: text, attributes: attributes)
        let height = ceil(string.size().height)
        let line = CGRect(x: rect.minX, y: rect.midY - height / 2, width: rect.width, height: height)
        string.draw(with: line, options: [.usesLineFragmentOrigin, .truncatesLastVisibleLine], context: nil)
    }
}
