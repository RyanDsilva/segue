#!/usr/bin/env swift
// Generates and checks the Segue website, segue.ryandsilva.dev
// (docs/release/specs/WS4-website.md section 8.1).
//
// Canonical inputs: content/site.json (the single config point), content/changelog.json,
// content/partials/*.html and the hand-written pages under website/, whose
// `<!--slot:name-->...<!--/slot-->` regions this script fills.
//
// Slots: <config.path> (escaped value), vendors.<role>.link / .siteLink / .termsLink (anchors
// to privacyUrl / url / termsUrl), vendors.<role>.shortName (first word of the name),
// owner.email.link (mailto anchor), and the computed slots in Renderer.render.
//
// Usage: scripts/gen-site.swift                   fill every slot in place, write generated files
//        scripts/gen-site.swift --check           exit 1 if any output is stale or a check fails
//        scripts/gen-site.swift --check --strict  also refuse placeholders, maker-note markers,
//                                                 missing rasters and (when live) missing art
//        scripts/gen-site.swift --raster          render the OG image, icons, wordmark PNGs and
//                                                 screenshot JPEGs (not byte-checked)
//        scripts/gen-site.swift --check-external  GET every external https link (network)
//
// Output is deterministic (fixed order, no timestamps) so `--check` is a byte comparison.
// Run from anywhere; paths resolve relative to the repo root.

import AppKit
import CryptoKit
import Foundation
import ImageIO

// MARK: - Paths, errors, small helpers

let repoRoot = URL(fileURLWithPath: CommandLine.arguments[0])
    .resolvingSymlinksInPath()
    .deletingLastPathComponent()
    .deletingLastPathComponent()
let fileManager = FileManager.default

func repoURL(_ path: String) -> URL {
    repoRoot.appendingPathComponent(path)
}

func siteURL(_ path: String) -> URL {
    repoURL("website/\(path)")
}

enum SiteError: Error, CustomStringConvertible {
    case changelog(String)
    case config(String)
    case missing(String)
    case raster(String)
    case slot(file: String, String)

    var description: String {
        switch self {
        case let .changelog(message): "content/changelog.json: \(message)"
        case let .config(message): "content/site.json: \(message)"
        case let .missing(path): "missing or unreadable file: \(path)"
        case let .raster(message): "raster: \(message)"
        case let .slot(file, message): "\(file): \(message)"
        }
    }
}

func readText(_ url: URL, label: String) throws -> String {
    guard let text = try? String(contentsOf: url, encoding: .utf8) else {
        throw SiteError.missing(label)
    }
    return text
}

func isFile(_ url: URL) -> Bool {
    var isDirectory: ObjCBool = false
    return fileManager.fileExists(atPath: url.path, isDirectory: &isDirectory)
        && !isDirectory.boolValue
}

func escapeHTML(_ text: String) -> String {
    text.replacingOccurrences(of: "&", with: "&amp;")
        .replacingOccurrences(of: "<", with: "&lt;")
        .replacingOccurrences(of: ">", with: "&gt;")
        .replacingOccurrences(of: "\"", with: "&quot;")
        .replacingOccurrences(of: "'", with: "&#39;")
}

func unescapeHTML(_ text: String) -> String {
    text.replacingOccurrences(of: "&lt;", with: "<")
        .replacingOccurrences(of: "&gt;", with: ">")
        .replacingOccurrences(of: "&quot;", with: "\"")
        .replacingOccurrences(of: "&#39;", with: "'")
        .replacingOccurrences(of: "&amp;", with: "&")
}

/// Every match of `pattern` as its capture groups (index 0 is the whole match).
func captures(_ pattern: String, in text: String, caseless: Bool = false) -> [[String]] {
    let options: NSRegularExpression.Options = caseless ? [.caseInsensitive] : []
    guard let regex = try? NSRegularExpression(pattern: pattern, options: options) else {
        return []
    }
    let range = NSRange(text.startIndex..., in: text)
    return regex.matches(in: text, range: range).map { match in
        (0 ..< match.numberOfRanges).map { index in
            Range(match.range(at: index), in: text).map { String(text[$0]) } ?? ""
        }
    }
}

func sha256(_ data: Data) -> String {
    SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
}

/// `{UPPER_SNAKE}` values that only a [RYAN] step can fill.
let placeholderPattern = #"\{[A-Z][A-Z0-9_]*\}"#

func isPlaceholder(_ text: String) -> Bool {
    !captures(placeholderPattern, in: text).isEmpty
}

// MARK: - Fixed facts from the spec

enum Spec {
    /// Section 2: site anchors linked from outside (the app's guide links are checked from
    /// SegueLinks.swift itself, WS6 7.1). Never rename without a redirect.
    static let contractLinks = [
        "/guide", "/support#report-a-bug", "/support#request-a-feature",
        "/privacy#usage-statistics", "/privacy#crash-reports", "/privacy#bug-reports",
        "/privacy#your-choices",
    ]
    /// The user guide (WS6): built by Astro into website/guide (gitignored), so its pages are
    /// not hand pages; links into it resolve against the build (`make guide` runs first).
    static let guideDirectory = "guide/"
    static let guideHome = "guide.html"
    /// Section 9.3, checked byte for byte in `_headers`.
    static let csp = "Content-Security-Policy: default-src 'none'; "
        + "script-src https://static.cloudflareinsights.com; "
        + "connect-src 'self'; img-src 'self'; style-src 'self'; "
        + "font-src 'self'; base-uri 'none'; form-action 'none'; frame-ancestors 'none'; "
        + "upgrade-insecure-requests"
    /// WS6 4.5: the guide's CSP, under a `/guide/*` rule that first detaches the site CSP.
    /// Starlight's own bundled scripts (search, menu) run from 'self'; Pagefind needs
    /// WebAssembly ('wasm-unsafe-eval') and draws its icons as data: images; clips are
    /// same-origin media. Set on both `/guide` (the home, guide.html) and `/guide/*`.
    static let guideCSP = "Content-Security-Policy: default-src 'none'; "
        + "script-src 'self' 'wasm-unsafe-eval' https://static.cloudflareinsights.com; "
        + "connect-src 'self'; img-src 'self' data:; media-src 'self'; style-src 'self'; "
        + "font-src 'self'; base-uri 'none'; form-action 'none'; frame-ancestors 'none'; "
        + "upgrade-insecure-requests"
    static let homeTitle = "Segue - Setlists & Chords for Mac"
    static let appleBadge = "assets/img/badge-mac-app-store-black.svg"
    static let badgeHeight = 48
    /// Rendered by `--raster`; `--check` verifies presence and pixel size.
    static let rasters: [(path: String, width: Int, height: Int)] = [
        ("assets/img/og.png", 1200, 630),
        ("apple-touch-icon.png", 180, 180),
        ("favicon-32.png", 32, 32),
        ("assets/img/wordmark-dark.png", 640, 256),
        ("assets/img/wordmark-light.png", 640, 256),
    ]
    /// Copies of design files: (published path, source path, required?).
    static let copies: [(path: String, source: String, required: Bool)] = [
        ("favicon.svg", "design/icon/icon-32.svg", true),
        ("assets/img/icon.svg", "design/icon/master.svg", true),
        // Regenerated by `make icon` (gitignored there); committed here as the press asset.
        ("assets/img/icon-1024.png", "design/icon/previews/icon-default-1024.png", false),
    ]
    /// Privacy-policy processor roles: (site.json vendors key, what the provider does).
    static let vendorRoles: [(key: String, purpose: String)] = [
        ("analytics", "usage statistics"), ("crash", "crash reports"),
        ("bugReports", "bug reports"), ("board", "feature board"),
        ("hosting", "website hosting"), ("webAnalytics", "website analytics"),
        ("emailRouting", "email forwarding"), ("inbox", "email inbox"),
    ]
    static let fontSources = "Packages/SegueUI/Sources/SegueUI/Theme/Fonts"
    /// The notices shipped in the app bundle; every site credit must be named in them.
    static let thirdPartyNotices = "THIRD_PARTY_NOTICES.md"
    /// The app's one URL table: every site URL in it must resolve (check 1).
    static let appLinks = "Packages/SegueUI/Sources/SegueUI/App/SegueLinks.swift"
    static let screenshotSource = ".build/screenshots/raw"
}

// MARK: - content/site.json

struct Config {
    let root: [String: Any]

    func value(_ path: String) -> Any? {
        var node: Any? = root
        for key in path.split(separator: ".") {
            node = (node as? [String: Any])?[String(key)]
        }
        return node
    }

    func string(_ path: String) throws -> String {
        guard let text = value(path) as? String else {
            throw SiteError.config("\(path) is missing or not a string")
        }
        return text
    }

    var origin: String {
        (try? string("site.origin")) ?? ""
    }

    var isLive: Bool {
        (try? string("appStore.status")) == "live"
    }

    var credits: [[String: String]] {
        (value("credits") as? [[String: Any]] ?? []).map { credit in
            credit.compactMapValues { $0 as? String }
        }
    }

