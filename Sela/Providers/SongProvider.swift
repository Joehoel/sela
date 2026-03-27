import Foundation

protocol SongProvider: Sendable {
    func loadSongs() async -> [Song]
}
