import Foundation
import ModelPort
import Plugins
@testable import SeguePersonalModules
import Testing

/// R194: one " - " is split by code; with more, the model picks among the code's own splits,
/// and without a usable answer the last " - " split stays, flagged.
struct FilmTitleTests {
    static let name = "Brahmāstra Part One - Shiva - Kesariya"

    @Test
    func `one dash under a placeholder artist splits by code`() {
        let fields = SourceCredits.fields(
            songName: "Aashiqui 2 - Tum Hi Ho",
            artist: "Misc Soundtrack",
        )
        #expect(fields.title == "Tum Hi Ho")
        #expect(fields.album == "Aashiqui 2")
        #expect(!fields.titleUncertain)
        #expect(fields.titleSplits.isEmpty)
    }

    @Test
    func `several dashes fall back to the last one, flagged, with every split`() {
        let fields = SourceCredits.fields(songName: Self.name, artist: "Misc Soundtrack")
        #expect(fields.title == "Kesariya")
        #expect(fields.album == "Brahmāstra Part One - Shiva")
        #expect(fields.titleUncertain)
        #expect(fields.titleSplits == [
            TitleSplit(title: "Shiva - Kesariya", album: "Brahmāstra Part One"),
            TitleSplit(title: "Kesariya", album: "Brahmāstra Part One - Shiva"),
        ])
    }

    @Test
    func `a real artist keeps the name as the title`() {
        let fields = SourceCredits.fields(songName: "Tum Hi Ho - Rehnuma", artist: "Shreya Ghoshal")
        #expect(fields.title == "Tum Hi Ho - Rehnuma")
        #expect(fields.album == nil && !fields.titleUncertain)
    }

    @Test(arguments: [
        ("shiva - KESARIYA", "Shiva - Kesariya"),
        ("Kesariya", "Kesariya"),
        ("Kesariya (Reprise)", nil),
        ("", nil)
    ] as [(String, String?)])
    func `only one of the code's own titles is taken`(answer: String, title: String?) {
        let splits = SourceCredits.fields(songName: Self.name, artist: "Misc Soundtrack")
            .titleSplits
        #expect(FilmTitleResolver.pick(answer, from: splits)?.title == title)
    }

    static func router(answer: String?) throws -> Router {
        let fields = SourceCredits.fields(songName: name, artist: "Misc Soundtrack")
        let task = try #require(FilmTitleResolver.task(for: fields))
        guard let answer else { return Router(providers: []) }
        let output = #"{"title":"\#(answer)","key":""}"#
        let json = #"{"task":"metadata","input":"\#(task.inputHash)","output":\#(output)}"#
        let call = try JSONDecoder().decode(RecordedCall.self, from: Data(json.utf8))
        return Router(providers: [ScriptedProvider(id: .foundationModels, recordings: [call])])
    }

    @Test
    func `the model's pick replaces the fallback and clears the flag`() async throws {
        let fields = SourceCredits.fields(songName: Self.name, artist: "Misc Soundtrack")
        let resolved = try await FilmTitleResolver.resolve(
            fields,
            router: Self.router(answer: "Shiva - Kesariya"),
        )
        #expect(resolved.title == "Shiva - Kesariya")
        #expect(resolved.album == "Brahmāstra Part One")
        #expect(!resolved.titleUncertain)
    }

    @Test(arguments: [nil, "Something Invented"] as [String?])
    func `no model or an invented answer keeps the flagged fallback`(answer: String?) async throws {
        let fields = SourceCredits.fields(songName: Self.name, artist: "Misc Soundtrack")
        let resolved = try await FilmTitleResolver.resolve(
            fields,
            router: Self.router(answer: answer),
        )
        #expect(resolved == fields)
    }
}
