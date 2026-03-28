import Foundation

/// Corrects translation engine output using the user's glossary.
/// Replaces known wrong Dutch words with the preferred term, respecting word boundaries.
struct GlossaryReplacementStep: TranslationPipelineStep {
    let name = "Applying glossary…"
    let entries: [GlossaryEntry]

    func process(_ items: inout [TranslationItem]) async throws {
        let activeEntries = entries.filter { !$0.replacements.isEmpty }
        guard !activeEntries.isEmpty else { return }

        for i in items.indices {
            for entry in activeEntries {
                for replacement in entry.replacements {
                    items[i].currentText = items[i].currentText
                        .replacingWordOccurrences(of: replacement, with: entry.target)
                }
            }
        }
    }
}

extension String {
    /// Replaces whole-word occurrences of `target` with `replacement`, case-insensitive.
    func replacingWordOccurrences(of target: String, with replacement: String) -> String {
        let pattern = "\\b\(NSRegularExpression.escapedPattern(for: target))\\b"
        guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) else {
            return self
        }
        return regex.stringByReplacingMatches(
            in: self,
            range: NSRange(startIndex..., in: self),
            withTemplate: NSRegularExpression.escapedTemplate(for: replacement)
        )
    }
}
