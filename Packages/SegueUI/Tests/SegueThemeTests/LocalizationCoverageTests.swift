import Foundation
@testable import SegueUI
import Testing

/// P9-5 section 4 (R179): SegueUI's String Catalog. v1.0 is English only, so every key's
/// English text is the key itself and the app reads exactly as before the catalogs; song
/// content (titles, lyrics, chords, section labels, romanized Hindi) is never a key.
/// `make strings-check` proves the catalog holds every string the code uses.
struct LocalizationCoverageTests {
    private static func catalog() throws -> [String: Any] {
        let url = URL(filePath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appending(path: "Sources/SegueUI/Localizable.xcstrings")
        let object = try JSONSerialization.jsonObject(with: Data(contentsOf: url))
        let root = try #require(object as? [String: Any])
        #expect(root["sourceLanguage"] as? String == "en")
        return try #require(root["strings"] as? [String: Any])
    }

    @Test
    func `the catalog holds the app's strings, English only, and English is the key`() throws {
        let strings = try Self.catalog()
        #expect(strings.count > 900)
        for (key, value) in strings {
            let entry = try #require(value as? [String: Any], "\(key)")
            let languages = (entry["localizations"] as? [String: Any])?.keys.sorted() ?? []
            #expect(languages.allSatisfy { $0 == "en" }, "\(key): \(languages)")
        }
        for key in ["Start Show", "Report…", "New song", "Segue Help", "Move to Trash"] {
            #expect(strings[key] != nil, "\(key) is not in the catalog")
            #expect(uiString(String.LocalizationValue(key)) == key, "\(key) reads differently")
        }
    }

    @Test
    func `no song content is a catalog key`() throws {
        let keys = try Set(Self.catalog().keys)
        let welcome = try #require(Bundle.module.url(
            forResource: "WelcomeLibrary",
            withExtension: nil,
        ))
        let songs = try FileManager.default.contentsOfDirectory(
            at: welcome,
            includingPropertiesForKeys: nil,
        ).filter { $0.pathExtension == "cho" }
        #expect(!songs.isEmpty)
        for song in songs {
            let source = try String(contentsOf: song, encoding: .utf8)
            for line in source.split(separator: "\n") {
                // Lyric text without chords, and directive values (title, artist, labels).
                let words = line.replacing(/\[[^\]]*\]/, with: "")
                    .replacing(/^\{[a-z_]+:?\s*/, with: "").replacing(/\}$/, with: "")
                    .trimmingCharacters(in: .whitespaces)
                guard words.count > 3 else { continue }
                #expect(!keys.contains(words), "song text “\(words)” is a catalog key")
            }
        }
        // Section labels are written into song files exactly as shown (P9-5 4.2).
        for label in ["Verse", "Chorus", "Bridge", "Intro", "Outro", "Pre-Chorus"] {
            #expect(!keys.contains(label), "the section label \(label) is a catalog key")
        }
    }
}
