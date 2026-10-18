// Renders the Soprano Tab app icon as a 1024×1024 PNG.
// Usage: swift scripts/render-app-icon.swift <output.png>
//
// Family look of Soprano's icon: a dark #2a2a2a rounded square, cream #8a8270 tiles and
// strokes, and exactly one glowing orange #ff7f1a "lamp". The motif is a window switcher:
// three window outlines stacked diagonally, the front one lit as the lamp and carrying a
// dark ⇥ (tab) mark.
import AppKit

let canvasSize = 1024
let canvas = CGFloat(canvasSize)

// Same body as Soprano's app-icon.png so the family sits equally in the Dock: the rounded
// square fills the whole canvas (corner radius measured from that icon) and carries a 4 px
// lighter rim.
let bodyRect = CGRect(x: 0, y: 0, width: canvas, height: canvas)
let bodyRadius: CGFloat = 228
let rimWidth: CGFloat = 4

let background = CGColor(srgbRed: 0x2a / 255, green: 0x2a / 255, blue: 0x2a / 255, alpha: 1)
let rim = CGColor(srgbRed: 0x36 / 255, green: 0x35 / 255, blue: 0x32 / 255, alpha: 1)
let cream = CGColor(srgbRed: 0x8a / 255, green: 0x82 / 255, blue: 0x70 / 255, alpha: 1)
let dimCream = CGColor(srgbRed: 0x8a / 255, green: 0x82 / 255, blue: 0x70 / 255, alpha: 0.55)
let orange = CGColor(srgbRed: 1, green: 0x7f / 255, blue: 0x1a / 255, alpha: 1)

// Stack geometry, in top-left coordinates on the 1024 canvas. The three windows step down
// and right by `windowStep`; the whole stack spans 232…792 on both axes, centred on the
// canvas, so it carries the same visual weight as Soprano's tiles.
let windowSize = CGSize(width: 400, height: 320)
let windowRadius: CGFloat = 44
let windowStep: CGFloat = 80
let stackOrigin = CGPoint(x: 232, y: 272)
let outlineWidth: CGFloat = 36
let markWidth: CGFloat = 40

guard CommandLine.arguments.count == 2 else {
    FileHandle.standardError.write(Data("Usage: render-app-icon.swift <output.png>\n".utf8))
    exit(2)
}
let outputURL = URL(fileURLWithPath: CommandLine.arguments[1])

guard
    let context = CGContext(
        data: nil,
        width: canvasSize,
        height: canvasSize,
        bitsPerComponent: 8,
        bytesPerRow: 0,
        space: CGColorSpace(name: CGColorSpace.sRGB)!,
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    )
else {
    FileHandle.standardError.write(Data("render-app-icon: could not create a bitmap context.\n".utf8))
    exit(1)
}

// Draw in top-left coordinates so the geometry above reads like a screen layout.
context.translateBy(x: 0, y: canvas)
context.scaleBy(x: 1, y: -1)

func roundedPath(_ rect: CGRect, radius: CGFloat) -> CGPath {
    CGPath(roundedRect: rect, cornerWidth: radius, cornerHeight: radius, transform: nil)
}

func windowRect(index: Int) -> CGRect {
    let offset = windowStep * CGFloat(index)
    return CGRect(
        x: stackOrigin.x + offset,
        y: stackOrigin.y + offset,
        width: windowSize.width,
        height: windowSize.height
    )
}

// Body, then its rim, as on Soprano's icon.
let bodyPath = roundedPath(bodyRect, radius: bodyRadius)
context.addPath(bodyPath)
context.setFillColor(rim)
context.fillPath()
context.addPath(roundedPath(bodyRect.insetBy(dx: rimWidth, dy: rimWidth), radius: bodyRadius - rimWidth))
context.setFillColor(background)
context.fillPath()

// Everything else stays inside the body.
context.addPath(bodyPath)
context.clip()

// Back windows, farthest first. Each is filled with the body colour before its outline is
// stroked, so a nearer window hides the outline of the one behind it.
for (index, stroke) in [(0, dimCream), (1, cream)] {
    let outline = roundedPath(
        windowRect(index: index).insetBy(dx: outlineWidth / 2, dy: outlineWidth / 2),
        radius: windowRadius - outlineWidth / 2
    )
    context.addPath(outline)
    context.setFillColor(background)
    context.fillPath()
    context.addPath(outline)
    context.setStrokeColor(stroke)
    context.setLineWidth(outlineWidth)
    context.strokePath()
}

// Front window: the single glowing orange lamp.
let frontRect = windowRect(index: 2)
let lamp = roundedPath(frontRect, radius: windowRadius)
context.saveGState()
context.setShadow(offset: .zero, blur: 90, color: CGColor(srgbRed: 1, green: 0x7f / 255, blue: 0x1a / 255, alpha: 0.55))
context.addPath(lamp)
context.setFillColor(orange)
context.fillPath()
context.restoreGState()
context.saveGState()
context.setShadow(offset: .zero, blur: 28, color: CGColor(srgbRed: 1, green: 0x7f / 255, blue: 0x1a / 255, alpha: 0.45))
context.addPath(lamp)
context.setFillColor(orange)
context.fillPath()
context.restoreGState()

// The ⇥ mark on the lamp: a shaft and arrowhead running into a stop bar.
let markCenter = CGPoint(x: frontRect.midX, y: frontRect.midY)
let barX = markCenter.x + 96
let tipX = barX - 54
let headReach: CGFloat = 66
let mark = CGMutablePath()
mark.move(to: CGPoint(x: markCenter.x - 118, y: markCenter.y))
mark.addLine(to: CGPoint(x: tipX, y: markCenter.y))
mark.move(to: CGPoint(x: tipX - headReach, y: markCenter.y - headReach))
mark.addLine(to: CGPoint(x: tipX, y: markCenter.y))
mark.addLine(to: CGPoint(x: tipX - headReach, y: markCenter.y + headReach))
mark.move(to: CGPoint(x: barX, y: markCenter.y - 84))
mark.addLine(to: CGPoint(x: barX, y: markCenter.y + 84))
context.addPath(mark)
context.setStrokeColor(background)
context.setLineWidth(markWidth)
context.setLineCap(.round)
context.setLineJoin(.round)
context.strokePath()

guard let image = context.makeImage() else {
    FileHandle.standardError.write(Data("render-app-icon: could not finish the bitmap.\n".utf8))
    exit(1)
}
let bitmap = NSBitmapImageRep(cgImage: image)
guard let png = bitmap.representation(using: .png, properties: [:]) else {
    FileHandle.standardError.write(Data("render-app-icon: could not encode the PNG.\n".utf8))
    exit(1)
}
do {
    try FileManager.default.createDirectory(
        at: outputURL.deletingLastPathComponent(),
        withIntermediateDirectories: true
    )
    try png.write(to: outputURL, options: .atomic)
} catch {
    FileHandle.standardError.write(Data("render-app-icon: could not write \(outputURL.path): \(error)\n".utf8))
    exit(1)
}
