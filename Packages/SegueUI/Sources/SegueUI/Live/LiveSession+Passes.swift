#if os(macOS)
    import Foundation
    import Library
    import LiveLayout
    import Services
    import Shows
    import SwiftUI

    /// The current pass, section jump and the rehearsal loop (R147, R148, P8-2 sections
    /// 9-11). The pass maths is pure (`StagePasses`); this is the stage's state around it.
    extension LiveSession {
        /// The current shown pass at `now`; nil without passes.
        func currentPass(at now: Date) -> Int? {
            guard let plan else { return nil }
            return StagePasses.current(in: plan, offset: scrollOffset(at: now), pinned: pinnedPass)
        }

        /// How far the reading line is through the current pass, 0 ... 1.
        func passProgress(at now: Date) -> Double {
            guard let plan, let current = currentPass(at: now) else { return 0 }
            return StagePasses.progress(of: current, in: plan, offset: scrollOffset(at: now))
        }

        /// The passes the map shows: none in a break, past the end, for an unavailable song,
        /// or for fewer than two shown passes (the band stays reserved, R158 Q7).
        var mapPasses: [PlanPass] {
            guard state.record.currentBreak == nil, state.current != nil, currentModel != nil,
                  let passes = plan?.passes, passes.count >= 2
            else { return [] }
            return passes
        }

        /// The looped pass, for the header pill.
        var loopedPass: PlanPass? {
            guard let loopPass, let passes = plan?.passes, passes.indices.contains(loopPass) else {
                return nil
            }
            return passes[loopPass]
        }

        /// The loop key as a keycap ("L"), from the live bindings.
        var loopKey: String? {
            context.bindings.triggers(for: .toggleLoop).first.map(KeyHelp.keycap)
        }

        // MARK: Jump

        /// 1-9 or a map chip: the pass at `index` (0-based among shown passes) becomes
        /// current. In a scrolling one-column plan the scroll lands 14 pt above it (running
        /// auto-scroll keeps running); otherwise only the current pass changes. A jump to
        /// another pass ends a loop.
        func jump(toPass index: Int) {
            guard state.record.currentBreak == nil, let plan,
                  plan.passes.indices.contains(index)
            else {
                flash("No section \(index + 1)")
                return
            }
            if let loop = loopPass, loop != index {
                stopLoop()
            }
            let now = context.scrollClock.now()
            if let offset = StagePasses.jumpOffset(to: index, in: plan) {
                scroller?.seek(to: offset, at: now)
                Task { await flushScroll() }
            }
            pinnedPass = index
            noteCurrentPass(index)
            showJumpToast(plan.passes[index].name)
            if !recordedJump {
                recordedJump = true
                services.record(.featureUsed(.sectionJump, .stage))
            }
            rescheduleLoopWrap()
        }

        /// "Jumped to Bridge" / "Jumped to Chorus · 2 of 3": a toast and a VoiceOver
        /// announcement.
        private func showJumpToast(_ name: PassName) {
            let text = name.badgeText.map { "Jumped to \(name.title) · \($0)" }
                ?? "Jumped to \(name.title)"
            jumpToast = StageJumpToast.Message(text: text, sequence: (jumpToast?.sequence ?? 0) + 1)
            AccessibilityNotification.Announcement(text).post()
            jumpToastTask?.cancel()
            jumpToastTask = Task { [weak self] in
                try? await Task.sleep(for: StageJumpToast.visible + StageJumpToast.fade)
                guard !Task.isCancelled else { return }
                self?.jumpToast = nil
            }
        }

        /// A manual scroll, page step, Home, auto-scroll start or song change: the current
        /// pass follows the scroll again.
        func clearPinnedPass() {
            if pinnedPass != nil {
                pinnedPass = nil
            }
        }

        // MARK: Loop

        /// `L`: loops the current pass in a rehearsal (on with a one-bar count-in at every
        /// wrap; `L` again stops). In a gig it changes nothing.
        func toggleLoop() {
            guard kind == .rehearsal else {
                flash("Loop works in rehearsals")
                return
            }
            if loopPass != nil {
                stopLoop()
                flash("Loop off")
                return
            }
            guard state.record.currentBreak == nil,
                  let current = currentPass(at: context.scrollClock.now())
            else {
                flash("Nothing to loop")
                return
            }
            loopPass = current
            services.record(.featureUsed(.sectionLoop, .stage))
            rescheduleLoopWrap()
        }

        /// Ends the loop (L, a jump elsewhere, a song change, End).
        func stopLoop() {
            loopWrapTask?.cancel()
            loopWrapTask = nil
            loopWrapInstant = nil
            if loopPass != nil {
                loopPass = nil
            }
        }

        /// The wrap: back to the looped pass's top (14 pt above), pinned, then a one-bar
        /// count-in (the scroll holds for the bar, the metronome restarts on beat 1 at the
        /// wrap; 2 s and no pips without a tempo) before it moves on at the same speed.
        func wrapLoop(at now: Date) {
            guard let loop = loopPass, let plan, plan.passes.indices.contains(loop) else {
                return
            }
            let hold = metronome.countIn(at: now)
            if let offset = StagePasses.jumpOffset(to: loop, in: plan) {
                scroller?.seek(to: offset, at: now, holding: hold)
                Task { await flushScroll() }
            }
            pinnedPass = loop
            rescheduleLoopWrap()
        }

        /// Schedules the next wrap for when a running scroll brings the reading line to the
        /// looped pass's bottom (or reaches the end first), on the scroll clock. Called on
        /// every seek, nudge, pause and re-layout.
        func rescheduleLoopWrap() {
            loopWrapTask?.cancel()
            loopWrapTask = nil
            loopWrapInstant = nil
            guard let loop = loopPass, let plan, StagePasses.followsScroll(plan),
                  let scroller
            else { return }
            let target = StagePasses.wrapOffset(of: loop, in: plan)
            guard let instant = scroller.instant(reaching: target) else { return }
            loopWrapInstant = instant
            let clock = context.scrollClock
            loopWrapTask = Task { [weak self] in
                // Polled in short sleeps, so a time-scaled scroll clock still lands on time.
                while !Task.isCancelled {
                    let wait = instant.timeIntervalSince(clock.now())
                    if wait <= 0 {
                        break
                    }
                    try? await Task.sleep(for: .seconds(min(wait, 0.1)))
                }
                guard !Task.isCancelled else { return }
                self?.wrapLoopIfDue()
            }
        }

        /// Wraps when the scheduled instant has come (the wait task, and tests on a manual
        /// clock).
        func wrapLoopIfDue() {
            let now = context.scrollClock.now()
            guard let instant = loopWrapInstant, now >= instant else { return }
            wrapLoop(at: now)
        }

        /// Page Down while looping: a step that would take the reading line past the looped
        /// pass's bottom wraps instead (in a song that fits, every Page Down wraps, R158 Q3).
        /// Returns whether it wrapped.
        func pageWrapsLoop() -> Bool {
            guard let loop = loopPass, let plan, plan.passes.indices.contains(loop) else {
                return false
            }
            let now = context.scrollClock.now()
            if StagePasses.followsScroll(plan) {
                let offset = scrollOffset(at: now)
                if let stop = plan.pageStops.first(where: { $0 > offset + 0.5 }) {
                    let line = StagePasses.readLine(offset: min(stop, plan.overflow), plan: plan)
                    if line <= plan.passes[loop].bottom + 0.5 {
                        return false
                    }
                }
            }
            wrapLoop(at: now)
            return true
        }
    }
#endif
