#!/usr/bin/env swift

import AppKit
import CoreGraphics

let outputPath = CommandLine.arguments.count > 1
    ? CommandLine.arguments[1]
    : "/Users/michaelwildenauer/-Coding/Tippi/icons/tippi-icon-1024.png"

let size: CGFloat = 1024
let width = Int(size)
let height = Int(size)

let colorSpace = CGColorSpaceCreateDeviceRGB()

guard let ctx = CGContext(
    data: nil,
    width: width,
    height: height,
    bitsPerComponent: 8,
    bytesPerRow: 0,
    space: colorSpace,
    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
) else {
    fputs("Failed to create CGContext\n", stderr)
    exit(1)
}

let canvas = CGRect(x: 0, y: 0, width: size, height: size)
let cornerRadius: CGFloat = 224

let squirclePath = CGPath(
    roundedRect: canvas,
    cornerWidth: cornerRadius,
    cornerHeight: cornerRadius,
    transform: nil
)

// 1) Background gradient (very subtle, light gray → near-white from bottom to top)
ctx.saveGState()
ctx.addPath(squirclePath)
ctx.clip()

let bgColors = [
    CGColor(red: 0.976, green: 0.980, blue: 0.984, alpha: 1.0),
    CGColor(red: 0.910, green: 0.918, blue: 0.929, alpha: 1.0)
] as CFArray
let bgLocations: [CGFloat] = [0.0, 1.0]
let bgGradient = CGGradient(colorsSpace: colorSpace, colors: bgColors, locations: bgLocations)!
ctx.drawLinearGradient(
    bgGradient,
    start: CGPoint(x: 0, y: size),
    end: CGPoint(x: 0, y: 0),
    options: []
)
ctx.restoreGState()

// 2) Keycap with soft shadow
let keycapInset: CGFloat = 240
let keycapRect = CGRect(
    x: keycapInset,
    y: keycapInset,
    width: size - keycapInset * 2,
    height: size - keycapInset * 2
)
let keycapRadius: CGFloat = 80
let keycapPath = CGPath(
    roundedRect: keycapRect,
    cornerWidth: keycapRadius,
    cornerHeight: keycapRadius,
    transform: nil
)

ctx.saveGState()
ctx.setShadow(
    offset: CGSize(width: 0, height: -18),
    blur: 38,
    color: CGColor(red: 0, green: 0, blue: 0, alpha: 0.22)
)
ctx.setFillColor(CGColor(red: 0.165, green: 0.184, blue: 0.208, alpha: 1.0))
ctx.addPath(keycapPath)
ctx.fillPath()
ctx.restoreGState()

// 3) Subtle keycap top highlight
ctx.saveGState()
ctx.addPath(keycapPath)
ctx.clip()
let highlightColors = [
    CGColor(red: 1, green: 1, blue: 1, alpha: 0.12),
    CGColor(red: 1, green: 1, blue: 1, alpha: 0.0)
] as CFArray
let highlightGradient = CGGradient(
    colorsSpace: colorSpace,
    colors: highlightColors,
    locations: [0.0, 1.0]
)!
ctx.drawLinearGradient(
    highlightGradient,
    start: CGPoint(x: 0, y: keycapRect.maxY),
    end: CGPoint(x: 0, y: keycapRect.maxY - 180),
    options: []
)
ctx.restoreGState()

// 4) Letter "T"
ctx.saveGState()
let nsCtx = NSGraphicsContext(cgContext: ctx, flipped: false)
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = nsCtx

let letterFont = NSFont.systemFont(ofSize: 400, weight: .bold)
let letterColor = NSColor(calibratedRed: 0.945, green: 0.953, blue: 0.965, alpha: 1.0)
let para = NSMutableParagraphStyle()
para.alignment = .center

let letterAttrs: [NSAttributedString.Key: Any] = [
    .font: letterFont,
    .foregroundColor: letterColor,
    .paragraphStyle: para
]
let letter = NSAttributedString(string: "T", attributes: letterAttrs)
let letterSize = letter.size()
let letterRect = CGRect(
    x: (size - letterSize.width) / 2,
    y: (size - letterSize.height) / 2 - 12,
    width: letterSize.width,
    height: letterSize.height
)
letter.draw(in: letterRect)

NSGraphicsContext.restoreGraphicsState()
ctx.restoreGState()

// 5) Sparkle in upper-right of keycap (4-point star)
ctx.saveGState()

let sparkleCenter = CGPoint(x: keycapRect.maxX - 110, y: keycapRect.maxY - 110)
let sparkleOuter: CGFloat = 90
let sparkleInner: CGFloat = 18
let sparklePath = CGMutablePath()

let points = 8
for i in 0..<points {
    let angle = CGFloat(i) * (.pi * 2 / CGFloat(points)) - .pi / 2
    let radius = (i % 2 == 0) ? sparkleOuter : sparkleInner
    let x = sparkleCenter.x + cos(angle) * radius
    let y = sparkleCenter.y + sin(angle) * radius
    if i == 0 {
        sparklePath.move(to: CGPoint(x: x, y: y))
    } else {
        sparklePath.addLine(to: CGPoint(x: x, y: y))
    }
}
sparklePath.closeSubpath()

ctx.setShadow(
    offset: CGSize(width: 0, height: -6),
    blur: 22,
    color: CGColor(red: 1.0, green: 0.541, blue: 0.239, alpha: 0.55)
)
ctx.setFillColor(CGColor(red: 1.0, green: 0.541, blue: 0.239, alpha: 1.0))
ctx.addPath(sparklePath)
ctx.fillPath()

ctx.restoreGState()

// 6) Export PNG
guard let cgImage = ctx.makeImage() else {
    fputs("Failed to make CGImage\n", stderr)
    exit(1)
}

let rep = NSBitmapImageRep(cgImage: cgImage)
rep.size = NSSize(width: size, height: size)
guard let pngData = rep.representation(using: .png, properties: [:]) else {
    fputs("Failed to encode PNG\n", stderr)
    exit(1)
}

let outURL = URL(fileURLWithPath: outputPath)
try pngData.write(to: outURL)
print("Wrote \(outputPath)")
