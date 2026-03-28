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

    static func `default`(session: TranslationSession) -> TranslationPipeline {
        var pipeline = TranslationPipeline()
        pipeline.steps.append(AppleTranslationStep(session: session))
        if #available(macOS 26, *) {
            pipeline.steps.append(FoundationModelRefinementStep())
        }
        return pipeline
    }
}
