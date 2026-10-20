import AIEval
import Foundation
import MLXAdapter
import MLXEngine
import ModelPort
import ModelStore

/// "Check this model" (R62): runs the bundled original paste fixtures through a custom model
/// and scores it with the spike metrics, to show beside the curated model's stored score. It
/// never blocks using the model, whatever the score.
enum AdvancedModelsCheck {
    struct Outcome: Sendable, Hashable {
        var score: EvalScore
        /// The curated model's stored score on the same fixtures (`make eval-ai BASELINE=1`).
        var curated: EvalScore?
    }

    /// The fixtures the Personal app bundles (`Contents/Resources/paste`).
    static var fixturesFolder: URL? {
        Bundle.main.url(forResource: "paste", withExtension: nil)
    }

    /// Runs every fixture through `model` (installed at `folder`); `progress` gets "n of m".
    static func run(
        model: LocalModelManifest,
        folder: URL,
        progress: @escaping @Sendable (Int, Int) -> Void,
    ) async -> Outcome? {
        guard let fixturesFolder,
              let fixtures = try? EvalFixture.load(directory: fixturesFolder),
              let gold = try? GoldEntry.load(fixturesFolder.appending(path: "gold.json"))
        else { return nil }
        let provider = MLXProvider(
            engine: MLXGuidedEngine(),
            resolver: Fixed(manifest: model, folder: folder),
            defaultModel: model.ref,
            // Warm across the fixtures; dropped when the check ends.
            configuration: .init(timeout: .seconds(180), linger: .seconds(10)),
        )
        let counter = Counter(total: fixtures.count, report: progress)
        let (records, _) = await PasteEvaluator.run(fixtures, provider: provider) { _ in
            counter.step()
        }
        return Outcome(score: EvalScore(records: records, gold: gold), curated: curatedScore)
    }

    /// `mlx-fixtures` from the baseline AIEval bundles.
    static var curatedScore: EvalScore? {
        guard let data = EvalBaseline.data,
              let scores = try? JSONDecoder().decode([String: EvalScore].self, from: data)
        else { return nil }
        return scores["mlx-fixtures"]
    }

    private struct Fixed: ModelFolderResolver {
        let manifest: LocalModelManifest
        let folder: URL

        func activeModel() async -> (manifest: LocalModelManifest, folder: URL)? {
            (manifest, folder)
        }
    }

    private final class Counter: @unchecked Sendable {
        private let lock = NSLock()
        private var done = 0
        private let total: Int
        private let report: @Sendable (Int, Int) -> Void

        init(total: Int, report: @escaping @Sendable (Int, Int) -> Void) {
            self.total = total
            self.report = report
        }

        func step() {
            let done = lock.withLock {
                self.done += 1
                return self.done
            }
            report(done, total)
        }
    }
}
