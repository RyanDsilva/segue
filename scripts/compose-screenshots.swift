#!/usr/bin/env swift
// The App Store screenshot compositor (docs/release/specs/WS5-store-listing.md 8.6 and 9.4).
// Turns the raw window captures `make screenshots` exported from the AppStoreScreenshotTests
// run into captioned 2880x1800 PNGs: sRGB, no alpha, brand background from
// design/tokens.json, Schibsted Grotesk captions from store/screenshots.json, the window
// clipped to its corner radius with a hairline and a shadow.
//
// Usage:
//   scripts/compose-screenshots.swift --raw <dir> [--raw <dir>...] --captions
//   store/screenshots.json
//       --tokens design/tokens.json --fonts <dir> --out <dir> [--direction A|B|C]
//       [--contact-sheet <file>] [--directions <dir>]
//   scripts/compose-screenshots.swift --verify <out dir>
//   scripts/compose-screenshots.swift --video-captions <dir> --captions store/screenshots.json
//       --tokens design/tokens.json --fonts <dir>
//
// --directions renders shots 1 and 3 in each of A, B and C for Ryan's pick (WS5 step 6);
// the direction in screenshots.json is the one --out uses unless --direction overrides it.
// --video-captions writes one 1920x1080 transparent PNG per preview caption (section 9.4).
// AppKit, CoreGraphics, CoreText and ImageIO only.

import AppKit
import CoreText
import Foundation
import ImageIO
import UniformTypeIdentifiers

struct Failure: Error, CustomStringConvertible {
    let description: String
}

func fail(_ message: String) -> Never {
    FileHandle.standardError.write(Data("compose-screenshots: \(message)\n".utf8))
    exit(1)
}

let arguments = Array(CommandLine.arguments.dropFirst())
func value(_ flag: String) -> String? {
    arguments.firstIndex(of: flag)
        .flatMap { arguments.indices.contains($0 + 1) ? arguments[$0 + 1] : nil }
}

func values(_ flag: String) -> [String] {
    arguments.enumerated().compactMap { index, argument in
        argument == flag && arguments.indices.contains(index + 1) ? arguments[index + 1] : nil
    }
}

let canvasWidth = 2880
let canvasHeight = 1800

// MARK: - Images

func loadImage(_ url: URL) throws -> CGImage {
    guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
          let image = CGImageSourceCreateImageAtIndex(source, 0, nil)
    else { throw Failure(description: "cannot read \(url.path)") }
    return image
}

/// Writes an opaque image as a 24-bit RGB PNG tagged sRGB: no alpha channel at all (ImageIO
/// keeps a padding alpha for CGContext's RGBX images, which App Store Connect rejects).
func writeOpaquePNG(_ image: CGImage, to url: URL) throws {
    let width = image.width
    let height = image.height
    // RGBX bytes in sRGB, then copied into a 3-sample bitmap (NSGraphicsContext cannot draw
    // into a bitmap without alpha).
    let source = try context(width: width, height: height, alpha: false)
    source.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
    guard let pixels = source.data?.assumingMemoryBound(to: UInt8.self),
          let rep = NSBitmapImageRep(
              bitmapDataPlanes: nil, pixelsWide: width, pixelsHigh: height,
              bitsPerSample: 8, samplesPerPixel: 3, hasAlpha: false, isPlanar: false,
              colorSpaceName: .calibratedRGB, bytesPerRow: width * 3, bitsPerPixel: 24,
          ),
          let target = rep.bitmapData
    else { throw Failure(description: "cannot make an RGB bitmap for \(url.lastPathComponent)") }
    let stride = source.bytesPerRow
    for row in 0 ..< height {
        for column in 0 ..< width {
            let from = row * stride + column * 4
            let to = row * width * 3 + column * 3
            target[to] = pixels[from]
            target[to + 1] = pixels[from + 1]
            target[to + 2] = pixels[from + 2]
        }
    }
    guard let tagged = rep.retagging(with: .sRGB),
          let data = tagged.representation(using: .png, properties: [:])
    else { throw Failure(description: "PNG encoding failed for \(url.path)") }
    try data.write(to: url, options: .atomic)
}

