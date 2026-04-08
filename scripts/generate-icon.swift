#!/usr/bin/env swift
import Cocoa

// Bloomberg terminal-style "T" icon generator
// Black background, orange T, blue border, green cursor

func renderIcon(pixelSize: Int) -> Data {
    let s = CGFloat(pixelSize)
    let image = NSImage(size: NSSize(width: s, height: s))

    image.lockFocus()

    // Background — near-black with rounded corners
    let radius = s * 0.20
    let bg = NSBezierPath(roundedRect: NSRect(x: 0, y: 0, width: s, height: s),
                          xRadius: radius, yRadius: radius)
    NSColor(red: 0.03, green: 0.03, blue: 0.06, alpha: 1.0).setFill()
    bg.fill()

    // Inner border — Bloomberg dark blue
    let bw = max(s * 0.025, 1)
    let inset = bw * 1.5
    let borderRect = NSRect(x: inset, y: inset, width: s - inset * 2, height: s - inset * 2)
    let border = NSBezierPath(roundedRect: borderRect,
                              xRadius: radius * 0.85, yRadius: radius * 0.85)
    border.lineWidth = bw
    NSColor(red: 0.0, green: 0.18, blue: 0.50, alpha: 0.9).setStroke()
    border.stroke()

    // Second inner border — subtle Bloomberg panel line
    let inset2 = inset + bw * 2.5
    let innerRect = NSRect(x: inset2, y: inset2, width: s - inset2 * 2, height: s - inset2 * 2)
    let inner = NSBezierPath(roundedRect: innerRect,
                             xRadius: radius * 0.75, yRadius: radius * 0.75)
    inner.lineWidth = max(bw * 0.4, 0.5)
    NSColor(red: 0.15, green: 0.15, blue: 0.20, alpha: 0.7).setStroke()
    inner.stroke()

    // "T" — bold monospace, Bloomberg orange
    let fontSize = s * 0.58
    let font = NSFont.monospacedSystemFont(ofSize: fontSize, weight: .black)
    let tColor = NSColor(red: 1.0, green: 0.55, blue: 0.0, alpha: 1.0)
    let shadow = NSShadow()
    shadow.shadowColor = NSColor(red: 1.0, green: 0.4, blue: 0.0, alpha: 0.3)
    shadow.shadowBlurRadius = s * 0.03
    shadow.shadowOffset = NSSize(width: 0, height: 0)

    let attrs: [NSAttributedString.Key: Any] = [
        .font: font,
        .foregroundColor: tColor,
        .shadow: shadow,
    ]
    let attrStr = NSAttributedString(string: "T", attributes: attrs)
    let textSize = attrStr.size()
    let tx = (s - textSize.width) / 2
    let ty = (s - textSize.height) / 2 + s * 0.04
    attrStr.draw(at: NSPoint(x: tx, y: ty))

    // Green cursor block — terminal feel
    let cursorW = s * 0.10
    let cursorH = max(s * 0.028, 1)
    let cursorX = (s - cursorW) / 2
    let cursorY = ty - s * 0.005
    let cursorColor = NSColor(red: 0, green: 1.0, blue: 0.25, alpha: 0.9)
    cursorColor.setFill()
    NSBezierPath(rect: NSRect(x: cursorX, y: cursorY, width: cursorW, height: cursorH)).fill()

    // Subtle green glow on cursor
    let glowColor = NSColor(red: 0, green: 1.0, blue: 0.25, alpha: 0.15)
    glowColor.setFill()
    let glowRect = NSRect(x: cursorX - s * 0.02, y: cursorY - s * 0.01,
                          width: cursorW + s * 0.04, height: cursorH + s * 0.02)
    NSBezierPath(roundedRect: glowRect, xRadius: 2, yRadius: 2).fill()

    image.unlockFocus()

    guard let tiff = image.tiffRepresentation,
          let bitmap = NSBitmapImageRep(data: tiff),
          let png = bitmap.representation(using: .png, properties: [:]) else {
        fatalError("Failed to render icon at size \(pixelSize)")
    }
    return png
}

// Generate iconset
let projectDir = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "."
let iconsetDir = "\(projectDir)/TerminalRSS.iconset"

let fm = FileManager.default
try? fm.removeItem(atPath: iconsetDir)
try fm.createDirectory(atPath: iconsetDir, withIntermediateDirectories: true)

let sizes: [(name: String, pixels: Int)] = [
    ("icon_16x16.png", 16),
    ("icon_16x16@2x.png", 32),
    ("icon_32x32.png", 32),
    ("icon_32x32@2x.png", 64),
    ("icon_128x128.png", 128),
    ("icon_128x128@2x.png", 256),
    ("icon_256x256.png", 256),
    ("icon_256x256@2x.png", 512),
    ("icon_512x512.png", 512),
    ("icon_512x512@2x.png", 1024),
]

for (name, pixels) in sizes {
    let data = renderIcon(pixelSize: pixels)
    let path = "\(iconsetDir)/\(name)"
    try data.write(to: URL(fileURLWithPath: path))
    print("  \(name) (\(pixels)px)")
}

// Convert to .icns
let icnsPath = "\(projectDir)/TerminalRSS.icns"
let process = Process()
process.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
process.arguments = ["-c", "icns", iconsetDir, "-o", icnsPath]
try process.run()
process.waitUntilExit()

if process.terminationStatus == 0 {
    try? fm.removeItem(atPath: iconsetDir)
    print("Generated \(icnsPath)")
} else {
    print("iconutil failed with status \(process.terminationStatus)")
}
