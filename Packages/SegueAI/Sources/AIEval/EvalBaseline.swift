import Foundation

/// The stored fixture scores (`make eval-ai BASELINE=1` writes `Resources/baseline.json`):
/// aggregate numbers per provider, compared on every run and shown beside a custom model's
/// "Check this model" score (Personal, R62).
public enum EvalBaseline {
    /// The baseline file's bytes, or nil if this build has none.
    public static var data: Data? {
        Bundle.module.url(forResource: "baseline", withExtension: "json")
            .flatMap { try? Data(contentsOf: $0) }
    }
}
