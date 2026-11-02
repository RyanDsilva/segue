#!/usr/bin/env swift
// The store-text gate (docs/release/specs/WS5-store-listing.md 3 and 11): checks store/ the
// way App Store Connect and the listing rules would, so a bad field fails `make store-check`
// (part of `make check`) instead of an upload or a review.
//
//   scripts/check-store-metadata.swift [<store dir>]     default: store
//
// Fails on: a missing or empty field file; name or subtitle over 30 characters; promotional
// text over 170; description over 4,000; keywords over 100 bytes, a term of 2 characters or
// fewer, a term repeating a word of the name or subtitle, a space next to a comma or an empty
// term; review notes over 4,000 bytes or naming "Report a Bug" (the item is "Report a
// Problem...", I-5); an em or en dash anywhere; a banned word (competitor names from
// research/04 section 5, other platforms, beta wording, "collects no data"); a screenshot
// headline over 40 or subline over 64 characters, or more than 10 shots; the copyright not
// the R30 name; a URL that is not https on segue.ryandsilva.dev; any locale but en-US (A46).
// Counts ignore one trailing newline per file (deliver trims it).
import Foundation

let root = URL(fileURLWithPath: CommandLine.arguments.dropFirst().first ?? "store")
let metadata = root.appending(path: "metadata")
var failures: [String] = []

func fail(_ message: String) {
    failures.append(message)
}

/// The file's text without trailing whitespace and newlines, or nil (and a failure) if it is
/// missing or empty.
func field(_ path: String) -> String? {
    let url = metadata.appending(path: path)
    guard let text = try? String(contentsOf: url, encoding: .utf8) else {
        fail("\(path): missing")
        return nil
    }
    let trimmed = text.replacingOccurrences(of: #"\s+$"#, with: "", options: .regularExpression)
    if trimmed.isEmpty {
        fail("\(path): empty")
        return nil
    }
    return trimmed
}

func limit(_ path: String, _ text: String?, characters max: Int) {
    guard let text else { return }
    if text.count > max {
        fail("\(path): \(text.count) characters, over \(max)")
    }
}

func limit(_ path: String, _ text: String?, bytes max: Int) {
    guard let text else { return }
    let count = text.utf8.count
    if count > max {
        fail("\(path): \(count) bytes, over \(max)")
    }
}

/// Competitors (research/04-store-listing.md 5.1 and 5.2), other platforms and beta wording,
/// matched case-insensitively as whole words.
let banned = [
    "OnSong", "SongbookPro", "BandHelper", "Set List Maker", "SongSheet", "forScore",
    "MobileSheets", "Planning Center", "LinkeSOFT", "LivePrompter", "WorshipTools", "iReal",
    "Chordify", "Ultimate Guitar", "Leganote", "Songbook Buddy", "GigNotes", "LeadSheets",
    "SongDeck", "Setlister", "SUS4", "Bandfix", "Songbookly", "QMe", "Gig Hard",
    "Setlist Helper", "iPhone", "iPad", "Android", "Windows", "beta", "collects no data",
]

func screen(_ path: String, _ text: String?) {
    guard let text else { return }
    if text.contains("\u{2014}") || text.contains("\u{2013}") {
        fail("\(path): em or en dash (use \"-\")")
    }
    for word in banned {
        let pattern = "(?i)(?<![A-Za-z0-9])" + NSRegularExpression.escapedPattern(for: word)
            + "(?![A-Za-z0-9])"
        if text.range(of: pattern, options: .regularExpression) != nil {
            fail("\(path): banned word \"\(word)\"")
        }
    }
}

// Locales: en-US only (A46).
let locales = (try? FileManager.default.contentsOfDirectory(atPath: metadata.path)) ?? []
for entry in locales where entry != "en-US" && entry != "review_information" {
    var isDirectory: ObjCBool = false
    let path = metadata.appending(path: entry).path
    if FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory),
       isDirectory.boolValue
    {
        fail("metadata/\(entry): only en-US is listed (A46)")
    }
}

let name = field("en-US/name.txt")
let subtitle = field("en-US/subtitle.txt")
let promo = field("en-US/promotional_text.txt")
let description = field("en-US/description.txt")
let keywords = field("en-US/keywords.txt")
limit("en-US/name.txt", name, characters: 30)
limit("en-US/subtitle.txt", subtitle, characters: 30)
limit("en-US/promotional_text.txt", promo, characters: 170)
limit("en-US/description.txt", description, characters: 4000)
limit("en-US/keywords.txt", keywords, bytes: 100)
for (path, text) in [
    ("en-US/name.txt", name), ("en-US/subtitle.txt", subtitle),
    ("en-US/promotional_text.txt", promo), ("en-US/description.txt", description),
    ("en-US/keywords.txt", keywords),
] {
    screen(path, text)
}

