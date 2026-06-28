import Combine
import SwiftUI

extension Notification.Name {
    static let saveSong = Notification.Name("saveSong")
}

struct SongEditorView: View {
    @Environment(AppState.self) private var appState
    @Environment(UserPreferences.self) private var preferences
    let song: Song
    @FocusState private var focusedLineID: String?

    @State private var controller: EditorController
    @State private var showSavePopover = false

    init(song: Song) {
        self.song = song
        self._controller = State(initialValue: EditorController(song: song))
    }

    /// Line IDs that currently have one or more diagnostics, used to tint their
    /// rows. Recomputes with `diagnoseIssues`, so it tracks edits live.
    private var issueLineIDs: Set<String> {
        Set(controller.diagnoseIssues.map(\.lineID))
    }

    var body: some View {
        @Bindable var appState = appState

        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 24) {
                    ForEach(song.slideGroups.filter { !$0.slides.isEmpty }) { group in
                        SlideGroupView(
                            group: group,
                            focusedLineID: $focusedLineID,
                            issueLineIDs: issueLineIDs,
                            onAdvance: { controller.advanceFromLine($0) },
                            onRetreat: { controller.retreatFromLine($0) },
                            onTranslateSlide: { controller.translateSlide($0) }
                        )
                    }
                }
                .padding(20)
            }
            .onChange(of: controller.focusedLineID) { _, lineID in
                focusedLineID = lineID
            }
            .onChange(of: controller.scrollRequest) { _, request in
                guard let request else { return }
                withAnimation {
                    proxy.scrollTo(request.lineID, anchor: .center)
                }
            }
        }
        .navigationTitle(song.title)
        .navigationSubtitle(song.author)
        .toolbar { toolbarContent }
        .inspector(isPresented: $appState.isInspectorPresented) {
            DiagnoseInspector(
                song: song,
                issues: controller.diagnoseIssues,
                onSelectIssue: { controller.navigateToLine($0.lineID) },
                onFixIssue: { controller.applyFix(for: $0) },
                onFixAll: { controller.fixAllIssues() }
            )
            .inspectorColumnWidth(min: 200, ideal: 260, max: 340)
        }
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
        .onChange(of: appState.translationRequest) { _, request in
            guard let request else { return }
            controller.requestTranslation(request)
            appState.translationRequest = nil
        }
        .onReceive(NotificationCenter.default.publisher(for: .saveSong)) { _ in
            Task { await controller.performSave() }
        }
        .onReceive(NotificationCenter.default.publisher(for: .fixAllIssues)) { _ in
            controller.fixAllIssues()
        }
        .onAppear {
            controller.preferences = preferences
            controller.save = { [appState, song] in
                try await appState.save(song)
            }
        }
        .onChange(of: focusedLineID) { _, newValue in
            controller.focusedLineID = newValue
        }
        .onChange(of: controller.showSaveNotice) { _, show in
            if show { showSavePopover = true }
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

            Button {
                controller.requestTranslation(.emptySlides)
            } label: {
                Label("Translate", systemImage: "translate")
            }
            .keyboardShortcut("t")
            .help("Translate empty slides (⌘T)")
            .disabled(controller.translationStatus != nil)
            .popover(isPresented: $showSavePopover) {
                VStack(alignment: .leading, spacing: 12) {
                    Label("Restart ProPresenter to see your changes", systemImage: "arrow.clockwise")
                        .font(.callout)

                    Button {
                        Task { await controller.restartProPresenter() }
                    } label: {
                        if controller.isRestartingProPresenter {
                            ProgressView()
                                .controlSize(.small)
                        } else {
                            Text("Restart ProPresenter")
                                .frame(maxWidth: .infinity)
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(controller.isRestartingProPresenter)

                    if let restartError = controller.restartError {
                        Text(restartError)
                            .font(.caption)
                            .foregroundStyle(.red)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .padding()
                .frame(width: 280)
            }

            Button {
                appState.isInspectorPresented.toggle()
            } label: {
                Label("Diagnose", systemImage: "sidebar.trailing")
            }
            .badge(controller.diagnoseIssues.count)
            .keyboardShortcut("d")
            .help("Toggle diagnose inspector (⌘D)")
            .popoverTip(DiagnoseInspectorTip())
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
    .environment(UserPreferences())
    .frame(width: 600, height: 700)
}

#Preview("Empty") {
    NavigationStack {
        SongEditorView(song: MockSongProvider.wayMaker)
    }
    .environment(AppState())
    .environment(UserPreferences())
    .frame(width: 600, height: 700)
}
