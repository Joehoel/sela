import Foundation
import Observation
@preconcurrency import Translation

@Observable @MainActor
final class EditorController {
    let song: Song
    var save: () async throws -> Void

    // MARK: - Navigation

    var focusedLineID: String?

    // MARK: - Save state

    private(set) var isDirty = false
    private(set) var isSaving = false
    var saveError: String?

    // MARK: - Translation state

    private(set) var translationStatus: String?
    private(set) var translationError: String?
    var showRetranslateConfirmation = false
    private(set) var translationConfig: TranslationSession.Configuration?
    private var pendingLineIDs: Set<String> = []

    // MARK: - Engine config (synced from view's @AppStorage)

    var engine: TranslationEngine = .apple
    var deeplAPIKey: String = ""

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

    func handleAppleSession(_ session: TranslationSession) async {
        let glossary = GlossaryEntry.load()
        let pipeline = TranslationPipeline.make(engine: .apple, session: session, glossary: glossary)
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

        switch engine {
        case .apple:
            if translationConfig == nil {
                translationConfig = .init(
                    source: Locale.Language(identifier: "en"),
                    target: Locale.Language(identifier: "nl")
                )
            } else {
                translationConfig?.invalidate()
            }
        case .deepl:
            let glossary = GlossaryEntry.load()
            let pipeline = TranslationPipeline.make(engine: .deepl, deeplAPIKey: deeplAPIKey, glossary: glossary)
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

        do {
            try await pipeline.run(&items) { status in
                Task { @MainActor in
                    self.translationStatus = status
                }
            }

            guard !Task.isCancelled else { return }

            writeBack(items)
            translationStatus = nil
        } catch {
            guard !Task.isCancelled else { return }
            translationStatus = nil
            translationError = error.localizedDescription
        }
    }
}
