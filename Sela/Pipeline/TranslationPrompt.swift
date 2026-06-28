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
            - Translate all \(count) input lines — do not add or remove lines
            - Each input line is labelled "N. EN: ...". Return one entry per line with:
                • number: the SAME source line number (mapping is by number, so order doesn't matter)
                • text: ONLY the Dutch translation — do NOT prefix it with the number,
                  "N.", "NL:", quotes, labels, or any other formatting
            """
        case .refine:
            return """
            You are refining Dutch translations of English worship songs.
            Rules:
            - Use reverent register: "U" (not "jij/je") when addressing God
            - Keep lines singable: similar syllable count to the original English
            - Use common Dutch worship vocabulary
            - Maintain the poetic/lyrical feel
            - Refine all \(count) input lines — do not add or remove lines
            - Each input line is labelled "N. EN/NL: ...". Return one entry per line with:
                • number: the SAME source line number (mapping is by number, so order doesn't matter)
                • text: ONLY the refined Dutch translation — do NOT prefix it with the number,
                  "N.", "NL:", quotes, labels, or any other formatting
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
