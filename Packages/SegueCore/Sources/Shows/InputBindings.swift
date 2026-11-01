// Phase 2 frozen interface (docs/phases/2-interfaces.md). Owner: unit A (core), C (keys).

import Foundation
import Support

/// Modifier keys of a keystroke.
public struct KeyModifiers: OptionSet, Sendable, Hashable, Codable {
    public let rawValue: Int

    public init(rawValue: Int) {
        self.rawValue = rawValue
    }

    public static let command = Self(rawValue: 1 << 0)
    public static let option = Self(rawValue: 1 << 1)
    public static let control = Self(rawValue: 1 << 2)
    /// Recorded for named keys only. For character keys the character already carries Shift
    /// ("+" rather than Shift-"="), so input sources drop it there.
    public static let shift = Self(rawValue: 1 << 3)

    private static let names: [(String, Self)] = [
        ("command", .command), ("option", .option), ("control", .control), ("shift", .shift),
    ]

    /// Encoded as names (`["command"]`) so `bindings.json` is readable and hand-editable.
    public init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        let names = try container.decode([String].self)
        var value: Self = []
        for name in names {
            guard let match = Self.names.first(where: { $0.0 == name }) else {
                throw DecodingError.dataCorruptedError(
                    in: container,
                    debugDescription: "Unknown modifier: \(name)",
                )
            }
            value.insert(match.1)
        }
        self = value
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(Self.names.filter { contains($0.1) }.map(\.0))
    }
}

/// A key with modifiers, independent of AppKit/SwiftUI so bindings stay in Core.
public struct KeyStroke: Sendable, Hashable, Codable, CustomStringConvertible {
    /// A named key (`KeyStroke.rightArrow` ...) or a single lowercased character ("k", "[").
    public var key: String
    public var modifiers: KeyModifiers

    public init(_ key: String, modifiers: KeyModifiers = []) {
        self.key = key.count == 1 ? key.lowercased() : key
        self.modifiers = modifiers
    }

    public static let rightArrow = "rightArrow"
    public static let leftArrow = "leftArrow"
    public static let upArrow = "upArrow"
    public static let downArrow = "downArrow"
    public static let pageUp = "pageUp"
    public static let pageDown = "pageDown"
    public static let home = "home"
    public static let end = "end"
    public static let space = "space"
    public static let escape = "escape"
    public static let returnKey = "return"

    /// "Cmd-K", "Right Arrow", "[" for help and the bindings list.
    public var description: String {
        var parts: [String] = []
        if modifiers.contains(.control) {
            parts.append("Ctrl")
        }
        if modifiers.contains(.option) {
            parts.append("Opt")
        }
        if modifiers.contains(.shift) {
            parts.append("Shift")
        }
        if modifiers.contains(.command) {
            parts.append("Cmd")
        }
        parts.append(key.count == 1 ? key.uppercased() : key)
        return parts.joined(separator: "-")
    }
}

/// A raw input event a binding matches. Phase 6 adds a `.midi` case here; input sources
/// produce triggers, the table maps them.
///
/// On disk a trigger is a flat object keyed by its source: `{"key": "k", "modifiers":
/// ["command"]}` (phase 6 adds e.g. `{"midi": ...}`).
public enum InputTrigger: Sendable, Hashable, Codable {
    case key(KeyStroke)

    private enum CodingKeys: String, CodingKey {
        case key
        case modifiers
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let key = try container.decode(String.self, forKey: .key)
        let modifiers = try container.decodeIfPresent(KeyModifiers.self, forKey: .modifiers)
        self = .key(KeyStroke(key, modifiers: modifiers ?? []))
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case let .key(stroke):
            try container.encode(stroke.key, forKey: .key)
            if !stroke.modifiers.isEmpty {
                try container.encode(stroke.modifiers, forKey: .modifiers)
            }
        }
    }
}

/// One trigger -> command mapping.
public struct InputBinding: Sendable, Hashable, Codable {
    public var trigger: InputTrigger
    public var command: LiveCommand

    public init(_ trigger: InputTrigger, _ command: LiveCommand) {
        self.trigger = trigger
        self.command = command
    }
}

/// The binding table: defaults in code, optionally overridden by `bindings.json` in
/// Application Support (`{"schemaVersion": 2, "bindings": [...]}`). A file binding replaces
/// the default binding of the same trigger; triggers it does not mention keep their default.
public struct InputBindingTable: Sendable, Hashable {
    /// 2 (P9-2): the same shape as 1, bumped when `toggleSingerView` arrived so a Segue that
    /// predates it reads a file naming it best effort instead of rejecting the whole file.
    public static let currentSchemaVersion = 2
    public static let fileName = "bindings.json"

    public private(set) var bindings: [InputBinding]

    public init(_ bindings: [InputBinding]) {
        self.bindings = bindings
    }

    /// The command bound to `trigger` (the last binding wins).
    public func command(for trigger: InputTrigger) -> LiveCommand? {
        bindings.last { $0.trigger == trigger }?.command
    }

    /// Every trigger bound to `command`, in table order (for help text).
    public func triggers(for command: LiveCommand) -> [InputTrigger] {
        var seen: Set<InputTrigger> = []
        return bindings.compactMap { binding in
            guard self.command(for: binding.trigger) == command,
                  seen.insert(binding.trigger).inserted
            else { return nil }
            return binding.trigger
        }
    }

    /// The table with `overrides` applied on top (same trigger replaces).
    public func merged(with overrides: [InputBinding]) -> Self {
        let replaced = Set(overrides.map(\.trigger))
        return Self(bindings.filter { !replaced.contains($0.trigger) } + overrides)
    }

