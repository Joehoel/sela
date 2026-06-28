import AISDKJSONSchema
import AISDKProvider
import AISDKProviderUtils
import Foundation
import SwiftAISDK

/// Friendly, user-facing errors for the unified translation step. The opaque
/// swift-ai-sdk errors (auth, rate limit) are mapped to these so the editor's
/// error banner stays actionable.
enum AISDKTranslationError: LocalizedError, Equatable {
    case authenticationFailed
    case rateLimitExceeded
    case incompleteResponse(received: Int, expected: Int)

    var errorDescription: String? {
        switch self {
        case .authenticationFailed:
            "The translation provider rejected the request. Check your API key in Settings."
        case .rateLimitExceeded:
            "Translation rate limit reached. Try again in a moment."
        case let .incompleteResponse(received, expected):
            "The model only translated \(received) of \(expected) lines. Please try again."
        }
    }

    /// Maps an opaque SDK/provider error to a friendly case, or `nil` if it isn't
    /// a recognizable auth/rate-limit failure (caller should rethrow the original).
    static func classify(_ error: any Error) -> AISDKTranslationError? {
        let description = (error as NSError).localizedDescription.lowercased()
        if description.contains("api key") || description.contains("unauthorized")
            || description.contains("401") || description.contains("403")
            || description.contains("permission")
        {
            return .authenticationFailed
        }
        if description.contains("rate limit") || description.contains("429")
            || description.contains("quota") || description.contains("resource_exhausted")
        {
            return .rateLimitExceeded
        }
        return nil
    }
}

/// Unified translation step backed by `swift-ai-sdk`. Resolves a
/// `LanguageModelV3` for the selected engine/model and runs the call through the
/// SDK's `generateObject`, mapping the structured `[{number,text}]` output back
/// onto the pipeline items by number.
///
/// This replaces the per-engine HTTP steps for LLM backends. Line mapping is
/// structural (via the schema), so there is no text parsing to misassign a
/// translation to the wrong source line.
struct AISDKTranslationStep: TranslationPipelineStep {
    let model: any LanguageModelV3
    let mode: TranslationPrompt.Mode
    let isRequired: Bool
    /// Sampling temperature (0.3 for LLM engines for determinism); `nil` leaves
    /// the provider default. Ignored by custom (non-LLM) backends.
    let temperature: Double?
    /// Provider-specific options (e.g. Gemini `thinkingBudget` for the Flash tier).
    let providerOptions: ProviderOptions?

    var name: String {
        switch mode {
        case .translate: "Translating…"
        case .refine: "Refining…"
        }
    }

    init(
        model: any LanguageModelV3,
        mode: TranslationPrompt.Mode = .translate,
        isRequired: Bool = true,
        temperature: Double? = nil,
        providerOptions: ProviderOptions? = nil
    ) {
        self.model = model
        self.mode = mode
        self.isRequired = isRequired
        self.temperature = temperature
        self.providerOptions = providerOptions
    }

    func process(_ items: inout [TranslationItem]) async throws {
        guard !items.isEmpty else { return }

        let prompt = TranslationPrompt(mode: mode)
        let systemPrompt = prompt.systemPrompt(for: items.count)
        let userPrompt = prompt.buildUserPrompt(from: items)

        let object: TranslationResult
        do {
            object = try await generateObject(
                model: .v3(model),
                schema: FlexibleSchema.auto(TranslationResult.self),
                system: systemPrompt,
                prompt: userPrompt,
                providerOptions: providerOptions,
                settings: CallSettings(temperature: temperature)
            ).object
        }
        // Preserve the custom backends' already-friendly errors; only map the
        // opaque SDK/LLM-provider errors.
        catch let error as DeepLError { throw error }
        catch let error as GoogleTranslateError { throw error }
        catch let error as MyMemoryError { throw error }
        catch let error as AppleTranslationError { throw error }
        catch let error as AISDKModelError { throw error }
        catch {
            throw AISDKTranslationError.classify(error) ?? error
        }

        Self.apply(object, to: &items)

        // In translate mode an omitted line would leave the English source as its
        // "translation" (currentText starts as the source). Fail loudly instead of
        // silently saving English. Refine mode keeps the prior translation, so a
        // missing line there is acceptable.
        if mode == .translate {
            let covered = Set(object.translations.map(\.number)).intersection(Set(1 ... items.count))
            if covered.count < items.count {
                throw AISDKTranslationError.incompleteResponse(received: covered.count, expected: items.count)
            }
        }
    }

    /// Maps the structured result back onto the items by 1-based line number.
    /// Numbers outside the valid range are ignored; lines the model omitted keep
    /// their existing text.
    static func apply(_ result: TranslationResult, to items: inout [TranslationItem]) {
        for line in result.translations where (1 ... items.count).contains(line.number) {
            items[line.number - 1].currentText = strippingEchoedNumber(line.text, number: line.number)
        }
    }

    /// Defensive: some models echo the line number into `text` ("3. Genade")
    /// despite the schema keeping `number` separate. Strip a leading number that
    /// matches this line's own number followed by a `.`/`)`/`:`/`-` separator, so
    /// translations aren't prefixed. Leaves unrelated leading numbers intact.
    static func strippingEchoedNumber(_ text: String, number: Int) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        let prefix = String(number)
        guard trimmed.hasPrefix(prefix) else { return text }
        var rest = trimmed.dropFirst(prefix.count)
        guard let separator = rest.first, ".):-".contains(separator) else { return text }
        rest = rest.dropFirst()
        return String(rest).trimmingCharacters(in: .whitespaces)
    }

    // MARK: - Provider tuning

    /// Sampling temperature for an engine — 0.3 for the LLM providers (matching
    /// the pre-migration behavior), `nil` for custom backends that ignore it.
    static func temperature(for engine: TranslationEngine) -> Double? {
        switch engine {
        case .gemini, .openAI, .anthropic: 0.3
        default: nil
        }
    }

    /// Provider options for an engine/model. Disables Gemini "thinking" for the
    /// 2.5 Flash tier (lower latency) — reasoning models (2.5 Pro, 3.x) reject
    /// `thinkingBudget: 0`, so they keep their default thinking mode.
    static func providerOptions(for engine: TranslationEngine, modelID: String) -> ProviderOptions? {
        guard engine == .gemini,
              modelID == "gemini-2.5-flash" || modelID == "gemini-2.5-flash-lite"
        else {
            return nil
        }
        return ["google": ["thinkingConfig": .object(["thinkingBudget": .number(0)])]]
    }
}

/// A pipeline step that always throws when run. Used to defer a model-resolution
/// failure (e.g. a missing API key) to pipeline-run time, so the error surfaces
/// through the same path as a failed request rather than at pipeline build time.
struct FailingTranslationStep: TranslationPipelineStep {
    let name: String
    let isRequired: Bool
    let error: any Error

    init(name: String, isRequired: Bool = true, error: any Error) {
        self.name = name
        self.isRequired = isRequired
        self.error = error
    }

    func process(_: inout [TranslationItem]) async throws {
        throw error
    }
}
