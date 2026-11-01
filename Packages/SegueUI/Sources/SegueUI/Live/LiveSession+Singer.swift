#if os(macOS)
    import Editing
    import Foundation
    import LiveLayout
    import MusicTheory
    import Services
    import Shows

    /// Singer view on stage (P9-2 section 6): `V` hands the screen to a singer, lyrics only,
    /// in Live and Rehearsal alike. A remembered Settings-level value, never a song setting;
    /// the same session (keys, map, pedals, requests) keeps working.
    extension LiveSession {
        /// Whether the stage shows lyrics only (Settings > Live, `V`, the Live menu).
        var singerView: Bool {
            context.settings.settings.singerView
        }

        /// `V`: singer view on or off, re-laid out at once on the same pass at the same
        /// progress, with a brief "Singer view" / "Chords" indicator. Display only: never a
        /// sound, never a show change, so it is safe mid-song in a gig.
        func toggleSingerView() {
            setSingerView(!singerView)
        }

        /// Singer view `on` or off from the stage, the Live menu or Settings.
        func setSingerView(_ on: Bool) {
            guard on != singerView else { return }
            context.settings.updateFromStage { $0.singerView = on }
            followSingerSetting()
            flash(on ? "Singer view" : "Chords")
        }

        /// Re-lays out when the setting no longer matches the plan (a change from Settings
        /// or the menu while the stage is up), keeping the performer's place: the same pass
        /// at the same progress, never back to the top.
        func followSingerSetting() {
            let singer = singerView
            if singer {
                singerViewUsed = true
            }
            guard (planView == .singer) != singer else { return }
            let now = context.scrollClock.now()
            let before = plan.flatMap { plan in
                SingerScreenFollow.position(
                    in: plan,
                    offset: scrollOffset(at: now),
                    pinned: pinnedPass,
                ).map { (plan: plan, pass: $0.pass, progress: $0.progress) }
            }
            relayout()
            // A plan that did not follow the scroll (it fit, or used columns) has no pass at
            // the reading line: the re-layout kept the scroll fraction and any pinned pass.
            guard let before, StagePasses.followsScroll(before.plan), let plan, var scroller
            else { return }
            let offset = SingerScreenFollow.offset(
                pass: before.pass,
                progress: before.progress,
                in: plan,
            )
            scroller.seek(to: offset, at: now)
            self.scroller = scroller
            rescheduleLoopWrap()
            noteCurrentPass(currentPass(at: now))
            Task { await flushScroll() }
        }

        /// Cmd +, Cmd -, Cmd 0 in singer view: the one singer zoom (Settings-level), never
        /// the song's own.
        func zoomSinger(_ direction: Int) {
            let current = context.settings.settings.singerZoom
            let zoom = switch direction {
            case 0: 1.0
            case let step where step > 0: current * Self.zoomStep
            default: current / Self.zoomStep
            }
            let clamped = LiveSettings.clampedSingerZoom(zoom)
            guard clamped != current else { return }
            context.settings.updateFromStage { $0.singerZoom = clamped }
            relayout()
            flash("Zoom \(Int((clamped * 100).rounded()))%")
        }

        /// `B` or `T` while singer view is on: they explain themselves and change nothing,
        /// so turning singer view off returns the bass view exactly as it was (P9-2 6.6).
        /// True when the key was taken.
        func refusesBassKeyInSingerView() -> Bool {
            guard singerView else { return false }
            flash("Singer view hides chords (\(singerKey ?? "V") shows them)")
            return true
        }

        /// The singer view key as a keycap ("V"), from the live bindings.
        var singerKey: String? {
            context.bindings.triggers(for: .toggleSingerView).first.map(KeyHelp.keycap)
        }

        /// The header's key line in singer view: "Key A, 96" (P9-2 6.7), the sounding key in
        /// effect at the current pass (a mid-song `{key}` included), never a capo or shape
        /// key; nil when the song has neither key nor tempo.
        var singerKeyLine: String? {
            guard let model = currentModel else { return nil }
            let key = timedPass(shownPass)?.key
                .map { $0.transposed(by: model.transform.concertSemitones) }
                ?? model.transform.concertKey
            return SongSummary.singerKeyLine(key: key, tempo: model.header.tempo)
        }

        /// The footer's up-next key line in singer view.
        var upNextSingerKeyLine: String? {
            guard let model = upNextModel else { return nil }
            return SongSummary.singerKeyLine(
                key: model.transform.concertKey,
                tempo: model.header.tempo,
            )
        }

        /// The footer's song as it renders in its slot, in the arranged order (the up-next
        /// line reads the first line actually played); in singer view the singer model, so
        /// the line is the next song's first line with words (P9-2 6.7).
        func upNextRenderModel(singer: Bool) -> RenderModel? {
            upNextSlot.flatMap { slot in
                slot.song.map { song in
                    let arranged = Self.arranged(
                        StageRequest.renderModel(
                            song,
                            overrides: slot.item.overrides,
                            bass: singer ? nil : bassView,
                        ),
                        StageRequest.resolution(slot.item.arrangement, song: song),
                    )
                    return singer ? SingerView.model(arranged) : arranged
                }
            }
        }

        /// The style the current plan was laid out with.
        var planStyle: LayoutStyle {
            planView == .singer ? .singer : .stage
        }
    }
#endif
