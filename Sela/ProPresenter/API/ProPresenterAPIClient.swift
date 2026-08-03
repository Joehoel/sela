import Foundation

enum ProPresenterAPIError: LocalizedError, Equatable {
    /// The request never reached ProPresenter (network down, wrong port, app closed).
    case unreachable(String)
    /// ProPresenter answered with a non-2xx status.
    case requestFailed(statusCode: Int)
    /// The response was not an HTTP response, or the URL could not be built.
    case invalidResponse
    /// The body was not the JSON we expect.
    case decodingFailed(String)

    var errorDescription: String? {
        switch self {
        case let .unreachable(reason):
            "Could not reach ProPresenter: \(reason)"
        case let .requestFailed(statusCode):
            "ProPresenter request failed (HTTP \(statusCode))."
        case .invalidResponse:
            "ProPresenter returned an unexpected response."
        case let .decodingFailed(reason):
            "Could not read ProPresenter's response: \(reason)"
        }
    }
}

/// A stream of raw response bytes, as produced by `URLSession.bytes(for:)`.
/// Injectable so the chunked endpoints can be tested without the network.
typealias ProPresenterByteStream = AsyncThrowingStream<UInt8, Error>

/// A thin, testable client for the ProPresenter HTTP API (7.9+).
///
/// The API has no authentication and no TLS: everything is plain HTTP against
/// `http://<host>:<port>`. Both transports are injectable — the same idiom as
/// `DeepLLanguageModel` — so every endpoint can be exercised with fixtures.
///
/// See `docs/research/propresenter-api.md`.
struct ProPresenterAPIClient: Sendable {
    let baseURL: URL

    /// Sends a request and returns the whole body. Defaults to `URLSession.shared`.
    private let transport: @Sendable (URLRequest) async throws -> (Data, URLResponse)
    /// Sends a request and returns its body as it arrives, for chunked endpoints.
    private let streamTransport: @Sendable (URLRequest) async throws -> (ProPresenterByteStream, URLResponse)

    init(
        baseURL: URL,
        transport: @escaping @Sendable (URLRequest) async throws -> (Data, URLResponse) = { request in
            try await URLSession.shared.data(for: request)
        },
        streamTransport: @escaping @Sendable (URLRequest) async throws -> (ProPresenterByteStream, URLResponse) = { request in
            try await ProPresenterAPIClient.urlSessionByteStream(for: request)
        }
    ) {
        self.baseURL = baseURL
        self.transport = transport
        self.streamTransport = streamTransport
    }

    /// Convenience for the `host:port` pair the user configures in Settings.
    init?(host: String, port: Int) {
        var components = URLComponents()
        components.scheme = "http"
        components.host = host
        components.port = port
        guard let url = components.url else { return nil }
        self.init(baseURL: url)
    }

    /// Timeout for one-shot requests. Chunked streams stay open far longer.
    static let requestTimeout: TimeInterval = 10
    /// Chunked endpoints only emit when something changes, so the idle timeout
    /// has to be generous; reconnects are the caller's job.
    static let streamTimeout: TimeInterval = 86400

    // MARK: - Endpoints

    /// `GET /version` — healthcheck; the only path without the `/v1` prefix.
    func version() async throws -> ProPresenterVersion {
        try await get("version", as: ProPresenterVersion.self)
    }

    /// `GET /v1/playlists` — the playlist tree, with `group` nodes nesting children.
    func playlists() async throws -> [ProPresenterPlaylistNode] {
        try await get("v1/playlists", as: [ProPresenterPlaylistNode].self)
    }

    /// `GET /v1/playlist/{id}` — the items of one playlist. `id` may be a UUID,
    /// a name or an index; prefer the UUID.
    func playlist(id: String) async throws -> ProPresenterPlaylist {
        try await get("v1/playlist/\(Self.escape(id))", as: ProPresenterPlaylist.self)
    }

    /// `GET /v1/playlist/focused` — the playlist selected in ProPresenter's UI.
    func focusedPlaylist() async throws -> ProPresenterPlaylistFocus {
        try await get("v1/playlist/focused", as: ProPresenterPlaylistFocus.self)
    }

    /// `GET /v1/playlist/active` — the playlist owning the most recently triggered cue.
    func activePlaylist() async throws -> ProPresenterActivePlaylist {
        try await get("v1/playlist/active", as: ProPresenterActivePlaylist.self)
    }