func writePNG(_ image: CGImage, to url: URL) throws {
    guard let destination = CGImageDestinationCreateWithURL(
        url as CFURL, UTType.png.identifier as CFString, 1, nil,
    ) else { throw Failure(description: "cannot write \(url.path)") }
    CGImageDestinationAddImage(destination, image, nil)
    guard CGImageDestinationFinalize(destination) else {
        throw Failure(description: "PNG encoding failed for \(url.path)")
    }
}

func context(width: Int, height: Int, alpha: Bool) throws -> CGContext {
    guard let space = CGColorSpace(name: CGColorSpace.sRGB),
          let context = CGContext(
              data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
              space: space,
              bitmapInfo: alpha
                  ? CGImageAlphaInfo.premultipliedLast.rawValue
                  : CGImageAlphaInfo.noneSkipLast.rawValue,
          )
    else { throw Failure(description: "cannot make a \(width)x\(height) bitmap context") }
    context.interpolationQuality = .high
    return context
}

// MARK: - Tokens and fonts

struct Palette {
    let ground: CGColor
    let ink: CGColor
    let muted: CGColor
    let hairline: CGColor
    let cue: CGColor
    let background: CGColor
}

func color(_ hex: String) throws -> CGColor {
    var text = hex.trimmingCharacters(in: .whitespaces)
    if text.hasPrefix("#") {
        text.removeFirst()
    }
    guard text.count == 6 || text.count == 8, let value = UInt64(text, radix: 16) else {
        throw Failure(description: "bad colour \(hex)")
    }
    let hasAlpha = text.count == 8
    let red = Double((value >> (hasAlpha ? 24 : 16)) & 0xFF) / 255
    let green = Double((value >> (hasAlpha ? 16 : 8)) & 0xFF) / 255
    let blue = Double((value >> (hasAlpha ? 8 : 0)) & 0xFF) / 255
    let alpha = hasAlpha ? Double(value & 0xFF) / 255 : 1
    guard let space = CGColorSpace(name: CGColorSpace.sRGB),
          let color = CGColor(colorSpace: space, components: [red, green, blue, alpha])
    else { throw Failure(description: "cannot make colour \(hex)") }
    return color
}

func palette(tokens url: URL, dark: Bool) throws -> Palette {
    let data = try Data(contentsOf: url)
    guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
          let list = json["color"] as? [[String: Any]]
    else { throw Failure(description: "\(url.path): no color list") }
    func token(_ name: String, _ mode: String) throws -> CGColor {
        guard let entry = list.first(where: { $0["name"] as? String == name }),
              let hex = entry[mode] as? String
        else { throw Failure(description: "tokens: no \(name).\(mode)") }
        return try color(hex)
    }
    let mode = dark ? "dark" : "light"
    // brand.md section 7 (controlBorder logic): `line` on light, `muted` at 40% on dark.
    let hairline = dark
        ? try token("muted", "dark").copy(alpha: 0.4) ?? token("muted", "dark")
        : try token("line", "light")
    return try Palette(
        ground: token("ground", mode),
        ink: token("ink", mode),
        muted: token("muted", mode),
        hairline: hairline,
        cue: token("cue", mode),
        // The dark ground; on light the alternate surface, so the white window separates.
        background: dark ? token("ground", "dark") : token("surfaceAlt", "light"),
    )
}

