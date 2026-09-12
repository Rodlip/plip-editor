import AppKit

let destination = CommandLine.arguments[1]
try FileManager.default.createDirectory(atPath: destination, withIntermediateDirectories: true)
var images: [String: Data] = [:]
for size in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let pixels = size * scale
        let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        NSGraphicsContext.current?.imageInterpolation = .high
        let transform = NSAffineTransform(); transform.scale(by: CGFloat(pixels) / 1024); transform.concat()
        let body = NSBezierPath(roundedRect: NSRect(x: 82, y: 82, width: 860, height: 860), xRadius: 192, yRadius: 192)
        NSGraphicsContext.saveGraphicsState()
        let shadow = NSShadow(); shadow.shadowColor = NSColor.black.withAlphaComponent(0.22); shadow.shadowBlurRadius = 24; shadow.shadowOffset = NSSize(width: 0, height: -10); shadow.set()
        NSColor(calibratedRed: 0.22, green: 0.29, blue: 0.78, alpha: 1).setFill(); body.fill()
        NSGraphicsContext.restoreGraphicsState()
        NSGradient(colors: [NSColor(calibratedRed: 0.18, green: 0.71, blue: 0.99, alpha: 1), NSColor(calibratedRed: 0.22, green: 0.39, blue: 0.94, alpha: 1), NSColor(calibratedRed: 0.38, green: 0.22, blue: 0.76, alpha: 1)])!.draw(in: body, angle: -65)
        NSColor.white.withAlphaComponent(0.22).setStroke(); body.lineWidth = 3; body.stroke()
        let back = NSBezierPath(roundedRect: NSRect(x: 272, y: 225, width: 520, height: 604), xRadius: 64, yRadius: 64)
        NSColor.white.withAlphaComponent(0.27).setFill(); back.fill()
        let paper = NSBezierPath(roundedRect: NSRect(x: 224, y: 196, width: 540, height: 606), xRadius: 66, yRadius: 66)
        NSGraphicsContext.saveGraphicsState()
        let paperShadow = NSShadow(); paperShadow.shadowColor = NSColor(calibratedRed: 0.08, green: 0.13, blue: 0.40, alpha: 0.30); paperShadow.shadowBlurRadius = 34; paperShadow.shadowOffset = NSSize(width: 0, height: -16); paperShadow.set()
        NSColor.white.setFill(); paper.fill()
        NSGraphicsContext.restoreGraphicsState()
        NSGradient(starting: .white, ending: NSColor(calibratedRed: 0.92, green: 0.95, blue: 1, alpha: 1))!.draw(in: paper, angle: -90)
        let ink = NSColor(calibratedRed: 0.26, green: 0.35, blue: 0.73, alpha: 1)
        ink.setStroke()
        let tree = NSBezierPath(); tree.lineWidth = 24; tree.lineCapStyle = .round; tree.lineJoinStyle = .round
        tree.move(to: NSPoint(x: 333, y: 667)); tree.line(to: NSPoint(x: 333, y: 349)); tree.line(to: NSPoint(x: 412, y: 349))
        tree.move(to: NSPoint(x: 333, y: 504)); tree.line(to: NSPoint(x: 412, y: 504)); tree.stroke()
        for (y, width) in [(667.0, 214.0), (504.0, 181.0), (349.0, 137.0)] {
            ink.setFill()
            NSBezierPath(roundedRect: NSRect(x: y == 667 ? 415 : 470, y: y - 14, width: width, height: 28), xRadius: 14, yRadius: 14).fill()
        }
        for y in [504.0, 349.0] {
            NSColor(calibratedRed: 0.08, green: 0.66, blue: 0.75, alpha: 1).setFill()
            NSBezierPath(roundedRect: NSRect(x: 403, y: y - 23, width: 46, height: 46), xRadius: 12, yRadius: 12).fill()
        }
        NSGraphicsContext.restoreGraphicsState()
        let name = "\(size)x\(size)\(scale == 2 ? "@2x" : "")"
        let png = rep.representation(using: .png, properties: [:])!
        images[name] = png
        try png.write(to: URL(fileURLWithPath: "\(destination)/icon_\(name).png"))
    }
}
// Modern ICNS representations contain lossless PNG payloads at each native size.
func word(_ value: Int) -> Data {
    var bigEndian = UInt32(value).bigEndian
    return withUnsafeBytes(of: &bigEndian) { Data($0) }
}
var chunks = Data()
for (tag, name) in [("icp4", "16x16"), ("icp5", "32x32"), ("ic07", "128x128"), ("ic08", "256x256"), ("ic09", "512x512"), ("ic10", "512x512@2x"), ("ic11", "16x16@2x"), ("ic12", "32x32@2x"), ("ic13", "128x128@2x"), ("ic14", "256x256@2x")] {
    let png = images[name]!
    chunks.append(Data(tag.utf8)); chunks.append(word(png.count + 8)); chunks.append(png)
}
var icon = Data("icns".utf8); icon.append(word(chunks.count + 8)); icon.append(chunks)
try icon.write(to: URL(fileURLWithPath: "\(destination)/PlipIcon.icns"))
