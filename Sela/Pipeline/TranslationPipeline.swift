import Foundation

/// A single step in the translation pipeline.
protocol TranslationPipelineStep {
    var name: String { get }
    var isRequired: Bool { get }
    func process(_ items: inout [TranslationItem]) async throws
}

extension TranslationPipelineStep {
    var isRequired: Bool {
        true
    }
}

/// Runs an ordered sequence of translation steps.
struct TranslationPipeline {
    var steps: [any TranslationPipelineStep & Sendable] = []

    func run(
        _ items: inout [TranslationItem],
        onStatus: (@Sendable (String) -> Void)? = nil
    ) async throws {
        for step in steps {
            onStatus?(step.name)
            if step.isRequired {
                try await step.process(&items)
            } else {
                try? await step.process(&items)
            }
        }
    }

    // swiftlint:disable:next cyclomatic_complexity function_body_length
    static func make(
        engine: TranslationEngine,
        deeplAPIKey: String = "",
        geminiAPIKey: String = "",
        openAIAPIKey: String = "",
        anthropicAPIKey: String = "",
        glossary: [GlossaryEntry] = [],
        refinementEngine: RefinementEngine? = nil,
        translationModel: AIModel? = nil,
        refinementModel: AIModel? = nil
    ) -> TranslationPipeline {
        var pipeline = TranslationPipeline()

        // 1. Primary translator
        switch engine {
        case .apple:
            pipeline.steps.append(makeAISDKStep(
                engine: .apple, apiKey: "", modelID: "", mode: .translate
            ))
        case .googleTranslate:
            pipeline.steps.append(makeAISDKStep(
                engine: .googleTranslate, apiKey: "", modelID: "", mode: .translate
            ))
        case .myMemory:
            pipeline.steps.append(makeAISDKStep(
                engine: .myMemory, apiKey: "", modelID: "", mode: .translate
            ))
        case .deepl:
            // No explicit model selection → empty id → DeepL account default
            // model_type (don't force latency_optimized).
            pipeline.steps.append(makeAISDKStep(
                engine: .deepl,
                apiKey: deeplAPIKey,
                modelID: translationModel?.id ?? "",
                mode: .translate
            ))
        case .gemini:
            pipeline.steps.append(makeAISDKStep(
                engine: .gemini,
                apiKey: geminiAPIKey,
                modelID: translationModel?.id ?? TranslationEngine.gemini.defaultModel?.id ?? "gemini-2.5-flash",
                mode: .translate
            ))
        case .openAI:
            pipeline.steps.append(makeAISDKStep(
                engine: .openAI,
                apiKey: openAIAPIKey,
                modelID: translationModel?.id ?? TranslationEngine.openAI.defaultModel?.id ?? "gpt-5-mini",
                mode: .translate
            ))
        case .anthropic:
            pipeline.steps.append(makeAISDKStep(
                engine: .anthropic,
                apiKey: anthropicAPIKey,
                modelID: translationModel?.id ?? TranslationEngine.anthropic.defaultModel?.id ?? "claude-sonnet-4-6",
                mode: .translate
            ))
        case .foundationModel:
            pipeline.steps.append(makeAISDKStep(
                engine: .foundationModel, apiKey: "", modelID: "", mode: .translate
            ))
        }

        // 2. Optional refinement (only when FM is not the primary translator)
        if let refinementEngine, engine != .foundationModel {
            switch refinementEngine {
            case .foundationModel:
                pipeline.steps.append(makeAISDKStep(
                    engine: .foundationModel, apiKey: "", modelID: "", mode: .refine
                ))
            case .gemini:
                pipeline.steps.append(makeAISDKStep(
                    engine: .gemini,
                    apiKey: geminiAPIKey,
                    modelID: refinementModel?.id ?? RefinementEngine.gemini.defaultModel?.id ?? "gemini-2.5-flash",
                    mode: .refine
                ))
            }
        }

        // 3. Glossary always runs last
        let activeGlossary = glossary.filter { !$0.replacements.isEmpty }
        if !activeGlossary.isEmpty {
            pipeline.steps.append(GlossaryReplacementStep(entries: activeGlossary))
        }

        return pipeline
    }

    /// Resolves a `LanguageModelV3` for an LLM engine and wraps it in an
    /// `AISDKTranslationStep`. If resolution fails (missing key, unsupported
    /// engine), returns a `FailingTranslationStep` so the error surfaces at
    /// pipeline-run time — mirroring the old steps' deferred missing-key error.
    static func makeAISDKStep(
        engine: TranslationEngine,
        apiKey: String,
        modelID: String,
        mode: TranslationPrompt.Mode
    ) -> any TranslationPipelineStep & Sendable {
        // Refinement is best-effort: a failed second pass must not discard a good
        // primary translation, so refine steps are not required.
        let required = mode == .translate
        do {
            let model = try AISDKModelResolver.model(for: engine, apiKey: apiKey, modelID: modelID)
            return AISDKTranslationStep(
                model: model,
                mode: mode,
                isRequired: required,
                temperature: AISDKTranslationStep.temperature(for: engine),
                providerOptions: AISDKTranslationStep.providerOptions(for: engine, modelID: modelID)
            )
        } catch {
            let name = mode == .translate ? "Translating…" : "Refining…"
            return FailingTranslationStep(name: name, isRequired: required, error: error)
        }
    }
}