func registerFonts(in folder: URL) throws {
    let files = try FileManager.default.contentsOfDirectory(
        at: folder,
        includingPropertiesForKeys: nil,
    ).filter { $0.pathExtension.lowercased() == "ttf" }
    guard !files.isEmpty else { throw Failure(description: "no .ttf fonts in \(folder.path)") }
    for file in files {
        var error: Unmanaged<CFError>?
        if !CTFontManagerRegisterFontsForURL(file as CFURL, .process, &error) {
            // Already registered in this process is fine; anything else is not.
            let code = error.map { CFErrorGetCode($0.takeRetainedValue()) } ?? 0
            if code != CTFontManagerError.alreadyRegistered.rawValue {
                throw Failure(description: "cannot register \(file.lastPathComponent)")
            }
        }
    }
}

func font(_ name: String, size: Double) throws -> CTFont {
    let font = CTFontCreateWithName(name as CFString, size, nil)
    guard CTFontCopyPostScriptName(font) as String == name else {
        throw Failure(description: "font \(name) is not available (--fonts)")
    }
    return font
}

// MARK: - Text

/// The headline: ExtraBold, tracking -0.035em, the closing full stop in the cue colour (the
/// wordmark's dot).
func headline(_ text: String, size: Double, palette: Palette) throws -> NSAttributedString {
    let face = try font("SchibstedGrotesk-ExtraBold", size: size)
    let string = NSMutableAttributedString(string: text, attributes: [
        NSAttributedString.Key(kCTFontAttributeName as String): face,
        NSAttributedString.Key(kCTForegroundColorAttributeName as String): palette.ink,
        NSAttributedString.Key(kCTKernAttributeName as String): -0.035 * size,
    ])
    if text.hasSuffix(".") {
        string.addAttribute(
            NSAttributedString.Key(kCTForegroundColorAttributeName as String),
            value: palette.cue,
            range: NSRange(location: (text as NSString).length - 1, length: 1),
        )
    }
    return string
}

func subline(_ text: String, size: Double, palette: Palette) throws -> NSAttributedString {
    let face = try font("SchibstedGrotesk-Medium", size: size)
    return NSAttributedString(string: text, attributes: [
        NSAttributedString.Key(kCTFontAttributeName as String): face,
        NSAttributedString.Key(kCTForegroundColorAttributeName as String): palette.muted,
        NSAttributedString.Key(kCTKernAttributeName as String): -0.01 * size,
    ])
}

/// The typographic width of one line.
func width(_ text: NSAttributedString) -> Double {
    let line = CTLineCreateWithAttributedString(text)
    return CTLineGetTypographicBounds(line, nil, nil, nil) - CTLineGetTrailingWhitespaceWidth(line)
}

/// Draws one line with its baseline at `y` (top-left canvas coordinates), starting at `x`.
func draw(_ text: NSAttributedString, x: Double, baseline y: Double, in context: CGContext) {
    let line = CTLineCreateWithAttributedString(text)
    context.saveGState()
    context.textMatrix = .identity
    context.textPosition = CGPoint(x: x, y: Double(context.height) - y)
    CTLineDraw(line, context)
    context.restoreGState()
}

/// Lines of `text` wrapped to `maxWidth` (word breaks only).
func wrapped(_ text: NSAttributedString, maxWidth: Double) -> [NSAttributedString] {
    let framesetter = CTFramesetterCreateWithAttributedString(text)
    let path = CGPath(rect: CGRect(x: 0, y: 0, width: maxWidth, height: 100_000), transform: nil)
    let frame = CTFramesetterCreateFrame(framesetter, CFRange(location: 0, length: 0), path, nil)
    let lines = CTFrameGetLines(frame) as? [CTLine] ?? []
    return lines.map { line in
        let range = CTLineGetStringRange(line)
        return text.attributedSubstring(from: NSRange(
            location: range.location,
            length: range.length,
        ))
    }
}

// MARK: - Captions file

struct Shot {
    let id: String
    let raw: String
    let appearance: String
    let background: String
    let headline: String
    let subline: String
    let crop: CGRect?
}

struct Captions {
    let direction: String
    let cornerRadius: Double
    let shots: [Shot]
    let video: [(id: String, text: String)]
}

