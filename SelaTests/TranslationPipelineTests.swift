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
