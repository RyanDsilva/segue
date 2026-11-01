#if os(macOS)
    import Editing
    import Foundation
    import LiveLayout
    import Observation
    import Shows
    import SwiftUI

    /// What the Singer Screen shows (P9-2c 6.13): its own singer plan of the current song,
    /// laid out at its own display's size with the singer style and zoom (never the main
    /// stage's `V`, `B`, `T` or zoom), notes hidden, scrolled to the performer's pass and
    /// progress on the main stage.
    @MainActor
    @Observable
    final class SingerScreenModel {
        let live: LiveSession
        /// The screen's body area (its display less the header, map and padding).
        private(set) var viewport = LayoutSize(width: 0, height: 0)
        @ObservationIgnored private var cache: (key: PlanKey, plan: LayoutPlan?)?

        init(live: LiveSession) {
            self.live = live
        }

        func setViewport(_ size: LayoutSize) {
            if size != viewport {
                viewport = size
            }
        }

        /// What a plan is laid out from: a new song, a new version of it, a new size or a
        /// singer setting re-lays it out.
        private struct PlanKey: Equatable {
            var item: ShowItemID
            var source: String
            var slot: StageSlot
            var viewport: LayoutSize
            var settings: LiveSettings
            var columns: Int?
        }

        /// The current song's singer plan; nil in a break, past the end, for an unavailable
        /// song and before the view has a size.
        var plan: LayoutPlan? {
            guard live.state.record.currentBreak == nil, let current = live.state.current,
                  let song = current.song, viewport.width > 0, viewport.height > 0
            else { return nil }
            let prefs = live.prefs(for: song)
            let settings = live.context.settings.settings
            let key = PlanKey(
                item: current.item.itemId,
                source: song.source,
                slot: StageSlot(current.item),
                viewport: viewport,
                settings: settings,
                columns: prefs.columns,
            )
            if let cache, cache.key == key {
                return cache.plan
            }
            let (request, _) = StageRequest.make(
                song: song,
                slot: StageSlot(current.item),
                prefs: prefs,
                settings: settings,
                minLyricSize: settings.minLyricSize,
                viewport: viewport,
                singer: true,
            )
            let plan = LayoutEngine.plan(request, metrics: StageTextMetrics())
            cache = (key, plan)
            return plan
        }

        /// The scroll offset that puts the main stage's pass, at its progress, at the reading
        /// line here.
        func offset(in plan: LayoutPlan, at now: Date) -> Double {
            guard let leader = live.plan else { return 0 }
            return SingerScreenFollow.offset(
                following: leader,
                at: live.scrollOffset(at: now),
                pinned: live.pinnedPass,
                in: plan,
            )
        }

        /// The header's key line: the sounding key at the current pass, "Key A, 96".
        var keyLine: String? {
            live.singerKeyLine
        }

        /// The current song's title (the item's title when the song is unavailable).
        var title: String {
            live.state.current.map { slot in
                slot.song.map(SongSummary.title) ?? slot.item.title
            } ?? live.setlistName
        }
    }

    /// The Singer Screen, mirroring the stage (R187 direction A): the stage header (cue dot,
    /// title, singer key line) and the map strip on top, the singer plan below. Nothing on it
    /// is interactive.
    struct SingerScreenView: View {
        let model: SingerScreenModel

        nonisolated static let headerHeight: CGFloat = LiveView.headerHeight
        nonisolated static let mapHeight: CGFloat = LiveView.mapHeight
        nonisolated static let horizontalPadding: CGFloat = LiveView.horizontalPadding
        nonisolated static let bodyTopPadding: CGFloat = LiveView.bodyTopPadding
        nonisolated static let bottomPadding: CGFloat = 24

        var body: some View {
            VStack(spacing: 0) {
                header
                    .frame(height: Self.headerHeight)
                content
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Theme.color.ground)
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier(AccessibilityID.singerScreen)
        }

        private var header: some View {
            HStack(alignment: .center, spacing: 14) {
                Circle()
                    .fill(Theme.color.cue)
                    .frame(width: 10, height: 10)
                    .accessibilityHidden(true)
                Text(model.title)
                    .font(Theme.font.title)
                    .tracking(Theme.tracking.title * 28)
                    .foregroundStyle(Theme.color.ink)
                    .lineLimit(1)
                    .layoutPriority(1)
                if let line = model.keyLine, model.live.state.record.currentBreak == nil {
                    Text(line)
                        .font(SchibstedGrotesk.medium.font(size: 16))
                        .foregroundStyle(Theme.color.muted)
                        .lineLimit(1)
                }
                Spacer(minLength: 24)
            }
            .padding(.horizontal, Self.horizontalPadding)
        }

        @ViewBuilder private var content: some View {
            let live = model.live
            if let info = live.state.record.currentBreak {
                // Between parts: the next song's title, as on the stage.
                StageBreakView(info: info, nextTitle: live.state.current?.item.title)
            } else if live.state.current == nil {
                Text("End of set")
                    .font(Theme.font.sectionHeading)
                    .foregroundStyle(Theme.color.muted)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                TimelineView(.animation(paused: !live.isAutoScrolling)) { _ in
                    let now = live.context.scrollClock.now()
                    VStack(spacing: 0) {
                        map(now: now)
                        songBody(now: now)
                    }
                }
            }
        }

        private func map(now: Date) -> some View {
            ZStack {
                if let passes = model.plan?.passes, passes.count >= 2 {
                    StageMapStrip(
                        passes: passes,
                        current: model.live.currentPass(at: now),
                        progress: model.live.passProgress(at: now),
                        loop: model.live.loopPass,
                    )
                    .allowsHitTesting(false)
                }
            }
            .frame(maxWidth: .infinity)
            .frame(height: Self.mapHeight)
        }

        private func songBody(now: Date) -> some View {
            ZStack(alignment: .topLeading) {
                Color.clear
                if let plan = model.plan {
                    let offset = model.offset(in: plan, at: now)
                    StagePlanView(plan: plan, style: .singer)
                        .equatable()
                        .overlay(alignment: .topLeading) {
                            StagePassOverlay(
                                plan: plan,
                                current: model.live.currentPass(at: now),
                                loop: model.live.loopPass,
                                style: .singer,
                            )
                        }
                        .offset(y: -offset)
                        .frame(
                            width: plan.viewport.width,
                            height: plan.viewport.height,
                            alignment: .topLeading,
                        )
                        .mask {
                            LiveView.edgeMask(moreBelow: offset < plan.overflow - 0.5)
                                .padding(.horizontal, -LiveView.markSlack)
                        }
                }
            }
            .padding(.horizontal, Self.horizontalPadding)
            .padding(.top, Self.bodyTopPadding)
            .padding(.bottom, Self.bottomPadding)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .clipped()
            .onGeometryChange(for: LayoutSize.self) { proxy in
                LayoutSize(
                    width: max(0, proxy.size.width - 2 * Self.horizontalPadding),
                    height: max(0, proxy.size.height - Self.bodyTopPadding - Self.bottomPadding),
                )
            } action: { size in
                model.setViewport(size)
            }
        }
    }
#endif
