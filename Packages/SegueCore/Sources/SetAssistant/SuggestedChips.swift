// Phase 3 P3-7 (spec section 7 step 2, R65, R92, R93): the async model pass. Only the words
// the lexicon left go to the model, with the library's actual tags as the only answers it may
// give; whatever it maps becomes suggested chips the user accepts or ignores. It never
// replaces a chip the request states, and nothing runs it during a show (the router skips).

import Foundation
import ModelPort

public enum SuggestedChips {
    /// The model call for `lexicon`'s leftover words, or nil when nothing is left to map
    /// (no call is made). The tags go in sorted, so the same library always asks the same
    /// question (and recordings replay).
    public static func task(for lexicon: LexiconResult, libraryTags: [String]) -> SetRequestTask? {
        let words = lexicon.leftoverText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !words.isEmpty, !libraryTags.isEmpty else { return nil }
        let tags = libraryTags
            .sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
        return SetRequestTask(words: words, libraryTags: tags)
    }

    /// Words that name a slot ("opener", "finish") or a proficiency ("know", "learning"): a
    /// model's opener / closer or proficiency answer counts only when the words sent hold one.
    /// Foundation Models fills every field whatever it is asked (spike section 4; recorded
    /// again for P3-7), and R92 allows slot shaping only when the request asks.
    static let slotCues: Set = [
        "start", "open", "opener", "opening", "first", "kick", "end", "finish", "close",
        "closer", "closing", "last", "encore",
    ]
    static let proficiencyCues: Set = [
        "know", "known", "play", "learning", "learn", "learned", "learnt", "ready", "pro",
        "cold", "heart", "practised", "practiced", "rehearsed", "solid", "tight",
    ]

    /// The suggestions in `output` that add something to `chips`: tags the library has (in
    /// its spelling), a proficiency floor when none is stated and `words` mention one,
    /// opener / closer tags when none is stated and `words` mention a slot. Each comes back
    /// with origin `.suggested`.
    public static func suggestions(
        from output: SetRequestOutput,
        words: String,
        libraryTags: [String],
        existing chips: [RequestChip],
    ) -> [RequestChip] {
        let clean = output.normalized(libraryTags: libraryTags)
        let sent = Set(Token.split(words).map(\.word))
        let asksSlot = !sent.isDisjoint(with: slotCues)
        let asksProficiency = !sent.isDisjoint(with: proficiencyCues)
        var kinds: [SetChip] = clean.includeTags.map { .tag($0) }
            + clean.excludeTags.map { .excludeTag($0) }
        if asksProficiency {
            switch clean.minProficiency {
            case .any: break
            case .ready: kinds.append(.proficiency(.ready))
            case .pro: kinds.append(.proficiency(.pro))
            }
        }
        if asksSlot, !clean.openerTag.isEmpty {
            kinds.append(.opener(tag: clean.openerTag))
        }
        if asksSlot, !clean.closerTag.isEmpty {
            kinds.append(.closer(tag: clean.closerTag))
        }
        let taken = Set(chips.map(\.id))
        var seen: Set<String> = []
        return kinds.compactMap { kind in
            guard !taken.contains(kind.slot), seen.insert(kind.slot).inserted else { return nil }
            return RequestChip(kind, origin: .suggested)
        }
    }
}
