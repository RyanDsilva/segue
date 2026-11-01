#if os(macOS)
    import AppKit
    import ChordPro
    import Library
    import LiveLayout
    import SwiftUI

    /// The section map (R147, mockup A1): one chip per shown pass in played order, sized by
    /// the pass's length, named "Chorus 2/3", the current one filled with a progress bar,
    /// played ones dimmed, the looped one ringed in coral. A click (or 1-9) jumps. The
    /// `.preview` style is the Arrange Sections miniature (P8-3): smaller, never interactive.
    struct StageMapStrip: View {
        enum Style: Equatable {
            case stage
            case preview

            struct Metrics: Equatable {
                var chipHeight: CGFloat
                var below: CGFloat
                var sidePadding: CGFloat
                var gap: CGFloat
                var minimum: CGFloat
                var padding: EdgeInsets
                var label: CGFloat
                var number: CGFloat
                var showsModeLine: Bool
                var isInteractive: Bool
            }

            var metrics: Metrics {
                switch self {
                case .stage:
                    Metrics(
                        chipHeight: 48,
                        below: 10,
                        sidePadding: 40,
                        gap: 4,
                        minimum: 52,
                        padding: EdgeInsets(top: 6, leading: 9, bottom: 0, trailing: 9),
                        label: 15,
                        number: 12,
                        showsModeLine: true,
                        isInteractive: true,
                    )
                case .preview:
                    Metrics(
                        chipHeight: 32,
                        below: 8,
                        sidePadding: 16,
                        gap: 3,
                        minimum: 30,
                        padding: EdgeInsets(top: 4, leading: 6, bottom: 0, trailing: 6),
                        label: 11.5,
                        number: 10,
                        showsModeLine: false,
                        isInteractive: false,
                    )
                }
            }

            /// The band's height: the chips plus the space below them.
            var height: CGFloat {
                metrics.chipHeight + metrics.below
            }
        }

        let passes: [PlanPass]
        /// The current pass's index; nil for none.
        let current: Int?
        /// How far through the current pass, 0 ... 1.
        let progress: Double
        /// The looped pass's index (rehearsal).
        let loop: Int?
        var style: Style = .stage
        var onJump: ((Int) -> Void)?
        /// A medley's member titles by segment (P9-3 9.3, R187 map B): each member's chips sit
        /// in a labelled container; empty for a song.
        var members: [String] = []
        /// The member the stage shows (its container is lit).
        var currentMember: Int?

        @Environment(\.accessibilityReduceMotion) private var reduceMotion
        @State private var width: CGFloat = 0

        var body: some View {
            let metrics = style.metrics
            let available = max(0, width - 2 * metrics.sidePadding)
            let widths = Self.widths(passes.map(\.weight), in: available, metrics: metrics)
            VStack(spacing: 0) {
                Group {
                    if members.count > 1, let widths = groupedWidths(available) {
                        groupedRow(widths)
                    } else if let widths {
                        row(widths)
                    } else {
                        scrolling
                    }
                }
                .frame(height: metrics.chipHeight)
                .padding(.horizontal, metrics.sidePadding)
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity)
            .frame(height: style.height)
            .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { width = $0 }
            .accessibilityElement(children: .contain)
            .accessibilityLabel("Section map")
            .accessibilityIdentifier(AccessibilityID.liveMap)
        }

        private func row(_ widths: [CGFloat]) -> some View {
            HStack(spacing: style.metrics.gap) {
                ForEach(passes.indices, id: \.self) { index in
                    chip(index).frame(width: widths[index])
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }

        /// Too many chips for the width at their minimum: the strip scrolls and keeps the
        /// current chip in view.
        private var scrolling: some View {
            ScrollViewReader { proxy in
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: style.metrics.gap) {
                        ForEach(passes.indices, id: \.self) { index in
                            chip(index)
                                .frame(width: style.metrics.minimum)
                                .id(index)
                        }
                    }
                }
                .onChange(of: current, initial: true) { _, current in
                    guard let current else { return }
                    withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.2)) {
                        proxy.scrollTo(current, anchor: .center)
                    }
                }
            }
        }

        func chip(_ index: Int) -> some View {
            StageMapChip(
                pass: passes[index],
                state: state(of: index),
                isLooping: loop == index,
                progress: index == current ? progress : (state(of: index) == .played ? 1 : 0),
                style: style,
                onJump: onJump.map { jump in { jump(index) } },
                member: members.indices.contains(passes[index].segment)
                    ? members[passes[index].segment] : nil,
            )
        }

        func state(of index: Int) -> StageMapChip.State {
            guard let current else { return .upcoming }
            if index == current {
                return .current
            }
            return index < current ? .played : .upcoming
        }

        /// Chip widths proportional to `weights` with a floor of `minimum`, filling
        /// `available`; nil when the chips do not fit at their minimum.
        static func widths(
            _ weights: [Double],
            in available: CGFloat,
            metrics: Style.Metrics,
        ) -> [CGFloat]? {
            let count = CGFloat(weights.count)
            guard !weights.isEmpty else { return [] }
            let room = available - (count - 1) * metrics.gap
            guard count * metrics.minimum <= room else { return nil }
            // Water-fill: chips below the floor take the floor; the rest share what is left
            // in proportion to their weight.
            var floored = Set<Int>()
            while true {
                let free = weights.indices.filter { !floored.contains($0) }
                let space = room - CGFloat(floored.count) * metrics.minimum
                let total = free.reduce(0.0) { $0 + max(weights[$1], 0) }
                func share(_ index: Int) -> CGFloat {
                    total > 0
                        ? space * CGFloat(max(weights[index], 0) / total)
                        : space / CGFloat(max(free.count, 1))
                }
                let below = free.filter { share($0) < metrics.minimum }
                if below.isEmpty {
                    return weights.indices
                        .map { floored.contains($0) ? metrics.minimum : share($0) }
                }
                floored.formUnion(below)
            }
        }
    }

    /// One chip of the map.
    struct StageMapChip: View {
        enum State: Equatable {
            case upcoming
            case current
            case played
        }

        let pass: PlanPass
        let state: State
        let isLooping: Bool
        let progress: Double
        let style: StageMapStrip.Style
        let onJump: (() -> Void)?
        /// The medley member the pass belongs to, read in its label (P9-3 9.3).
        var member: String?

        @Environment(\.accessibilityReduceMotion) private var reduceMotion
        @State private var isHovered = false

        private var metrics: StageMapStrip.Style.Metrics {
            style.metrics
        }

        var body: some View {
            let shape = RoundedRectangle(cornerRadius: 7, style: .continuous)
            content
                .padding(metrics.padding)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .background(state == .current ? Theme.color.surfaceAlt : .clear, in: shape)
                .overlay(alignment: .leading) { stripe }
                .overlay(alignment: .bottomLeading) { progressBar }
                .overlay(alignment: .topTrailing) { hint }
                .clipShape(shape)
                .overlay { shape.strokeBorder(border, lineWidth: 1) }
                .contentShape(shape)
                .onHover { hovering in
                    guard metrics.isInteractive else { return }
                    withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.12)) {
                        isHovered = hovering
                    }
                }
                .onTapGesture { onJump?() }
                .accessibilityElement(children: .ignore)
                .accessibilityAddTraits(metrics.isInteractive ? .isButton : [])
                .accessibilityLabel(Self.spokenLabel(pass) + (member.map { ", \($0)" } ?? ""))
                .accessibilityValue(spokenValue)
                .accessibilityHint(metrics.isInteractive ? "Jumps to this section" : "")
                .accessibilityAction { onJump?() }
                .accessibilityIdentifier(AccessibilityID.liveMapChip(pass.index + 1))
        }

        private var content: some View {
            VStack(alignment: .leading, spacing: 1) {
                ViewThatFits(in: .horizontal) {
                    label(pass.name.title)
                    label(pass.name.short)
                }
                if metrics.showsModeLine {
                    Text(Self.modeLine(pass.mode))
                        .font(SchibstedGrotesk.bold.font(size: 10.5))
                        .tracking(0.06 * 10.5)
                        .foregroundStyle(Theme.color.muted)
                        .lineLimit(1)
                }
            }
        }

        private func label(_ title: String) -> some View {
            HStack(alignment: .firstTextBaseline, spacing: 3) {
                Text(title)
                    .font(SchibstedGrotesk.bold.font(size: metrics.label))
                    .foregroundStyle(state == .played ? Theme.color.muted : Theme.color.ink)
                if let number = pass.name.number {
                    Text("\(number)/\(pass.name.total)")
                        .font(SchibstedGrotesk.semiBold.font(size: metrics.number))
                        .foregroundStyle(
                            state == .played ? Theme.color.indicatorOff : Theme.color.muted,
                        )
                }
            }
            .lineLimit(1)
            .fixedSize()
        }

        /// The kind stripe at the left edge, in the section band colour (R158 Q6).
        private var stripe: some View {
            UnevenRoundedRectangle(
                topLeadingRadius: 0,
                bottomLeadingRadius: 0,
                bottomTrailingRadius: 2,
                topTrailingRadius: 2,
                style: .continuous,
            )
            .fill(Color(nsColor: SectionBandStyle.dynamicColor(for: pass.kind ?? .custom(""))))
            .frame(width: 3)
            .padding(.top, 7)
            .padding(.bottom, 9)
            .accessibilityHidden(true)
        }

        @ViewBuilder private var progressBar: some View {
            if style == .stage, state != .upcoming {
                GeometryReader { proxy in
                    Rectangle()
                        .fill(state == .played ? Theme.color.indicatorOff : Theme.color.cue)
                        .frame(width: proxy.size.width * min(max(progress, 0), 1), height: 3)
                        .frame(maxHeight: .infinity, alignment: .bottom)
                }
                .accessibilityHidden(true)
            }
        }

        /// The number key, on hover (passes after the ninth have none).
        @ViewBuilder private var hint: some View {
            if metrics.isInteractive, isHovered, pass.index < 9 {
                Text("\(pass.index + 1)")
                    .font(SchibstedGrotesk.semiBold.font(size: 11))
                    .foregroundStyle(Theme.color.muted)
                    .padding(.horizontal, 4)
                    .overlay {
                        RoundedRectangle(cornerRadius: 4, style: .continuous)
                            .strokeBorder(Theme.color.controlBorder, lineWidth: 1)
                    }
                    .padding(.top, 5)
                    .padding(.trailing, 6)
                    .transition(.opacity)
                    .accessibilityHidden(true)
            }
        }

        private var border: Color {
            if isLooping {
                return Theme.color.cue.opacity(0.7)
            }
            return state == .current || isHovered ? Theme.color.controlBorder : Theme.color.line
        }

        private var spokenValue: String {
            let base = switch state {
            case .current: "current"
            case .played: "played"
            case .upcoming: "upcoming"
            }
            return isLooping ? base + ", looping" : base
        }

        /// "Chorus, 2 of 3, chords only".
        static func spokenLabel(_ pass: PlanPass) -> String {
            var parts = [pass.name.title]
            if let badge = pass.name.badgeText {
                parts.append(badge)
            }
            switch pass.mode {
            case .chordsOnly: parts.append("chords only")
            case .firstLine: parts.append("first line only")
            case .full, .skip: break
            }
            return parts.joined(separator: ", ")
        }

        /// "CHORDS", "1ST LINE", or a non-breaking space for Full (keeps the height).
        static func modeLine(_ mode: PassMode) -> String {
            switch mode {
            case .chordsOnly: "CHORDS"
            case .firstLine: "1ST LINE"
            case .full, .skip: "\u{00A0}"
            }
        }
    }
#endif
