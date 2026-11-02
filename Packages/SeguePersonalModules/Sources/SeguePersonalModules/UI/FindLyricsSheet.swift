import Plugins
import SegueUI
import SwiftUI

/// Find Lyrics (spec 6.4, R198 direction A): the search field in the title row with Artist
/// behind a disclosure; on the left one list holding the three fixed groups, each with its
/// count, spinner and status line, versions nested under their song; on the right the
/// preview of the selected version with its source line, Open in Safari and Review.
struct FindLyricsSheet: View {
    @Bindable var model: FindLyricsModel
    let host: ImportHost
    @FocusState private var focus: Field?

    enum Field: Hashable {
        case query
        case artist
        case list
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            HStack(spacing: 0) {
                results
                    .frame(width: 400)
                Divider()
                FindLyricsPreview(model: model)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .frame(maxHeight: .infinity)
        }
        .frame(width: 960, height: 600)
        .background(Theme.color.ground)
        .accessibilityIdentifier(AccessibilityID.findLyricsSheet)
        .onExitCommand { model.escape() }
        .onAppear {
            model.attach(host)
            focus = .query
        }
        .onDisappear { model.cancelSearch() }
        .sheet(item: $model.openHere) { request in
            OpenHereSheet(url: request.url, source: model.challengeSource) { cleared in
                model.openHereFinished(cleared: cleared)
            }
        }
    }

    // MARK: Header

    private var header: some View {
        HStack(spacing: 12) {
            Text(verbatim: "Find Lyrics")
                .font(SchibstedGrotesk.extraBold.font(size: 17))
                .foregroundStyle(Theme.color.ink)
            TextField(
                "Search",
                text: $model.query,
                prompt: Text(verbatim: "Song title, artist or a line"),
            )
            .textFieldStyle(.roundedBorder)
            .autocorrectionDisabled()
            .focused($focus, equals: .query)
            .onSubmit(search)
            .accessibilityLabel("Song title, artist or a line")
            .accessibilityIdentifier(AccessibilityID.findLyricsField)
            if model.showsArtist {
                TextField("Artist", text: $model.artist, prompt: Text(verbatim: "Artist"))
                    .textFieldStyle(.roundedBorder)
                    .autocorrectionDisabled()
                    .frame(width: 160)
                    .focused($focus, equals: .artist)
                    .onSubmit(search)
                    .accessibilityIdentifier(AccessibilityID.findLyricsArtist)
            }
            Button {
                model.showsArtist.toggle()
                focus = model.showsArtist ? .artist : .query
            } label: {
                HStack(spacing: 3) {
                    Text(verbatim: "Artist")
                    Image(systemName: model.showsArtist ? "chevron.down" : "chevron.right")
                        .font(.system(size: 9, weight: .semibold))
                }
                .font(SchibstedGrotesk.medium.font(size: 13))
                .foregroundStyle(Theme.color.muted)
            }
            .buttonStyle(.plain)
            .help("Narrow the search by artist")
            .accessibilityLabel(model
                .showsArtist ? "Hide the artist field" : "Show the artist field")
            Button("Search", action: search)
                .buttonStyle(.segueSecondary)
                .disabled(!model.canSearch)
            ImportHelpButton(topic: .search)
                .accessibilityIdentifier(AccessibilityID.findLyricsHelp)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 12)
    }

    private func search() {
        model.search()
        focus = .list
    }

    // MARK: Results

    private var results: some View {
        List(selection: $model.selection) {
            if !model.hasSearched {
                Text(verbatim: "Type a song and press Return. Ultimate Guitar, E-Chords and "
                    + "LRCLIB are searched together.")
                    .font(SchibstedGrotesk.medium.font(size: 13))
                    .foregroundStyle(Theme.color.muted)
                    .padding(.vertical, 8)
                    .selectionDisabled()
            } else {
                ForEach(model.groups) { group in
                    Section {
                        groupBody(group)
                    } header: {
                        groupHeader(group)
                    }
                }
            }
        }
        .listStyle(.sidebar)
        .scrollContentBackground(.hidden)
        .focused($focus, equals: .list)
        .contextMenu(forSelectionType: FindLyricsModel.Row.self) { _ in
        } primaryAction: { _ in
            model.pick()
        }
        .onKeyPress(.leftArrow) {
            model.setExpanded(false)
            return .handled
        }
        .onKeyPress(.rightArrow) {
            model.setExpanded(true)
            return .handled
        }
        .accessibilityIdentifier(AccessibilityID.findLyricsResults)
    }

