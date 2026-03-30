import Foundation
#if canImport(FoundationModels)
    import FoundationModels
#endif

#if canImport(FoundationModels)
    @available(macOS 26, *)
    @Generable
    struct TranslationLines {
        @Guide(description: "Refined Dutch worship translations, one per input line, same order")
        var lines: [String]
    }

    /// Refines literal Dutch translations using the on-device foundation model for worship voice.
    @available(macOS 26, *)
    struct FoundationModelRefinementStep: TranslationPipelineStep {
        let name = "Refining…"

        func process(_ items: inout [TranslationItem]) async throws {
            let session = LanguageModelSession {
                """
                You are refining Dutch translations of English worship songs.
                Rules:
                - Use reverent register: "U" (not "jij/je") when addressing God
                - Keep lines singable: similar syllable count to the original English
                - Use common Dutch worship vocabulary
                - Maintain the poetic/lyrical feel
                - Do not add or remove lines
                - Return exactly \(items.count) lines in the same order
                """
            }

            let prompt = buildPrompt(from: items)

            let response: LanguageModelSession.Response<TranslationLines>
            do {
                response = try await session.respond(
                    to: prompt,
                    generating: TranslationLines.self
                )
            } catch {
                return
            }

            let refined = response.content.lines

            // Apply refined lines where available; keep originals for any extras/missing
            for index in items.indices where index < refined.count {
                items[index].currentText = refined[index]
            }
        }

        private func buildPrompt(from items: [TranslationItem]) -> String {
            var lines: [String] = []
            lines.append("Refine the following Dutch translations for use in a worship song.\n")

            var currentGroup: String?
            for item in items {
                if let group = item.groupName, group != currentGroup {
                    lines.append("[\(group)]")
                    currentGroup = group
                }
                lines.append("EN: \(item.sourceText)")
                lines.append("NL: \(item.currentText)")
                lines.append("")
            }

            return lines.joined(separator: "\n")
        }
    }
#endif
