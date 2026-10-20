#!/usr/bin/env swift
// The user guide's screenshot and clip-poster processor (docs/release/specs/WS6-user-guide.md
// sections 5.6 and 6). Reads the attachments `make docs-shots` exported from the capture
// runs and writes:
//   guide/public/shots/<id>-<appearance>.avif   (stage shots: <id>.avif)
//   guide/src/data/shots.json                   (the manifest Shot.astro and guide-check read)
//
// Usage: scripts/docs-shots.swift --raw <dir> [--raw <dir>...] [--only id,id]
//        scripts/docs-shots.swift --poster <frame.png> --clip <id> --width <px> --height <px>
//            --seconds <s>
//
// AVIF from ImageIO (no third-party encoder). A shot is rewritten only when it really
// changed: when fewer than 0.5% of its pixels differ by more than 8/255 from the committed
// file, the committed file is kept, so re-running on an unchanged app leaves git clean.
// Budgets (also checked by guide-check): 150 KB per shot.

import AppKit
import Foundation
import ImageIO

let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
let shotsDir = root.appending(path: "guide/public/shots", directoryHint: .isDirectory)
let clipsDir = root.appending(path: "guide/public/clips", directoryHint: .isDirectory)
let manifestURL = root.appending(path: "guide/src/data/shots.json")
/// Widest image the guide needs: an 860 px column at 2x.
let maxWidth = 1760
let shotBudget = 150 * 1024

struct Failure: Error, CustomStringConvertible {
    let description: String
}

func fail(_ message: String) -> Never {
    FileHandle.standardError.write(Data("docs-shots: \(message)\n".utf8))
    exit(1)
}

// MARK: - Images

func loadImage(_ url: URL) throws -> CGImage {
    guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
          let image = CGImageSourceCreateImageAtIndex(source, 0, nil)
    else { throw Failure(description: "cannot read \(url.path)") }
    return image
}

/// `image` scaled down to at most `maxWidth` wide (never up), sRGB, no alpha.
func normalized(_ image: CGImage) throws -> CGImage {
    let scale = min(1, Double(maxWidth) / Double(image.width))
    let width = Int((Double(image.width) * scale).rounded())
    let height = Int((Double(image.height) * scale).rounded())
    guard let space = CGColorSpace(name: CGColorSpace.sRGB),
          let context = CGContext(
              data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
              space: space, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue,
          )
    else { throw Failure(description: "cannot make a bitmap context") }
    context.interpolationQuality = .high
    context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
    guard let result = context.makeImage() else { throw Failure(description: "cannot scale") }
    return result
}

func avifData(_ image: CGImage, quality: Double = 0.8) throws -> Data {
    let data = NSMutableData()
    guard let destination = CGImageDestinationCreateWithData(
        data, "public.avif" as CFString, 1, nil,
    ) else { throw Failure(description: "ImageIO cannot write AVIF here") }
    let options = [kCGImageDestinationLossyCompressionQuality: quality] as CFDictionary
    CGImageDestinationAddImage(destination, image, options)
    guard CGImageDestinationFinalize(destination) else {
        throw Failure(description: "AVIF encoding failed")
    }
    return data as Data
}

/// RGBA bytes of `image` at `width` x `height`.
func pixels(_ image: CGImage, width: Int, height: Int) -> [UInt8]? {
    var bytes = [UInt8](repeating: 0, count: width * height * 4)
    guard let space = CGColorSpace(name: CGColorSpace.sRGB),
          let context = CGContext(
              data: &bytes, width: width, height: height, bitsPerComponent: 8,
              bytesPerRow: width * 4, space: space,
              bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue,
          )
    else { return nil }
    context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
    return bytes
}

/// Whether `new` (encoded) differs visibly from the file at `url`.
func changed(_ new: Data, from url: URL) -> Bool {
    guard let oldImage = try? loadImage(url),
          let source = CGImageSourceCreateWithData(new as CFData, nil),
          let newImage = CGImageSourceCreateImageAtIndex(source, 0, nil),
          oldImage.width == newImage.width, oldImage.height == newImage.height,
          let a = pixels(oldImage, width: newImage.width, height: newImage.height),
          let b = pixels(newImage, width: newImage.width, height: newImage.height)
    else { return true }
    var differing = 0
    for pixel in stride(from: 0, to: a.count, by: 4) {
        for channel in 0 ..< 3 where abs(Int(a[pixel + channel]) - Int(b[pixel + channel])) > 8 {
            differing += 1
            break
        }
    }
    return Double(differing) / Double(newImage.width * newImage.height) >= 0.005
}

/// Writes `image` as AVIF to `url` unless the committed file is visibly the same.
/// Returns the written (or kept) pixel size.
func writeShot(_ image: CGImage, to url: URL) throws -> (Int, Int, Bool) {
    let scaled = try normalized(image)
    let data = try avifData(scaled)
    if data.count > shotBudget {
        throw Failure(
            description: "\(url.lastPathComponent) is \(data.count / 1024) KB (budget 150 KB)",
        )
    }
    let fresh = !FileManager.default.fileExists(atPath: url.path) || changed(data, from: url)
    if fresh {
        try data.write(to: url, options: .atomic)
    }
    return (scaled.width, scaled.height, fresh)
}

// MARK: - Manifest

func loadManifest() -> [String: Any] {
    guard let data = try? Data(contentsOf: manifestURL),
          let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
    else { return ["schema": 1, "shots": [String: Any](), "clips": [String: Any]()] }
    return json
}

