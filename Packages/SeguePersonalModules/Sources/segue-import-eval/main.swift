// segue-import-eval (P9-4 spec 16.3): runs every page reader over the saved corpus pages and
// scores the result against the hand-written gold. Manual and offline: `make eval-import`.
// Never part of quick, gate or check.
//
// Usage: segue-import-eval <corpus dir> [--list] [--show <page slug>] [--dump <dir>]
// --dump writes what the import makes of each page (<slug>.cho, or a `# noChart` line) for
// the gold review tool (tools/review-gold.py) to start from.
import Foundation
import Ingest
import Plugins
import SeguePersonalModules

let arguments = Array(CommandLine.arguments.dropFirst())
guard let root = arguments.first else {
    FileHandle.standardError
        .write(Data("usage: segue-import-eval <corpus dir> [--show slug]\n".utf8))
    exit(2)
}

let show = arguments.firstIndex(of: "--show")
    .flatMap { arguments.indices.contains($0 + 1) ? arguments[$0 + 1] : nil }
let rows = try EvalCorpus.load(root: URL(filePath: root))
var report = EvalReport()
for row in rows {
    guard let html = try? String(contentsOf: row.file, encoding: .utf8) else { continue }
    let reading = WebImportEval.read(page: html, url: row.url)
    let score = EvalScore(row: row, reading: reading)
    report.add(score)
    if let dump = arguments.firstIndex(of: "--dump")
        .flatMap({ arguments.indices.contains($0 + 1) ? arguments[$0 + 1] : nil })
    {
        let out = URL(filePath: dump).appending(path: row.slug + ".cho")
        let failure = reading.failure.map { "\($0)" } ?? "unknown"
        let text = reading.result?.text ?? "# noChart: \(failure)\n"
        try? FileManager.default.createDirectory(
            at: out.deletingLastPathComponent(),
            withIntermediateDirectories: true,
        )
        try? Data(text.utf8).write(to: out)
    }
    if arguments.contains("--list") {
        let meta = reading.result?.metadata
        let lines = reading.result?.text.split(separator: "\n").count ?? 0
        let failure = reading.failure.map { "\($0)" } ?? ""
        print([
            row.site,
            String(row.file.lastPathComponent.prefix(50)),
            reading.reader?.rawValue ?? "-",
            reading.fellBack ? "fellBack" : "",
            failure,
            meta?.title ?? "",
            meta?.artists.joined(separator: "+") ?? "",
            meta?.album ?? "",
            meta?.key ?? "",
            meta?.capo.map(String.init) ?? "",
            "\(lines)",
            WebImportEval.siteCheck(page: html, url: row.url).joined(separator: ","),
        ]
        .joined(separator: " | "))
    }
    if let show, row.file.lastPathComponent.contains(show) {
        print("== \(row.url.absoluteString)")
        print(reading.result?.text ?? "failure: \(String(describing: reading.failure))")
    }
}

print(report.render())
