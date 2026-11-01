import AppKit
import Foundation
import Library
@testable import SegueUI
import Setlists
import Shows
import Support
import SwiftUI
import Testing

/// The Gig Log's nested medley rows (P9-3 8.3): members under their medley numbered "4a",
/// "4b" in medley order, a skipped member shown under it and named with its medley in the
/// Skipped list; rendered light and dark to `.build/screenshots/p9-3/`.
@MainActor
struct GigMedleyRowsTests {
    private static func ulid(_ index: UInt8) -> ULID {
        ULID(milliseconds: 9, randomness: Array(repeating: index, count: 10))
    }

    private static let medleySlot = SetlistItemID(ulid(40))

    private static func item(
        _ index: UInt8,
        _ title: String,
        medley: Int? = nil,
        state: ItemState = .played,
    ) -> ShowItem {
        ShowItem(
            itemId: ShowItemID(ulid(index)),
            songId: SongID(ulid(index + 100)),
            title: title,
            origin: .setlist,
            state: state,
            medley: medley.map {
                ShowMedleyRef(
                    slot: medleySlot,
                    title: "Love medley",
                    index: $0,
                    count: 3,
                    transition: $0 == 0 ? nil : "Hold the D",
                )
            },
        )
    }

    private static func played(_ item: ShowItem, minute: Int) -> PlayedSong {
        let start = Date(timeIntervalSince1970: 1_792_224_000 + Double(minute * 60))
        return PlayedSong(item: item, startedAt: start, endedAt: start + 150, fromRequest: false)
    }

    /// Harbour Lights, then the medley (Kesariya played, Tum Hi Ho skipped, Channa Mereya
    /// played with an arrangement), then the Kesariya reprise.
    private static var entry: GigLogEntry {
        var channa = item(3, "Channa Mereya", medley: 2)
        let anchor = SectionAnchor.section(SectionRef(label: "Chorus", occurrence: 1))
        channa.arrangement = SlotArrangement(passes: [ArrangementPass(anchor: anchor)])
        let skipped = item(2, "Tum Hi Ho", medley: 1, state: .skipped)
        return GigLogEntry(
            id: ShowID(ulid(1)),
            setlistId: SetlistID(ulid(2)),
            setlistName: "Friday",
            details: GigDetails(venue: "The Anchor"),
            startedAt: Date(timeIntervalSince1970: 1_792_224_000),
            endedAt: Date(timeIntervalSince1970: 1_792_226_000),
            played: [
                played(item(4, "Harbour Lights"), minute: 0),
                played(item(1, "Kesariya", medley: 0), minute: 4),
                played(channa, minute: 7),
                played(item(5, "Kesariya"), minute: 11),
            ],
            skipped: [skipped],
            closure: .ended,
        )
    }

    @Test
    func `members nest under their medley in medley order, skipped ones included`() {
        let slots = Self.entry.slots
        #expect(slots.count == 3)
        guard case let .medley(_, title, members, skipped) = slots[1] else {
            Issue.record("expected the medley second")
            return
        }
        #expect(GigMedleyText.title(title) == "Love medley")
        let rows = GigMedleyText.rows(members: members, skipped: skipped)
        #expect(rows.map(\.index) == [0, 1, 2])
        #expect(rows.map { GigMedleyText.label(2, $0.index) } == ["2a", "2b", "2c"])
        #expect(GigMedleyText.skippedTitle(skipped[0]) == "Tum Hi Ho (in Love medley)")
        #expect(GigMedleyText.title(nil) == "Medley")
    }

    @Test
    func `the played list renders nested medley rows`() throws {
        for dark in [false, true] {
            let view = GigPlayedList(entry: Self.entry)
                .padding(24)
                .frame(width: 640, height: 560, alignment: .top)
                .background(Theme.color.ground)
            try SetComposerMedleyTests.render(
                view,
                size: CGSize(width: 640, height: 560),
                dark: dark,
                name: "gig-log-\(dark ? "dark" : "light")",
            )
        }
    }
}