func loadCaptions(_ url: URL) throws -> Captions {
    let data = try Data(contentsOf: url)
    guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
          let canvas = json["canvas"] as? [String: Any],
          canvas["width"] as? Int == canvasWidth, canvas["height"] as? Int == canvasHeight,
          let locales = json["locales"] as? [String: Any],
          let list = locales["en-US"] as? [[String: Any]]
    else { throw Failure(description: "\(url.path): needs canvas 2880x1800 and locales.en-US") }
    let shots = try list.map { item -> Shot in
        guard let id = item["id"] as? String, let raw = item["raw"] as? String,
              let appearance = item["appearance"] as? String,
              let background = item["background"] as? String,
              let headline = item["headline"] as? String, let subline = item["subline"] as? String
        else { throw Failure(description: "\(url.path): a shot is missing a field") }
        var crop: CGRect?
        if let box = item["crop"] as? [String: Double], let x = box["x"], let y = box["y"],
           let w = box["w"], let h = box["h"]
        {
            crop = CGRect(x: x, y: y, width: w, height: h)
        }
        return Shot(
            id: id, raw: raw, appearance: appearance, background: background,
            headline: headline, subline: subline, crop: crop,
        )
    }
    let video = (json["previewCaptions"] as? [[String: Any]] ?? []).compactMap { item in
        (item["id"] as? String).flatMap { id in (item["text"] as? String).map { (id, $0) } }
    }
    return Captions(
        direction: json["direction"] as? String ?? "A",
        cornerRadius: json["windowCornerRadius"] as? Double ?? 0,
        shots: shots,
        video: video,
    )
}

// MARK: - Raw captures

/// Raw captures by attachment name prefix (`appstore-01-stage-dark`). XCTest appends
/// `_<n>_<uuid>` to the name, so only the prefix is trusted (8.5).
func rawCaptures(in folders: [URL]) throws -> [String: URL] {
    var found: [String: URL] = [:]
    let pattern =
        try NSRegularExpression(pattern: #"^(appstore-\d\d-[a-z]+-(?:dark|light))(?:_|\.|$)"#)
    for folder in folders {
        let data = try Data(contentsOf: folder.appending(path: "manifest.json"))
        guard let tests = try JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
            throw Failure(description: "\(folder.path)/manifest.json: unexpected shape")
        }
        for test in tests {
            for attachment in test["attachments"] as? [[String: Any]] ?? [] {
                guard let file = attachment["exportedFileName"] as? String,
                      let name = attachment["suggestedHumanReadableName"] as? String,
                      let match = pattern.firstMatch(
                          in: name,
                          range: NSRange(name.startIndex..., in: name),
                      ),
                      let key = Range(match.range(at: 1), in: name).map({ String(name[$0]) })
                else { continue }
                found[key] = folder.appending(path: file)
            }
        }
    }
    return found
}

// MARK: - Composition

/// Where the window and the captions go for one direction.
struct Layout {
    let window: CGRect
    /// Caption block: left edge, first baseline, column width, centred or left-aligned.
    let textX: Double
    let headlineBaseline: Double
    let columnWidth: Double
    let centred: Bool
    let wraps: Bool
}