func saveManifest(_ manifest: [String: Any]) throws {
    let data = try JSONSerialization.data(
        withJSONObject: manifest,
        options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes],
    )
    try (String(decoding: data, as: UTF8.self) + "\n").write(
        to: manifestURL,
        atomically: true,
        encoding: .utf8,
    )
}

// MARK: - xcresult attachments

struct Attachment {
    let id: String
    /// "dark", "light" or "stage".
    let appearance: String
    let isFrames: Bool
    let file: URL
}

/// Attachments named `guide-<id>-<appearance>` (and `.frames`) in an exported folder. The
/// export's manifest maps exported file names to the names the tests gave them; XCTest
/// appends `_<n>_<uuid>` (before any extension), so only the prefix is trusted.
func attachments(in folder: URL) throws -> [Attachment] {
    let data = try Data(contentsOf: folder.appending(path: "manifest.json"))
    guard let tests = try JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
        throw Failure(description: "\(folder.path)/manifest.json: unexpected shape")
    }
    let pattern = try NSRegularExpression(pattern: #"^guide-(.+)-(dark|light|stage)(?:_|\.|$)"#)
    var found: [Attachment] = []
    for test in tests {
        for attachment in test["attachments"] as? [[String: Any]] ?? [] {
            guard let file = attachment["exportedFileName"] as? String,
                  let name = attachment["suggestedHumanReadableName"] as? String,
                  let match = pattern.firstMatch(
                      in: name,
                      range: NSRange(name.startIndex..., in: name),
                  ),
                  let id = Range(match.range(at: 1), in: name).map({ String(name[$0]) }),
                  let appearance = Range(match.range(at: 2), in: name).map({ String(name[$0]) })
            else { continue }
            found.append(Attachment(
                id: id,
                appearance: appearance,
                // XCTest moves the ".frames" suffix after its own "_<n>_<uuid>".
                isFrames: name.hasSuffix(".frames") || file.hasSuffix(".json"),
                file: folder.appending(path: file),
            ))
        }
    }
    return found
}

// MARK: - Main

let arguments = Array(CommandLine.arguments.dropFirst())
func value(_ flag: String) -> String? {
    arguments.firstIndex(of: flag)
        .flatMap { arguments.indices.contains($0 + 1) ? arguments[$0 + 1] : nil }
}

do {
    try FileManager.default.createDirectory(at: shotsDir, withIntermediateDirectories: true)
    var manifest = loadManifest()

    if let poster = value("--poster") {
        guard let id = value("--clip"), let width = value("--width").flatMap(Int.init),
              let height = value("--height").flatMap(Int.init),
              let seconds = value("--seconds").flatMap(Double.init)
        else { fail("--poster needs --clip, --width, --height and --seconds") }
        try FileManager.default.createDirectory(at: clipsDir, withIntermediateDirectories: true)
        let image = try normalized(loadImage(URL(fileURLWithPath: poster)))
        try avifData(image).write(to: clipsDir.appending(path: "\(id).avif"), options: .atomic)
        var clips = manifest["clips"] as? [String: Any] ?? [:]
        clips[id] = ["width": width, "height": height, "seconds": (seconds * 10).rounded() / 10]
        manifest["clips"] = clips
        try saveManifest(manifest)
        print("docs-shots: clip \(id) poster and manifest written")
        exit(0)
    }

    var raws: [URL] = []
    for (index, argument) in arguments.enumerated() where argument == "--raw" {
        guard arguments.indices.contains(index + 1) else { fail("--raw needs a folder") }
        raws.append(URL(fileURLWithPath: arguments[index + 1], isDirectory: true))
    }
    guard !raws.isEmpty else { fail("usage: --raw <exported attachments folder> [--raw ...]") }
    let only = value("--only").map { Set($0.split(separator: ",").map(String.init)) }

    let found = try raws.flatMap(attachments(in:))
    var shots = manifest["shots"] as? [String: Any] ?? [:]
    var written = 0
    var kept = 0
    for id in Set(found.map(\.id)).sorted() where only?.contains(id) ?? true {
        let images = found.filter { $0.id == id && !$0.isFrames }
        guard !images.isEmpty else { continue }
        let isStage = images.contains { $0.appearance == "stage" }
        var size = (0, 0)
        for image in images {
            let name = isStage ? "\(id).avif" : "\(id)-\(image.appearance).avif"
            let result = try writeShot(loadImage(image.file), to: shotsDir.appending(path: name))
            size = (result.0, result.1)
            if result.2 {
                written += 1
            } else {
                kept += 1
            }
        }
        // Callout frames: the dark run's (or the only one).
        let framesFile = found.first { $0.id == id && $0.isFrames && $0.appearance != "light" }
            ?? found.first { $0.id == id && $0.isFrames }
        let callouts = framesFile.flatMap { try? Data(contentsOf: $0.file) }
            .flatMap { try? JSONSerialization.jsonObject(with: $0) } ?? [String: Any]()
        shots[id] = [
            "appearances": isStage ? ["dark"] : images.map(\.appearance).sorted(),
            "stage": isStage,
            "width": size.0,
            "height": size.1,
            "callouts": callouts,
        ]
    }
    manifest["schema"] = 1
    manifest["shots"] = shots
    if manifest["clips"] == nil {
        manifest["clips"] = [String: Any]()
    }
    try saveManifest(manifest)
    print("docs-shots: \(written) written, \(kept) unchanged, \(shots.count) shots in shots.json")
} catch {
    fail("\(error)")
}
