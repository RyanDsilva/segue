#if os(macOS)
    import AppKit
    import Library
    import Services
    import Setlists
    import SwiftUI

    /// The set composer (P8-5, direction B): always the last row of the set list in Pick and
    /// Arrange. Type a few letters of a song, Return, next. The best library match shows as
    /// a muted ghost with the key, capo and time the new slot would show; ↓ / Tab open the
    /// alternatives under the row; "in A" sets the slot's gig key; "---" adds a break; a
    /// song already in the set is flagged, never added twice. The row is also the set's
    /// drop zone (a library song dropped on it is appended).
    struct SetComposerRow: View {
        let setlist: Setlist
        let model: SetlistsViewModel
        let library: LibraryViewModel
        let composer: SetComposerModel
        /// The set assistant's score column is shown on the rows above.
        var hasScores = false
        /// A drop of library songs or a dragged row onto the composer (appends).
        var onDrop: ([String]) -> Bool = { _ in false }
        /// Selects (and scrolls to) a row: the duplicate block.
        var onReveal: (SetlistItemID) -> Void = { _ in }
        /// A row was added: scroll so it and the composer show.
        var onAdded: (SetlistItemID) -> Void = { _ in }
        /// ↑ or Escape on an empty line: focus the set list on its last row.
        var onLeave: () -> Void = {}

        var body: some View {
            VStack(spacing: 0) {
                if isReadOnly {
                    readOnlyRow
                } else {
                    row
                    if composer.showsAlternatives, composer.resolution.matches.count > 1 {
                        ComposerAlternatives(
                            setlist: setlist,
                            library: library,
                            composer: composer,
                            trailingWidth: trailingWidth,
                            onPick: { index in
                                composer.choose(index)
                                accept()
                            },
                        )
                    }
                }
            }
            .contentShape(Rectangle())
            .dropDestination(for: String.self) { (items: [String], _: CGPoint) -> Bool in
                isReadOnly ? false : onDrop(items)
            }
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier(AccessibilityID.setlistDropZone)
            .onChange(of: library.catalogRevision) {
                composer.refresh(library: library)
            }
        }

        private var isReadOnly: Bool {
            setlist.readOnly != nil
        }

        /// The Start, lock, (score) and remove columns of the rows above, left empty.
        private var trailingWidth: CGFloat {
            60 + 8 + 20 + (hasScores ? 56 : 0) + 8 + 20
        }

        // MARK: The row

        private var row: some View {
            let state = ComposerRowState(composer: composer, setlist: setlist, library: library)
            return HStack(alignment: .firstTextBaseline, spacing: 8) {
                // The next slot number (a medley is one slot).
                Text(state.isBreak ? "" : "\(setlist.slotCount + 1)")
                    .font(SchibstedGrotesk.medium.font(size: 14))
                    .foregroundStyle(Theme.color.muted)
                    .frame(width: 32, alignment: .leading)
                    .accessibilityHidden(true)
                titleColumn(state)
                    .frame(maxWidth: .infinity, alignment: .leading)
                keyCell(state)
                if !state.isMedley {
                    cell(state.capo, width: 64, identifier: AccessibilityID.setlistComposerCapo)
                }
                cell(state.time, width: 56, identifier: AccessibilityID.setlistComposerTime)
                // Start, lock, (score) and remove columns of the rows above stay empty.
                Color.clear.frame(width: trailingWidth, height: 1)
            }
            .padding(.leading, 32)
            .padding(.trailing, 12)
            .padding(.vertical, 11)
            .background { rowBackground(state) }
            .overlay(alignment: .leading) {
                Rectangle()
                    .fill(PartPalette.color(state.part).opacity(composer.isFocused ? 0.55 : 0.3))
                    .frame(width: 4)
            }
            .overlay(alignment: .bottom) { Rule() }
            .help("Type a song name and press Return (\(MenuShortcuts.addSongByName.displayText))")
        }

        @ViewBuilder
        private func rowBackground(_ state: ComposerRowState) -> some View {
            if state.isBreak {
                LinearGradient(
                    colors: [PartPalette.color(state.part).opacity(0.14), .clear],
                    startPoint: .leading,
                    endPoint: .trailing,
                )
                .background(Theme.color.ground)
            } else if composer.isFocused {
                Theme.color.surfaceAlt.opacity(0.5).background(Theme.color.ground)
            } else {
                Theme.color.ground
            }
        }

        private func titleColumn(_ state: ComposerRowState) -> some View {
            VStack(alignment: .leading, spacing: 3) {
                ZStack(alignment: .topLeading) {
                    if composer.text.isEmpty {
                        placeholder
                    } else {
                        ghost(state)
                    }
                    ComposerTextField(
                        text: composer.text,
                        font: Self.fieldFont,
                        focusRequest: composer.focusRequest,
                        selectAllRequest: composer.selectAllRequest,
                        accessibilityLabel: "Add a song by name",
                        accessibilityValue: state.spokenValue,
                        onChange: { composer.setText($0, library: library) },
                        onFocusChange: focusChanged,
                        onCommand: handle,
                        onSelectionChange: { composer.setCaret($0) },
                    )
                    .frame(height: 22)
                }
                // The field has no text baseline for SwiftUI: its text starts at the top, so
                // the baseline is the face's ascender down (aligns # and the cells with it).
                .alignmentGuide(.firstTextBaseline) { [baseline = Self.fieldBaseline] _ in
                    baseline
                }
                if let status = state.status {
                    statusLine(status, state: state)
                }
            }
            .overlay(alignment: .topTrailing) {
                if composer.showsAlternatives, state.matchCount > 1 {
                    Text("\(composer.choice + 1) of \(state.matchCount)")
                        .font(SchibstedGrotesk.medium.font(size: 12))
                        .monospacedDigit()
                        .foregroundStyle(Theme.color.muted)
                        .padding(.top, 3)
                        .padding(.trailing, 8)
                        .accessibilityIdentifier(AccessibilityID.setlistComposerCounter)
                }
            }
        }

        /// "Add a song - type its name", with the ⌘L hint while the field is not focused.
        private var placeholder: some View {
            HStack(spacing: 8) {
                Text("Add a song - type its name")
                    .font(Self.swiftUIFieldFont)
                    .foregroundStyle(Theme.color.muted)
                    .lineLimit(1)
                if !composer.isFocused {
                    Text(MenuShortcuts.addSongByName.displayText)
                        .font(SchibstedGrotesk.medium.font(size: 12))
                        .foregroundStyle(Theme.color.muted)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 1)
                        .overlay {
                            RoundedRectangle(cornerRadius: 4)
                                .strokeBorder(Theme.color.lineStrong, lineWidth: 1)
                        }
                }
            }
            .padding(.leading, Self.textInset)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
        }

        /// The ghost after the typed text: the rest of the title ("Kesa|riya"), or the
        /// whole title after an arrow when the line does not start it ("kesriya → Kesariya").
        /// A click on it accepts, like Return.
        @ViewBuilder
        private func ghost(_ state: ComposerRowState) -> some View {
            if let ghost = state.ghost {
                Text(ghost.text)
                    .font(Self.swiftUIFieldFont)
                    .foregroundStyle(ghost.isBreak ? PartPalette.color(state.part) : Theme
                        .color.muted)
                    .lineLimit(1)
                    .contentShape(Rectangle())
                    .onTapGesture { accept() }
                    .padding(.leading, Self.textInset + Self.typedWidth(composer.text))
                    // SwiftUI sets the face a point lower than the field does.
                    .offset(y: -2)
                    .accessibilityIdentifier(AccessibilityID.setlistComposerGhost)
                    .accessibilityHidden(true)
            }
        }

        private func statusLine(_ status: ComposerRowState.Status, state: ComposerRowState)
            -> some View
        {
            Group {
                switch status {
                case let .alreadyInSet(item, position):
                    Button {
                        onReveal(item)
                    } label: {
                        Label(
                            "Already in the set at #\(position)",
                            systemImage: "exclamationmark.triangle.fill",
                        )
                        .symbolRenderingMode(.multicolor)
                    }
                    .buttonStyle(.plain)
                    .help("Show it in the set")
                case let .note(text):
                    Text(text)
                case let .blocked(item, text):
                    Button {
                        onReveal(item)
                    } label: {
                        Label(text, systemImage: "exclamationmark.triangle.fill")
                            .symbolRenderingMode(.multicolor)
                    }
                    .buttonStyle(.plain)
                    .help("Show it in the set")
                case let .medley(parts):
                    medleyLine(parts, active: state.activePart)
                }
            }
            .font(SchibstedGrotesk.medium.font(size: 13))
            .foregroundStyle(Theme.color.muted)
            .lineLimit(1)
            .padding(.leading, Self.textInset)
            .accessibilityIdentifier(AccessibilityID.setlistComposerStatus)
        }

        /// "Medley · Kesariya (A) + Tum Hi Ho (G, reprise of 2)": the parts in the title's
        /// colour, the joins muted (R187 composer A); the part under the caret, whose
        /// alternatives ↑ / ↓ and Tab cycle, underlined.
        private func medleyLine(_ parts: [ComposerRowState.MedleyPart], active: Int?) -> Text {
            var line = Text(verbatim: "Medley · ").foregroundStyle(Theme.color.muted)
            for (index, part) in parts.enumerated() {
                if index > 0 {
                    let join = Text(verbatim: "  +  ").foregroundStyle(Theme.color.muted)
                    line = Text("\(line)\(join)")
                }
                let detail = part.detail.map { " (\($0))" } ?? ""
                let text = Text(verbatim: part.title + detail)
                    .foregroundStyle(Theme.color.ink)
                    .underline(index == active && parts.count > 1)
                line = Text("\(line)\(text)")
            }
            return line
        }

        @ViewBuilder
        private func keyCell(_ state: ComposerRowState) -> some View {
            if state.isMedley {
                // The key path ("E → G → G") spans the key and capo columns.
                cell(
                    state.key,
                    width: 56 + 8 + 64,
                    weight: .semiBold,
                    identifier: AccessibilityID.setlistComposerKey,
                )
            } else if state.duplicate != nil {
                Text("In set")
                    .font(SchibstedGrotesk.semiBold.font(size: 11))
                    .foregroundStyle(Theme.color.muted)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .overlay {
                        RoundedRectangle(cornerRadius: 4)
                            .strokeBorder(Theme.color.lineStrong, lineWidth: 1)
                    }
                    .fixedSize()
                    .frame(width: 56, alignment: .leading)
                    .accessibilityIdentifier(AccessibilityID.setlistComposerKey)
            } else {
                cell(
                    state.key,
                    width: 56,
                    weight: .semiBold,
                    identifier: AccessibilityID.setlistComposerKey,
                )
            }
        }

        private func cell(
            _ text: String,
            width: CGFloat,
            weight: SchibstedGrotesk = .medium,
            identifier: String,
        ) -> some View {
            Text(text)
                .font(weight.font(size: 14))
                .foregroundStyle(Theme.color.muted)
                .lineLimit(1)
                .frame(width: width, alignment: .leading)
                .accessibilityIdentifier(identifier)
        }

        private var readOnlyRow: some View {
            Text("Read-only - this setlist was saved by a newer Segue")
                .font(SchibstedGrotesk.medium.font(size: 14))
                .foregroundStyle(Theme.color.muted)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.leading, 72)
                .padding(.vertical, 14)
        }
    }

    extension SetComposerRow {
        // MARK: Keys and actions

        fileprivate func handle(_ command: ComposerCommand) -> Bool {
            switch command {
            case .accept:
                accept()
                return true
            case .next:
                return composer.cycle(by: 1) || !composer.text.isEmpty
            case .previous:
                if composer.text.isEmpty {
                    onLeave()
                    return true
                }
                return composer.cycle(by: -1) || true
            case .tab:
                guard !composer.text.isEmpty else { return false }
                _ = composer.cycle(by: 1)
                return true
            case .backtab:
                guard !composer.text.isEmpty else { return false }
                _ = composer.cycle(by: -1)
                return true
            case .escape:
                if composer.escape() == .leave {
                    onLeave()
                }
                return true
            }
        }

        /// Return (or a click on the ghost): add the shown song or the break, as one undo
        /// step; flag a song already in the set; nothing for a line that names no song.
        fileprivate func accept() {
            guard !isReadOnly else { return }
            let resolution = composer.resolution
            guard resolution.kind != .empty else { return }
            let typed = composer.text
            let choice = composer.choice
            let partChoices = composer.partChoices
            let setlistID = setlist.id
            composer.track(accept: Task {
                let outcome = await model.compose(
                    resolution,
                    choice: choice,
                    partChoices: partChoices,
                    in: setlistID,
                    songs: library.song(id:),
                    entry: composer.entry,
                )
                composer.noteReturn(outcome)
                apply(outcome, typed: typed, choice: choice)
            })
        }

        fileprivate func apply(_ outcome: ComposeOutcome, typed: String, choice: Int) {
            switch outcome {
            case let .added(item), let .breakAdded(item):
                // Text typed while the write was in flight stays.
                if composer.text == typed {
                    composer.clear()
                }
                onAdded(item)
                announce(addedMessage(item))
            case let .alreadyInSet(item):
                onReveal(item)
                composer.requestSelectAll()
                let match = composer.resolution.matches.indices.contains(choice)
                    ? composer.resolution.matches[choice] : nil
                if composer.resolution.kind == .medley {
                    let state = ComposerRowState(
                        composer: composer,
                        setlist: model.setlist(setlist.id) ?? setlist,
                        library: library,
                    )
                    if case let .blocked(_, text) = state.status {
                        announce(text)
                    }
                    return
                }
                let title = match.flatMap { library.song(id: $0.id) }.map(SongSummary.title)
                if let title, let position = position(of: item) {
                    announce("\(title) is already number \(position)")
                }
            case .ignored, .noMatch:
                break
            }
        }

        fileprivate func addedMessage(_ item: SetlistItemID) -> String {
            let current = model.setlist(setlist.id) ?? setlist
            guard let entry = current.entry(item) else { return "Added" }
            if let info = entry.breakInfo {
                return "Added break, \(info.label)"
            }
            if let medley = entry.medley {
                return "Added \(medley.displayTitle) of \(medley.members.count) songs, "
                    + "number \(current.slotCount)"
            }
            let title = entry.songId.flatMap(library.song(id:)).map(SongSummary.title) ?? "song"
            return "Added \(title), number \(current.slotCount)"
        }

        fileprivate func position(of item: SetlistItemID) -> Int? {
            let current = model.setlist(setlist.id) ?? setlist
            return ComposerRowState.songNumber(of: item, in: current)
        }

        fileprivate func focusChanged(_ focused: Bool) {
            if focused {
                composer.refresh(library: library)
            }
            if let session = composer.focusChanged(focused) {
                model.recordComposerSession(songs: session.songs, cycles: session.cycles)
            }
        }

        fileprivate func announce(_ message: String) {
            AccessibilityNotification.Announcement(message).post()
        }

        // MARK: Metrics

        /// Schibsted Grotesk semibold 16, ink: the title column's face.
        static let fieldFont: NSFont = {
            _ = FontRegistration.registerBundledFonts()
            return NSFont(name: SchibstedGrotesk.semiBold.rawValue, size: 16)
                ?? .systemFont(ofSize: 16, weight: .semibold)
        }()

        /// The field's first text baseline from its top: the face's ascender, nudged up 2 pt.
        /// Read on the main actor and captured by value, since the alignment guide closure
        /// is Sendable.
        static var fieldBaseline: CGFloat {
            ceil(fieldFont.ascender) - 2
        }

        static let swiftUIFieldFont = SchibstedGrotesk.semiBold.font(size: 16)

        /// The typed text's width in the field's font, where the ghost starts.
        static func typedWidth(_ text: String) -> CGFloat {
            ceil((text as NSString).size(withAttributes: [.font: fieldFont]).width)
        }

        /// Where a borderless `NSTextField` starts drawing its text.
        static let textInset: CGFloat = 0
    }
#endif
