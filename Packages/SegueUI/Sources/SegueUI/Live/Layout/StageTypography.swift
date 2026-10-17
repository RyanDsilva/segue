// Phase 2 frozen interface (docs/phases/2-interfaces.md). Owner: unit B; used by C.
//
// The one place that decides which face each `TextRole` uses on stage. The layout engine
// measures with `StageTextMetrics` and the stage view draws with `StageTypography.font`, both
// from the same table, so the drawn text is exactly what auto-fit measured.
//
// Drawing contract for the stage view: draw each `PlacedText` on one line, unwrapped, at its
// `x` and baseline with `StageTypography.font(run.role, size: run.size)` (for example
// `Canvas` + `context.draw(Text(...), at:anchor:)` aligned by `firstBaseline`, or a
// `.fixedSize()` `Text`). Never let SwiftUI wrap or truncate a run.

import CoreText
import Foundation
import LiveLayout
import SwiftUI

/// The face a role is set in.
enum StageFace: Hashable, Sendable {
    case schibsted(SchibstedGrotesk)
    /// The system monospaced face (SF Mono), for tab/grid lines.
    case monospaced

    /// Brand type scale (docs/brand.md section 6-7).
    static func of(_ role: TextRole) -> Self {
        switch role {
        case .chord, .cue, .sectionLabel: .schibsted(.bold)
        case .collapsedRepeat, .lyric: .schibsted(.regular)
        case .comment, .labelDetail, .note: .schibsted(.medium)
        case .verbatim: .monospaced
        }
    }

    func ctFont(size: Double) -> CTFont {
        switch self {
        case let .schibsted(face):
            _ = FontRegistration.registerBundledFonts()
            return CTFontCreateWithName(face.rawValue as CFString, size, nil)
        case .monospaced:
            #if os(macOS)
                return NSFont.monospacedSystemFont(ofSize: size, weight: .regular) as CTFont
            #else
                return UIFont.monospacedSystemFont(ofSize: size, weight: .regular) as CTFont
            #endif
        }
    }

    func font(size: Double) -> Font {
        switch self {
        case let .schibsted(face): face.font(size: size)
        case .monospaced: .system(size: size, weight: .regular, design: .monospaced)
        }
    }
}

/// Core Text measurement with the bundled Schibsted Grotesk faces (and the system monospaced
/// face for `.verbatim`). Thread-safe; caches fonts per (role, size) and chord-sized widths.
/// Glyphs missing from Schibsted (Devanagari, emoji) are measured in Core Text's fallback
/// font, as they are drawn.
public struct StageTextMetrics: TextMeasuring {
    public init() {}

    public func width(of text: String, role: TextRole, size: Double) -> Double {
        if let cached = Self.cache.width(text, role, size) {
            return cached
        }
        let width = CTLineGetTypographicBounds(line(text, role: role, size: size), nil, nil, nil)
        Self.cache.store(width, text, role, size)
        return width
    }

    public func prefixWidths(
        of text: String,
        utf16Offsets: [Int],
        role: TextRole,
        size: Double,
    ) -> [Double] {
        if let cached = Self.cache.prefixes(text, utf16Offsets, role, size) {
            return cached
        }
        let line = line(text, role: role, size: size)
        let total = CTLineGetTypographicBounds(line, nil, nil, nil)
        let length = text.utf16.count
        let widths = utf16Offsets.map { offset -> Double in
            if offset <= 0 {
                return 0
            }
            if offset >= length {
                return Double(total)
            }
            return Double(CTLineGetOffsetForStringIndex(line, offset, nil))
        }
        Self.cache.store(widths, text, utf16Offsets, role, size)
        return widths
    }

    public func extents(of role: TextRole) -> FontExtents {
        Self.cache.extents(role) {
            let font = StageFace.of(role).ctFont(size: 100)
            // Ink top: the tallest of capitals and ascenders.
            let sample = Array("Hdlbkf".utf16)
            var glyphs = [CGGlyph](repeating: 0, count: sample.count)
            CTFontGetGlyphsForCharacters(font, sample, &glyphs, sample.count)
            let box = CTFontGetBoundingRectsForGlyphs(font, .default, glyphs, nil, glyphs.count)
            return FontExtents(
                ascent: CTFontGetAscent(font) / 100,
                descent: CTFontGetDescent(font) / 100,
                inkTop: min(box.maxY, CTFontGetAscent(font)) / 100,
            )
        }
    }

