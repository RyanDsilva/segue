#if os(macOS)
    import Library
    import Shows
    import SwiftUI

    /// Q: the request queue, oldest first. Play makes one current (the interrupted song
    /// goes back to pending); Drop removes it. R plays the oldest without opening this.
    struct RequestPanel: View {
        let session: LiveSession

        var body: some View {
            StageSidePanel(title: "Requests", hint: "R plays the oldest  ·  Q closes") {
                let requests = session.queuedRequests
                if requests.isEmpty {
                    Text("No requests yet. ⌘K finds a song; ⌘↩ adds it here.")
                        .font(Theme.font.body)
                        .foregroundStyle(Theme.color.muted)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.horizontal, 20)
                } else {
                    ScrollView {
                        VStack(spacing: 4) {
                            ForEach(requests) { request in
                                row(request)
                            }
                        }
                        .padding(.horizontal, 12)
                    }
                    .scrollIndicators(.never)
                }
            }
            .accessibilityIdentifier(AccessibilityID.liveRequests)
        }

        private func row(_ request: ShowRequest) -> some View {
            HStack(alignment: .center, spacing: 10) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(request.title)
                        .font(SchibstedGrotesk.semiBold.font(size: 17))
                        .foregroundStyle(Theme.color.ink)
                        .lineLimit(1)
                    Text(detail(request))
                        .font(Theme.font.label)
                        .foregroundStyle(Theme.color.muted)
                        .lineLimit(1)
                }
                Spacer(minLength: 8)
                Button("Play") { session.perform(.playRequest(request.requestId)) }
                    .buttonStyle(.seguePrimary)
                    .accessibilityIdentifier(AccessibilityID.liveRequestPlay)
                Button("Drop") { session.perform(.dropRequest(request.requestId)) }
                    .buttonStyle(.segueSecondary)
            }
            .controlSize(.small)
            .padding(.horizontal, 8)
            .padding(.vertical, 8)
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier(AccessibilityID.liveRequestRow)
        }

        private func detail(_ request: ShowRequest) -> String {
            let time = request.addedAt.formatted(date: .omitted, time: .shortened)
            if let note = request.note, !note.isEmpty {
                return "\(note)  ·  \(time)"
            }
            return "Added \(time)"
        }
    }

    /// S: the show order with states. Drag to reorder; per row, play now, play next, skip
    /// or un-skip. Skipped songs stay in the list, dimmed.
    struct SetOrderDrawer: View {
        let session: LiveSession

        var body: some View {
            StageSidePanel(title: "Set order", hint: "Drag to reorder  ·  S closes") {
                List {
                    let items = Array(session.state.record.items.enumerated())
                    ForEach(items, id: \.element.id) { index, item in
                        SetOrderRow(index: index, item: item, session: session)
                            .listRowBackground(Color.clear)
                            .listRowSeparator(.hidden)
                            // A medley moves as one block, by its first member (P9-3 8.2).
                            .moveDisabled((item.medley?.index ?? 0) > 0)
                    }
                    .onMove { offsets, destination in
                        session.perform(.move(fromOffsets: offsets, toOffset: destination))
                    }
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
                .accessibilityIdentifier(AccessibilityID.liveDrawerList)
            }
            .accessibilityIdentifier(AccessibilityID.liveDrawer)
        }
    }

    private struct SetOrderRow: View {
        let index: Int
        let item: ShowItem
        let session: LiveSession

        var body: some View {
            VStack(alignment: .leading, spacing: 2) {
                if let medley = item.medley, medley.index == 0 {
                    // The medley as a group: its title over its members (P9-3 8.2).
                    Text("MEDLEY \u{00B7} \(medley.displayTitle)")
                        .font(SchibstedGrotesk.bold.font(size: 11))
                        .tracking(0.08 * 11)
                        .foregroundStyle(Theme.color.muted)
                        .padding(.leading, 32)
                        .padding(.top, 4)
                }
                row
                    .padding(.leading, item.medley == nil ? 0 : 14)
            }
        }

        private var row: some View {
            HStack(spacing: 10) {
                Text("\(index + 1)")
                    .font(Theme.font.label)
                    .foregroundStyle(Theme.color.muted)
                    .monospacedDigit()
                    .frame(width: 22, alignment: .trailing)
                VStack(alignment: .leading, spacing: 1) {
                    Text(item.title)
                        .font(SchibstedGrotesk.semiBold.font(size: 16))
                        .foregroundStyle(item.state == .played ? Theme.color.muted : Theme.color
                            .ink)
                        .lineLimit(1)
                    if let state = stateLabel {
                        Text(state)
                            .font(Theme.font.label)
                            .foregroundStyle(item.state == .current ? Theme.color.cueText : Theme
                                .color.muted)
                    }
                }
                Spacer(minLength: 6)
                actions
            }
            .controlSize(.small)
            .padding(.vertical, 4)
            .opacity(item.state == .skipped ? 0.45 : 1)
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier(AccessibilityID.liveDrawerRow)
            .accessibilityLabel("\(index + 1). \(item.title), \(item.state.rawValue)")
        }

        private var stateLabel: String? {
            let origin: String? = switch item.origin {
            case .request: "Request"
            case .inserted: "Added"
            case .setlist: nil
            }
            let state: String? = switch item.state {
            case .current: "Now playing"
            case .played: "Played"
            case .skipped: "Skipped"
            case .pending: nil
            }
            let parts = [state, origin].compactMap(\.self)
            return parts.isEmpty ? nil : parts.joined(separator: "  ·  ")
        }

        @ViewBuilder private var actions: some View {
            switch item.state {
            case .pending:
                Button("Next") { moveNext() }
                    .buttonStyle(.segueSecondary)
                    .accessibilityIdentifier(AccessibilityID.liveDrawerPlayNext)
                Button("Skip") { session.perform(.skip(item.itemId)) }
                    .buttonStyle(.segueSecondary)
                    .accessibilityIdentifier(AccessibilityID.liveDrawerSkip)
                Button("Play") { session.perform(.jump(item.itemId)) }
                    .buttonStyle(.segueSecondary)
            case .skipped:
                Button("Unskip") { session.perform(.unskip(item.itemId)) }
                    .buttonStyle(.segueSecondary)
                    .accessibilityIdentifier(AccessibilityID.liveDrawerUnskip)
            case .current, .played:
                EmptyView()
            }
        }

        /// Moves this item right after the current one.
        private func moveNext() {
            let items = session.state.record.items
            guard let from = items.firstIndex(where: { $0.itemId == item.itemId }) else { return }
            let target = (session.state.current?.position ?? -1) + 1
            guard from != target else { return }
            session.perform(.move(fromOffsets: IndexSet(integer: from), toOffset: target))
        }
    }

    /// A full-height panel at the stage's edge, between header and footer.
    struct StageSidePanel<Content: View>: View {
        let title: String
        let hint: String
        @ViewBuilder let content: Content

        var body: some View {
            VStack(alignment: .leading, spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(Theme.font.sectionHeading)
                        .foregroundStyle(Theme.color.ink)
                    Text(hint)
                        .font(Theme.font.label)
                        .foregroundStyle(Theme.color.muted)
                }
                .padding(.horizontal, 20)
                .padding(.top, 18)
                content
                Spacer(minLength: 0)
            }
            .frame(width: 400, alignment: .leading)
            .frame(maxHeight: .infinity, alignment: .top)
            .background(StagePanelBackground())
            .padding(.top, LiveView.headerHeight + 4)
            .padding(.bottom, LiveView.footerHeight + 4)
            .padding(.horizontal, 16)
            .accessibilityElement(children: .contain)
        }
    }
#endif
