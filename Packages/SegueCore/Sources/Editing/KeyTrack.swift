// P8-7a (docs/phases/8-workstreams/P8-7-time-model-and-fills.md section 5.3, R167 Q3,
// R168 Q2). Positional `{key}`, `{time}` and `{tempo}`: each applies from where it is
// written. The rule lives here so the render model (spelling, Nashville) and Library's
// `SongTimeline` (walk-ups, play-along, fills) read one definition.

import ChordPro
import MusicTheory

/// A metadata directive as written, where it is.
public struct WrittenDirective: Sendable, Hashable {
    /// Canonical name (`key`, `time`, `tempo`).
    public var name: String
    public var value: String
    public var path: BlockPath

    public init(name: String, value: String, path: BlockPath) {
        self.name = name
        self.value = value
        self.path = path
    }
}

public extension SongDocument {
    /// Every directive named `name` that has a value, in source order (top level and inside
    /// sections, as `Metadata` collects them).
    func writtenDirectives(named name: String) -> [WrittenDirective] {
        var result: [WrittenDirective] = []
        for (index, block) in blocks.enumerated() {
            switch block {
            case let .directive(directive):
                if directive.name == name, let value = directive.value {
                    result.append(WrittenDirective(
                        name: name,
                        value: value,
                        path: BlockPath(block: index),
                    ))
                }
            case let .section(section):
                for (item, inner) in section.items.enumerated() {
                    if case let .directive(directive) = inner, directive.name == name,
                       let value = directive.value
                    {
                        result.append(WrittenDirective(
                            name: name,
                            value: value,
                            path: BlockPath(block: index, item: item),
                        ))
                    }
                }
            case .blank, .chorusRef, .commentDirective, .fileComment, .line:
                break
            }
        }
        return result
    }

    /// The positional changes of `name` after the one `Metadata` reads as the song's value
    /// (`songValue`: the first written, or the first that parses for `{tempo}`): every later
    /// directive of that name whose value `parse` accepts, in source order. An unreadable
    /// later value is skipped (its diagnostic already flags it).
    func positionalChanges<Value>(
        named name: String,
        songValue: PositionalSongValue,
        parse: (String) -> Value?,
    ) -> [(path: BlockPath, value: Value)] {
        let written = writtenDirectives(named: name)
        let first: Int? = switch songValue {
        case .firstWritten: written.isEmpty ? nil : 0
        case .firstParsed: written.firstIndex { parse($0.value) != nil }
        }
        guard let first else { return [] }
        return written[(first + 1)...].compactMap { directive in
            parse(directive.value).map { (directive.path, $0) }
        }
    }
}

/// Which written directive is the song's own value (the one `Metadata` keeps).
public enum PositionalSongValue: Sendable, Hashable {
    /// `{key}`, `{time}`: the first one written, readable or not.
    case firstWritten
    /// `{tempo}`: the first readable one.
    case firstParsed
}

/// The written `{key}` in effect along a song (P8-7 section 5.3): the song's key
/// (`KeyContext`, the first `{key}` or the detected key) until a later `{key}` changes it,
/// from the first line after that directive in source order. Spelling, Nashville numbers,
/// walk-ups and fills follow it; the library, filters and the song header keep the song's key
/// (R168 Q2).
public struct KeyTrack: Sendable, Hashable {
    public struct Change: Sendable, Hashable {
        public var path: BlockPath
        public var key: SongKey

        public init(path: BlockPath, key: SongKey) {
            self.path = path
            self.key = key
        }
    }

    public var song: KeyContext
    /// Later readable `{key}`s in source order.
    public var changes: [Change]

    public init(song: KeyContext, changes: [Change]) {
        self.song = song
        self.changes = changes
    }

    public init(document: SongDocument) {
        song = KeyContext(document: document)
        changes = document.positionalChanges(
            named: "key",
            songValue: .firstWritten,
            parse: SongKey.init(parsing:),
        ).map { Change(path: $0.path, key: $0.value) }
    }

    /// The written key in effect for a block at `path` (a line, a `{chorus}`).
    public func key(at path: BlockPath) -> SongKey? {
        changes.last { $0.path < path }?.key ?? song.writtenKey
    }

    /// The key context for a block at `path`: the song's own (declared or detected) until a
    /// change, then that `{key}` as declared.
    public func context(at path: BlockPath) -> KeyContext {
        guard let change = changes.last(where: { $0.path < path }) else { return song }
        return KeyContext(declared: change.key, detection: nil)
    }
}
