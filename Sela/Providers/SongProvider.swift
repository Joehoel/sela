import Foundation

@MainActor
protocol SongProvider {
    func loadSongs() async -> [Song]
}
