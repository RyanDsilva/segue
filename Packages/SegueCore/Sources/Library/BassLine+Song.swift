// P8-4b (docs/phases/8-workstreams/P8-4-bass.md section 8.6). Walk-ups for a whole song in
// written order: the editor and library previews, the Walk-ups popover, the bass chart PDF.

import ChordPro
import Editing

public extension BassLine {
    /// The context for a song rendered as `model` (its bass view) with its saved `prefs`:
    /// the song's timeline in written order (lengths, tempo and `{key}` in effect, P8-7
    /// section 5.7) and its picks; nil without a bass view.
    static func context(
        for model: RenderModel,
        document: SongDocument,
        prefs: BassPrefs,
    ) -> BassLineContext? {
        guard let bass = model.transform.options.bass else { return nil }
        let units = SongSections.units(of: document)
        let picks = prefs.walkUps.isEmpty ? ResolvedPicks.empty : ChordAnchors.resolve(
            prefs.walkUps,
            units: units,
            sections: model.sections,
        )
        return BassLineContext(
            transform: model.transform,
            genre: prefs.genre ?? bass.genre,
            density: bass.walkUps,
            timeline: SongTimeline.build(
                document: document,
                sections: model.sections,
                units: units,
                timing: prefs.timing,
                order: nil,
            ),
            picks: picks,
        )
    }

    /// `model` with walk-ups drawn: only in the bass-note view and while the density is not
    /// Off (R162 Q4), in written order (editor, library, bass chart PDF).
    static func annotated(
        _ model: RenderModel,
        document: SongDocument,
        prefs: BassPrefs,
    ) -> RenderModel {
        guard model.transform.options.bass?.notes == true,
              let context = context(for: model, document: document, prefs: prefs),
              context.density != .off
        else { return model }
        var model = model
        model.sections = annotate(
            model.sections,
            origins: Array(model.sections.indices),
            context: context,
        )
        return model
    }

    /// Every change of the song in written order (the Walk-ups list and popover).
    static func changes(
        _ model: RenderModel,
        document: SongDocument,
        prefs: BassPrefs,
    ) -> [ChordChange] {
        guard let context = context(for: model, document: document, prefs: prefs) else {
            return []
        }
        return changes(model.sections, origins: Array(model.sections.indices), context: context)
    }
}
