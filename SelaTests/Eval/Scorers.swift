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
        let ok = ratio >= 0.6 && ratio <= 1.4
        if ok { passCount += 1 }
        details.append("L\(index + 1): \(enSyl)\u{2192}\(nlSyl) (\(Int(ratio * 100))%)\(ok ? "" : " OVER")")
    }

    let value = Double(passCount) / Double(evalCase.english.count)
    let passed = value >= 0.75
    return Score(name: "Syllable similarity", value: value, passed: passed, rationale: details.joined(separator: ", "))
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

func worshipVocabulary(_ evalCase: EvalCase, _ output: [String]) -> Score {
    let expectedTerms: [(english: String, dutch: [String])] = [
        ("lord", ["heer", "here"]),
        ("grace", ["genade"]),
        ("soul", ["ziel"]),
        ("praise", ["prijs", "lofprijs", "lof"]),
        ("worship", ["aanbid", "aanbidding", "prijs"]),
        ("holy", ["heilig", "heilige"]),
        ("mercy", ["barmhartig", "genade"]),
        ("salvation", ["verlossing", "redding", "heil"]),
        ("heaven", ["hemel"]),
        ("god", ["god"]),
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

// MARK: - Reference similarity (Jaccard)

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
        let outWords = Set(out.lowercased().split(separator: " ").map(String.init))
        let refWords = Set(ref.lowercased().split(separator: " ").map(String.init))
        let intersection = outWords.intersection(refWords).count
        let union = outWords.union(refWords).count
        let jaccard = union > 0 ? Double(intersection) / Double(union) : 0.0
        totalScore += jaccard
        details.append("L\(index + 1): \(Int(jaccard * 100))%")
    }

    let avg = totalScore / Double(reference.count)
    let passed = avg >= 0.3
    return Score(name: "Reference similarity", value: avg, passed: passed, rationale: details.joined(separator: ", "))
}
