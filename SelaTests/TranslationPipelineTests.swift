import Foundation
@testable import Sela
import Testing

struct TranslationPipelineTests {
    // MARK: - Mock step

    struct MockStep: TranslationPipelineStep {
        let name: String
        let transform: @Sendable (inout [TranslationItem]) -> Void

        func process(_ items: inout [TranslationItem]) async throws {
            transform(&items)
        }
    }

    struct FailingStep: TranslationPipelineStep {
        let name = "Failing"

        func process(_: inout [TranslationItem]) async throws {
            throw TestError.intentional
        }
    }

    struct OptionalFailingStep: TranslationPipelineStep {
        let name = "Optional Failing"
        let isRequired = false

        func process(_: inout [TranslationItem]) async throws {
            throw TestError.intentional
        }
    }

    enum TestError: Error {
        case intentional
    }

    // MARK: - Pipeline tests

    @Test("empty pipeline is a no-op")
    func emptyPipeline() async throws {
        let pipeline = TranslationPipeline()
        var items = [
            TranslationItem(sourceText: "Hello", lineID: "1"),
        ]
        try await pipeline.run(&items)
        #expect(items[0].currentText == "Hello")
    }

    @Test("pipeline runs steps in order")
    func stepsRunInOrder() async throws {
        var pipeline = TranslationPipeline()
        pipeline.steps.append(MockStep(name: "Step A") { items in
            for i in items.indices {
                items[i].currentText += " A"
            }
        })
        pipeline.steps.append(MockStep(name: "Step B") { items in
            for i in items.indices {
                items[i].currentText += " B"
            }
        })

        var items = [TranslationItem(sourceText: "Start", lineID: "1")]
        try await pipeline.run(&items)
        #expect(items[0].currentText == "Start A B")
    }

    @Test("onStatus callback fires for each step")
    func onStatusCallback() async throws {
        var pipeline = TranslationPipeline()
        pipeline.steps.append(MockStep(name: "Translating…") { _ in })
        pipeline.steps.append(MockStep(name: "Refining…") { _ in })

        let statuses = LockIsolated<[String]>([])
        var items: [TranslationItem] = [TranslationItem(sourceText: "Test", lineID: "1")]
        try await pipeline.run(&items) { status in
            statuses.withValue { $0.append(status) }
        }
        #expect(statuses.value == ["Translating…", "Refining…"])
    }

