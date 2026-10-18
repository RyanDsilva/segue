#!/usr/bin/env swift
// Generates the `.cho` document icon, direction B "Taped page" (docs/release/decisions.md
// R52): a paper page with a folded corner, coral gaffer tape over the top edge, an ink title
// bar and grey set lines, and "CHO" below from 128 px up. 16 and 32 px are hand-tuned and
// pixel-snapped so they stay crisp in Finder's list view; 64 px and up draw the large art.
//
// Writes design/icon/document/Segue-Document.icns (Info.plist's CFBundleTypeIconFile and
// UTTypeIconFile) and design/icon/document/previews/*.png for review.
//
// Usage: scripts/gen-doc-icon.swift   (part of `make icon`; needs macOS `iconutil`)

import AppKit
import CoreText
import Foundation

let repo = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
let outDir = repo.appendingPathComponent("design/icon/document")

// MARK: - Palette (brand.md sections 4 and 5)

func color(_ hex: UInt32, _ alpha: CGFloat = 1) -> CGColor {
    CGColor(
        srgbRed: CGFloat((hex >> 16) & 0xFF) / 255,
        green: CGFloat((hex >> 8) & 0xFF) / 255,
        blue: CGFloat(hex & 0xFF) / 255,
        alpha: alpha,
    )
}

let ink = color(0x111113)
let cue = color(0xF2555A)
let grey = color(0x9A9AA2)
let paperEdge = color(0xC9C9CF)
let labelGrey = color(0x8A8A92)
let paperTop = color(0xFFFFFF)
let paperBottom = color(0xF6F6F8)
let foldDark = color(0xDCDCE1)

// MARK: - Geometry (top-left origin, in each art's own pixel grid)

struct Page {
    let x, y, w, h, r, fold: CGFloat
}

struct Art {
    /// The pixel grid the geometry is drawn in.
    let grid: CGFloat
    let page: Page
    let edge: CGFloat
    let title: CGRect
    let titleRadius: CGFloat
    let lines: [CGRect]
    let lineRadius: CGFloat
    /// The tape: centre, size, rotation in degrees, corner radius.
    let tape: (center: CGPoint, size: CGSize, degrees: CGFloat, radius: CGFloat)
    let shadow: Bool
    let label: Bool
}

/// The large art (512 grid), also used for 64, 128 and 256 px.
let big = Art(
    grid: 512,
    page: Page(x: 72, y: 20, w: 368, h: 472, r: 26, fold: 108),
    edge: 2.5,
    title: CGRect(x: 128, y: 128, width: 152, height: 30),
    titleRadius: 11,
    lines: [
        CGRect(x: 128, y: 196, width: 216, height: 18),
        CGRect(x: 128, y: 246, width: 186, height: 18),
        CGRect(x: 128, y: 296, width: 236, height: 18),
    ],
    lineRadius: 9,
    tape: (CGPoint(x: 232, y: 46), CGSize(width: 156, height: 56), -6, 5),
    shadow: true,
    label: true,
)

/// 32 px: whole-pixel shapes, a straight tape, a 1 px edge on the half pixel.
let art32 = Art(
    grid: 32,
    page: Page(x: 5.5, y: 1.5, w: 21, h: 29, r: 2, fold: 7),
    edge: 1,
    title: CGRect(x: 9, y: 9, width: 10, height: 3),
    titleRadius: 1,
    lines: [
        CGRect(x: 9, y: 15, width: 13, height: 2),
        CGRect(x: 9, y: 20, width: 11, height: 2),
        CGRect(x: 9, y: 25, width: 14, height: 2),
    ],
    lineRadius: 1,
    tape: (CGPoint(x: 15, y: 3.5), CGSize(width: 10, height: 5), 0, 0.5),
    shadow: false,
    label: false,
)

