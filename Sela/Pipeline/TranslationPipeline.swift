import Foundation
@preconcurrency import Translation

/// A single step in the translation pipeline.
protocol TranslationPipelineStep {
    var name: String { get }
    func process(_ items: inout [TranslationItem]) async throws
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
            try await step.process(&items)
        }
    }

    static func make(
        engine: TranslationEngine,
        session: TranslationSession? = nil,
        deeplAPIKey: String = "",
        glossary: [GlossaryEntry] = []
    ) -> TranslationPipeline {
        var pipeline = TranslationPipeline()

        switch engine {
        case .apple:
            if let session {
                pipeline.steps.append(AppleTranslationStep(session: session))
            }
        case .deepl:
            pipeline.steps.append(DeepLTranslationStep(apiKey: deeplAPIKey))
        }

        let activeGlossary = glossary.filter { !$0.replacements.isEmpty }
        if !activeGlossary.isEmpty {
            pipeline.steps.append(GlossaryReplacementStep(entries: activeGlossary))
        }

        #if canImport(FoundationModels)
            if #available(macOS 26, *) {
                pipeline.steps.append(FoundationModelRefinementStep())
            }
        #endif

        return pipeline
    }
}
