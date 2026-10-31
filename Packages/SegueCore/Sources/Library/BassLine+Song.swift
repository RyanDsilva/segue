// P8-4b (docs/phases/8-workstreams/P8-4-bass.md section 8.6). Walk-ups for a whole song in
// written order: the editor and library previews, the Walk-ups popover, the bass chart PDF.

import ChordPro
import Editing
import MusicTheory

public extension BassLine {
    /// The context for a song rendered as `model` (its bass view) with its saved `prefs` and
    /// `parts` (the sidecar's fills): the song's timeline in written order (lengths, tempo and
    /// `{key}` in effect, P8-7 section 5.7), its picks, its fills and its scale (R170); nil
    /// without a bass view.
    static func context(
        for model: RenderModel,
        document: SongDocument,
        prefs: BassPrefs,
        parts: [Part] = [],
    ) -> BassLineContext? {
        guard let bass = model.transform.options.bass else { return nil }
        let units = SongSections.units(of: document)
        let timeline = SongTimeline.build(
            document: document,
            sections: model.sections,
            units: units,
            timing: prefs.timing,
            order: nil,
        )
        var context = BassLineContext(
            transform: model.transform,
            genre: prefs.genre ?? bass.genre,
            density: bass.walkUps,
            timeline: timeline,
        )
        context.apply(prefs, parts: parts, units: units, sections: model.sections)
        return context
    }

    /// `model` with walk-ups drawn: only in the bass-note view and while the density is not
    /// Off (R162 Q4), in written order (editor, library, bass chart PDF).
    static func annotated(
        _ model: RenderModel,
        document: SongDocument,
        prefs: BassPrefs,
        parts: [Part] = [],
    ) -> RenderModel {
        guard model.transform.options.bass?.notes == true,
              let context = context(for: model, document: document, prefs: prefs, parts: parts),
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
        parts: [Part] = [],
    ) -> [ChordChange] {
        guard let context = context(for: model, document: document, prefs: prefs, parts: parts)
        else {
            return []
        }
        return changes(model.sections, origins: Array(model.sections.indices), context: context)
    }
}

public extension BassLineContext {
    /// The song's sidecar applied: its walk-up picks and its fills (`parts`) resolved against
    /// the written song (`units`, `sections`, this context's timeline), and its scale (R170,
    /// else the default from this context's feel and key).
    mutating func apply(
        _ prefs: BassPrefs,
        parts: [Part],
        units: [SongSectionUnit],
        sections: [RenderSection],
    ) {
        picks = prefs.walkUps.isEmpty ? .empty : ChordAnchors.resolve(
            prefs.walkUps,
            units: units,
            sections: sections,
        )
        self.parts = parts.isEmpty ? .empty : PartAnchors.resolve(
            parts,
            timeline: timeline,
            units: units,
            sections: sections,
        )
        mode = FillMode.resolved(prefs.mode, genre: genre, key: key)
    }
}
