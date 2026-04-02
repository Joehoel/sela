import Foundation
@preconcurrency import Translation

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

    // swiftlint:disable:next cyclomatic_complexity
    static func make(
        engine: TranslationEngine,
        session: (any Sendable)? = nil,
        deeplAPIKey: String = "",
        geminiAPIKey: String = "",
        glossary: [GlossaryEntry] = [],
        refinementEngine: RefinementEngine? = nil
    ) -> TranslationPipeline {
        var pipeline = TranslationPipeline()

        // 1. Primary translator
        switch engine {
        case .apple:
            if #available(macOS 15, *), let session = session as? TranslationSession {
                pipeline.steps.append(AppleTranslationStep(session: session))
            }
        case .googleTranslate:
            pipeline.steps.append(GoogleTranslateStep())
        case .myMemory:
            pipeline.steps.append(MyMemoryTranslationStep())
        case .deepl:
            pipeline.steps.append(DeepLTranslationStep(apiKey: deeplAPIKey))
        case .gemini:
            pipeline.steps.append(GeminiTranslationStep(apiKey: geminiAPIKey))
        case .foundationModel:
            #if canImport(FoundationModels)
                if #available(macOS 26, *) {
                    pipeline.steps.append(FoundationModelStep(mode: .translate, isRequired: true))
                }
            #endif
        }

        // 2. Optional refinement (only when FM is not the primary translator)
        if let refinementEngine, engine != .foundationModel {
            switch refinementEngine {
            case .foundationModel:
                #if canImport(FoundationModels)
                    if #available(macOS 26, *) {
                        pipeline.steps.append(FoundationModelStep(mode: .refine, isRequired: false))
                    }
                #endif
            case .gemini:
                pipeline.steps.append(GeminiTranslationStep(apiKey: geminiAPIKey, mode: .refine))
            }
        }

        // 3. Glossary always runs last
        let activeGlossary = glossary.filter { !$0.replacements.isEmpty }
        if !activeGlossary.isEmpty {
            pipeline.steps.append(GlossaryReplacementStep(entries: activeGlossary))
        }

        return pipeline
    }
}
