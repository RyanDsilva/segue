#if os(macOS)
    import AppKit
    import Setlists
    import SwiftUI

    /// Part colours for the timeline strip and the rows' leading edge (direction C). Darker
    /// in light mode and lighter in dark mode, so a label in `ground` on a region keeps 4.5:1
    /// either way; Increase Contrast deepens them further. They cycle after four parts.
    enum PartPalette {
        private struct Swatch {
            var light: NSColor
            var dark: NSColor
            var lightHigh: NSColor
            var darkHigh: NSColor
        }

        private static let swatches: [Swatch] = [
            Swatch(
                light: rgb(0x2563C9),
                dark: rgb(0x6E9BF2),
                lightHigh: rgb(0x1A4A9E),
                darkHigh: rgb(0x9BBAF7),
            ),
            Swatch(
                light: rgb(0x9A5B00),
                dark: rgb(0xE5A94A),
                lightHigh: rgb(0x744400),
                darkHigh: rgb(0xF2C680),
            ),
            Swatch(
                light: rgb(0x0B7A6F),
                dark: rgb(0x45C4B3),
                lightHigh: rgb(0x075C53),
                darkHigh: rgb(0x7FDACE),
            ),
            Swatch(
                light: rgb(0x6D45C2),
                dark: rgb(0xA990F0),
                lightHigh: rgb(0x52309A),
                darkHigh: rgb(0xC6B5F6),
            ),
        ]

        /// The colour of part `index` (0 = the first part).
        static func color(_ index: Int) -> Color {
            let swatch = swatches[((index % swatches.count) + swatches.count) % swatches.count]
            return Color(nsColor: NSColor(name: nil) { appearance in
                let dark = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
                let high = NSWorkspace.shared.accessibilityDisplayShouldIncreaseContrast
                switch (dark, high) {
                case (false, false): return swatch.light
                case (true, false): return swatch.dark
                case (false, true): return swatch.lightHigh
                case (true, true): return swatch.darkHigh
                }
            })
        }

        private static func rgb(_ hex: Int) -> NSColor {
            NSColor(
                srgbRed: CGFloat((hex >> 16) & 0xFF) / 255,
                green: CGFloat((hex >> 8) & 0xFF) / 255,
                blue: CGFloat(hex & 0xFF) / 255,
                alpha: 1,
            )
        }
    }

    /// The part each entry belongs to (0 for the rows before the first break; a break row
    /// belongs to the part it opens).
    func partIndexes(_ entries: [SetlistEntry]) -> [Int] {
        var part = 0
        return entries.map { entry in
            if entry.isBreak {
                part += 1
            }
            return part
        }
    }

    /// The builder's total (direction C): the whole set's time, the "N unknown" button, the
    /// target, and a proportional strip with one coloured region per part, the unknown
    /// lengths hatched at the end of their part, each break as a gap (its intermission to
    /// scale) and the target as a line.
    struct SetlistTimelineView: View {
        let timing: SetlistTiming
        let setlist: Setlist
        let library: LibraryViewModel
        @Environment(\.colorSchemeContrast) private var contrast

        var body: some View {
            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    TotalText(
                        total: timing.total,
                        unknown: timing.unknownCount,
                        estimated: timing.isEstimated,
                        note: timing.changeoverNote,
                        font: SchibstedGrotesk.bold.font(size: 15),
                        identifier: AccessibilityID.setlistTotal,
                    )
                    if !timing.unknownItemIds.isEmpty {
                        MissingTimesButton(
                            count: timing.unknownItemIds.count,
                            setlist: setlist,
                            library: library,
                            followsTotal: timing.total > 0,
                        )
                    }
                    Spacer(minLength: 8)
                    Text(targetText)
                        .font(SchibstedGrotesk.medium.font(size: 14))
                        .foregroundStyle(Theme.color.muted)
                        .lineLimit(1)
                        .truncationMode(.head)
                        .accessibilityIdentifier(AccessibilityID.setlistTarget)
                }
                strip
                    .frame(height: 22)
                    .accessibilityElement(children: .ignore)
                    // A drawn summary, so VoiceOver reads it as an image with its label
                    // (without a role the accessibility audit reports "Unknown role").
                    .accessibilityAddTraits(.isImage)
                    .accessibilityLabel(stripSummary)
                    .accessibilityIdentifier(AccessibilityID.setlistTimeline)
            }
        }

        private var targetText: String {
            guard let target = timing.target else { return "no target" }
            let over = timing.total - target
            return over > 0
                ? "\(SetlistTiming.format(over)) over \(SetlistTiming.format(target))"
                : "target \(SetlistTiming.format(target))"
        }

        /// "Set 1 12:00, break 15:00, Set 2 8:52 + 1 unknown, target 45:00".
        private var stripSummary: String {
            var parts: [String] = []
            for (index, part) in timing.parts.enumerated() {
                if let breakId = part.breakItemId,
                   let length = timing.items.first(where: { $0.itemId == breakId })?.time
                {
                    parts.append("break \(SetlistTiming.format(length.seconds))")
                }
                if index > 0 || !part.songItemIds.isEmpty {
                    parts.append("\(part.label ?? "Set 1") \(part.totalText)")
                }
            }
            if let target = timing.target {
                parts.append("target \(SetlistTiming.format(target))")
            }
            return parts.joined(separator: ", ")
        }

        private var segments: [Segment] {
            var result: [Segment] = []
            for (index, part) in timing.parts.enumerated() {
                if let breakId = part.breakItemId {
                    let pause = timing.items.first { $0.itemId == breakId }?.time?.seconds ?? 0
                    result.append(Segment(kind: .gap, seconds: pause, part: index, label: nil))
                }
                if part.total > 0 {
                    result.append(Segment(
                        kind: .known,
                        seconds: part.total,
                        part: index,
                        label: part.label ?? (timing.parts.count > 1 ? "Set 1" : nil),
                    ))
                }
                if part.unknownCount > 0 {
                    result.append(Segment(
                        kind: .unknown(part.unknownCount),
                        seconds: 0,
                        part: index,
                        label: nil,
                    ))
                }
            }
            return result
        }

        private var strip: some View {
            GeometryReader { proxy in
                let layout = Self.layout(
                    segments,
                    width: proxy.size.width,
                    scale: max(timing.total, timing.target ?? 0),
                )
                ZStack(alignment: .topLeading) {
                    RoundedRectangle(cornerRadius: 5, style: .continuous)
                        .fill(Theme.color.line)
                    ForEach(layout, id: \.offset) { placed in
                        segmentView(placed.segment)
                            .frame(width: max(placed.width, 0), height: proxy.size.height)
                            .offset(x: placed.offset)
                    }
                    if let target = timing.target, target > 0 {
                        let scale = max(timing.total, target)
                        Rectangle()
                            .fill(Theme.color.ink)
                            .frame(width: 2, height: proxy.size.height + 8)
                            .offset(
                                x: min(proxy.size.width * target / scale, proxy.size.width) - 1,
                                y: -4,
                            )
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
                .overlay {
                    if contrast == .increased {
                        RoundedRectangle(cornerRadius: 5, style: .continuous)
                            .strokeBorder(Theme.color.ink, lineWidth: 1)
                    }
                }
            }
        }

        @ViewBuilder
        private func segmentView(_ segment: Segment) -> some View {
            switch segment.kind {
            case .known:
                PartPalette.color(segment.part)
                    .overlay(alignment: .leading) {
                        if let label = segment.label {
                            Text(label.uppercased())
                                .font(SchibstedGrotesk.bold.font(size: 10.5))
                                .tracking(0.6)
                                .foregroundStyle(Theme.color.ground)
                                .lineLimit(1)
                                .padding(.leading, 6)
                        }
                    }
                    .clipped()
            case .unknown:
                HatchPattern(color: PartPalette.color(segment.part))
            case .gap:
                Theme.color.ground.opacity(0.0001)
            }
        }

        struct Segment {
            enum Kind: Equatable {
                case known
                case unknown(Int)
                case gap
            }

            var kind: Kind
            var seconds: TimeInterval
            var part: Int
            var label: String?
        }

        struct Placed {
            var segment: Segment
            var offset: CGFloat
            var width: CGFloat
        }

        /// Hatched unknowns get a fixed width per song (they have no time to scale);
        /// breaks without an intermission a thin gap; the rest shares the width by time.
        static func layout(_ segments: [Segment], width: CGFloat, scale: TimeInterval)
            -> [Placed]
        {
            let fixed: (Segment) -> CGFloat? = { segment in
                switch segment.kind {
                case let .unknown(count): CGFloat(min(count, 3)) * 10
                case .gap where segment.seconds <= 0: 4
                default: nil
                }
            }
            let reserved = segments.compactMap(fixed).reduce(0, +)
            let timed = max(width - reserved, 0)
            let total = max(scale, segments.filter { fixed($0) == nil }.map(\.seconds).reduce(0, +))
            var offset: CGFloat = 0
            return segments.map { segment in
                let segmentWidth = fixed(segment)
                    ?? (total > 0 ? timed * CGFloat(segment.seconds / total) : 0)
                defer { offset += segmentWidth }
                return Placed(segment: segment, offset: offset, width: segmentWidth)
            }
        }
    }

    /// Diagonal stripes in a part's colour: songs in that part with no time yet.
    private struct HatchPattern: View {
        let color: Color

        var body: some View {
            Canvas { context, size in
                var path = Path()
                var x: CGFloat = -size.height
                while x < size.width {
                    path.move(to: CGPoint(x: x, y: size.height))
                    path.addLine(to: CGPoint(x: x + size.height, y: 0))
                    x += 5
                }
                context.stroke(path, with: .color(color), lineWidth: 1.5)
            }
        }
    }

    /// A total in the phase 2 notation, drawn as its known part ("38:20") with the
    /// "+ 2 unknown" part as the `MissingTimesButton` beside it; VoiceOver and the E2E
    /// suite read the whole notation ("38:20 + 2 unknown"; no "≥" on totals, R189).
    struct TotalText: View {
        let total: TimeInterval
        let unknown: Int
        var estimated = false
        let note: String?
        let font: Font
        let identifier: String

        var body: some View {
            Text(visible)
                .font(font)
                .foregroundStyle(Theme.color.ink)
                .fixedSize()
                .help(note ?? "")
                .accessibilityLabel(SetlistTiming.totalText(
                    total: total,
                    unknown: unknown,
                    estimated: estimated,
                ))
                .accessibilityValue(SetlistTiming.spokenTotal(
                    total: total,
                    unknown: unknown,
                    estimated: estimated,
                ))
                .accessibilityIdentifier(identifier)
        }

        /// "38:20" or "~38:20" (a known time rests on default chord lengths), or
        /// nothing when only unknowns are left (the button says it).
        private var visible: String {
            let prefix = estimated && total > 0 ? SetlistTiming.estimatedPrefix : ""
            guard unknown > 0 else { return prefix + SetlistTiming.format(total) }
            guard total > 0 else { return "" }
            return prefix + SetlistTiming.format(total)
        }
    }

    /// "+ 2 unknown ▾", tinted red: opens the list of exactly the songs with no time.
    struct MissingTimesButton: View {
        let count: Int
        let setlist: Setlist
        let library: LibraryViewModel
        /// A part's song slots; nil for the whole set.
        var within: Set<SetlistItemID>?
        /// Drawn after a known total ("38:20 + 2 unknown"): starts with "+ ".
        var followsTotal = true
        @State private var isOpen = false

        var body: some View {
            Button {
                isOpen.toggle()
            } label: {
                HStack(spacing: 4) {
                    Text(followsTotal ? "+ \(count) unknown" : "\(count) unknown")
                    Image(systemName: "chevron.down")
                        .font(.system(size: 8, weight: .bold))
                }
                .font(SchibstedGrotesk.semiBold.font(size: 12))
                .foregroundStyle(Theme.color.cueText)
                .padding(.horizontal, 8)
                .frame(height: 22)
                .background(Capsule().fill(Theme.color.cue.opacity(isOpen ? 0.18 : 0.09)))
                .overlay(Capsule().strokeBorder(Theme.color.cue.opacity(0.55), lineWidth: 1))
                .contentShape(Capsule())
            }
            .buttonStyle(.plain)
            .fixedSize()
            .help("Songs with no time")
            .accessibilityLabel(count == 1 ? "1 song with no time" :
                "\(count) songs with no time")
            .accessibilityIdentifier(AccessibilityID.setlistUnknownButton)
            .popover(isPresented: $isOpen, arrowEdge: .bottom) {
                MissingTimesList(setlist: setlist, library: library, within: within)
            }
        }
    }
#endif