func layout(_ direction: String, aspect: Double) -> Layout {
    let canvasW = Double(canvasWidth)
    let canvasH = Double(canvasHeight)
    switch direction {
    case "B":
        // Floating window: fully inside, even margins; headline top-left on the window edge.
        let width = canvasW * 0.74
        let height = width / aspect
        let x = (canvasW - width) / 2
        let y = canvasH - height - 110
        return Layout(
            window: CGRect(x: x, y: y, width: width, height: height),
            textX: x, headlineBaseline: 205, columnWidth: width, centred: false, wraps: false,
        )
    case "C":
        // Split: captions in a left column, the window on the right, vertically centred.
        let width = canvasW * 0.66
        let height = width / aspect
        let x = canvasW - width - 120
        let y = (canvasH - height) / 2
        return Layout(
            window: CGRect(x: x, y: y, width: width, height: height),
            textX: 150, headlineBaseline: 0, columnWidth: x - 150 - 110,
            centred: false, wraps: true,
        )
    default:
        // A: caption over, window below, centred and bottom-anchored. WS5 suggested a ~6%
        // bleed off the bottom, but any bleed hides the stage's Up next footer, so the whole
        // window stays on the canvas with a small bottom margin.
        let width = canvasW * 0.76
        let height = width / aspect
        let x = (canvasW - width) / 2
        let y = canvasH - height - 70
        return Layout(
            window: CGRect(x: x, y: y, width: width, height: height),
            textX: canvasW / 2, headlineBaseline: 178, columnWidth: canvasW - 240,
            centred: true, wraps: false,
        )
    }
}

/// One composed screenshot (no alpha).
func compose(
    _ shot: Shot,
    raw: CGImage,
    direction: String,
    cornerRadius: Double,
    palette: Palette,
) throws -> CGImage {
    let context = try context(width: canvasWidth, height: canvasHeight, alpha: false)
    let canvasH = Double(canvasHeight)
    context.setFillColor(palette.background)
    context.fill(CGRect(x: 0, y: 0, width: canvasWidth, height: canvasHeight))

    var image = raw
    if let crop = shot.crop {
        guard let cropped = raw.cropping(to: crop) else {
            throw Failure(description: "\(shot.id): crop outside the raw capture")
        }
        image = cropped
    }
    let aspect = Double(image.width) / Double(image.height)
    let box = layout(direction, aspect: aspect)
    let scale = box.window.width / Double(image.width)
    if scale > 1.001 {
        throw Failure(description: "\(shot.id): the raw capture would be upscaled (\(scale)x)")
    }

    // Captions.
    let dark = shot.background == "dark"
    let headlineSize = 104.0
    let sublineSize = 46.0
    let title = try headline(shot.headline, size: headlineSize, palette: palette)
    let sub = try subline(shot.subline, size: sublineSize, palette: palette)
    if box.wraps {
        let titleLines = wrapped(title, maxWidth: box.columnWidth)
        let subLines = wrapped(sub, maxWidth: box.columnWidth)
        let titleLead = headlineSize * 1.08
        let subLead = sublineSize * 1.35
        let blockHeight = Double(titleLines.count) * titleLead + 40
            + Double(subLines.count) * subLead
        var baseline = (canvasH - blockHeight) / 2 + headlineSize * 0.86
        for line in titleLines {
            draw(line, x: box.textX, baseline: baseline, in: context)
            baseline += titleLead
        }
        baseline += 40 - titleLead + sublineSize * 1.0 + (titleLead - headlineSize * 0.86)
        for line in subLines {
            draw(line, x: box.textX, baseline: baseline, in: context)
            baseline += subLead
        }
    } else {
        for (text, label) in [(title, "headline"), (sub, "subline")]
            where width(text) > box.columnWidth
        {
            throw Failure(description: "\(shot.id): the \(label) overflows one line")
        }
        let titleX = box.centred ? box.textX - width(title) / 2 : box.textX
        let subX = box.centred ? box.textX - width(sub) / 2 : box.textX
        draw(title, x: titleX, baseline: box.headlineBaseline, in: context)
        draw(sub, x: subX, baseline: box.headlineBaseline + 84, in: context)
    }

    // The window: shadow, clipped image, hairline. CG's origin is bottom-left.
    let rect = CGRect(
        x: box.window.minX,
        y: canvasH - box.window.maxY,
        width: box.window.width,
        height: box.window.height,
    )
    let radius = max(0, cornerRadius * scale)
    let clip = CGPath(
        roundedRect: rect.insetBy(dx: 1, dy: 1),
        cornerWidth: radius, cornerHeight: radius, transform: nil,
    )
    context.saveGState()
    context.setShadow(
        offset: CGSize(width: 0, height: -24),
        blur: dark ? 110 : 80,
        color: CGColor(gray: 0, alpha: dark ? 0.5 : 0.35),
    )
    context.addPath(clip)
    context.setFillColor(palette.ground)
    context.fillPath()
    context.restoreGState()

    context.saveGState()
    context.addPath(clip)
    context.clip()
    context.draw(image, in: rect)
    context.restoreGState()

    context.saveGState()
    context.addPath(clip)
    context.setStrokeColor(palette.hairline)
    context.setLineWidth(2)
    context.strokePath()
    context.restoreGState()

    guard let result = context.makeImage() else { throw Failure(description: "render failed") }
    return result
}

