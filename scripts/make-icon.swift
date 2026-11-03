// Draws the app icon: a couch with a couchbar tray on its arm, on the macOS icon grid.
// Usage: swift scripts/make-icon.swift <output.png> [size]
import AppKit

let output = CommandLine.arguments[1]
let size = CommandLine.arguments.count > 2 ? Int(CommandLine.arguments[2])! : 1024

func color(_ hex: UInt32, _ alpha: CGFloat = 1) -> NSColor {
    NSColor(srgbRed: CGFloat(hex >> 16 & 0xFF) / 255, green: CGFloat(hex >> 8 & 0xFF) / 255, blue: CGFloat(hex & 0xFF) / 255, alpha: alpha)
}

func rounded(_ x: CGFloat, _ y: CGFloat, _ width: CGFloat, _ height: CGFloat, _ radius: CGFloat) -> NSBezierPath {
    NSBezierPath(roundedRect: NSRect(x: x, y: y, width: width, height: height), xRadius: radius, yRadius: radius)
}

func fill(_ path: NSBezierPath, _ top: UInt32, _ bottom: UInt32) {
    NSGradient(starting: color(bottom), ending: color(top))!.draw(in: path, angle: 90)
}

func withShadow(_ shadowColor: NSColor, blur: CGFloat, offset: NSSize = .zero, _ draw: () -> Void) {
    NSGraphicsContext.saveGraphicsState()
    let shadow = NSShadow()
    shadow.shadowColor = shadowColor
    shadow.shadowBlurRadius = blur
    shadow.shadowOffset = offset
    shadow.set()
    draw()
    NSGraphicsContext.restoreGraphicsState()
}

let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: size, pixelsHigh: size, bitsPerSample: 8, samplesPerPixel: 4,
                           hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
NSGraphicsContext.current!.imageInterpolation = .high
let scale = CGFloat(size) / 1024
NSGraphicsContext.current!.cgContext.scaleBy(x: scale, y: scale)

// Apple's icon grid: an 824 pt rounded square centred on a 1024 pt canvas, with a soft drop shadow.
let plate = rounded(100, 100, 824, 824, 185)
withShadow(color(0x000000, 0.35), blur: 24, offset: NSSize(width: 0, height: -12)) {
    fill(plate, 0x2E2F7A, 0x111233)
}

NSGraphicsContext.saveGraphicsState()
plate.addClip()
NSGradient(starting: color(0x5AA8FF, 0.5), ending: color(0x5AA8FF, 0))!
    .draw(fromCenter: NSPoint(x: 512, y: 560), radius: 0, toCenter: NSPoint(x: 512, y: 560), radius: 470, options: [])

let outline = color(0x15163A)
func part(_ path: NSBezierPath, _ top: UInt32, _ bottom: UInt32) {
    fill(path, top, bottom)
    outline.setStroke()
    path.lineWidth = 10
    path.stroke()
}

// The couch, facing you.
for x: CGFloat in [204, 790] {
    fill(rounded(x, 290, 30, 56, 10), 0x7A3A2A, 0x4D2318)
}
withShadow(color(0x000000, 0.35), blur: 40, offset: NSSize(width: 0, height: -16)) {
    part(rounded(262, 410, 500, 300, 64), 0xFFB774, 0xFF8A52)
}
part(rounded(262, 330, 250, 150, 40), 0xFF9C5E, 0xEE6540)
part(rounded(512, 330, 250, 150, 40), 0xFF9C5E, 0xEE6540)
part(rounded(160, 320, 150, 290, 66), 0xFFAD6A, 0xF4703F)
part(rounded(714, 320, 150, 290, 66), 0xFFAD6A, 0xF4703F)

// A couchbar, the wooden tray that rests on a sofa arm, with a mug and a glass on it.
part(rounded(698, 520, 26, 82, 8), 0xC98E55, 0xA9703D)
part(rounded(854, 520, 26, 82, 8), 0xC98E55, 0xA9703D)
part(rounded(684, 562, 210, 48, 12), 0xE9BE86, 0xC08750)
let handle = NSBezierPath(ovalIn: NSRect(x: 768, y: 628, width: 34, height: 36))
outline.setStroke()
handle.lineWidth = 10
handle.stroke()
part(rounded(718, 610, 62, 72, 14), 0xFFFFFF, 0xE2E6F0)
part(rounded(812, 610, 44, 98, 12), 0xBDEBFF, 0x7FC8F0)
fill(rounded(817, 615, 34, 54, 8), 0xFFC34D, 0xF29A1F)
NSGraphicsContext.restoreGraphicsState()

try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: output))
