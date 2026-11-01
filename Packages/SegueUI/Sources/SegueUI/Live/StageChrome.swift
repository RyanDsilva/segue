#if os(macOS)
    import Editing
    import Library
    import Shows
    import SwiftUI

    /// Header: cue dot, title (28 / 800), "G, capo 2, 96" (muted), then the set progress
    /// dots and elapsed set time on the right (brand.md section 7).
    struct StageHeader: View {
        let session: LiveSession

        var body: some View {
            HStack(alignment: .center, spacing: 14) {
                Circle()
                    .fill(Theme.color.cue)
                    .frame(width: 10, height: 10)
                    .accessibilityHidden(true)
                Text(title)
                    .font(Theme.font.title)
                    .tracking(Theme.tracking.title * 28)
                    .foregroundStyle(Theme.color.ink)
                    .lineLimit(1)
                    .accessibilityIdentifier(AccessibilityID.liveTitle)
                    .layoutPriority(1)
                if let line = performanceLine {
                    Text(line)
                        .font(SchibstedGrotesk.medium.font(size: 16))
                        .foregroundStyle(Theme.color.muted)
                        .lineLimit(1)
                        .accessibilityIdentifier(AccessibilityID.liveMeta)
                }
                if let medley = session.medleyChipText {
                    // "Medley 2 of 3" (P9-3 9.4).
                    StageChip(text: medley)
                        .accessibilityLabel(session.medleyChipLabel ?? medley)
                        .accessibilityIdentifier(AccessibilityID.liveMedley)
                }
                if let arrangement = session.currentArrangement {
                    // Quiet: an arranged slot says so; one whose sections changed says the
                    // full song is shown (R122, R123).
                    Text(arrangement == .applied ? "Arranged" : "Full song")
                        .font(SchibstedGrotesk.medium.font(size: 16))
                        .foregroundStyle(Theme.color.muted)
                        .lineLimit(1)
                        .accessibilityLabel(arrangement == .applied
                            ? "Arranged for this gig"
                            : "Full song: the arrangement is out of date")
                        .accessibilityIdentifier(AccessibilityID.liveArrangement)
                }
                if let scale = session.currentScale {
                    StageScaleLine(scale: scale)
                }
                Spacer(minLength: 24)
                if session.isPlayingAlong {
                    StagePlayAlongPill()
                }
                if let pass = session.loopedPass {
                    StageLoopPill(name: pass.name, stopKey: session.loopKey)
                }
                if session.planView == .singer {
                    // Why there are no chords, at a glance (P9-2 6.1).
                    StageChip(text: "Singer")
                        .accessibilityLabel("Singer view, lyrics only")
                        .accessibilityIdentifier(AccessibilityID.liveSinger)
                }
                if session.kind == .rehearsal {
                    StageChip(text: "Rehearsal")
                        .accessibilityIdentifier(AccessibilityID.liveRehearsal)
                }
                if session.scope == .setlist {
                    ProgressDots(items: session.state.record.items, position: session.positionText)
                }
                ElapsedTime(session: session)
                    .padding(.leading, 6)
            }
            .padding(.horizontal, LiveView.horizontalPadding)
        }

        /// "G, capo 2, 96"; in singer view the sounding key only, "Key A, 96" (P9-2 6.7).
        private var performanceLine: String? {
            session.planView == .singer
                ? session.singerKeyLine
                : session.currentModel.flatMap(SongSummary.performanceLine)
        }

        private var title: String {
            session.state.current.map { slot in
                slot.song.map(SongSummary.title) ?? slot.item.title
            } ?? session.setlistName
        }
    }

    /// Set progress: played dots in `played`, the current song as a 20px `cue` pill,
    /// upcoming in `indicatorOff` (all 3:1 on the stage, A44). Skipped songs are rings
    /// (shape, not hue, tells them apart).
    private struct ProgressDots: View {
        let items: [ShowItem]
        let position: String

        var body: some View {
            HStack(spacing: 6) {
                ForEach(Self.groups(items), id: \.first?.itemId) { group in
                    if group.count > 1 {
                        // A medley: a short bar split into its members' ticks (P9-3 9.4).
                        HStack(spacing: 2) {
                            ForEach(group) { tick($0.state) }
                        }
                    } else if let item = group.first {
                        dot(item.state)
                    }
                }
            }
            .accessibilityRepresentation {
                Text(position)
                    .accessibilityIdentifier(AccessibilityID.livePosition)
            }
        }

        /// Consecutive items of one medley form one group; every other item is its own.
        static func groups(_ items: [ShowItem]) -> [[ShowItem]] {
            var groups: [[ShowItem]] = []
            for item in items {
                if let slot = item.medley?.slot, groups.last?.first?.medley?.slot == slot {
                    groups[groups.count - 1].append(item)
                } else {
                    groups.append([item])
                }
            }
            return groups
        }

        /// One member's tick in a medley's bar.
        private func tick(_ state: ItemState) -> some View {
            RoundedRectangle(cornerRadius: 1.5, style: .continuous)
                .fill(state == .current ? Theme.color.cue
                    : state == .pending ? Theme.color.indicatorOff : Theme.color.played)
                .frame(width: state == .current ? 10 : 6, height: 6)
        }

        @ViewBuilder
        private func dot(_ state: ItemState) -> some View {
            switch state {
            case .current:
                Capsule().fill(Theme.color.cue).frame(width: 20, height: 6)
            case .played:
                Circle().fill(Theme.color.played).frame(width: 6, height: 6)
            case .skipped:
                Circle().strokeBorder(Theme.color.played, lineWidth: 1.5).frame(width: 6, height: 6)
            case .pending:
                Circle().fill(Theme.color.indicatorOff).frame(width: 6, height: 6)
            }
        }
    }

    /// Elapsed set time in muted, ticking once a second.
    private struct ElapsedTime: View {
        let session: LiveSession

        var body: some View {
            TimelineView(.periodic(from: .now, by: 1)) { _ in
                Text(Self.format(session.elapsed(at: session.context.clock.now())))
                    .font(SchibstedGrotesk.medium.font(size: 15))
                    .foregroundStyle(Theme.color.muted)
                    .monospacedDigit()
                    .accessibilityLabel("Elapsed")
                    .accessibilityValue(Self
                        .format(session.elapsed(at: session.context.clock.now())))
            }
        }

        /// "32:10", "1:02:05".
        static func format(_ seconds: TimeInterval) -> String {
            let total = Int(seconds)
            let hours = total / 3600
            let minutes = (total % 3600) / 60
            let secs = total % 60
            let tail = String(format: "%02d", secs)
            return hours > 0
                ? "\(hours):\(String(format: "%02d", minutes)):\(tail)"
                : "\(minutes):\(tail)"
        }
    }

    /// The header's loop pill (R148): "⟲ Looping Chorus 2/3" and "L stops", ringed and
    /// lightly filled in coral.
    struct StageLoopPill: View {
        let name: PassName
        let stopKey: String?

        var body: some View {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text("⟲ Looping \(name.chipText)")
                    .font(SchibstedGrotesk.semiBold.font(size: 14))
                    .foregroundStyle(Theme.color.ink)
                if let stopKey {
                    Text("\(stopKey) stops")
                        .font(SchibstedGrotesk.medium.font(size: 14))
                        .foregroundStyle(Theme.color.muted)
                }
            }
            .lineLimit(1)
            .padding(.horizontal, 11)
            .padding(.vertical, 5)
            .background {
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(Theme.color.cue.opacity(0.08))
                    .overlay {
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .strokeBorder(Theme.color.cue.opacity(0.55), lineWidth: 1)
                    }
            }
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier(AccessibilityID.liveLoop)
        }
    }

    /// "♪ Playing along" (P8-6 10.4): Rehearsal play-along is sounding. Text, so VoiceOver
    /// reads it; nothing relies on the sound alone.
    struct StagePlayAlongPill: View {
        var body: some View {
            Text("\u{266A} Playing along")
                .font(SchibstedGrotesk.semiBold.font(size: 14))
                .foregroundStyle(Theme.color.ink)
                .lineLimit(1)
                .padding(.horizontal, 11)
                .padding(.vertical, 5)
                .background {
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(Theme.color.cue.opacity(0.08))
                        .overlay {
                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .strokeBorder(Theme.color.cue.opacity(0.55), lineWidth: 1)
                        }
                }
                .accessibilityLabel("Playing along")
                .accessibilityIdentifier(AccessibilityID.livePlayAlong)
        }
    }

    /// A brand chip: 14 / 600, padding 5x10, radius 6, 1px border, no fill.
    struct StageChip: View {
        let text: String

        var body: some View {
            Text(text)
                .font(SchibstedGrotesk.semiBold.font(size: 14))
                .foregroundStyle(Theme.color.muted)
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .overlay {
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .strokeBorder(Theme.color.controlBorder, lineWidth: 1)
                }
        }
    }

    /// Footer: "Up next" (14 / 700 muted), the title (20 / 700), key and capo (muted); a
    /// queued request replaces it ("Request"). Right: auto-scroll state and the request
    /// count with a cue dot.
    struct StageFooter: View {
        let session: LiveSession

        var body: some View {
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                upNext
                Spacer(minLength: 24)
                // Ticks while scrolling so "Scroll at end" shows when the bottom is reached.
                TimelineView(.periodic(from: .now, by: 0.5)) { _ in
                    if let status = session.scrollStatus(at: session.context.scrollClock.now()) {
                        Text(status)
                            .font(SchibstedGrotesk.medium.font(size: 15))
                            .foregroundStyle(Theme.color.muted)
                            .accessibilityIdentifier(AccessibilityID.liveScrollStatus)
                    }
                }
                .fixedSize()
                if !session.queuedRequests.isEmpty {
                    requestCount(session.queuedRequests.count)
                }
            }
            .padding(.horizontal, LiveView.horizontalPadding)
            .frame(maxHeight: .infinity)
            .overlay(alignment: .top) {
                Rectangle().fill(Theme.color.line).frame(height: 1)
            }
        }

        @ViewBuilder private var upNext: some View {
            switch session.state.upNext {
            case let .request(request, song):
                label("Request", color: Theme.color.cueText)
                titleText(song.map(SongSummary.title) ?? request.title)
                if let note = request.note, !note.isEmpty {
                    detail(note)
                }
            case let .item(slot) where session.nextInMedley != nil:
                // Inside a medley before its last member (P9-3 9.4).
                label("Next in medley", color: Theme.color.muted)
                titleText(slot.song.map(SongSummary.title) ?? slot.item.title)
                if let line = Self.keyLine(session.upNextModel) {
                    detail(line)
                }
                if let transition = session.nextInMedley?.transition {
                    detail("\u{21B3} " + transition)
                        .lineLimit(1)
                        .truncationMode(.tail)
                        .layoutPriority(-1)
                }
            case .item where session.upNextMedley != nil:
                label("Up next", color: Theme.color.muted)
                titleText(session.upNextMedley?.title ?? "")
                detail(session.upNextMedley?.members ?? "")
                if let line = Self.keyLine(session.upNextModel) {
                    detail(line)
                }
            case let .item(slot):
                label("Up next", color: Theme.color.muted)
                titleText((slot.song.map(SongSummary.title) ?? slot.item.title)
                    + (session.upNextIsReprise ? " (reprise)" : ""))
                if let line = session.planView == .singer
                    ? session.upNextSingerKeyLine
                    : Self.keyLine(session.upNextModel)
                {
                    detail(line)
                }
                if let first = session.upNextModel.flatMap(Self.firstLine) {
                    detail(first)
                        .lineLimit(1)
                        .truncationMode(.tail)
                        .layoutPriority(-1)
                }
            case nil where session.scope == .song:
                label("End of song", color: Theme.color.muted)
                detail(session.kind == .gig ? "Cmd-. ends" : "Cmd-. ends the rehearsal")
            case nil:
                label("End of set", color: Theme.color.muted)
                detail("Cmd-. ends the \(session.kind == .gig ? "show" : "rehearsal")")
            }
        }

        private func label(_ text: String, color: Color) -> some View {
            Text(text)
                .font(SchibstedGrotesk.bold.font(size: 14))
                .foregroundStyle(color)
                .accessibilityIdentifier(AccessibilityID.liveUpNextLabel)
        }

        private func titleText(_ title: String) -> some View {
            Text(title)
                .font(Theme.font.sectionHeading)
                .foregroundStyle(Theme.color.ink)
                .lineLimit(1)
                .accessibilityIdentifier(AccessibilityID.liveUpNext)
        }

        private func detail(_ text: String) -> some View {
            Text(text)
                .font(SchibstedGrotesk.medium.font(size: 16))
                .foregroundStyle(Theme.color.muted)
                .lineLimit(1)
        }

        private func requestCount(_ count: Int) -> some View {
            HStack(spacing: 8) {
                Circle().fill(Theme.color.cue).frame(width: 8, height: 8)
                Text(count == 1 ? "1 request" : "\(count) requests")
                    .font(SchibstedGrotesk.semiBold.font(size: 15))
                    .foregroundStyle(Theme.color.ink)
            }
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier(AccessibilityID.liveRequestCount)
        }

        /// "D, capo 2" / "D, no capo" (the displayed key after overrides).
        static func keyLine(_ model: RenderModel?) -> String? {
            guard let model, let key = model.header.key, !key.isEmpty else { return nil }
            let capo = model.header.capo ?? 0
            return capo > 0 ? "\(key), capo \(capo)" : "\(key), no capo"
        }

        /// The first lyric line, else the first section label.
        static func firstLine(_ model: RenderModel) -> String? {
            for section in model.sections {
                for item in section.items {
                    if case let .lyrics(line) = item {
                        let text = line.lyrics.trimmingCharacters(in: .whitespaces)
                        if !text.isEmpty {
                            return text
                        }
                    }
                }
            }
            return model.sections.compactMap(\.label).first
        }
    }

    /// The status line that fades in on mouse move: position, elapsed time, scroll state and
    /// the main keys. A notice (an action that failed) shows here too.
    struct StageStatusLine: View {
        let session: LiveSession

        var body: some View {
            Group {
                if let notice = session.notice {
                    Text(notice)
                        .foregroundStyle(Theme.color.ink)
                        .accessibilityIdentifier(AccessibilityID.liveNotice)
                } else {
                    Text(summary)
                        .foregroundStyle(Theme.color.muted)
                        .accessibilityIdentifier(AccessibilityID.liveStatus)
                }
            }
            .font(Theme.font.label)
            .lineLimit(1)
            .padding(.horizontal, 14)
            .frame(maxHeight: .infinity)
            .background(StagePanelBackground(radius: 8))
        }

        /// Generated from the live bindings, so custom keys show truthfully.
        private var summary: String {
            let hints = KeyHelp.statusHints(
                session.context.bindings,
                kind: session.kind,
                hasFills: session.currentSongHasFills,
            )
            return (["Song \(session.positionText)"] + hints).joined(separator: "  ·  ")
        }
    }
#endif
