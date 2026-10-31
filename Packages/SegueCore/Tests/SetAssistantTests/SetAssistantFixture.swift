import Diagrams
import Foundation
import Library
import MusicTheory
@testable import SetAssistant
import Setlists
import Support

/// The seeded 300-song fixture library (P3-7 tests): tags, proficiency, keys, capo, tunings,
/// tempo (some songs without one, so with no time), a bar count, and play history. A song's
/// time is its tempo times its bars (one bar per chord in 4/4, `SlotTimes`). Deterministic: the
/// same
/// seed gives the same library.
struct AssistantFixture {
    static let tags = [
        "upbeat", "ballad", "crowd pleaser", "singalong", "original", "cover", "hindi",
        "wedding", "rock", "acoustic",
    ]
    static let keys = [
        "C", "G", "D", "A", "E", "F", "Bb", "Eb", "Am", "Em", "Bm", "Dm", "F#m", "Gm", "Cm",
    ]
    static let now = Date(timeIntervalSince1970: 1_790_000_000)

    struct Song {
        var id: SongID
        var title: String
        var tags: [String]
        var proficiency: Proficiency?
        var key: String?
        var capo: Int
        var dropD: Bool
        var tempo: Int?
        /// Chords, one bar each.
        var bars: Int
        var lastPlayedDaysAgo: Int?

        var source: String {
            var lines = ["{title: \(title)}"]
            if let key {
                lines.append("{key: \(key)}")
            }
            if capo > 0 {
                lines.append("{capo: \(capo)}")
            }
            if let tempo {
                lines.append("{tempo: \(tempo)}")
            }
            let chords = (0 ..< bars).map { $0.isMultiple(of: 2) ? "[C]la" : "[G]la" }
            lines += [
                "",
                "{start_of_verse: Verse 1}",
                chords.joined(separator: " "),
                "{end_of_verse}",
                "",
            ]
            return lines.joined(separator: "\n")
        }

        /// Tempo x bars; nil without a tempo.
        var seconds: TimeInterval? {
            tempo.map { Double(bars) * 240 / Double($0) }
        }

        var assistantSong: AssistantSong {
            AssistantSong(
                id: id,
                title: title,
                tags: tags,
                proficiency: proficiency,
                key: key.flatMap(SongKey.init(parsing:)),
                capo: capo,
                tuning: dropD ? [38, 45, 50, 55, 59, 64] : Tuning.standard.strings,
                tempo: tempo.map(Double.init),
                time: seconds.map { .known(seconds: $0, bars: bars, tempo: 0, estimated: true) }
                    ?? .unknown(.noTempo),
                lastPlayed: lastPlayedDaysAgo.map {
                    AssistantFixture.now.addingTimeInterval(-Double($0) * 86400)
                },
            )
        }
    }

    let songs: [Song]

    init(count: Int = 300, seed: UInt64 = 7) {
        var random = SplitMix64(seed: seed)
        func roll(_ upper: Int) -> Int {
            Int(random.next() % UInt64(upper))
        }
        let ids = ULIDGenerator(clock: ManualClock(), seed: seed)
        songs = (0 ..< count).map { index in
            var tags: [String] = []
            for _ in 0 ..< roll(4) {
                let tag = Self.tags[roll(Self.tags.count)]
                if !tags.contains(tag) {
                    tags.append(tag)
                }
            }
            let level = roll(20)
            let proficiency: Proficiency? = switch level {
            case 0 ..< 3: .learning
            case 3 ..< 12: .ready
            case 12 ..< 18: .pro
            default: nil
            }
            let tempo = roll(8) == 0 ? nil : 60 + roll(110)
            return Song(
                id: SongID(ids.next()),
                title: String(format: "Fixture Song %03d", index + 1),
                tags: tags,
                proficiency: proficiency,
                key: roll(12) == 0 ? nil : Self.keys[roll(Self.keys.count)],
                capo: roll(5) == 0 ? 1 + roll(4) : 0,
                dropD: roll(10) == 0,
                tempo: tempo,
                bars: max(1, (150 + roll(180)) * (tempo ?? 96) / 240),
                lastPlayedDaysAgo: roll(5) < 2 ? roll(200) : nil,
            )
        }
    }

    var library: AssistantLibrary {
        AssistantLibrary(songs: songs.map(\.assistantSong), now: Self.now)
    }

    func song(_ id: SongID) -> Song? {
        songs.first { $0.id == id }
    }

    /// Item IDs in sequence from a seeded generator.
    static func itemIDs(seed: UInt64 = 99) -> () -> SetlistItemID {
        let ids = ULIDGenerator(clock: ManualClock(), seed: seed)
        return { SetlistItemID(ids.next()) }
    }
}
