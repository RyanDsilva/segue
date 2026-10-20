import Foundation
import Library
import Support
import Testing

/// Tag rename and merge across a real library folder (P3-6): sidecars rewritten, the index
/// following (tag search), one-action undo, read-only songs left alone, smart filters
/// following the rename, and the starter suggestions rule (R71).
struct TagManagementTests {
    private struct Fixture {
        let lib: TestLibrary
        let store: LibraryStore
        let ids: [String: SongID]

        func tags(_ title: String) async throws -> [String] {
            let id = try #require(ids[title])
            return try #require(try await store.song(id: id)).sidecar.tags
        }
    }

    private static func fixture() async throws -> Fixture {
        let lib = try TestLibrary()
        let store = try await lib.openStore()
        let specs: [(String, [String])] = [
            ("One", ["Upbeat", "cover"]),
            ("Two", ["up-beat", "Ballad"]),
            ("Three", ["cover", "upbeat", "UP-BEAT"]),
            ("Four", ["original"]),
        ]
        var ids: [String: SongID] = [:]
        for (title, tags) in specs {
            let song = try await store.createSong(source: "{title: \(title)}\nLa\n")
            try await store.updateMetadata(id: song.id, SongMetadata(tags: tags))
            ids[title] = song.id
        }
        return Fixture(lib: lib, store: store, ids: ids)
    }