    /// The glyph-path bounds of `text` set as one line (fallback fonts included, as
    /// drawn), at the reference size of 100pt.
    public func inkExtents(of text: String, role: TextRole) -> InkExtents {
        if let cached = Self.cache.ink(text, role) {
            return cached
        }
        let bounds = CTLineGetBoundsWithOptions(
            line(text, role: role, size: 100),
            .useGlyphPathBounds,
        )
        let ink = bounds.isNull || bounds.isEmpty
            ? InkExtents(top: 0, bottom: 0)
            : InkExtents(top: max(0, bounds.maxY) / 100, bottom: max(0, -bounds.minY) / 100)
        Self.cache.store(ink, text, role)
        return ink
    }

    /// The font measurement and drawing use for `role` at `size`.
    public static func ctFont(_ role: TextRole, size: Double) -> CTFont {
        cache.font(role, size)
    }

    private func line(_ text: String, role: TextRole, size: Double) -> CTLine {
        let attributes = [kCTFontAttributeName: Self.cache.font(role, size)] as CFDictionary
        let string = CFAttributedStringCreate(nil, text as CFString, attributes)
            ?? NSAttributedString(string: text)
        return CTLineCreateWithAttributedString(string)
    }

    private static let cache = MetricsCache()
}

/// Fonts per (role, size), vertical extents per role, widths of short strings (chords repeat
/// on every line) and per-line prefix widths (so re-planning a song for zoom or a new
/// viewport skips Core Text). Bounded: each table is cleared past `limit` entries. Unchecked
/// Sendable: every access to the dictionaries holds `lock`, and `CTFont` is immutable and
/// thread-safe.
private final class MetricsCache: @unchecked Sendable {
    private struct Key: Hashable {
        var role: TextRole
        var size: Double
    }

    private struct WidthKey: Hashable {
        var text: String
        var role: TextRole
        var size: Double
    }

    private let limit = 4096
    private let lock = NSLock()
    private var fonts: [Key: CTFont] = [:]
    private var extentsByRole: [TextRole: FontExtents] = [:]
    private var widths: [WidthKey: Double] = [:]
    private var prefixWidths: [PrefixKey: [Double]] = [:]
    private var inks: [InkKey: InkExtents] = [:]

    private struct InkKey: Hashable {
        var text: String
        var role: TextRole
    }

    func ink(_ text: String, _ role: TextRole) -> InkExtents? {
        lock.withLock { inks[InkKey(text: text, role: role)] }
    }

    func store(_ ink: InkExtents, _ text: String, _ role: TextRole) {
        lock.withLock {
            if inks.count >= limit {
                inks.removeAll()
            }
            inks[InkKey(text: text, role: role)] = ink
        }
    }

    private struct PrefixKey: Hashable {
        var text: String
        var offsets: [Int]
        var role: TextRole
        var size: Double
    }

    func prefixes(_ text: String, _ offsets: [Int], _ role: TextRole, _ size: Double) -> [Double]? {
        lock
            .withLock {
                prefixWidths[PrefixKey(text: text, offsets: offsets, role: role, size: size)]
            }
    }

    func store(
        _ widths: [Double],
        _ text: String,
        _ offsets: [Int],
        _ role: TextRole,
        _ size: Double,
    ) {
        lock.withLock {
            if prefixWidths.count >= limit {
                prefixWidths.removeAll()
            }
            prefixWidths[PrefixKey(text: text, offsets: offsets, role: role, size: size)] = widths
        }
    }

    func font(_ role: TextRole, _ size: Double) -> CTFont {
        let key = Key(role: role, size: size)
        if let font = lock.withLock({ fonts[key] }) {
            return font
        }
        let font = StageFace.of(role).ctFont(size: size)
        lock.withLock {
            if fonts.count >= limit {
                fonts.removeAll()
            }
            fonts[key] = font
        }
        return font
    }

    func extents(_ role: TextRole, compute: () -> FontExtents) -> FontExtents {
        if let cached = lock.withLock({ extentsByRole[role] }) {
            return cached
        }
        let value = compute()
        lock.withLock { extentsByRole[role] = value }
        return value
    }

    func width(_ text: String, _ role: TextRole, _ size: Double) -> Double? {
        lock.withLock { widths[WidthKey(text: text, role: role, size: size)] }
    }

    func store(_ width: Double, _ text: String, _ role: TextRole, _ size: Double) {
        guard text.utf16.count <= 16 else { return }
        lock.withLock {
            if widths.count >= limit {
                widths.removeAll()
            }
            widths[WidthKey(text: text, role: role, size: size)] = width
        }
    }
}

/// SwiftUI fonts matching `StageTextMetrics`.
public enum StageTypography {
    /// The face for `role` at point `size` (the plan's lyric/chord size, or the fixed role
    /// sizes in `LayoutStyle`; every `PlacedText` carries its own `size`).
    public static func font(_ role: TextRole, size: Double) -> Font {
        StageFace.of(role).font(size: size)
    }
}
