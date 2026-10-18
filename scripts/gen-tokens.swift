#!/usr/bin/env swift
// Generates Segue's colour tokens from `design/tokens.json` (the single source of truth):
//
//   - Packages/SegueUI/Sources/SegueUI/Theme/Tokens.xcassets  (colour sets, Any + Dark, plus
//     High Contrast variants for tokens that declare `lightHigh` / `darkHigh`)
//   - Packages/SegueUI/Sources/SegueUI/Theme/ColorTokens.generated.swift  (typed accessors)
//   - website/assets/css/tokens.css  (CSS custom properties, dark first, light via media query)
//
// Usage: scripts/gen-tokens.swift            regenerate in place
//        scripts/gen-tokens.swift --check    exit 1 if the checked-in output is stale
//
// Output is deterministic (fixed key order, no timestamps) so `--check` is a plain byte
// comparison. Run from anywhere; paths resolve relative to the repo root.

import Foundation

/// One colour token. Values are `#RRGGBB`, or `#RRGGBBAA` for a translucent colour.
/// `lightHigh` / `darkHigh` are optional Increase Contrast values (asset catalog
/// `"contrast": "high"`); absent, the system uses the standard value there too.
struct ColorToken: Decodable {
    let name: String
    let light: String
    let dark: String
    let lightHigh: String?
    let darkHigh: String?
    let use: String
}

struct TokenFile: Decodable {
    let color: [ColorToken]
}

enum GenError: Error, CustomStringConvertible {
    case invalidHex(token: String, value: String)
    case invalidName(String)
    case duplicate(String)

    var description: String {
        switch self {
        case let .duplicate(name): "duplicate colour token '\(name)'"
        case let .invalidHex(token, value): "token '\(token)': '\(value)' is not #RRGGBB[AA]"
        case let .invalidName(name): "token name '\(name)' is not a lowerCamelCase identifier"
        }
    }
}

let repoRoot = URL(fileURLWithPath: CommandLine.arguments[0])
    .resolvingSymlinksInPath()
    .deletingLastPathComponent()
    .deletingLastPathComponent()
let tokensURL = repoRoot.appendingPathComponent("design/tokens.json")
let themeDir = "Packages/SegueUI/Sources/SegueUI/Theme"
let catalogPath = "\(themeDir)/Tokens.xcassets"
let swiftPath = "\(themeDir)/ColorTokens.generated.swift"
let cssPath = "website/assets/css/tokens.css"

struct Components {
    let red: String
    let green: String
    let blue: String
    /// Xcode's alpha string, "1.000" for opaque.
    let alpha: String
}

/// Splits "#RRGGBB" or "#RRGGBBAA" into Xcode's "0xRR" component strings.
func components(_ hex: String, token: String) throws -> Components {
    let digits = Array(hex.uppercased())
    let isHex = (digits.count == 7 || digits.count == 9) && digits[0] == "#"
        && digits.dropFirst().allSatisfy(\.isHexDigit)
    guard isHex else { throw GenError.invalidHex(token: token, value: hex) }
    func pair(_ index: Int) -> String {
        "0x" + String(digits[index ..< index + 2])
    }
    let alpha = digits.count == 9
        ? Double(Int(String(digits[7 ..< 9]), radix: 16) ?? 255) / 255
        : 1
    return Components(
        red: pair(1), green: pair(3), blue: pair(5), alpha: String(format: "%.3f", alpha),
    )
}

/// One asset catalog colour entry; `dark` and `high` add the luminosity and contrast
/// appearances it applies to.
func colorEntry(_ hex: String, token: String, dark: Bool, high: Bool = false) throws -> String {
    let rgb = try components(hex, token: token)
    var appearances: [String] = []
    if dark {
        appearances.append("""
                {
                  "appearance" : "luminosity",
                  "value" : "dark"
                }
        """)
    }
    if high {
        appearances.append("""
                {
                  "appearance" : "contrast",
                  "value" : "high"
                }
        """)
    }
    let appearance = appearances.isEmpty
        ? ""
        : """

              "appearances" : [
        \(appearances.joined(separator: ",\n"))
              ],
        """
    return """
        {\(appearance)
          "color" : {
            "color-space" : "srgb",
            "components" : {
              "alpha" : "\(rgb.alpha)",
              "blue" : "\(rgb.blue)",
              "green" : "\(rgb.green)",
              "red" : "\(rgb.red)"
            }
          },
          "idiom" : "universal"
        }
    """
}

