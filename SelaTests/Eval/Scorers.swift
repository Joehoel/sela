import Foundation

struct Score {
    let name: String
    let value: Double
    let passed: Bool
    let rationale: String

    static func pass(_ name: String, value: Double = 1.0, rationale: String = "") -> Score {
        Score(name: name, value: value, passed: true, rationale: rationale)
    }

    static func fail(_ name: String, value: Double = 0.0, rationale: String) -> Score {
        Score(name: name, value: value, passed: false, rationale: rationale)
    }
}

// MARK: - Line count

func lineCount(_ evalCase: EvalCase, _ output: [String]) -> Score {
    if evalCase.english.count == output.count {
        return .pass("Line count", rationale: "\(output.count) lines")
    }
    return .fail("Line count", rationale: "expected \(evalCase.english.count), got \(output.count)")
}

// MARK: - Reverent register

/// Checks that informal Dutch pronouns (jij/je/jouw/jou) are not used.
/// Worship songs addressing God should use "U"/"Uw".
func reverentRegister(_: EvalCase, _ output: [String]) -> Score {
    let informalPatterns = [
        ("\\bjij\\b", "jij"),
        ("\\bje\\b", "je"),
        ("\\bjouw\\b", "jouw"),
        ("\\bjou\\b", "jou"),
    ]

    var violations: [String] = []
    for (index, line) in output.enumerated() {
        for (pattern, label) in informalPatterns {
            if let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) {
                let range = NSRange(line.startIndex..., in: line)
                if regex.firstMatch(in: line, range: range) != nil {
                    violations.append("L\(index + 1): \"\(label)\"")
                }
            }
        }
    }

    if violations.isEmpty {
        return .pass("Reverent register", rationale: "no informal pronouns")
    }
    let score = max(0, 1.0 - Double(violations.count) / Double(output.count))
    return .fail("Reverent register", value: score, rationale: violations.joined(separator: ", "))
}

// MARK: - Syllable similarity

/// Compares syllable counts between English and Dutch to check singability.
/// Uses a per-line ratio with a tolerance band, then checks what fraction of
/// lines fall within range. The reference translations themselves often diverge
/// by 20-50%, so we use a generous 0.5x–1.6x band.
func syllableSimilarity(_ evalCase: EvalCase, _ output: [String]) -> Score {
    guard evalCase.english.count == output.count else {
        return .fail("Syllable similarity", rationale: "line count mismatch")
    }

    var details: [String] = []
    var passCount = 0

    for (index, (en, nl)) in zip(evalCase.english, output).enumerated() {
        let enSyl = estimateSyllables(en)
        let nlSyl = estimateSyllables(nl)
        let ratio = enSyl > 0 ? Double(nlSyl) / Double(enSyl) : 1.0
        let ok = ratio >= 0.5 && ratio <= 1.6
        if ok { passCount += 1 }
        let flag = ok ? "" : " OVER"
        details.append("L\(index + 1): \(enSyl)\u{2192}\(nlSyl) (\(Int(ratio * 100))%)\(flag)")
    }

    let value = Double(passCount) / Double(evalCase.english.count)
    let passed = value >= 0.75
    return Score(
        name: "Syllable similarity",
        value: value,
        passed: passed,
        rationale: details.joined(separator: ", ")
    )
}

private func estimateSyllables(_ text: String) -> Int {
    let vowels = CharacterSet(charactersIn: "aeiouAEIOUáéíóúàèìòùäëïöüâêîôû")
    var count = 0
    var inVowel = false
    for scalar in text.unicodeScalars {
        if vowels.contains(scalar) {
            if !inVowel { count += 1; inVowel = true }
        } else {
            inVowel = false
        }
    }
    return max(count, 1)
}

// MARK: - Worship vocabulary

