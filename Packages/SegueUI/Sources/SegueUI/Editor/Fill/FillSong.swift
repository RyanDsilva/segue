// P8-7d (docs/phases/8-workstreams/P8-7-time-model-and-fills.md sections 12.1-12.3, 12.7).
// What the fill editor needs from the screen it opens over (the editor, the library): the
// song as its preview renders it, its saved fills, and the writers for parts and timing.

import ChordPro
import Diagrams
import Editing
import Library
import MusicTheory
import Playback
import Services

/// One song as the fill editor reads it: written order, the preview's transform, the bass
/// placed as play-along places it.
struct FillSong {
    var title: String
    var model: RenderModel
    var document: SongDocument
    var prefs: BassPrefs
    /// Every saved part (the sidecar's, unmatched ones included).
    var parts: [Part]
    /// The play-along bar's view of the song: timeline, units, resolved parts, placement.
    var playAlong: PlayAlongSource
    /// The song's feel, else the profile's (Pop).
    var genre: BassGenre
    /// Parts can be written (a saved song from this Segue).
    var canEdit: Bool
    /// Why nothing can be written, for the disabled controls' help.
    var readOnlyHelp: String?
    /// The bass-note view is on (fills show only there).
    var bassViewOn: Bool

    @MainActor
    static func make(
        // swiftlint:disable:previous function_parameter_count
        title: String,
        model: RenderModel,
        document: SongDocument,
        prefs: BassPrefs,
        parts: [Part],
        profile: InstrumentProfile?,
        canEdit: Bool,
        readOnlyHelp: String?,
    ) -> Self {
        Self(
            title: title,
            model: model,
            document: document,
            prefs: prefs,
            parts: parts,
            playAlong: PlayAlongSource.make(
                model: model,
                document: document,
                prefs: prefs,
                parts: parts,
                profile: profile,
                canEdit: canEdit,
            ),
            genre: prefs.genre ?? profile?.genre ?? .pop,
            canEdit: canEdit,
            readOnlyHelp: readOnlyHelp,
            bassViewOn: model.transform.options.bass?.notes == true,
        )
    }

    var timeline: SongTimeline {
        playAlong.timeline
    }

    var resolved: ResolvedParts {
        playAlong.fills.parts
    }

    var placement: BassPlacement {
        playAlong.placement
    }

    var transform: DisplayTransform {
        model.transform
    }

    /// The span's anchor (what a saved part keeps), nil when the span cannot take a fill.
    func anchor(_ span: ClosedRange<Int>) -> SpanAnchor? {
        FillSpan.anchor(
            timeline: timeline,
            chords: span,
            units: playAlong.units,
            sections: model.sections,
        )
    }

    /// The generator's facts for `span`.
    func context(_ span: ClosedRange<Int>) -> FillContext? {
        FillSpan.context(
            timeline: timeline,
            chords: span,
            transform: transform,
            genre: genre,
            tuning: placement.tuning,
            home: placement.home,
            sections: model.sections,
            mode: prefs.mode,
        )
    }

    /// The written span of an applied part: its first play in written order.
    func span(of part: PartID) -> ClosedRange<Int>? {
        resolved.plays(in: timeline).first { $0.part.id == part }?.chords
            ?? resolved.applied.first { $0.part.id == part }.flatMap { applied in
                let first = timeline.chords.firstIndex { $0.position == applied.positions.first }
                return first.map { $0 ... $0 + applied.positions.count - 1 }
            }
    }

    /// A section's label ("Chorus 2" when it plays more than once in written order).
    func sectionTitle(ofChord index: Int) -> String {
        guard timeline.chords.indices.contains(index) else { return "" }
        return playAlong.passTitle(timeline.chords[index].pass)
    }
}

/// What the fill editor's owner hands it: the song now, the writers, sound and analytics.
struct FillHost {
    var context: FeatureContext
    /// The song as it is now; nil once it is gone.
    var song: @MainActor () -> FillSong?
    /// Replaces the song's parts (sidecar only), one undo step named `actionName` in the
    /// editor (the library has no undo).
    var writeParts: @MainActor (_ parts: [Part], _ actionName: String) -> Void
    /// Saves a timing change from the sheet's chord lane (its own undo step).
    var writeTiming: TimingWriter
    var sound: SoundSession?
    var services: ServicesHub
    var settings: FillEditorSettings
    /// A one-time note after saving (the bass-note view is off).
    var showNote: @MainActor (String) -> Void
}
