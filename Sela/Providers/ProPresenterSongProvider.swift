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

        var songs: [Song] = []
        for url in urls {
            guard let (song, presentation) = try? ProPresenterReader.read(from: url) else { continue }
            cache[song.id] = presentation
            songs.append(song)
        }
        return songs
            .filter { $0.slideGroups.contains { $0.slides.contains(where: \.isTranslatable) } }
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
