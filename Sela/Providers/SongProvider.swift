import Foundation

@MainActor
protocol SongProvider {
    func loadSongs() async -> [Song]
    func save(_ song: Song) async throws
}

extension SongProvider {
    func save(_: Song) async throws {}
}
