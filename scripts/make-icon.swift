import AppKit

let root = URL(fileURLWithPath: CommandLine.arguments[1])
try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
let sizes = [16, 32, 128, 256, 512]
for size in sizes {
    for scale in [1, 2] {
        let pixels = size * scale
        let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels,
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
            colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        let context = NSGraphicsContext.current!.cgContext
        context.scaleBy(x: CGFloat(pixels) / 1024, y: CGFloat(pixels) / 1024)
        let background = NSBezierPath(roundedRect: NSRect(x: 52, y: 52, width: 920, height: 920), xRadius: 215, yRadius: 215)
        NSColor(calibratedRed: 0.88, green: 0.94, blue: 0.88, alpha: 1).setFill()
        background.fill()
        NSColor(calibratedRed: 0.22, green: 0.43, blue: 0.33, alpha: 1).setStroke()
        let corners = NSBezierPath()
        corners.lineWidth = 48
        corners.lineCapStyle = .round
        corners.lineJoinStyle = .round
        for (x, y, dx, dy) in [(280.0, 280.0, 1.0, 1.0), (744, 280, -1, 1), (280, 744, 1, -1), (744, 744, -1, -1)] {
            corners.move(to: NSPoint(x: x + dx * 120, y: y))
            corners.line(to: NSPoint(x: x, y: y))
            corners.line(to: NSPoint(x: x, y: y + dy * 120))
        }
        corners.stroke()
        NSColor(calibratedRed: 0.22, green: 0.43, blue: 0.33, alpha: 1).setFill()
        NSBezierPath(ovalIn: NSRect(x: 466, y: 466, width: 92, height: 92)).fill()
        NSGraphicsContext.restoreGraphicsState()
        let data = rep.representation(using: .png, properties: [:])!
        let suffix = scale == 2 ? "@2x" : ""
        try data.write(to: root.appendingPathComponent("icon_\(size)x\(size)\(suffix).png"))
    }
}

// ICNS stores modern icon representations as length-prefixed PNG chunks.
func bigEndian(_ value: Int) -> Data {
    var number = UInt32(value).bigEndian
    return withUnsafeBytes(of: &number) { Data($0) }
}
var chunks = Data()
for (tag, filename) in [("ic07", "icon_128x128.png"), ("ic08", "icon_256x256.png"),
                         ("ic09", "icon_512x512.png"), ("ic10", "icon_512x512@2x.png")] {
    let png = try Data(contentsOf: root.appendingPathComponent(filename))
    chunks.append(Data(tag.utf8))
    chunks.append(bigEndian(png.count + 8))
    chunks.append(png)
}
var icon = Data("icns".utf8)
icon.append(bigEndian(chunks.count + 8))
icon.append(chunks)
try icon.write(to: URL(fileURLWithPath: CommandLine.arguments[2]))
