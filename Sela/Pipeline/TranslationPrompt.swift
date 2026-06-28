import Foundation

struct TranslationPrompt {
    enum Mode {
        case translate
        case refine
    }

    let mode: Mode
    private let systemPromptOverride: String?

    init(mode: Mode, systemPromptOverride: String? = nil) {
        self.mode = mode
        self.systemPromptOverride = systemPromptOverride
    }

    func systemPrompt(for count: Int) -> String {
        if let override = systemPromptOverride {
            return override
        }
        switch mode {
        case .translate:
            return """
            You are translating English worship songs to Dutch.
            Rules:
            - Use reverent register: "U" (not "jij/je") when addressing God
            - Keep lines singable: similar syllable count to the original English
            - Use common Dutch worship vocabulary
            - Maintain the poetic/lyrical feel
            - Do not add or remove lines
            - Each input line is numbered. Return every translation prefixed with
              the SAME number, e.g. "3. <Dutch translation>"
            - The number maps each translation back to its source line, so keep it
              exact even if you change the order
            - Return exactly \(count) numbered lines, one per input line
            - Return only the number and the Dutch text — no "NL:" prefixes,
              labels, group headers, or other formatting
            """
        case .refine:
            return """
            You are refining Dutch translations of English worship songs.
            Rules:
            - Use reverent register: "U" (not "jij/je") when addressing God
            - Keep lines singable: similar syllable count to the original English
            - Use common Dutch worship vocabulary
            - Maintain the poetic/lyrical feel
            - Do not add or remove lines
            - Each input line is numbered. Return every refined line prefixed with
              the SAME number, e.g. "3. <Dutch translation>"
            - The number maps each line back to its source, so keep it exact even
              if you change the order
            - Return exactly \(count) numbered lines, one per input line
            - Return only the number and the Dutch text — no "NL:" prefixes,
              labels, group headers, or other formatting
            """
        }
    }

    func buildUserPrompt(from items: [TranslationItem]) -> String {
        var lines: [String] = []

        switch mode {
        case .translate:
            lines.append("Translate the following English worship song lines to Dutch.\n")
        case .refine:
            lines.append("Refine the following Dutch translations for use in a worship song.\n")
        }

        var currentGroup: String?
        for (index, item) in items.enumerated() {
            if let group = item.groupName, group != currentGroup {
                lines.append("[\(group)]")
                currentGroup = group
            }
            let number = index + 1
            lines.append("\(number). EN: \(item.sourceText)")
            if mode == .refine {
                lines.append("\(number). NL: \(item.currentText)")
            }
            lines.append("")
        }

        return lines.joined(separator: "\n")
    }
}
