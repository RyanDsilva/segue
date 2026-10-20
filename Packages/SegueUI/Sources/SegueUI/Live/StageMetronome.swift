#if os(macOS)
    import Foundation
    import Library
    import Observation
    import Shows
    import Support

    /// The stage metronome (R90, R108, P3-14): a quiet pulse at the current song's
    /// `{tempo}` and `{time}`, toggled per show (pre-show checklist, remembered as the next
    /// show's default) and by `M` (this show only); in a rehearsal only, a click behind its
    /// own toggle (`K`, or the checklist's switch; off at the start of every rehearsal).
    ///
    /// The beat grid restarts on beat 1 whenever a new song becomes current and when the
    /// metronome is switched on. There is no track (nothing pulses or clicks) during a
    /// break interstitial, at the end of the set, or for a song without a tempo.
    @MainActor
    @Observable
    public final class StageMetronome {
        public let kind: ShowKind
        /// The pulse is on (this run; the checklist's choice is remembered in settings).
        public private(set) var isOn: Bool
        /// The rehearsal click is on. Always false in a gig.
        public private(set) var clicks = false
        /// The current song's beat grid; nil without a tempo, in a break or past the end.
        public private(set) var track: MetronomeTrack?

        /// The monotonic stage clock (the auto-scroll clock): beats never drift with NTP.
        @ObservationIgnored let clock: any Clock
        /// The rehearsal click. Nil in a gig, always: no audio path exists there.
        @ObservationIgnored let click: RehearsalClick?
        /// What the track was built from, so an unrelated state change keeps the grid.
        @ObservationIgnored private var source: Source?

        private struct Source: Equatable {
            var item: ShowItemID?
            var tempo: Double?
            var time: String?
            var inBreak: Bool
        }

        init(
            kind: ShowKind,
            isOn: Bool,
            clock: any Clock,
            makeClickOutput: @escaping @MainActor () -> any MetronomeClickOutput,
        ) {
            self.kind = kind
            self.isOn = isOn
            self.clock = clock
            click = RehearsalClick(kind: kind, clock: clock, makeOutput: makeClickOutput)
        }

        /// Whether the stage shows the pulse.
        public var showsPulse: Bool {
            isOn && track != nil
        }

        /// Follows the engine: a new current item (or a changed tempo or meter, or a break
        /// starting or ending) restarts the grid on beat 1 now.
        func follow(_ state: ShowState) {
            let metadata = state.current?.song?.document.metadata
            let inBreak = state.record.currentBreak != nil
            let next = Source(
                item: state.current?.item.itemId,
                tempo: metadata?.tempo,
                time: metadata?.time,
                inBreak: inBreak,
            )
            guard next != source else { return }
            source = next
            let start = clock.now()
            track = inBreak ? nil : metadata.flatMap { MetronomeTrack(metadata: $0, start: start) }
            syncClick()
        }

        /// `M`: the pulse on or off. Switching it on restarts the grid on beat 1, so the
        /// press can count the band in.
        func toggle() {
            isOn.toggle()
            if isOn {
                restartGrid()
            }
        }

        /// `K`: the rehearsal click on or off. Returns false in a gig (nothing changes).
        @discardableResult
        func toggleClick() -> Bool {
            guard click != nil else { return false }
            clicks.toggle()
            if clicks, !isOn {
                restartGrid()
            }
            syncClick()
            return true
        }

        /// The checklist's Click switch at the start of a rehearsal (ignored in a gig).
        func startClicking(_ on: Bool) {
            if on, !clicks {
                toggleClick()
            }
        }

        /// The run ended or the stage went away: silence now.
        func stop() {
            clicks = false
            click?.stop()
        }

        private func restartGrid() {
            guard var track else { return }
            track.start = clock.now()
            self.track = track
            syncClick()
        }

        private func syncClick() {
            click?.play(clicks ? track : nil)
        }
    }
#endif
