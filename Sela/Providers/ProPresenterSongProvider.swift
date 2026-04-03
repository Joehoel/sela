import Foundation

@MainActor
class ProPresenterSongProvider: SongProvider {
    private var cache: [String: RVData_Presentation] = [:]
    private let libraryURL: URL

    init(libraryURL: URL) {
        self.libraryURL = libraryURL
    }

    func loadSongs() async -> [Song] {
        let urls = (try? FileManager.default.contentsOfDirectory(
            at: libraryURL,
            includingPropertiesForKeys: nil
        ).filter { $0.pathExtension == "pro" }) ?? []

        // Read file data concurrently off the main actor
        let fileData: [(URL, Data)] = await withTaskGroup(of: (URL, Data)?.self) { group in
            for url in urls {
                group.addTask {
                    guard let data = try? Data(contentsOf: url) else { return nil }
                    return (url, data)
                }
            }
            var collected: [(URL, Data)] = []
            for await result in group {
                if let result { collected.append(result) }
            }
            return collected
        }

        // Parse on main actor (Song is not Sendable)
        var songs: [Song] = []
        for (url, data) in fileData {
            guard let presentation = try? RVData_Presentation(serializedBytes: data) else { continue }
            let song = ProPresenterReader.parse(presentation: presentation, url: url)
            cache[song.id] = presentation
            songs.append(song)
        }

        // Yield periodically to keep UI responsive
        return songs
            .filter { $0.slideGroups.contains { !$0.slides.isEmpty } }
            .sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
    }

    func save(_ song: Song) async throws {
        guard let filePath = song.filePath,
              var presentation = cache[song.id]
        else { return }

        try ProPresenterWriter.save(song, into: &presentation, at: filePath)
        cache[song.id] = presentation
    }
}
