import AppKit

let directory = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
for size in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let pixels = size * scale
        let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels,
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
            colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        let unit = CGFloat(pixels) / 1024
        NSAffineTransform().withScale(unit)
        NSColor(red: 0.055, green: 0.075, blue: 0.10, alpha: 1).setFill()
        NSBezierPath(roundedRect: NSRect(x: 58, y: 58, width: 908, height: 908), xRadius: 204, yRadius: 204).fill()
        let mint = NSColor(red: 0.43, green: 0.94, blue: 0.76, alpha: 1)
        for row in 0..<3 {
            for col in 0..<3 {
                let active = row == 1 && col == 1
                (active ? mint : NSColor.white.withAlphaComponent(0.15)).setFill()
                let rect = NSRect(x: 207 + col * 211, y: 207 + row * 211, width: 188, height: 188)
                NSBezierPath(roundedRect: rect, xRadius: 39, yRadius: 39).fill()
                if active {
                    let attributes: [NSAttributedString.Key: Any] = [
                        .font: NSFont.systemFont(ofSize: 136, weight: .medium),
                        .foregroundColor: NSColor(red: 0.055, green: 0.075, blue: 0.10, alpha: 1)
                    ]
                    let text = "5" as NSString
                    let measure = text.size(withAttributes: attributes)
                    text.draw(at: NSPoint(x: rect.midX - measure.width / 2, y: rect.midY - measure.height / 2), withAttributes: attributes)
                }
            }
        }
        NSGraphicsContext.restoreGraphicsState()
        let suffix = scale == 2 ? "@2x" : ""
        try rep.representation(using: .png, properties: [:])!.write(to: directory.appendingPathComponent("icon_\(size)x\(size)\(suffix).png"))
    }
}

extension NSAffineTransform {
    func withScale(_ scale: CGFloat) { scaleX(by: scale, yBy: scale); concat() }
}
