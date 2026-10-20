import FoundationModels
import ModelPort

/// Foundation Models values -> the port's typed values (pure, unit-tested).
public enum FoundationModelsMapping {
    /// R69: each `UnavailableReason` to its cause; a reason this build does not know is
    /// `.unknown` ("Apple Intelligence isn't available right now").
    public static func cause(
        _ reason: SystemLanguageModel.Availability.UnavailableReason,
    ) -> UnavailableCause {
        switch reason {
        case .deviceNotEligible: .deviceNotEligible
        case .appleIntelligenceNotEnabled: .appleIntelligenceNotEnabled
        case .modelNotReady: .modelNotReady
        @unknown default: .unknown
        }
    }

    public static func availability(
        _ availability: SystemLanguageModel.Availability,
    ) -> ProviderAvailability {
        switch availability {
        case .available: .available
        case let .unavailable(reason): .unavailable(cause(reason))
        }
    }

    /// Every error a call can throw, as a typed fallback reason (spec 4.1).
    public static func providerError(_ error: any Error) -> ProviderError {
        if let error = error as? ProviderError {
            return error
        }
        if let error = error as? LanguageModelSession.GenerationError {
            return providerError(error)
        }
        if #available(macOS 27.0, *), let error = error as? LanguageModelError {
            return providerError(error)
        }
        return .other
    }

    public static func providerError(_ error: LanguageModelSession
        .GenerationError) -> ProviderError
    {
        switch error {
        case .exceededContextWindowSize: .contextOverflow
        // The on-device model is not downloaded or not ready.
        case .assetsUnavailable: .notInstalled
        case .guardrailViolation: .guardrail
        case .unsupportedGuide: .other
        case .unsupportedLanguageOrLocale: .unsupportedLanguage
        case .decodingFailure: .decodingFailure
        case .rateLimited: .rateLimited
        case .concurrentRequests: .busy
        case .refusal: .refusal
        @unknown default: .other
        }
    }

    /// macOS 27 renames the errors (`LanguageModelError`); the mapping is the same.
    @available(macOS 27.0, *)
    public static func providerError(_ error: LanguageModelError) -> ProviderError {
        switch error {
        case .contextSizeExceeded: .contextOverflow
        case .rateLimited: .rateLimited
        case .guardrailViolation: .guardrail
        case .refusal: .refusal
        case .unsupportedLanguageOrLocale: .unsupportedLanguage
        case .timeout: .timeout
        case .unsupportedCapability, .unsupportedGenerationGuide, .unsupportedTranscriptContent:
            .other
        @unknown default: .other
        }
    }
}
