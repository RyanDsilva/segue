// P9-3 9.1-9.2, 13: a medley is one stage plan made of segments, one per member, each with
// its own model (key, capo), arrangement, cues, notes and walk-ups, opened by a member
// header. Print (P9-1) builds the same headers through `MemberHeader.make`, so stage and
// paper say the same thing.

import Editing
import Foundation
import Library
import Setlists

/// One member's part of a medley plan: what a single-song request carries, plus the header.
public struct LayoutSegment: Sendable {
    /// The member's model with its overrides applied.
    public var model: RenderModel
    /// Its applied arrangement; nil = the full song.
    public var passes: [PlayedPass]?
    public var cues: [SongCue]
    /// Its song note and its member note.
    public var notes: [String]
    public var walkUps: BassLineContext?
    /// Nil for a plain song.
    public var header: MemberHeader?

    public init(
        model: RenderModel,
        passes: [PlayedPass]? = nil,
        cues: [SongCue] = [],
        notes: [String] = [],
        walkUps: BassLineContext? = nil,
        header: MemberHeader? = nil,
    ) {
        self.model = model
        self.passes = passes
        self.cues = cues
        self.notes = notes
        self.walkUps = walkUps
        self.header = header
    }
}

/// One change between two members, for the derived change line ("G -> A").
public struct MemberChange: Sendable, Hashable {
    public enum Kind: Sendable, Hashable {
        case key
        /// Drawn in the cue colour, so a mid-medley capo move is never missed.
        case capo
        case tempo
        case meter
    }

    public var kind: Kind
    public var text: String

    public init(_ kind: Kind, _ text: String) {
        self.kind = kind
        self.text = text
    }
}

/// The block that opens a member's segment (P9-3 9.2): its title, key line, "2 of 3", the
/// transition into it and the derived change line.
public struct MemberHeader: Sendable, Hashable {
    /// The member's display title.
    public var title: String
    /// "A, capo 2, 120" (singer view: "Key A, 120").
    public var keyLine: String
    /// 0-based.
    public var index: Int
    public var count: Int
    /// From the second member on; nil when none is written.
    public var transition: String?
    /// What changes from the previous member: key, capo, tempo, meter (empty for the first).
    public var changes: [MemberChange]

    public init(
        title: String,
        keyLine: String,
        index: Int,
        count: Int,
        transition: String? = nil,
        changes: [MemberChange] = [],
    ) {
        self.title = title
        self.keyLine = keyLine
        self.index = index
        self.count = count
        self.transition = transition
        self.changes = changes
    }

    /// "2 of 3".
    public var positionText: String {
        "\(index + 1) of \(count)"
    }

    /// The change line as one string: "G -> A · capo 2 -> no capo · 96 -> 120 BPM".
    public var changeLine: String {
        changes.map(\.text).joined(separator: " \u{00B7} ")
    }

    // swiftlint:disable function_parameter_count
    /// The header for `member` after `previous` (nil for the first member), as stage and
    /// print draw it. `singer` (P9-2 9.9) uses the sounding key and drops the capo, from the
    /// key line and the change line. A missing song (nil record) shows its title only.
    public static func make(
        member: MedleyMember,
        previous: MedleyMember?,
        record: SongRecord?,
        previousRecord: SongRecord?,
        index: Int,
        count: Int,
        title: String,
        singer: Bool = false,
    ) -> Self {
        let facts = record.map { MemberFacts($0, overrides: member.overrides, singer: singer) }
        let before = previousRecord.flatMap { record in
            previous.map { MemberFacts(record, overrides: $0.overrides, singer: singer) }
        }
        return Self(
            title: title,
            keyLine: facts?.keyLine(singer: singer) ?? "",
            index: index,
            count: count,
            transition: index == 0 ? nil : SetlistMedley.clean(member.transition),
            changes: facts.flatMap { now in before.map { now.changes(from: $0, singer: singer) } }
                ?? [],
        )
    }
    // swiftlint:enable function_parameter_count
}