    @Test
    func `rename rewrites every sidecar and the index`() async throws {
        let fix = try await Self.fixture()
        let fourBefore = try fix.lib.read("songs/four.segue.json")
        fix.lib.clock.advance(by: 60)

        let rewrite = try await fix.store.renameTag("upbeat", to: "  High  energy ")

        #expect(rewrite.count == 2)
        #expect(try await fix.tags("One") == ["High energy", "cover"])
        #expect(try await fix.tags("Three") == ["cover", "High energy", "UP-BEAT"])
        #expect(try await fix.tags("Two") == ["up-beat", "Ballad"])
        #expect(try fix.lib.read("songs/four.segue.json") == fourBefore)
        #expect(try fix.lib.read("songs/one.segue.json").contains("\"High energy\""))
        // The index follows: tag search finds the new name, not the old one.
        #expect(try await Set(fix.store.search(query: "high energy").titles) == ["One", "Three"])
        #expect(try await fix.store.allTags().map(\.tag).contains("High energy"))
        #expect(try await !fix.store.allTags().map { $0.tag.lowercased() }.contains("upbeat"))
        // A relaunch reads the same.
        let reopened = try await fix.lib.openStore()
        #expect(try await reopened.song(id: #require(fix.ids["One"]))?.sidecar.tags
            == ["High energy", "cover"])
    }

    @Test
    func `merge folds several tags into one without duplicates`() async throws {
        let fix = try await Self.fixture()
        let rewrite = try await fix.store.mergeTags(["up-beat", "UPBEAT"], into: "upbeat")

        #expect(Set(rewrite.previous.keys) == Set([fix.ids["One"], fix.ids["Two"], fix.ids["Three"]]
                .compactMap(\.self)))
        #expect(try await fix.tags("One") == ["upbeat", "cover"])
        #expect(try await fix.tags("Two") == ["upbeat", "Ballad"])
        #expect(try await fix.tags("Three") == ["cover", "upbeat"])
        let counts = try await fix.store.allTags()
        #expect(counts.first == TagCount(tag: "upbeat", count: 3))
    }

    @Test
    func `undo puts every song back in one action and redo applies it again`() async throws {
        let fix = try await Self.fixture()
        let before = try await fix.store.allSongs().map(\.sidecar.tags)
        let rewrite = try await fix.store.mergeTags(["up-beat"], into: "upbeat")

        let redo = try await fix.store.restoreTags(rewrite)
        #expect(try await fix.store.allSongs().map(\.sidecar.tags) == before)
        #expect(try await fix.store.allTags().map { $0.tag.lowercased() }.contains("up-beat"))

        try await fix.store.restoreTags(redo)
        #expect(try await fix.tags("Two") == ["upbeat", "Ballad"])
    }

    @Test
    func `read-only songs are skipped and reported`() async throws {
        let fix = try await Self.fixture()
        let future = SongID(fix.lib.ids.next())
        let sidecar = "{\"schemaVersion\": 99, \"id\": \"\(future)\", \"tags\": [\"upbeat\"]}"
        try fix.lib.write("{title: Future}\nLa\n", to: "songs/future.cho")
        try fix.lib.write(sidecar, to: "songs/future.segue.json")
        try await fix.store.refresh()

        let rewrite = try await fix.store.renameTag("upbeat", to: "lively")

        #expect(rewrite.skipped == [future])
        #expect(rewrite.count == 2)
        #expect(try fix.lib.read("songs/future.segue.json") == sidecar)
    }

    @Test
    func `delete removes a tag everywhere and undoes in one step`() async throws {
        let fix = try await Self.fixture()
        let before = try await fix.store.allSongs().map(\.sidecar.tags)
        let rewrite = try await fix.store.deleteTag("COVER")
        #expect(rewrite.count == 2)
        #expect(try await fix.tags("One") == ["Upbeat"])
        #expect(try await fix.tags("Three") == ["upbeat", "UP-BEAT"])
        #expect(try await !fix.store.allTags().map(\.tag).contains("cover"))
        try await fix.store.restoreTags(rewrite)
        #expect(try await fix.store.allSongs().map(\.sidecar.tags) == before)
    }

    @Test
    func `blank names and unknown tags change nothing`() async throws {
        let fix = try await Self.fixture()
        #expect(try await fix.store.renameTag("upbeat", to: "   ") == TagRewrite())
        #expect(try await fix.store.renameTag("nope", to: "yes") == TagRewrite())
        #expect(try await fix.store.mergeTags([], into: "yes") == TagRewrite())
        #expect(try await fix.tags("One") == ["Upbeat", "cover"])
    }

    @Test
    func `smart filters follow a rename and undo through replace`() async throws {
        let fix = try await Self.fixture()
        let filters = SmartFilterStore(
            fileSystem: fix.lib.fileSystem,
            clock: fix.lib.clock,
            ids: fix.lib.ids,
        )
        try await filters.load(root: fix.lib.root)
        let saved = try await filters.create(name: "Lively", conditions: SmartFilterConditions(
            allTags: ["UPBEAT"],
            anyTags: ["cover", "up-beat"],
            noneTags: ["ballad"],
        ))
        let untouched = try await filters.create(name: "Plain", conditions: SmartFilterConditions(
            allTags: ["original"],
        ))

        let previous = try await filters.rewriteTags(["upbeat", "up-beat"], to: "lively")

        #expect(previous == [saved])
        let rewritten = try #require(await filters.filter(id: saved.id))
        #expect(rewritten.conditions.allTags == ["lively"])
        #expect(rewritten.conditions.anyTags == ["cover", "lively"])
        #expect(rewritten.conditions.noneTags == ["ballad"])
        #expect(await filters.filter(id: untouched.id) == untouched)
        try await filters.replace(saved)
        #expect(await filters.filter(id: saved.id)?.conditions == saved.conditions)
    }

    @Test(arguments: [
        ([String](), [String](), StarterTags.all),
        (["Welcome"], ["Welcome"], StarterTags.all),
        (["welcome "], ["Welcome"], StarterTags.all),
        (["Welcome", "gig"], ["Welcome"], []),
        (["cover"], ["Welcome"], []),
    ])
    func `starter tags show only while the user has no tags of their own`(
        library: [String],
        seeds: [String],
        expected: [String],
    ) {
        #expect(StarterTags.suggestions(libraryTags: library, seedTags: seeds) == expected)
    }

    @Test
    func `starter tags are the six from the spec and none is energy`() {
        #expect(StarterTags.all == [
            "upbeat",
            "ballad",
            "crowd pleaser",
            "singalong",
            "original",
            "cover",
        ])
    }
}
