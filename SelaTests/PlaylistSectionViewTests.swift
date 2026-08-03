import Foundation
@testable import Sela
import Testing

/// The pure pieces behind the sidebar's playlist section: row identity, the
/// search filter, and the line shown when there is no playlist.
struct PlaylistSectionViewTests {
    private func song(_ title: String) -> Song {
        Song(id: title, title: title)
    }

    private func playlist(_ items: [ServicePlaylistItem]) -> ServicePlaylist {
        ServicePlaylist(id: "PL1", name: "Sunday Service", items: items)
    }

    // MARK: - Row identity

    @Test("song rows keep their own id so the list does not re-create them")
    func songRowsKeepTheirID() {
        let grace = song("Amazing Grace")
        let rows = PlaylistRow.rows(for: [.song(grace)])

        #expect(rows.map(\.id) == ["song:Amazing Grace"])
        #expect(rows.first?.item.song === grace)
    }

    @Test("a repeated header title still gets a unique row id")
    func repeatedHeadersGetUniqueIDs() {
        let rows = PlaylistRow.rows(for: [
            .header("Songs"),
            .song(song("Amazing Grace")),
            .header("Songs"),
            .song(song("Way Maker")),
        ])

        #expect(Set(rows.map(\.id)).count == rows.count)
        #expect(rows.map(\.id) == [
            "header:Songs",
            "song:Amazing Grace",
            "header:Songs#2",
            "song:Way Maker",
        ])
    }

    // MARK: - Search

    @Test("an empty search term keeps every row")
    func emptySearchKeepsEverything() {
        let items: [ServicePlaylistItem] = [.header("Songs"), .song(song("Amazing Grace"))]

        #expect(playlist(items).items(matching: "").count == 2)
    }

    @Test("searching keeps matching songs and drops the rest")
    func searchFiltersSongs() {
        let items: [ServicePlaylistItem] = [
            .song(song("Amazing Grace")),
            .song(song("Way Maker")),
        ]

        let matches = playlist(items).items(matching: "way")

        #expect(matches.compactMap(\.song).map(\.title) == ["Way Maker"])
    }

    @Test("a header survives only when a song under it still matches")
    func searchDropsEmptyHeaders() {
        let items: [ServicePlaylistItem] = [
            .header("Opening"),
            .song(song("Amazing Grace")),
            .header("Closing"),
            .song(song("Way Maker")),
        ]

        let matches = playlist(items).items(matching: "grace")

        #expect(matches.count == 2)
        #expect(matches.first?.id == "header:Opening")
        #expect(matches.last?.song?.title == "Amazing Grace")
    }

    // MARK: - Status line

    @Test("the connection outranks the playlist status")
    func connectionStatusWins() {
        let endpoint = ProPresenterEndpoint(host: "localhost", port: 1025)

        #expect(
            PlaylistSectionStatus.message(connection: .disconnected, playlist: .ready)
                == "Not connected"
        )
        #expect(
            PlaylistSectionStatus.message(connection: .searching, playlist: .ready)
                == "Searching for ProPresenter…"
        )
        #expect(
            PlaylistSectionStatus.message(connection: .connecting(endpoint), playlist: .idle)
                == "Searching for ProPresenter…"
        )
    }

    /// A verified connection, the state every playlist-status case is judged in.
    private var connected: ProPresenterConnectionStatus {
        .connected(
            ProPresenterEndpoint(host: "localhost", port: 1025),
            ProPresenterVersion(
                name: nil,
                platform: nil,
                osVersion: nil,
                hostDescription: "ProPresenter 7.13",
                apiVersion: nil
            )
        )
    }

    @Test("a loaded playlist with no rows says it is empty instead of loading")
    func emptyPlaylistIsNotReportedAsLoading() {
        // `.ready` with no rows is a playlist that really is empty — the
        // section used to promise a load that was never coming.
        #expect(
            PlaylistSectionStatus.message(connection: connected, playlist: .ready)
                == "Playlist is empty"
        )
        #expect(
            PlaylistSectionStatus.message(connection: connected, playlist: .loading)
                == "Loading playlist…"
        )
        #expect(
            PlaylistSectionStatus.message(connection: connected, playlist: .idle)
                == "Loading playlist…"
        )
    }

    @Test("a playlist shown without a live connection carries a stale hint")
    func staleHintWhileNotLive() {
        #expect(PlaylistSectionStatus.staleHint(connection: connected, playlist: .ready) == nil)
        #expect(PlaylistSectionStatus.staleHint(connection: connected, playlist: .loading) == nil)
        #expect(
            PlaylistSectionStatus.staleHint(connection: connected, playlist: .offline)
                == "ProPresenter is not reachable"
        )
        #expect(
            PlaylistSectionStatus.staleHint(connection: connected, playlist: .failed("Boom")) == "Boom"
        )
        #expect(
            PlaylistSectionStatus.staleHint(connection: .disconnected, playlist: .ready)
                == "Not connected"
        )
        #expect(
            PlaylistSectionStatus.staleHint(connection: .searching, playlist: .ready)
                == "Searching for ProPresenter…"
        )
    }

    @Test("while connected the playlist status is what the section reports")
    func connectedReportsPlaylistStatus() {
        #expect(
            PlaylistSectionStatus.message(connection: connected, playlist: .loading)
                == "Loading playlist…"
        )
        #expect(
            PlaylistSectionStatus.message(connection: connected, playlist: .unavailable)
                == "No playlist focused in ProPresenter"
        )
        #expect(
            PlaylistSectionStatus.message(connection: connected, playlist: .failed("Boom"))
                == "Boom"
        )
    }
}