let info = """
  "info" : {
    "author" : "xcode",
    "version" : 1
  }
"""

func colorSet(_ token: ColorToken) throws -> String {
    var entries = try [
        colorEntry(token.light, token: token.name, dark: false),
        colorEntry(token.dark, token: token.name, dark: true),
    ]
    if let lightHigh = token.lightHigh {
        try entries.append(colorEntry(lightHigh, token: token.name, dark: false, high: true))
    }
    if let darkHigh = token.darkHigh {
        try entries.append(colorEntry(darkHigh, token: token.name, dark: true, high: true))
    }
    return """
    {
      "colors" : [
    \(entries.joined(separator: ",\n"))
      ],
    \(info)
    }

    """
}

/// "0xRRGGBB" for the colour part of a token value.
func packed(_ hex: String) -> String {
    "0x" + hex.dropFirst().prefix(6).uppercased()
}

/// The alpha of a token value as a Swift literal; nil when opaque.
func alphaLiteral(_ hex: String, token: String) throws -> String? {
    let alpha = try components(hex, token: token).alpha
    return alpha == "1.000" ? nil : alpha
}

/// The `ColorTokens` property for `token`, with its values in the doc comment.
func swiftProperty(_ token: ColorToken) -> String {
    let high = [
        token.lightHigh.map { "light \($0.uppercased())" },
        token.darkHigh.map { "dark \($0.uppercased())" },
    ]
    .compactMap(\.self)
    let highLine = high.isEmpty
        ? ""
        : "\n    /// Increase Contrast: \(high.joined(separator: ", "))."
    return """
        /// \(token.use)
        /// Light \(token.light.uppercased()), dark \(token.dark.uppercased()).\(highLine)
        public let \(token.name) = Color("\(token.name)", bundle: .module)
    """
}

/// The `ColorTokenValue.all` entry for `token`; one argument per line when it has more
/// than the three plain values, so generated lines stay short.
func swiftValue(_ token: ColorToken) throws -> String {
    let arguments = try [
        "name: \"\(token.name)\"",
        "light: \(packed(token.light))",
        "dark: \(packed(token.dark))",
        token.lightHigh.map { "lightHigh: \(packed($0))" },
        token.darkHigh.map { "darkHigh: \(packed($0))" },
        alphaLiteral(token.light, token: token.name).map { "lightAlpha: \($0)" },
        alphaLiteral(token.dark, token: token.name).map { "darkAlpha: \($0)" },
    ].compactMap(\.self)
    guard arguments.count > 3 else {
        return "        ColorTokenValue(\(arguments.joined(separator: ", "))),"
    }
    let lines = arguments.map { "            \($0)," }.joined(separator: "\n")
    return "        ColorTokenValue(\n\(lines)\n        ),"
}

/// The generated `ColorTokenValue` type (fixed text).
let valueTypeSource = """
/// One colour token's sRGB values as 0xRRGGBB (plus alpha, and the Increase Contrast
/// values when it has them), for tests and swatch views.
public struct ColorTokenValue: Sendable, Hashable {
    public let name: String
    public let light: UInt32
    public let dark: UInt32
    /// Increase Contrast values; nil when the standard value applies there too.
    public let lightHigh: UInt32?
    public let darkHigh: UInt32?
    public let lightAlpha: Double
    public let darkAlpha: Double

    init(
        name: String,
        light: UInt32,
        dark: UInt32,
        lightHigh: UInt32? = nil,
        darkHigh: UInt32? = nil,
        lightAlpha: Double = 1,
        darkAlpha: Double = 1,
    ) {
        self.name = name
        self.light = light
        self.dark = dark
        self.lightHigh = lightHigh
        self.darkHigh = darkHigh
        self.lightAlpha = lightAlpha
        self.darkAlpha = darkAlpha
    }
}
"""

func swiftSource(_ tokens: [ColorToken]) throws -> String {
    let properties = tokens.map(swiftProperty).joined(separator: "\n")
    let values = try tokens.map(swiftValue).joined(separator: "\n")
    return """
    // Generated by scripts/gen-tokens.swift from design/tokens.json - do not edit by hand.

    import SwiftUI

    /// Colour tokens from `design/tokens.json`, backed by the `Tokens` asset catalog colour
    /// sets (Any = light UI, Dark = dark stage, High Contrast where a token declares it).
    public struct ColorTokens: Sendable {
    \(properties)
    }

    \(valueTypeSource)

    public extension ColorTokenValue {
        /// Every colour token, in `tokens.json` order.
        static let all: [ColorTokenValue] = [
    \(values)
        ]
    }

    """
}

