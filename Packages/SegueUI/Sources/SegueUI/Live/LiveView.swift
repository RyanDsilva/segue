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
        nonisolated static let bodyVerticalPadding: CGFloat = 20
        /// Fixed chrome heights, so the body (and the layout viewport) follows from the
        /// screen size alone.
        nonisolated static let headerHeight: CGFloat = 76
        nonisolated static let footerHeight: CGFloat = 64

        /// The layout viewport for a stage of `size` (the body minus its padding).
        static func viewport(for size: CGSize, topInset: CGFloat) -> LayoutSize {
            let body = size.height - headerHeight - footerHeight - topInset
            return LayoutSize(
                width: max(0, size.width - 2 * horizontalPadding),
                height: max(0, body - 2 * bodyVerticalPadding),
            )
        }

        var body: some View {
            VStack(spacing: 0) {
                StageHeader(session: session)
                    .frame(height: Self.headerHeight)
                    .padding(.top, topInset)
                songArea
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
            .overlay(alignment: .top) { searchOverlay }
            .overlay { endConfirm }
            .overlay(alignment: .bottom) { statusLine }
            .overlay(alignment: .topTrailing) { modeIndicator }
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier(AccessibilityID.liveView)
            .onContinuousHover { phase in
                if case .active = phase {
                    revealStatus()
                }
            }
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
            .padding(.vertical, Self.bodyVerticalPadding)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .contentShape(Rectangle())
            .clipped()
            .onGeometryChange(for: LayoutSize.self) { proxy in
                LayoutSize(
                    width: max(0, proxy.size.width - 2 * Self.horizontalPadding),
                    height: max(0, proxy.size.height - 2 * Self.bodyVerticalPadding),
                )
            } action: { size in
                session.setViewport(size)
            }
        }

        @ViewBuilder private var songContent: some View {
            if let plan = session.plan {
                TimelineView(.animation(paused: !session.isAutoScrolling)) { _ in
                    let now = session.context.scrollClock.now()
                    let fraction = session.scrollFraction(at: now)
                    StagePlanView(plan: plan)
                        .equatable()
                        .offset(y: -session.scrollOffset(at: now))
                        .frame(
                            width: plan.viewport.width,
                            height: plan.viewport.height,
                            alignment: .topLeading,
                        )
                        .clipped()
                        .mask { Self.edgeMask(moreBelow: fraction < 0.999 && plan.needsScroll) }
                        .accessibilityElement(children: .contain)
                        .overlay(alignment: .topLeading) {
                            // The layout state as one element (VoiceOver, the E2E suite).
                            Color.clear
                                .frame(width: 1, height: 1)
                                .accessibilityElement()
                                .accessibilityLabel(Self.bodyValue(plan, fraction: fraction))
                                .accessibilityIdentifier(AccessibilityID.liveBody)
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
            }
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

        @ViewBuilder private var statusLine: some View {
            if statusVisible || session.notice != nil {
                StageStatusLine(session: session)
                    .padding(.bottom, 92)
                    .transition(.opacity)
            }
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
            ZStack {
                Theme.color.ground.opacity(0.7)
                VStack(alignment: .leading, spacing: 14) {
                    Text("End the \(noun)?")
                        .font(Theme.font.sectionHeading)
                        .foregroundStyle(Theme.color.ink)
                    Text(
                        session.kind == .gig
                            ? "The set is saved to the gig log. You can review any reordering next."
                            : "Song timings are kept. Rehearsals never go in the gig log.",
                    )
                    .font(Theme.font.body)
                    .foregroundStyle(Theme.color.muted)
                    .fixedSize(horizontal: false, vertical: true)
                    HStack(spacing: 10) {
                        Spacer()
                        Button("Keep Playing (Esc)") { session.overlay = nil }
                            .buttonStyle(.segueSecondary)
                        Button("End \(noun.capitalized) (Return)") { session.confirmEnd() }
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