/// Checks that key worship terms in the English source appear as their
/// Dutch equivalents in the output. Expanded term list based on real
/// test case content.
func worshipVocabulary(_ evalCase: EvalCase, _ output: [String]) -> Score {
    let expectedTerms: [(english: String, dutch: [String])] = [
        ("lord", ["heer", "here"]),
        ("grace", ["genade"]),
        ("soul", ["ziel"]),
        ("praise", ["prijs", "lofprijs", "lof", "loof"]),
        ("worship", ["aanbid", "aanbidding", "prijs", "verheerlijk"]),
        ("holy", ["heilig", "heilige"]),
        ("mercy", ["barmhartig", "genade"]),
        ("salvation", ["verlossing", "redding", "heil"]),
        ("heaven", ["hemel"]),
        ("god", ["god"]),
        ("sing", ["zing"]),
        ("love", ["lief", "liefde", "hou van"]),
        ("faithful", ["trouw", "getrouw"]),
        ("light", ["licht"]),
        ("heart", ["hart"]),
        ("name", ["naam"]),
        ("free", ["vrij"]),
        ("child", ["kind"]),
        ("chosen", ["gekozen", "uitverkoren"]),
    ]

    let enJoined = evalCase.english.joined(separator: " ").lowercased()
    let nlJoined = output.joined(separator: " ").lowercased()

    var checked = 0
    var found = 0
    var missing: [String] = []

    for term in expectedTerms {
        guard enJoined.contains(term.english) else { continue }
        checked += 1
        if term.dutch.contains(where: { nlJoined.contains($0) }) {
            found += 1
        } else {
            missing.append("\"\(term.english)\" missing")
        }
    }

    guard checked > 0 else {
        return .pass("Worship vocabulary", rationale: "no terms to check")
    }

    let value = Double(found) / Double(checked)
    let passed = value >= 0.5
    let rationale = missing.isEmpty
        ? "\(checked)/\(checked) found"
        : "\(found)/\(checked) found; \(missing.joined(separator: ", "))"
    return Score(name: "Worship vocabulary", value: value, passed: passed, rationale: rationale)
}

// MARK: - Reference similarity (character n-gram)

/// Compares output against a gold-standard reference translation using
/// character trigram overlap (Dice coefficient). This is much more forgiving
/// than word-level Jaccard for creative translations where word choice differs
/// but the text is still semantically close (e.g. "genade" vs "genade Gods").
func referenceSimilarity(_ evalCase: EvalCase, _ output: [String]) -> Score {
    guard let reference = evalCase.referenceDutch, !reference.isEmpty else {
        return .pass("Reference similarity", rationale: "skipped (no reference)")
    }
    guard output.count == reference.count else {
        return .fail("Reference similarity", rationale: "line count mismatch with reference")
    }

    var totalScore = 0.0
    var details: [String] = []

    for (index, (out, ref)) in zip(output, reference).enumerated() {
        let similarity = trigramSimilarity(out.lowercased(), ref.lowercased())
        totalScore += similarity
        details.append("L\(index + 1): \(Int(similarity * 100))%")
    }

    let avg = totalScore / Double(reference.count)
    let passed = avg >= 0.25
    return Score(
        name: "Reference similarity",
        value: avg,
        passed: passed,
        rationale: details.joined(separator: ", ")
    )
}

/// Dice coefficient on character trigrams — more robust than word-level
/// Jaccard for comparing translations with different word boundaries.
private func trigramSimilarity(_ lhs: String, _ rhs: String) -> Double {
    let trigramsA = characterTrigrams(lhs)
    let trigramsB = characterTrigrams(rhs)
    guard !trigramsA.isEmpty, !trigramsB.isEmpty else { return 0 }
    let intersection = trigramsA.intersection(trigramsB).count
    return 2.0 * Double(intersection) / Double(trigramsA.count + trigramsB.count)
}

private func characterTrigrams(_ text: String) -> Set<String> {
    let chars = Array(text)
    guard chars.count >= 3 else { return Set([text]) }
    var trigrams = Set<String>()
    for i in 0 ..< (chars.count - 2) {
        trigrams.insert(String(chars[i ... i + 2]))
    }
    return trigrams
}