/// `cueText` -> `cue-text`: the CSS custom property name for a lowerCamelCase token.
func kebab(_ name: String) -> String {
    name.reduce(into: "") { result, char in
        if char.isUppercase {
            result += "-" + char.lowercased()
        } else {
            result.append(char)
        }
    }
}

/// The website's tokens: `:root` holds the dark (stage) values, the light (paper) values
/// swap in under `prefers-color-scheme: light`. Increase Contrast values are app-only.
func cssSource(_ tokens: [ColorToken]) throws -> String {
    func block(_ value: (ColorToken) -> String, indent: String) throws -> String {
        try tokens.map { token in
            let hex = value(token)
            _ = try components(hex, token: token.name)
            return "\(indent)--\(kebab(token.name)): \(hex.uppercased());"
        }.joined(separator: "\n")
    }
    let dark = try block(\.dark, indent: "  ")
    let light = try block(\.light, indent: "    ")
    return """
    /* Generated by scripts/gen-tokens.swift from design/tokens.json - do not edit by hand. */
    :root {
      color-scheme: dark light;
    \(dark)
    }
    @media (prefers-color-scheme: light) {
      :root {
    \(light)
      }
    }
    /* Always the stage: dark values in both schemes, like the app's stage window. */
    .scheme-stage {
      color-scheme: dark;
    \(dark)
    }

    """
}

/// Every generated file as (repo-relative path, contents).
func render() throws -> [(path: String, contents: String)] {
    let file = try JSONDecoder().decode(TokenFile.self, from: Data(contentsOf: tokensURL))
    var seen = Set<String>()
    for token in file.color {
        let valid = token.name.first?.isLowercase == true
            && token.name.allSatisfy { $0.isLetter || $0.isNumber }
        guard valid else { throw GenError.invalidName(token.name) }
        guard seen.insert(token.name).inserted else { throw GenError.duplicate(token.name) }
    }
    var files: [(String, String)] = try [
        ("\(catalogPath)/Contents.json", "{\n\(info)\n}\n"),
        (swiftPath, swiftSource(file.color)),
        (cssPath, cssSource(file.color)),
    ]
    for token in file.color {
        try files.append(("\(catalogPath)/\(token.name).colorset/Contents.json", colorSet(token)))
    }
    return files.sorted { $0.0 < $1.0 }
}

/// All regular files currently under the catalog, repo-relative.
func existingCatalogFiles() -> Set<String> {
    let root = repoRoot.appendingPathComponent(catalogPath)
    guard let walker = FileManager.default.enumerator(at: root, includingPropertiesForKeys: nil)
    else { return [] }
    var paths = Set<String>()
    for case let url as URL in walker where !url.hasDirectoryPath {
        guard url.lastPathComponent != ".DS_Store" else { continue }
        paths.insert(catalogPath + url.path.dropFirst(root.path.count))
    }
    return paths
}

do {
    let check = CommandLine.arguments.dropFirst().contains("--check")
    let files = try render()
    let expected = Set(files.map(\.path))
    if check {
        var stale: [String] = []
        for file in files {
            let url = repoRoot.appendingPathComponent(file.path)
            if (try? String(contentsOf: url, encoding: .utf8)) != file.contents {
                stale.append(file.path)
            }
        }
        stale += existingCatalogFiles().subtracting(expected).sorted().map { "\($0) (extra)" }
        guard stale.isEmpty else {
            let list = stale.map { "  \($0)" }.joined(separator: "\n")
            FileHandle.standardError.write(Data("""
            error: generated tokens are stale; run `make tokens`:
            \(list)

            """.utf8))
            exit(1)
        }
        print("gen-tokens: up to date (\(files.count) files)")
    } else {
        let catalog = repoRoot.appendingPathComponent(catalogPath)
        try? FileManager.default.removeItem(at: catalog)
        for file in files {
            let url = repoRoot.appendingPathComponent(file.path)
            try FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(), withIntermediateDirectories: true,
            )
            try Data(file.contents.utf8).write(to: url, options: .atomic)
        }
        print("gen-tokens: wrote \(files.count) files")
    }
} catch {
    FileHandle.standardError.write(Data("error: gen-tokens: \(error)\n".utf8))
    exit(1)
}
