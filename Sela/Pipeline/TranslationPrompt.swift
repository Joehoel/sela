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
            - Return exactly \(count) lines in the same order
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
            - Return exactly \(count) lines in the same order
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
