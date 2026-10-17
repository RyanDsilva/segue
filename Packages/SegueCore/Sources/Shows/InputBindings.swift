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

/// A raw input event a binding matches. Phase 6 adds `.hid` (pedals that are not keyboards)
/// and `.midi` cases here; input sources produce triggers, the table maps them.
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
/// Application Support (`{"schemaVersion": 1, "bindings": [...]}`). A file binding replaces
/// the default binding of the same trigger; triggers it does not mention keep their default.
public struct InputBindingTable: Sendable, Hashable {
    public static let currentSchemaVersion = 1
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
        guard let url, fileSystem.fileExists(at: url) else { return defaults }
        let file = try SegueJSON.decode(File.self, from: fileSystem.readData(at: url))
        return defaults.merged(with: file.bindings)
    }

    private struct File: Codable {
        var schemaVersion: Int
        var bindings: [InputBinding]
    }

    /// The default keys (phase 2 spec, "Command layer"). Pedals usually send PgUp/PgDn or
    /// arrows, so they work with these.
    public static let defaults = Self(
        [
            key(KeyStroke.rightArrow, .next),
            key(KeyStroke.space, .next),
            key(KeyStroke.leftArrow, .previous),
            key(KeyStroke.pageDown, .scrollPageDown),
            key(KeyStroke.downArrow, .scrollPageDown),
            key(KeyStroke.pageUp, .scrollPageUp),
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
            key("o", .toggleCollapseRepeats),
            key("=", .zoomIn, [.command]),
            key("+", .zoomIn, [.command]),
            key("-", .zoomOut, [.command]),
            key("0", .resetZoom, [.command]),
            key(".", .endShow, [.command]),
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
