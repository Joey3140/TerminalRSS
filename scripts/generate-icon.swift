#!/usr/bin/env swift
import Cocoa

// Terminal-style icon generator for TerminalRSS
// Dark background, Iosevka-style thin monospace "_T", green cursor glow

func drawIosevkaT(in ctx: CGContext, cx: CGFloat, cy: CGFloat, s: CGFloat) {
    // Iosevka-style T: thin uniform strokes, geometric, with subtle serifs
    let strokeW = s * 0.06
    let letterH = s * 0.336
    let letterW = s * 0.256

    let topY = cy + letterH * 0.5
    let botY = cy - letterH * 0.5
    let color = NSColor(red: 0.0, green: 0.9, blue: 0.3, alpha: 1.0)

    ctx.setStrokeColor(color.cgColor)
    ctx.setLineWidth(strokeW)
    ctx.setLineCap(.butt)
    ctx.setLineJoin(.miter)

    // Horizontal bar of T (top)
    ctx.move(to: CGPoint(x: cx - letterW / 2, y: topY))
    ctx.addLine(to: CGPoint(x: cx + letterW / 2, y: topY))
    ctx.strokePath()

    // Vertical stem of T
    ctx.move(to: CGPoint(x: cx, y: topY))
    ctx.addLine(to: CGPoint(x: cx, y: botY))
    ctx.strokePath()

    // Small serifs at ends of horizontal bar (Iosevka style)
    let serifLen = strokeW * 1.8
    // Left serif (downward tick)
    ctx.move(to: CGPoint(x: cx - letterW / 2, y: topY))
    ctx.addLine(to: CGPoint(x: cx - letterW / 2, y: topY - serifLen))
    ctx.strokePath()
    // Right serif (downward tick)
    ctx.move(to: CGPoint(x: cx + letterW / 2, y: topY))
    ctx.addLine(to: CGPoint(x: cx + letterW / 2, y: topY - serifLen))
    ctx.strokePath()

    // Small serif at bottom of stem (horizontal)
    let botSerifW = strokeW * 2.2
    ctx.move(to: CGPoint(x: cx - botSerifW, y: botY))
    ctx.addLine(to: CGPoint(x: cx + botSerifW, y: botY))
    ctx.strokePath()
}

func drawTerminalUnderscore(in ctx: CGContext, rightEdgeX: CGFloat, baseY: CGFloat, s: CGFloat) {
    // Terminal underscore cursor "_" — blinking cursor style, positioned before the letter
    let cursorW = s * 0.112
    let cursorH = s * 0.05
    let color = NSColor(red: 0, green: 1.0, blue: 0.25, alpha: 1.0)

    // Underscore bar
    color.setFill()
    let rect = NSRect(x: rightEdgeX - cursorW, y: baseY, width: cursorW, height: cursorH)
    NSBezierPath(rect: rect).fill()

    // Glow
    let glowColor = NSColor(red: 0, green: 1.0, blue: 0.25, alpha: 0.25)
    glowColor.setFill()
    let glowRect = NSRect(x: rect.minX - s * 0.02, y: rect.minY - s * 0.012,
                          width: rect.width + s * 0.04, height: rect.height + s * 0.024)
    NSBezierPath(roundedRect: glowRect, xRadius: 2, yRadius: 2).fill()
}

func renderIcon(pixelSize: Int) -> Data {
    let s = CGFloat(pixelSize)
    let image = NSImage(size: NSSize(width: s, height: s))

    image.lockFocus()
    let ctx = NSGraphicsContext.current!.cgContext

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

    // Green glow behind text (subtle)
    let glowCenter = NSPoint(x: s / 2 + s * 0.04, y: s / 2 + s * 0.02)
    let glowRadius = s * 0.25
    let orangeGlow = NSGradient(colors: [
        NSColor(red: 0.0, green: 0.8, blue: 0.2, alpha: 0.08),
        NSColor(red: 0.0, green: 0.8, blue: 0.2, alpha: 0.0),
    ])!
    orangeGlow.draw(fromCenter: glowCenter, radius: 0,
                    toCenter: glowCenter, radius: glowRadius, options: [])

    // Draw the Iosevka-style "T" — shifted right slightly to make room for underscore
    let letterCX = s / 2 + s * 0.04
    let letterCY = s / 2 + s * 0.02
    drawIosevkaT(in: ctx, cx: letterCX, cy: letterCY, s: s)

    // Draw terminal underscore "_" before the T
    let letterH = s * 0.336
    let letterW = s * 0.256
    let underscoreBaseY = letterCY - letterH * 0.5
    let underscoreRightX = letterCX - letterW / 2 - s * 0.025
    drawTerminalUnderscore(in: ctx, rightEdgeX: underscoreRightX, baseY: underscoreBaseY, s: s)

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
