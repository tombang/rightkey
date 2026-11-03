#!/usr/bin/env swift
// Render the website's document-and-cursor mark as a native macOS app icon.
// Run from the repository root: swift scripts/generate_app_icon.swift
import Foundation
import CoreGraphics
import ImageIO

let output = URL(fileURLWithPath: CommandLine.arguments.dropFirst().first
    ?? "RightKey/Assets.xcassets/AppIcon.appiconset", isDirectory: true)
let fileManager = FileManager.default
try fileManager.createDirectory(at: output, withIntermediateDirectories: true)
let colorSpace = CGColorSpace(name: CGColorSpace.sRGB)!

func color(_ hex: UInt32, alpha: CGFloat = 1) -> CGColor {
    CGColor(colorSpace: colorSpace, components: [
        CGFloat((hex >> 16) & 255) / 255,
        CGFloat((hex >> 8) & 255) / 255,
        CGFloat(hex & 255) / 255,
        alpha,
    ])!
}

func fillGradient(_ path: CGPath, in context: CGContext, colors: [CGColor],
                  start: CGPoint, end: CGPoint) {
    context.saveGState()
    context.addPath(path)
    context.clip()
    let gradient = CGGradient(colorsSpace: colorSpace, colors: colors as CFArray,
                              locations: [0, 1])!
    context.drawLinearGradient(gradient, start: start, end: end,
        options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])
    context.restoreGState()
}

func render(pixels: Int, to url: URL) throws {
    let context = CGContext(data: nil, width: pixels, height: pixels,
        bitsPerComponent: 8, bytesPerRow: 0, space: colorSpace,
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    context.clear(CGRect(x: 0, y: 0, width: pixels, height: pixels))
    let pixelScale = CGFloat(pixels) / 80
    context.translateBy(x: 0, y: CGFloat(pixels))
    context.scaleBy(x: pixelScale, y: -pixelScale)

    // Transparent margins and a restrained shadow fit macOS icon spacing.
    let tile = CGPath(roundedRect: CGRect(x: 7, y: 6, width: 66, height: 66),
                      cornerWidth: 15.5, cornerHeight: 15.5, transform: nil)
    context.saveGState()
    context.setShadow(offset: CGSize(width: 0, height: -1.2 * pixelScale), blur: 2.1 * pixelScale,
                      color: color(0x071D16, alpha: 0.28))
    context.addPath(tile)
    context.setFillColor(color(0x162E2B))
    context.fillPath()
    context.restoreGState()
    fillGradient(tile, in: context, colors: [color(0x254D42), color(0x122F29)],
                 start: CGPoint(x: 40, y: 6), end: CGPoint(x: 40, y: 72))
    context.addPath(tile)
    context.setStrokeColor(color(0xFFFFFF, alpha: 0.13))
    context.setLineWidth(0.45)
    context.strokePath()

    context.translateBy(x: 7, y: 6)
    context.scaleBy(x: 0.825, y: 0.825)
    let document = CGMutablePath()
    document.move(to: CGPoint(x: 24, y: 18))
    document.addLine(to: CGPoint(x: 47, y: 18))
    document.addLine(to: CGPoint(x: 59, y: 30))
    document.addLine(to: CGPoint(x: 59, y: 59))
    document.addCurve(to: CGPoint(x: 54, y: 64), control1: CGPoint(x: 59, y: 61.76),
                      control2: CGPoint(x: 56.76, y: 64))
    document.addLine(to: CGPoint(x: 24, y: 64))
    document.addCurve(to: CGPoint(x: 19, y: 59), control1: CGPoint(x: 21.24, y: 64),
                      control2: CGPoint(x: 19, y: 61.76))
    document.addLine(to: CGPoint(x: 19, y: 23))
    document.addCurve(to: CGPoint(x: 24, y: 18), control1: CGPoint(x: 19, y: 20.24),
                      control2: CGPoint(x: 21.24, y: 18))
    document.closeSubpath()
    context.saveGState()
    context.setShadow(offset: CGSize(width: 0, height: -0.8 * pixelScale), blur: 1.5 * pixelScale,
                      color: color(0x00180D, alpha: 0.28))
    context.addPath(document)
    context.setFillColor(color(0xC3F3B8))
    context.fillPath()
    context.restoreGState()
    fillGradient(document, in: context, colors: [color(0xDEFFD3), color(0xAFE9AB)],
                 start: CGPoint(x: 25, y: 18), end: CGPoint(x: 52, y: 64))

    let fold = CGMutablePath()
    fold.move(to: CGPoint(x: 46, y: 18))
    fold.addLine(to: CGPoint(x: 46, y: 31))
    fold.addLine(to: CGPoint(x: 59, y: 31))
    fold.closeSubpath()
    context.addPath(fold)
    context.setFillColor(color(0x86C99B))
    context.fillPath()

    let cursor = CGMutablePath()
    cursor.move(to: CGPoint(x: 36, y: 35))
    cursor.addLine(to: CGPoint(x: 60, y: 53))
    cursor.addLine(to: CGPoint(x: 48, y: 55))
    cursor.addLine(to: CGPoint(x: 42, y: 66))
    cursor.closeSubpath()
    context.addPath(cursor)
    context.setFillColor(color(0x162E2B))
    context.setStrokeColor(color(0x162E2B))
    context.setLineWidth(3)
    context.setLineJoin(.round)
    context.drawPath(using: .fillStroke)

    let image = context.makeImage()!
    guard let destination = CGImageDestinationCreateWithURL(url as CFURL,
            "public.png" as CFString, 1, nil) else {
        throw NSError(domain: "RightKeyIcon", code: 1,
                      userInfo: [NSLocalizedDescriptionKey: "Cannot create PNG: \(url.path)"])
    }
    CGImageDestinationAddImage(destination, image, nil)
    guard CGImageDestinationFinalize(destination) else {
        throw NSError(domain: "RightKeyIcon", code: 2,
                      userInfo: [NSLocalizedDescriptionKey: "Cannot write PNG: \(url.path)"])
    }
}

var images: [[String: String]] = []
for size in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let suffix = scale == 1 ? "" : "@2x"
        let name = "icon_\(size)x\(size)\(suffix).png"
        try render(pixels: size * scale, to: output.appendingPathComponent(name))
        images.append(["idiom": "mac", "size": "\(size)x\(size)",
                       "scale": "\(scale)x", "filename": name])
    }
}
let info: [String: Any] = ["author": "xcode", "version": 1]
let manifest: [String: Any] = ["images": images, "info": info]
try JSONSerialization.data(withJSONObject: manifest, options: [.prettyPrinted, .sortedKeys])
    .write(to: output.appendingPathComponent("Contents.json"))
try JSONSerialization.data(withJSONObject: ["info": info], options: [.prettyPrinted, .sortedKeys])
    .write(to: output.deletingLastPathComponent().appendingPathComponent("Contents.json"))
print("Generated 10 macOS app icon variants (16–1024 px) at \(output.path)")
