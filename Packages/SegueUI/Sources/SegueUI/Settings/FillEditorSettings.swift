// P8-7d (docs/phases/8-workstreams/P8-7-time-model-and-fills.md sections 12.1, 12.2, R167
// Q13). The fill editor's per-user memory: the view it opens on (fretboard + grid the first
// time, then the last one used; never per song) and whether the bass-note view note was shown.

import Foundation
import Observation
import Support

/// The fill editor's two views.
enum FillEditorView: String, Sendable, Hashable, Codable, CaseIterable {
    case fretboard
    case pianoRoll

    var title: String {
        switch self {
        case .fretboard: "Fretboard"
        case .pianoRoll: "Piano Roll"
        }
    }
}

/// UserDefaults `fill.editor`: one JSON value, each field read leniently.
@MainActor
@Observable
final class FillEditorSettings {
    static let defaultsKey = "fill.editor"

    struct Values: Codable, Equatable {
        var view: FillEditorView = .fretboard
        /// "Fills show in the bass-note view..." was shown once.
        var bassViewNoteShown = false
        /// Keys this build does not model, kept for the next save
        /// (docs/architecture/data-compatibility.md).
        var unknown: UnknownFields = .empty

        private enum CodingKeys: String, CodingKey, CaseIterable {
            case view
            case bassViewNoteShown
        }

        init() {}

        init(from decoder: any Decoder) throws {
            var object = try LenientObject<CodingKeys>(decoder)
            view = object.value(.view, default: .fretboard)
            bassViewNoteShown = object.value(.bassViewNoteShown, default: false)
            unknown = object.unknown
        }

        func encode(to encoder: any Encoder) throws {
            try unknown.encode(to: encoder)
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(view, forKey: .view)
            try container.encode(bassViewNoteShown, forKey: .bassViewNoteShown)
        }
    }

    private(set) var values: Values
    @ObservationIgnored private let defaults: UserDefaults

    init(defaults: UserDefaults) {
        self.defaults = defaults
        values = defaults.data(forKey: Self.defaultsKey)
            .flatMap { try? SegueJSON.decode(Values.self, from: $0) } ?? Values()
    }

    var view: FillEditorView {
        get { values.view }
        set { update { $0.view = newValue } }
    }

    var bassViewNoteShown: Bool {
        get { values.bassViewNoteShown }
        set { update { $0.bassViewNoteShown = newValue } }
    }

    private func update(_ change: (inout Values) -> Void) {
        var next = values
        change(&next)
        guard next != values else { return }
        values = next
        if let data = try? SegueJSON.encode(next) {
            defaults.set(data, forKey: Self.defaultsKey)
        }
    }
}
