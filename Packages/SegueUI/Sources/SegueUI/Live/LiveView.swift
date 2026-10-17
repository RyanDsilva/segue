#if os(macOS)
    import AppKit
    import Library
    import SwiftUI

    /// The stage: header (cue dot, title, "G, capo 2, 96", set progress), the song body with
    /// a section label gutter, and an "Up next" footer. Arrows and space move between songs.
    struct LiveView: View {
        let model: LiveViewModel
        /// Extra top padding so the header clears the camera housing on notched displays.
        var topInset: CGFloat = 0
        var onExit: () -> Void
        @FocusState private var isFocused: Bool

        var body: some View {
            VStack(spacing: 0) {
                header
                ScrollView {
                    if let song = model.current {
                        songBody(song)
                            .padding(.horizontal, 48)
                            .padding(.vertical, 28)
                            .frame(maxWidth: 1100, alignment: .leading)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .id(song.id)
                    }
                }
                .scrollIndicators(.never)
                footer
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Theme.color.ground)
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier(AccessibilityID.liveView)
            .focusable()
            .focusEffectDisabled()
            .focused($isFocused)
            .onKeyPress(keys: [.rightArrow, .downArrow, .space, .pageDown]) { _ in
                model.next()
                return .handled
            }
            .onKeyPress(keys: [.leftArrow, .upArrow, .pageUp]) { _ in
                model.previous()
                return .handled
            }
            .onKeyPress(.escape) {
                onExit()
                return .handled
            }
            .onExitCommand(perform: onExit)
            .onAppear {
                isFocused = true
                model.stageDidAppear()
            }
            .onDisappear { model.stageDidDisappear() }
        }

        private var header: some View {
            HStack(alignment: .center, spacing: 14) {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(alignment: .center, spacing: 12) {
                        Circle()
                            .fill(Theme.color.cue)
                            .frame(width: 10, height: 10)
                            .accessibilityHidden(true)
                        Text(model.current.map(SongSummary.title) ?? model.setlistName)
                            .font(Theme.font.title)
                            .tracking(Theme.tracking.title * 28)
                            .foregroundStyle(Theme.color.ink)
                            .lineLimit(1)
                            .accessibilityIdentifier(AccessibilityID.liveTitle)
                    }
                    if let line = model.current.flatMap({ song in
                        let rendered = SongSummary.renderModel(song, showDiagrams: false)
                        return SongSummary.performanceLine(rendered)
                    }) {
                        Text(line)
                            .font(Theme.font.body)
                            .foregroundStyle(Theme.color.muted)
                            .padding(.leading, 22)
                            .accessibilityIdentifier(AccessibilityID.liveMeta)
                    }
                }
                Spacer(minLength: 24)
                progress
            }
            .padding(.horizontal, 48)
            .padding(.top, 28 + topInset)
            .padding(.bottom, 18)
            .overlay(alignment: .bottom) {
                Rectangle().fill(Theme.color.line).frame(height: 1)
            }
        }

        private var progress: some View {
            VStack(alignment: .trailing, spacing: 8) {
                HStack(spacing: 6) {
                    ForEach(model.songs.indices, id: \.self) { index in
                        Capsule()
                            .fill(dotColor(index))
                            .frame(width: index == model.index ? 20 : 6, height: 6)
                    }
                }
                .accessibilityHidden(true)
                Text(model.positionText)
                    .font(Theme.font.label)
                    .foregroundStyle(Theme.color.muted)
                    .monospacedDigit()
                    .accessibilityIdentifier(AccessibilityID.livePosition)
            }
        }

        private func dotColor(_ index: Int) -> Color {
            if index == model.index {
                return Theme.color.cue
            }
            return index < model.index ? Theme.color.played : Theme.color.lineStrong
        }

        @ViewBuilder
        private func songBody(_ song: SongRecord) -> some View {
            // The song as its display toggles render it (transpose, capo, Nashville).
            let sections = SongSummary.renderModel(song, showDiagrams: false).sections
            if sections.isEmpty {
                Text("This song has no lyrics yet.")
                    .font(Theme.font.liveLyric(size: SongSheetStyle.stage.lyricSize))
                    .foregroundStyle(Theme.color.muted)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                SongSheetView(sections: sections, style: .stage)
            }
        }

        private var footer: some View {
            HStack(alignment: .firstTextBaseline, spacing: 14) {
                if let next = model.upNext {
                    Text("Up next")
                        .font(Theme.font.label)
                        .foregroundStyle(Theme.color.muted)
                    Text(SongSummary.title(next))
                        .font(Theme.font.sectionHeading)
                        .foregroundStyle(Theme.color.ink)
                        .lineLimit(1)
                        .accessibilityIdentifier(AccessibilityID.liveUpNext)
                    if let line = SongSummary.performanceLine(next.document.metadata) {
                        Text(line)
                            .font(Theme.font.body)
                            .foregroundStyle(Theme.color.muted)
                    }
                } else {
                    Text("End of set")
                        .font(Theme.font.label)
                        .foregroundStyle(Theme.color.muted)
                }
                Spacer(minLength: 24)
                Text("← → to change song · Esc to exit")
                    .font(Theme.font.label)
                    .foregroundStyle(Theme.color.muted)
            }
            // Same height with or without an "Up next" song, so the body never jumps.
            .frame(minHeight: 28)
            .padding(.horizontal, 48)
            .padding(.vertical, 18)
            .overlay(alignment: .top) {
                Rectangle().fill(Theme.color.line).frame(height: 1)
            }
        }
    }
#endif
