import Foundation
import Observation
@preconcurrency import Sentry
@preconcurrency import Translation

@Observable @MainActor
final class EditorController {
    let song: Song
    var save: () async throws -> Void

    // MARK: - Navigation

    var focusedLineID: String?
    var scrollRequest: ScrollRequest?

    struct ScrollRequest: Equatable {
        let lineID: String
        let token = UUID()
    }

    // MARK: - Save state

    private(set) var isDirty = false
    private(set) var isSaving = false
    private(set) var showSaveNotice = false
    var saveError: String?
    private var saveNoticeTask: Task<Void, Never>?

    // MARK: - Translation state

    private(set) var translationStatus: String?
    private(set) var translationError: String?
    var showRetranslateConfirmation = false
    private var _translationConfig: Any?
    private var pendingLineIDs: Set<String> = []

    @available(macOS 15, *)
    var translationConfig: TranslationSession.Configuration? {
        get { _translationConfig as? TranslationSession.Configuration }
        set { _translationConfig = newValue }
    }

    // MARK: - Preferences (set on appear)

    var preferences: UserPreferences?

    // MARK: - Diagnostics

    var diagnoseIssues: [DiagnoseIssue] {
        let enabledIDs = preferences?.enabledRuleIDs ?? Set(DiagnosticRules.defaultEnabledIDs)
        let rules = DiagnosticRules.all.filter { enabledIDs.contains($0.id) }
        return DiagnosticsEngine.diagnose(song: song, rules: rules)
    }

    func applyFix(for issue: DiagnoseIssue) {
        guard let fix = issue.fix else { return }
        let allLines = song.slideGroups.flatMap(\.slides).flatMap(\.lines)
        guard let line = allLines.first(where: { $0.id == issue.lineID }),
              let fixed = fix(line)
        else { return }
        line.translation = fixed
        debounceSave()
    }

    func fixAllIssues() {
        for issue in diagnoseIssues {
            applyFix(for: issue)
        }
    }

    // MARK: - Init

    private var debounceTask: Task<Void, Never>?

    init(song: Song, save: @escaping () async throws -> Void = {}) {
        self.song = song
        self.save = save
    }

    // MARK: - Navigation

    private var allLineIDs: [String] {
        song.slideGroups.flatMap(\.slides).flatMap(\.lines).map(\.id)
    }

    func navigateToLine(_ lineID: String) {
        focusedLineID = lineID
        scrollRequest = ScrollRequest(lineID: lineID)
    }

    func advanceFromLine(_ lineID: String) {
        let ids = allLineIDs
        guard let index = ids.firstIndex(of: lineID) else { return }
        let next = (index + 1) % ids.count
        focusedLineID = ids[next]
    }

    func retreatFromLine(_ lineID: String) {
        let ids = allLineIDs
        guard let index = ids.firstIndex(of: lineID) else { return }
        let prev = (index - 1 + ids.count) % ids.count
        focusedLineID = ids[prev]
    }

    // MARK: - Save

    func debounceSave() {
        isDirty = true
        debounceTask?.cancel()
        debounceTask = Task {
            try? await Task.sleep(for: .seconds(2))
            guard !Task.isCancelled else { return }
            await performSave()
        }
    }

    func performSave() async {
        debounceTask?.cancel()
        isSaving = true
        do {
            try await save()
            isDirty = false
            showSaveNotice = true
            saveNoticeTask?.cancel()
            saveNoticeTask = Task {
                try? await Task.sleep(for: .seconds(5))
                guard !Task.isCancelled else { return }
                showSaveNotice = false
            }
        } catch {
            saveError = error.localizedDescription
        }
        isSaving = false
    }

    // MARK: - Translation

    func requestTranslation(_ request: TranslationRequest) {
        switch request {
        case .allSlides:
            showRetranslateConfirmation = true
        case .emptySlides, .lines:
            triggerTranslation(for: request)
        }
    }

    @available(macOS 15, *)
    func handleAppleSession(_ session: TranslationSession) async {
        let glossary = GlossaryEntry.load()
        let refinement = preferences?.refinementEngine
        let geminiKey = preferences?.geminiAPIKey ?? ""
        let pipeline = TranslationPipeline.make(
            engine: .apple, session: session, geminiAPIKey: geminiKey, glossary: glossary,
            refinementEngine: refinement
        )
        await runPipeline(pipeline)
    }

    func translateSlide(_ slide: Slide) {
        let lineIDs = slide.lines.map(\.id)
        requestTranslation(.lines(lineIDs))
    }

    func dismissTranslationError() {
        translationError = nil
    }