if let keywords {
    if keywords.contains(", ") || keywords.contains(" ,") {
        fail("en-US/keywords.txt: a space next to a comma wastes a byte")
    }
    let taken = Set(
        "\(name ?? "") \(subtitle ?? "")".lowercased()
            .split(whereSeparator: { !$0.isLetter && !$0.isNumber }).map(String.init),
    )
    for term in keywords.split(separator: ",", omittingEmptySubsequences: false) {
        let term = term.trimmingCharacters(in: .whitespaces).lowercased()
        if term.isEmpty {
            fail("en-US/keywords.txt: empty term")
        } else if term.count <= 2 {
            fail("en-US/keywords.txt: \"\(term)\" is 2 characters or fewer (Apple ignores it)")
        } else if taken.contains(term) {
            fail("en-US/keywords.txt: \"\(term)\" repeats the name or subtitle")
        }
    }
}

for path in ["en-US/support_url.txt", "en-US/marketing_url.txt", "en-US/privacy_url.txt"] {
    if let url = field(path), !url.hasPrefix("https://segue.ryandsilva.dev") {
        fail("\(path): \(url) is not on https://segue.ryandsilva.dev")
    }
}

if let copyright = field("copyright.txt"), copyright != "2026 Ryan Rony Dsilva" {
    fail("copyright.txt: \"\(copyright)\" is not \"2026 Ryan Rony Dsilva\" (R30)")
}

if let primary = field("primary_category.txt"), primary != "MUSIC" {
    fail("primary_category.txt: \(primary), expected MUSIC (R3)")
}

if let secondary = field("secondary_category.txt"), secondary != "PRODUCTIVITY" {
    fail("secondary_category.txt: \(secondary), expected PRODUCTIVITY (R3)")
}

for path in ["first_name", "last_name", "email_address"] {
    screen("review_information/\(path).txt", field("review_information/\(path).txt"))
}

let notes = field("review_information/notes.txt")
limit("review_information/notes.txt", notes, bytes: 4000)
screen("review_information/notes.txt", notes)
if let notes, notes.range(of: "Report a Bug", options: .caseInsensitive) != nil {
    fail("review_information/notes.txt: the Help item is \"Report a Problem...\" (I-5)")
}

if FileManager.default.fileExists(
    atPath: metadata.appending(path: "review_information/phone_number.txt").path,
) {
    fail("review_information/phone_number.txt: the phone comes from SEGUE_REVIEW_PHONE only")
}

/// Screenshot captions (WS5 8.4): headline <= 40, subline <= 64, 1-10 shots per locale.
let captionsURL = root.appending(path: "screenshots.json")
if let data = try? Data(contentsOf: captionsURL),
   let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
   let byLocale = json["locales"] as? [String: [[String: Any]]]
{
    for (locale, shots) in byLocale {
        if locale != "en-US" {
            fail("screenshots.json: locale \(locale), only en-US (A46)")
        }
        if !(1 ... 10).contains(shots.count) {
            fail("screenshots.json \(locale): \(shots.count) shots (1-10)")
        }
        for shot in shots {
            let id = shot["id"] as? String ?? "?"
            for (key, max) in [("headline", 40), ("subline", 64)] {
                let text = shot[key] as? String
                limit("screenshots.json \(id) \(key)", text, characters: max)
                screen("screenshots.json \(id) \(key)", text)
            }
        }
    }
} else {
    fail("screenshots.json: missing or not the expected shape")
}

if failures.isEmpty {
    print(
        "store-check: ok (name \(name?.count ?? 0)/30, subtitle \(subtitle?.count ?? 0)/30, "
            + "promo \(promo?.count ?? 0)/170, description \(description?.count ?? 0)/4000, "
            + "keywords \(keywords?.utf8.count ?? 0)/100 bytes, "
            + "notes \(notes?.utf8.count ?? 0)/4000 bytes)",
    )
} else {
    for failure in failures {
        FileHandle.standardError.write(Data("store-check: \(failure)\n".utf8))
    }
    exit(1)
}
