#if os(macOS)
    import Editing
    import Foundation
    import Library
    import LiveLayout
    import Shows

    /// Mid-song `{key}`, `{tempo}` and `{time}` on stage (P8-7 section 5.3): at a pass boundary
    /// the metronome takes the tempo and meter in effect at the pass's first chord (R168 Q3),
    /// and the bass-note view's scale line its key (R168 Q2). The header's key line keeps the
    /// song's key, as the library does.
    extension LiveSession {
        /// The current pass is `index` (the stage's timeline view, a jump, a relayout).
        func noteCurrentPass(_ index: Int?) {
            if shownPass != index {
                shownPass = index
            }
            guard let pass = timedPass(index) else { return }
            let timing = StageMetronome.PassTiming(
                tempo: pass.tempo,
                meter: MetronomeMeter(pass.meter),
            )
            metronome.follow(pass: timing, item: StageMetronome.gridItem(of: state))
        }

        /// What shown pass `index` has in effect: its part's written pass on the timeline (in a
        /// medley, its own member's, so the metronome switches as the reading line crosses into
        /// the next member, before the member is committed).
        func timedPass(_ index: Int?) -> TimedPass? {
            guard let index, let plan, plan.passes.indices.contains(index) else { return nil }
            let segment = plan.passes[index].segment
            let timeline = isInMedley
                ? (medleyTimelines.indices.contains(segment) ? medleyTimelines[segment] : nil)
                : currentTimeline
            guard let passes = timeline?.passes else { return nil }
            let source = plan.passes[index].source
            return passes.indices.contains(source) ? passes[source] : nil
        }

        /// The bass-note view's scale line for the current pass: the `{key}` in effect there,
        /// at sounding pitch; nil outside the bass-note view.
        var currentScale: String? {
            guard let model = currentModel, let scale = model.header.scale else { return nil }
            guard let key = timedPass(shownPass)?.key else { return scale }
            return RenderHeader.scaleText(for: key.transposed(by: model.transform.concertSemitones))
        }
    }
#endif
