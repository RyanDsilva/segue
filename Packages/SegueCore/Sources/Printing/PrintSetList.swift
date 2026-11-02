// Owner: P9-1 (spec 5.10). The set list page's rows from a setlist and its timing.

import Foundation
import Setlists

/// What the caller knows about one song slot: its words (the UI words credits and keys) and
/// the index of its printed song.
public struct PrintSlot: Sendable, Hashable {
    public var title: String
    public var credits: String?
    public var key: String?
    /// Index into the job's songs.
    public var song: Int

    public init(title: String, credits: String?, key: String?, song: Int) {
        self.title = title
        self.credits = credits
        self.key = key
        self.song = song
    }
}

/// What the caller knows about one medley slot: its set list title, its printed song (nil
/// when every member is missing) and its members in order (nil for a missing song), each
/// with its segment in the medley's request.
public struct PrintMedleySlot: Sendable, Hashable {
    public var title: String
    public var song: Int?
    public var members: [PrintSlot?]
    public var segments: [Int?]

    public init(title: String, song: Int?, members: [PrintSlot?], segments: [Int?]) {
        self.title = title
        self.song = song
        self.members = members
        self.segments = segments
    }

    /// "a", "b", ... for member `index` (R178: "5a", "5b").
    public static func letter(_ index: Int) -> String {
        String(UnicodeScalar(UInt8(97 + min(max(index, 0), 25))))
    }
}

public enum PrintSetList {
    /// One row per slot in set order, numbered as the builder numbers them: songs with their
    /// time (`ItemTiming.timeText`: "3:40", "~3:40", "--:--"), breaks as headings with their
    /// part total and intermission, a slot missing from `slots` as "Song not in library".
    /// When the set has breaks the first part gets a "Set 1" heading too, as in the builder.
    /// A medley is one numbered row with its total, then a row per member ("5a", "5b") with
    /// its own time (spec 9).
    public static func rows(
        entries: [SetlistEntry],
        timing: SetlistTiming,
        slots: [SetlistItemID: PrintSlot],
        medleys: [SetlistItemID: PrintMedleySlot] = [:],
    ) -> [SetListRow] {
        var rows: [SetListRow] = []
        let times = Dictionary(
            timing.items.map { ($0.itemId, $0) },
            uniquingKeysWith: { first, _ in first },
        )
        if timing.parts.count > 1, let first = timing.parts.first, first.breakItemId == nil {
            rows.append(.breakHeading(title: "Set 1", total: first.totalText, interval: nil))
        }
        var number = 0
        for entry in entries {
            if case let .break(info) = entry.kind {
                let interval = (info.length ?? 0) > 0
                    ? "Interval " + SetlistTiming.format(info.length ?? 0) : nil
                rows.append(.breakHeading(
                    title: info.label,
                    total: timing.part(openedBy: entry.id)?.totalText,
                    interval: interval,
                ))
                continue
            }
            if case .medley = entry.kind {
                number += 1
                if let medley = medleys[entry.id] {
                    rows += medleyRows(medley, number: number, timing: times[entry.id])
                }
                continue
            }
            guard case .song = entry.kind else { continue }
            number += 1
            guard let slot = slots[entry.id] else {
                rows.append(.missing(number: "\(number)"))
                continue
            }
            rows.append(.song(SetListSong(
                number: "\(number)",
                title: slot.title,
                credits: slot.credits,
                key: slot.key,
                time: times[entry.id]?.timeText ?? SetlistTiming.unknownText,
                song: slot.song,
            )))
        }
        return rows
    }

    /// A medley's row and its members' rows.
    static func medleyRows(_ medley: PrintMedleySlot, number: Int, timing: ItemTiming?)
        -> [SetListRow]
    {
        var rows: [SetListRow] = [.medley(SetListSong(
            number: "\(number)",
            title: medley.title,
            time: timing?.timeText ?? SetlistTiming.unknownText,
            song: medley.song ?? -1,
        ))]
        for (index, member) in medley.members.enumerated() {
            let label = "\(number)" + PrintMedleySlot.letter(index)
            guard let member, let song = medley.song,
                  let segment = medley.segments.indices.contains(index)
                  ? medley.segments[index] : nil
            else {
                rows.append(.missing(number: label))
                continue
            }
            let time = timing?.medley?.members.indices.contains(index) == true
                ? timing?.medley?.members[index].timeText : nil
            rows.append(.song(SetListSong(
                number: label,
                title: member.title,
                credits: member.credits,
                key: member.key,
                time: time ?? SetlistTiming.unknownText,
                song: song,
                member: segment,
            )))
        }
        return rows
    }

    /// A library selection's contents (spec 5.13): numbered 1...N, no times.
    public static func selectionRows(_ slots: [PrintSlot]) -> [SetListRow] {
        slots.enumerated().map { index, slot in
            .song(SetListSong(
                number: "\(index + 1)",
                title: slot.title,
                credits: slot.credits,
                key: slot.key,
                song: slot.song,
            ))
        }
    }
}