    private func groupHeader(_ group: FindLyricsModel.Group) -> some View {
        HStack(spacing: 6) {
            Text(verbatim: group.name.uppercased())
                .font(SchibstedGrotesk.bold.font(size: 11))
                .tracking(0.6)
                .foregroundStyle(Theme.color.muted)
            Text(verbatim: "· " + count(group))
                .font(SchibstedGrotesk.medium.font(size: 11))
                .foregroundStyle(Theme.color.muted)
            Spacer()
            if group.status == .searching || group.status == .retrying {
                ProgressView().controlSize(.mini).padding(.trailing, 6)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(group.name), \(count(group))")
        .accessibilityAddTraits(.isHeader)
        .accessibilityIdentifier(AccessibilityID.findLyricsGroup(group.id.analyticsName))
    }

    private func count(_ group: FindLyricsModel.Group) -> String {
        switch group.status {
        case .searching where group.songs.isEmpty, .retrying where group.songs.isEmpty:
            return "searching…"
        case .failed: return "no results"
        default: break
        }
        let noun = group.id == .lyricsRecord ? "record" : "song"
        let count = group.songs.count
        return count == 1 ? "1 \(noun)" : "\(count) \(noun)s"
    }

    @ViewBuilder
    private func groupBody(_ group: FindLyricsModel.Group) -> some View {
        if group.status == .retrying {
            statusLine("\(group.name) is busy, retrying…", actions: [], group: group.id)
        }
        if case let .failed(_, message) = group.status, !message.text.isEmpty {
            statusLine(message.text, actions: message.actions, group: group.id)
        }
        if group.status == .done, group.songs.isEmpty {
            Text(
                verbatim: "No results for “\(model.query)”. Try the title only, or another spelling"
                    + ".",
            )
            .font(SchibstedGrotesk.medium.font(size: 12.5))
            .foregroundStyle(Theme.color.muted)
            .selectionDisabled()
        }
        ForEach(group.songs) { song in
            FindLyricsSongRow(
                song: song,
                expanded: model.expanded.contains(song.id),
                toggle: { toggle(song) },
            )
            .tag(FindLyricsModel.Row.song(song.id))
            .selectionDisabled(song.best.isInstrumental)
            .opacity(group.isStale || song.best.isInstrumental ? 0.45 : 1)
            .accessibilityIdentifier(AccessibilityID.findLyricsResult(index(of: .song(song.id))))
            if song.nests, model.expanded.contains(song.id) {
                ForEach(Array(song.versions.enumerated()), id: \.element.id) { offset, version in
                    let row = FindLyricsModel.Row.version(model.key(group.id, version))
                    FindLyricsVersionRow(version: version, isBest: offset == 0)
                        .tag(row)
                        .opacity(group.isStale ? 0.45 : 1)
                        .accessibilityIdentifier(AccessibilityID.findLyricsVersion(index(of: row)))
                }
            }
        }
        if !group.variants.isEmpty {
            Text(verbatim: "Also searched: " + group.variants.joined(separator: ", "))
                .font(SchibstedGrotesk.medium.font(size: 12))
                .foregroundStyle(Theme.color.muted)
                .selectionDisabled()
        }
    }

    private func statusLine(
        _ text: String,
        actions: [ImportCopy.Action],
        group: SearchGroup,
    ) -> some View {
        ImportMessageView(message: ImportCopy.Message(text: text, actions: actions)) { action in
            model.perform(action, in: group)
        }
        .padding(.vertical, 4)
        .selectionDisabled()
        .accessibilityIdentifier(AccessibilityID.findLyricsStatus)
    }

    private func toggle(_ song: FindLyricsModel.Song) {
        if model.expanded.contains(song.id) {
            model.expanded.remove(song.id)
        } else {
            model.expanded.insert(song.id)
        }
    }

    private func index(of row: FindLyricsModel.Row) -> Int {
        model.rows.firstIndex(of: row) ?? 0
    }
}

/// The right pane: the selected version as it will import, read-only, with its source line,
/// the group's attribution, Open in Safari and Review.
struct FindLyricsPreview: View {
    @Bindable var model: FindLyricsModel

    var body: some View {
        VStack(spacing: 0) {
            Group {
                switch model.preview {
                case .empty:
                    placeholder(model.rows.isEmpty ? "" : "Select a version to preview it.")
                case .loading:
                    ProgressView().controlSize(.small)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                case let .loaded(_, song, chordPro):
                    ScrollView {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(verbatim: sourceLine(song))
                                .font(SchibstedGrotesk.medium.font(size: 12.5))
                                .foregroundStyle(Theme.color.muted)
                            ChordProPageView(chordPro: chordPro)
                        }
                        .padding(.horizontal, 24)
                        .padding(.vertical, 20)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                case let .failed(_, text):
                    placeholder(text)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .accessibilityElement(children: .contain)
            .accessibilityLabel("Preview")
            .accessibilityIdentifier(AccessibilityID.findLyricsPreview)
            Divider()
            footer
        }
    }

    private var group: SearchGroup? {
        model.selection.flatMap { model.candidate(for: $0)?.0.group }
    }

    private var footer: some View {
        HStack(spacing: 10) {
            if let group {
                Button {
                    model.openSite(group)
                } label: {
                    Text(verbatim: SearchSite.attribution(group))
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .buttonStyle(.plain)
                .pointerStyle(.link)
                .font(SchibstedGrotesk.medium.font(size: 12))
                .foregroundStyle(Theme.color.muted)
                .accessibilityIdentifier(AccessibilityID.findLyricsAttribution)
            }
            Spacer(minLength: 12)
            Button("Cancel") { model.escape() }
                .buttonStyle(.segueSecondary)
            Button("Open in Safari") { model.openInBrowser() }
                .buttonStyle(.segueSecondary)
                .disabled(group == nil || group == .lyricsRecord)
            Button {
                model.pick()
            } label: {
                if model.isPicking {
                    ProgressView().controlSize(.mini)
                } else {
                    Text(verbatim: "Review")
                }
            }
            .buttonStyle(.seguePrimary)
            .keyboardShortcut(.return, modifiers: .command)
            .disabled(!canReview)
            .help("Review this version (⌘↩)")
            .accessibilityIdentifier(AccessibilityID.findLyricsReview)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 11)
    }

    private var canReview: Bool {
        if case .loaded = model.preview {
            return true
        }
        return false
    }

    private func sourceLine(_ song: ImportedSong) -> String {
        var parts = [song.provenance.attribution ?? "From "
            + WebAddress.siteHost(song.provenance.sourceURL)]
        if song.provenance.fellBack {
            parts.append("read with the general page reader")
        }
        if song.provenance.romanized {
            parts.append("converted from Devanagari")
        }
        return parts.joined(separator: " - ")
    }

    private func placeholder(_ text: String) -> some View {
        Text(verbatim: text)
            .font(SchibstedGrotesk.medium.font(size: 13))
            .foregroundStyle(Theme.color.muted)
            .multilineTextAlignment(.center)
            .padding(24)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

extension SearchGroup {
    /// The technique name, as analytics and the accessibility identifiers use it.
    var analyticsName: String {
        switch self {
        case .tabJSON: "tabJSON"
        case .chordPre: "chordPre"
        case .lyricsRecord: "lyricsRecord"
        }
    }
}
