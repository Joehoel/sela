import Foundation
@testable import Sela
import Testing

/// The ProPresenter HTTP API client, exercised entirely with injected
/// transports: JSON fixtures per endpoint, plus a byte stream for the chunked
/// endpoints. Nothing here touches the network.
struct ProPresenterAPIClientTests {
    private static let baseURL = URL(string: "http://localhost:1025")!

    // MARK: - Request building

    @Test("builds GET requests against the configured base URL")
    func buildsRequests() throws {
        let client = ProPresenterAPIClient(baseURL: Self.baseURL)
        let request = try client.makeRequest(path: "v1/playlists")
        #expect(request.httpMethod == "GET")
        #expect(request.url?.absoluteString == "http://localhost:1025/v1/playlists")
        #expect(request.value(forHTTPHeaderField: "Accept") == "application/json")
    }

    @Test("host/port convenience init produces a plain-HTTP base URL")
    func hostPortInit() throws {
        let client = try #require(ProPresenterAPIClient(host: "10.0.0.5", port: 50727))
        #expect(client.baseURL.absoluteString == "http://10.0.0.5:50727")
    }

    @Test("percent-encodes playlist ids that are names")
    func escapesPathComponents() async throws {
        let captured = RequestCapture()
        let client = ProPresenterAPIClient(baseURL: Self.baseURL) { request in
            captured.store(request)
            return (Data(#"{"id":{"uuid":"1","name":"Sunday Service","index":0},"items":[]}"#.utf8), Self.ok)
        }
        _ = try await client.playlist(id: "Sunday Service")
        #expect(captured.url() == "http://localhost:1025/v1/playlist/Sunday%20Service")
    }

    // MARK: - version

    @Test("version parses the healthcheck payload")
    func parsesVersion() async throws {
        let json = """
        {"name":"Mac Studio","platform":"mac","os_version":"15.3",
         "host_description":"ProPresenter 7.13","api_version":"v1"}
        """
        let captured = RequestCapture()
        let client = ProPresenterAPIClient(baseURL: Self.baseURL) { request in
            captured.store(request)
            return (Data(json.utf8), Self.ok)
        }
        let version = try await client.version()
        #expect(version.hostDescription == "ProPresenter 7.13")
        #expect(version.apiVersion == "v1")
        #expect(version.osVersion == "15.3")
        // `/version` is the one endpoint without the /v1 prefix.
        #expect(captured.url() == "http://localhost:1025/version")
    }

    // MARK: - playlists

    @Test("playlists parses a tree with nested groups")
    func parsesPlaylistTree() async throws {
        let json = """
        [
          {"id":{"index":0,"name":"Sunday Service","uuid":"AAA"},"type":"playlist"},
          {"id":{"index":1,"name":"2026","uuid":"BBB"},"type":"group","playlists":[
            {"id":{"index":0,"name":"Januari","uuid":"CCC"},"type":"group","playlists":[
              {"id":{"index":0,"name":"04-01","uuid":"DDD"},"type":"playlist"}
            ]},
            {"id":{"index":1,"name":"Kerst","uuid":"EEE"},"type":"playlist"}
          ]}
        ]
        """
        let client = ProPresenterAPIClient(baseURL: Self.baseURL) { _ in (Data(json.utf8), Self.ok) }
        let nodes = try await client.playlists()

        #expect(nodes.count == 2)
        #expect(nodes[0].type == .playlist)
        #expect(nodes[0].id.name == "Sunday Service")
        #expect(nodes[0].playlists.isEmpty)

        let group = nodes[1]
        #expect(group.type == .group)
        #expect(group.playlists.count == 2)
        #expect(group.playlists[0].type == .group)
        #expect(group.playlists[0].playlists[0].id.uuid == "DDD")
        #expect(group.playlists[1].type == .playlist)
    }

    @Test("unknown node types decode as .unknown instead of failing")
    func unknownNodeType() async throws {
        let json = #"[{"id":{"uuid":"X"},"type":"something-new"}]"#
        let client = ProPresenterAPIClient(baseURL: Self.baseURL) { _ in (Data(json.utf8), Self.ok) }
        let nodes = try await client.playlists()
        #expect(nodes[0].type == .unknown)
        #expect(nodes[0].id.name.isEmpty)
        #expect(nodes[0].id.index == 0)
    }

    // MARK: - playlist(id:)

    @Test("playlist parses headers, presentations and media")
    func parsesPlaylistItems() async throws {
        let json = """
        {
          "id":{"index":0,"name":"Sunday Service","uuid":"942C"},
          "items":[
            {"id":{"index":0,"name":"Songs","uuid":""},"type":"header",
             "header_color":{"red":1,"green":0,"blue":0,"alpha":1}},
            {"id":{"index":1,"name":"Amazing Grace","uuid":"ITEM-1"},"type":"presentation",
             "is_hidden":false,"is_pco":false,
             "presentation_info":{"presentation_uuid":"PRES-1","arrangement_name":"My Chains"}},
            {"id":{"index":2,"name":"Countdown","uuid":"ITEM-2"},"type":"media",
             "target_uuid":"MEDIA-1"},
            {"id":{"index":3,"name":"Hidden Song","uuid":"ITEM-3"},"type":"presentation",
             "is_hidden":true,"target_uuid":"PRES-2"}
          ]
        }
        """
        let client = ProPresenterAPIClient(baseURL: Self.baseURL) { _ in (Data(json.utf8), Self.ok) }
        let playlist = try await client.playlist(id: "942C")

        #expect(playlist.id.name == "Sunday Service")
        #expect(playlist.items.count == 4)

        #expect(playlist.items[0].type == .header)
        #expect(playlist.items[0].id.name == "Songs")
        #expect(playlist.items[0].presentationUUID == nil)

        let song = playlist.items[1]
        #expect(song.type == .presentation)
        #expect(song.isHidden == false)
        #expect(song.presentationUUID == "PRES-1")
        #expect(song.presentationInfo?.arrangementName == "My Chains")

        #expect(playlist.items[2].type == .media)
        #expect(playlist.items[2].presentationUUID == "MEDIA-1")

        // Without presentation_info the target_uuid is the presentation.
        #expect(playlist.items[3].isHidden)
        #expect(playlist.items[3].presentationUUID == "PRES-2")
    }

    // MARK: - focused / active

    @Test("focusedPlaylist parses playlist and item")
    func parsesFocusedPlaylist() async throws {
        let json = """
        {"playlist":{"index":3,"name":"Sunday Service","uuid":"AAA"},
         "item":{"index":1,"name":"Amazing Grace","uuid":"ITEM-1"}}
        """
        let captured = RequestCapture()
        let client = ProPresenterAPIClient(baseURL: Self.baseURL) { request in
            captured.store(request)
            return (Data(json.utf8), Self.ok)
        }
        let focus = try await client.focusedPlaylist()
        #expect(focus.playlist?.uuid == "AAA")
        #expect(focus.playlist?.index == 3)
        #expect(focus.item?.name == "Amazing Grace")
        #expect(captured.url() == "http://localhost:1025/v1/playlist/focused")
    }

    @Test("activePlaylist parses both layers and tolerates a missing one")
    func parsesActivePlaylist() async throws {
        let json = """
        {"presentation":{"playlist":{"index":0,"name":"Sunday Service","uuid":"AAA"},
                         "item":{"index":2,"name":"Way Maker","uuid":"ITEM-2"}},
         "announcements":{"playlist":null,"item":null}}
        """
        let client = ProPresenterAPIClient(baseURL: Self.baseURL) { _ in (Data(json.utf8), Self.ok) }
        let active = try await client.activePlaylist()
        #expect(active.presentation?.playlist?.name == "Sunday Service")
        #expect(active.presentation?.item?.uuid == "ITEM-2")
        #expect(active.announcements?.playlist == nil)
    }

    // MARK: - presentation

    @Test("presentation exposes presentation_path and slide text")
    func parsesPresentation() async throws {
        let json = """
        {"presentation":{
          "id":{"uuid":"PRES-1","name":"Amazing Grace","index":4},
          "groups":[
            {"name":"Verse 1","color":{"red":0,"green":0,"blue":1,"alpha":1},
             "slides":[{"enabled":true,"notes":"","text":"Amazing grace","label":"V1","size":{}}]},
            {"name":"Chorus","slides":[{"enabled":true,"text":"My chains are gone"}]}
          ],
          "has_timeline":false,
          "presentation_path":"/Users/me/Documents/ProPresenter/Libraries/Default/Amazing Grace.pro",
          "destination":"presentation"}}
        """
        let captured = RequestCapture()
        let client = ProPresenterAPIClient(baseURL: Self.baseURL) { request in
            captured.store(request)
            return (Data(json.utf8), Self.ok)
        }
        let presentation = try await client.presentation(uuid: "PRES-1")

        #expect(captured.url() == "http://localhost:1025/v1/presentation/PRES-1")
        #expect(presentation.id.name == "Amazing Grace")
        #expect(
            presentation.presentationPath
                == "/Users/me/Documents/ProPresenter/Libraries/Default/Amazing Grace.pro"
        )
        #expect(presentation.groups.count == 2)
        #expect(presentation.groups[0].name == "Verse 1")
        #expect(presentation.groups[0].slides[0].text == "Amazing grace")
        #expect(presentation.groups[1].slides[0].text == "My chains are gone")
        #expect(presentation.hasTimeline == false)
    }

    @Test("presentation also accepts an unwrapped body")
    func parsesUnwrappedPresentation() async throws {
        let json = """
        {"id":{"uuid":"PRES-2","name":"Way Maker","index":0},
         "presentation_path":"/Users/me/Documents/ProPresenter/Libraries/Default/Way Maker.pro"}
        """
        let client = ProPresenterAPIClient(baseURL: Self.baseURL) { _ in (Data(json.utf8), Self.ok) }
        let presentation = try await client.presentation(uuid: "PRES-2")
        #expect(presentation.id.uuid == "PRES-2")
        #expect(presentation.presentationPath?.hasSuffix("Way Maker.pro") == true)
        #expect(presentation.groups.isEmpty)
    }

    // MARK: - Errors

    @Test("a transport failure maps to .unreachable")
    func unreachable() async {
        struct Boom: Error {}
        let client = ProPresenterAPIClient(baseURL: Self.baseURL) { _ in throw Boom() }
        await #expect(throws: ProPresenterAPIError.self) {
            _ = try await client.version()
        }
    }

