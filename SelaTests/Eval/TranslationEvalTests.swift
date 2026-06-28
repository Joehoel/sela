import Foundation
@testable import Sela
import Testing

#if canImport(FoundationModels)
    import FoundationModels

    extension Tag {
        @Tag static var eval: Self
    }

    /// Drives Apple Intelligence (on-device FoundationModels) through the unified
    /// `AISDKTranslationStep` — the same path the app uses — and scores the output.
    /// Requires an Apple-Intelligence-capable host; skipped otherwise.
    @Suite(.tags(.eval))
    struct TranslationEvalTests {
        static let cases = EvalCase.loadAll()

        static let scorers: [Scorer] = [
            lineCount,
            reverentRegister,
            syllableSimilarity,
            worshipVocabulary,
            referenceSimilarity,
        ]

        @Test("FM translate", arguments: cases)
        func translate(_ evalCase: EvalCase) async throws {
            guard #available(macOS 26, *) else { return }

            let output = try await runFM(mode: .translate, items: evalCase.makeItems())

            let report = EvalReport(case: evalCase, mode: "translate", output: output, scorers: Self.scorers)
            report.printReport()
            report.recordIssues()

            #expect(
                report.average >= 0.7,
                "Overall score \(String(format: "%.0f%%", report.average * 100)) below 70% threshold"
            )
        }

        @Test("FM refine", arguments: cases)
        func refine(_ evalCase: EvalCase) async throws {
            guard #available(macOS 26, *) else { return }

            // First translate, then refine the same items.
            var items = evalCase.makeItems()
            let rawOutput = try await runFM(mode: .translate, items: items)
            for i in items.indices where i < rawOutput.count {
                items[i].currentText = rawOutput[i]
            }

            let refined: [String]
            do {
                refined = try await runFM(mode: .refine, items: items)
            } catch {
                Issue.record("FM refused to refine \(evalCase.name): \(error)")
                let report = EvalReport(
                    case: evalCase, mode: "refine (raw, FM refused)", output: rawOutput, scorers: Self.scorers
                )
                report.printReport()
                return
            }

            let report = EvalReport(case: evalCase, mode: "refine", output: refined, scorers: Self.scorers)
            report.printReport()
            report.recordIssues()

            #expect(
                report.average >= 0.7,
                "Overall score \(String(format: "%.0f%%", report.average * 100)) below 70% threshold"
            )
        }

        // MARK: - FM caller (through the unified step)

        @available(macOS 26, *)
        private func runFM(mode: TranslationPrompt.Mode, items: [TranslationItem]) async throws -> [String] {
            var items = items
            let step = AISDKTranslationStep(model: FoundationModelLanguageModel(), mode: mode)
            try await step.process(&items)
            return items.map(\.currentText)
        }
    }
#endif
