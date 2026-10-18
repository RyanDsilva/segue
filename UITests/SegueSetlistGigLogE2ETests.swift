import XCTest

/// Phase 2 gig log + show-end reorder review E2E (unit D). Shows are seeded as files: one
/// finished gig, and one unfinished gig untouched for over 12 hours, which the launch check
/// auto-closes into the gig log and offers for review (Save / Discard). Its inserted request
/// is ticked by default (decisions.md, phase 2 build rulings); Save writes the played order.
final class SegueSetlistGigLogE2ETests: SetlistE2ETestCase {
    private let finishedShow = "01JC0000000000000000000H01"
    private let staleShow = "01JC0000000000000000000H02"
    private let fridaySetlist = "01JC0000000000000000000T01"
    private let staleSetlist = "01JC0000000000000000000T02"

    @MainActor
    func testGigLogAndReorderReview() throws {
        let root = try XCTUnwrap(libraryRoot)
        try seed(root)
        let app = try launch()

        try reviewReorder(app, root)
        try gigLogDetail(app, root)
        try playStatsAndDelete(app, root)
    }

    // MARK: - Steps

    @MainActor
    private func reviewReorder(_ app: XCUIApplication, _ root: URL) throws {
        let sheet = SetlistE2E.element(app, SetlistAXID.reorderSheet)
        XCTAssertTrue(sheet.appears(timeout: 15), "No reorder review at launch")
        XCTAssertEqual(
            SetlistE2E.texts(app, SetlistAXID.reorderPlannedRow).count, 3,
        )
        let performed = SetlistE2E.texts(app, SetlistAXID.reorderPerformedRow)
        XCTAssertEqual(performed.count, 4, "\(performed)")
        let include = SetlistE2E.element(app, SetlistAXID.reorderInclude)
        XCTAssertTrue(include.exists)
        XCTAssertEqual(include.value as? Int, 1, "Inserted songs must be ticked by default")
        screenshot(app, "reorder-review")
        SetlistE2E.element(app, SetlistAXID.reorderSave).click(in: app)
        XCTAssertTrue(sheet.disappears(timeout: 10))

        // Saved: performed order, the request included as a new entry.
        let song = { (title: String) in SetlistFixture.song(title).id }
        SetlistE2E.waitForDisk("The played order was never saved to the setlist") {
            let file = try XCTUnwrap(SetlistFixture.setlistFiles(root)
                .first { $0["id"] as? String == self.staleSetlist })
            let entries = try XCTUnwrap(file["entries"] as? [[String: Any]])
            return entries.compactMap { $0["songId"] as? String } == [
                song("Paper Boats"), song("Harbor Lights"), song("Kitchen Radio"),
                song("Lamplighter"),
            ]
        }
    }

    @MainActor
    private func gigLogDetail(_ app: XCUIApplication, _ root: URL) throws {
        SetlistE2E.element(app, SetlistAXID.sidebarGigLog).click(in: app)
        let rows = SetlistE2E.all(app, SetlistAXID.gigLogRow)
        SetlistE2E.waitUntil("Expected 2 gigs, got \(rows.count)") { rows.count == 2 }
        // Newest first: the auto-closed show started later than the finished one.
        XCTAssertTrue(SetlistE2E.text(rows.element(boundBy: 0)).contains("Late Set"))
        rows.element(boundBy: 1).click(in: app)

        let title = app.staticTexts[SetlistAXID.gigTitle]
        SetlistE2E.waitUntil("The finished gig never showed") {
            title.exists && SetlistE2E.text(title) == "Dockside"
        }
        let played = SetlistE2E.texts(app, SetlistAXID.gigPlayedRow)
        XCTAssertEqual(
            played.map { $0.components(separatedBy: CharacterSet(charactersIn: " ,"))[0] },
            ["1", "2", "3", "4"],
        )
        XCTAssertTrue(played[1].contains("Dil Ki Raah") && played[1].contains("Request"))
        XCTAssertEqual(SetlistE2E.all(app, SetlistAXID.gigSkippedRow).count, 2)
        XCTAssertTrue(SetlistE2E.text(SetlistE2E.element(app, SetlistAXID.gigSummary))
            .contains("4 played, 2 skipped, 1 request"))
        screenshot(app, "gig-log-detail")

        // Edit rating and notes; they save on their own.
        SetlistE2E.element(app, SetlistAXID.gigRating(4)).click(in: app)
        let notes = app.textViews[SetlistAXID.gigNotes]
        notes.click(in: app)
        notes.typeText("Great crowd, encore of Northbound", in: app)
        let showURL = root.appending(path: "shows/\(finishedShow).show.json")
        SetlistE2E.waitForDisk("Rating and notes never reached the show file") {
            let gig = try SetlistFixture.json(showURL)["gig"] as? [String: Any]
            return gig?["rating"] as? Int == 4
                && gig?["notes"] as? String == "Great crowd, encore of Northbound"
                && gig?["venue"] as? String == "Dockside"
        }
        screenshot(app, "gig-log-edited")
    }

