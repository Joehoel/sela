import Foundation
@testable import Sela

/// An in-memory ProPresenter: a route table for the one-shot endpoints and
/// scripted chunked streams for the update endpoints.
final class FakeProPresenter: @unchecked Sendable {
    private let lock = NSLock()

    private var storage = Storage()

    private struct Storage {
        var focused: String?
        var active: String?
        var playlists: [String: String] = [:]
        var playlistTree: String?
        var presentations: [String: String] = [:]
        var focusUpdates: [String] = []
        var contentChanges = false
        var statusStreamFails = false
        var isUnreachable = false
        var openedStreamPaths: [String] = []
        var requestedPaths: [String] = []
        var focusStreamOpened = false
        var contentStreamOpened = false
    }

    /// Runs the first time the focus stream is opened — the hook tests use to
    /// change ProPresenter's state "while" Sela is listening.
    var onFocusStreamOpened: (@Sendable (FakeProPresenter) -> Void)?
    /// Same, for the per-playlist content stream.
    var onContentStreamOpened: (@Sendable (FakeProPresenter) -> Void)?
    /// Runs before every one-shot response, and may suspend — which is how a
    /// test gets to cancel a refresh while it is halfway through resolving.
    var beforeResponse: (@Sendable (String) async -> Void)?

    var focused: String? {
        get { withLock { $0.focused } }
        set { withLock { $0.focused = newValue } }
    }

    var active: String? {
        get { withLock { $0.active } }
        set { withLock { $0.active = newValue } }
    }

    var playlists: [String: String] {
        get { withLock { $0.playlists } }
        set { withLock { $0.playlists = newValue } }
    }

    /// The `GET /v1/playlists` tree, if the test needs one.
    var playlistTree: String? {
        get { withLock { $0.playlistTree } }
        set { withLock { $0.playlistTree = newValue } }
    }

    var presentations: [String: String] {
        get { withLock { $0.presentations } }
        set { withLock { $0.presentations = newValue } }
    }

    /// The one status-update document the focus stream emits, if any.
    var focusUpdate: String? {
        get { withLock { $0.focusUpdates.first } }
        set { withLock { $0.focusUpdates = newValue.map { [$0] } ?? [] } }
    }

    /// The status-update documents the focus stream emits, in order — several
    /// of them, because ProPresenter pushes the current state of every stream
    /// on connect and then again on every operator action.
    var focusUpdates: [String] {
        get { withLock { $0.focusUpdates } }
        set { withLock { $0.focusUpdates = newValue } }
    }

    /// Whether the per-playlist content stream pushes one `"change"` signal.
    var contentChanges: Bool {
        get { withLock { $0.contentChanges } }
        set { withLock { $0.contentChanges = newValue } }
    }

    /// Makes `POST /v1/status/updates` answer 400 — an older ProPresenter build
    /// that does not serve the aggregator, i.e. a stream that dies on open.
    var statusStreamFails: Bool {
        get { withLock { $0.statusStreamFails } }
        set { withLock { $0.statusStreamFails = newValue } }
    }

    /// Makes every one-shot request fail the way a crashed or hung ProPresenter
    /// does: a transport error rather than an answer.
    var isUnreachable: Bool {
        get { withLock { $0.isUnreachable } }
        set { withLock { $0.isUnreachable = newValue } }
    }

    var openedStreamPaths: [String] { withLock { $0.openedStreamPaths } }

    /// One-shot request paths, in order.
    var requestedPaths: [String] { withLock { $0.requestedPaths } }

    /// Lets the scripted streams fire once more — ProPresenter answering again
    /// after a stretch of failed opens.
    func rearmStreams() {
        withLock {
            $0.focusStreamOpened = false
            $0.contentStreamOpened = false
        }
    }

    private func withLock<T>(_ body: (inout Storage) -> T) -> T {
        lock.lock(); defer { lock.unlock() }
        return body(&storage)
    }

    // MARK: Client

    func client() -> ProPresenterAPIClient {
        ProPresenterAPIClient(
            baseURL: URL(string: "http://localhost:1025")!,
            transport: { [self] request in
                let path = request.url?.path ?? ""
                withLock { $0.requestedPaths.append(path) }
                await beforeResponse?(path)
                if isUnreachable { throw URLError(.cannotConnectToHost) }
                return respond(to: request, path: path)
            },
            streamTransport: { [self] request in stream(for: request) }
        )
    }

    private func respond(to request: URLRequest, path: String) -> (Data, URLResponse) {
        let body = body(for: path)
        let response = HTTPURLResponse(
            url: request.url!,
            statusCode: body == nil ? 404 : 200,
            httpVersion: nil,
            headerFields: nil
        )!
        return (Data((body ?? "").utf8), response)
    }

    private func body(for path: String) -> String? {
        switch path {
        case "/version":
            return #"{"host_description":"ProPresenter 7.13"}"#
        case "/v1/playlists":
            return playlistTree
        case "/v1/playlist/focused":
            return focused
        case "/v1/playlist/active":
            return active
        default:
            if let uuid = path.dropPrefixIfPresent("/v1/playlist/") {
                return playlists[uuid]
            }
            if let uuid = path.dropPrefixIfPresent("/v1/presentation/") {
                return presentations[uuid]
            }
            return nil
        }
    }

    // MARK: Streams

