// P9-3 6.2, 9.2, 13: what changes from one medley member to the next ("G → A", "capo 2 →
// no capo", "96 → 120 BPM", "4/4 → 6/8"). One derivation, so the builder's change line, the
// stage's member header and the printed songbook say the same thing. Pure.

import Editing
import Foundation
import Library

/// What a medley member plays in: the key shown after its overrides, its capo, tempo and
/// meter.
public struct MemberKeyInfo: Sendable, Equatable {
    /// The displayed key ("A"), as the set row shows it; nil when the song has none.
    public var key: String?
    /// The capo to play with; nil = no capo.
    public var capo: Int?
    /// The song's `{tempo}`.
    public var tempo: Double?
    /// The song's `{time}` ("6/8").
    public var meter: String?

    public init(key: String?, capo: Int?, tempo: Double?, meter: String?) {
        self.key = key
        self.capo = capo
        self.tempo = tempo
        self.meter = meter
    }

    /// The member as `record` plays with `overrides` (the set row's key and capo rule).
    public init(record: SongRecord, overrides: SetlistOverrides) {
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
        self.init(
            key: transform.displayKey?.name,
            capo: (capo ?? 0) > 0 ? capo : nil,
            tempo: metadata.tempo,
            meter: metadata.time.flatMap { $0.isEmpty ? nil : $0 },
        )
    }

    /// "A, capo 2, 120": the key line under a member's title (parts it lacks left out).
    public var keyLine: String {
        var parts: [String] = []
        if let key {
            parts.append(key)
        }
        if let capo {
            parts.append("capo \(capo)")
        }
        if let tempo {
            parts.append("\(Int(tempo.rounded()))")
        }
        return parts.joined(separator: ", ")
    }
}

/// One thing that changes between two members.
public enum MedleyChange: Sendable, Equatable {
    case key(String, String)
    case capo(Int?, Int?)
    case tempo(Int, Int)
    case meter(String, String)

    /// "G → A", "capo 2 → no capo", "96 → 120 BPM", "4/4 → 6/8".
    public var text: String {
        switch self {
        case let .key(from, to):
            "\(from) → \(to)"
        case let .capo(from, to):
            "\(Self.capoText(from)) → \(Self.capoText(to))"
        case let .tempo(from, to):
            "\(from) → \(to) BPM"
        case let .meter(from, to):
            "\(from) → \(to)"
        }
    }

    /// A capo change: drawn in the essentials colour so a mid-medley capo move is never
    /// missed.
    public var isCapo: Bool {
        if case .capo = self {
            return true
        }
        return false
    }

    private static func capoText(_ fret: Int?) -> String {
        fret.map { "capo \($0)" } ?? "no capo"
    }
}

public enum MedleyChanges {
    /// What changes from `previous` to `next`, only what changes: key, capo, tempo, meter.
    /// A value one side lacks is no change (nothing is invented).
    public static func between(_ previous: MemberKeyInfo, _ next: MemberKeyInfo)
        -> [MedleyChange]
    {
        var changes: [MedleyChange] = []
        if let from = previous.key, let to = next.key, from != to {
            changes.append(.key(from, to))
        }
        if previous.capo != next.capo {
            changes.append(.capo(previous.capo, next.capo))
        }
        if let from = previous.tempo.map({ Int($0.rounded()) }),
           let to = next.tempo.map({ Int($0.rounded()) }), from != to
        {
            changes.append(.tempo(from, to))
        }
        if let from = previous.meter, let to = next.meter, from != to {
            changes.append(.meter(from, to))
        }
        return changes
    }

    /// The change line joined " · " ("G → A · capo 2 → no capo · 96 → 120 BPM").
    public static func line(_ changes: [MedleyChange]) -> String {
        changes.map(\.text).joined(separator: " · ")
    }
}
