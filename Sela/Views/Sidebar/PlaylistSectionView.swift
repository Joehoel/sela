import SwiftUI

/// The service playlist at the top of the sidebar: whatever ProPresenter has
/// focused, or the playlist the user pinned through the header menu.
///
/// The body is a `Section`, so the view plugs straight into `SongListView`'s
/// `List` and shares that list's selection — a playlist song and its library row
/// are the same `Song`, so selecting either opens the same editor. Without a
/// connection the section collapses to a single status row: the libraries
/// underneath keep working, because Sela stays a full library editor with or
/// without ProPresenter.
struct PlaylistSectionView: View {
    @Environment(AppState.self) private var appState
    @Environment(PlaylistController.self) private var playlistController
    @Environment(ProPresenterConnection.self) private var connection

    var body: some View {
        // While searching, a section without matches disappears entirely — the
        // same rule the library groups follow.
        if !appState.searchText.isEmpty, rows.isEmpty {
            EmptyView()
        } else {
            Section {
                if rows.isEmpty {
                    statusRow
                } else {
                    ForEach(rows) { row in
                        rowView(for: row)
                    }
                }
            } header: {
                header
            }
        }
    }

    /// The playlist rows for the current search term.
    private var rows: [PlaylistRow] {
        guard let playlist = playlistController.playlist else { return [] }
        return PlaylistRow.rows(for: playlist.items(matching: appState.searchText))
    }

    // MARK: - Rows

    @ViewBuilder
    private func rowView(for row: PlaylistRow) -> some View {
        switch row.item {
        case let .song(song):
            SongRowView(song: song)
                .tag(song.id)
                .contextMenu {
                    // Hiding is deliberately absent: the playlist mirrors the
                    // service, so a row here is not the user's to remove.
                    Button("Clear All Translations") {
                        song.clearTranslations()
                        Task { try? await appState.save(song) }
                    }
                    .disabled(!song.hasTranslation)
                }
        case let .header(title):
            Text(title)
                .font(.caption)
                .fontWeight(.semibold)
                .foregroundStyle(.secondary)
                .selectionDisabled()
        }
    }

    /// Shown instead of the rows when there is no playlist to show.
    private var statusRow: some View {
        Text(
            PlaylistSectionStatus.message(
                connection: connection.status,
                playlist: playlistController.status
            )
        )
        .font(.callout)
        .foregroundStyle(.secondary)
        .selectionDisabled()
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 4) {
            Text(playlistController.playlist?.name ?? "Playlist")
                .lineLimit(1)
            if let hint = staleHint {
                Image(systemName: "wifi.slash")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .help(hint)
                    .accessibilityLabel(hint)
            }
            Spacer(minLength: 0)
            playlistMenu
        }
        // The tree is fetched once per connection and again whenever the shown
        // playlist changes, which is as often as a menu this small needs it.
        .task(id: menuRefreshToken) {
            await playlistController.loadAvailablePlaylists()
        }
    }

    /// Set while the rows on screen are a last known playlist rather than a live
    /// one; `nil` otherwise.
    private var staleHint: String? {
        guard playlistController.playlist != nil else { return nil }
        return PlaylistSectionStatus.staleHint(
            connection: connection.status,
            playlist: playlistController.status
        )
    }

    private var menuRefreshToken: String {
        "\(connection.status.isConnected)|\(playlistController.playlist?.id ?? "")"
    }

    private var playlistMenu: some View {
        Menu {
            Button {
                playlistController.followProPresenter()
            } label: {
                PlaylistMenuLabel(
                    title: "Follow ProPresenter",
                    isSelected: playlistController.selection.followsProPresenter
                )
            }

            if !playlistController.availablePlaylists.isEmpty {
                Divider()
                PlaylistMenuNodes(
                    nodes: playlistController.availablePlaylists,
                    selectedID: playlistController.selection.playlistID,
                    select: { playlistController.select(id: $0.uuid, name: $0.name) }
                )
            }
        } label: {
            Image(systemName: "chevron.down")
                .font(.caption2)
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .accessibilityLabel("Choose playlist")
    }
}

