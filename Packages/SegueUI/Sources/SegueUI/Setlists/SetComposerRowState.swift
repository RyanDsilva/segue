#if os(macOS)
    import Library
    import Setlists
    import SwiftUI

    /// What the composer row shows for the current line, derived from the model (P8-5
    /// section 4.2): the ghost, the new slot's cells, the status line and the field's
    /// spoken value.
    @MainActor
    struct ComposerRowState {
        enum Status: Equatable {
            case alreadyInSet(SetlistItemID, position: Int)
            case note(String)
            /// A medley part's song is already a member ("Tum Hi Ho is already 4b"): the row
            /// it points at and the text.
            case blocked(SetlistItemID, String)
            /// A " + " line that would add: "Medley · Kesariya (A) + Tum Hi Ho (G, reprise
            /// of 2)" (R187 composer A).
            case medley([MedleyPart])
        }

        /// One part of the medley status line: the title and its detail ("G, reprise of 2").
        struct MedleyPart: Equatable {
            var title: String
            var detail: String?
        }

        struct Ghost: Equatable {
            var text: String
            var isBreak = false
        }

        var isBreak = false
        /// A " + " line: the key cell shows the key path and spans the capo column.
        var isMedley = false
        /// The part a new row joins (its leading-edge colour).
        var part: Int
        var ghost: Ghost?
        var key = ""
        var capo = ""
        var time = ""
        var status: Status?
        var duplicate: SetlistItemID?
        var matchCount = 0
        /// A medley line's part under the caret (0-based): the status line marks it.
        var activePart: Int?
        /// The field's accessibility value: the suggestion and the status.
        var spokenValue = ""

        init(composer: SetComposerModel, setlist: Setlist, library: LibraryViewModel) {
            let resolution = composer.resolution
            let breaks = setlist.entries.count(where: \.isBreak)
            part = breaks
            matchCount = resolution.matches.count
            switch resolution.kind {
            case .empty:
                return
            case .breakRow:
                isBreak = true
                part = breaks + 1
                let label = setlist.breakLabel(at: setlist.entries.count)
                ghost = Ghost(text: "   → Break, \(label)", isBreak: true)
                spokenValue = "Suggestion: a break, \(label)."
            case .song:
                guard let match = composer.chosen else {
                    status = .note("No song matches")
                    spokenValue = "No song matches"
                    return
                }
                describe(match, composer: composer, setlist: setlist, library: library)
            case .medley:
                describeMedley(composer: composer, setlist: setlist, library: library)
            }
        }

        private mutating func describe(
            _ match: SongMatch,
            composer: SetComposerModel,
            setlist: Setlist,
            library: LibraryViewModel,
        ) {
            let resolution = composer.resolution
            let record = library.song(id: match.id)
            let title = record.map(SongSummary.title) ?? "Missing song"
            let preview = record.map { ComposerSlotPreview(record: $0, key: resolution.key) }
            if resolution.key == nil, composer.choice == 0,
               let suffix = SetComposer.ghostSuffix(typed: composer.text, title: title)
            {
                ghost = Ghost(text: suffix)
            } else {
                ghost = Ghost(text: "   → \(title)")
            }
            key = preview?.display.key ?? "-"
            capo = preview?.display.capoText ?? ""
            let slotTime = record.map { library.times.song($0) }
            time = Self.cell(slotTime)
            if let existing = setlist.entries.first(where: { $0.songId == match.id }),
               let position = Self.songNumber(of: existing.itemId, in: setlist)
            {
                duplicate = existing.itemId
                status = .alreadyInSet(existing.itemId, position: position)
            } else if case let .reprise(occurrence) = setlist.canAdd(match.id, as: .slot),
                      case let .member(entryId, _, label) = occurrence
            {
                // Decision 8: a member-only song comes back as its reprise slot.
                let medley = setlist.entry(entryId)?.medley?.displayTitle ?? "a medley"
                status = .note("\(title) · also \(label) in \(medley): adds a reprise")
            } else if preview?.keyIgnored == true, let typedKey = resolution.key {
                status = .note("This song has no key, so 'in \(typedKey.name)' is ignored")
            } else if match.tier == .fuzzyTitle {
                status = .note("Close spelling")
            } else if match.tier == .firstLine, let line = record?.document.firstLyricLine {
                status = .note("From the first line: \(line)")
            } else if let artist = match.artist {
                // The artist tier, or trailing words that named the artist (P8-8 3.5.1).
                status = .note("By \(artist)")
            }
            spokenValue = spoken(
                title: title,
                time: slotTime,
                choice: composer.choice,
            )
        }

        /// A " + " line (P9-3 section 10, R187 composer A): the ghost shows the part under the
        /// caret (completing the last part as it is typed, else "→ Title"), the key cell
        /// shows the key path, the time cell the medley's time, and the status line spells
        /// the medley out, the caret's part marked, or names the first failing part.
        private mutating func describeMedley(
            composer: SetComposerModel,
            setlist: Setlist,
            library: LibraryViewModel,
        ) {
            isMedley = true
            let resolution = composer.resolution
            let picks = SetComposer.medleyPicks(resolution, choices: composer.partChoices)
            let active = min(composer.activePart, max(picks.count - 1, 0))
            activePart = active
            let records = picks.map { $0.flatMap { library.song(id: $0.id) } }
            let titles = records.map { $0.map(SongSummary.title) ?? "Missing song" }
            let keys = zip(records, resolution.parts).map { record, part in
                record.flatMap { ComposerSlotPreview(record: $0, key: part.key).display.key }
            }
            key = keys.map { $0 ?? "?" }.joined(separator: " → ")
            let time = MedleyTime(members: records.map { record in
                record.map { library.times.song($0) } ?? .unknown(.missingSong)
            })
            self.time = time.hasKnown ? time.clock : "-"
            if records.indices.contains(active), let record = records[active] {
                let lastText = composer.text
                    .components(separatedBy: SetComposerLine.medleySeparator).last ?? ""
                let title = SongSummary.title(record)
                // Only the last part's completion can follow the typed text.
                if active == records.count - 1, resolution.key == nil, composer.choice == 0,
                   let suffix = SetComposer.ghostSuffix(typed: lastText, title: title)
                {
                    ghost = Ghost(text: suffix)
                } else {
                    ghost = Ghost(text: "   → \(title)")
                }
            }
            let check = SetComposer.checkMedley(
                picks.map { $0?.id },
                queries: resolution.parts.map(\.query),
                in: setlist,
            )
            status = Self.medleyStatus(check, titles: titles, keys: keys, resolution: resolution)
            if case let .blocked(item, _) = status {
                duplicate = item
            }
            var spoken = "Suggestion: medley of \(titles.count) songs, "
                + titles.joined(separator: ", ")
            if time.hasKnown {
                spoken += ", \(time.spoken)"
            }
            spoken += "."
            if case let .note(text) = status {
                spoken += " Not added: \(text)."
            } else if case let .blocked(_, text) = status {
                spoken += " Not added: \(text)."
            }
            spokenValue = spoken
        }

        /// The status line for a medley line's check.
        private static func medleyStatus(
            _ check: SetComposer.MedleyCheck,
            titles: [String],
            keys: [String?],
            resolution: SetComposerResolution,
        ) -> Status {
            func title(_ part: Int) -> String {
                titles.indices.contains(part - 1) ? titles[part - 1] : "Song \(part)"
            }
            switch check {
            case let .ok(reprises):
                return .medley(titles.indices.map { index in
                    let details = [
                        keys[index],
                        reprises[index + 1].map { "reprise of \($0.label)" },
                    ]
                    .compactMap(\.self)
                    return MedleyPart(
                        title: titles[index],
                        detail: details.isEmpty ? nil : details.joined(separator: ", "),
                    )
                })
            case let .noMatch(part):
                let query = resolution.parts.indices.contains(part - 1)
                    ? resolution.parts[part - 1].query : ""
                return .note("No song matches '\(query)' (song \(part))")
            case let .emptyPart(part):
                return .note("Song \(part) is empty")
            case let .duplicate(part, earlier):
                return .note(
                    "\(title(part)) is in this medley twice (songs \(earlier) and \(part))",
                )
            case let .inSet(part, occurrence):
                return .blocked(
                    SetlistsViewModel.revealed(occurrence),
                    "\(title(part)) is already \(occurrence.label)",
                )
            case .tooMany:
                return .note("A medley holds at most \(SetlistMedley.maxMembers) songs")
            }
        }

        /// The ghost's Time cell: "3:40", "~3:40", or "-" when unknown (never a guess).
        static func cell(_ time: SlotTime?) -> String {
            guard let time, time.seconds != nil else { return "-" }
            return time.clock
        }

        /// "Suggestion: Kesariya, key A, 4:05. 1 of 3." plus the status line.
        private func spoken(title: String, time: SlotTime?, choice: Int) -> String {
            var spoken = "Suggestion: \(title)"
            if key != "-" {
                spoken += ", key \(key)"
            }
            if let time, time.seconds != nil {
                spoken += ", \(time.spoken)"
            }
            spoken += ". \(choice + 1) of \(matchCount)."
            switch status {
            case let .alreadyInSet(_, position):
                spoken += " Already in the set at number \(position)."
            case let .blocked(_, text), let .note(text):
                spoken += " \(text)."
            case .medley, nil:
                break
            }
            return spoken
        }

        /// The 1-based song number of `item` (break rows are not numbered).
        static func songNumber(of item: SetlistItemID, in setlist: Setlist) -> Int? {
            var count = 0
            for entry in setlist.entries where !entry.isBreak {
                count += 1
                if entry.itemId == item {
                    return count
                }
            }
            return nil
        }
    }

    /// Direction B's alternatives (R158 Q3): up to five candidates under the composer row
    /// from the first ↓ / Tab, the shown one marked; a click adds that one.
    struct ComposerAlternatives: View {
        let setlist: Setlist
        let library: LibraryViewModel
        let composer: SetComposerModel
        /// The empty trailing columns of the rows above.
        let trailingWidth: CGFloat
        let onPick: (Int) -> Void

        var body: some View {
            VStack(spacing: 0) {
                ForEach(
                    Array(composer.resolution.matches.enumerated()),
                    id: \.offset,
                ) { index, match in
                    row(index: index, match: match)
                }
            }
            .padding(.vertical, 4)
            .background(Theme.color.surfaceAlt.opacity(0.6))
            .background(Theme.color.ground)
            .overlay(alignment: .bottom) { Rule() }
            .accessibilityElement(children: .contain)
            .accessibilityLabel(uiString("Suggestions"))
            .accessibilityIdentifier(AccessibilityID.setlistComposerAlternatives)
        }

        private func row(index: Int, match: SongMatch) -> some View {
            let record = library.song(id: match.id)
            let preview = record
                .map { ComposerSlotPreview(record: $0, key: composer.resolution.key) }
            let isChosen = index == composer.choice
            // Refused where it would go (decision 8): a song line needs no plain slot of it,
            // a medley part no member of it.
            let role: AddRole = composer.resolution.kind == .medley
                ? .member(of: SetComposer.newMedley) : .slot
            let inSet = !setlist.canAdd(match.id, as: role).isAllowed
            let title = record.map(SongSummary.title) ?? "Missing song"
            return HStack(spacing: 8) {
                Color.clear.frame(width: 32, height: 1)
                Text(title)
                    .font(SchibstedGrotesk.semiBold.font(size: 14))
                    .foregroundStyle(isChosen ? Theme.color.ink : Theme.color.muted)
                    .lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: .leading)
                if inSet {
                    Text("In set", bundle: #bundle)
                        .font(SchibstedGrotesk.semiBold.font(size: 12))
                        .foregroundStyle(Theme.color.muted)
                }
                Text(preview?.display.key ?? "-")
                    .font(SchibstedGrotesk.semiBold.font(size: 13))
                    .foregroundStyle(Theme.color.muted)
                    .frame(width: 56, alignment: .leading)
                Color.clear.frame(width: 64, height: 1)
                Text(ComposerRowState.cell(record.map { library.times.song($0) }))
                    .font(SchibstedGrotesk.medium.font(size: 13))
                    .foregroundStyle(Theme.color.muted)
                    .frame(width: 56, alignment: .leading)
                Color.clear.frame(width: trailingWidth, height: 1)
            }
            .padding(.leading, 32)
            .padding(.trailing, 12)
            .padding(.vertical, 5)
            .background(isChosen ? Theme.color.surfaceAlt : Color.clear)
            .overlay(alignment: .leading) {
                if isChosen {
                    Rectangle().fill(Theme.color.ink).frame(width: 3).padding(.leading, 32)
                }
            }
            .contentShape(Rectangle())
            .onTapGesture { onPick(index) }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(inSet ? uiString("\(title), already in set") : title)
            .accessibilityAddTraits(isChosen ? [.isSelected, .isButton] : .isButton)
            .accessibilityAction { onPick(index) }
        }
    }
#endif