/// 16 px: the same page reduced to whole pixels.
let art16 = Art(
    grid: 16,
    page: Page(x: 2.5, y: 0.5, w: 11, h: 15, r: 1, fold: 4),
    edge: 1,
    title: CGRect(x: 5, y: 5, width: 5, height: 2),
    titleRadius: 0.5,
    lines: [
        CGRect(x: 5, y: 8, width: 6, height: 1),
        CGRect(x: 5, y: 10, width: 5, height: 1),
        CGRect(x: 5, y: 12, width: 6, height: 1),
    ],
    lineRadius: 0.5,
    tape: (CGPoint(x: 7.5, y: 1.5), CGSize(width: 5, height: 3), 0, 0.25),
    shadow: false,
    label: false,
)

// MARK: - Drawing

func pagePath(_ p: Page) -> CGPath {
    let path = CGMutablePath()
    path.move(to: CGPoint(x: p.x + p.r, y: p.y))
    path.addLine(to: CGPoint(x: p.x + p.w - p.fold, y: p.y))
    path.addLine(to: CGPoint(x: p.x + p.w, y: p.y + p.fold))
    path.addLine(to: CGPoint(x: p.x + p.w, y: p.y + p.h - p.r))
    path.addQuadCurve(
        to: CGPoint(x: p.x + p.w - p.r, y: p.y + p.h),
        control: CGPoint(x: p.x + p.w, y: p.y + p.h),
    )
    path.addLine(to: CGPoint(x: p.x + p.r, y: p.y + p.h))
    path.addQuadCurve(
        to: CGPoint(x: p.x, y: p.y + p.h - p.r),
        control: CGPoint(x: p.x, y: p.y + p.h),
    )
    path.addLine(to: CGPoint(x: p.x, y: p.y + p.r))
    path.addQuadCurve(to: CGPoint(x: p.x + p.r, y: p.y), control: CGPoint(x: p.x, y: p.y))
    path.closeSubpath()
    return path
}

func foldPath(_ p: Page, radius: CGFloat) -> CGPath {
    let path = CGMutablePath()
    path.move(to: CGPoint(x: p.x + p.w - p.fold, y: p.y))
    path.addLine(to: CGPoint(x: p.x + p.w - p.fold, y: p.y + p.fold - radius))
    path.addQuadCurve(
        to: CGPoint(x: p.x + p.w - p.fold + radius, y: p.y + p.fold),
        control: CGPoint(x: p.x + p.w - p.fold, y: p.y + p.fold),
    )
    path.addLine(to: CGPoint(x: p.x + p.w, y: p.y + p.fold))
    path.closeSubpath()
    return path
}

func fill(_ ctx: CGContext, _ rect: CGRect, radius: CGFloat, _ fill: CGColor) {
    ctx.addPath(CGPath(
        roundedRect: rect,
        cornerWidth: radius,
        cornerHeight: radius,
        transform: nil,
    ))
    ctx.setFillColor(fill)
    ctx.fillPath()
}

func linear(_ ctx: CGContext, _ path: CGPath, _ colors: [CGColor], from: CGPoint, to: CGPoint) {
    ctx.saveGState()
    ctx.addPath(path)
    ctx.clip()
    let gradient = CGGradient(
        colorsSpace: CGColorSpace(name: CGColorSpace.sRGB),
        colors: colors as CFArray,
        locations: nil,
    )
    if let gradient {
        ctx.drawLinearGradient(gradient, start: from, end: to, options: [])
    }
    ctx.restoreGState()
}

func registerFonts() {
    let dir = repo.appendingPathComponent("Packages/SegueUI/Sources/SegueUI/Theme/Fonts")
    let files = (try? FileManager.default.contentsOfDirectory(
        at: dir,
        includingPropertiesForKeys: nil,
    ))
        ?? []
    for url in files where url.pathExtension == "ttf" {
        CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil)
    }
}

