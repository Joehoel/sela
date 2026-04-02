import Foundation
@testable import Sela
import Testing

#if canImport(FoundationModels)
    import FoundationModels

    extension Tag {
        @Tag static var eval: Self
    }

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

            let prompt = TranslationPrompt(mode: .translate)
            let output = try await callFM(prompt: prompt, items: evalCase.makeItems())

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

            // First translate, then refine
            let translatePrompt = TranslationPrompt(mode: .translate)
            let rawOutput = try await callFM(prompt: translatePrompt, items: evalCase.makeItems())

            var items = evalCase.makeItems()
            for i in items.indices where i < rawOutput.count {
                items[i].currentText = rawOutput[i]
            }

            let refined: [String]
            do {
                let refinePrompt = TranslationPrompt(mode: .refine)
                refined = try await callFM(prompt: refinePrompt, items: items)
            } catch {
                Issue.record("FM refused to refine \(evalCase.name): \(error)")
                // Score the raw translation instead so we still get a report
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

        // MARK: - FM caller

        @available(macOS 26, *)
        private func callFM(prompt: TranslationPrompt, items: [TranslationItem]) async throws -> [String] {
            let systemPrompt = prompt.systemPrompt(for: items.count)
            let session = LanguageModelSession { systemPrompt }
            let userPrompt = prompt.buildUserPrompt(from: items)

            let response = try await session.respond(
                to: userPrompt,
                generating: TranslationLines.self
            )
            return response.content.lines
        }
    }
#endif
