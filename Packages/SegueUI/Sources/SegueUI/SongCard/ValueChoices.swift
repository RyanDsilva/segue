import MusicTheory

// The value vocabularies the song card and Text mode's value help share (R81).

/// Common time signatures, in the order the card and Text mode offer them.
enum TimeSignatures {
    static let common = ["4/4", "3/4", "6/8"]
    static let more = ["2/4", "12/8", "5/4", "7/8", "2/2"]
}

/// Every major and minor key in its conventional spelling, for the key picker and Text
/// mode's `{key: }` suggestions.
enum KeyChoices {
    static func keys(_ mode: KeyMode) -> [SongKey] {
        (0 ..< 12).map { SongKey(canonical: PitchClass($0), mode: mode) }
    }

    /// Keys whose name starts with `prefix` (case-insensitive on the tonic), the detected
    /// key first.
    static func matching(_ prefix: String, detected: SongKey?) -> [SongKey] {
        let typed = prefix.trimmingCharacters(in: .whitespaces)
        let all = (detected.map { [$0] } ?? []) + keys(.major) + keys(.minor)
        var seen = Set<String>()
        return all.filter { key in
            guard seen.insert(key.name).inserted else { return false }
            return typed.isEmpty || key.name.lowercased().hasPrefix(typed.lowercased())
        }
    }
}
