import Foundation
#if canImport(FoundationModels)
import FoundationModels
#endif

// Apple's on-device model (FoundationModels, macOS 26+), kept free of any
// other Tippi type on purpose: `scripts/apple-intelligence-messung/` compiles
// this file on its own, so the measurement runs exactly the code that ships.
// The `LLMProvider` conformance lives in `AppleIntelligenceProvider.swift`.
//
// Availability check and error wording are adapted from Blitztext's
// `TextRewriter.swift` (MIT, see NOTICES.md).

/// Why Apple Intelligence produced no text — every case has a sentence for the
/// user, because the dictation toast and the Preview show `localizedDescription`.
enum AppleIntelligenceError: LocalizedError, Equatable {
    case requiresNewerMacOS
    case deviceNotEligible
    case notEnabled
    case modelNotReady
    case unavailable
    /// Instructions + text + answer exceed the context window.
    case textTooLong
    /// Apple's content filter or the model itself declined.
    case rejected
    case unsupportedLanguage
    case busy
    case failed

    /// The model cannot run at all right now — as opposed to a request that
    /// failed. The router may then try another *local* provider.
    var isUnavailability: Bool {
        switch self {
        case .requiresNewerMacOS, .deviceNotEligible, .notEnabled, .modelNotReady, .unavailable: return true
        default: return false
        }
    }

    var errorDescription: String? {
        switch self {
        case .requiresNewerMacOS:  return String(localized: "llm.apple.error.requiresNewerMacOS")
        case .deviceNotEligible:   return String(localized: "llm.apple.error.deviceNotEligible")
        case .notEnabled:          return String(localized: "llm.apple.error.notEnabled")
        case .modelNotReady:       return String(localized: "llm.apple.error.modelNotReady")
        case .unavailable:         return String(localized: "llm.apple.error.unavailable")
        case .textTooLong:         return String(localized: "llm.apple.error.textTooLong")
        case .rejected:            return String(localized: "llm.apple.error.rejected")
        case .unsupportedLanguage: return String(localized: "llm.apple.error.unsupportedLanguage")
        case .busy:                return String(localized: "llm.apple.error.busy")
        case .failed:              return String(localized: "llm.apple.error.failed")
        }
    }
}

enum AppleIntelligenceModel {
    /// `nil` = ready to answer.
    static var unavailableReason: AppleIntelligenceError? {
        #if canImport(FoundationModels)
        if #available(macOS 26, *) {
            switch SystemLanguageModel.default.availability {
            case .available:                                return nil
            case .unavailable(.deviceNotEligible):          return .deviceNotEligible
            case .unavailable(.appleIntelligenceNotEnabled): return .notEnabled
            case .unavailable(.modelNotReady):              return .modelNotReady
            case .unavailable:                              return .unavailable
            }
        }
        #endif
        return .requiresNewerMacOS
    }

    enum Sampling: Equatable, Sendable {
        case greedy
        case temperature(Double)
    }

    /// Tippi's temperature hint → sampling. The only hint Tippi sends is the
    /// dictation cleanup's 0.1 (`TaskTemperature.transcriptCleanup`, pinned by
    /// a test): "change as little as possible" — greedy is the flattest the
    /// framework offers. No hint → Tippi's usual 0.3.
    static func sampling(forTemperatureHint hint: Double?) -> Sampling {
        guard let hint else { return .temperature(0.3) }
        return hint <= 0.1 ? .greedy : .temperature(hint)
    }

    /// `.permissive` is Apple's mode for transforming text the user supplied:
    /// String answers no longer throw a guardrail violation (the model may
    /// still refuse). Tippi only ever rewrites the user's own text — an angry
    /// message for "Defuse" is the whole point of that prompt.
    enum Guardrails: Sendable { case permissive, standard }

    /// One fresh session per call: Tippi requests are independent, and a
    /// session cannot serve two requests at once.
    ///
    /// No `maximumResponseTokens` on purpose: hitting that limit ends the
    /// answer silently mid-sentence, and a cut-off rewrite must never be
    /// inserted. Without it the answer ends on its own or the context window
    /// fills — which throws (`.textTooLong`), so nothing partial comes back.
    static func respond(
        instructions: String,
        text: String,
        sampling: Sampling,
        guardrails: Guardrails = .permissive
    ) async throws -> String {
        #if canImport(FoundationModels)
        if #available(macOS 26, *) {
            if let reason = unavailableReason { throw reason }
            let model = SystemLanguageModel(guardrails: guardrails == .permissive
                                            ? .permissiveContentTransformations : .default)
            let session = LanguageModelSession(model: model, instructions: instructions)
            let options: GenerationOptions
            switch sampling {
            case .greedy:               options = GenerationOptions(samplingMode: .greedy)
            case .temperature(let t):   options = GenerationOptions(temperature: t)
            }
            do {
                return try await session.respond(to: text, options: options).content
            } catch {
                throw mapped(error)
            }
        }
        #endif
        throw AppleIntelligenceError.requiresNewerMacOS
    }

    #if canImport(FoundationModels)
    /// macOS 27 introduced `LanguageModelError` and deprecated
    /// `GenerationError`; which one a 27 system throws to a 26-era call is not
    /// documented, so both are mapped.
    @available(macOS 26, *)
    static func mapped(_ error: Error) -> Error {
        if error is CancellationError { return error }
        if #available(macOS 27, *), let error = error as? LanguageModelError {
            switch error {
            case .contextSizeExceeded:              return AppleIntelligenceError.textTooLong
            case .guardrailViolation, .refusal:     return AppleIntelligenceError.rejected
            case .unsupportedLanguageOrLocale:      return AppleIntelligenceError.unsupportedLanguage
            case .rateLimited, .timeout:            return AppleIntelligenceError.busy
            default:                                return AppleIntelligenceError.failed
            }
        }
        if let error = error as? LanguageModelSession.GenerationError {
            switch error {
            case .exceededContextWindowSize:        return AppleIntelligenceError.textTooLong
            case .guardrailViolation, .refusal:     return AppleIntelligenceError.rejected
            case .unsupportedLanguageOrLocale:      return AppleIntelligenceError.unsupportedLanguage
            case .assetsUnavailable:                return AppleIntelligenceError.modelNotReady
            case .rateLimited, .concurrentRequests: return AppleIntelligenceError.busy
            default:                                return AppleIntelligenceError.failed
            }
        }
        return AppleIntelligenceError.failed
    }
    #endif
}
