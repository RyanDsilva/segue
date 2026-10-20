// Manual runner: records real Foundation Models answers for the paste fixtures, for
// ScriptedProvider (spec section 4). Never run by tests or gates; P3-3 folds it into
// `make eval-ai RECORD=1`.
//
//   swift run segue-ai-record <fixtures dir> <output dir>
//
// e.g. `swift run segue-ai-record ../SegueCore/Tests/Fixtures/paste
// ../SegueCore/Tests/Fixtures/paste/recorded/fm`. Writes one `<fixture>.json` per fixture that
// asks a model anything; fixtures with no question get no file.

import Foundation
import FoundationModels
import FoundationModelsAdapter
import Ingest
import ModelPort

let arguments = CommandLine.arguments
guard arguments.count == 3 || arguments.count == 4 && arguments[1] == "--set-requests" else {
    print("usage: segue-ai-record <fixtures dir> <output dir>")
    print("       segue-ai-record --set-requests <requests.json> <output.json>")
    exit(2)
}

// P3-7: `--set-requests` records `SetRequestTask` answers for the set assistant's tests. The
// input is `{"libraryTags": [...], "words": ["mellow vibe", ...]}` (the lexicon's leftovers).
if arguments[1] == "--set-requests" {
    struct SetRequestInputs: Decodable {
        var libraryTags: [String]
        var words: [String]
    }
    let inputs = try JSONDecoder().decode(
        SetRequestInputs.self, from: Data(contentsOf: URL(fileURLWithPath: arguments[2])),
    )
    let provider = FoundationModelsProvider()
    guard await provider.availability() == .available else {
        await print("Foundation Models is not available: \(provider.availability())")
        exit(1)
    }
    var calls: [RecordedCall] = []
    for words in inputs.words {
        let task = SetRequestTask(words: words, libraryTags: inputs.libraryTags)
        do throws(ProviderError) {
            let result = try await provider.run(task, context: CallContext(allowsChunking: false))
            print("\(words): \(result.output) in \(result.metrics.latency)")
            if let call = try? RecordedCall.answered(task, result.output) {
                calls.append(call)
            }
        } catch {
            print("\(words): \(error)")
            calls.append(RecordedCall.failed(task, error))
        }
    }
    let os = ProcessInfo.processInfo.operatingSystemVersionString
    let file = RecordingFile(
        provider: .foundationModels,
        fixture: "set-requests",
        source: "apple-fm \(os)",
        calls: calls,
    )
    try file.encoded().write(to: URL(fileURLWithPath: arguments[3]))
    exit(0)
}

let fixtures = URL(fileURLWithPath: arguments[1])
let output = URL(fileURLWithPath: arguments[2])
let provider = FoundationModelsProvider()
guard await provider.availability() == .available else {
    await print("Foundation Models is not available: \(provider.availability())")
    exit(1)
}

let context = CallContext(allowsChunking: true)
let os = ProcessInfo.processInfo.operatingSystemVersionString
try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)

func record<T: ModelTask>(_ task: T?) async -> RecordedCall? {
    guard let task else { return nil }
    do throws(ProviderError) {
        let result = try await provider.run(task, context: context)
        print("  \(T.kind.rawValue): ok in \(result.metrics.latency)")
        return try? RecordedCall.answered(task, result.output)
    } catch {
        print("  \(T.kind.rawValue): \(error)")
        return RecordedCall.failed(task, error)
    }
}

let names = try FileManager.default.contentsOfDirectory(atPath: fixtures.path)
    .filter { $0.hasSuffix(".txt") || $0.hasSuffix(".crd") }
    .sorted()
for name in names {
    let data = try Data(contentsOf: fixtures.appendingPathComponent(name))
    guard let text = String(data: data, encoding: .utf8)
        ?? String(data: data, encoding: .windowsCP1252)
    else { continue }
    let stem = (name as NSString).deletingPathExtension
    let origin: IngestOrigin = name.hasSuffix(".crd") ? .file(extension: "crd") : .paste
    let result = IngestPipeline.ingest(text, origin: origin)
    print(stem)
    let calls = await [
        record(PasteRefiner.labelTask(for: result)),
        record(PasteRefiner.metadataTask(for: result)),
        record(PasteRefiner.ambiguousLineTask(for: result)),
    ].compactMap(\.self)
    guard !calls.isEmpty else {
        print("  nothing to ask")
        continue
    }
    let file = RecordingFile(
        provider: .foundationModels,
        fixture: stem,
        source: "apple-fm \(os)",
        calls: calls,
    )
    try file.encoded().write(to: output.appendingPathComponent("\(stem).json"))
}
