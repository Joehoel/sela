import Foundation

// Decodable shapes for the ProPresenter HTTP API (7.9+). Only the fields Sela
// needs are modelled; every container decodes tolerantly (unknown fields are
// ignored, missing fields fall back to empty/`nil`) because the payloads differ
// per ProPresenter version.
// See `docs/research/propresenter-api.md` for the full endpoint survey.

/// The `{"uuid", "name", "index"}` triple ProPresenter uses to identify
/// playlists, playlist items and presentations.
struct ProPresenterObjectID: Decodable, Sendable, Equatable {
    var uuid: String
    var name: String
    var index: Int

    init(uuid: String = "", name: String = "", index: Int = 0) {
        self.uuid = uuid
        self.name = name
        self.index = index
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        uuid = try container.decodeIfPresent(String.self, forKey: .uuid) ?? ""
        name = try container.decodeIfPresent(String.self, forKey: .name) ?? ""
        index = try container.decodeIfPresent(Int.self, forKey: .index) ?? 0
    }

    private enum CodingKeys: String, CodingKey {
        case uuid, name, index
    }
}

/// `GET /version` — the healthcheck payload.
struct ProPresenterVersion: Decodable, Sendable, Equatable {
    let name: String?
    let platform: String?
    let osVersion: String?
    /// e.g. `"ProPresenter 7.13"` — used for feature gating.
    let hostDescription: String?
    let apiVersion: String?

    private enum CodingKeys: String, CodingKey {
        case name, platform
        case osVersion = "os_version"
        case hostDescription = "host_description"
        case apiVersion = "api_version"
    }
}

/// A node in the `GET /v1/playlists` tree: either a playlist or a folder
/// (`group`) that nests more nodes.
struct ProPresenterPlaylistNode: Decodable, Sendable, Equatable {
    let id: ProPresenterObjectID
    let type: Kind
    /// Child nodes; empty for leaf playlists.
    let playlists: [ProPresenterPlaylistNode]

    enum Kind: String, Decodable, Sendable {
        case playlist
        case group
        case unknown

        init(from decoder: Decoder) throws {
            let raw = try decoder.singleValueContainer().decode(String.self)
            self = Kind(rawValue: raw) ?? .unknown
        }
    }

    init(id: ProPresenterObjectID, type: Kind, playlists: [ProPresenterPlaylistNode] = []) {
        self.id = id
        self.type = type
        self.playlists = playlists
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(ProPresenterObjectID.self, forKey: .id) ?? ProPresenterObjectID()
        type = try container.decodeIfPresent(Kind.self, forKey: .type) ?? .unknown
        playlists = try container.decodeIfPresent([ProPresenterPlaylistNode].self, forKey: .playlists) ?? []
    }

    private enum CodingKeys: String, CodingKey {
        case id, type, playlists
    }
}

/// `GET /v1/playlist/{id}` — one playlist and its items.
struct ProPresenterPlaylist: Decodable, Sendable, Equatable {
    let id: ProPresenterObjectID
    let items: [ProPresenterPlaylistItem]

    init(id: ProPresenterObjectID, items: [ProPresenterPlaylistItem] = []) {
        self.id = id
        self.items = items
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(ProPresenterObjectID.self, forKey: .id) ?? ProPresenterObjectID()
        items = try container.decodeIfPresent([ProPresenterPlaylistItem].self, forKey: .items) ?? []
    }

    private enum CodingKeys: String, CodingKey {
        case id, items
    }
}

/// One row inside a playlist. `id.uuid` is the *item's* UUID; the presentation
/// is identified by `presentationUUID`.
struct ProPresenterPlaylistItem: Decodable, Sendable, Equatable {
    let id: ProPresenterObjectID
    let type: Kind
    let isHidden: Bool
    /// "The real UUID of the presentation, audio or media item" (nullable).
    let targetUUID: String?
    let presentationInfo: PresentationInfo?

    enum Kind: String, Decodable, Sendable {
        case presentation
        case placeholder
        case header
        case media
        case audio
        case livevideo
        case unknown

        init(from decoder: Decoder) throws {
            let raw = try decoder.singleValueContainer().decode(String.self)
            self = Kind(rawValue: raw) ?? .unknown
        }
    }

    struct PresentationInfo: Decodable, Sendable, Equatable {
        let presentationUUID: String?
        let arrangementName: String?

        init(presentationUUID: String?, arrangementName: String? = nil) {
            self.presentationUUID = presentationUUID
            self.arrangementName = arrangementName
        }

        private enum CodingKeys: String, CodingKey {
            case presentationUUID = "presentation_uuid"
            case arrangementName = "arrangement_name"
        }
    }

    /// The UUID to hand to `presentation(uuid:)`, or `nil` for rows that are not
    /// backed by a presentation (headers, media).
    var presentationUUID: String? {
        if let uuid = presentationInfo?.presentationUUID, !uuid.isEmpty { return uuid }
        if let uuid = targetUUID, !uuid.isEmpty { return uuid }
        return nil
    }