    /// The focus stream emits its scripted updates once; the content stream
    /// emits a bare `"change"` once. Every later open parks, so the controller's
    /// re-subscribe does not spin — except where the endpoint genuinely fails:
    /// the updates path of a playlist that no longer exists answers 404, and
    /// `statusStreamFails` makes the aggregator answer 400.
    private func stream(for request: URLRequest) -> (ProPresenterByteStream, URLResponse) {
        let path = request.url?.path ?? ""
        withLock { $0.openedStreamPaths.append(path) }

        var documents: [String] = []
        var status = 200
        if path == "/v1/status/updates" {
            if statusStreamFails {
                status = 400
            } else {
                let first = withLock { storage -> Bool in
                    defer { storage.focusStreamOpened = true }
                    return !storage.focusStreamOpened
                }
                if first { onFocusStreamOpened?(self) }
                documents = first ? focusUpdates : []
            }
        } else if let uuid = playlistUUID(inUpdatesPath: path) {
            if playlists[uuid] == nil {
                // The operator deleted this playlist in ProPresenter.
                status = 404
            } else {
                let first = withLock { storage -> Bool in
                    defer { storage.contentStreamOpened = true }
                    return !storage.contentStreamOpened
                }
                if first { onContentStreamOpened?(self) }
                documents = first && contentChanges ? ["\"change\""] : []
            }
        }

        let response = HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: nil)!
        let stream = ProPresenterByteStream { continuation in
            for document in documents {
                for byte in Data(document.utf8) { continuation.yield(byte) }
            }
            // Parking streams stay open until the consumer cancels.
            if !documents.isEmpty || status != 200 { continuation.finish() }
        }
        return (stream, response)
    }

    /// The playlist uuid in `/v1/playlist/{uuid}/updates`, if that is the path.
    private func playlistUUID(inUpdatesPath path: String) -> String? {
        guard let rest = path.dropPrefixIfPresent("/v1/playlist/"), rest.hasSuffix("/updates") else {
            return nil
        }
        return String(rest.dropLast("/updates".count)).removingPercentEncoding ?? rest
    }

    // MARK: JSON builders

    static func focusJSON(uuid: String, name: String) -> String {
        """
        {"playlist":{"uuid":"\(uuid)","name":"\(name)","index":0},\
        "item":{"uuid":"ITEM","name":"Item","index":0}}
        """
    }

    static func activeJSON(uuid: String, name: String) -> String {
        """
        {"presentation":{"playlist":{"uuid":"\(uuid)","name":"\(name)","index":0},\
        "item":{"uuid":"ITEM","name":"Item","index":0}}}
        """
    }

    static func playlistJSON(uuid: String, name: String, items: [String]) -> String {
        """
        {"id":{"uuid":"\(uuid)","name":"\(name)","index":0},"items":[\(items.joined(separator: ","))]}
        """
    }

    static func headerItem(index: Int, name: String) -> String {
        #"{"id":{"uuid":"H\#(index)","name":"\#(name)","index":\#(index)},"type":"header"}"#
    }

    static func mediaItem(index: Int, name: String) -> String {
        #"{"id":{"uuid":"M\#(index)","name":"\#(name)","index":\#(index)},"type":"media"}"#
    }

    static func presentationItem(index: Int, name: String, uuid: String, isHidden: Bool = false) -> String {
        """
        {"id":{"uuid":"I\(index)","name":"\(name)","index":\(index)},"type":"presentation",\
        "is_hidden":\(isHidden),"presentation_info":{"presentation_uuid":"\(uuid)"}}
        """
    }

    static func presentationJSON(uuid: String, path: String?) -> String {
        let pathField = path.map { #""presentation_path":"\#($0)","# } ?? ""
        return """
        {"presentation":{"id":{"uuid":"\(uuid)","name":"Presentation","index":0},\
        \(pathField)"groups":[]}}
        """
    }

    static func statusUpdateJSON(url: String, data: String) -> String {
        #"{"url":"\#(url)","data":\#(data)}"#
    }
}

private extension String {
    /// Returns the remainder after `prefix`, or `nil` when the prefix is absent.
    func dropPrefixIfPresent(_ prefix: String) -> String? {
        guard hasPrefix(prefix) else { return nil }
        return String(dropFirst(prefix.count))
    }
}

/// Stands in for reading a `.pro` file: only the listed paths are readable,
/// everything else throws the way a missing or corrupt file would.
final class FakeSongReader: @unchecked Sendable {
    private let lock = NSLock()
    private let readable: [String: String]
    private var paths: [String] = []

    /// Paths the controller tried to read, in order.
    var readPaths: [String] {
        lock.lock(); defer { lock.unlock() }
        return paths
    }

    init(readable: [String: String] = [:]) {
        self.readable = readable
    }

    func read(_ url: URL) throws -> ParsedSong {
        lock.lock()
        paths.append(url.path)
        lock.unlock()

        guard let title = readable[url.path] else {
            throw CocoaError(.fileReadNoSuchFile)
        }
        return ParsedSong(
            id: title,
            title: title,
            author: "",
            slideGroups: [
                ParsedSlideGroup(
                    id: "\(title)-g1",
                    name: "Verse 1",
                    slides: [
                        ParsedSlide(
                            id: "\(title)-s1",
                            lines: [ParsedLine(id: "\(title)-l1", original: title, translation: "")]
                        ),
                    ]
                ),
            ],
            filePath: url
        )
    }
}
