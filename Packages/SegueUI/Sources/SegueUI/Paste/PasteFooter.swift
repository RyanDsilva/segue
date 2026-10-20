#if os(macOS)
    import Foundation
    import ModelPort

    /// The review sheet footer's content (spec 6.2, R69, R93): what produced the result, the
    /// Apple Intelligence note when it explains a code-only result, and the quiet one-line link
    /// to Settings > AI when the curated model is not installed and the result came from Apple
    /// Intelligence or code. No popup, tip or sheet ever offers the download.
    public struct PasteFooter: Equatable, Sendable {
        /// "Refining with Apple Intelligence..." while a model runs, else nil.
        public var refiningLine: String?
        /// "Labels by Apple Intelligence", "Converted without AI", ...
        public var producedBy: String
        /// The R69 note (with its "Open System Settings" action), when relevant.
        public var note: AIAvailabilityCopy.Note?
        public var showsDownloadLink: Bool

        public static let downloadLinkTitle = "Get the Segue model for better results"
        public static let aiOffLine = "Converted without AI (AI is off in Settings)"
        public static let codeOnlyLine = "Converted without AI"

        /// - Parameters:
        ///   - status: the song's refinement status.
        ///   - reports: how its tasks routed so far.
        ///   - aiEnabled: the AI toggle (R93).
        ///   - availability: each provider's last availability read.
        public static func make(
            status: PasteRefinementStatus,
            reports: [ModelTaskKind: RoutingReport],
            aiEnabled: Bool,
            availability: [ProviderKind: ProviderAvailability],
        ) -> Self {
            let curatedMissing = availability[.mlx] == nil
                || availability[.mlx] == .unavailable(.notInstalled)
            guard aiEnabled else {
                return Self(
                    refiningLine: nil,
                    producedBy: aiOffLine,
                    note: nil,
                    showsDownloadLink: false,
                )
            }
            let refining: String? = if case let .running(kind) = status {
                "Refining with \(kind.map(name) ?? "AI")..."
            } else {
                nil
            }
            let answered = [ModelTaskKind.sectionLabels, .metadata, .ambiguousLines]
                .lazy.compactMap { reports[$0]?.answeredBy }.first
            switch answered {
            case let .mlx(model):
                return Self(
                    refiningLine: refining,
                    producedBy: "Labels by \(modelName(model))",
                    note: nil,
                    showsDownloadLink: false,
                )
            case .foundationModels:
                return Self(
                    refiningLine: refining,
                    producedBy: "Labels by Apple Intelligence",
                    note: nil,
                    showsDownloadLink: curatedMissing,
                )
            case nil:
                let note: AIAvailabilityCopy.Note? = if case let .unavailable(cause) = availability[
                    .foundationModels,
                ] {
                    AIAvailabilityCopy.note(for: cause)
                } else {
                    nil
                }
                return Self(
                    refiningLine: refining,
                    producedBy: codeOnlyLine,
                    note: refining == nil ? note : nil,
                    showsDownloadLink: curatedMissing,
                )
            }
        }

        static func name(_ kind: ProviderKind) -> String {
            switch kind {
            case .foundationModels: "Apple Intelligence"
            case .mlx: "the Segue model"
            }
        }

        /// "Qwen3-4B" from `mlx-community/Qwen3-4B-Instruct-2507-4bit`.
        static func modelName(_ model: ModelRef) -> String {
            let repo = model.repo.split(separator: "/").last.map(String.init) ?? model.repo
            if let range = repo.range(of: "-Instruct") {
                return String(repo[..<range.lowerBound])
            }
            return repo
        }
    }
#endif
