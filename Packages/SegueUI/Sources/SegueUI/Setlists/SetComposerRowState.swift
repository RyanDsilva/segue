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
        }

        struct Ghost: Equatable {
            var text: String
            var isBreak = false
        }

        var isBreak = false
        /// The part a new row joins (its leading-edge colour).
        var part: Int
        var ghost: Ghost?
        var key = ""
        var capo = ""
        var time = ""
        var status: Status?
        var duplicate: SetlistItemID?
        var matchCount = 0
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
            case let .note(text):
                spoken += " \(text)."
            case nil:
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
            .accessibilityLabel("Suggestions")
            .accessibilityIdentifier(AccessibilityID.setlistComposerAlternatives)
        }

        private func row(index: Int, match: SongMatch) -> some View {
            let record = library.song(id: match.id)
            let preview = record
                .map { ComposerSlotPreview(record: $0, key: composer.resolution.key) }
            let isChosen = index == composer.choice
            let inSet = setlist.contains(match.id)
            let title = record.map(SongSummary.title) ?? "Missing song"
            return HStack(spacing: 8) {
                Color.clear.frame(width: 32, height: 1)
                Text(title)
                    .font(SchibstedGrotesk.semiBold.font(size: 14))
                    .foregroundStyle(isChosen ? Theme.color.ink : Theme.color.muted)
                    .lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: .leading)
                if inSet {
                    Text("In set")
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
            .accessibilityLabel(inSet ? "\(title), already in set" : title)
            .accessibilityAddTraits(isChosen ? [.isSelected, .isButton] : .isButton)
            .accessibilityAction { onPick(index) }
        }
    }
#endif
