import Foundation
import Observation

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
    private var debounceTask: Task<Void, Never>?

    init(song: Song, save: @escaping () async throws -> Void = {}) {
        self.song = song
        self.save = save
    }

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
}
