import SwiftUI

struct SongEditorView: View {
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
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                Button {
                    translateEmptySlides()
                } label: {
                    Label("Translate", systemImage: "translate")
                }
                .keyboardShortcut("t")
                .help("Translate empty slides (⌘T)")
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
        guard let index = ids.firstIndex(of: lineID), index + 1 < ids.count else { return }
        focusedLineID = ids[index + 1]
    }

    private func retreatFromLine(_ lineID: String) {
        let ids = allLineIDs
        guard let index = ids.firstIndex(of: lineID), index > 0 else { return }
        focusedLineID = ids[index - 1]
    }
}
