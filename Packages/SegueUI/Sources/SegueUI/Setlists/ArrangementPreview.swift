#if os(macOS)
    import Editing
    import Library
    import LiveLayout
    import Setlists
    import Shows
    import SwiftUI

    /// What Arrange Sections needs from the app (P8-3 sections 6.4 and 6.7): Settings > Live
    /// and the instrument profile, so its preview lays the song out as the stage does, and
    /// the one-song rehearsal entry point.
    /// Injected where the builder is shown.
    struct ArrangementStage {
        var settings: LiveSettingsStore
        var instrument: InstrumentProfileStore?
        /// Whether a one-song rehearsal can start now (nothing performing or starting).
        var canRehearse = false
        /// "Rehearse this" (R156): an unlogged one-song rehearsal of the slot; `onEnd` runs
        /// when it ends.
        var rehearse: @MainActor (SongID, StageSlot, @escaping @MainActor () -> Void)
            -> Void = { _, _, _ in }
        /// Rehearse Medley (P9-3 12): an unlogged run of a whole setlist slot; `onEnd` runs
        /// when it ends.
        var rehearseSlot: @MainActor (SetlistEntry, @escaping @MainActor () -> Void)
            -> Void = { _, _ in }
    }

    extension EnvironmentValues {
        @Entry var arrangementStage: ArrangementStage?
    }

    /// The song as the stage will lay it out with the sheet's arrangement (P8-3 section 6.4):
    /// the stage's own request (`StageRequest.make`), the compact section map, and the real
    /// layout engine and stage faces at a 1024 x 640 stage scaled to the pane. Selecting a
    /// playing chip scrolls to its pass.
    struct ArrangementPreview: View {
        let record: SongRecord
        let entry: SetlistEntry
        /// The arrangement to show (the lane, or a roadmap being typed); nil = the full song.
        let arrangement: SlotArrangement?
        let settings: LiveSettings
        var bass: BassView?
        /// The selected lane position.
        var selection: Int?

        static let stage = LayoutSize(width: 1024, height: 640)

        @Environment(\.accessibilityReduceMotion) private var reduceMotion
        @State private var position = ScrollPosition(edge: .top)
        @State private var width: CGFloat = 0

        var body: some View {
            let plan = Self.plan(
                record: record,
                entry: entry,
                arrangement: arrangement,
                settings: settings,
                bass: bass,
            )
            VStack(spacing: 0) {
                HStack {
                    eyebrow("Stage preview", color: Theme.color.muted)
                    Spacer()
                    eyebrow("As the stage will draw it", color: Theme.color.indicatorOff)
                }
                .padding(.top, 14)
                .padding(.horizontal, 16)
                .padding(.bottom, 8)
                StageMapStrip(
                    passes: plan.passes,
                    current: nil,
                    progress: 0,
                    loop: nil,
                    style: .preview,
                )
                stageBody(plan)
            }
            .background(Theme.color.ground)
            .onChange(of: selection) { scroll(to: selection, in: plan) }
            .accessibilityElement(children: .ignore)
            // One spoken label: static text exposes its words as the value.
            .accessibilityLabel(uiString("Stage preview, \(Self.spokenCount(plan.passes.count))"))
            .accessibilityAddTraits(.isStaticText)
            .accessibilityIdentifier(AccessibilityID.arrangementPreview)
        }

        private func eyebrow(_ text: String, color: Color) -> some View {
            Text(text.uppercased())
                .font(SchibstedGrotesk.bold.font(size: 11))
                .tracking(0.08 * 11)
                .foregroundStyle(color)
        }

        private func stageBody(_ plan: LayoutPlan) -> some View {
            let scale = Self.scale(forWidth: width)
            return ScrollView(.vertical) {
                // The miniature sits in an overlay so the full-size plan never widens the pane;
                // only its scaled box takes space.
                Color.clear
                    .frame(
                        width: plan.viewport.width * scale,
                        height: max(plan.contentHeight, 1) * scale,
                    )
                    .overlay(alignment: .topLeading) {
                        StagePlanView(plan: plan)
                            .scaleEffect(scale, anchor: .topLeading)
                            .frame(
                                width: plan.viewport.width * scale,
                                height: max(plan.contentHeight, 1) * scale,
                                alignment: .topLeading,
                            )
                    }
                    .clipped()
                    .padding(.top, 8)
                    .padding(.horizontal, 16)
                    .padding(.bottom, 20)
            }
            .scrollPosition($position)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { width = $0 }
        }

        /// Selecting a playing chip scrolls so its pass's top shows; a skipped chip does not
        /// scroll (it is not on stage).
        private func scroll(to selection: Int?, in plan: LayoutPlan) {
            guard let selection, let pass = plan.passes.first(where: { $0.position == selection })
            else { return }
            let top = max(pass.top * Self.scale(forWidth: width), 0)
            withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.25)) {
                position.scrollTo(y: top)
            }
        }

        /// The miniature's scale for a pane `width` wide (16 pt each side).
        static func scale(forWidth width: CGFloat) -> CGFloat {
            min(max(width - 32, 1) / stage.width, 1)
        }

        /// "9 passes", "1 pass".
        static func spokenCount(_ count: Int) -> String {
            count == 1 ? "1 pass" : "\(count) passes"
        }

        /// The stage's request for this slot with `arrangement`: what the stage builds
        /// (Settings > Live minimum lyric size and default columns, the song's zoom and notes,
        /// the slot's overrides and note), at a 1024 x 640 stage.
        static func request(
            record: SongRecord,
            entry: SetlistEntry,
            arrangement: SlotArrangement?,
            settings: LiveSettings,
            bass: BassView? = nil,
        ) -> LayoutRequest {
            var slot = StageSlot(entry)
            slot.arrangement = arrangement
            return StageRequest.make(
                song: record,
                slot: slot,
                prefs: record.sidecar.live,
                settings: settings,
                minLyricSize: settings.minLyricSize,
                viewport: stage,
                bass: bass,
            ).request
        }

        static func plan(
            record: SongRecord,
            entry: SetlistEntry,
            arrangement: SlotArrangement?,
            settings: LiveSettings,
            bass: BassView? = nil,
        ) -> LayoutPlan {
            LayoutEngine.plan(
                request(
                    record: record,
                    entry: entry,
                    arrangement: arrangement,
                    settings: settings,
                    bass: bass,
                ),
                metrics: StageTextMetrics(),
            )
        }
    }
#endif
