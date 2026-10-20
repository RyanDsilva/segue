// `make eval-ai` (manual, never in `make check` or `make gate`): runs real Foundation Models
// and the local MLX model over the golden paste fixtures and, when present, Ryan's local
// pastes; writes one JSON line per paste and provider plus a score summary (the spike
// metrics, aggregate numbers only), compares the fixture scores with the stored baseline, and
// with --record refreshes the `ScriptedProvider` recordings of the committed fixtures only
// (and, with --set-requests, the set assistant's `SetRequestTask` recordings beside that
// requests file, in `recorded/<provider>/set-requests.json`).
// Built by xcodebuild (SwiftPM's command line does not build MLX's Metal library).
//
//   segue-eval --fixtures <dir> --gold <file> --model <dir> --out <dir>
//              [--pastes <dir> --pastes-gold <file>] [--providers mlx,fm]
//              [--baseline <file>] [--write-baseline] [--record <recorded dir>]
//              [--set-requests <requests.json>]

import AIEval
import Foundation
import FoundationModelsAdapter
import MLXAdapter
import MLXEngine
import ModelPort
import ModelStore

struct Options {
    var values: [String: String] = [:]
    var flags: Set<String> = []

    init(_ arguments: [String]) {
        var iterator = arguments.dropFirst().makeIterator()
        while let argument = iterator.next() {
            guard argument.hasPrefix("--") else { continue }
            let name = String(argument.dropFirst(2))
            if ["write-baseline"].contains(name) {
                flags.insert(name)
            } else if let value = iterator.next() {
                values[name] = value
            }
        }
    }

    func url(_ name: String) -> URL? {
        values[name].map { URL(fileURLWithPath: $0) }
    }
}

/// The model folder `make eval-ai` prepared (only the manifest's files), as the installed model.
struct FixedFolder: ModelFolderResolver {
    let manifest: LocalModelManifest
    let folder: URL

    func activeModel() async -> (manifest: LocalModelManifest, folder: URL)? {
        (manifest, folder)
    }
}

func fail(_ message: String) -> Never {
    FileHandle.standardError.write(Data("segue-eval: \(message)\n".utf8))
    exit(2)
}

// Progress lines as they happen, also when stdout is a log file.
setvbuf(stdout, nil, _IOLBF, 0)
let options = Options(CommandLine.arguments)
guard let fixturesDir = options.url("fixtures"), let goldURL = options.url("gold"),
      let out = options.url("out")
else { fail("usage: --fixtures <dir> --gold <file> --model <dir> --out <dir> [...]") }
let providerNames = (options.values["providers"] ?? "mlx,fm").split(separator: ",").map(String.init)
try FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)

struct EvalSet {
    var name: String
    var fixtures: [EvalFixture]
    var gold: [String: GoldEntry]
}

var sets = try [EvalSet(
    name: "fixtures",
    fixtures: EvalFixture.load(directory: fixturesDir),
    gold: GoldEntry.load(goldURL),
)]
if let pastes = options.url("pastes"), let pastesGold = options.url("pastes-gold"),
   FileManager.default.fileExists(atPath: pastes.path)
{
    try sets.append(EvalSet(
        name: "pastes",
        fixtures: EvalFixture.load(directory: pastes),
        gold: GoldEntry.load(pastesGold),
    ))
}

var providers: [any LanguageModelProvider] = []
for name in providerNames {
    switch name {
    case "mlx":
        guard let model = options.url("model"),
              let manifest = ModelStore.curatedCatalog.first
        else { fail("--model <dir> is needed for mlx") }
        // Warm between pastes like the spike measured (the app unloads after 2 s, R94).
        providers.append(MLXProvider(
            engine: MLXGuidedEngine(),
            resolver: FixedFolder(manifest: manifest, folder: model),
            defaultModel: manifest.ref,
            configuration: .init(timeout: .seconds(300), linger: .seconds(120)),
        ))
    case "fm":
        let fm = FoundationModelsProvider()
        if await fm.availability() == .available {
            providers.append(fm)
        } else {
            await print("fm: skipped, \(fm.availability())")
        }
    default:
        fail("unknown provider \(name)")
    }
}

