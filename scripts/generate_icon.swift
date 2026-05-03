import AppKit
import Foundation

guard CommandLine.arguments.count == 2 else {
    fputs("Usage: swift scripts/generate_icon.swift <iconset-dir>\n", stderr)
    exit(2)
}

let iconsetURL = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
try FileManager.default.createDirectory(at: iconsetURL, withIntermediateDirectories: true)

func drawIcon(size: CGFloat) -> NSImage {
    let image = NSImage(size: NSSize(width: size, height: size))
    image.lockFocus()
    defer { image.unlockFocus() }

    let rect = NSRect(x: 0, y: 0, width: size, height: size)
    NSColor(calibratedRed: 0.05, green: 0.52, blue: 0.86, alpha: 1).setFill()
    rect.fill()

    let background = rect.insetBy(dx: size * 0.035, dy: size * 0.035)
    NSColor(calibratedRed: 0.10, green: 0.57, blue: 0.88, alpha: 1).setFill()
    NSBezierPath(roundedRect: background, xRadius: size * 0.18, yRadius: size * 0.18).fill()

    NSColor.white.withAlphaComponent(0.18).setStroke()
    let highlight = NSBezierPath(roundedRect: background.insetBy(dx: size * 0.018, dy: size * 0.018), xRadius: size * 0.16, yRadius: size * 0.16)
    highlight.lineWidth = max(1, size * 0.012)
    highlight.stroke()

    let video = NSBezierPath(roundedRect: NSRect(x: size * 0.18, y: size * 0.47, width: size * 0.44, height: size * 0.27), xRadius: size * 0.04, yRadius: size * 0.04)
    NSColor.white.withAlphaComponent(0.95).setFill()
    video.fill()

    let play = NSBezierPath()
    play.move(to: NSPoint(x: size * 0.34, y: size * 0.52))
    play.line(to: NSPoint(x: size * 0.34, y: size * 0.69))
    play.line(to: NSPoint(x: size * 0.49, y: size * 0.605))
    play.close()
    NSColor(calibratedRed: 0.05, green: 0.13, blue: 0.18, alpha: 1).setFill()
    play.fill()

    let noteStem = NSBezierPath(roundedRect: NSRect(x: size * 0.67, y: size * 0.34, width: size * 0.045, height: size * 0.36), xRadius: size * 0.015, yRadius: size * 0.015)
    NSColor(calibratedRed: 1.00, green: 0.78, blue: 0.20, alpha: 1).setFill()
    noteStem.fill()
    NSBezierPath(ovalIn: NSRect(x: size * 0.56, y: size * 0.27, width: size * 0.17, height: size * 0.13)).fill()
    let beam = NSBezierPath()
    beam.move(to: NSPoint(x: size * 0.70, y: size * 0.68))
    beam.line(to: NSPoint(x: size * 0.84, y: size * 0.63))
    beam.line(to: NSPoint(x: size * 0.84, y: size * 0.55))
    beam.line(to: NSPoint(x: size * 0.70, y: size * 0.60))
    beam.close()
    beam.fill()

    let paragraph = NSMutableParagraphStyle()
    paragraph.alignment = .center
    let attrs: [NSAttributedString.Key: Any] = [
        .font: NSFont.boldSystemFont(ofSize: size * 0.12),
        .foregroundColor: NSColor.white,
        .paragraphStyle: paragraph
    ]
    "MP3".draw(in: NSRect(x: size * 0.18, y: size * 0.17, width: size * 0.64, height: size * 0.16), withAttributes: attrs)

    return image
}

func writePNG(image: NSImage, url: URL) throws {
    guard let tiff = image.tiffRepresentation,
          let bitmap = NSBitmapImageRep(data: tiff),
          let png = bitmap.representation(using: .png, properties: [:]) else {
        throw NSError(domain: "IconGeneration", code: 1)
    }
    try png.write(to: url, options: [.atomic])
}

let variants: [(CGFloat, String)] = [
    (16, "icon_16x16.png"),
    (32, "icon_16x16@2x.png"),
    (32, "icon_32x32.png"),
    (64, "icon_32x32@2x.png"),
    (128, "icon_128x128.png"),
    (256, "icon_128x128@2x.png"),
    (256, "icon_256x256.png"),
    (512, "icon_256x256@2x.png"),
    (512, "icon_512x512.png"),
    (1024, "icon_512x512@2x.png")
]

for (size, name) in variants {
    try writePNG(image: drawIcon(size: size), url: iconsetURL.appendingPathComponent(name))
}
