import SwiftUI

struct SongEditorView: View {
    @Environment(AppState.self) private var appState
    let song: Song
    @FocusState private var focusedLineID: String?

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 24) {
                ForEach(song.slideGroups) { group in
                    SlideGroupView(
                        group: group,
                        focusedLineID: $focusedLineID,
                        onAdvance: { advanceFromLine($0) },
                        onRetreat: { retreatFromLine($0) }
                    )
                }
            }
            .padding(20)
        }
        .navigationTitle(song.title)
        .navigationSubtitle(song.author)
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                Button {
                    translateEmptySlides()
                } label: {
                    Label("Translate", systemImage: "translate")
                }
                .keyboardShortcut("t")
                .help("Translate empty slides (⌘T)")

                Button {
                    appState.isInspectorPresented.toggle()
                } label: {
                    Label("Diagnose", systemImage: "sidebar.trailing")
                }
                .keyboardShortcut("d")
                .help("Toggle diagnose inspector (⌘D)")
            }
        }
    }

    private func translateEmptySlides() {
        // Placeholder — will wire to translation pipeline later
    }

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