    /// `redirects`: moved pages, e.g. the old /help pages to the guide (WS6 7.3).
    func redirects() throws -> [(from: String, to: String, status: Int)] {
        guard let list = root["redirects"] as? [[String: Any]] else { return [] }
        return try list.enumerated().map { index, item in
            guard let from = item["from"] as? String, from.hasPrefix("/"),
                  let to = item["to"] as? String, to.hasPrefix("/"),
                  let status = (item["status"] as? NSNumber)?.intValue, [301, 302].contains(status),
                  item.count == 3
            else {
                throw SiteError.config(
                    "redirects[\(index)] needs exactly from, to (paths) and status (301 or 302)",
                )
            }
            return (from, to, status)
        }
    }

    func campaignLink(_ campaign: String) throws -> String {
        let appleID = try string("appStore.appleId")
        let token = try string("appStore.providerToken")
        let media = try string("appStore.mediaType")
        let tag = try string("appStore.campaigns.\(campaign)")
        return "https://apps.apple.com/app/apple-store/id\(appleID)?pt=\(token)&ct=\(tag)&mt=\(media)"
    }

    /// Every string leaf as (dotted path, value), in sorted key order.
    func leaves() -> [(path: String, value: String)] {
        func walk(_ node: Any, _ path: String) -> [(String, String)] {
            if let text = node as? String {
                return [(path, text)]
            }
            if let object = node as? [String: Any] {
                return object.keys.sorted().flatMap { key in
                    walk(object[key] as Any, path.isEmpty ? key : "\(path).\(key)")
                }
            }
            if let array = node as? [Any] {
                return array.enumerated().flatMap { walk($1, "\(path)[\($0)]") }
            }
            return []
        }
        return walk(root, "")
    }
}

func loadConfig() throws -> Config {
    let data = try Data(contentsOf: repoURL("content/site.json"))
    guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
        throw SiteError.config("top level is not an object")
    }
    let config = Config(root: root)
    guard (root["schema"] as? NSNumber)?.intValue == 1 else {
        throw SiteError.config("schema must be 1")
    }
    let required = [
        "site.origin", "site.name", "site.tagline", "owner.legalName", "owner.email",
        "owner.country", "owner.governingState", "legal.privacyEffectiveDate",
        "legal.termsEffectiveDate", "legal.copyrightYear", "app.requirements",
        "appStore.status", "appStore.appleId", "appStore.providerToken", "appStore.mediaType",
        "appStore.campaigns.hero", "appStore.campaigns.footer", "appStore.campaigns.press",
        "vendors.board.boardUrl",
    ]
    for path in required {
        _ = try config.string(path)
    }
    for role in Spec.vendorRoles {
        for field in ["name", "privacyUrl", "location"] {
            _ = try config.string("vendors.\(role.key).\(field)")
        }
    }
    guard try ["upcoming", "live"].contains(config.string("appStore.status")) else {
        throw SiteError.config("appStore.status must be \"upcoming\" or \"live\"")
    }
    let origin = config.origin
    guard origin.hasPrefix("https://"), !origin.hasSuffix("/") else {
        throw SiteError.config("site.origin must be https:// with no trailing slash")
    }
    guard let credits = root["credits"] as? [[String: Any]] else {
        throw SiteError.config("credits must be an array of objects")
    }
    for (index, credit) in credits.enumerated() {
        for field in ["name", "summary", "licence", "source", "licenceFile"]
            where !(credit[field] is String)
        {
            throw SiteError.config("credits[\(index)].\(field) is missing or not a string")
        }
    }
    return config
}

// MARK: - content/changelog.json (schema 1, section 6.2)

struct Highlight {
    let kind: String
    let text: String
    let help: String?
}

struct Release {
    let version: String
    let date: String
    let title: String
    let summary: String?
    let showInApp: Bool
    let draft: Bool
    let highlights: [Highlight]
}

func jsonBool(_ value: Any?) -> Bool? {
    guard let number = value as? NSNumber, CFGetTypeID(number) == CFBooleanGetTypeID() else {
        return nil
    }
    return number.boolValue
}

/// Why `text` is not acceptable plain text for the changelog, or nil.
func plainTextProblem(_ text: String) -> String? {
    if let bad = text.first(where: { "<>`*_[]\n\u{2014}".contains($0) }) {
        let shown = bad == "\u{2014}" ? "an em dash" : bad == "\n" ? "a newline" : "'\(bad)'"
        return "contains \(shown) (plain text only)"
    }
    if text.hasPrefix("#") {
        return "starts with '#' (plain text only)"
    }
    if text != text.trimmingCharacters(in: .whitespaces) {
        return "has leading or trailing spaces"
    }
    return nil
}

func versionComponents(_ version: String) -> [Int] {
    let parts = version.split(separator: ".").compactMap { Int($0) }
    return parts + Array(repeating: 0, count: max(0, 3 - parts.count))
}

