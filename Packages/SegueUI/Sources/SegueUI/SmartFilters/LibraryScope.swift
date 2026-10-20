import Library

/// What part of the library the song list shows before the search and chips apply: every
/// song, a saved smart filter's songs, or the built-in "Missing essentials" (R110).
public enum LibraryScope: Equatable, Sendable {
    case all
    case smartFilter(SmartFilter)
    case missingEssentials

    /// The built-in filter's name (R110).
    public static let missingEssentialsName = "Missing essentials"

    /// The list's title ("Library" for every song).
    public var title: String {
        switch self {
        case .all: "Library"
        case let .smartFilter(filter): filter.name
        case .missingEssentials: Self.missingEssentialsName
        }
    }

    /// Whether the list is narrowed to a filter.
    public var isFiltered: Bool {
        self != .all
    }

    /// The matcher for this scope against `playStats`; nil for every song.
    public func matcher(playStats: [SongID: PlayStats]) -> SongFilter? {
        switch self {
        case .all: nil
        case let .smartFilter(filter): filter.conditions.compiled(playStats: playStats)
        case .missingEssentials: SongFilter(missingEssentials: true)
        }
    }
}

extension LibraryViewModel {
    /// `records` narrowed to the current scope.
    func scoped(_ records: [SongRecord]) -> [SongRecord] {
        guard let matcher = scope.matcher(playStats: playStats) else { return records }
        return records.filter(matcher.matches)
    }
}