    /// Defaults plus the file at `url`, if it exists. A malformed file throws (the caller
    /// reports it and uses `defaults`).
    public static func load(from url: URL?, fileSystem: any FileSystem) throws -> Self {
        try loadReporting(from: url, fileSystem: fileSystem).table
    }

    /// What `loadReporting` found.
    public struct Loaded: Sendable, Equatable {
        public var table: InputBindingTable
        /// Set when the file was written by a newer Segue (its `schemaVersion`): the
        /// bindings this version understands were applied, `skipped` others were ignored.
        public var newerSchema: Int?
        public var skipped: Int
    }

    /// Defaults plus the file at `url`, honouring its `schemaVersion`: the current version
    /// (or a file without one, the pre-versioned format) decodes strictly and a malformed
    /// file throws, except that a binding to a retired command (`LiveCommand.retired`) is
    /// skipped silently; a newer version is read best effort (bindings with triggers or commands
    /// this version does not know are skipped and counted), never rewritten.
    public static func loadReporting(from url: URL?, fileSystem: any FileSystem) throws
        -> Loaded
    {
        guard let url, fileSystem.fileExists(at: url) else {
            return Loaded(table: defaults, newerSchema: nil, skipped: 0)
        }
        let data = try fileSystem.readData(at: url)
        switch try migrator.migrate(data) {
        case let .current(json), let .migrated(json, _):
            let file = try SegueJSON.decode(File.self, from: json)
            let bindings = file.bindings.compactMap(\.binding)
            return Loaded(table: defaults.merged(with: bindings), newerSchema: nil, skipped: 0)
        case let .newer(found):
            let file = try SegueJSON.decode(LenientFile.self, from: data)
            let bindings = file.bindings.compactMap(\.binding)
            return Loaded(
                table: defaults.merged(with: bindings),
                newerSchema: found,
                skipped: file.bindings.count - bindings.count,
            )
        }
    }

    /// Versions 0 (no `schemaVersion`) and 1 have the same shape as version 2.
    private static let migrator = SchemaMigrator(
        currentVersion: currentSchemaVersion,
        steps: [0: { _ in }, 1: { _ in }],
    )

    private struct File: Decodable {
        var schemaVersion: Int
        var bindings: [StrictBinding]
    }

    /// A current-version binding: strict, but nil for a retired command.
    private struct StrictBinding: Decodable {
        var binding: InputBinding?

        private enum CodingKeys: String, CodingKey {
            case command
        }

        init(from decoder: any Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            let command = try container.decode(String.self, forKey: .command)
            binding = LiveCommand.retired.contains(command) ? nil : try InputBinding(from: decoder)
        }
    }

    /// A newer file: each binding decoded on its own.
    private struct LenientFile: Decodable {
        var bindings: [LenientBinding]
    }

    private struct LenientBinding: Decodable {
        var binding: InputBinding?

        init(from decoder: any Decoder) throws {
            binding = try? InputBinding(from: decoder)
        }
    }

    /// The default keys (phase 2 spec, "Command layer"). Pedals usually send PgUp/PgDn or
    /// arrows, so they work with these.
    public static let defaults = Self(
        [
            key(KeyStroke.rightArrow, .next),
            key(KeyStroke.space, .next),
            key(KeyStroke.leftArrow, .previous),
            // Page turners send Page Down/Up: they cross song boundaries (R45).
            key(KeyStroke.pageDown, .pageForward),
            key(KeyStroke.downArrow, .scrollPageDown),
            key(KeyStroke.pageUp, .pageBack),
            key(KeyStroke.upArrow, .scrollPageUp),
            key(KeyStroke.home, .restartScroll),
            key("a", .toggleAutoScroll),
            key("[", .scrollSlower),
            key("]", .scrollFaster),
            key("k", .openSearch, [.command]),
            key("/", .openSearch),
            key("r", .playNextRequest),
            key("q", .toggleRequests),
            key("x", .skipCurrent),
            key("s", .toggleSidebar),
            key("c", .cycleColumns),
            key("=", .zoomIn, [.command]),
            key("+", .zoomIn, [.command]),
            key("-", .zoomOut, [.command]),
            key("0", .resetZoom, [.command]),
            key(".", .endShow, [.command]),
            key("?", .showKeys),
            key("m", .toggleMetronome),
            // Rehearsals only; does nothing in a show (R118).
            key("k", .toggleMetronomeClick),
            // Sections (R148): 1-9 jump to a shown pass; L loops one (rehearsals only).
            key("1", .jumpToPass1),
            key("2", .jumpToPass2),
            key("3", .jumpToPass3),
            key("4", .jumpToPass4),
            key("5", .jumpToPass5),
            key("6", .jumpToPass6),
            key("7", .jumpToPass7),
            key("8", .jumpToPass8),
            key("9", .jumpToPass9),
            key("l", .toggleLoop),
            // Play along with bass, chords and click (P8-6 10.4; rehearsals only).
            key("p", .togglePlayAlong),
            // The bass-note view, for anyone (P8-4, R158 Q3).
            key("b", .toggleBassNotes),
            // Saved fills as mini tabs, for anyone (P8-7 section 14.2).
            key("t", .toggleFillTab),
            // Lyrics only, chords hidden (P9-2 section 6.1).
            key("v", .toggleSingerView),
        ],
    )

    private static func key(
        _ name: String,
        _ command: LiveCommand,
        _ modifiers: KeyModifiers = [],
    ) -> InputBinding {
        InputBinding(.key(KeyStroke(name, modifiers: modifiers)), command)
    }
}
