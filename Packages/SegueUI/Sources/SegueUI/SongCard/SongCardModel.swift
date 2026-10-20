import ChordPro
import Editing
import Foundation
import Library
import MusicTheory

// The song card (R80, spec 16.0.1; design: direction 2 "Tokens", Ryan's pick 2026-10-19):
// what it shows, how it writes, and the focus seams siblings use. Every field writes
// standard ChordPro through one `EditOperation` (one undo step) or the sidecar.

/// A field of the song card, for focus requests (`focus(.title)` from Start blank,
/// `focus(.length)` from the missing-lengths list).
public enum SongCardField: String, Sendable, Hashable, CaseIterable {
    case title
    case artist
    case key
    case tempo
    case length
    case capo
    case time
}

/// The song card's values, read from a parsed song.
struct SongCardValues: Equatable {
    var title: String
    var artist: String
    /// `{key}` as written (nil when absent).
    var key: String?
    var tempo: Double?
    var length: TimeInterval?
    var capo: Int
    var time: String?
    /// The key `KeyDetector` hears in the chords, offered as a suggestion only.
    var detectedKey: SongKey?

    init(document: SongDocument) {
        let metadata = document.metadata
        title = metadata.title ?? ""
        artist = metadata.artists.first ?? ""
        key = metadata.key
        tempo = metadata.tempo
        length = metadata.duration
        capo = metadata.capo ?? 0
        time = metadata.time
        detectedKey = document.detectedKey
        missing = SongEssentials.missing(in: document)
    }

    var missing: [SetEssential]

    /// "84" (a whole tempo without decimals).
    var tempoText: String? {
        tempo.map(Self.tempoText)
    }

    static func tempoText(_ tempo: Double) -> String {
        tempo.rounded() == tempo ? String(Int(tempo)) : String(tempo)
    }
}

/// Validated writes: each returns the one operation for a committed value, or a message
/// when the value must not reach the file. Clearing removes the directive.
enum SongCardWrite {
    static func title(_ text: String) -> EditOperation {
        .setDirective(name: "title", value: cleaned(text))
    }

    static func artist(_ text: String) -> EditOperation {
        .setDirective(name: "artist", value: cleaned(text))
    }

    static func key(_ key: SongKey?) -> EditOperation {
        .setDirective(name: "key", value: key?.name)
    }

    static func capo(_ capo: Int) -> EditOperation {
        let value = min(max(capo, 0), 11)
        return .setDirective(name: "capo", value: value == 0 ? nil : String(value))
    }

    /// A tempo in BPM: a positive number up to 400 (nil or blank clears).
    static func tempo(_ text: String) -> Result<EditOperation, Problem> {
        guard let value = cleaned(text) else {
            return .success(.setDirective(name: "tempo", value: nil))
        }
        guard let tempo = Metadata.parseTempo(value), tempo <= 400 else {
            return .failure(Problem("Enter beats per minute, like 96"))
        }
        let rounded = (tempo * 10).rounded() / 10
        return .success(.setDirective(name: "tempo", value: SongCardValues.tempoText(rounded)))
    }

    /// A time signature `n/d` (blank clears).
    static func time(_ text: String) -> Result<EditOperation, Problem> {
        guard let value = cleaned(text) else {
            return .success(.setDirective(name: "time", value: nil))
        }
        guard let (beats, noteValue) = Metadata.parseTime(value) else {
            return .failure(Problem("Enter a time signature like 4/4, 3/4 or 6/8"))
        }
        return .success(.setDirective(name: "time", value: "\(beats)/\(noteValue)"))
    }

    struct Problem: Error, Equatable {
        let message: String

        init(_ message: String) {
            self.message = message
        }
    }

    private static func cleaned(_ text: String) -> String? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "}", with: "")
            .replacingOccurrences(of: "\n", with: " ")
        return trimmed.isEmpty ? nil : trimmed
    }
}