/// What a member's header compares: its displayed (or sounding) key, capo, tempo, meter.
struct MemberFacts {
    var key: String?
    var capo: Int
    var tempo: Double?
    var meter: String?

    init(_ record: SongRecord, overrides: SetlistOverrides, singer: Bool) {
        let metadata = record.document.metadata
        let (options, capo) = overrides.applied(
            to: record.sidecar.displayPrefs.displayOptions,
            songCapo: metadata.capo,
        )
        let transform = DisplayTransform(
            options: options,
            key: KeyContext(document: record.document),
            capo: capo,
        )
        key = (singer ? transform.concertKey : transform.displayKey)?.name
        self.capo = max(capo ?? 0, 0)
        tempo = metadata.tempo
        meter = metadata.time.flatMap { $0.isEmpty ? nil : $0 }
    }

    func keyLine(singer: Bool) -> String {
        var parts: [String] = []
        if let key {
            parts.append(singer ? "Key \(key)" : key)
        }
        if !singer, capo > 0 {
            parts.append("capo \(capo)")
        }
        if let tempo {
            parts.append(Self.bpm(tempo))
        }
        return parts.joined(separator: ", ")
    }

    func changes(from before: Self, singer: Bool) -> [MemberChange] {
        var changes: [MemberChange] = []
        if let old = before.key, let new = key, old != new {
            changes.append(MemberChange(.key, "\(old) \u{2192} \(new)"))
        }
        if !singer, before.capo != capo {
            changes.append(MemberChange(
                .capo,
                "\(Self.capoText(before.capo)) \u{2192} \(Self.capoText(capo))",
            ))
        }
        if let old = before.tempo, let new = tempo, Self.bpm(old) != Self.bpm(new) {
            changes.append(MemberChange(.tempo, "\(Self.bpm(old)) \u{2192} \(Self.bpm(new)) BPM"))
        }
        if let old = before.meter, let new = meter, old != new {
            changes.append(MemberChange(.meter, "\(old) \u{2192} \(new)"))
        }
        return changes
    }

    static func capoText(_ capo: Int) -> String {
        capo > 0 ? "capo \(capo)" : "no capo"
    }

    static func bpm(_ tempo: Double) -> String {
        "\(Int(tempo.rounded()))"
    }
}

/// A member header as placed in its block (P9-3 9.2), from the head's top; drawn across the
/// whole column (gutter included) above the segment's first pass.
public struct PlacedMemberHeader: Sendable, Hashable {
    public var header: MemberHeader
    /// The header's height, spacing below included (the pass's content starts there).
    public var height: Double
    /// Whether a one-line rule is drawn at its top (from the second member on).
    public var hasRule: Bool
    /// The title's size (0.75 x the lyric size) and first baseline.
    public var titleSize: Double
    public var titleBaseline: Double
    /// The transition (role `.cue` lines) and the change line in one callout; nil when the
    /// member has neither.
    public var callout: PlacedCue?
    /// The change line's baseline inside the callout and its size.
    public var changesBaseline: Double?
    public var changesSize: Double
    /// A later member's notes (role `.note`), under the callout.
    public var notes: [PlacedLine]

    public init(
        header: MemberHeader,
        height: Double,
        hasRule: Bool,
        titleSize: Double,
        titleBaseline: Double,
        callout: PlacedCue? = nil,
        changesBaseline: Double? = nil,
        changesSize: Double = 0,
        notes: [PlacedLine] = [],
    ) {
        self.header = header
        self.height = height
        self.hasRule = hasRule
        self.titleSize = titleSize
        self.titleBaseline = titleBaseline
        self.callout = callout
        self.changesBaseline = changesBaseline
        self.changesSize = changesSize
        self.notes = notes
    }

    /// The title's size against the lyric size.
    public static let titleScale = 0.75
}
