import Foundation

/// One row of the playlist Sela shows above the libraries.
///
/// Only two kinds survive resolution: a presentation that maps onto a `.pro`
/// file (and therefore onto an editable `Song`), and a header used as a section
/// title. Media, audio and video items — and presentations whose file could not
/// be found — are dropped while building, so every row here is actionable.
enum ServicePlaylistItem: Identifiable {
    case song(Song)
    case header(String)

    /// Stable across refreshes. Song ids are unique; two headers with the same
    /// title share an id, so lists that must distinguish them should key on the
    /// row's position instead.
    var id: String {
        switch self {
        case let .song(song): "song:\(song.id)"
        case let .header(title): "header:\(title)"
        }
    }

    var song: Song? {
        guard case let .song(song) = self else { return nil }
        return song
    }
}

/// The ProPresenter playlist Sela is currently showing: the service, resolved
/// onto the songs the user can edit.
struct ServicePlaylist: Identifiable {
    /// The playlist's UUID, as ProPresenter reports it.
    let id: String
    /// The playlist's name, shown as the section title.
    let name: String
    /// Resolved rows, in playlist order.
    var items: [ServicePlaylistItem]

    init(id: String, name: String, items: [ServicePlaylistItem] = []) {
        self.id = id
        self.name = name
        self.items = items
    }

    /// The editable songs in the playlist, headers left out.
    var songs: [Song] {
        items.compactMap(\.song)
    }

    var isEmpty: Bool {
        items.isEmpty
    }

    /// The rows to show for a search term: songs whose title matches, plus the
    /// headers that still have a match under them. An empty term returns every
    /// row — the same filter the library groups apply.
    func items(matching searchText: String) -> [ServicePlaylistItem] {
        guard !searchText.isEmpty else { return items }

        var matches: [ServicePlaylistItem] = []
        var pendingHeader: ServicePlaylistItem?
        for item in items {
            switch item {
            case .header:
                pendingHeader = item
            case let .song(song):
                guard song.title.localizedCaseInsensitiveContains(searchText) else { continue }
                if let pendingHeader {
                    matches.append(pendingHeader)
                }
                pendingHeader = nil
                matches.append(item)
            }
        }
        return matches
    }
}