    func triggerTranslation(for request: TranslationRequest) {
        let lines = resolveLines(for: request)
        guard !lines.isEmpty else { return }

        pendingLineIDs = Set(lines.map(\.id))

        let engine = preferences?.translationEngine ?? .apple

        let refinement = preferences?.refinementEngine
        let geminiKey = preferences?.geminiAPIKey ?? ""

        switch engine {
        case .apple:
            if #available(macOS 15, *) {
                if translationConfig == nil {
                    translationConfig = .init(
                        source: Locale.Language(identifier: "en"),
                        target: Locale.Language(identifier: "nl")
                    )
                } else {
                    translationConfig?.invalidate()
                }
            }
        case .googleTranslate, .myMemory:
            let glossary = GlossaryEntry.load()
            let pipeline = TranslationPipeline.make(
                engine: engine, geminiAPIKey: geminiKey, glossary: glossary,
                refinementEngine: refinement
            )
            Task { await runPipeline(pipeline) }
        case .deepl:
            let glossary = GlossaryEntry.load()
            let apiKey = preferences?.deeplAPIKey ?? ""
            let pipeline = TranslationPipeline.make(
                engine: .deepl, deeplAPIKey: apiKey, geminiAPIKey: geminiKey, glossary: glossary,
                refinementEngine: refinement
            )
            Task { await runPipeline(pipeline) }
        case .gemini:
            let glossary = GlossaryEntry.load()
            let pipeline = TranslationPipeline.make(
                engine: .gemini, geminiAPIKey: geminiKey, glossary: glossary,
                refinementEngine: refinement
            )
            Task { await runPipeline(pipeline) }
        case .foundationModel:
            let glossary = GlossaryEntry.load()
            let pipeline = TranslationPipeline.make(
                engine: .foundationModel, glossary: glossary
            )
            Task { await runPipeline(pipeline) }
        }
    }

    func resolveLines(for request: TranslationRequest) -> [SlideLine] {
        let allLines = song.slideGroups.flatMap(\.slides).flatMap(\.lines)
        switch request {
        case .emptySlides:
            return allLines.filter(\.translation.isEmpty)
        case .allSlides:
            return allLines
        case let .lines(ids):
            let idSet = Set(ids)
            return allLines.filter { idSet.contains($0.id) }
        }
    }

    func buildItems() -> [TranslationItem] {
        var items: [TranslationItem] = []
        for group in song.slideGroups {
            for slide in group.slides {
                for line in slide.lines where pendingLineIDs.contains(line.id) {
                    items.append(TranslationItem(
                        sourceText: line.original,
                        lineID: line.id,
                        groupName: group.name
                    ))
                }
            }
        }
        return items
    }

    func writeBack(_ items: [TranslationItem]) {
        let lookup = Dictionary(items.map { ($0.lineID, $0.currentText) }, uniquingKeysWith: { _, last in last })
        for group in song.slideGroups {
            for slide in group.slides {
                for line in slide.lines {
                    if let translated = lookup[line.id] {
                        line.translation = translated
                    }
                }
            }
        }
        pendingLineIDs = []
        debounceSave()
    }

    // MARK: - Test helpers

    var hasPendingLines: Bool {
        !pendingLineIDs.isEmpty
    }

    func setPendingLineIDs(_ ids: Set<String>) {
        pendingLineIDs = ids
    }

    func setTranslationError(_ message: String) {
        translationError = message
    }

    // MARK: - Private

    private func runPipeline(_ pipeline: TranslationPipeline) async {
        var items = buildItems()
        guard !items.isEmpty else { return }

        let engine = (preferences?.translationEngine ?? .apple).rawValue
        let startTime = Date()
        SelaMetrics.translationRequested(engine: engine, lineCount: items.count)

        let transaction = SentrySDK.startTransaction(
            name: "translation.pipeline",
            operation: "translate",
            bindToScope: true
        )
        transaction.setTag(value: engine, key: "engine")

        do {
            try await pipeline.run(&items) { status in
                Task { @MainActor in
                    self.translationStatus = status
                }
            }

            guard !Task.isCancelled else {
                transaction.finish(status: .cancelled)
                return
            }

            writeBack(items)
            translationStatus = nil
            SelaMetrics.translationCompleted(engine: engine, durationMs: startTime.msSince)
            transaction.finish()
        } catch {
            guard !Task.isCancelled else {
                transaction.finish(status: .cancelled)
                return
            }
            translationStatus = nil
            translationError = error.localizedDescription
            SelaMetrics.translationFailed(engine: engine, reason: Self.classify(error))
            SentrySDK.capture(error: error)
            transaction.finish(status: .internalError)
        }
    }

    private static func classify(_ error: Error) -> SelaMetrics.TranslationFailureReason {
        let nsError = error as NSError
        if nsError.domain == NSURLErrorDomain { return .network }
        let description = nsError.localizedDescription.lowercased()
        if description.contains("api key") || description.contains("401") || description.contains("403") {
            return .auth
        }
        if description.contains("decode") || description.contains("parse") || description.contains("json") {
            return .parse
        }
        return .other
    }
}
