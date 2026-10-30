#if os(macOS)
    import AppKit
    import LiveLayout
    import Shows
    import SwiftUI

    /// The stage (brand.md section 7, mockup "C Precise"): header (cue dot, title, "G, capo
    /// 2, 96", set progress and elapsed time), the song body drawn from the `LayoutPlan`, and
    /// the "Up next" footer. Overlays: set order drawer (S), request queue (Q), quick search
    /// (Cmd-K or /) and the end-show confirmation (Cmd-.). Keys arrive through
    /// `LiveKeyInput`; nothing on stage needs the mouse.
    struct LiveView: View {
        let session: LiveSession
        /// Extra top padding so the header clears the camera housing on notched displays.
        var topInset: CGFloat = 0
        @Environment(\.accessibilityReduceMotion) private var reduceMotion
        @State private var statusVisible = false
        @State private var statusHideTask: Task<Void, Never>?

        nonisolated static let horizontalPadding: CGFloat = 40
        /// Space between the header and the song.
        nonisolated static let bodyTopPadding: CGFloat = 20
        /// The status line's (and the metronome's) height.
        nonisolated static let statusLineHeight: CGFloat = 30
        /// The band between the song and the footer that the status line and the metronome
        /// sit in, so they never cover a lyric line: the line plus 8pt above and below.
        nonisolated static let statusBandHeight: CGFloat = statusLineHeight + 2 * 8
        /// Fixed chrome heights, so the body (and the layout viewport) follows from the
        /// screen size alone.
        nonisolated static let headerHeight: CGFloat = 76
        nonisolated static let footerHeight: CGFloat = 64
        /// The section map band under the header (R147): 48 pt chips plus 10 pt below,
        /// always reserved so the viewport never changes between songs.
        nonisolated static let mapHeight: CGFloat = 58
        /// How far left of the song area the pass marks may draw (the current pass's dot sits
        /// before the gutter name, in the side padding).
        nonisolated static let markSlack: CGFloat = 24

        /// The layout viewport for a stage of `size` (the body minus its padding and the
        /// status band).
        static func viewport(for size: CGSize, topInset: CGFloat) -> LayoutSize {
            let body = size.height - headerHeight - mapHeight - footerHeight - topInset
            return LayoutSize(
                width: max(0, size.width - 2 * horizontalPadding),
                height: max(0, body - bodyTopPadding - statusBandHeight),
            )
        }

        var body: some View {
            VStack(spacing: 0) {
                StageHeader(session: session)
                    .frame(height: Self.headerHeight)
                    .padding(.top, topInset)
                mapBand
                songArea
                statusBand
                StageFooter(session: session)
                    .frame(height: Self.footerHeight)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Theme.color.ground)
            .overlay(alignment: .leading) {
                if session.showsDrawer {
                    SetOrderDrawer(session: session)
                        .padding(.top, topInset)
                }
            }
            .overlay(alignment: .trailing) {
                if session.showsRequests {
                    RequestPanel(session: session)
                        .padding(.top, topInset)
                }
            }
            .overlay(alignment: .top) { jumpToast }
            .overlay(alignment: .top) { searchOverlay }
            .overlay { endConfirm }
            .overlay { keysOverlay }
            .overlay(alignment: .top) { problemBanner }
            .overlay(alignment: .topTrailing) { modeIndicator }
            .overlay(alignment: .bottomTrailing) { metronome }
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier(AccessibilityID.liveView)
            .onContinuousHover { phase in
                if case .active = phase {
                    revealStatus()
                }
            }
        }

        // MARK: Section map

        /// The map strip (R147): the shown passes of the current song, current one lit, in
        /// Live and Rehearsal. Empty (but reserved) in a break, past the end, for an
        /// unavailable song and for fewer than two passes.
        private var mapBand: some View {
            ZStack {
                let passes = session.mapPasses
                if !passes.isEmpty {
                    TimelineView(.animation(paused: !session.isAutoScrolling)) { _ in
                        let now = session.context.scrollClock.now()
                        StageMapStrip(
                            passes: passes,
                            current: session.currentPass(at: now),
                            progress: session.passProgress(at: now),
                            loop: session.loopPass,
                            onJump: { session.jump(toPass: $0) },
                        )
                    }
                }
            }
            .frame(maxWidth: .infinity)
            .frame(height: Self.mapHeight)
        }

        /// "Jumped to ...", 14 pt below the map, centred over the song.
        private var jumpToast: some View {
            StageJumpToast(message: session.jumpToast)
                .padding(.top, Self.headerHeight + Self.mapHeight + topInset + 14)
        }

        // MARK: Song body

        private var songArea: some View {
            // The clear ground keeps the area (and its measured size) even before there is a
            // plan to draw: an empty view would collapse and never report its geometry.
            ZStack(alignment: .topLeading) {
                Color.clear
                songContent
            }
            .padding(.horizontal, Self.horizontalPadding)
            .padding(.top, Self.bodyTopPadding)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .contentShape(Rectangle())
            .clipped()
            .onGeometryChange(for: LayoutSize.self) { proxy in
                LayoutSize(
                    width: max(0, proxy.size.width - 2 * Self.horizontalPadding),
                    height: max(0, proxy.size.height - Self.bodyTopPadding),
                )
            } action: { size in
                session.setViewport(size)
            }
        }

        @ViewBuilder private var songContent: some View {
            if let info = session.state.record.currentBreak {
                // Between parts (R104): the interstitial until Next.
                StageBreakView(info: info, nextTitle: session.state.current?.item.title)
            } else if let plan = session.plan {
                TimelineView(.animation(paused: !session.isAutoScrolling)) { _ in
                    let now = session.context.scrollClock.now()
                    let fraction = session.scrollFraction(at: now)
                    StagePlanView(plan: plan)
                        .equatable()
                        .overlay(alignment: .topLeading) {
                            StagePassOverlay(
                                plan: plan,
                                current: session.currentPass(at: now),
                                loop: session.loopPass,
                            )
                        }
                        .offset(y: -session.scrollOffset(at: now))
                        .frame(
                            width: plan.viewport.width,
                            height: plan.viewport.height,
                            alignment: .topLeading,
                        )
                        // Clipped by the mask, which reaches into the side padding so the
                        // current pass's dot before the gutter shows.
                        .mask {
                            Self.edgeMask(moreBelow: fraction < 0.999 && plan.needsScroll)
                                .padding(.horizontal, -Self.markSlack)
                        }
                        .accessibilityElement(children: .contain)
                        .overlay(alignment: .topLeading) {
                            // The layout state for the E2E suite only: VoiceOver users never
                            // hear this machine report (WS2b 4.9.2).
                            if UITesting.isActive {
                                Color.clear
                                    .frame(width: 1, height: 1)
                                    .accessibilityElement()
                                    .accessibilityLabel(Self.bodyValue(plan, fraction: fraction))
                                    .accessibilityIdentifier(AccessibilityID.liveBody)
                            }
                        }
                }
                .id(session.state.current?.item.itemId)
                .transition(.opacity)
                .animation(
                    reduceMotion ? nil : .linear(duration: 0.12),
                    value: session.state.current?.item.itemId,
                )
            } else if session.state.current == nil {
                endOfSet
            } else if session.currentModel == nil {
                songUnavailable
            }
        }

        /// The current song never loaded (its file was gone or unreadable when it became
        /// current): say so instead of a blank stage.
        private var songUnavailable: some View {
            VStack(alignment: .leading, spacing: 10) {
                Text("Song unavailable")
                    .font(Theme.font.sectionHeading)
                    .foregroundStyle(Theme.color.ink)
                Text(
                    "“\(session.state.current?.item.title ?? "This song")” could not be read "
                        + "from the library folder. Press → to continue.",
                )
                .font(Theme.font.body)
                .foregroundStyle(Theme.color.muted)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier(AccessibilityID.liveSongUnavailable)
        }

        /// Fades the last 32pt when more of the song is below, so a row cut by the edge
        /// reads as "continues" rather than as a stray chord line.
        static func edgeMask(moreBelow: Bool) -> some View {
            VStack(spacing: 0) {
                Rectangle()
                LinearGradient(
                    colors: [.black, moreBelow ? .clear : .black],
                    startPoint: .top,
                    endPoint: .bottom,
                )
                .frame(height: 32)
            }
        }

        /// "lyric 30 fits scroll 0.50": the plan's lyric size, fit and scroll position, for
        /// the E2E suite and VoiceOver.
        static func bodyValue(_ plan: LayoutPlan, fraction: Double) -> String {
            let fit = switch plan.fit {
            case .fits: "fits"
            case .scrollsAtMinimum: "scrolls at minimum"
            case .scrollsZoomed: "scrolls zoomed"
            }
            let size = plan.lyricSize.formatted(.number.precision(.fractionLength(0 ... 1)))
            let position = fraction.formatted(.number.precision(.fractionLength(2)))
            return "lyric \(size) \(fit) scroll \(position) columns \(plan.columns.count)"
        }

        private var endOfSet: some View {
            VStack(alignment: .leading, spacing: 10) {
                Text("That was the last song.")
                    .font(Theme.font.sectionHeading)
                    .foregroundStyle(Theme.color.ink)
                Text(
                    "Cmd-K finds another song. Cmd-. ends the "
                        + (session.kind == .gig ? "show." : "rehearsal."),
                )
                .font(Theme.font.body)
                .foregroundStyle(Theme.color.muted)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier(AccessibilityID.liveEndOfSet)
        }

        // MARK: Overlays

        @ViewBuilder private var searchOverlay: some View {
            if session.overlay == .search {
                QuickSearchOverlay(session: session)
                    .padding(.top, 96 + topInset)
            }
        }

        @ViewBuilder private var keysOverlay: some View {
            if session.overlay == .keys {
                KeysOverlay(groups: KeyHelp.groups(session.context.bindings))
                    .padding(.vertical, Self.headerHeight + topInset)
            }
        }

        @ViewBuilder private var endConfirm: some View {
            if session.overlay == .endConfirm {
                EndShowConfirmation(session: session)
            }
        }

        /// The brief mode chip under the header's right edge (no motion beyond a 150 ms fade,
        /// none with Reduce Motion).
        private var modeIndicator: some View {
            Group {
                if let text = session.indicator {
                    StageChip(text: text)
                        .background(
                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .fill(Theme.color.surfaceAlt),
                        )
                        .accessibilityIdentifier(AccessibilityID.liveIndicator)
                        .transition(.opacity)
                }
            }
            .padding(.top, Self.headerHeight + topInset + 8)
            .padding(.trailing, Self.horizontalPadding)
            .animation(reduceMotion ? nil : .linear(duration: 0.15), value: session.indicator)
        }

        /// The metronome (R90, R118) at the right end of the status band, above the footer;
        /// hidden while the request panel covers that corner.
        @ViewBuilder private var metronome: some View {
            if !session.showsRequests {
                StageMetronomeView(metronome: session.metronome)
                    .frame(height: Self.statusLineHeight)
                    .padding(.trailing, Self.horizontalPadding - 6)
                    .padding(
                        .bottom,
                        Self.footerHeight + (Self.statusBandHeight - Self.statusLineHeight) / 2,
                    )
            }
        }

        /// Failures that stay up until resolved (the show file is not being written, song
        /// settings not saved), under the header so they are never missed.
        @ViewBuilder private var problemBanner: some View {
            let problems = LiveSession.Problem.allCases.compactMap { session.problems[$0] }
            if !problems.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(problems, id: \.self) { problem in
                        HStack(alignment: .firstTextBaseline, spacing: 8) {
                            Circle().fill(Theme.color.cue).frame(width: 8, height: 8)
                                .accessibilityHidden(true)
                            Text(problem)
                                .foregroundStyle(Theme.color.ink)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
                .font(Theme.font.label)
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .frame(maxWidth: 760, alignment: .leading)
                .background(StagePanelBackground(radius: 8))
                .padding(.top, Self.headerHeight + topInset + 4)
                .accessibilityElement(children: .combine)
                .accessibilityIdentifier(AccessibilityID.liveProblem)
            }
        }

        /// The reserved band under the song: the status line fades in here, so it never
        /// covers the last lyric line (and showing it never changes the layout).
        private var statusBand: some View {
            // The mini neck (P8-4 7.3) takes the band's left end; the status line then
            // starts 16 pt after it so the two never overlap.
            let neck = session.showsBassNeck && !session.showsRequests
            return ZStack {
                if neck {
                    StageBassNeckBand(session: session)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                if statusVisible || session.notice != nil {
                    StageStatusLine(session: session)
                        .frame(height: Self.statusLineHeight)
                        .padding(.horizontal, Self.horizontalPadding)
                        .padding(.leading, neck ? StageBassNeck.width + 16 : 0)
                        .transition(.opacity)
                }
            }
            .frame(maxWidth: .infinity)
            .frame(height: Self.statusBandHeight)
        }

        /// The status line fades in on mouse move and out 3 s later (no motion with Reduce
        /// Motion).
        private func revealStatus() {
            let animation: Animation? = reduceMotion ? nil : .linear(duration: 0.15)
            withAnimation(animation) { statusVisible = true }
            statusHideTask?.cancel()
            statusHideTask = Task { @MainActor in
                try? await Task.sleep(for: .seconds(3))
                guard !Task.isCancelled else { return }
                withAnimation(animation) { statusVisible = false }
            }
        }
    }

    /// "End the show?" over the stage: Return ends, Esc keeps playing.
    private struct EndShowConfirmation: View {
        let session: LiveSession

        var body: some View {
            let noun = session.kind == .gig ? "show" : "rehearsal"
            let quitting = session.quitsAfterEnding
            ZStack {
                Theme.color.ground.opacity(0.7)
                VStack(alignment: .leading, spacing: 14) {
                    Text(title(noun: noun, quitting: quitting))
                        .font(Theme.font.sectionHeading)
                        .foregroundStyle(Theme.color.ink)
                    Text(detail)
                        .font(Theme.font.body)
                        .foregroundStyle(Theme.color.muted)
                        .fixedSize(horizontal: false, vertical: true)
                    HStack(spacing: 10) {
                        Spacer()
                        Button("Keep Playing (Esc)") { session.cancelEnd() }
                            .buttonStyle(.segueSecondary)
                        Button(
                            quitting ? "End and Quit (Return)" : "End \(noun.capitalized) (Return)",
                        ) { session.confirmEnd() }
                            .buttonStyle(.seguePrimary)
                            .accessibilityIdentifier(AccessibilityID.liveEndConfirm)
                    }
                    .controlSize(.large)
                }
                .padding(24)
                .frame(width: 460)
                .background(StagePanelBackground())
            }
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier(AccessibilityID.liveEndDialog)
        }
    }

    private extension EndShowConfirmation {
        func title(noun: String, quitting: Bool) -> String {
            if session.scope == .song {
                return quitting ? "End this song and quit Segue?" : "End this song?"
            }
            return quitting ? "End the \(noun) and quit Segue?" : "End the \(noun)?"
        }

        var detail: String {
            if session.scope == .song {
                return "A single song is never added to the gig log."
            }
            return session.kind == .gig
                ? "The set is saved to the gig log. You can review any reordering next."
                : "Song timings are kept. Rehearsals never go in the gig log."
        }
    }

    /// The raised surface of stage panels: `surfaceAlt` with a `controlBorder` hairline.
    struct StagePanelBackground: View {
        var radius: CGFloat = 12

        var body: some View {
            RoundedRectangle(cornerRadius: radius, style: .continuous)
                .fill(Theme.color.surfaceAlt)
                .overlay {
                    RoundedRectangle(cornerRadius: radius, style: .continuous)
                        .strokeBorder(Theme.color.controlBorder, lineWidth: 1)
                }
        }
    }
#endif