    /// `GET /v1/presentation/{uuid}` — carries `presentation_path`, the absolute
    /// `.pro` path that maps an API item onto a file on disk.
    func presentation(uuid: String) async throws -> ProPresenterPresentation {
        let envelope = try await get(
            "v1/presentation/\(Self.escape(uuid))",
            as: ProPresenterPresentationEnvelope.self
        )
        return envelope.presentation
    }

    // MARK: - Streaming

    /// `POST /v1/status/updates` — one connection carrying updates for several
    /// endpoints, e.g. `["playlist/focused", "playlist/active"]`. Each element is
    /// one `{"url": ..., "data": ...}` document from the chunked response.
    func statusUpdates(streams: [String]) -> AsyncThrowingStream<ProPresenterStatusUpdate, Error> {
        documentStream(
            makeRequest: {
                var request = try makeRequest(path: "v1/status/updates", timeout: Self.streamTimeout)
                request.httpMethod = "POST"
                request.setValue("application/json", forHTTPHeaderField: "Content-Type")
                let encoder = JSONEncoder()
                encoder.outputFormatting = .withoutEscapingSlashes
                request.httpBody = try encoder.encode(streams)
                return request
            },
            transform: Self.statusUpdate(from:)
        )
    }

    /// `GET /v1/playlist/{id}/updates?chunked=true` — each chunk is the bare
    /// string `"change"`, meaning "re-fetch this playlist". The id goes through
    /// the same escaping as `playlist(id:)`, because it may be a name.
    func playlistUpdates(id: String) -> AsyncThrowingStream<String, Error> {
        chunkedUpdates(path: "v1/playlist/\(Self.escape(id))/updates", as: String.self)
    }

    /// A per-endpoint `?chunked=true` stream: every chunk is that endpoint's
    /// regular response body, pushed whenever the data changes.
    func chunkedUpdates<T: Decodable & Sendable>(
        path: String,
        as type: T.Type
    ) -> AsyncThrowingStream<T, Error> {
        documentStream(
            makeRequest: {
                try makeRequest(
                    path: path,
                    queryItems: [URLQueryItem(name: "chunked", value: "true")],
                    timeout: Self.streamTimeout
                )
            },
            transform: { document in try Self.decode(T.self, from: document) }
        )
    }

    // MARK: - Requests

    /// Builds a GET request for one API path. Exposed for testing.
    func makeRequest(
        path: String,
        queryItems: [URLQueryItem] = [],
        timeout: TimeInterval = ProPresenterAPIClient.requestTimeout
    ) throws -> URLRequest {
        guard var components = URLComponents(url: baseURL, resolvingAgainstBaseURL: false) else {
            throw ProPresenterAPIError.invalidResponse
        }
        let base = components.percentEncodedPath.hasSuffix("/")
            ? String(components.percentEncodedPath.dropLast())
            : components.percentEncodedPath
        let suffix = path.hasPrefix("/") ? String(path.dropFirst()) : path
        components.percentEncodedPath = base + "/" + suffix
        if !queryItems.isEmpty {
            components.queryItems = (components.queryItems ?? []) + queryItems
        }
        guard let url = components.url else { throw ProPresenterAPIError.invalidResponse }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = timeout
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        return request
    }

