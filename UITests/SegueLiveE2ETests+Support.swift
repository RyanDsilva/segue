import XCTest

/// A fresh temp library for the live-mode E2E suite: songs with sidecars (fixed song IDs),
/// a 10-song setlist and the Shortcut log the fake runner writes. Lives under
/// `/private/tmp/segue-e2e/`, the only path the Debug sandbox exception allows.
struct LiveLibrary {
    let root: URL
    let setlistName = "Friday - The Anchor"
    /// The set, in order.
    let setTitles = [
        "Harbor Lights", "Paper Boats", "Salt Road", "Northern Line", "Long Way Home",
        "Copper Sky", "Lantern Song", "River Glass", "Night Bus", "Last Light",
    ]
    /// In the library but not in the set.
    let extraTitles = ["Pyaar Ki Raah", "Forty Lines"]

    init() throws {
        root = URL(filePath: "/private/tmp/segue-e2e", directoryHint: .isDirectory)
            .appending(path: "live-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(
            at: root.appending(path: "songs", directoryHint: .isDirectory),
            withIntermediateDirectories: true,
        )
        try FileManager.default.createDirectory(
            at: root.appending(path: "setlists", directoryHint: .isDirectory),
            withIntermediateDirectories: true,
        )
        for (index, title) in (setTitles + extraTitles).enumerated() {
            try writeSong(index: index, title: title)
        }
        try write(setlistJSON(), to: "setlists/friday-the-anchor.setlist.json")
    }

    func remove() {
        try? FileManager.default.removeItem(at: root)
    }

    var path: String {
        root.path(percentEncoded: false)
    }

    var shortcutLog: URL {
        root.appending(path: "shortcuts.log", directoryHint: .notDirectory)
    }

    var setlistFile: URL {
        root.appending(path: "setlists/friday-the-anchor.setlist.json")
    }

    /// The launch arguments of a test run on this library.
    func arguments(reset: Bool = true, extra: [String] = []) -> [String] {
        [
            "-SegueLibraryPath", path,
            "-SegueResetState", reset ? "YES" : "NO",
            "-SegueShortcutLog", shortcutLog.path(percentEncoded: false),
        ] + extra
    }

    /// The Shortcuts the fake runner was asked to run, in order.
    func shortcutsRun() -> [String] {
        guard let text = try? String(contentsOf: shortcutLog, encoding: .utf8) else { return [] }
        return text.split(separator: "\n").map(String.init)
    }

    /// Every show file's decoded JSON.
    func shows() throws -> [[String: Any]] {
        let folder = root.appending(path: "shows", directoryHint: .isDirectory)
        let names = (try? FileManager.default.contentsOfDirectory(atPath: folder.path)) ?? []
        return try names.filter { $0.hasSuffix(".show.json") }.sorted().map { name in
            let data = try Data(contentsOf: folder.appending(path: name))
            return try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        }
    }

    /// Item titles of a show by state ("played", "skipped", "pending").
    static func items(_ show: [String: Any], state: String) -> [String] {
        let items = show["items"] as? [[String: Any]] ?? []
        return items.filter { $0["state"] as? String == state }
            .compactMap { $0["title"] as? String }
    }

    /// Titles of the setlist file's entries, in order.
    func setlistTitles() throws -> [String] {
        let data = try Data(contentsOf: setlistFile)
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let entries = object["entries"] as? [[String: Any]] ?? []
        let all = setTitles + extraTitles
        return entries.compactMap { entry in
            guard let id = entry["songId"] as? String,
                  let index = (0 ..< all.count).first(where: { Self.songID($0) == id })
            else { return nil }
            return all[index]
        }
    }

    // MARK: Fixtures

    /// Deterministic Crockford ULIDs: "01K70000000000000000" + kind + 5 digits.
    static func ulid(_ kind: Character, _ number: Int) -> String {
        "01K70000000000000000\(kind)" + String(format: "%05d", number)
    }

    static func songID(_ index: Int) -> String {
        ulid("S", index)
    }

    private func writeSong(index: Int, title: String) throws {
        let slug = title.lowercased().replacingOccurrences(of: " ", with: "-")
        try write(Self.source(index: index, title: title), to: "songs/\(slug).cho")
        let sidecar = """
        {"schemaVersion": 1, "id": "\(Self.songID(index))", "tags": ["e2e"],
         "proficiency": "\(index.isMultiple(of: 3) ? "pro" : "ready")",
         "createdAt": "2026-10-01T10:00:00.000Z", "updatedAt": "2026-10-01T10:00:00.000Z"}
        """
        try write(sidecar, to: "songs/\(slug).segue.json")
    }

    /// Song 5 ("Long Way Home") and "Forty Lines" are long enough to scroll; the others
    /// fit. "Pyaar Ki Raah" is the romanized Hindi fixture.
    static func source(index: Int, title: String) -> String {
        title == "Pyaar Ki Raah" ? pyaar : generated(index: index, title: title)
    }

