import Combine
import SwiftUI
@preconcurrency import Translation

extension Notification.Name {
    static let saveSong = Notification.Name("saveSong")
}

struct SongEditorView: View {
    @Environment(AppState.self) private var appState
    let song: Song
    @FocusState private var focusedLineID: String?

    @AppStorage("translationEngine") private var selectedEngine = TranslationEngine.apple.rawValue
    @AppStorage("deeplAPIKey") private var deeplAPIKey = ""

    @State private var translationConfig: TranslationSession.Configuration?
    @State private var translationStatus: String?
    @State private var showRetranslateConfirmation = false
    @State private var translationError: String?
    @State private var saveTask: Task<Void, Never>?

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 24) {
                ForEach(song.slideGroups) { group in
                    SlideGroupView(
                        group: group,
                        focusedLineID: $focusedLineID,
                        onAdvance: { advanceFromLine($0) },
                        onRetreat: { retreatFromLine($0) },
                        onTranslateSlide: { translateSlide($0) }
                    )
                }
            }
            .padding(20)
        }
        .navigationTitle(song.title)
        .navigationSubtitle(song.author)
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                if let status = translationStatus {
                    ProgressView()
                        .controlSize(.small)
                    Text(status)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Button {
                    requestTranslation(.emptySlides)
                } label: {
                    Label("Translate", systemImage: "translate")
                }
                .keyboardShortcut("t")
                .help("Translate empty slides (⌘T)")
                .disabled(translationStatus != nil)

                Button {
                    appState.isInspectorPresented.toggle()
                } label: {
                    Label("Diagnose", systemImage: "sidebar.trailing")
                }
                .keyboardShortcut("d")
                .help("Toggle diagnose inspector (⌘D)")
            }
        }
        .alert("Retranslate All Slides?", isPresented: $showRetranslateConfirmation) {
            Button("Retranslate", role: .destructive) {
                triggerTranslation(for: .allSlides)
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This will overwrite all existing translations, including manual edits.")
        }
        .alert("Translation Failed", isPresented: .init(
            get: { translationError != nil },
            set: { if !$0 { translationError = nil } }
        )) {
            Button("OK") { translationError = nil }
        } message: {
            Text(translationError ?? "")
        }
        .translationTask(translationConfig) { session in
            let glossary = GlossaryEntry.load()
            let pipeline = TranslationPipeline.make(engine: .apple, session: session, glossary: glossary)
            await runPipeline(pipeline)
        }
        .onChange(of: appState.translationRequest) { _, request in
            guard let request else { return }
            requestTranslation(request)
        }
        .onReceive(NotificationCenter.default.publisher(for: .saveSong)) { _ in
            saveSong()
        }
    }

    // MARK: - Translation

    private func requestTranslation(_ request: TranslationRequest) {
        appState.translationRequest = nil

        switch request {
        case .allSlides:
            showRetranslateConfirmation = true
        case .emptySlides, .lines:
            triggerTranslation(for: request)
        }
    }

    private var engine: TranslationEngine {
        TranslationEngine(rawValue: selectedEngine) ?? .apple
    }

    private func triggerTranslation(for request: TranslationRequest) {
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

    @State private var pendingLineIDs: Set<String> = []

    private func resolveLines(for request: TranslationRequest) -> [SlideLine] {
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

    private func runPipeline(_ pipeline: TranslationPipeline) async {
        var items = buildItems()
        guard !items.isEmpty else { return }

        do {
            try await pipeline.run(&items) { status in
                Task { @MainActor in
                    translationStatus = status
                }
            }

            guard !Task.isCancelled else { return }

            await MainActor.run {
                writeBack(items)
                translationStatus = nil
            }
        } catch {
            guard !Task.isCancelled else { return }
            await MainActor.run {
                translationStatus = nil
                translationError = error.localizedDescription
            }
        }
    }

    private func buildItems() -> [TranslationItem] {
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

    private func writeBack(_ items: [TranslationItem]) {
        let lookup = Dictionary(uniqueKeysWithValues: items.map { ($0.lineID, $0.currentText) })
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

    // MARK: - Save

    private func debounceSave() {
        saveTask?.cancel()
        saveTask = Task {
            try? await Task.sleep(for: .seconds(2))
            guard !Task.isCancelled else { return }
            saveSong()
        }
    }

    private func saveSong() {
        saveTask?.cancel()
        Task {
            try? await appState.save(song)
        }
    }

    // MARK: - Slide-level translation

    private func translateSlide(_ slide: Slide) {
        let lineIDs = slide.lines.map(\.id)
        requestTranslation(.lines(lineIDs))
    }

    // MARK: - Navigation

    private var allLineIDs: [String] {
        song.slideGroups.flatMap(\.slides).flatMap(\.lines).map(\.id)
    }

    private func advanceFromLine(_ lineID: String) {
        let ids = allLineIDs
        guard let index = ids.firstIndex(of: lineID) else { return }
        let next = (index + 1) % ids.count
        focusedLineID = ids[next]
    }

    private func retreatFromLine(_ lineID: String) {
        let ids = allLineIDs
        guard let index = ids.firstIndex(of: lineID) else { return }
        let prev = (index - 1 + ids.count) % ids.count
        focusedLineID = ids[prev]
    }
}

#Preview("With Translation") {
    NavigationStack {
        SongEditorView(song: MockSongProvider.buildMyLife)
    }
    .environment(AppState())
    .frame(width: 600, height: 700)
}

#Preview("Empty") {
    NavigationStack {
        SongEditorView(song: MockSongProvider.wayMaker)
    }
    .environment(AppState())
    .frame(width: 600, height: 700)
}
