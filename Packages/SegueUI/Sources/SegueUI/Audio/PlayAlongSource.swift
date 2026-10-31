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
    /// Whether timing can be saved (a saved, writable song).
    var canEdit: Bool

    /// The source for a song rendered as `model` with its sidecar `prefs`. Walk-ups are
    /// worked out even when the charts hide them, so the Walk-ups toggle can turn them on:
    /// at the profile's density, else into sections.
    @MainActor static func make(
        model: RenderModel,
        document: SongDocument,
        prefs: BassPrefs,
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
        let context = BassLineContext(
            transform: model.transform,
            genre: prefs.genre ?? profile?.genre ?? .pop,
            density: density == .off ? .sections : density,
            timeline: timeline,
            picks: prefs.walkUps.isEmpty ? .empty
                : ChordAnchors.resolve(prefs.walkUps, units: units, sections: model.sections),
        )
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
            placement: SoundSession.placement(for: model, profile: profile),
            chartsShowWalkUps: model.transform.options.bass?.notes == true && density != .off,
            canEdit: canEdit,
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