/// One level of the `GET /v1/playlists` tree: playlists become buttons, groups
/// become submenus.
struct PlaylistMenuNodes: View {
    let nodes: [ProPresenterPlaylistNode]
    /// The pinned playlist's UUID, or `nil` while following ProPresenter.
    let selectedID: String?
    let select: (ProPresenterObjectID) -> Void

    var body: some View {
        // Node UUIDs come from ProPresenter and may be empty, so the position in
        // the tree is the identity here.
        ForEach(Array(nodes.enumerated()), id: \.offset) { _, node in
            switch node.type {
            case .group:
                Menu(node.id.name) {
                    AnyView(
                        PlaylistMenuNodes(
                            nodes: node.playlists,
                            selectedID: selectedID,
                            select: select
                        )
                    )
                }
            case .playlist, .unknown:
                Button {
                    select(node.id)
                } label: {
                    PlaylistMenuLabel(
                        title: node.id.name,
                        isSelected: !node.id.uuid.isEmpty && node.id.uuid == selectedID
                    )
                }
            }
        }
    }
}

/// A menu entry that shows a checkmark when it is the active choice.
struct PlaylistMenuLabel: View {
    let title: String
    let isSelected: Bool

    var body: some View {
        if isSelected {
            Label(title, systemImage: "checkmark")
        } else {
            Text(title)
        }
    }
}

/// One row of the playlist section.
///
/// `ServicePlaylistItem.id` is unique for songs but not for headers — a service
/// may well have two "Songs" blocks — so repeated ids get an occurrence suffix.
/// Song rows keep their plain id, which is what keeps the list from re-creating
/// them (and losing the selection highlight) on every refresh.
struct PlaylistRow: Identifiable {
    let id: String
    let item: ServicePlaylistItem

    static func rows(for items: [ServicePlaylistItem]) -> [PlaylistRow] {
        var occurrences: [String: Int] = [:]
        return items.map { item in
            let count = (occurrences[item.id] ?? 0) + 1
            occurrences[item.id] = count
            return PlaylistRow(id: count == 1 ? item.id : "\(item.id)#\(count)", item: item)
        }
    }
}

/// The single line the playlist section shows when it has no playlist.
///
/// The connection comes first: "not connected" and "searching" are the states the
/// user can act on, and they outrank whatever the playlist controller last saw.
enum PlaylistSectionStatus {
    static func message(
        connection: ProPresenterConnectionStatus,
        playlist: PlaylistStatus
    ) -> String {
        switch connection {
        case .disconnected:
            "Not connected"
        case .searching, .connecting:
            "Searching for ProPresenter…"
        case .connected:
            switch playlist {
            case .idle, .loading:
                "Loading playlist…"
            case .ready:
                // Loaded, and there is genuinely nothing in it.
                "Playlist is empty"
            case .unavailable:
                "No playlist focused in ProPresenter"
            case .offline:
                "ProPresenter is not reachable"
            case let .failed(reason):
                reason
            }
        }
    }

    /// The compact hint shown next to the section title while a playlist *is*
    /// on screen but no longer live — the list is then the last known service,
    /// and nothing else in the sidebar says so. `nil` while the section is
    /// following ProPresenter normally.
    static func staleHint(
        connection: ProPresenterConnectionStatus,
        playlist: PlaylistStatus
    ) -> String? {
        switch connection {
        case .disconnected:
            "Not connected"
        case .searching, .connecting:
            "Searching for ProPresenter…"
        case .connected:
            switch playlist {
            case .offline: "ProPresenter is not reachable"
            case let .failed(reason): reason
            case .idle, .loading, .ready, .unavailable: nil
            }
        }
    }
}