    @Test("a non-2xx status maps to .requestFailed")
    func httpFailure() async {
        let client = ProPresenterAPIClient(baseURL: Self.baseURL) { _ in
            (Data(), Self.response(status: 404))
        }
        await #expect(throws: ProPresenterAPIError.requestFailed(statusCode: 404)) {
            _ = try await client.playlist(id: "nope")
        }
    }

    @Test("a non-HTTP response maps to .invalidResponse")
    func invalidResponse() async {
        let client = ProPresenterAPIClient(baseURL: Self.baseURL) { request in
            (Data(), URLResponse(url: request.url!, mimeType: nil, expectedContentLength: 0, textEncodingName: nil))
        }
        await #expect(throws: ProPresenterAPIError.invalidResponse) {
            _ = try await client.version()
        }
    }

    @Test("a malformed body maps to .decodingFailed")
    func decodingFailure() async {
        let client = ProPresenterAPIClient(baseURL: Self.baseURL) { _ in
            (Data("not json".utf8), Self.ok)
        }
        await #expect(throws: ProPresenterAPIError.self) {
            _ = try await client.playlists()
        }
    }

    @Test("errors carry user-facing descriptions")
    func errorDescriptions() {
        #expect(ProPresenterAPIError.unreachable("timed out").errorDescription?.contains("timed out") == true)
        #expect(ProPresenterAPIError.requestFailed(statusCode: 500).errorDescription?.contains("500") == true)
        #expect(ProPresenterAPIError.invalidResponse.errorDescription?.contains("unexpected") == true)
        #expect(ProPresenterAPIError.decodingFailed("bad").errorDescription?.contains("bad") == true)
    }

    // MARK: - Helpers

    private static let ok = response(status: 200)

    private static func response(status: Int) -> HTTPURLResponse {
        HTTPURLResponse(url: baseURL, statusCode: status, httpVersion: nil, headerFields: nil)!
    }
}