func contactSheet(_ images: [CGImage], to url: URL) throws {
    let columns = 3
    let cellW = canvasWidth / 4
    let cellH = canvasHeight / 4
    let gap = 24
    let rows = (images.count + columns - 1) / columns
    let width = columns * cellW + (columns + 1) * gap
    let height = rows * cellH + (rows + 1) * gap
    let sheet = try context(width: width, height: height, alpha: false)
    sheet.setFillColor(CGColor(gray: 0.5, alpha: 1))
    sheet.fill(CGRect(x: 0, y: 0, width: width, height: height))
    for (index, image) in images.enumerated() {
        let column = index % columns
        let row = index / columns
        let x = gap + column * (cellW + gap)
        let y = height - (gap + row * (cellH + gap)) - cellH
        sheet.draw(image, in: CGRect(x: x, y: y, width: cellW, height: cellH))
    }
    guard let image = sheet.makeImage() else { throw Failure(description: "contact sheet failed") }
    try writePNG(image, to: url)
}

// MARK: - Verify

func verify(_ folder: URL) throws {
    let manager = FileManager.default
    let locales = try manager.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)
        .filter(\.hasDirectoryPath)
    guard !locales.isEmpty
    else { throw Failure(description: "no locale folders in \(folder.path)") }
    for locale in locales {
        let files = try manager.contentsOfDirectory(at: locale, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension == "png" }.sorted { $0.path < $1.path }
        guard (1 ... 10).contains(files.count) else {
            throw Failure(description: "\(locale.lastPathComponent): \(files.count) PNGs (1-10)")
        }
        for file in files {
            guard let source = CGImageSourceCreateWithURL(file as CFURL, nil),
                  let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil)
                  as? [CFString: Any]
            else { throw Failure(description: "cannot read \(file.path)") }
            let width = properties[kCGImagePropertyPixelWidth] as? Int ?? 0
            let height = properties[kCGImagePropertyPixelHeight] as? Int ?? 0
            // The decoded image's alpha info (the HasAlpha property is not always set).
            let decoded = CGImageSourceCreateImageAtIndex(source, 0, nil)
            let alpha = decoded.map { image in
                ![.none, .noneSkipLast, .noneSkipFirst].contains(image.alphaInfo)
            } ?? true
            let profile = properties[kCGImagePropertyProfileName] as? String ?? ""
            guard width == canvasWidth, height == canvasHeight, !alpha,
                  profile.lowercased().contains("srgb")
            else {
                throw Failure(description: """
                \(file.lastPathComponent): \(width)x\(height), alpha \(alpha), profile \
                "\(profile)" (want 2880x1800, no alpha, sRGB)
                """)
            }
        }
        print("compose-screenshots: \(locale.lastPathComponent): \(files.count) PNGs ok")
    }
}

// MARK: - Video captions (WS5 9.4)