    /// "Played 2 times" from the projection; deleting the finished gig drops its play.
    @MainActor
    private func playStatsAndDelete(_ app: XCUIApplication, _ root: URL) throws {
        let stats = SetlistE2E.element(app, SetlistAXID.songPlayStats)
        showHarbor(app)
        SetlistE2E.waitUntil("Play stats never showed 2 plays: \(SetlistE2E.text(stats))") {
            SetlistE2E.text(stats).hasPrefix("Played 2 times")
        }

        SetlistE2E.element(app, SetlistAXID.sidebarGigLog).click(in: app)
        let rows = SetlistE2E.all(app, SetlistAXID.gigLogRow)
        SetlistE2E.waitUntil("Gig log never came back") { rows.count == 2 }
        rows.element(boundBy: 1).click(in: app)
        // Show in Finder reveals the gig's show file (A28).
        SetlistE2E.element(app, SetlistAXID.gigMoreMenu).click(in: app)
        SetlistE2E.element(app, SetlistAXID.gigReveal).click(in: app)
        let showFile = "shows/\(finishedShow).show.json"
        SetlistE2E.waitForDisk("Show in Finder never revealed the show file") {
            let log = try String(contentsOf: Self.workspaceLog(root), encoding: .utf8)
            return log.contains(#""action":"reveal""#) && log.contains(showFile)
        }
        // Move to Trash from the gig's "…" menu: no confirmation (A23).
        SetlistE2E.element(app, SetlistAXID.gigMoreMenu).click(in: app)
        SetlistE2E.element(app, SetlistAXID.gigDelete).click(in: app)
        XCTAssertFalse(app.sheets.firstMatch.appears(timeout: 1), "No dialog expected")
        SetlistE2E.waitUntil("The gig was never deleted") { rows.count == 1 }
        let showURL = root.appending(path: "shows/\(finishedShow).show.json")
        XCTAssertFalse(FileManager.default.fileExists(atPath: showURL.path))
        XCTAssertEqual(Self.trashed(root), ["\(finishedShow).show.json"])

        showHarbor(app)
        SetlistE2E.waitUntil("Play stats never dropped to 1: \(SetlistE2E.text(stats))") {
            SetlistE2E.text(stats).hasPrefix("Played once")
        }

        // Edit > Undo puts the gig back with its plays.
        app.typeKey("z", modifierFlags: .command, in: app)
        SetlistE2E.waitUntil("Undo never restored the play count: \(SetlistE2E.text(stats))") {
            SetlistE2E.text(stats).hasPrefix("Played 2 times")
        }
        XCTAssertTrue(FileManager.default.fileExists(atPath: showURL.path))
        XCTAssertTrue(Self.trashed(root).isEmpty)
    }

    @MainActor
    private func showHarbor(_ app: XCUIApplication) {
        SetlistE2E.element(app, SetlistAXID.sidebarLibrary).click(in: app)
        let harbor = SetlistE2E.row(app, SetlistAXID.songRow, "Harbor Lights")
        XCTAssertTrue(harbor.appears(timeout: 5))
        harbor.click(in: app)
    }

    // MARK: - Seeding

    private func song(_ title: String) -> String {
        SetlistFixture.song(title).id
    }

    private func seed(_ root: URL) throws {
        try SetlistFixture.write(
            setlist(fridaySetlist, "Friday Set", [
                ("I01", "Harbor Lights"), ("I02", "Paper Boats"), ("I03", "Kitchen Radio"),
                ("I04", "Northbound"), ("I05", "Morning Ferry"),
            ]),
            to: root.appending(path: "setlists/friday-set.setlist.json"),
        )
        try SetlistFixture.write(
            setlist(staleSetlist, "Late Set", [
                ("J01", "Harbor Lights"), ("J02", "Paper Boats"), ("J03", "Kitchen Radio"),
            ]),
            to: root.appending(path: "setlists/late-set.setlist.json"),
        )
        try SetlistFixture.write(
            finishedShowJSON(),
            to: root.appending(path: "shows/\(finishedShow).show.json"),
        )
        try SetlistFixture.write(
            staleShowJSON(),
            to: root.appending(path: "shows/\(staleShow).show.json"),
        )
    }

    /// Harbor, request Dil Ki Raah, Paper, Northbound played; two skipped.
    private func finishedShowJSON() throws -> String {
        var show = ShowSeed(id: finishedShow, setlist: fridaySetlist, name: "Friday Set")
        show.items = [
            item("I01", "Harbor Lights", "setlist", "played"),
            item("R01", "Dil Ki Raah", "request", "played", request: "01JC0000000000000000000Q01"),
            item("I02", "Paper Boats", "setlist", "played"),
            item("I03", "Kitchen Radio", "setlist", "skipped"),
            item("I04", "Northbound", "setlist", "played"),
            item("I05", "Morning Ferry", "setlist", "skipped"),
        ]
        show.planned = ["I01", "I02", "I03", "I04", "I05"]
        show.events = [
            event("2026-10-16T20:00:00Z", "started", item: "I01"),
            event("2026-10-16T20:04:00Z", "advanced", item: "R01", from: "I01"),
            event("2026-10-16T20:08:00Z", "advanced", item: "I02", from: "R01"),
            event("2026-10-16T20:11:00Z", "skipped", item: "I03"),
            event("2026-10-16T20:11:10Z", "advanced", item: "I04", from: "I02"),
            event("2026-10-16T20:14:00Z", "skipped", item: "I05"),
            event("2026-10-16T20:14:30Z", "ended", from: "I04"),
        ]
        show.requests = [[
            "requestId": "01JC0000000000000000000Q01", "songId": song("Dil Ki Raah"),
            "title": "Dil Ki Raah", "addedAt": "2026-10-16T20:03:00Z", "note": "table 4",
            "state": "played",
        ]]
        show.started = "2026-10-16T20:00:00Z"
        show.updated = "2026-10-16T20:14:30Z"
        show.ended = "2026-10-16T20:14:30Z"
        show.gig = ["venue": "Dockside", "date": "2026-10-16"]
        return try show.json(itemID: itemID)
    }

    /// Untouched for over 12 hours: Paper moved first, Lamplighter inserted and current.
    private func staleShowJSON() throws -> String {
        let started = Date.now.addingTimeInterval(-13 * 3600)
        let stamp = { (offset: TimeInterval) in
            ISO8601DateFormatter().string(from: started.addingTimeInterval(offset))
        }
        var show = ShowSeed(id: staleShow, setlist: staleSetlist, name: "Late Set")
        show.items = [
            item("J02", "Paper Boats", "setlist", "played"),
            item("J01", "Harbor Lights", "setlist", "played"),
            item("J03", "Kitchen Radio", "setlist", "played"),
            item("X01", "Lamplighter", "inserted", "current"),
        ]
        show.planned = ["J01", "J02", "J03"]
        show.events = [
            event(stamp(0), "started", item: "J02"),
            event(stamp(200), "advanced", item: "J01", from: "J02"),
            event(stamp(400), "advanced", item: "J03", from: "J01"),
            event(stamp(500), "inserted", item: "X01"),
            event(stamp(600), "advanced", item: "X01", from: "J03"),
        ]
        show.started = stamp(0)
        show.updated = stamp(600)
        show.current = "X01"
        show.gig = ["venue": "The Anchor"]
        return try show.json(itemID: itemID)
    }

    /// "I01" -> a valid ULID (Crockford base 32 has no I, L, O, U, so letters are mapped).
    private func itemID(_ suffix: String) -> String {
        let letters: [Character: String] = ["I": "A", "R": "B", "J": "C", "X": "D"]
        let letter = suffix.first.flatMap { letters[$0] } ?? "Z"
        return "01JC000000000000000000T" + letter + suffix.dropFirst()
    }

    private func setlist(_ id: String, _ name: String, _ entries: [(String, String)]) -> String {
        let list = entries.map { item, title in
            #"{"itemId": "\#(itemID(item))", "songId": "\#(song(title))"}"#
        }
        return """
        {"schemaVersion": 2, "id": "\(id)", "name": "\(name)",
         "createdAt": "2026-10-10T10:00:00Z", "updatedAt": "2026-10-10T10:00:00Z",
         "entries": [\(list.joined(separator: ", "))]}
        """
    }

    private func item(
        _ id: String,
        _ title: String,
        _ origin: String,
        _ state: String,
        request: String? = nil,
    ) -> [String: Any] {
        var item: [String: Any] = [
            "itemId": itemID(id), "songId": song(title), "title": title, "origin": origin,
            "state": state, "overrides": [String: Any](),
        ]
        item["requestId"] = request
        return item
    }

    private func event(
        _ at: String,
        _ kind: String,
        item: String? = nil,
        from: String? = nil,
    ) -> [String: Any] {
        var event: [String: Any] = ["at": at, "kind": kind]
        event["itemId"] = item.map(itemID)
        event["fromItemId"] = from.map(itemID)
        return event
    }
}

/// A `shows/<id>.show.json` file written by hand (schema 1), for seeding.
private struct ShowSeed {
    let id: String
    let setlist: String
    let name: String
    var planned: [String] = []
    var items: [[String: Any]] = []
    var events: [[String: Any]] = []
    var requests: [[String: Any]] = []
    var started = ""
    var updated = ""
    var ended: String?
    var current: String?
    var gig: [String: Any] = [:]

    func json(itemID: (String) -> String) throws -> String {
        let plannedEntries: [[String: Any]] = planned.compactMap { suffix in
            items.first { $0["itemId"] as? String == itemID(suffix) }.map {
                ["itemId": itemID(suffix), "songId": $0["songId"] ?? ""]
            }
        }
        var object: [String: Any] = [
            "schemaVersion": 1, "id": id, "kind": "gig", "setlistId": setlist,
            "setlistName": name, "planned": plannedEntries, "items": items,
            "scrollPosition": 0, "requests": requests, "events": events,
            "startedAt": started, "updatedAt": updated, "gig": gig,
        ]
        object["endedAt"] = ended
        object["closure"] = ended == nil ? nil : "ended"
        object["currentItemId"] = current.map(itemID)
        let data = try JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted])
        return try XCTUnwrap(String(bytes: data, encoding: .utf8))
    }
}