/// The chunked endpoints: the aggregator stream, per-endpoint `?chunked=true`,
/// and the framing parser underneath them.
struct ProPresenterAPIStreamingTests {
    private static let baseURL = URL(string: "http://localhost:1025")!

    // MARK: - Streaming

    @Test("statusUpdates posts the requested streams and emits two updates")
    func statusUpdatesStream() async throws {
        let captured = RequestCapture()
        let chunks = [
            Data("""
            {"url":"/v1/playlist/focused","data":{"playlist":{"index":0,"name":"Sunday Service","uuid":"AAA"}}}
            """.utf8),
            Data("\r\n\r\n".utf8),
            Data("""
            {"url":"/v1/playlist/active","data":{"presentation":{"playlist":{"index":1,"name":"Kerst","uuid":"BBB"}}}}
            """.utf8),
            Data("\r\n\r\n".utf8),
        ]
        let client = ProPresenterAPIClient(
            baseURL: Self.baseURL,
            transport: { _ in (Data(), Self.ok) },
            streamTransport: { request in
                captured.store(request)
                return (Self.byteStream(chunks), Self.ok)
            }
        )

        var updates: [ProPresenterStatusUpdate] = []
        for try await update in client.statusUpdates(streams: ["playlist/focused", "playlist/active"]) {
            updates.append(update)
        }

        #expect(captured.method() == "POST")
        #expect(captured.url() == "http://localhost:1025/v1/status/updates")
        #expect(captured.body() == #"["playlist/focused","playlist/active"]"#)

        #expect(updates.count == 2)
        #expect(updates[0].url == "/v1/playlist/focused")
        let focus = try updates[0].decode(ProPresenterPlaylistFocus.self)
        #expect(focus.playlist?.uuid == "AAA")

        #expect(updates[1].url == "/v1/playlist/active")
        let active = try updates[1].decode(ProPresenterActivePlaylist.self)
        #expect(active.presentation?.playlist?.name == "Kerst")
    }

