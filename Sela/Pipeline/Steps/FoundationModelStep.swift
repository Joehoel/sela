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

        var name: String {
            switch mode {
            case .translate: "Translating…"
            case .refine: "Refining…"
            }
        }

        func process(_ items: inout [TranslationItem]) async throws {
            let session = LanguageModelSession {
                systemPrompt(for: items.count)
            }

            let prompt = buildPrompt(from: items)

            // Extract just the [String] lines inside the Task to avoid Sendable issues
            let respondTask = Task<[String], Error> {
                let response = try await session.respond(
                    to: prompt,
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

        private func systemPrompt(for count: Int) -> String {
            switch mode {
            case .translate:
                """
                You are translating English worship songs to Dutch.
                Rules:
                - Use reverent register: "U" (not "jij/je") when addressing God
                - Keep lines singable: similar syllable count to the original English
                - Use common Dutch worship vocabulary
                - Maintain the poetic/lyrical feel
                - Do not add or remove lines
                - Return exactly \(count) lines in the same order
                """
            case .refine:
                """
                You are refining Dutch translations of English worship songs.
                Rules:
                - Use reverent register: "U" (not "jij/je") when addressing God
                - Keep lines singable: similar syllable count to the original English
                - Use common Dutch worship vocabulary
                - Maintain the poetic/lyrical feel
                - Do not add or remove lines
                - Return exactly \(count) lines in the same order
                """
            }
        }

        private func buildPrompt(from items: [TranslationItem]) -> String {
            var lines: [String] = []

            switch mode {
            case .translate:
                lines.append("Translate the following English worship song lines to Dutch.\n")
            case .refine:
                lines.append("Refine the following Dutch translations for use in a worship song.\n")
            }

            var currentGroup: String?
            for item in items {
                if let group = item.groupName, group != currentGroup {
                    lines.append("[\(group)]")
                    currentGroup = group
                }
                lines.append("EN: \(item.sourceText)")
                if mode == .refine {
                    lines.append("NL: \(item.currentText)")
                }
                lines.append("")
            }

            return lines.joined(separator: "\n")
        }
    }
#endif
