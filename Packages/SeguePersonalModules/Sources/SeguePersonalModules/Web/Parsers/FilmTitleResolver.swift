import Foundation
import ModelPort
import Plugins

/// R194: when a film song name has more than one " - ", the on-device model picks which part
/// is the title, through the app's existing metadata task. Its answer is used only when it is
/// exactly one of the code's own candidate titles, so it can never invent a name; otherwise
/// (no model, AI off, a show running, any other answer) the fallback split at the last " - "
/// stays, flagged for the review.
enum FilmTitleResolver {
    /// The metadata task for an ambiguous name: the name and the convention, as top lines.
    static func task(for fields: SourceFields) -> MetadataTask? {
        guard fields.titleUncertain, let first = fields.titleSplits.first else { return nil }
        let name = first.album + " - " + first.title
        return MetadataTask(
            topLines: [
                name,
                "This film song name is written as <Movie> - <Song title>;"
                    + " the movie name may itself contain \" - \".",
            ],
            bottomLines: [],
            chords: [],
        )
    }

    /// The split whose title the answer names (case, spacing and diacritics ignored).
    static func pick(_ answer: String, from splits: [TitleSplit]) -> TitleSplit? {
        let key = loose(answer)
        guard !key.isEmpty else { return nil }
        return splits.first { loose($0.title) == key }
    }

    /// The fields with the model's pick applied, or unchanged (still flagged) without one.
    static func resolve(_ fields: SourceFields, router: Router) async -> SourceFields {
        guard let task = task(for: fields) else { return fields }
        let routed = await router.run(task)
        guard let answer = routed.output?.normalized().title,
              let split = pick(answer, from: fields.titleSplits)
        else { return fields }
        var resolved = fields
        resolved.title = split.title
        resolved.album = split.album
        resolved.titleUncertain = false
        return resolved
    }

    private static func loose(_ text: String) -> String {
        text.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
            .split(whereSeparator: { !$0.isLetter && !$0.isNumber }).joined(separator: " ")
    }
}