    private func get<T: Decodable>(_ path: String, as type: T.Type) async throws -> T {
        let request = try makeRequest(path: path)
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await transport(request)
        } catch let error as ProPresenterAPIError {
            throw error
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            throw ProPresenterAPIError.unreachable(error.localizedDescription)
        }
        try Self.validate(response)
        return try Self.decode(T.self, from: data)
    }

    private static func validate(_ response: URLResponse) throws {
        guard let http = response as? HTTPURLResponse else {
            throw ProPresenterAPIError.invalidResponse
        }
        guard (200 ..< 300).contains(http.statusCode) else {
            throw ProPresenterAPIError.requestFailed(statusCode: http.statusCode)
        }
    }

    private static func decode<T: Decodable>(_ type: T.Type, from data: Data) throws -> T {
        do {
            return try JSONDecoder().decode(T.self, from: data)
        } catch {
            throw ProPresenterAPIError.decodingFailed(String(describing: error))
        }
    }

    /// Percent-encodes one path segment; playlist ids may be names with spaces.
    private static func escape(_ component: String) -> String {
        let allowed = CharacterSet.urlPathAllowed.subtracting(CharacterSet(charactersIn: "/"))
        return component.addingPercentEncoding(withAllowedCharacters: allowed) ?? component
    }

    // MARK: - Chunk plumbing

    /// Opens a chunked connection and yields one element per complete JSON
    /// document in the response body. Cancelling the consuming task closes the
    /// connection.
    private func documentStream<T: Sendable>(
        makeRequest: @escaping @Sendable () throws -> URLRequest,
        transform: @escaping @Sendable (Data) throws -> T
    ) -> AsyncThrowingStream<T, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    let request = try makeRequest()
                    let bytes: ProPresenterByteStream
                    let response: URLResponse
                    do {
                        (bytes, response) = try await streamTransport(request)
                    } catch let error as ProPresenterAPIError {
                        throw error
                    } catch is CancellationError {
                        throw CancellationError()
                    } catch {
                        throw ProPresenterAPIError.unreachable(error.localizedDescription)
                    }
                    try Self.validate(response)

                    var parser = ProPresenterJSONChunkParser()
                    for try await byte in bytes {
                        guard let document = parser.consume(byte) else { continue }
                        continuation.yield(try transform(document))
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    /// Parses one `{"url": ..., "data": ...}` aggregator document, keeping `data`
    /// as raw JSON.
    static func statusUpdate(from document: Data) throws -> ProPresenterStatusUpdate {
        guard let object = try? JSONSerialization.jsonObject(with: document) as? [String: Any],
              let url = object["url"] as? String else {
            throw ProPresenterAPIError.decodingFailed("status update without a url")
        }
        let payload: Data
        do {
            payload = try JSONSerialization.data(
                withJSONObject: object["data"] ?? NSNull(),
                options: [.fragmentsAllowed]
            )
        } catch {
            throw ProPresenterAPIError.decodingFailed(String(describing: error))
        }
        return ProPresenterStatusUpdate(url: url, payload: payload)
    }

    /// Default streaming transport: `URLSession.bytes(for:)` re-shaped into a
    /// `Sendable` byte stream.
    static func urlSessionByteStream(for request: URLRequest) async throws -> (ProPresenterByteStream, URLResponse) {
        let (bytes, response) = try await URLSession.shared.bytes(for: request)
        let stream = ProPresenterByteStream { continuation in
            let task = Task {
                do {
                    for try await byte in bytes {
                        continuation.yield(byte)
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
        return (stream, response)
    }
}

/// Splits a chunked ProPresenter response into whole JSON documents.
///
/// HTTP chunk boundaries are invisible through `URLSession.bytes(for:)`, and the
/// aggregator separates its updates with CR-LF-CR-LF, so documents are framed by
/// balancing braces/brackets (or closing a top-level string, which is how
/// `/updates?chunked=true` sends its bare `"change"` signal). Whitespace between
/// documents is skipped.
struct ProPresenterJSONChunkParser {
    private var buffer: [UInt8] = []
    private var depth = 0
    private var started = false
    private var inString = false
    private var escaped = false

    /// Feeds one byte; returns a document as soon as one is complete.
    mutating func consume(_ byte: UInt8) -> Data? {
        if !started {
            // Whitespace, CR and LF between documents is framing, not content.
            guard !Self.isFraming(byte) else { return nil }
            started = true
            buffer.removeAll(keepingCapacity: true)
        }
        buffer.append(byte)
        return inString ? consumeInString(byte) : consumeStructural(byte)
    }

    private mutating func consumeInString(_ byte: UInt8) -> Data? {
        if escaped {
            escaped = false
        } else if byte == 0x5C { // backslash
            escaped = true
        } else if byte == 0x22 { // closing quote
            inString = false
            if depth == 0 { return emit() }
        }
        return nil
    }

    private mutating func consumeStructural(_ byte: UInt8) -> Data? {
        switch byte {
        case 0x22: // opening quote
            inString = true
        case 0x7B, 0x5B: // { [
            depth += 1
        case 0x7D, 0x5D: // } ]
            depth -= 1
            if depth <= 0 { return emit() }
        default:
            break
        }
        return nil
    }

    private static func isFraming(_ byte: UInt8) -> Bool {
        byte == 0x20 || byte == 0x09 || byte == 0x0D || byte == 0x0A
    }

    /// Feeds a whole buffer; returns every document it completes.
    mutating func consume(_ data: Data) -> [Data] {
        data.compactMap { consume($0) }
    }

    private mutating func emit() -> Data {
        let document = Data(buffer)
        buffer.removeAll(keepingCapacity: true)
        depth = 0
        started = false
        inString = false
        escaped = false
        return document
    }
}