/// A 1920x1080 transparent PNG: the caption centred in the top band that make-preview.sh
/// leaves above the (scaled) app footage, so it never covers the stage header.
func videoCaption(_ text: String, palette: Palette) throws -> CGImage {
    let canvasW = 1920
    let height = 1080
    let context = try context(width: canvasW, height: height, alpha: true)
    context.clear(CGRect(x: 0, y: 0, width: canvasW, height: height))
    let title = try headline(text, size: 54, palette: palette)
    guard width(title) < Double(canvasW) - 160 else {
        throw Failure(description: "video caption \"\(text)\" overflows one line")
    }
    draw(title, x: (Double(canvasW) - width(title)) / 2, baseline: 76, in: context)
    guard let image = context.makeImage() else { throw Failure(description: "render failed") }
    return image
}

// MARK: - Main

do {
    if let folder = value("--verify") {
        try verify(URL(fileURLWithPath: folder, isDirectory: true))
        exit(0)
    }
    guard let captionsPath = value("--captions"), let tokensPath = value("--tokens"),
          let fontsPath = value("--fonts")
    else { fail("needs --captions, --tokens and --fonts (see the header)") }
    try registerFonts(in: URL(fileURLWithPath: fontsPath, isDirectory: true))
    let captions = try loadCaptions(URL(fileURLWithPath: captionsPath))
    let tokens = URL(fileURLWithPath: tokensPath)
    let palettes = try [
        "dark": palette(tokens: tokens, dark: true),
        "light": palette(tokens: tokens, dark: false),
    ]

    if let folder = value("--video-captions") {
        let out = URL(fileURLWithPath: folder, isDirectory: true)
        try FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)
        guard let dark = palettes["dark"] else { fail("no dark palette") }
        for caption in captions.video {
            try writePNG(
                videoCaption(caption.text, palette: dark),
                to: out.appending(path: "\(caption.id).png"),
            )
        }
        print("compose-screenshots: \(captions.video.count) video captions in \(folder)")
        exit(0)
    }

    let raws = try rawCaptures(in: values("--raw")
        .map { URL(fileURLWithPath: $0, isDirectory: true) })
    guard !raws.isEmpty else { fail("no appstore-* captures under --raw") }
    func render(_ shot: Shot, direction: String) throws -> CGImage {
        let key = "\(shot.raw)-\(shot.appearance)"
        guard let url = raws[key] else { throw Failure(description: "no raw capture \(key)") }
        let raw = try loadImage(url)
        guard raw.width == canvasWidth, raw.height == canvasHeight else {
            throw Failure(description: "\(key) is \(raw.width)x\(raw.height), not 2880x1800")
        }
        guard let palette = palettes[shot.background] else {
            throw Failure(description: "\(shot.id): background must be dark or light")
        }
        return try compose(
            shot, raw: raw, direction: direction,
            cornerRadius: captions.cornerRadius, palette: palette,
        )
    }

    if let folder = value("--directions") {
        let out = URL(fileURLWithPath: folder, isDirectory: true)
        try FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)
        var samples: [CGImage] = []
        for direction in ["A", "B", "C"] {
            for shot in captions.shots.prefix(3) {
                let image = try render(shot, direction: direction)
                try writePNG(image, to: out.appending(path: "\(direction)-\(shot.id).png"))
                samples.append(image)
            }
        }
        try contactSheet(samples, to: out.appending(path: "directions-sheet.png"))
        print("compose-screenshots: directions A, B and C in \(folder)")
    }

    if let folder = value("--out") {
        let direction = value("--direction") ?? captions.direction
        let out = URL(fileURLWithPath: folder, isDirectory: true).appending(path: "en-US")
        try FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)
        var composed: [CGImage] = []
        for shot in captions.shots {
            let image = try render(shot, direction: direction)
            try writeOpaquePNG(image, to: out.appending(path: "\(shot.id).png"))
            composed.append(image)
        }
        if let sheet = value("--contact-sheet") {
            try contactSheet(composed, to: URL(fileURLWithPath: sheet))
        }
        print(
            "compose-screenshots: \(composed.count) shots in \(out.path) (direction \(direction))",
        )
    }
} catch {
    fail("\(error)")
}
