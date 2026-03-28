@preconcurrency import Translation

/// Batch-translates items from English to Dutch using Apple's Translation framework.
struct AppleTranslationStep: TranslationPipelineStep {
    let name = "Translating…"
    nonisolated(unsafe) let session: TranslationSession

    func process(_ items: inout [TranslationItem]) async throws {
        let requests = items.map { TranslationSession.Request(sourceText: $0.sourceText) }
        let responses = try await session.translations(from: requests)
        for (index, response) in responses.enumerated() {
            items[index].currentText = response.targetText
        }
    }
}
