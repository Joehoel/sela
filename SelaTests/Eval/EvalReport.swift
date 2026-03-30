import Testing

typealias Scorer = @Sendable (EvalCase, [String]) -> Score

struct EvalReport {
    let fixtureName: String
    let mode: String
    let scores: [Score]

    var average: Double {
        guard !scores.isEmpty else { return 0 }
        return scores.map(\.value).reduce(0, +) / Double(scores.count)
    }

    init(case evalCase: EvalCase, mode: String, output: [String], scorers: [Scorer]) {
        self.fixtureName = evalCase.name
        self.mode = mode
        self.scores = scorers.map { $0(evalCase, output) }
    }

    func printReport() {
        let header = "\(fixtureName) \u{2014} \(mode)"
        let width = max(header.count + 4, 50)
        let border = String(repeating: "\u{2550}", count: width)

        print("\n\u{2554}\(border)\u{2557}")
        print("\u{2551} \(header.padding(toLength: width - 1, withPad: " ", startingAt: 0))\u{2551}")
        print("\u{2560}\(border)\u{2563}")

        for score in scores {
            let icon = score.passed ? "\u{2713}" : "\u{2717}"
            let pct = String(format: "%3.0f%%", score.value * 100)
            let name = score.name.padding(toLength: 22, withPad: " ", startingAt: 0)
            print("\u{2551} \(icon) \(name) \(pct)  \(score.rationale)")
        }

        print("\u{2560}\(border)\u{2563}")
        print("\u{2551} Average: \(String(format: "%.0f%%", average * 100))")
        print("\u{255A}\(border)\u{255D}\n")
    }

    func recordIssues() {
        for score in scores where !score.passed {
            Issue.record(
                Comment(
                    rawValue: "[\(fixtureName)] \(score.name) (\(String(format: "%.0f%%", score.value * 100))): \(score.rationale)"
                )
            )
        }
    }
}
