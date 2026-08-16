import AppKit
import Foundation

guard CommandLine.arguments.count == 2 else {
    fputs("Usage: swift make_icon.swift output.png\n", stderr)
    exit(1)
}

let output = URL(fileURLWithPath: CommandLine.arguments[1])
let size = NSSize(width: 1024, height: 1024)
let image = NSImage(size: size)

image.lockFocus()

let canvas = NSRect(origin: .zero, size: size)
let tileRect = canvas.insetBy(dx: 74, dy: 74)
let tile = NSBezierPath(roundedRect: tileRect, xRadius: 220, yRadius: 220)
let gradient = NSGradient(colors: [
    NSColor(red: 0.55, green: 0.49, blue: 0.71, alpha: 1),
    NSColor(red: 0.36, green: 0.31, blue: 0.52, alpha: 1)
])!
gradient.draw(in: tile, angle: -48)

NSGraphicsContext.current?.saveGraphicsState()
let shadow = NSShadow()
shadow.shadowColor = NSColor.black.withAlphaComponent(0.22)
shadow.shadowBlurRadius = 34
shadow.shadowOffset = NSSize(width: 0, height: -18)
shadow.set()
let faceRect = NSRect(x: 244, y: 244, width: 536, height: 536)
NSColor.white.setFill()
NSBezierPath(ovalIn: faceRect).fill()
NSGraphicsContext.current?.restoreGraphicsState()

let ringRect = faceRect.insetBy(dx: 28, dy: 28)
let ring = NSBezierPath()
ring.appendArc(withCenter: NSPoint(x: ringRect.midX, y: ringRect.midY), radius: ringRect.width / 2, startAngle: 104, endAngle: 370)
ring.lineWidth = 42
ring.lineCapStyle = .round
NSColor(red: 0.85, green: 0.36, blue: 0.31, alpha: 1).setStroke()
ring.stroke()

let center = NSPoint(x: faceRect.midX, y: faceRect.midY)
let hand = NSBezierPath()
hand.move(to: center)
hand.line(to: NSPoint(x: center.x, y: center.y + 138))
hand.lineWidth = 25
hand.lineCapStyle = .round
NSColor(red: 0.18, green: 0.17, blue: 0.22, alpha: 1).setStroke()
hand.stroke()

NSColor(red: 0.85, green: 0.36, blue: 0.31, alpha: 1).setFill()
NSBezierPath(ovalIn: NSRect(x: center.x - 31, y: center.y - 31, width: 62, height: 62)).fill()

image.unlockFocus()

guard let tiff = image.tiffRepresentation,
      let bitmap = NSBitmapImageRep(data: tiff),
      let png = bitmap.representation(using: .png, properties: [:]) else {
    fputs("Could not render icon\n", stderr)
    exit(1)
}
try png.write(to: output)