/// "CHO", centred at `y` (top-left space), Schibsted Grotesk ExtraBold 54 on the 512 grid.
func drawLabel(_ ctx: CGContext, y: CGFloat) {
    let font = CTFontCreateWithName("SchibstedGrotesk-ExtraBold" as CFString, 54, nil)
    let attributes: [NSAttributedString.Key: Any] = [
        NSAttributedString.Key(kCTFontAttributeName as String): font,
        NSAttributedString.Key(kCTForegroundColorAttributeName as String): labelGrey,
        NSAttributedString.Key(kCTKernAttributeName as String): 1,
    ]
    let line = CTLineCreateWithAttributedString(NSAttributedString(
        string: "CHO",
        attributes: attributes,
    ))
    let bounds = CTLineGetImageBounds(line, ctx)
    ctx.saveGState()
    // Text draws upright in a bottom-left space: undo the flip around the label.
    ctx.translateBy(x: 0, y: y)
    ctx.scaleBy(x: 1, y: -1)
    ctx.textPosition = CGPoint(x: 256 - bounds.width / 2 - bounds.minX, y: -bounds.midY)
    CTLineDraw(line, ctx)
    ctx.restoreGState()
}

func draw(_ art: Art, in ctx: CGContext) {
    let page = pagePath(art.page)
    if art.shadow {
        ctx.saveGState()
        ctx.setShadow(offset: CGSize(width: 0, height: 4), blur: 20, color: color(0x000000, 0.28))
        ctx.addPath(page)
        ctx.setFillColor(paperTop)
        ctx.fillPath()
        ctx.restoreGState()
    }
    let p = art.page
    linear(
        ctx,
        page,
        [paperTop, paperBottom],
        from: CGPoint(x: 0, y: p.y),
        to: CGPoint(x: 0, y: p.y + p.h),
    )
    ctx.addPath(page)
    ctx.setStrokeColor(paperEdge)
    ctx.setLineWidth(art.edge)
    ctx.strokePath()
    let fold = foldPath(p, radius: art.shadow ? 14 : 0)
    linear(
        ctx, fold, [paperTop, foldDark],
        from: CGPoint(x: p.x + p.w - p.fold, y: p.y + p.fold),
        to: CGPoint(x: p.x + p.w - p.fold / 2, y: p.y + p.fold / 2),
    )
    ctx.addPath(fold)
    ctx.setStrokeColor(paperEdge)
    ctx.setLineWidth(art.edge)
    ctx.strokePath()

    fill(ctx, art.title, radius: art.titleRadius, ink)
    for line in art.lines {
        fill(ctx, line, radius: art.lineRadius, grey)
    }
    ctx.saveGState()
    ctx.translateBy(x: art.tape.center.x, y: art.tape.center.y)
    ctx.rotate(by: art.tape.degrees * .pi / 180)
    if art.shadow {
        ctx.setShadow(offset: CGSize(width: 0, height: 2), blur: 8, color: color(0x000000, 0.18))
    }
    let size = art.tape.size
    fill(
        ctx,
        CGRect(x: -size.width / 2, y: -size.height / 2, width: size.width, height: size.height),
        radius: art.tape.radius,
        cue,
    )
    ctx.restoreGState()
    if art.label {
        drawLabel(ctx, y: 418)
    }
}

/// Renders `art` at `pixels` (scaled from its grid) to a PNG.
func render(_ art: Art, pixels: Int, label: Bool, to url: URL) throws {
    guard let ctx = CGContext(
        data: nil, width: pixels, height: pixels, bitsPerComponent: 8, bytesPerRow: 0,
        space: CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB(),
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue,
    ) else { throw NSError(domain: "gen-doc-icon", code: 1) }
    // Top-left origin, the art's own grid.
    ctx.translateBy(x: 0, y: CGFloat(pixels))
    ctx.scaleBy(x: CGFloat(pixels) / art.grid, y: -CGFloat(pixels) / art.grid)
    ctx.interpolationQuality = .high
    var drawn = art
    if !label {
        drawn = Art(
            grid: art.grid, page: art.page, edge: art.edge, title: art.title,
            titleRadius: art.titleRadius, lines: art.lines, lineRadius: art.lineRadius,
            tape: art.tape, shadow: art.shadow, label: false,
        )
    }
    draw(drawn, in: ctx)
    guard let image = ctx.makeImage(),
          let data = NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:])
    else { throw NSError(domain: "gen-doc-icon", code: 2) }
    try data.write(to: url)
}

