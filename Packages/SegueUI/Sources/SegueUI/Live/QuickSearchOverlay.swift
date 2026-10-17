#if os(macOS)
    import Editing
    import Library
    import Shows
    import SwiftUI

    /// Cmd-K or /: search the library mid-show without leaving the stage. Up/Down select,
    /// Return plays now, Cmd-Return adds to requests, Option-Return inserts next, Esc goes
    /// back to the song at the same scroll position (keys handled by `LiveKeyInput`).
    struct QuickSearchOverlay: View {
        let session: LiveSession
        @FocusState private var fieldFocused: Bool

        var body: some View {
            @Bindable var search = session.search
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 12) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(Theme.color.muted)
                        .accessibilityHidden(true)
                    TextField("Search title, artist, first line or tag", text: $search.query)
                        .textFieldStyle(.plain)
                        .font(SchibstedGrotesk.medium.font(size: 22))
                        .foregroundStyle(Theme.color.ink)
                        .autocorrectionDisabled()
                        .focused($fieldFocused)
                        .accessibilityIdentifier(AccessibilityID.liveSearchField)
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 16)
                Rectangle().fill(Theme.color.line).frame(height: 1)
                results
                Rectangle().fill(Theme.color.line).frame(height: 1)
                actions
            }
            .frame(width: 720)
            .background(StagePanelBackground())
            .shadow(color: .black.opacity(0.5), radius: 30, y: 12)
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier(AccessibilityID.liveSearch)
            .defaultFocus($fieldFocused, true)
            .task {
                // Once the field is in the window (the stage is a borderless window).
                fieldFocused = true
                try? await Task.sleep(for: .milliseconds(50))
                fieldFocused = true
            }
        }

        @ViewBuilder private var results: some View {
            let search = session.search
            if let error = search.errorMessage {
                message(error)
            } else if search.results.isEmpty {
                let query = search.query.trimmingCharacters(in: .whitespaces)
                message(query.isEmpty
                    ? "Type to search the library. Spelling variants match (“pyar” finds “Pyaar”)."
                    : "No songs match “\(query)”.")
            } else {
                VStack(spacing: 2) {
                    ForEach(Array(search.results.enumerated()), id: \.element.id) { index, song in
                        SearchResultRow(
                            song: song,
                            isSelected: index == search.selection,
                            inSet: isPendingInSet(song.id),
                        )
                        .contentShape(Rectangle())
                        .onTapGesture(count: 2) { session.searchAction(.playNow, song: song.id) }
                        .onTapGesture { search.selection = index }
                    }
                }
                .padding(8)
            }
        }

        private func message(_ text: String) -> some View {
            Text(text)
                .font(Theme.font.body)
                .foregroundStyle(Theme.color.muted)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 20)
                .padding(.vertical, 18)
        }

        private var actions: some View {
            let selected = session.search.selected
            return HStack(spacing: 10) {
                Text("Esc returns to the song")
                    .font(Theme.font.label)
                    .foregroundStyle(Theme.color.muted)
                Spacer()
                actionButton(.insertNext, hint: "⌥↩", song: selected)
                    .buttonStyle(.segueSecondary)
                    .accessibilityIdentifier(AccessibilityID.liveSearchInsertNext)
                actionButton(.addRequest, hint: "⌘↩", song: selected)
                    .buttonStyle(.segueSecondary)
                    .accessibilityIdentifier(AccessibilityID.liveSearchAddRequest)
                actionButton(.playNow, hint: "↩", song: selected)
                    .buttonStyle(.seguePrimary)
                    .accessibilityIdentifier(AccessibilityID.liveSearchPlayNow)
            }
            .controlSize(.regular)
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
        }

        private func actionButton(
            _ action: LiveSession.SearchAction,
            hint: String,
            song: SongRecord?,
        ) -> some View {
            Button("\(action.title)  \(hint)") {
                if let song {
                    session.searchAction(action, song: song.id)
                }
            }
            .disabled(song == nil)
        }

        private func isPendingInSet(_ id: SongID) -> Bool {
            session.state.record.items.contains { $0.songId == id && $0.state == .pending }
        }
    }

    /// One search result: title and artist, then key, capo and proficiency.
    private struct SearchResultRow: View {
        let song: SongRecord
        let isSelected: Bool
        let inSet: Bool

        var body: some View {
            let metadata = song.document.metadata
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(SongSummary.title(song))
                        .font(SchibstedGrotesk.semiBold.font(size: 17))
                        .foregroundStyle(Theme.color.ink)
                        .lineLimit(1)
                    if let artist = SongSummary.artist(metadata) {
                        Text(artist)
                            .font(Theme.font.label)
                            .foregroundStyle(Theme.color.muted)
                            .lineLimit(1)
                    }
                }
                Spacer(minLength: 12)
                if inSet {
                    StageChip(text: "In set")
                }
                if let key = metadata.key, !key.isEmpty {
                    StageChip(text: key)
                }
                if let capo = metadata.capo, capo > 0 {
                    StageChip(text: "Capo \(capo)")
                }
                if let proficiency = song.sidecar.proficiency {
                    ProficiencyMark(proficiency)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(isSelected ? Theme.color.ink.opacity(0.08) : .clear)
            }
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier(AccessibilityID.liveSearchResult)
            .accessibilityAddTraits(isSelected ? .isSelected : [])
        }
    }
#endif
