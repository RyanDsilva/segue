import Foundation
import Services
import Support
import Testing

/// The privacy-safe rolling log on real files (spec 14.2-5).
struct ServicesDiagnosticLogTests {
    private enum ShowError: LoggableError {
        case conflict

        var logCode: StaticString {
            "showConflict"
        }
    }

    private static func text(_ url: URL) -> String {
        (try? String(contentsOf: url, encoding: .utf8)) ?? ""
    }

    @Test
    func `lines are typed, UTC and carry no user content`() async throws {
        let sandbox = try ServicesSandbox()
        defer { sandbox.cleanUp() }
        let clock = ManualClock(start: Date(timeIntervalSince1970: 1_792_270_991.4025))
        let log = DiagnosticLog(directory: sandbox.directory, clock: clock, mirrorToOSLog: false)

        log.notice(.library, "opened", ["songs": .bucket(SongBucket(57)), "ms": .int(212)])
        let secretPath = "/Users/x/Music/Segue/songs/secret-title.cho"
        let cocoa = CocoaError(.fileNoSuchFile, userInfo: [NSFilePathErrorKey: secretPath])
        log.error(.library, "save failed", ["error": .error(LoggedError(cocoa))])
        let odd = NSError(domain: "/Users/x/secret-title.cho", code: 3)
        log.error(.index, "rebuild failed", ["error": .error(LoggedError(odd)), "ok": .bool(false)])
        log.info(.show, "ended", [
            "error": .error(LoggedError(ShowError.conflict)),
            "took": .duration(.milliseconds(1500)),
            "ratio": .double(0.25),
            "kind": .token("gig"),
        ])
        await log.flush()

        let lines = Self.text(log.fileURL(0)).split(separator: "\n").map(String.init)
        #expect(lines == [
            "2026-10-17T21:03:11.402Z notice library opened songs=50-99 ms=212",
            "2026-10-17T21:03:11.402Z error library save failed error=NSCocoaErrorDomain:4",
            "2026-10-17T21:03:11.402Z error index rebuild failed error=other:3 ok=false",
            "2026-10-17T21:03:11.402Z info show ended "
                + "error=showConflict took=1500ms ratio=0.250 kind=gig",
        ])
        #expect(!Self.text(log.fileURL(0)).contains("secret"))
        let files = await log.files()
        #expect(files.map(\.name) == ["segue-0.log"])
    }

    @Test
    func `five launches keep four files, newest first`() async throws {
        let sandbox = try ServicesSandbox()
        defer { sandbox.cleanUp() }
        for launch in 0 ..< 5 {
            let log = DiagnosticLog(directory: sandbox.directory, mirrorToOSLog: false)
            log.notice(.app, "launched", ["launch": .int(launch)])
            await log.flush()
        }
        let log = DiagnosticLog(directory: sandbox.directory, mirrorToOSLog: false)
        log.notice(.app, "launched", ["launch": .int(5)])
        await log.flush()

        let names = try FileManager.default.contentsOfDirectory(atPath: sandbox.directory.path())
            .filter { $0.hasSuffix(".log") }.sorted()
        #expect(names == ["segue-0.log", "segue-1.log", "segue-2.log", "segue-3.log"])
        for index in 0 ..< 4 {
            #expect(Self.text(log.fileURL(index)).hasSuffix("launched launch=\(5 - index)\n"))
        }
        let files = await log.files()
        #expect(files.map(\.name) == ["segue-0.log", "segue-1.log", "segue-2.log", "segue-3.log"])
    }

    @Test
    func `a full file gets one truncation line and stays under the cap`() async throws {
        let sandbox = try ServicesSandbox()
        defer { sandbox.cleanUp() }
        let log = DiagnosticLog(directory: sandbox.directory, mirrorToOSLog: false)
        for index in 0 ..< 12000 {
            log.notice(
                .index,
                "rebuilt",
                ["ms": .int(index), "songs": .bucket(SongBucket.thousandPlus)],
            )
        }
        await log.flush()

        let data = try Data(contentsOf: log.fileURL(0))
        #expect(data.count <= DiagnosticLog.fileByteLimit)
        #expect(data.count > DiagnosticLog.fileByteLimit - 200)
        let lines = try #require(String(bytes: data, encoding: .utf8)).split(separator: "\n")
        #expect(lines.last == "log.truncated")
        #expect(lines.count(where: { $0 == "log.truncated" }) == 1)
    }
}
