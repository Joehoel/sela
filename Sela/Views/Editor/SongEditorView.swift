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

    @State private var controller: EditorController

    init(song: Song) {
        self.song = song
        self._controller = State(initialValue: EditorController(song: song))
    }

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 24) {
                ForEach(song.slideGroups.filter { !$0.contentSlides.isEmpty }) { group in
                    SlideGroupView(
                        group: group,
                        focusedLineID: $focusedLineID,
                        onAdvance: { controller.advanceFromLine($0) },
                        onRetreat: { controller.retreatFromLine($0) },
                        onTranslateSlide: { controller.translateSlide($0) }
                    )
                }
            }
            .padding(20)
        }
        .navigationTitle(song.title)
        .navigationSubtitle(song.author)
        .toolbar { toolbarContent }
        .alert("Retranslate All Slides?", isPresented: $controller.showRetranslateConfirmation) {
            Button("Retranslate", role: .destructive) {
                controller.triggerTranslation(for: .allSlides)
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This will overwrite all existing translations, including manual edits.")
        }
        .alert("Translation Failed", isPresented: hasTranslationError) {
            Button("OK") { controller.dismissTranslationError() }
        } message: {
            Text(controller.translationError ?? "")
        }
        .alert("Save Failed", isPresented: hasSaveError) {
            Button("OK") { controller.saveError = nil }
        } message: {
            Text(controller.saveError ?? "")
        }
        .translationTask(controller.translationConfig) { session in
            await controller.handleAppleSession(session)
        }
        .onChange(of: appState.translationRequest) { _, request in
            guard let request else { return }
            controller.requestTranslation(request)
            appState.translationRequest = nil
        }
        .onReceive(NotificationCenter.default.publisher(for: .saveSong)) { _ in
            Task { await controller.performSave() }
        }
        .onAppear { wireDependencies() }
        .onChange(of: selectedEngine) { _, val in
            controller.engine = TranslationEngine(rawValue: val) ?? .apple
        }
        .onChange(of: deeplAPIKey) { _, val in
            controller.deeplAPIKey = val
        }
        .onChange(of: controller.focusedLineID) { _, newValue in
            focusedLineID = newValue
        }
        .onChange(of: focusedLineID) { _, newValue in
            controller.focusedLineID = newValue
        }
    }

    private func wireDependencies() {
        controller.engine = TranslationEngine(rawValue: selectedEngine) ?? .apple
        controller.deeplAPIKey = deeplAPIKey
        controller.save = { [appState, song] in
            try await appState.save(song)
        }
    }

    // MARK: - Toolbar

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItemGroup(placement: .primaryAction) {
            if let status = controller.translationStatus {
                ProgressView()
                    .controlSize(.small)
                Text(status)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if controller.isSaving {
                ProgressView()
                    .controlSize(.small)
                    .help("Saving…")
            } else {
                Button { Task { await controller.performSave() } } label: {
                    Label("Save", systemImage: "externaldrive")
                }
                .help(controller.isDirty ? "Save (⌘S)" : "All changes saved")
                .disabled(!controller.isDirty)
            }

            Button {
                controller.requestTranslation(.emptySlides)
            } label: {
                Label("Translate", systemImage: "translate")
            }
            .keyboardShortcut("t")
            .help("Translate empty slides (⌘T)")
            .disabled(controller.translationStatus != nil)

            Button {
                appState.isInspectorPresented.toggle()
            } label: {
                Label("Diagnose", systemImage: "sidebar.trailing")
            }
            .badge(song.diagnoseIssues.count)
            .keyboardShortcut("d")
            .help("Toggle diagnose inspector (⌘D)")
        }
    }

    // MARK: - Bindings

    private var hasTranslationError: Binding<Bool> {
        Binding(
            get: { controller.translationError != nil },
            set: { if !$0 { controller.dismissTranslationError() } }
        )
    }

    private var hasSaveError: Binding<Bool> {
        Binding(
            get: { controller.saveError != nil },
            set: { if !$0 { controller.saveError = nil } }
        )
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
