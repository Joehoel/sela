import Foundation
#if canImport(FoundationModels)
    import FoundationModels
#endif

#if canImport(FoundationModels)
    @available(macOS 26, *)
    @Generable
    struct TranslationLines {
        @Guide(description: "Dutch worship translations, one per input line, same order")
        var lines: [String]
    }

    @available(macOS 26, *)
    struct FoundationModelStep: TranslationPipelineStep {
        enum Mode {
            case translate
            case refine
        }

        let mode: Mode
        let isRequired: Bool
        static let timeout: Duration = .seconds(60)

        private var prompt: TranslationPrompt {
            TranslationPrompt(mode: mode == .translate ? .translate : .refine)
        }

        var name: String {
            switch mode {
            case .translate: "Translating…"
            case .refine: "Refining…"
            }
        }

        func process(_ items: inout [TranslationItem]) async throws {
            let systemPrompt = prompt.systemPrompt(for: items.count)
            let session = LanguageModelSession {
                systemPrompt
            }

            let userPrompt = prompt.buildUserPrompt(from: items)

            // Extract just the [String] lines inside the Task to avoid Sendable issues
            let respondTask = Task<[String], Error> {
                let response = try await session.respond(
                    to: userPrompt,
                    generating: TranslationLines.self
                )
                return response.content.lines
            }

            let timeoutTask = Task {
                try? await Task.sleep(for: Self.timeout)
                respondTask.cancel()
            }

            let output: [String]
            do {
                output = try await respondTask.value
                timeoutTask.cancel()
            } catch {
                timeoutTask.cancel()
                if isRequired { throw error }
                return
            }

            for index in items.indices where index < output.count {
                items[index].currentText = output[index]
            }
        }
    }
#endif
