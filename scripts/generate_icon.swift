#!/usr/bin/env swift
import AppKit
import Foundation

guard CommandLine.arguments.count >= 2 else {
    fputs("Usage: generate_icon.swift <output_iconset_dir>\n", stderr)
    exit(1)
}

let iconsetDir = CommandLine.arguments[1]
try FileManager.default.createDirectory(atPath: iconsetDir, withIntermediateDirectories: true)

func renderIcon(size: Int) -> Data? {
    let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil,
        pixelsWide: size,
        pixelsHigh: size,
        bitsPerSample: 8,
        samplesPerPixel: 4,
        hasAlpha: true,
        isPlanar: false,
        colorSpaceName: .deviceRGB,
        bytesPerRow: 0,
        bitsPerPixel: 0
    )!

    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    guard let ctx = NSGraphicsContext.current?.cgContext else { return nil }

    let s = CGFloat(size)
    let inset = s * 0.06
    let rect = CGRect(x: inset, y: inset, width: s - inset * 2, height: s - inset * 2)
    let corner = s * 0.22

    // Rounded background with Doubao-inspired vibrant indigo-blue gradient
    let path = CGPath(roundedRect: rect, cornerWidth: corner, cornerHeight: corner, transform: nil)
    ctx.saveGState()
    ctx.addPath(path)
    ctx.clip()

    let colorSpace = CGColorSpaceCreateDeviceRGB()
    let colors = [
        CGColor(red: 0.18, green: 0.44, blue: 0.99, alpha: 1.0),
        CGColor(red: 0.42, green: 0.30, blue: 0.96, alpha: 1.0),
        CGColor(red: 0.56, green: 0.26, blue: 0.92, alpha: 1.0)
    ] as CFArray
    if let grad = CGGradient(colorsSpace: colorSpace, colors: colors, locations: [0.0, 0.55, 1.0]) {
        ctx.drawLinearGradient(
            grad,
            start: CGPoint(x: rect.minX, y: rect.maxY),
            end: CGPoint(x: rect.maxX, y: rect.minY),
            options: []
        )
    }

    // Subtle top highlight glow
    let glowColors = [
        CGColor(red: 1, green: 1, blue: 1, alpha: 0.22),
        CGColor(red: 1, green: 1, blue: 1, alpha: 0.0)
    ] as CFArray
    if let radial = CGGradient(colorsSpace: colorSpace, colors: glowColors, locations: [0.0, 1.0]) {
        ctx.drawRadialGradient(
            radial,
            startCenter: CGPoint(x: s * 0.3, y: s * 0.8),
            startRadius: 0,
            endCenter: CGPoint(x: s * 0.3, y: s * 0.8),
            endRadius: s * 0.55,
            options: []
        )
    }
    ctx.restoreGState()

    // Draw crisp white waveform bars in center
    let barHeights: [CGFloat] = [0.20, 0.38, 0.52, 0.32, 0.44, 0.22]
    let barWidth = s * 0.068
    let spacing = s * 0.044
    let totalWidth = CGFloat(barHeights.count) * barWidth + CGFloat(barHeights.count - 1) * spacing
    let startX = (s - totalWidth) / 2.0

    ctx.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 0.96))
    for (idx, hRatio) in barHeights.enumerated() {
        let h = s * hRatio
        let x = startX + CGFloat(idx) * (barWidth + spacing)
        let y = (s - h) / 2.0 - s * 0.02
        let barRect = CGRect(x: x, y: y, width: barWidth, height: h)
        let barPath = CGPath(roundedRect: barRect, cornerWidth: barWidth / 2, cornerHeight: barWidth / 2, transform: nil)
        ctx.addPath(barPath)
        ctx.fillPath()
    }

    // Draw 4-point AI sparkle star at top-right
    let cx = s * 0.76
    let cy = s * 0.77
    let rOuter = s * 0.095
    let rInner = s * 0.028
    let star = CGMutablePath()
    for i in 0..<8 {
        let angle = CGFloat(i) * .pi / 4.0
        let r = (i % 2 == 0) ? rOuter : rInner
        let px = cx + cos(angle) * r
        let py = cy + sin(angle) * r
        if i == 0 { star.move(to: CGPoint(x: px, y: py)) }
        else { star.addLine(to: CGPoint(x: px, y: py)) }
    }
    star.closeSubpath()
    ctx.setFillColor(CGColor(red: 1.0, green: 0.95, blue: 0.65, alpha: 1.0))
    ctx.addPath(star)
    ctx.fillPath()

    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])
}

let specs: [(String, Int)] = [
    ("icon_16x16.png", 16),
    ("icon_16x16@2x.png", 32),
    ("icon_32x32.png", 32),
    ("icon_32x32@2x.png", 64),
    ("icon_128x128.png", 128),
    ("icon_128x128@2x.png", 256),
    ("icon_256x256.png", 256),
    ("icon_256x256@2x.png", 512),
    ("icon_512x512.png", 512),
    ("icon_512x512@2x.png", 1024)
]

for (name, px) in specs {
    if let data = renderIcon(size: px) {
        let url = URL(fileURLWithPath: iconsetDir).appendingPathComponent(name)
        try data.write(to: url)
    }
}
print("Generated iconset at \(iconsetDir)")