/// Nearest-neighbour upscale for reviewing small sizes.
func zoom(_ source: URL, by factor: Int, to url: URL) throws {
    guard let image = NSImage(contentsOf: source),
          let cg = image.cgImage(forProposedRect: nil, context: nil, hints: nil),
          let ctx = CGContext(
              data: nil, width: cg.width * factor, height: cg.height * factor,
              bitsPerComponent: 8, bytesPerRow: 0,
              space: CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB(),
              bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue,
          )
    else { throw NSError(domain: "gen-doc-icon", code: 3) }
    ctx.interpolationQuality = .none
    ctx.draw(cg, in: CGRect(x: 0, y: 0, width: cg.width * factor, height: cg.height * factor))
    guard let out = ctx.makeImage(),
          let data = NSBitmapImageRep(cgImage: out).representation(using: .png, properties: [:])
    else { throw NSError(domain: "gen-doc-icon", code: 4) }
    try data.write(to: url)
}

// MARK: - Main

do {
    registerFonts()
    let fileManager = FileManager.default
    let iconset = fileManager.temporaryDirectory
        .appendingPathComponent("Segue-Document-\(UUID().uuidString).iconset")
    try fileManager.createDirectory(at: iconset, withIntermediateDirectories: true)
    defer { try? fileManager.removeItem(at: iconset) }
    // iconutil's slots: name, pixels.
    let slots: [(String, Int)] = [
        ("icon_16x16", 16), ("icon_16x16@2x", 32), ("icon_32x32", 32), ("icon_32x32@2x", 64),
        ("icon_128x128", 128), ("icon_128x128@2x", 256), ("icon_256x256", 256),
        ("icon_256x256@2x", 512), ("icon_512x512", 512), ("icon_512x512@2x", 1024),
    ]
    for (name, pixels) in slots {
        let art = pixels <= 16 ? art16 : pixels <= 32 ? art32 : big
        try render(
            art, pixels: pixels, label: pixels >= 128,
            to: iconset.appendingPathComponent("\(name).png"),
        )
    }
    try fileManager.createDirectory(at: outDir, withIntermediateDirectories: true)
    let icns = outDir.appendingPathComponent("Segue-Document.icns")
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
    process.arguments = ["-c", "icns", iconset.path, "-o", icns.path]
    try process.run()
    process.waitUntilExit()
    guard process.terminationStatus == 0 else {
        throw NSError(domain: "gen-doc-icon", code: Int(process.terminationStatus), userInfo: [
            NSLocalizedDescriptionKey: "iconutil failed",
        ])
    }
    let previews = outDir.appendingPathComponent("previews")
    try fileManager.createDirectory(at: previews, withIntermediateDirectories: true)
    for (source, name) in [("icon_512x512", "document-512"), ("icon_128x128", "document-128")] {
        try fileManager.removeItemIfPresent(at: previews.appendingPathComponent("\(name).png"))
        try fileManager.copyItem(
            at: iconset.appendingPathComponent("\(source).png"),
            to: previews.appendingPathComponent("\(name).png"),
        )
    }
    try zoom(
        iconset.appendingPathComponent("icon_32x32.png"),
        by: 8,
        to: previews.appendingPathComponent("document-32-x8.png"),
    )
    try zoom(
        iconset.appendingPathComponent("icon_16x16.png"),
        by: 8,
        to: previews.appendingPathComponent("document-16-x8.png"),
    )
    print("gen-doc-icon: wrote design/icon/document/Segue-Document.icns and previews")
} catch {
    FileHandle.standardError.write(Data("error: gen-doc-icon: \(error)\n".utf8))
    exit(1)
}

extension FileManager {
    func removeItemIfPresent(at url: URL) throws {
        if fileExists(atPath: url.path) {
            try removeItem(at: url)
        }
    }
}
