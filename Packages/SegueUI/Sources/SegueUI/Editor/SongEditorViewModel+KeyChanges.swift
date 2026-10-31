import ChordPro
import Editing
import Foundation
import Library
import MusicTheory

/// A directive the editor can insert at a point (P8-7 section 6.1, R167 Q2): one per action.
enum ChartDirective: String, CaseIterable, Identifiable, Sendable {
    case key
    case time
    case tempo

    var id: String {
        rawValue
    }

    /// "Insert Key Change Here...".
    var menuTitle: String {
        switch self {
        case .key: "Insert Key Change Here..."
        case .time: "Insert Time Change Here..."
        case .tempo: "Insert Tempo Change Here..."
        }
    }

    /// The Song > Insert item.
    var insertTitle: String {
        switch self {
        case .key: "Key Change..."
        case .time: "Time Change..."
        case .tempo: "Tempo Change..."
        }
    }

    /// The value's problem, or nil when it can be written (`Metadata`'s own checks).
    static func problem(_ directive: Self, value: String) -> String? {
        let value = value.trimmingCharacters(in: .whitespaces)
        switch directive {
        case .key:
            return SongKey(parsing: value) == nil ? "Pick a key" : nil
        case .time:
            return Metadata.parseTime(value) == nil
                ? "Type a time signature like 3/4 or 6/8" : nil
        case .tempo:
            guard let bpm = Double(value), bpm.isFinite, bpm > 0, bpm <= 400 else {
                return "Type a tempo in BPM, like 96"
            }
            return nil
        }
    }
}

/// What the insert popover starts from at a point.
struct DirectiveDraft: Equatable {
    var directive: ChartDirective
    var path: BlockPath
    /// The key, time and tempo in effect there (the key: the chip's suggestion first).
    var key: SongKey
    var time: String
    var tempo: String
    /// "Written key (capo 2: sounds B)" under a capo.
    var capoNote: String?
}

/// The key-change chip and directive inserts in the editor (P8-7 sections 6.1, 6.2): the
/// editor only (text-mode preview and the visual canvas), for any song. Inserting writes one
/// line into the `.cho` (one undo step); dismissing writes `timing.dismissedKeys` to the
/// sidecar (one undo step). Never applied without a click.
extension SongEditorViewModel {
    /// The song in written order as `SongTimeline` times it; nil before the first render.
    func editorTimeline(_ model: RenderModel? = nil) -> SongTimeline? {
        guard let model = model ?? renderModel else { return nil }
        return SongTimeline.build(
            document: snapshot.document,
            sections: model.sections,
            units: SongSections.units(of: snapshot.document),
            timing: bassPrefs.timing,
            order: nil,
        )
    }

    /// "Looks like a key change to A" suggestions for the rendered song.
    func keyChangeSuggestions(_ model: RenderModel? = nil) -> [KeyChangeSuggestion] {
        guard let model = model ?? renderModel, let timeline = editorTimeline(model) else {
            return []
        }
        return KeyChangeDetector.suggestions(
            timeline: timeline,
            sections: model.sections,
            units: SongSections.units(of: snapshot.document),
            dismissed: bassPrefs.timing.dismissedKeys,
        )
    }

    /// The chip's "Insert {key: A}": the directive before the section's header.
    func acceptKeyChange(_ suggestion: KeyChangeSuggestion) {
        guard let path = suggestion.insertBefore else { return }
        insertDirective(.key, value: suggestion.key.name, before: path)
    }

    /// The chip's "x": remembered in the sidecar (not the `.cho`), one undo step.
    func dismissKeyChange(_ suggestion: KeyChangeSuggestion) {
        guard canPickWalkUps else { return }
        var prefs = bassPrefs
        guard !prefs.timing.dismissedKeys.contains(suggestion.dismissal) else { return }
        prefs.timing.dismissedKeys.append(suggestion.dismissal)
        setBassPrefs(prefs, actionName: "Dismiss Key Change")
    }

    /// Writes `{name: value}` as its own line before `path`. Returns the problem when the
    /// value cannot be written or the point is not a line or section.
    @discardableResult
    func insertDirective(_ directive: ChartDirective, value: String, before path: BlockPath)
        -> String?
    {
        let value = value.trimmingCharacters(in: .whitespaces)
        if let problem = ChartDirective.problem(directive, value: value) {
            return problem
        }
        let operation = EditOperation.insertDirective(
            name: directive.rawValue,
            value: value,
            before: path,
        )
        return perform(operation) ? nil : "Can't insert a change here"
    }

    /// The popover's starting values at `path`.
    func directiveDraft(_ directive: ChartDirective, before path: BlockPath) -> DirectiveDraft {
        let timeline = editorTimeline()
        let chord = timeline?.chords.first { !$0.isSilent && $0.line >= path }
            ?? timeline?.chords.last
        let suggested = keyChangeSuggestions().first { $0.insertBefore == path }?.key
        let key = suggested ?? chord?.key ?? timeline?.keys.initial
            ?? renderModel?.transform.key.writtenKey
            ?? SongKey(canonical: PitchClass(0), mode: .major)
        let meter = chord?.meter ?? timeline?.meters.initial ?? .common
        let tempo = chord?.tempo ?? timeline?.tempos.initial.flatMap(\.self)
        let capo = renderModel?.transform.capo ?? 0
        return DirectiveDraft(
            directive: directive,
            path: path,
            key: key,
            time: meter.description,
            tempo: tempo.map { $0.rounded() == $0 ? "\(Int($0))" : "\($0)" } ?? "",
            capoNote: capo > 0 ? "capo \(capo)" : nil,
        )
    }

    /// The key that sounds for written `key` under the song's capo.
    func soundingKey(_ key: SongKey) -> SongKey {
        key.transposed(by: max(renderModel?.transform.capo ?? 0, 0))
    }
}
