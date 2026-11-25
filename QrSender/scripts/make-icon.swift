// Renders the app icon. Usage: swift scripts/make-icon.swift <out.png> [--ios]
// --ios: full-bleed opaque square (iOS applies its own mask) with a "receive" arrow.
import AppKit

let ios = CommandLine.arguments.contains("--ios")
let size = 1024
let ctx = CGContext(data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: 0,
                    space: CGColorSpace(name: CGColorSpace.sRGB)!,
                    bitmapInfo: (ios ? CGImageAlphaInfo.noneSkipLast : .premultipliedLast).rawValue)!

if ios {
    // Map the macOS 824pt body onto the full canvas so proportions match.
    let s = CGFloat(size) / 824
    ctx.scaleBy(x: s, y: s)
    ctx.translateBy(x: -100, y: -100)
}

func rgb(_ hex: UInt32, _ a: CGFloat = 1) -> CGColor {
    CGColor(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255, alpha: a)
}

func rounded(_ r: CGRect, _ radius: CGFloat) -> CGPath {
    CGPath(roundedRect: r, cornerWidth: radius, cornerHeight: radius, transform: nil)
}

// MARK: Body (macOS icon grid: 824pt squircle inset 100pt)
let bodyRect = CGRect(x: 100, y: 100, width: 824, height: 824)
let bodyPath = ios ? CGPath(rect: bodyRect, transform: nil) : rounded(bodyRect, 185)

ctx.saveGState()
if !ios { ctx.setShadow(offset: CGSize(width: 0, height: -10), blur: 24, color: rgb(0x000000, 0.28)) }
ctx.addPath(bodyPath)
ctx.setFillColor(rgb(0x3F6FFF))
ctx.fillPath()
ctx.restoreGState()

let sRGB = CGColorSpace(name: CGColorSpace.sRGB)!
ctx.saveGState()
ctx.addPath(bodyPath)
ctx.clip()
let grad = CGGradient(colorsSpace: sRGB,
                      colors: [rgb(0x6CC0FF), rgb(0x4A8CFF), rgb(0x4B63F5)] as CFArray,
                      locations: [0, 0.5, 1])!
ctx.drawLinearGradient(grad, start: CGPoint(x: 160, y: 960), end: CGPoint(x: 880, y: 80),
                       options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])
let glow = CGGradient(colorsSpace: sRGB, colors: [rgb(0xFFFFFF, 0.18), rgb(0xFFFFFF, 0)] as CFArray, locations: nil)!
ctx.drawRadialGradient(glow, startCenter: CGPoint(x: 260, y: 900), startRadius: 0,
                       endCenter: CGPoint(x: 260, y: 900), endRadius: 560, options: [])
ctx.restoreGState()

// MARK: Glyph — three finder patterns + send (macOS) / receive (iOS) arrow
let white = rgb(0xFFFFFF)
let side: CGFloat = 176
let gap: CGFloat = 80
let origin = (1024 - (side * 2 + gap)) / 2
let low = origin, high = origin + side + gap

func finder(_ x: CGFloat, _ y: CGFloat) {
    let outer = CGRect(x: x, y: y, width: side, height: side)
    ctx.addPath(rounded(outer, 52))
    ctx.addPath(rounded(outer.insetBy(dx: 30, dy: 30), 26))
    ctx.setFillColor(white)
    ctx.fillPath(using: .evenOdd)
    ctx.addPath(rounded(outer.insetBy(dx: 58, dy: 58), 18))
    ctx.fillPath()
}

ctx.saveGState()
ctx.setShadow(offset: CGSize(width: 0, height: -8), blur: 22, color: rgb(0x1A2A8A, 0.25))
ctx.beginTransparencyLayer(auxiliaryInfo: nil)

finder(low, high)
finder(high, high)
finder(low, low)

let cy = low + side / 2
let left = high + 22, right = high + side - 22
let (tail, tip) = ios ? (right, left) : (left, right)
let head: CGFloat = ios ? -52 : 52
ctx.setStrokeColor(white)
ctx.setLineWidth(30)
ctx.setLineCap(.round)
ctx.setLineJoin(.round)
ctx.move(to: CGPoint(x: tail, y: cy))
ctx.addLine(to: CGPoint(x: tip, y: cy))
ctx.move(to: CGPoint(x: tip - head, y: cy + abs(head)))
ctx.addLine(to: CGPoint(x: tip, y: cy))
ctx.addLine(to: CGPoint(x: tip - head, y: cy - abs(head)))
ctx.strokePath()

ctx.endTransparencyLayer()
ctx.restoreGState()

// MARK: Write PNG
let png = NSBitmapImageRep(cgImage: ctx.makeImage()!).representation(using: .png, properties: [:])!
try! png.write(to: URL(fileURLWithPath: CommandLine.arguments[1]))
