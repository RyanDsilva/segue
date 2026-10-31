import ChordPro
import Editing
import Library
import MusicTheory
import Playback
import SwiftUI

/// What the editor's or library's play-along bar plays (P8-6 sections 7.2, 10.3): the song in
/// written order as `SongTimeline` times it, with the changes the charts would show and the
/// bass placed as the previews place it. A value, so the bar rebuilds only when it changes.
struct PlayAlongSource: Equatable {
    /// Written order (`{chorus}` stubs written out).
    var timeline: SongTimeline
    /// The rendered sections (labels, the preview cue, the chart's chord text).
    var sections: [RenderSection]
    var units: [SongSectionUnit]
    /// The song's saved timing (rule and corrections).
    var timing: ChordTiming
    /// Every change in written order, with the walk-up the charts show (the pick, else the
    /// top candidate).
    var changes: [ChordChange]
    var transform: DisplayTransform
    var placement: BassPlacement
    /// Whether the charts show walk-ups (the bass-note view with walk-ups not Off): the
    /// Walk-ups toggle's default.
    var chartsShowWalkUps: Bool
    /// Whether the chart's walk-up density is not Off. Off, play-along plays no walk-ups
    /// and the Walk-ups toggle is unavailable (R170).
    var hasWalkUps: Bool
    /// Whether timing can be saved (a saved, writable song).
    var canEdit: Bool
    /// The song's saved fills, played instead of the bass line where they apply.
    var fills: PlayAlongFills

    /// The source for a song rendered as `model` with its sidecar `prefs` and `parts` (its
    /// saved fills). Walk-ups follow the chart's density (none while Off, R170); they are
    /// worked out even when the bass-note view is off, so the Walk-ups toggle can turn them
    /// on. A change a fill covers plays the fill, not a walk-up (P8-7 section 13).
    @MainActor static func make(
        // swiftlint:disable:previous function_parameter_count
        model: RenderModel,
        document: SongDocument,
        prefs: BassPrefs,
        parts: [Part],
        profile: InstrumentProfile?,
        canEdit: Bool,
    ) -> Self {
        let units = SongSections.units(of: document)
        let timeline = SongTimeline.build(
            document: document,
            sections: model.sections,
            units: units,
            timing: prefs.timing,
            order: nil,
        )
        let density = profile?.walkUps ?? .off
        var context = BassLineContext(
            transform: model.transform,
            genre: prefs.genre ?? profile?.genre ?? .pop,
            density: density,
            timeline: timeline,
        )
        context.apply(prefs, parts: parts, units: units, sections: model.sections)
        let placement = SoundSession.placement(for: model, profile: profile)
        return Self(
            timeline: timeline,
            sections: model.sections,
            units: units,
            timing: prefs.timing,
            changes: BassLine.changes(
                model.sections,
                origins: Array(model.sections.indices),
                context: context,
            ),
            transform: model.transform,
            placement: placement,
            chartsShowWalkUps: model.transform.options.bass?.notes == true && density != .off,
            hasWalkUps: density != .off,
            canEdit: canEdit,
            fills: PlayAlongFills(
                parts: context.parts,
                song: timeline,
                transform: model.transform,
                placement: placement,
            ),
        )
    }

    /// A pass's name for the range menu ("Verse", "Chorus 2").
    func passTitle(_ index: Int) -> String {
        guard timeline.passes.indices.contains(index) else { return "" }
        let pass = timeline.passes[index]
        let content = sections.indices.contains(pass.content) ? pass.content : pass.section
        let label = sections.indices.contains(content)
            ? SectionNotes.label(of: sections[content]) ?? "Section \(index + 1)"
            : "Section \(index + 1)"
        let plays = timeline.passes.count { $0.content == pass.content }
        return plays > 1 ? "\(label) \(pass.occurrence)" : label
    }

    /// The passes that have chords (the range menu lists only those).
    var playablePasses: [Int] {
        timeline.passes.indices.filter { index in
            timeline.chords.contains { $0.pass == index }
        }
    }

    /// Where a timed chord sits in the preview: its line's row and the chord on it. A
    /// `{chorus}` stub's chords point at the chorus they repeat.
    func cue(for chord: TimedChord) -> PlayAlongCue? {
        guard !chord.isSilent, sections.indices.contains(chord.position.section) else {
            return nil
        }
        let section = sections[chord.position.section]
        var ordinal = 0
        for (index, item) in section.items.enumerated() {
            guard case let .lyrics(line) = item else { continue }
            for written in line.chords where written.kind == .chord {
                if ordinal == chord.position.chord {
                    return PlayAlongCue(
                        row: "\(section.id).\(index)",
                        line: line.path,
                        offset: written.offset,
                        text: written.text,
                    )
                }
                ordinal += 1
            }
        }
        return nil
    }
}

/// A song's saved fills as play-along plays them (P8-7 section 13, R168 Q4): its parts
/// resolved against the written song, and the timeline every play-along range is cut from
/// (so "Shows on: Last time" is the song's last play, R170). Called as the play-along's
/// `fillProvider` with the range it voices.
struct PlayAlongFills: Equatable {
    var parts: ResolvedParts
    /// The timeline the range is cut from, in the order played.
    var song: SongTimeline
    var transform: DisplayTransform
    var placement: BassPlacement

    func callAsFunction(_ range: PlayAlongTimeline) -> [PlayAlongFill] {
        guard !parts.applied.isEmpty else { return [] }
        return PlayAlongFill.fills(
            parts,
            in: range,
            song: song,
            transform: transform,
            placement: placement,
        )
    }
}

/// The chord at the playhead in a preview (P8-6 10.3): its sheet row (to scroll to) and the
/// chord on its line (to underline).
struct PlayAlongCue: Equatable {
    /// `SheetRow.id`.
    var row: String
    var line: BlockPath
    /// The chord's lyric offset on its line.
    var offset: Int
    /// The chord as the chart row shows it (the bass note in the bass-note view).
    var text: String
}

extension EnvironmentValues {
    /// The chord at the play-along playhead in a preview (nil when not playing).
    @Entry var playAlongCue: PlayAlongCue?
}