/// P3-7: records `SetRequestTask` answers for the set assistant's tests. The input is
/// `{"libraryTags": [...], "words": ["mellow vibe", ...]}` (the lexicon's leftovers).
func recordSetRequests(_ requests: URL, provider: any LanguageModelProvider, source: String)
    async throws
{
    struct SetRequestInputs: Decodable {
        var libraryTags: [String]
        var words: [String]
    }
    let inputs = try JSONDecoder().decode(SetRequestInputs.self, from: Data(contentsOf: requests))
    var calls: [RecordedCall] = []
    for words in inputs.words {
        let task = SetRequestTask(words: words, libraryTags: inputs.libraryTags)
        do throws(ProviderError) {
            let result = try await provider.run(task, context: CallContext(allowsChunking: false))
            print("  \(words): \(result.output) in \(result.metrics.latency)")
            try? calls.append(RecordedCall.answered(task, result.output))
        } catch {
            print("  \(words): \(error)")
            calls.append(RecordedCall.failed(task, error))
        }
    }
    let file = RecordingFile(
        provider: provider.id.kind, fixture: "set-requests", source: source, calls: calls,
    )
    let folder = requests.deletingLastPathComponent()
        .appending(path: "recorded/\(provider.id.kind.rawValue)", directoryHint: .isDirectory)
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    try file.encoded().write(to: folder.appending(path: "set-requests.json"))
    print("  recorded \(calls.count) set requests into \(folder.path)")
}

let os = ProcessInfo.processInfo.operatingSystemVersionString
var scores: [String: EvalScore] = [:]
var summary = ""
for provider in providers {
    let kind = provider.id.kind.rawValue
    for set in sets {
        print("== \(kind) on \(set.name) (\(set.fixtures.count) pastes)")
        let recordDir = set.name == "fixtures" ? options.url("record") : nil
        let source = kind == "fm" ? "apple-fm \(os)" : "mlx \(provider.id)"
        // Ryan's pastes are copyrighted: progress lines name them only by position.
        let named = set.name == "fixtures"
        let (records, recordings) = await PasteEvaluator.run(
            set.fixtures,
            provider: provider,
            recordingSource: recordDir == nil ? nil : source,
        ) { line in
            print(named ? "  \(line)" : "  .")
        }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let lines = try records.map { try String(bytes: encoder.encode($0), encoding: .utf8) ?? "" }
        try (lines.joined(separator: "\n") + "\n").write(
            to: out.appending(path: "\(kind)-\(set.name).jsonl"), atomically: true, encoding: .utf8,
        )
        let score = EvalScore(records: records, gold: set.gold)
        scores["\(kind)-\(set.name)"] = score
        summary += "## \(kind) on \(set.name)\n\(score.report)\n\n"
        print(score.report)
        if let recordDir {
            let folder = recordDir.appending(path: kind, directoryHint: .isDirectory)
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            for file in recordings {
                try file.encoded().write(to: folder.appending(path: "\(file.fixture).json"))
            }
            print("  recorded \(recordings.count) files into \(folder.path)")
        }
    }
    if options.url("record") != nil, let requests = options.url("set-requests") {
        print("== \(kind) on set requests")
        let source = kind == "fm" ? "apple-fm \(os)" : "mlx \(provider.id)"
        try await recordSetRequests(requests, provider: provider, source: source)
    }
}

let encoder = JSONEncoder()
encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
try encoder.encode(scores).write(to: out.appending(path: "summary.json"))
try summary.write(to: out.appending(path: "summary.txt"), atomically: true, encoding: .utf8)

var regressed = false
if let baselineURL = options.url("baseline") {
    if options.flags.contains("write-baseline") {
        var stored = (try? JSONDecoder().decode(
            [String: EvalScore].self, from: Data(contentsOf: baselineURL),
        )) ?? [:]
        // Only the committed fixtures' scores are stored (the local pastes stay local).
        for (key, score) in scores where key.hasSuffix("-fixtures") {
            stored[key] = score
        }
        try encoder.encode(stored).write(to: baselineURL)
        print("baseline written: \(baselineURL.path)")
    } else if let data = try? Data(contentsOf: baselineURL),
              let baseline = try? JSONDecoder().decode([String: EvalScore].self, from: data)
    {
        for (key, score) in scores.sorted(by: { $0.key < $1.key }) {
            guard let before = baseline[key] else { continue }
            let found = score.regressions(against: before)
            print("\(key) vs baseline: " + (found.isEmpty ? "ok" : found.joined(separator: "; ")))
            regressed = regressed || !found.isEmpty
        }
    }
}

exit(regressed ? 1 : 0)