    @Test("chunkedUpdates decodes one element per chunk")
    func chunkedUpdatesStream() async throws {
        let captured = RequestCapture()
        let chunks = [
            Data(#"{"playlist":{"index":0,"name":"Sunday Service","uuid":"AAA"}}"#.utf8),
            Data(#"{"playlist":{"index":1,"name":"Kerst","uuid":"BBB"}}"#.utf8),
        ]
        let client = ProPresenterAPIClient(
            baseURL: Self.baseURL,
            transport: { _ in (Data(), Self.ok) },
            streamTransport: { request in
                captured.store(request)
                return (Self.byteStream(chunks), Self.ok)
            }
        )

        var names: [String] = []
        for try await focus in client.chunkedUpdates(path: "v1/playlist/focused", as: ProPresenterPlaylistFocus.self) {
            names.append(focus.playlist?.name ?? "")
        }

        #expect(names == ["Sunday Service", "Kerst"])
        #expect(captured.url() == "http://localhost:1025/v1/playlist/focused?chunked=true")
    }

    @Test("playlistUpdates percent-encodes a playlist id that is a name")
    func escapesPlaylistUpdatesPath() async throws {
        let captured = RequestCapture()
        let client = ProPresenterAPIClient(
            baseURL: Self.baseURL,
            transport: { _ in (Data(), Self.ok) },
            streamTransport: { request in
                captured.store(request)
                return (Self.byteStream([Data(#""change""#.utf8)]), Self.ok)
            }
        )

        var changes: [String] = []
        // A raw interpolation of this id makes URLComponents reject the path.
        for try await change in client.playlistUpdates(id: "Sunday Service") {
            changes.append(change)
        }

        #expect(changes == ["change"])
        #expect(
            captured.url()
                == "http://localhost:1025/v1/playlist/Sunday%20Service/updates?chunked=true"
        )
    }

    @Test("a failing stream response surfaces as a thrown error")
    func streamHTTPFailure() async {
        let client = ProPresenterAPIClient(
            baseURL: Self.baseURL,
            transport: { _ in (Data(), Self.ok) },
            streamTransport: { _ in (Self.byteStream([]), Self.response(status: 503)) }
        )
        await #expect(throws: ProPresenterAPIError.requestFailed(statusCode: 503)) {
            for try await _ in client.chunkedUpdates(path: "v1/playlist/focused", as: ProPresenterPlaylistFocus.self) {}
        }
    }

    // MARK: - Chunk parser

    @Test("the chunk parser frames documents split across byte boundaries")
    func chunkParserFraming() {
        var parser = ProPresenterJSONChunkParser()
        var documents: [String] = []
        let payload = #"{"a":1}"# + "\r\n\r\n" + #"{"b":{"c":"}}"}}"# + "\n" + #""change""#
        for byte in Data(payload.utf8) {
            if let document = parser.consume(byte) {
                documents.append(String(data: document, encoding: .utf8) ?? "")
            }
        }
        #expect(documents == [#"{"a":1}"#, #"{"b":{"c":"}}"}}"#, #""change""#])
    }

    @Test("the chunk parser ignores escaped quotes inside strings")
    func chunkParserEscapes() {
        var parser = ProPresenterJSONChunkParser()
        let documents = parser.consume(Data(#"{"text":"a \" }"}"#.utf8))
        #expect(documents.map { String(data: $0, encoding: .utf8) ?? "" } == [#"{"text":"a \" }"}"#])
    }

    // MARK: - Helpers

    private static let ok = response(status: 200)

    private static func response(status: Int) -> HTTPURLResponse {
        HTTPURLResponse(url: baseURL, statusCode: status, httpVersion: nil, headerFields: nil)!
    }

    /// Replays fixture chunks as the byte stream a chunked response would produce.
    private static func byteStream(_ chunks: [Data]) -> ProPresenterByteStream {
        ProPresenterByteStream { continuation in
            for chunk in chunks {
                for byte in chunk { continuation.yield(byte) }
            }
            continuation.finish()
        }
    }
}

/// Thread-safe capture of the request handed to an injected transport.
private final class RequestCapture: @unchecked Sendable {
    private let lock = NSLock()
    private var request: URLRequest?

    func store(_ request: URLRequest) {
        lock.lock(); defer { lock.unlock() }
        self.request = request
    }

    func url() -> String {
        lock.lock(); defer { lock.unlock() }
        return request?.url?.absoluteString ?? ""
    }

    func method() -> String {
        lock.lock(); defer { lock.unlock() }
        return request?.httpMethod ?? ""
    }

    func body() -> String {
        lock.lock(); defer { lock.unlock() }
        return request?.httpBody.flatMap { String(data: $0, encoding: .utf8) } ?? ""
    }
}
