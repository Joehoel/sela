import Foundation

/// Maps an LLM step's raw text output back onto the pipeline items.
///
/// The prompt asks the model to prefix every line with its 1-based number
/// ("3. <Dutch>"). We map each returned line back to its item *by that number*,
/// so the model reordering lines, echoing a group header, or emitting a blank
/// line can never misassign a translation to the wrong source line.
enum TranslationResponseMapper {
    static func apply(_ responseText: String, to items: inout [TranslationItem]) {
        let numbered = parseNumberedLines(responseText)

        if !numbered.isEmpty {
            for (number, text) in numbered where (1 ... items.count).contains(number) {
                items[number - 1].currentText = text
            }
            return
        }

        // Fallback for models that ignore the numbering instruction: assign the
        // i-th non-empty output line to the i-th item (legacy, positional).
        let lines = responseText
            .components(separatedBy: "\n")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }

        for index in items.indices where index < lines.count {
            items[index].currentText = lines[index]
        }
    }

    /// Parses lines shaped like `"<n>. text"`, `"<n>) text"`, `"<n>: text"`, or
    /// `"<n> - text"`. Lines without a leading number (headers, blanks,
    /// preamble) are skipped. The first occurrence of each number wins.
    private static func parseNumberedLines(_ text: String) -> [(number: Int, text: String)] {
        var result: [(Int, String)] = []
        var seen = Set<Int>()

        for rawLine in text.components(separatedBy: "\n") {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            guard let parsed = parseNumberedLine(line), !seen.contains(parsed.number) else {
                continue
            }
            seen.insert(parsed.number)
            result.append(parsed)
        }

        return result
    }

    private static func parseNumberedLine(_ line: String) -> (number: Int, text: String)? {
        var index = line.startIndex
        var digits = ""
        while index < line.endIndex, line[index].isNumber {
            digits.append(line[index])
            index = line.index(after: index)
        }
        guard let number = Int(digits), index < line.endIndex else { return nil }

        let separator = line[index]
        guard separator == "." || separator == ")" || separator == ":" || separator == "-" else {
            return nil
        }

        let text = line[line.index(after: index)...].trimmingCharacters(in: .whitespaces)
        guard !text.isEmpty else { return nil }
        return (number, text)
    }
}
