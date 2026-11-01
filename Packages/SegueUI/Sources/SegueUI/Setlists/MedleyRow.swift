#if os(macOS)
    import AppKit
    import Library
    import Setlists
    import SwiftUI

    /// A medley slot in the set list (P9-3 6.2, R187): the group card (direction A) holding
    /// the header, the member rows and the transition rows; its disclosure collapses it to
    /// one row of member chips (direction C).
    struct MedleyRow: View {
        let entry: SetlistEntry
        let medley: SetlistMedley
        let number: Int
        let part: Int
        let setlist: Setlist
        let model: SetlistsViewModel
        let library: LibraryViewModel
        let timing: ItemTiming?
        let isReadOnly: Bool
        /// The header's lock (on and disabled: medleys stay in place on Rebuild).
        let assistant: EntryAssistant
        /// A click on a row: returns whether it was plain (the list's selection rules).
        let onSelect: (SetlistItemID) -> Bool
        /// Library songs or a set row dropped on a member (inserted before it; nil = at the
        /// end of the medley).
        let onDropMember: ([String], Int?) -> Bool
        @State private var isHovered = false
        @Environment(\.arrangementStage) private var stage

        private var isCollapsed: Bool {
            model.collapsedMedleys.contains(entry.itemId)
        }

        private var isSelected: Bool {
            model.arrangeSelection.contains(entry.itemId)
        }

        var body: some View {
            Group {
                if isCollapsed {
                    header(collapsed: true)
                        .padding(.leading, 32)
                        .padding(.trailing, 12)
                        .padding(.vertical, 10)
                        .background(isSelected || isHovered ? Theme.color.surfaceAlt
                            : Theme.color.ground)
                } else {
                    card
                        .padding(.horizontal, MedleyMemberPlace.cardInset)
                        .padding(.vertical, 8)
                        .background(Theme.color.ground)
                }
            }
            .overlay(alignment: .leading) {
                Rectangle().fill(PartPalette.color(part)).frame(width: 4)
            }
            .overlay(alignment: .bottom) { Rule() }
        }

        private var card: some View {
            VStack(spacing: 0) {
                header(collapsed: false)
                    .padding(.leading, 32 - MedleyMemberPlace.cardInset)
                    .padding(.trailing, 12 - MedleyMemberPlace.cardInset)
                    .padding(.vertical, 10)
                    .background(isSelected || isHovered ? Theme.color.line : .clear)
                Rectangle().fill(Theme.color.line).frame(height: 1)
                    .accessibilityHidden(true)
                ForEach(Array(medley.members.enumerated()), id: \.element.itemId) { index, member in
                    if index > 0 {
                        MedleyTransitionRow(
                            member: member,
                            title: title(of: member),
                            changes: changes(into: index),
                            isReadOnly: isReadOnly,
                            onCommit: { text in
                                Task {
                                    await model.setTransition(
                                        text,
                                        member: member.itemId,
                                        in: setlist.id,
                                    )
                                }
                            },
                        )
                    }
                    memberRow(member, index: index)
                }
                if medley.members.count < 2 {
                    lonelyHint
                }
            }
            .padding(.bottom, 4)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Theme.color.surfaceAlt),
            )
            .overlay {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(Theme.color.line, lineWidth: 1)
            }
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
    }

    // MARK: - Header

    extension MedleyRow {
        private func header(collapsed: Bool) -> some View {
            HStack(alignment: collapsed ? .center : .firstTextBaseline, spacing: 8) {
                Text("\(number)")
                    .font(SchibstedGrotesk.medium.font(size: 14))
                    .foregroundStyle(Theme.color.muted)
                    .frame(width: 32, alignment: .leading)
                VStack(alignment: .leading, spacing: 6) {
                    titleLine(showsCount: !collapsed)
                    if collapsed {
                        MedleyChips(
                            members: medley.members,
                            number: number,
                            titles: medley.members.map(title(of:)),
                            keys: medley.members.map(key(of:)),
                            capoChanges: medley.members.indices.map(capoChanges(into:)),
                        )
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                columns
                EntryAssistantCells(assistant: assistant, title: displayTitle, isHovered: false)
                disclosure
            }
            .contentShape(Rectangle())
            .onHover { isHovered = $0 }
            .onTapGesture(count: 2) {
                guard !isReadOnly else { return }
                _ = onSelect(entry.itemId)
                model.renamingMedley = entry.itemId
            }
            .onTapGesture { _ = onSelect(entry.itemId) }
            .contextMenu { headerMenu }
            .accessibilityElement(children: .contain)
            .accessibilityLabel(accessibilityLabel)
            .accessibilityAddTraits(isSelected ? .isSelected : [])
            .accessibilityIdentifier(AccessibilityID.medley)
            .accessibilityActions { headerActions }
            .dropDestination(for: String.self) { items, _ in
                onDropMember(items, nil)
            } isTargeted: { _ in }
        }

        /// Key path, time and start, in the set rows' columns.
        @ViewBuilder private var columns: some View {
            Text(keyPath)
                .font(SchibstedGrotesk.semiBold.font(size: 14))
                .foregroundStyle(Theme.color.ink)
                .lineLimit(1)
                .frame(width: 56 + 8 + 64, alignment: .leading)
                .accessibilityLabel("Keys \(keyPath.replacingOccurrences(of: "→", with: "to"))")
                .accessibilityIdentifier(AccessibilityID.medleyKeyPath)
            Text(timeText)
                .font(SchibstedGrotesk.medium.font(size: 14))
                .foregroundStyle(Theme.color.muted)
                .lineLimit(1)
                .frame(width: 56, alignment: .leading)
                .help(timeHelp)
                .accessibilityValue(timing?.medley?.time.spoken ?? "")
                .accessibilityIdentifier(AccessibilityID.entryTime)
            Text(timing?.startText ?? "")
                .font(SchibstedGrotesk.medium.font(size: 14))
                .foregroundStyle(Theme.color.muted)
                .lineLimit(1)
                .frame(width: 60, alignment: .trailing)
                .accessibilityIdentifier(AccessibilityID.entryStart)
        }

        private func titleLine(showsCount: Bool) -> some View {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text("MEDLEY")
                    .font(SchibstedGrotesk.bold.font(size: 11))
                    .tracking(0.88)
                    .foregroundStyle(Theme.color.muted)
                    .accessibilityHidden(true)
                if model.renamingMedley == entry.itemId, !isReadOnly {
                    MedleyTitleField(
                        title: medley.title ?? "",
                        onCommit: { title in
                            model.renamingMedley = nil
                            guard title != (medley.title ?? "") else { return }
                            Task {
                                await model.renameMedley(entry.itemId, to: title, in: setlist.id)
                            }
                        },
                    )
                } else {
                    Text(medley.title ?? "Medley")
                        .font(SchibstedGrotesk.semiBold.font(size: 16))
                        .foregroundStyle(medley.title == nil ? Theme.color.muted : Theme.color.ink)
                        .lineLimit(1)
                        .help(isReadOnly ? "" : "Double-click to rename")
                        .accessibilityIdentifier(AccessibilityID.medleyTitle)
                }
                if showsCount {
                    Text(songCountText)
                        .font(SchibstedGrotesk.medium.font(size: 13))
                        .foregroundStyle(Theme.color.muted)
                        .lineLimit(1)
                        .fixedSize()
                        .accessibilityIdentifier(AccessibilityID.medleySongCount)
                }
            }
        }

        private var disclosure: some View {
            Button {
                withAnimation(.easeOut(duration: 0.15)) {
                    model.setCollapsed(entry.itemId, !isCollapsed)
                }
            } label: {
                Image(systemName: isCollapsed ? "chevron.right" : "chevron.down")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Theme.color.muted)
                    .frame(width: 20, height: 20)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help(isCollapsed ? "Show the songs" : "Collapse to one row")
            .accessibilityLabel(isCollapsed ? "Expand \(displayTitle)" : "Collapse \(displayTitle)")
            .accessibilityIdentifier(AccessibilityID.medleyDisclosure)
        }

        @ViewBuilder private var headerMenu: some View {
            Button("Rename Medley") { model.renamingMedley = entry.itemId }
                .disabled(isReadOnly)
            Button("Ungroup Medley") {
                Task { await model.ungroup(entry.itemId, in: setlist.id) }
            }
            .disabled(isReadOnly)
            Button("Rehearse Medley") { rehearseMedley() }
                .disabled(!canRehearse)
            Button(isCollapsed ? "Expand Medley" : "Collapse Medley") {
                model.setCollapsed(entry.itemId, !isCollapsed)
            }
            Divider()
            Button("Remove from Setlist", role: .destructive) {
                guard let index = setlist.entries.firstIndex(of: entry) else { return }
                Task { await model.remove(in: setlist.id, atOffsets: IndexSet(integer: index)) }
            }
            .disabled(isReadOnly)
        }

        @ViewBuilder private var headerActions: some View {
            if !isReadOnly {
                Button("Ungroup") { Task { await model.ungroup(entry.itemId, in: setlist.id) } }
                Button("Rename") { model.renamingMedley = entry.itemId }
            }
            if canRehearse {
                Button("Rehearse Medley") { rehearseMedley() }
            }
            Button(isCollapsed ? "Expand" : "Collapse") {
                model.setCollapsed(entry.itemId, !isCollapsed)
            }
        }

        private var canRehearse: Bool {
            stage?.canRehearse == true && medley.members
                .contains { library.song(id: $0.songId) != nil }
        }

        /// Rehearse Medley (P9-3 12): the whole medley as arranged, unlogged; the builder
        /// reselects it when the rehearsal ends.
        private func rehearseMedley() {
            guard let stage else { return }
            let medleyId = entry.itemId
            model.services.record(.featureUsed(.medley, .builder))
            stage.rehearseSlot(entry) { [model] in
                model.builderMode = .arrange
                model.arrangeSelection.select(medleyId)
            }
        }
    }

    // MARK: - Members

    extension MedleyRow {
        private func memberRow(_ member: MedleyMember, index: Int) -> some View {
            let record = library.song(id: member.songId)
            let slot = member.asSlot
            return SetEntryRow(
                position: number,
                part: part,
                selection: { model.arrangeSelection.contains(member.itemId) },
                onSelect: { onSelect(member.itemId) },
                onInsertBreak: nil,
                entry: slot,
                record: record,
                timing: timing?.medley?.members.indices.contains(index) == true
                    ? timing?.medley?.members[index] : nil,
                isReadOnly: isReadOnly,
                onChange: { updated in
                    Task { await model.updateSongSlot(updated, in: setlist.id) }
                },
                onArrange: record == nil ? nil : {
                    model.openArrangement(member.itemId, in: setlist.id)
                },
                onRemove: { Task { await model.removeMember(member.itemId, in: setlist.id) } },
                member: MedleyMemberPlace(
                    label: Setlist.memberLabel(slot: number, index: index),
                    medleyTitle: displayTitle,
                    index: index,
                    count: medley.members.count,
                    moveEarlier: { move(member.itemId, by: -1) },
                    moveLater: { move(member.itemId, by: 1) },
                    removeFromMedley: {
                        Task { await model.removeFromMedley(member.itemId, in: setlist.id) }
                    },
                ),
                reprise: RepriseMark.forMember(member.songId, in: setlist),
            )
            .dropDestination(for: String.self) { items, _ in
                onDropMember(items, index)
            } isTargeted: { _ in }
        }

        private func move(_ member: SetlistItemID, by delta: Int) {
            Task {
                if await !model.moveMember(member, by: delta, in: setlist.id) {
                    NSSound.beep()
                }
            }
        }

        /// A medley of one (a hand-edited file, P9-3 5.3).
        private var lonelyHint: some View {
            Text(medley.members.isEmpty ? "Empty medley" : "Add a song or Ungroup")
                .font(SchibstedGrotesk.medium.font(size: 13))
                .foregroundStyle(Theme.color.muted)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.leading, 32 - MedleyMemberPlace.cardInset + 32 + 8)
                .padding(.vertical, 8)
        }
    }

    // MARK: - Text

    extension MedleyRow {
        private var displayTitle: String {
            medley.displayTitle
        }

        private var songCountText: String {
            medley.members.count == 1 ? "1 song" : "\(medley.members.count) songs"
        }

        private func title(of member: MedleyMember) -> String {
            library.song(id: member.songId).map(SongSummary.title) ?? "Missing song"
        }

        private func info(_ member: MedleyMember) -> MemberKeyInfo? {
            library.song(id: member.songId).map {
                MemberKeyInfo(record: $0, overrides: member.overrides)
            }
        }

        private func key(of member: MedleyMember) -> String? {
            info(member)?.key
        }

        /// "G → A → D": each member's displayed key ("-" when unknown).
        private var keyPath: String {
            medley.members.map { key(of: $0) ?? "-" }.joined(separator: " → ")
        }

        private func changes(into index: Int) -> [MedleyChange] {
            guard index > 0, let previous = info(medley.members[index - 1]),
                  let next = info(medley.members[index])
            else { return [] }
            return MedleyChanges.between(previous, next)
        }

        private func capoChanges(into index: Int) -> Bool {
            changes(into: index).contains(where: \.isCapo)
        }

        private var timeText: String {
            timing?.timeText ?? SetlistTiming.unknownText
        }

        private var timeHelp: String {
            timing?.medley?.time.help(titles: medley.members.map(title(of:))) ?? ""
        }

        private var accessibilityLabel: String {
            let time = timing?.medley?.time.spoken ?? "medley of \(medley.members.count) songs"
            return "\(number). \(displayTitle), \(time)"
        }
    }

    /// The context menu's "Make Medley from 3 Songs" (P9-3 6.1).
    struct MakeMedleyItem {
        var songs: Int
        var action: () -> Void

        var title: String {
            "Make Medley from \(songs) Songs"
        }
    }

    /// Where a member row sits in its medley, and its medley actions (P9-3 6.3, 6.5).
    struct MedleyMemberPlace {
        /// The member rows' title indent inside the card.
        static let indent: CGFloat = 24
        /// The card's inset from the list's edges.
        static let cardInset: CGFloat = 12

        var label: String
        var medleyTitle: String
        var index: Int
        var count: Int
        var moveEarlier: () -> Void
        var moveLater: () -> Void
        var removeFromMedley: () -> Void
    }

    /// A member's context menu items (and its VoiceOver actions): Move Earlier / Later in
    /// Medley and Remove from Medley.
    struct MedleyMemberMenuItems: View {
        let place: MedleyMemberPlace
        let isReadOnly: Bool
        var spoken = false

        var body: some View {
            if !spoken || place.index > 0 {
                Button("Move Earlier in Medley", action: place.moveEarlier)
                    .disabled(isReadOnly || place.index == 0)
            }
            if !spoken || place.index < place.count - 1 {
                Button("Move Later in Medley", action: place.moveLater)
                    .disabled(isReadOnly || place.index == place.count - 1)
            }
            Button("Remove from Medley", action: place.removeFromMedley)
                .disabled(isReadOnly)
        }
    }

    /// The quiet mark on the two occurrences of a reprised song (decision 8).
    struct RepriseMark: Equatable {
        /// "also 9", "reprise of 4a".
        var text: String
        /// "This song is also in the set at 9".
        var help: String

        var spoken: String {
            help.prefix(1).lowercased() + help.dropFirst()
        }

        /// A member whose song is also a plain slot.
        static func forMember(_ song: SongID, in setlist: Setlist) -> Self? {
            guard let slot = setlist.occurrences(of: song).first(where: { !$0.isMember })
            else { return nil }
            return Self(
                text: "also \(slot.label)",
                help: "This song is also in the set at "
                    + slot.label,
            )
        }

        /// A plain slot whose song is also a medley member.
        static func forSlot(_ song: SongID, in setlist: Setlist) -> Self? {
            guard let member = setlist.occurrences(of: song).first(where: \.isMember)
            else { return nil }
            return Self(
                text: "reprise of \(member.label)",
                help: "This song is also in the "
                    + "set at \(member.label)",
            )
        }
    }
#endif