    static let pyaar = """
    {title: Pyaar Ki Raah}
    {artist: Fixture Sangeet}
    {key: Am}
    {tempo: 84}

    {start_of_verse: Verse 1}
    [Am]Chalte chalte [G]is raah pe, [F]tera saath mila [E]hai
    [Am]Kabhi dhoop kabhi [G]chhaon mein, [F]dil ne kuch kaha [E]hai
    {end_of_verse}

    {start_of_chorus}
    [F]Pyaar ki [G]raah mein, [Am]hum tum saath hain
    [F]Sapnon ki [G]baahon mein, [E]dil ke jazbaat hain
    {end_of_chorus}

    {chorus}

    """

    private static func generated(index: Int, title: String) -> String {
        let keys = ["G", "D", "A", "E", "C", "F", "Bb", "Em", "Am", "Dm"]
        let key = keys[index % keys.count]
        let verses = switch title {
        case "Long Way Home": 40
        case "Forty Lines": 10
        default: 2
        }
        var text = "{title: \(title)}\n{artist: The Fixtures}\n{key: \(key)}\n"
        text += "{tempo: \(84 + index * 4)}\n"
        if title == "Long Way Home" {
            text += "{duration: 3:00}\n"
        }
        if index == 1 {
            text += "{capo: 2}\n"
        }
        text += "\n"
        for verse in 0 ..< verses {
            text += "{start_of_verse: Verse \(verse + 1)}\n"
            text += "[\(key)]Lanterns on the [D]water, line \(verse * 4 + 1), [Em]boats [C]in\n"
            text += "[\(key)]Salt upon my [D]collar, line \(verse * 4 + 2), [C]tide turns [D]thin\n"
            text += "[\(key)]Every road I [D]wandered, line \(verse * 4 + 3) [C]led me back\n"
            text += "[\(key)]Home before the [D]morning, line \(verse * 4 + 4) [C]comes\n"
            text += "{end_of_verse}\n\n"
            if verse == 0 {
                text += "{start_of_chorus}\n[C]Hold on, [G]\(title.lowercased())\n"
                text += "[D]Keep me [Em]steady through the night\n{end_of_chorus}\n\n"
            }
        }
        if verses == 2 {
            text += "{chorus}\n"
        }
        return text
    }

    private func setlistJSON() -> String {
        let entries = setTitles.indices.map { index in
            #"{"itemId": "\#(Self.ulid("T", index))", "songId": "\#(Self.songID(index))"}"#
        }
        return """
        {"schemaVersion": 2, "id": "\(Self.ulid("P", 1))", "name": "\(setlistName)",
         "entries": [\(entries.joined(separator: ",\n  "))],
         "createdAt": "2026-10-01T10:00:00.000Z", "updatedAt": "2026-10-01T10:00:00.000Z",
         "venue": "The Anchor", "date": "2026-10-23"}
        """
    }

    private func write(_ text: String, to relativePath: String) throws {
        try Data(text.utf8).write(to: root.appending(path: relativePath))
    }
}

/// Accessibility identifiers used by the live E2E suite (mirrors `AccessibilityID` in
/// SegueUI, which the test target cannot import).
enum LiveAXID {
    static let sidebarSetlists = "segue.sidebar.setlists"
    static let sidebarGigLog = "segue.sidebar.gigLog"
    static let sidebarLibrary = "segue.sidebar.library"
    static let setlistRow = "segue.setlists.row"
    static let setlistStartShow = "segue.setlist.startShow"
    static let setlistRehearse = "segue.setlist.rehearse"
    static let gigLogRow = "segue.gigLog.row"
    static let gigPlayedRow = "segue.gig.played"
    static let gigSkippedRow = "segue.gig.skipped"
    static let reorderSheet = "segue.reorder"
    static let reorderSave = "segue.reorder.save"
    static let reorderDiscard = "segue.reorder.discard"
    static let songRow = "segue.library.row"
    static let songPlayStats = "segue.song.playStats"

    static let liveView = "segue.live"
    static let liveTitle = "segue.live.title"
    static let liveMeta = "segue.live.meta"
    static let livePosition = "segue.live.position"
    static let liveUpNext = "segue.live.upNext"
    static let liveUpNextLabel = "segue.live.upNextLabel"
    static let liveBody = "segue.live.body"
    static let liveRehearsal = "segue.live.rehearsal"
    static let liveScrollStatus = "segue.live.scrollStatus"
    static let liveRequestCount = "segue.live.requestCount"
    static let liveIndicator = "segue.live.indicator"
    static let liveEndDialog = "segue.live.endDialog"
    static let liveSearch = "segue.live.search"
    static let liveSearchField = "segue.live.search.field"
    static let liveSearchResult = "segue.live.search.result"
    static let liveSearchNote = "segue.live.search.note"
    static let liveDrawer = "segue.live.drawer"
    static let liveDrawerRow = "segue.live.drawer.row"
    static let liveDrawerPlayNext = "segue.live.drawer.playNext"
    static let liveRequests = "segue.live.requests"
    static let liveRequestRow = "segue.live.requests.row"

    static let checklist = "segue.live.checklist"
    static let checklistStart = "segue.live.checklist.start"
    static let checklistRow = "segue.live.checklist.row"
    static let checklistMissing = "segue.live.checklist.missing"
    static let resumeShowResume = "segue.live.resume.resume"
    static let settingsMinLyricSize = "segue.settings.live.minLyricSize"
}