    @Test("pipeline propagates errors")
    func pipelineError() async throws {
        var pipeline = TranslationPipeline()
        pipeline.steps.append(FailingStep())

        var items = [TranslationItem(sourceText: "Test", lineID: "1")]
        await #expect(throws: TestError.self) {
            try await pipeline.run(&items)
        }
    }

    @Test("optional step failure does not propagate")
    func optionalStepFailure() async throws {
        var pipeline = TranslationPipeline()
        pipeline.steps.append(MockStep(name: "Translate") { items in
            for i in items.indices {
                items[i].currentText = "Translated"
            }
        })
        pipeline.steps.append(OptionalFailingStep())
        pipeline.steps.append(MockStep(name: "Glossary") { items in
            for i in items.indices {
                items[i].currentText += " (glossary)"
            }
        })

        var items = [TranslationItem(sourceText: "Hello", lineID: "1")]
        try await pipeline.run(&items)
        #expect(items[0].currentText == "Translated (glossary)")
    }

    @Test("required step failure stops pipeline")
    func requiredStepFailure() async throws {
        var pipeline = TranslationPipeline()
        pipeline.steps.append(FailingStep())
        pipeline.steps.append(MockStep(name: "Never reached") { items in
            for i in items.indices {
                items[i].currentText = "Should not happen"
            }
        })

        var items = [TranslationItem(sourceText: "Hello", lineID: "1")]
        await #expect(throws: TestError.self) {
            try await pipeline.run(&items)
        }
        #expect(items[0].currentText == "Hello")
    }

    @Test("step transforms carry through pipeline")
    func transformCarryThrough() async throws {
        var pipeline = TranslationPipeline()
        pipeline.steps.append(MockStep(name: "Uppercase") { items in
            for i in items.indices {
                items[i].currentText = items[i].currentText.uppercased()
            }
        })
        pipeline.steps.append(MockStep(name: "Append") { items in
            for i in items.indices {
                items[i].currentText += "!"
            }
        })

        var items = [
            TranslationItem(sourceText: "hello", lineID: "1"),
            TranslationItem(sourceText: "world", lineID: "2"),
        ]
        try await pipeline.run(&items)
        #expect(items[0].currentText == "HELLO!")
        #expect(items[1].currentText == "WORLD!")
    }

    // MARK: - make() routing

    @Test("Gemini routes through the unified AISDK step")
    func geminiRoutesThroughAISDKStep() {
        let pipeline = TranslationPipeline.make(
            engine: .gemini,
            geminiAPIKey: "AIzaTESTKEY",
            translationModel: AIModel(id: "gemini-2.5-flash", displayName: "Gemini 2.5 Flash")
        )
        let aisdkSteps = pipeline.steps.compactMap { $0 as? AISDKTranslationStep }
        #expect(aisdkSteps.count == 1)
        #expect(aisdkSteps.first?.mode == .translate)
    }

    @Test("Gemini refinement routes through the unified AISDK step")
    func geminiRefinementRoutesThroughAISDKStep() {
        let pipeline = TranslationPipeline.make(
            engine: .deepl,
            deeplAPIKey: "deepl-key",
            geminiAPIKey: "AIzaTESTKEY",
            refinementEngine: .gemini,
            translationModel: AIModel(id: "latency_optimized", displayName: "Latency optimized"),
            refinementModel: AIModel(id: "gemini-2.5-flash", displayName: "Gemini 2.5 Flash")
        )
        // Primary (DeepL) + refinement (Gemini) both run through the unified step;
        // no legacy per-engine step remains.
        let aisdkSteps = pipeline.steps.filter { $0 is AISDKTranslationStep }
        #expect(aisdkSteps.count == 2)
        let refine = aisdkSteps.compactMap { $0 as? AISDKTranslationStep }.first { $0.mode == .refine }
        #expect(refine != nil)
    }

    @Test("Gemini without a key yields a deferred-failing step, not the old step")
    func geminiMissingKeyDefersError() async {
        let pipeline = TranslationPipeline.make(engine: .gemini, geminiAPIKey: "")
        #expect(pipeline.steps.contains { $0 is FailingTranslationStep })

        var items = [TranslationItem(sourceText: "Hello", lineID: "1")]
        await #expect(throws: AISDKModelError.self) {
            try await pipeline.run(&items)
        }
    }

    @Test("DeepL routes through the unified AISDK step")
    func deepLRoutesThroughAISDKStep() {
        let pipeline = TranslationPipeline.make(
            engine: .deepl,
            deeplAPIKey: "deepl-key",
            translationModel: AIModel(id: "latency_optimized", displayName: "Latency optimized")
        )
        #expect(pipeline.steps.contains { $0 is AISDKTranslationStep })
    }

    @Test("DeepL without a key yields a deferred-failing step")
    func deepLMissingKeyDefersError() async {
        let pipeline = TranslationPipeline.make(engine: .deepl, deeplAPIKey: "")
        #expect(pipeline.steps.contains { $0 is FailingTranslationStep })

        var items = [TranslationItem(sourceText: "Hello", lineID: "1")]
        await #expect(throws: DeepLError.self) {
            try await pipeline.run(&items)
        }
    }

    @Test("Google Translate routes through the unified AISDK step, key-free")
    func googleTranslateRoutesThroughAISDKStep() {
        let pipeline = TranslationPipeline.make(engine: .googleTranslate)
        #expect(pipeline.steps.contains { $0 is AISDKTranslationStep })
        #expect(!pipeline.steps.contains { $0 is FailingTranslationStep })
    }

    @Test("MyMemory routes through the unified AISDK step, key-free")
    func myMemoryRoutesThroughAISDKStep() {
        let pipeline = TranslationPipeline.make(engine: .myMemory)
        #expect(pipeline.steps.contains { $0 is AISDKTranslationStep })
        #expect(!pipeline.steps.contains { $0 is FailingTranslationStep })
    }

    @Test("OpenAI routes through the unified AISDK step")
    func openAIRoutesThroughAISDKStep() {
        let pipeline = TranslationPipeline.make(
            engine: .openAI,
            openAIAPIKey: "sk-TESTKEY",
            translationModel: AIModel(id: "gpt-5-mini", displayName: "GPT-5 mini")
        )
        #expect(pipeline.steps.contains { $0 is AISDKTranslationStep })
    }

    @Test("Anthropic routes through the unified AISDK step")
    func anthropicRoutesThroughAISDKStep() {
        let pipeline = TranslationPipeline.make(
            engine: .anthropic,
            anthropicAPIKey: "sk-ant-TESTKEY",
            translationModel: AIModel(id: "claude-sonnet-4-6", displayName: "Claude Sonnet")
        )
        #expect(pipeline.steps.contains { $0 is AISDKTranslationStep })
    }

    @Test("OpenAI without a key yields a deferred-failing step")
    func openAIMissingKeyDefersError() async {
        let pipeline = TranslationPipeline.make(engine: .openAI, openAIAPIKey: "")
        #expect(pipeline.steps.contains { $0 is FailingTranslationStep })

        var items = [TranslationItem(sourceText: "Hello", lineID: "1")]
        await #expect(throws: AISDKModelError.self) {
            try await pipeline.run(&items)
        }
    }

    @Test("Anthropic without a key yields a deferred-failing step")
    func anthropicMissingKeyDefersError() async {
        let pipeline = TranslationPipeline.make(engine: .anthropic, anthropicAPIKey: "")
        #expect(pipeline.steps.contains { $0 is FailingTranslationStep })

        var items = [TranslationItem(sourceText: "Hello", lineID: "1")]
        await #expect(throws: AISDKModelError.self) {
            try await pipeline.run(&items)
        }
    }

    @Test("Apple Translation routes through the unified AISDK step when available")
    func appleTranslationRoutesThroughAISDKStep() {
        let pipeline = TranslationPipeline.make(engine: .apple)
        if #available(macOS 26, *) {
            #expect(pipeline.steps.contains { $0 is AISDKTranslationStep })
            #expect(!pipeline.steps.contains { $0 is FailingTranslationStep })
        } else {
            // Below macOS 26 the headless session is unavailable; the error is
            // deferred to run time like a missing key.
            #expect(pipeline.steps.contains { $0 is FailingTranslationStep })
        }
    }

    @Test("Apple Intelligence routes through the unified AISDK step when available")
    func foundationModelRoutesThroughAISDKStep() {
        guard TranslationEngine.isFoundationModelAvailable else { return }
        let pipeline = TranslationPipeline.make(engine: .foundationModel)
        #expect(pipeline.steps.contains { $0 is AISDKTranslationStep })
        #expect(!pipeline.steps.contains { $0 is FailingTranslationStep })
    }

    // MARK: - TranslationItem tests

    @Test("TranslationItem initializes currentText from sourceText")
    func itemInitialization() {
        let item = TranslationItem(sourceText: "Test", lineID: "1", groupName: "Verse 1")
        #expect(item.currentText == "Test")
        #expect(item.sourceText == "Test")
        #expect(item.groupName == "Verse 1")
    }

    @Test("TranslationItem groupName defaults to nil")
    func itemGroupNameDefault() {
        let item = TranslationItem(sourceText: "Test", lineID: "1")
        #expect(item.groupName == nil)
    }

    // MARK: - TranslationRequest tests

    @Test("TranslationRequest equality")
    func requestEquality() {
        #expect(TranslationRequest.emptySlides == TranslationRequest.emptySlides)
        #expect(TranslationRequest.allSlides == TranslationRequest.allSlides)
        #expect(TranslationRequest.lines(["a", "b"]) == TranslationRequest.lines(["a", "b"]))
        #expect(TranslationRequest.emptySlides != TranslationRequest.allSlides)
        #expect(TranslationRequest.lines(["a"]) != TranslationRequest.lines(["b"]))
    }
}

/// Thread-safe wrapper for testing.
final class LockIsolated<Value: Sendable>: @unchecked Sendable {
    private var _value: Value
    private let lock = NSLock()

    var value: Value {
        lock.withLock { _value }
    }

    init(_ value: Value) {
        self._value = value
    }

    func withValue<T>(_ operation: (inout Value) -> T) -> T {
        lock.withLock { operation(&_value) }
    }
}