func isValidDate(_ text: String) -> Bool {
    guard !captures(#"^\d{4}-\d{2}-\d{2}$"#, in: text).isEmpty else { return false }
    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.timeZone = TimeZone(identifier: "UTC")
    formatter.dateFormat = "yyyy-MM-dd"
    return formatter.date(from: text).map { formatter.string(from: $0) } == text
}

func checkKeys(_ object: [String: Any], allowed: Set<String>, at path: String) throws {
    if let unknown = object.keys.sorted().first(where: { !allowed.contains($0) }) {
        throw SiteError.changelog("\(path): unknown key \"\(unknown)\"")
    }
}

func requireText(
    _ object: [String: Any], _ key: String, at path: String, max: Int, optional: Bool = false,
) throws -> String? {
    guard let raw = object[key] else {
        if optional {
            return nil
        }
        throw SiteError.changelog("\(path).\(key) is required")
    }
    guard let text = raw as? String else {
        throw SiteError.changelog("\(path).\(key) must be a string")
    }
    guard (1 ... max).contains(text.count) else {
        throw SiteError.changelog("\(path).\(key) must be 1-\(max) characters (has \(text.count))")
    }
    if let problem = plainTextProblem(text) {
        throw SiteError.changelog("\(path).\(key) \(problem)")
    }
    return text
}

func parseHighlight(_ raw: Any, at path: String) throws -> Highlight {
    guard let object = raw as? [String: Any] else {
        throw SiteError.changelog("\(path) must be an object")
    }
    try checkKeys(object, allowed: ["kind", "text", "help"], at: path)
    guard let kind = object["kind"] as? String, ["new", "improved", "fixed"].contains(kind) else {
        throw SiteError.changelog("\(path).kind must be \"new\", \"improved\" or \"fixed\"")
    }
    let text = try requireText(object, "text", at: path, max: 120) ?? ""
    var help: String?
    if let raw = object["help"] {
        guard let link = raw as? String,
              ["/guide", "/support", "/privacy"].contains(where: { link.hasPrefix($0) })
        else {
            throw SiteError.changelog("\(path).help must start with /guide, /support or /privacy")
        }
        help = link
    }
    return Highlight(kind: kind, text: text, help: help)
}

func parseRelease(_ raw: Any, at path: String) throws -> Release {
    guard let object = raw as? [String: Any] else {
        throw SiteError.changelog("\(path) must be an object")
    }
    let allowed: Set = ["version", "date", "title", "summary", "showInApp", "draft", "highlights"]
    try checkKeys(object, allowed: allowed, at: path)
    guard let version = object["version"] as? String,
          !captures(#"^\d+\.\d+(\.\d+)?$"#, in: version).isEmpty
    else {
        throw SiteError.changelog("\(path).version must look like 0.5 or 0.5.1")
    }
    guard let date = object["date"] as? String, isValidDate(date) else {
        throw SiteError.changelog("\(path).date must be a real YYYY-MM-DD date")
    }
    let title = try requireText(object, "title", at: path, max: 60) ?? ""
    let summary = try requireText(object, "summary", at: path, max: 200, optional: true)
    guard let showInApp = jsonBool(object["showInApp"]) else {
        throw SiteError.changelog("\(path).showInApp is required and must be true or false")
    }
    let draft = object["draft"] == nil ? false : jsonBool(object["draft"])
    guard let draft else { throw SiteError.changelog("\(path).draft must be true or false") }
    guard let items = object["highlights"] as? [Any], (1 ... 8).contains(items.count) else {
        throw SiteError.changelog("\(path).highlights must hold 1-8 items")
    }
    let highlights = try items.enumerated().map { index, item in
        try parseHighlight(item, at: "\(path).highlights[\(index)]")
    }
    return Release(
        version: version, date: date, title: title, summary: summary, showInApp: showInApp,
        draft: draft, highlights: highlights,
    )
}

/// Every release in the source, drafts included, validated against schema 1.
func loadChangelog() throws -> [Release] {
    let data = try Data(contentsOf: repoURL("content/changelog.json"))
    guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
        throw SiteError.changelog("top level is not an object")
    }
    try checkKeys(root, allowed: ["schema", "releases"], at: "root")
    guard (root["schema"] as? NSNumber)?.intValue == 1, jsonBool(root["schema"]) == nil else {
        throw SiteError.changelog("schema must be 1")
    }
    guard let items = root["releases"] as? [Any] else {
        throw SiteError.changelog("releases must be an array")
    }
    let releases = try items.enumerated().map { try parseRelease($1, at: "releases[\($0)]") }
    for (older, newer) in zip(releases.dropFirst(), releases) {
        let label = "releases \(newer.version) and \(older.version)"
        let isNewer = versionComponents(older.version)
            .lexicographicallyPrecedes(versionComponents(newer.version))
        guard isNewer else {
            throw SiteError.changelog("\(label): newest first, versions unique")
        }
        guard newer.date >= older.date else {
            throw SiteError.changelog("\(label): dates must not increase down the list")
        }
    }
    return releases
}

func jsonString(_ text: String) -> String {
    var out = "\""
    for scalar in text.unicodeScalars {
        switch scalar {
        case "\"": out += "\\\""
        case "\\": out += "\\\\"
        case "\n": out += "\\n"
        case "\t": out += "\\t"
        case _ where scalar.value < 0x20: out += String(format: "\\u%04x", scalar.value)
        default: out.unicodeScalars.append(scalar)
        }
    }
    return out + "\""
}

/// `website/changelog.json`: drafts removed, fixed key order. The app bundles this file.
func publishedChangelogJSON(_ releases: [Release]) -> String {
    let entries = releases.map { release in
        var fields = [
            "\"version\": \(jsonString(release.version))",
            "\"date\": \(jsonString(release.date))",
            "\"title\": \(jsonString(release.title))",
        ]
        if let summary = release.summary {
            fields.append("\"summary\": \(jsonString(summary))")
        }
        fields.append("\"showInApp\": \(release.showInApp)")
        let highlights = release.highlights.map { item in
            var parts = ["\"kind\": \(jsonString(item.kind))", "\"text\": \(jsonString(item.text))"]
            if let help = item.help {
                parts.append("\"help\": \(jsonString(help))")
            }
            return "        { " + parts.joined(separator: ", ") + " }"
        }.joined(separator: ",\n")
        fields.append("\"highlights\": [\n\(highlights)\n      ]")
        return "    {\n" + fields.map { "      \($0)" }.joined(separator: ",\n") + "\n    }"
    }
    let body = entries.isEmpty ? "[]" : "[\n" + entries.joined(separator: ",\n") + "\n  ]"
    return "{\n  \"schema\": 1,\n  \"releases\": \(body)\n}\n"
}

// MARK: - Slots

struct SlotMatch {
    let name: String
    /// `<!--slot:name-->`
    let open: Range<String.Index>
    /// `<!--/slot-->`
    let close: Range<String.Index>
}

func lineNumber(_ index: String.Index, in text: String) -> Int {
    text[..<index].count(where: { $0 == "\n" }) + 1
}

func findSlots(in html: String, file: String) throws -> [SlotMatch] {
    var result: [SlotMatch] = []
    var cursor = html.startIndex
    while true {
        let rest = cursor ..< html.endIndex
        let open = html.range(of: "<!--slot:", range: rest)
        let close = html.range(of: "<!--/slot-->", range: rest)
        guard let open else {
            if let close {
                let line = lineNumber(close.lowerBound, in: html)
                throw SiteError.slot(
                    file: file,
                    "line \(line): closing slot marker without opening",
                )
            }
            return result
        }
        let line = lineNumber(open.lowerBound, in: html)
        guard let close, close.lowerBound > open.lowerBound else {
            throw SiteError.slot(file: file, "line \(line): unbalanced slot markers")
        }
        guard let nameEnd = html.range(of: "-->", range: open.upperBound ..< close.lowerBound)
        else {
            throw SiteError.slot(file: file, "line \(line): malformed slot marker")
        }
        let name = String(html[open.upperBound ..< nameEnd.lowerBound])
        if html.range(of: "<!--slot:", range: nameEnd.upperBound ..< close.lowerBound) != nil {
            throw SiteError.slot(
                file: file,
                "line \(line): slot \"\(name)\" contains a nested slot",
            )
        }
        result.append(SlotMatch(
            name: name,
            open: open.lowerBound ..< nameEnd.upperBound,
            close: close,
        ))
        cursor = close.upperBound
    }
}

/// Replaces each slot's content; `keepMarkers: false` drops the markers (used for partials,
/// whose slots must not survive into the page as nested slots).
func fillSlots(
    _ html: String, file: String, keepMarkers: Bool = true, render: (String) throws -> String,
) throws -> String {
    var out = ""
    var cursor = html.startIndex
    for slot in try findSlots(in: html, file: file) {
        out += html[cursor ..< (keepMarkers ? slot.open.upperBound : slot.open.lowerBound)]
        do {
            out += try render(slot.name)
        } catch let error as SiteError {
            throw SiteError.slot(
                file: file, "line \(lineNumber(slot.open.lowerBound, in: html)): \(error)",
            )
        }
        if keepMarkers {
            out += html[slot.close]
        }
        cursor = slot.close.upperBound
    }
    out += html[cursor...]
    return out
}

// MARK: - Pages

struct Page {
    /// Path under website/, e.g. "help/live.html".
    let file: String
    /// URL path, e.g. "/help/live" ("/" for index.html).
    let path: String
    let title: String
    let description: String

    init(file: String, html: String) {
        self.file = file
        let stem = String(file.dropLast(".html".count))
        path = stem == "index" ? "/" : "/" +
            (stem.hasSuffix("/index") ? String(stem.dropLast(5)) : stem)
        title = unescapeHTML(captures(#"<title>([^<]*)</title>"#, in: html).first?[1] ?? "")
        description = unescapeHTML(
            captures(#"<meta name="description" content="([^"]*)">"#, in: html).first?[1] ?? "",
        )
    }
}

/// Every hand-written page (everything but the generated changelog), sorted.
func handPages() -> [String] {
    files(under: "website").filter {
        $0.hasSuffix(".html") && $0 != "changelog.html" && !isGuideOutput($0)
    }
}

/// Built by `make guide` (gitignored): website/guide/** and the home page website/guide.html.
func isGuideOutput(_ path: String) -> Bool {
    path.hasPrefix(Spec.guideDirectory) || path == Spec.guideHome
}

/// The built guide's pages, empty before `make guide`.
func guidePages() -> [String] {
    files(under: "website").filter { isGuideOutput($0) && $0.hasSuffix(".html") }
}

/// Regular files under a repo directory, as sorted paths relative to it.
func files(under directory: String) -> [String] {
    let root = repoURL(directory)
    let paths = (try? fileManager.subpathsOfDirectory(atPath: root.path)) ?? []
    return paths.filter { path in
        !path.hasSuffix(".DS_Store") && isFile(root.appendingPathComponent(path))
    }.sorted()
}

// MARK: - Slot rendering

struct Renderer {
    let config: Config
    /// Published (non-draft) releases, newest first.
    let releases: [Release]

    func render(_ name: String, page: Page) throws -> String {
        switch name {
        case "partial:header": try partial("header", page: page)
        case "partial:footer": try partial("footer", page: page)
        case "appstore:hero": try appStore("hero")
        case "appstore:footer": try appStore("footer")
        case "appstore:press": try appStore("press")
        case "latest-release": latestRelease()
        case "vendor-table": try vendorTable()
        case "retention-table": try retentionTable()
        case "credits": try credits()
        case "year": try escapeHTML(config.string("legal.copyrightYear"))
        case "meta:og": openGraph(page)
        default: try configValue(name)
        }
    }

    func configValue(_ name: String) throws -> String {
        if name == "owner.email.link" {
            let email = try escapeHTML(config.string("owner.email"))
            return "<a href=\"mailto:\(email)\">\(email)</a>"
        }
        if name.hasSuffix(".shortName"), name.hasPrefix("vendors.") {
            // "Cloudflare (Cloudflare Pages)" -> "Cloudflare", for running text.
            let full = try config.string(String(name.dropLast(".shortName".count)) + ".name")
            return escapeHTML(String(full.split(separator: " ").first ?? ""))
        }
        let links = [(".link", "privacyUrl"), (".siteLink", "url"), (".termsLink", "termsUrl")]
        for (suffix, field) in links where name.hasSuffix(suffix) {
            let base = String(name.dropLast(suffix.count))
            guard base.hasPrefix("vendors."), config.value(base) is [String: Any] else {
                throw SiteError.config("unknown slot \"\(name)\" (\(suffix) needs a vendor)")
            }
            let href = try config.string("\(base).\(field)")
            // A placeholder renders as visible text, never as a dead link.
            if isPlaceholder(href) {
                return escapeHTML(href)
            }
            let label = suffix == ".termsLink"
                ? href.replacingOccurrences(of: "https://", with: "")
                : try config.string("\(base).name")
            return "<a href=\"\(escapeHTML(href))\">\(escapeHTML(label))</a>"
        }
        switch config.value(name) {
        case let text as String: return escapeHTML(text)
        case let number as NSNumber where jsonBool(number) == nil: return number.stringValue
        default: throw SiteError.config("unknown slot \"\(name)\"")
        }
    }

    func partial(_ name: String, page: Page) throws -> String {
        let file = "content/partials/\(name).html"
        let source = try readText(repoURL(file), label: file)
        var html = try fillSlots(source, file: file, keepMarkers: false) { slot in
            guard !slot.hasPrefix("partial:") else {
                throw SiteError.slot(file: file, "partials cannot include partials")
            }
            return try render(slot, page: page)
        }
        html = html.trimmingCharacters(in: .whitespacesAndNewlines)
        if name != "footer" {
            html = html.replacingOccurrences(
                of: "<a href=\"\(page.path)\"",
                with: "<a href=\"\(page.path)\" aria-current=\"page\"",
            )
        }
        return "\n\(html)\n"
    }

    func appStore(_ campaign: String) throws -> String {
        guard config.isLive else { return "Coming soon to the Mac App Store." }
        let href = try escapeHTML(config.campaignLink(campaign))
        guard campaign == "hero" else {
            return "<a href=\"\(href)\">Download Segue on the Mac App Store</a>"
        }
        let width = try badgeWidth()
        return "<a href=\"\(href)\"><img src=\"/\(Spec.appleBadge)\" "
            + "alt=\"Download on the Mac App Store\" width=\"\(width)\" "
            + "height=\"\(Spec.badgeHeight)\" fetchpriority=\"high\"></a>"
    }

    /// The badge's width at 48 px tall, from its SVG viewBox.
    func badgeWidth() throws -> Int {
        let svg = try readText(siteURL(Spec.appleBadge), label: "website/\(Spec.appleBadge)")
        guard let box = captures(#"viewBox="([^"]+)""#, in: svg).first?[1] else {
            throw SiteError.missing("viewBox in website/\(Spec.appleBadge)")
        }
        let numbers = box.split(whereSeparator: { $0 == " " || $0 == "," }).compactMap {
            Double($0)
        }
        guard numbers.count == 4, numbers[3] > 0 else {
            throw SiteError.missing("valid viewBox in website/\(Spec.appleBadge)")
        }
        return Int((numbers[2] / numbers[3] * Double(Spec.badgeHeight)).rounded())
    }

    func latestRelease() -> String {
        guard let release = releases.first else { return "" }
        let items = release.highlights.prefix(3).map { item in
            "<li><span class=\"kind\">\(kindLabel(item.kind))</span> \(escapeHTML(item.text))</li>"
        }
        return """

        <div class="latest-release">
        <p class="latest-release-title">New in \(release.version): \(escapeHTML(release.title))</p>
        <ul>
        \(items.joined(separator: "\n"))
        </ul>
        <p><a href="/changelog">See all changes</a></p>
        </div>

        """
    }

    func vendorTable() throws -> String {
        var groups: [(url: String, roles: [(key: String, purpose: String)])] = []
        for role in Spec.vendorRoles {
            let privacy = try config.string("vendors.\(role.key).privacyUrl")
            if let index = groups.firstIndex(where: { $0.url == privacy }) {
                groups[index].roles.append(role)
            } else {
                groups.append((privacy, [role]))
            }
        }
        let rows = try groups.map { group in
            let names = try group.roles.map { try config.string("vendors.\($0.key).name") }
            let name = commonName(names)
            let purposes = group.roles.map(\.purpose)
            let purpose = purposes.dropLast().joined(separator: ", ")
                + (purposes.count > 1 ? " and " : "") + (purposes.last ?? "")
            let location = try config.string("vendors.\(group.roles[0].key).location")
            return "<tr><th scope=\"row\">\(escapeHTML(name))</th>"
                + "<td>\(escapeHTML(sentenceCase(purpose)))</td><td>\(escapeHTML(sentenceCase(location)))</td>"
                + "<td><a href=\"\(escapeHTML(group.url))\">"
                + "\(escapeHTML(name)) privacy policy</a></td></tr>"
        }
        return """

        <table>
        <thead><tr><th scope="col">Provider</th><th scope="col">What for</th>\
        <th scope="col">Where</th><th scope="col">Privacy policy</th></tr></thead>
        <tbody>
        \(rows.joined(separator: "\n"))
        </tbody>
        </table>

        """
    }

    func retentionTable() throws -> String {
        let host = try config.string("vendors.hosting.name").split(separator: " ").first ?? ""
        let rows: [(String, String)] = try [
            (
                "Usage statistics",
                config.string("vendors.analytics.retention")
                    + "; the identifier in them is scrambled twice and can't be traced back to you",
            ),
            ("Crash reports", config.string("vendors.crash.retention")),
            (
                "Bug reports, including attached songs",
                config.string("vendors.bugReports.retention"),
            ),
            ("Feature board posts and votes", config.string("vendors.board.retention")),
            ("Feature board email", "until you unsubscribe or ask us to remove it"),
            ("Email to \(config.string("owner.email"))", config.string("vendors.inbox.retention")),
            ("Website analytics (totals only)", config.string("vendors.webAnalytics.retention")),
            ("Website request logs", "\(host)'s standard retention; we receive no per-visit logs"),
        ]
        let body = rows.map { what, howLong in
            "<tr><th scope=\"row\">\(escapeHTML(what))</th><td>\(escapeHTML(howLong))</td></tr>"
        }
        return """

        <table>
        <thead><tr><th scope="col">What</th><th scope="col">How long</th></tr></thead>
        <tbody>
        \(body.joined(separator: "\n"))
        </tbody>
        </table>

        """
    }

    func credits() throws -> String {
        let sections = try config.credits.map { credit in
            let name = credit["name"] ?? ""
            let source = credit["source"] ?? ""
            let licencePath = credit["licenceFile"] ?? ""
            let licence = try readText(repoURL(licencePath), label: licencePath)
                .split(separator: "\n", omittingEmptySubsequences: false)
                .map { $0.replacingOccurrences(of: #"\s+$"#, with: "", options: .regularExpression)
                }
                .joined(separator: "\n")
            let shown = source.replacingOccurrences(of: "https://", with: "")
            return """
            <section class="credit">
            <h2>\(escapeHTML(name))</h2>
            <p>\(escapeHTML(credit["summary"] ?? ""))</p>
            <p>\(escapeHTML(credit["licence"] ?? "")). <a href="\(escapeHTML(source))">\(escapeHTML(shown))</a></p>
            <details>
            <summary>\(escapeHTML(name)) licence text</summary>
            <pre>\(escapeHTML(licence.trimmingCharacters(in: .whitespacesAndNewlines)))</pre>
            </details>
            </section>
            """
        }
        return "\n" + sections.joined(separator: "\n") + "\n"
    }

    func openGraph(_ page: Page) -> String {
        let origin = config.origin
        let tags = [
            ("property", "og:type", "website"),
            ("property", "og:site_name", (try? config.string("site.name")) ?? "Segue"),
            ("property", "og:title", page.title),
            ("property", "og:description", page.description),
            ("property", "og:url", origin + page.path),
            ("property", "og:image", "\(origin)/assets/img/og.png"),
            ("property", "og:image:width", "1200"),
            ("property", "og:image:height", "630"),
            ("property", "og:image:alt", "Segue for Mac: your chart, your set, your cue."),
            ("name", "twitter:card", "summary_large_image"),
        ]
        let lines = tags.map { kind, key, value in
            "<meta \(kind)=\"\(key)\" content=\"\(escapeHTML(value))\">"
        }
        return "\n" + lines.joined(separator: "\n") + "\n"
    }
}

func kindLabel(_ kind: String) -> String {
    switch kind {
    case "fixed": "Fixed"
    case "improved": "Improved"
    default: "New"
    }
}

func sentenceCase(_ text: String) -> String {
    text.prefix(1).uppercased() + text.dropFirst()
}

/// The leading words all names share ("Cloudflare (Cloudflare Pages)" and "Cloudflare Web
/// Analytics" -> "Cloudflare"), or the single name.
func commonName(_ names: [String]) -> String {
    guard let first = names.first, names.count > 1 else { return names.first ?? "" }
    var words = first.split(separator: " ")
    for name in names.dropFirst() {
        let other = name.split(separator: " ")
        words = Array(zip(words, other).prefix { $0 == $1 }.map(\.0))
    }
    return words.isEmpty ? first : words.joined(separator: " ")
}

// MARK: - Fully generated outputs

let monthNames = [
    "January", "February", "March", "April", "May", "June", "July", "August", "September",
    "October", "November", "December",
]

func longDate(_ iso: String) -> String {
    let parts = iso.split(separator: "-").compactMap { Int($0) }
    guard parts.count == 3, (1 ... 12).contains(parts[1]) else { return iso }
    return "\(monthNames[parts[1] - 1]) \(parts[2]), \(parts[0])"
}

func changelogTemplate(_ releases: [Release], origin: String) -> String {
    let sections = releases.map { release in
        var lines = [
            "<section class=\"release\" id=\"v\(release.version)\">",
            "<h2>Version \(release.version): \(escapeHTML(release.title))</h2>",
            "<p><time datetime=\"\(release.date)\">\(longDate(release.date))</time></p>",
        ]
        if let summary = release.summary {
            lines.append("<p>\(escapeHTML(summary))</p>")
        }
        for kind in ["new", "improved", "fixed"] {
            let items = release.highlights.filter { $0.kind == kind }
            guard !items.isEmpty else { continue }
            lines.append("<h3>\(kindLabel(kind))</h3>")
            lines.append("<ul>")
            for item in items {
                let more = item.help.map { " <a href=\"\(escapeHTML($0))\">Learn more</a>" } ?? ""
                lines.append("<li>\(escapeHTML(item.text))\(more)</li>")
            }
            lines.append("</ul>")
        }
        lines.append("</section>")
        return lines.joined(separator: "\n")
    }
    let body = sections.isEmpty
        ? "<p>The first release is on its way.</p>"
        : sections.joined(separator: "\n")
    return """
    <!DOCTYPE html>
    <!-- Generated by scripts/gen-site.swift from content/changelog.json - do not edit by hand. -->
    <html lang="en">
    <head>
    <meta charset="utf-8">
    <meta name="viewport" content="width=device-width, initial-scale=1">
    <title>Changelog - Segue</title>
    <meta name="description" content="What changed in each version of Segue for Mac: new features, improvements and fixes, newest first.">
    <link rel="canonical" href="\(origin)/changelog">
    <link rel="preload" href="/assets/fonts/schibsted-grotesk-800.woff2" as="font" type="font/woff2" crossorigin>
    <link rel="preload" href="/assets/fonts/schibsted-grotesk-400.woff2" as="font" type="font/woff2" crossorigin>
    <link rel="stylesheet" href="/assets/css/tokens.css">
    <link rel="stylesheet" href="/assets/css/site.css">
    <link rel="icon" href="/favicon.svg" type="image/svg+xml">
    <link rel="icon" href="/favicon-32.png" sizes="32x32" type="image/png">
    <link rel="apple-touch-icon" href="/apple-touch-icon.png">
    <!--slot:meta:og--><!--/slot-->
    </head>
    <body>
    <!--slot:partial:header--><!--/slot-->
    <main id="main">
    <div class="doc">
    <h1>Changelog</h1>
    <p class="lede">What changed in each version of Segue. Segue shows the bigger updates in the app too, under <span class="nowrap">Help &gt; What's New in Segue</span>.</p>
    <div class="prose">
    \(body)
    </div>
    </div>
    </main>
    <!--slot:partial:footer--><!--/slot-->
    </body>
    </html>

    """
}

func redirectsFile(_ config: Config) throws -> String {
    let board = try config.string("vendors.board.boardUrl")
    let feedback = isPlaceholder(board) ? "/support#request-a-feature" : board
    let moved = try config.redirects().map { "\($0.from) \($0.to) \($0.status)" }
    return (["/feedback \(feedback) 302", "/favicon.ico /favicon-32.png 301"] + moved)
        .joined(separator: "\n") + "\n"
}

func sitemap(_ pages: [Page], html: [String: String], origin: String) -> String {
    let urls = pages.filter { page in
        page.file != "404.html" && !(html[page.file] ?? "").contains("content=\"noindex")
    }.map(\.path).sorted()
    let entries = urls.map { "  <url><loc>\(origin)\($0)</loc></url>" }
    return """
    <?xml version="1.0" encoding="UTF-8"?>
    <urlset xmlns="http://www.sitemaps.org/schemas/sitemap/0.9">
    \(entries.joined(separator: "\n"))
    </urlset>

    """
}

struct Build {
    let config: Config
    let allReleases: [Release]
    /// Every generated or filled file, keyed by path under website/.
    var outputs: [String: Data] = [:]
    /// Every page's final HTML, keyed by path under website/.
    var pages: [String: String] = [:]
    var pageInfo: [Page] = []
}

func build() throws -> Build {
    let config = try loadConfig()
    let allReleases = try loadChangelog()
    let published = allReleases.filter { !$0.draft }
    let renderer = Renderer(config: config, releases: published)
    var result = Build(config: config, allReleases: allReleases)

    var sources = try handPages().map { file in
        try (file, readText(siteURL(file), label: "website/\(file)"))
    }
    sources.append(("changelog.html", changelogTemplate(published, origin: config.origin)))
    for (file, source) in sources {
        let page = Page(file: file, html: source)
        let html = try fillSlots(source, file: "website/\(file)") { name in
            try renderer.render(name, page: page)
        }
        result.pages[file] = html
        result.pageInfo.append(page)
        result.outputs[file] = Data(html.utf8)
    }
    result.pageInfo.sort { $0.file < $1.file }
    result.outputs["changelog.json"] = Data(publishedChangelogJSON(published).utf8)
    result.outputs["_redirects"] = try Data(redirectsFile(config).utf8)
    result.outputs["sitemap.xml"] = Data(
        sitemap(result.pageInfo, html: result.pages, origin: config.origin).utf8,
    )
    for copy in Spec.copies {
        if let data = try? Data(contentsOf: repoURL(copy.source)) {
            result.outputs[copy.path] = data
        } else if copy.required {
            throw SiteError.missing(copy.source)
        }
    }
    return result
}

// MARK: - Content checks (--check)

struct Checker {
    let build: Build
    let strict: Bool
    var failures: [String] = []

    /// Contents of a published file: the in-memory output if generated, else the disk copy.
    func data(_ path: String) -> Data? {
        build.outputs[path] ?? (isFile(siteURL(path)) ? try? Data(contentsOf: siteURL(path)) : nil)
    }

    func exists(_ path: String) -> Bool {
        build.outputs[path] != nil || isFile(siteURL(path))
    }

    /// All published files, sorted, as paths under website/.
    func publishedFiles() -> [String] {
        Set(build.outputs.keys).union(files(under: "website")).sorted()
    }

    static let textExtensions: Set = ["html", "css", "json", "txt", "xml", "svg", ""]

    func textFiles() -> [(path: String, text: String)] {
        publishedFiles().compactMap { path in
            // The built guide: its pages only (its bundled assets are checked by guide-check).
            if isGuideOutput(path), !path.hasSuffix(".html") {
                return nil
            }
            guard Self.textExtensions.contains((path as NSString).pathExtension),
                  let data = data(path), let text = String(data: data, encoding: .utf8)
            else { return nil }
            return ("website/\(path)", text)
        }
    }

    func contentFiles() -> [(path: String, text: String)] {
        files(under: "content").compactMap { path in
            (try? String(contentsOf: repoURL("content/\(path)"), encoding: .utf8))
                .map { ("content/\(path)", $0) }
        }
    }

    mutating func fail(_ message: String) {
        failures.append(message)
    }

    mutating func run() {
        checkStale()
        checkLinks()
        checkPages()
        checkMarkup()
        checkText()
        checkSiteCSS()
        checkFonts()
        checkCredits()
        checkHeaders()
        checkRasters()
        if strict {
            checkStrict()
        }
    }

    mutating func checkStale() {
        for path in build.outputs.keys.sorted() {
            let disk = try? Data(contentsOf: siteURL(path))
            if disk != build.outputs[path] {
                fail("website/\(path) is stale; run `make site`")
            }
        }
        for copy in Spec.copies where build.outputs[copy.path] == nil && !exists(copy.path) {
            fail(
                "website/\(copy.path) is missing (source \(copy.source) not built; run `make icon`)",
            )
        }
    }

    /// Check 1: internal links, modelling Cloudflare Pages routing.
    func route(_ path: String) -> String? {
        if path == "/" {
            return "index.html"
        }
        let stem = String(path.dropFirst())
        if stem.hasSuffix("/") {
            return exists(stem + "index.html") ? stem + "index.html" : nil
        }
        return [stem + ".html", stem + "/index.html", stem].first { exists($0) }
    }

    func ids(_ file: String) -> Set<String> {
        let html = build.pages[file] ?? data(file).flatMap { String(data: $0, encoding: .utf8) }
        return Set(captures(#"\sid="([^"]+)""#, in: html ?? "").map { $0[1] })
    }

    func redirectSources() -> Set<String> {
        let text = data("_redirects").flatMap { String(data: $0, encoding: .utf8) } ?? ""
        return Set(text.split(separator: "\n")
            .compactMap { $0.split(separator: " ").first.map(String.init) })
    }

    /// Nil when `link` (seen on page `from`) resolves, else why not.
    func linkProblem(_ link: String, from page: Page) -> String? {
        let lower = link.lowercased()
        for scheme in ["https:", "http:", "mailto:", "tel:", "data:"]
            where lower.hasPrefix(scheme)
        {
            return nil
        }
        guard let base = URL(string: "https://site.invalid\(page.path)"),
              let resolved = URL(string: link, relativeTo: base)
        else { return "unparseable link" }
        let path = resolved.path.isEmpty ? "/" : resolved.path
        let fragment = resolved.fragment
        let samePage = link.hasPrefix("#")
        if !samePage, redirectSources().contains(path) {
            return nil
        }
        let targetFile = samePage ? page.file : route(path)
        guard let targetFile else { return "no page or file serves \(path)" }
        if let fragment, !fragment.isEmpty, targetFile.hasSuffix(".html"),
           !ids(targetFile).contains(fragment)
        {
            return "no id=\"\(fragment)\" on \(targetFile)"
        }
        return nil
    }

    mutating func checkLinks() {
        for page in build.pageInfo {
            let html = build.pages[page.file] ?? ""
            var links = captures(#"\s(?:href|src)="([^"]*)""#, in: html).map { $0[1] }
            for set in captures(#"\ssrcset="([^"]*)""#, in: html) {
                links += set[1].split(separator: ",").compactMap {
                    $0.split(separator: " ").first.map(String.init)
                }
            }
            for link in links {
                if let problem = linkProblem(unescapeHTML(link), from: page) {
                    fail("website/\(page.file): broken link \"\(link)\": \(problem)")
                }
            }
        }
        guard let home = build.pageInfo.first(where: { $0.path == "/" }) else {
            fail("website/index.html is missing")
            return
        }
        for link in Spec.contractLinks {
            if let problem = linkProblem(link, from: home) {
                fail("app contract link \(link) does not resolve: \(problem)")
            }
        }
        let appLinks = (try? String(contentsOf: repoURL(Spec.appLinks), encoding: .utf8)) ?? ""
        let sitePattern = "\"(" + NSRegularExpression.escapedPattern(for: build.config.origin)
            + "[^\"]*)\""
        let siteLinks = captures(sitePattern, in: appLinks).map { $0[1] }
        if siteLinks.isEmpty {
            fail("\(Spec.appLinks) names no \(build.config.origin) URL")
        }
        for url in siteLinks {
            let link = String(url.dropFirst(build.config.origin.count))
            if let problem = linkProblem(link.isEmpty ? "/" : link, from: home) {
                fail("\(Spec.appLinks) link \(url) does not resolve: \(problem)")
            }
        }
        // Guide pages: links that leave the guide (Starlight's validator covers the rest).
        for file in guidePages() {
            let html = data(file).flatMap { String(data: $0, encoding: .utf8) } ?? ""
            let page = Page(file: file, html: html)
            for link in captures(#"\shref="(/[^"]*)""#, in: html).map({ unescapeHTML($0[1]) })
                where !link.hasPrefix("/guide")
            {
                if let problem = linkProblem(link, from: page) {
                    fail("website/\(file): broken link \"\(link)\": \(problem)")
                }
            }
        }
        if guidePages().isEmpty {
            fail("website/guide is not built; run `make guide` first")
        }
        for redirect in (try? build.config.redirects()) ?? [] {
            if let problem = linkProblem(redirect.to, from: home) {
                fail("content/site.json redirect \(redirect.from) -> \(redirect.to): \(problem)")
            }
        }
        for release in build.allReleases {
            for help in release.highlights.compactMap(\.help) {
                if let problem = linkProblem(help, from: home) {
                    fail("content/changelog.json \(release.version): help \(help): \(problem)")
                }
            }
        }
    }

    /// Check 2: page basics.
    mutating func checkPages() {
        let origin = build.config.origin
        for page in build.pageInfo {
            let html = build.pages[page.file] ?? ""
            let file = "website/\(page.file)"
            let h1s = captures(#"<h1[\s>]"#, in: html).count
            if h1s != 1 {
                fail("\(file): has \(h1s) <h1> elements (needs exactly one)")
            }
            if !html.contains("<html lang=\"en\">") {
                fail("\(file): needs <html lang=\"en\">")
            }
            if page.path == "/" {
                if page.title != Spec
                    .homeTitle
                {
                    fail("\(file): title must be \"\(Spec.homeTitle)\"")
                }
            } else if page.title.count < 9 || !page.title.hasSuffix(" - Segue") {
                fail("\(file): title must follow \"Page - Segue\" (has \"\(page.title)\")")
            }
            if !(50 ... 160).contains(page.description.count) {
                fail(
                    "\(file): meta description must be 50-160 characters (has \(page.description.count))",
                )
            }
            if page.file != "404.html" {
                let canonical = captures(#"<link rel="canonical" href="([^"]*)">"#, in: html)
                    .first?[1]
                if canonical != origin + page.path {
                    fail("\(file): canonical must be \(origin + page.path)")
                }
            }
            for slot in ["partial:header", "partial:footer"]
                where !html.contains("<!--slot:\(slot)-->")
            {
                fail("\(file): missing the \(slot) slot")
            }
        }
    }

    /// Checks 3 and 6: scripts, inline handlers and styles, external assets, images.
    mutating func checkMarkup() {
        for page in build.pageInfo {
            let html = build.pages[page.file] ?? ""
            let file = "website/\(page.file)"
            for tag in captures(#"<[a-zA-Z][^>]*>"#, in: html).map({ $0[0] }) {
                let name = tag.dropFirst().prefix { $0.isLetter || $0.isNumber }.lowercased()
                if name == "script",
                   !tag.contains("type=\"application/ld+json\"") || tag.contains(" src=")
                {
                    fail("\(file): <script> is only allowed as type=\"application/ld+json\" data")
                }
                if name == "style" {
                    fail("\(file): no <style> elements (CSP style-src 'self')")
                }
                if !captures(#"\son[a-z]+\s*="#, in: tag, caseless: true).isEmpty {
                    fail("\(file): inline event handler in \(tag)")
                }
                if !captures(#"\sstyle\s*="#, in: tag, caseless: true).isEmpty {
                    fail("\(file): style= attribute in \(tag)")
                }
                checkExternal(tag, name: name, file: file)
                if name == "img" {
                    checkImage(tag, file: file)
                }
            }
        }
    }

    mutating func checkExternal(_ tag: String, name: String, file: String) {
        let external = #"\s(?:src|srcset|href)="(?:https?:)?//"#
        guard !captures(external, in: tag, caseless: true).isEmpty, name != "a" else { return }
        if name == "link", tag.contains("rel=\"canonical\"") {
            return
        }
        fail("\(file): asset loaded from another origin: \(tag)")
    }

    mutating func checkImage(_ tag: String, file: String) {
        for attribute in ["alt", "width", "height"] where !tag.contains(" \(attribute)=") {
            fail("\(file): <img> without \(attribute): \(tag)")
        }
        if !tag.contains("fetchpriority=\"high\""), !tag.contains("loading=\"lazy\"") {
            fail(
                "\(file): below-the-fold <img> needs loading=\"lazy\" (or fetchpriority=\"high\"): \(tag)",
            )
        }
    }

    /// Checks 4 and 11: no em dash in website/ or content/, no "anonymous" on the site.
    mutating func checkText() {
        let published = textFiles()
        for (path, text) in published + contentFiles() where text.contains("\u{2014}") {
            fail("\(path): contains an em dash (U+2014); use \"-\"")
        }
        let partials = contentFiles().filter { $0.path.hasPrefix("content/partials/") }
        for (path, text) in published + partials where text.lowercased().contains("anonymous") {
            fail("\(path): contains \"anonymous\" (analytics carry a hashed install identifier)")
        }
    }

    /// Check 5: every hand-written stylesheet (all of assets/css except the generated
    /// tokens.css) uses tokens only.
    mutating func checkSiteCSS() {
        let sheets = publishedFiles().filter {
            $0.hasPrefix("assets/css/") && $0.hasSuffix(".css") && $0 != "assets/css/tokens.css"
        }
        for sheet in sheets {
            guard let css = data(sheet).flatMap({ String(data: $0, encoding: .utf8) })
            else { continue }
            let literals = captures(
                #"#[0-9a-fA-F]{3,8}\b|\b(?:rgba?|hsla?|hwb|lab|lch|oklab|oklch)\("#,
                in: css,
            )
            for literal in literals {
                fail("website/\(sheet): colour literal \"\(literal[0])\"; use var(--token)")
            }
            if !captures(#"url\(\s*["']?(?:https?:)?//"#, in: css).isEmpty {
                fail("website/\(sheet): loads a url() from another origin")
            }
        }
    }

    /// Check 7: fonts.lock.json matches the TTFs and the committed WOFF2 files.
    mutating func checkFonts() {
        let lockPath = "content/fonts.lock.json"
        guard let data = try? Data(contentsOf: repoURL(lockPath)),
              let lock = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let fonts = lock["fonts"] as? [[String: Any]]
        else {
            fail("\(lockPath): missing or unreadable; run `make site-fonts`")
            return
        }
        var listed = Set<String>()
        for font in fonts {
            for (pathKey, hashKey) in [("source", "sourceSha256"), ("output", "outputSha256")] {
                let path = font[pathKey] as? String ?? ""
                if pathKey == "output" {
                    listed.insert(path)
                }
                let actual = (try? Data(contentsOf: repoURL(path))).map(sha256)
                if actual == nil || actual != font[hashKey] as? String {
                    fail("\(lockPath): \(path) does not match its hash; run `make site-fonts`")
                }
            }
        }
        let fontFiles = publishedFiles().filter { $0.hasSuffix(".woff2") }.map { "website/\($0)" }
        for file in fontFiles where !listed.contains(file) {
            fail("\(file): not listed in \(lockPath)")
        }
        if !exists("assets/fonts/OFL.txt") {
            fail("website/assets/fonts/OFL.txt is missing")
        }
    }

    /// Check 8: every credit is also in the notices the app bundle ships, and its licence
    /// text exists.
    mutating func checkCredits() {
        let notices = (try? String(contentsOf: repoURL(Spec.thirdPartyNotices), encoding: .utf8))
            ?? ""
        for credit in build.config.credits {
            let name = credit["name"] ?? ""
            if !notices.contains(name) {
                fail("content/site.json credit \"\(name)\" is not in \(Spec.thirdPartyNotices)")
            }
            let licence = credit["licenceFile"] ?? ""
            if !FileManager.default.fileExists(atPath: repoURL(licence).path) {
                fail("content/site.json credit \"\(name)\": licenceFile \(licence) is missing")
            }
        }
    }

    /// Check 9: _headers carries exactly the section 9.3 CSP.
    mutating func checkHeaders() {
        guard let text = data("_headers").flatMap({ String(data: $0, encoding: .utf8) }) else {
            fail("website/_headers is missing")
            return
        }
        let lines = text.split(separator: "\n").map { $0.trimmingCharacters(in: .whitespaces) }
        let csp = lines.filter { $0.hasPrefix("Content-Security-Policy:") }
        if csp != [Spec.csp, Spec.guideCSP, Spec.guideCSP] {
            fail(
                "website/_headers: the Content-Security-Policy lines must be exactly:\n"
                    + "    \(Spec.csp)\n"
                    + "  and, under /guide and /guide/* after \"! Content-Security-Policy\":\n"
                    + "    \(Spec.guideCSP)",
            )
        }
        for rule in ["/guide", "/guide/*"] {
            let next = lines.firstIndex(of: rule).flatMap { lines.dropFirst($0 + 1).first }
            if next != "! Content-Security-Policy" {
                fail(
                    "website/_headers: a \(rule) rule must start with \"! Content-Security-Policy\"",
                )
            }
        }
    }

    mutating func checkRasters() {
        for raster in Spec.rasters {
            guard exists(raster.path) else {
                if strict {
                    fail("website/\(raster.path) is missing; run `make site-raster`")
                }
                continue
            }
            let size = pixelSize(siteURL(raster.path))
            if size?.0 != raster.width || size?.1 != raster.height {
                fail("website/\(raster.path) must be \(raster.width)x\(raster.height) px")
            }
        }
    }

    mutating func checkStrict() {
        let live = build.config.isLive
        for leaf in build.config.leaves() where isPlaceholder(leaf.value) {
            if !live, leaf.path.hasPrefix("appStore.") {
                continue
            }
            fail("content/site.json \(leaf.path): placeholder \(leaf.value) (--strict)")
        }
        for (path, text) in textFiles() {
            for match in Set(captures(placeholderPattern, in: text).map { $0[0] }).sorted() {
                fail("\(path): placeholder \(match) (--strict)")
            }
            if text.contains("<!--ryan-edit-->") || text.contains("<!--/ryan-edit-->") {
                fail("\(path): ryan-edit marker; rewrite the maker note and delete the markers")
            }
        }
        guard live else { return }
        if !exists(Spec.appleBadge) {
            fail("website/\(Spec.appleBadge) is missing (status is live)")
        }
        if !publishedFiles()
            .contains(where: { $0.hasPrefix("assets/img/screens/") && $0.hasSuffix(".jpg") })
        {
            fail("website/assets/img/screens/ has no screenshots (status is live)")
        }
        if !build.allReleases.contains(where: { !$0.draft }) {
            fail("content/changelog.json has no published release (status is live)")
        }
    }
}

func pixelSize(_ url: URL) -> (Int, Int)? {
    guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
          let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
          let width = properties[kCGImagePropertyPixelWidth] as? Int,
          let height = properties[kCGImagePropertyPixelHeight] as? Int
    else { return nil }
    return (width, height)
}

// MARK: - Rasters (--raster)

struct Palette {
    let tokens: [String: (light: String, dark: String)]

    init() throws {
        let data = try Data(contentsOf: repoURL("design/tokens.json"))
        let root = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        var tokens: [String: (String, String)] = [:]
        for token in root?["color"] as? [[String: String]] ?? [] {
            if let name = token["name"], let light = token["light"], let dark = token["dark"] {
                tokens[name] = (light, dark)
            }
        }
        self.tokens = tokens
    }

    func color(_ name: String, dark: Bool) throws -> CGColor {
        guard let pair = tokens[name] else { throw SiteError.raster("no colour token \(name)") }
        let hex = dark ? pair.dark : pair.light
        guard let value = UInt32(hex.dropFirst(), radix: 16) else {
            throw SiteError.raster("bad hex \(hex)")
        }
        return CGColor(
            srgbRed: CGFloat(value >> 16 & 0xFF) / 255, green: CGFloat(value >> 8 & 0xFF) / 255,
            blue: CGFloat(value & 0xFF) / 255, alpha: 1,
        )
    }
}

func registerFonts() throws {
    for style in ["Regular", "SemiBold", "Bold", "ExtraBold"] {
        let url = repoURL("\(Spec.fontSources)/SchibstedGrotesk-\(style).ttf") as CFURL
        var error: Unmanaged<CFError>?
        if !CTFontManagerRegisterFontsForURL(url, .process, &error) {
            let reason = error?.takeRetainedValue().localizedDescription ?? "unknown error"
            if !reason.contains("already registered") {
                throw SiteError.raster("could not register \(style): \(reason)")
            }
        }
    }
}

func font(_ style: String, _ size: CGFloat) throws -> CTFont {
    let font = CTFontCreateWithName("SchibstedGrotesk-\(style)" as CFString, size, nil)
    guard (CTFontCopyPostScriptName(font) as String) == "SchibstedGrotesk-\(style)" else {
        throw SiteError.raster("font SchibstedGrotesk-\(style) is not available")
    }
    return font
}

/// Draws one line with its baseline at `y`; returns its advance width.
@discardableResult
func drawText(
    _ text: String, font: CTFont, color: CGColor, tracking: CGFloat = 0, x: CGFloat, y: CGFloat,
    in context: CGContext,
) -> CGFloat {
    let attributes: [NSAttributedString.Key: Any] = [
        NSAttributedString.Key(kCTFontAttributeName as String): font,
        NSAttributedString.Key(kCTForegroundColorAttributeName as String): color,
        NSAttributedString.Key(kCTKernAttributeName as String): tracking * CTFontGetSize(font),
    ]
    let line = CTLineCreateWithAttributedString(NSAttributedString(
        string: text,
        attributes: attributes,
    ))
    context.textPosition = CGPoint(x: x, y: y)
    CTLineDraw(line, context)
    return CGFloat(CTLineGetTypographicBounds(line, nil, nil, nil))
}

/// The wordmark (docs/brand.md section 3): "Segue" in 800 at -0.045em, then the cue dot,
/// 0.22em across, top-aligned with the cap height. Returns the total width.
@discardableResult
func drawWordmark(
    size: CGFloat, x: CGFloat, baseline: CGFloat, word: CGColor, dot: CGColor,
    in context: CGContext,
) throws -> CGFloat {
    let face = try font("ExtraBold", size)
    let width = drawText(
        "Segue",
        font: face,
        color: word,
        tracking: -0.045,
        x: x,
        y: baseline,
        in: context,
    )
    let diameter = size * 0.22
    let dotX = x + width + size * 0.06
    let top = baseline + CTFontGetCapHeight(face)
    context.setFillColor(dot)
    context.fillEllipse(in: CGRect(x: dotX, y: top - diameter, width: diameter, height: diameter))
    return dotX + diameter - x
}

func measureWordmark(size: CGFloat) throws -> CGFloat {
    let face = try font("ExtraBold", size)
    let attributes: [NSAttributedString.Key: Any] = [
        NSAttributedString.Key(kCTFontAttributeName as String): face,
        NSAttributedString.Key(kCTKernAttributeName as String): -0.045 * size,
    ]
    let line = CTLineCreateWithAttributedString(NSAttributedString(
        string: "Segue",
        attributes: attributes,
    ))
    return CGFloat(CTLineGetTypographicBounds(line, nil, nil, nil)) + size * 0.28
}

func bitmapContext(width: Int, height: Int) throws -> CGContext {
    guard let space = CGColorSpace(name: CGColorSpace.sRGB),
          let context = CGContext(
              data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
              space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue,
          )
    else { throw SiteError.raster("could not create a \(width)x\(height) context") }
    return context
}

func drawSVG(_ path: String, in rect: CGRect, context: CGContext) throws {
    guard let image = NSImage(contentsOf: repoURL(path)) else {
        throw SiteError.raster("AppKit could not load \(path)")
    }
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: false)
    image.draw(in: rect)
    NSGraphicsContext.restoreGraphicsState()
}

func writeImage(_ context: CGContext, to path: String, type: CFString, quality: Double = 1) throws {
    guard let image = context.makeImage(),
          let destination = CGImageDestinationCreateWithURL(siteURL(path) as CFURL, type, 1, nil)
    else { throw SiteError.raster("could not encode \(path)") }
    try fileManager.createDirectory(
        at: siteURL(path).deletingLastPathComponent(), withIntermediateDirectories: true,
    )
    let options = [kCGImageDestinationLossyCompressionQuality: quality] as CFDictionary
    CGImageDestinationAddImage(destination, image, options)
    guard CGImageDestinationFinalize(destination) else {
        throw SiteError.raster("could not write \(path)")
    }
    print("gen-site: rendered website/\(path)")
}

func textWidth(_ text: String, font: CTFont, tracking: CGFloat = 0) -> CGFloat {
    let attributes: [NSAttributedString.Key: Any] = [
        NSAttributedString.Key(kCTFontAttributeName as String): font,
        NSAttributedString.Key(kCTKernAttributeName as String): tracking * CTFontGetSize(font),
    ]
    let line = CTLineCreateWithAttributedString(
        NSAttributedString(string: text, attributes: attributes),
    )
    return CGFloat(CTLineGetTypographicBounds(line, nil, nil, nil))
}

/// Splits `text` into two lines of as-equal-as-possible width.
func balancedLines(_ text: String, font: CTFont, tracking: CGFloat) -> [String] {
    let words = text.split(separator: " ").map(String.init)
    guard words.count > 1 else { return [text] }
    let splits = (1 ..< words.count).map { index in
        [words[..<index].joined(separator: " "), words[index...].joined(separator: " ")]
    }
    return splits.min { lhs, rhs in
        let left = lhs.map { textWidth($0, font: font, tracking: tracking) }.max() ?? 0
        let right = rhs.map { textWidth($0, font: font, tracking: tracking) }.max() ?? 0
        return left < right
    } ?? [text]
}

/// The Open Graph card, in the site's Stage direction: centred eyebrow, the tagline as a
/// big tight headline, and the wordmark at the foot.
func renderOpenGraph(_ palette: Palette, tagline: String) throws {
    let (width, height): (CGFloat, CGFloat) = (1200, 630)
    let context = try bitmapContext(width: Int(width), height: Int(height))
    let ink = try palette.color("ink", dark: true)
    let muted = try palette.color("muted", dark: true)
    let cue = try palette.color("cue", dark: true)
    try context.setFillColor(palette.color("ground", dark: true))
    context.fill(CGRect(x: 0, y: 0, width: width, height: height))

    let eyebrowFont = try font("SemiBold", 30)
    let eyebrow = "Segue for Mac"
    let eyebrowWidth = textWidth(eyebrow, font: eyebrowFont) + 22
    let eyebrowX = (width - eyebrowWidth) / 2
    context.setFillColor(cue)
    context.fillEllipse(in: CGRect(x: eyebrowX, y: 488, width: 12, height: 12))
    drawText(eyebrow, font: eyebrowFont, color: muted, x: eyebrowX + 22, y: 484, in: context)

    let headline = try font("ExtraBold", 104)
    let lines = balancedLines(tagline, font: headline, tracking: -0.045)
    for (index, line) in lines.enumerated() {
        let lineWidth = textWidth(line, font: headline, tracking: -0.045)
        drawText(
            line, font: headline, color: ink, tracking: -0.045, x: (width - lineWidth) / 2,
            y: 370 - CGFloat(index) * 104, in: context,
        )
    }

    let markSize: CGFloat = 40
    let markWidth = try measureWordmark(size: markSize)
    try drawWordmark(
        size: markSize, x: (width - markWidth) / 2, baseline: 64, word: ink, dot: cue,
        in: context,
    )
    try writeImage(context, to: "assets/img/og.png", type: "public.png" as CFString)
}

func renderIcons(_ palette: Palette) throws {
    let touch = try bitmapContext(width: 180, height: 180)
    // iOS masks the touch icon itself, so fill the corners with the icon's own ground.
    try touch.setFillColor(palette.color("ink", dark: false))
    touch.fill(CGRect(x: 0, y: 0, width: 180, height: 180))
    try drawSVG(
        "design/icon/master.svg",
        in: CGRect(x: 0, y: 0, width: 180, height: 180),
        context: touch,
    )
    try writeImage(touch, to: "apple-touch-icon.png", type: "public.png" as CFString)

    let favicon = try bitmapContext(width: 32, height: 32)
    try drawSVG(
        "design/icon/icon-32.svg",
        in: CGRect(x: 0, y: 0, width: 32, height: 32),
        context: favicon,
    )
    try writeImage(favicon, to: "favicon-32.png", type: "public.png" as CFString)
}

func renderWordmarks(_ palette: Palette) throws {
    for (name, dark) in [("dark", true), ("light", false)] {
        let context = try bitmapContext(width: 640, height: 256)
        let size: CGFloat = 128
        let width = try measureWordmark(size: size)
        let face = try font("ExtraBold", size)
        let baseline = (256 - CTFontGetCapHeight(face)) / 2
        try drawWordmark(
            size: size, x: (640 - width) / 2, baseline: baseline,
            word: palette.color("ink", dark: dark), dot: palette.color("cue", dark: dark),
            in: context,
        )
        try writeImage(
            context,
            to: "assets/img/wordmark-\(name).png",
            type: "public.png" as CFString,
        )
    }
}

/// Screenshot JPEGs at 1280 and 2560 px wide from the R10 raw captures (section 8.5).
func renderScreenshots() throws {
    let source = repoURL(Spec.screenshotSource)
    let files = (try? fileManager.contentsOfDirectory(at: source, includingPropertiesForKeys: nil))?
        .filter { $0.pathExtension == "png" }.sorted { $0.path < $1.path } ?? []
    guard !files.isEmpty else {
        print(
            "gen-site: no screenshots in \(Spec.screenshotSource) yet; sections render without art",
        )
        return
    }
    for file in files {
        guard let image = CGImageSourceCreateWithURL(file as CFURL, nil)
            .flatMap({ CGImageSourceCreateImageAtIndex($0, 0, nil) }), image.width == 2880
        else { continue }
        let stem = file.deletingPathExtension().lastPathComponent.lowercased()
        for width in [1280, 2560] {
            let height = image.height * width / image.width
            let context = try bitmapContext(width: width, height: height)
            context.interpolationQuality = .high
            context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
            try writeImage(
                context, to: "assets/img/screens/\(stem)-\(width).jpg",
                type: "public.jpeg" as CFString,
                quality: 0.85,
            )
        }
    }
}

func renderRasters(_ config: Config) throws {
    try registerFonts()
    let palette = try Palette()
    try renderOpenGraph(palette, tagline: config.string("site.tagline"))
    try renderIcons(palette)
    try renderWordmarks(palette)
    try renderScreenshots()
}

// MARK: - External links (--check-external)

final class StatusBox: @unchecked Sendable {
    var result = ""
}

func externalStatus(_ link: String) -> String {
    guard let url = URL(string: link) else { return "unparseable" }
    var request = URLRequest(url: url, timeoutInterval: 30)
    request.setValue(
        "Mozilla/5.0 (Macintosh) segue-site-link-check",
        forHTTPHeaderField: "User-Agent",
    )
    let box = StatusBox()
    let done = DispatchSemaphore(value: 0)
    URLSession.shared.dataTask(with: request) { _, response, error in
        if let status = (response as? HTTPURLResponse)?.statusCode {
            box.result = (200 ..< 400).contains(status) ? "" : "HTTP \(status)"
        } else {
            box.result = error?.localizedDescription ?? "no response"
        }
        done.signal()
    }.resume()
    done.wait()
    return box.result
}

func checkExternalLinks(_ build: Build) -> Int32 {
    var links = Set<String>()
    for html in build.pages.values {
        for match in captures(#"\shref="(https://[^"]+)""#, in: html) {
            links.insert(unescapeHTML(match[1]).components(separatedBy: "#")[0])
        }
    }
    links.remove(build.config.origin)
    let origin = build.config.origin + "/"
    var failures = 0
    for link in links.sorted() where !link.hasPrefix(origin) {
        if isPlaceholder(link) {
            print("SKIP \(link) (placeholder)")
            continue
        }
        let problem = externalStatus(link)
        print(problem.isEmpty ? "ok   \(link)" : "FAIL \(link): \(problem)")
        if !problem.isEmpty {
            failures += 1
        }
    }
    return failures == 0 ? 0 : 1
}

// MARK: - Main

func writeOutputs(_ build: Build) throws -> Int {
    var written = 0
    for (path, data) in build.outputs.sorted(by: { $0.key < $1.key }) {
        let url = siteURL(path)
        if (try? Data(contentsOf: url)) == data {
            continue
        }
        try fileManager.createDirectory(
            at: url.deletingLastPathComponent(), withIntermediateDirectories: true,
        )
        try data.write(to: url, options: .atomic)
        written += 1
    }
    return written
}

let arguments = Set(CommandLine.arguments.dropFirst())
let known: Set = ["--check", "--strict", "--raster", "--check-external"]
do {
    if let unknown = arguments.subtracting(known).first {
        throw SiteError.config("unknown option \(unknown)")
    }
    if arguments.contains("--strict"), !arguments.contains("--check") {
        throw SiteError.config("--strict only works with --check")
    }
    if arguments.contains("--raster") {
        try renderRasters(loadConfig())
        exit(0)
    }
    let site = try build()
    if arguments.contains("--check-external") {
        exit(checkExternalLinks(site))
    }
    if arguments.contains("--check") {
        var checker = Checker(build: site, strict: arguments.contains("--strict"))
        checker.run()
        guard checker.failures.isEmpty else {
            let list = checker.failures.map { "  \($0)" }.joined(separator: "\n")
            FileHandle.standardError.write(Data("error: site check failed:\n\(list)\n".utf8))
            exit(1)
        }
        let mode = arguments.contains("--strict") ? " (strict)" : ""
        print(
            "gen-site: up to date and valid\(mode) (\(site.outputs.count) generated files, \(site.pages.count) pages)",
        )
    } else {
        let written = try writeOutputs(site)
        print("gen-site: wrote \(written) of \(site.outputs.count) files")
    }
} catch {
    FileHandle.standardError.write(Data("error: gen-site: \(error)\n".utf8))
    exit(1)
}