    init(
        id: ProPresenterObjectID,
        type: Kind,
        isHidden: Bool = false,
        targetUUID: String? = nil,
        presentationInfo: PresentationInfo? = nil
    ) {
        self.id = id
        self.type = type
        self.isHidden = isHidden
        self.targetUUID = targetUUID
        self.presentationInfo = presentationInfo
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(ProPresenterObjectID.self, forKey: .id) ?? ProPresenterObjectID()
        type = try container.decodeIfPresent(Kind.self, forKey: .type) ?? .unknown
        isHidden = try container.decodeIfPresent(Bool.self, forKey: .isHidden) ?? false
        targetUUID = try container.decodeIfPresent(String.self, forKey: .targetUUID)
        presentationInfo = try container.decodeIfPresent(PresentationInfo.self, forKey: .presentationInfo)
    }

    private enum CodingKeys: String, CodingKey {
        case id, type
        case isHidden = "is_hidden"
        case targetUUID = "target_uuid"
        case presentationInfo = "presentation_info"
    }
}

/// `GET /v1/playlist/focused` — and one layer of `GET /v1/playlist/active`.
struct ProPresenterPlaylistFocus: Decodable, Sendable, Equatable {
    let playlist: ProPresenterObjectID?
    let item: ProPresenterObjectID?

    init(playlist: ProPresenterObjectID?, item: ProPresenterObjectID? = nil) {
        self.playlist = playlist
        self.item = item
    }
}

/// `GET /v1/playlist/active` — the playlist owning the most recently triggered
/// cue, per layer.
struct ProPresenterActivePlaylist: Decodable, Sendable, Equatable {
    let presentation: ProPresenterPlaylistFocus?
    let announcements: ProPresenterPlaylistFocus?

    init(presentation: ProPresenterPlaylistFocus?, announcements: ProPresenterPlaylistFocus? = nil) {
        self.presentation = presentation
        self.announcements = announcements
    }
}

/// `GET /v1/presentation/{uuid}`. `presentationPath` — the absolute path of the
/// `.pro` file on disk — is what maps an API item back onto a Sela song.
struct ProPresenterPresentation: Decodable, Sendable, Equatable {
    let id: ProPresenterObjectID
    let presentationPath: String?
    let groups: [Group]
    let hasTimeline: Bool
    let destination: String?

    struct Group: Decodable, Sendable, Equatable {
        let name: String?
        let slides: [Slide]

        init(name: String?, slides: [Slide] = []) {
            self.name = name
            self.slides = slides
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            name = try container.decodeIfPresent(String.self, forKey: .name)
            slides = try container.decodeIfPresent([Slide].self, forKey: .slides) ?? []
        }

        private enum CodingKeys: String, CodingKey {
            case name, slides
        }
    }

    /// Slide text is readable but never writable through the API — editing stays
    /// on the `.pro` files.
    struct Slide: Decodable, Sendable, Equatable {
        /// Disabled slides are skipped by ProPresenter; missing means enabled.
        let enabled: Bool
        let text: String?
        let notes: String?
        let label: String?

        init(enabled: Bool = true, text: String?, notes: String? = nil, label: String? = nil) {
            self.enabled = enabled
            self.text = text
            self.notes = notes
            self.label = label
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            enabled = try container.decodeIfPresent(Bool.self, forKey: .enabled) ?? true
            text = try container.decodeIfPresent(String.self, forKey: .text)
            notes = try container.decodeIfPresent(String.self, forKey: .notes)
            label = try container.decodeIfPresent(String.self, forKey: .label)
        }

        private enum CodingKeys: String, CodingKey {
            case enabled, text, notes, label
        }
    }

    init(
        id: ProPresenterObjectID,
        presentationPath: String?,
        groups: [Group] = [],
        hasTimeline: Bool = false,
        destination: String? = nil
    ) {
        self.id = id
        self.presentationPath = presentationPath
        self.groups = groups
        self.hasTimeline = hasTimeline
        self.destination = destination
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(ProPresenterObjectID.self, forKey: .id) ?? ProPresenterObjectID()
        presentationPath = try container.decodeIfPresent(String.self, forKey: .presentationPath)
        groups = try container.decodeIfPresent([Group].self, forKey: .groups) ?? []
        hasTimeline = try container.decodeIfPresent(Bool.self, forKey: .hasTimeline) ?? false
        destination = try container.decodeIfPresent(String.self, forKey: .destination)
    }

    private enum CodingKeys: String, CodingKey {
        case id, groups, destination
        case presentationPath = "presentation_path"
        case hasTimeline = "has_timeline"
    }
}

/// Presentation responses are wrapped in a `presentation` key on some builds and
/// returned bare on others; this envelope accepts both.
struct ProPresenterPresentationEnvelope: Decodable, Sendable {
    let presentation: ProPresenterPresentation

    init(from decoder: Decoder) throws {
        if let container = try? decoder.container(keyedBy: CodingKeys.self),
           let wrapped = try? container.decodeIfPresent(ProPresenterPresentation.self, forKey: .presentation) {
            presentation = wrapped
        } else {
            presentation = try ProPresenterPresentation(from: decoder)
        }
    }

    private enum CodingKeys: String, CodingKey {
        case presentation
    }
}

/// One update from `POST /v1/status/updates`: the endpoint that changed plus its
/// regular payload, kept as raw JSON so callers decode only what they need.
struct ProPresenterStatusUpdate: Sendable, Equatable {
    /// e.g. `"/v1/playlist/focused"`.
    let url: String
    let payload: Data

    func decode<T: Decodable>(_ type: T.Type, using decoder: JSONDecoder = JSONDecoder()) throws -> T {
        do {
            return try decoder.decode(T.self, from: payload)
        } catch {
            throw ProPresenterAPIError.decodingFailed(String(describing: error))
        }
    }
}
