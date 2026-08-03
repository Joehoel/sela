import Foundation
import Network
import Observation

/// How Sela looks for the ProPresenter API.
enum ProPresenterConnectionMode: String, CaseIterable, Sendable {
    /// Last known endpoint, then Bonjour, then the usual localhost ports.
    case automatic
    /// Exactly the host and port configured in Settings.
    case manual

    var displayName: String {
        switch self {
        case .automatic: "Automatic"
        case .manual: "Manual"
        }
    }
}

/// A `host:port` pair the ProPresenter API might live on.
struct ProPresenterEndpoint: Sendable, Hashable {
    var host: String
    var port: Int

    var displayName: String { "\(host):\(port)" }
}

/// Where the connection is in its search/connect cycle.
enum ProPresenterConnectionStatus: Sendable, Equatable {
    /// The loop is not running (app start, or explicitly stopped).
    case disconnected
    /// Looking for an endpoint that answers, including the backoff waits.
    case searching
    /// Verifying one candidate with `GET /version`.
    case connecting(ProPresenterEndpoint)
    /// Verified; `ProPresenterConnection.client` is ready to use.
    case connected(ProPresenterEndpoint, ProPresenterVersion)

    var isConnected: Bool {
        if case .connected = self { return true }
        return false
    }

    /// One line for the Settings indicator.
    var summary: String {
        switch self {
        case .disconnected:
            "Not connected"
        case .searching:
            "Searching…"
        case let .connecting(endpoint):
            "Connecting to \(endpoint.displayName)…"
        case let .connected(endpoint, version):
            "\(version.hostDescription ?? "ProPresenter") at \(endpoint.displayName)"
        }
    }
}

/// Finds the ProPresenter API, keeps a verified `ProPresenterAPIClient` around,
/// and reconnects with backoff for as long as the app runs.
///
/// Everything slow or environmental is injected — the client factory, Bonjour
/// discovery and sleeping — so the state machine runs offline in tests. The same
/// transport-injection idiom as `ProPresenterAPIClient` and `DeepLLanguageModel`.
@Observable @MainActor
final class ProPresenterConnection {
    private(set) var status: ProPresenterConnectionStatus = .disconnected

    /// The client for the live connection; `nil` unless `status` is `.connected`.
    private(set) var client: ProPresenterAPIClient?

    private let preferences: UserPreferences
    private let makeClient: @Sendable (ProPresenterEndpoint) -> ProPresenterAPIClient?
    private let discover: @Sendable () async -> [ProPresenterEndpoint]
    private let wait: @Sendable (Duration) async throws -> Void

    @ObservationIgnored private var loopTask: Task<Void, Never>?
    /// Bumped by every `start()`/`stop()`, so a probe that finishes after the
    /// user changed the settings cannot write stale state.
    @ObservationIgnored private var generation = 0
    /// Resumed when a connection is dropped, to wake the waiting loop.
    @ObservationIgnored private var disconnectSignal: CheckedContinuation<Void, Never>?
    /// A disconnect that arrived before the loop parked; consumed on the next wait.
    @ObservationIgnored private var disconnectPending = false

    init(
        preferences: UserPreferences,
        makeClient: @escaping @Sendable (ProPresenterEndpoint) -> ProPresenterAPIClient? = { endpoint in
            ProPresenterAPIClient(host: endpoint.host, port: endpoint.port)
        },
        discover: @escaping @Sendable () async -> [ProPresenterEndpoint] = {
            await ProPresenterBonjourDiscovery.endpoints()
        },
        wait: @escaping @Sendable (Duration) async throws -> Void = { duration in
            try await Task.sleep(for: duration)
        }
    ) {
        self.preferences = preferences
        self.makeClient = makeClient
        self.discover = discover
        self.wait = wait
    }

    /// The localhost ports auto mode falls back to: 1025 is ProPresenter's
    /// default, 50727 is the other port seen in the wild.
    static let localhostCandidates = [
        ProPresenterEndpoint(host: "localhost", port: 1025),
        ProPresenterEndpoint(host: "localhost", port: 50727),
    ]

    /// Reconnect delays: 1, 2, 4, 8, 16, then 30 seconds forever.
    static let maximumBackoff = Duration.seconds(30)

    static func backoffDelay(forAttempt attempt: Int) -> Duration {
        guard attempt > 1 else { return .seconds(1) }
        guard attempt < 6 else { return maximumBackoff }
        return min(.seconds(1 << (attempt - 1)), maximumBackoff)
    }

    // MARK: - Lifecycle

    /// Starts searching and keeps reconnecting until `stop()`. Idempotent.
    func start() {
        guard loopTask == nil else { return }
        disconnectPending = false
        generation += 1
        let generation = generation
        loopTask = Task { [weak self] in
            await self?.runLoop(generation: generation)
        }
    }

    /// Stops the loop and drops the client.
    func stop() {
        generation += 1
        loopTask?.cancel()
        loopTask = nil
        resumeDisconnectSignal()
        client = nil
        status = .disconnected
    }

    /// Drops the current connection and searches again — after the connection
    /// settings change, or when a stream the app was following died.
    func reconnect() {
        let wasRunning = loopTask != nil
        stop()
        if wasRunning { start() }
    }

    // MARK: - State machine

    /// The connect/reconnect loop. `start()` runs this in a task; tests await it
    /// directly with an injected `wait` that ends the loop.
    func runLoop(generation: Int) async {
        var attempt = 0
        while !Task.isCancelled, generation == self.generation {
            if await connectOnce() {
                attempt = 0
                await waitForDisconnect()
            } else {
                attempt += 1
                do {
                    try await wait(Self.backoffDelay(forAttempt: attempt))
                } catch {
                    return
                }
            }
        }
    }

    /// Walks the candidate endpoints once. Returns `true` when one answered
    /// `GET /version`; otherwise the status is left at `.searching`.
    @discardableResult
    func connectOnce() async -> Bool {
        let generation = generation
        client = nil
        apply(.searching, generation: generation)

        let connected: Bool
        switch preferences.proPresenterMode {
        case .manual:
            connected = await connectManually(generation: generation)
        case .automatic:
            connected = await connectAutomatically(generation: generation)
        }

        if !connected { apply(.searching, generation: generation) }
        return connected
    }

    private func connectManually(generation: Int) async -> Bool {
        guard let endpoint = preferences.proPresenterManualEndpoint else { return false }
        return await verify(endpoint, generation: generation)
    }

    private func connectAutomatically(generation: Int) async -> Bool {
        // The last known endpoint first: it costs one request, while Bonjour
        // browsing always spends its full budget.
        let lastKnown = preferences.proPresenterLastKnownEndpoint
        if let lastKnown, await verify(lastKnown, generation: generation) { return true }
        guard generation == self.generation else { return false }

        for endpoint in automaticCandidates(discovered: await discover()) where endpoint != lastKnown {
            if await verify(endpoint, generation: generation) { return true }
            guard generation == self.generation else { return false }
        }
        return false
    }

    /// The endpoints auto mode probes, in order: last known, whatever Bonjour
    /// found, then the usual localhost ports. Duplicates drop out.
    func automaticCandidates(discovered: [ProPresenterEndpoint]) -> [ProPresenterEndpoint] {
        let lastKnown = preferences.proPresenterLastKnownEndpoint.map { [$0] } ?? []
        var seen: Set<ProPresenterEndpoint> = []
        return (lastKnown + discovered + Self.localhostCandidates).filter { seen.insert($0).inserted }
    }

    /// Probes one candidate. A closed port is the normal case while searching,
    /// so failures are silent.
    private func verify(_ endpoint: ProPresenterEndpoint, generation: Int) async -> Bool {
        guard let candidate = makeClient(endpoint) else { return false }
        apply(.connecting(endpoint), generation: generation)
        guard let version = try? await candidate.version() else { return false }
        guard generation == self.generation else { return false }

        client = candidate
        status = .connected(endpoint, version)
        preferences.proPresenterLastKnownEndpoint = endpoint
        return true
    }

    private func apply(_ status: ProPresenterConnectionStatus, generation: Int) {
        guard generation == self.generation else { return }
        self.status = status
    }

    // MARK: - Disconnect signalling

    private func waitForDisconnect() async {
        guard !disconnectPending else {
            disconnectPending = false
            return
        }
        await withCheckedContinuation { continuation in
            disconnectSignal = continuation
        }
    }

    /// Wakes the parked loop, or remembers the signal for a loop that is about
    /// to park — a disconnect can land while a probe is still in flight.
    private func resumeDisconnectSignal() {
        guard let signal = disconnectSignal else {
            disconnectPending = true
            return
        }
        disconnectSignal = nil
        signal.resume()
    }
}

/// Finds ProPresenter instances on the local network.
///
/// ProPresenter advertises its remote and stage-display services over Bonjour on
/// the same port as the HTTP API, so a resolved service is a candidate endpoint —
/// candidates are still verified with `GET /version` before use.
enum ProPresenterBonjourDiscovery {
    /// The service types ProPresenter 7 is known to advertise.
    static let serviceTypes = ["_pro7proremote._tcp", "_pro7stagedsp._tcp", "_propresenter._tcp"]

    /// How long to browse, and how long to wait for one service to resolve.
    static let defaultTimeout = Duration.seconds(2)

    /// Browses every known service type in parallel and resolves the results to
    /// `host:port`. Never throws: no answer simply means an empty list.
    static func endpoints(timeout: Duration = defaultTimeout) async -> [ProPresenterEndpoint] {
        await withTaskGroup(of: [ProPresenterEndpoint].self) { group in
            for type in serviceTypes {
                group.addTask { await endpoints(ofType: type, timeout: timeout) }
            }
            var seen: Set<ProPresenterEndpoint> = []
            var found: [ProPresenterEndpoint] = []
            for await endpoints in group {
                found.append(contentsOf: endpoints.filter { seen.insert($0).inserted })
            }
            return found
        }
    }

    private static func endpoints(ofType type: String, timeout: Duration) async -> [ProPresenterEndpoint] {
        var found: [ProPresenterEndpoint] = []
        for service in await browse(type: type, timeout: timeout) {
            if let endpoint = await resolve(service, timeout: timeout) { found.append(endpoint) }
        }
        return found
    }

    /// Collects the Bonjour results seen within `timeout`.
    private static func browse(type: String, timeout: Duration) async -> [NWBrowser.Result] {
        let collector = ResultCollector()
        let browser = NWBrowser(for: .bonjour(type: type, domain: nil), using: .tcp)
        browser.browseResultsChangedHandler = { results, _ in collector.store(Array(results)) }
        browser.start(queue: .global())
        try? await Task.sleep(for: timeout)
        browser.cancel()
        return collector.results()
    }

    /// Bonjour results carry no port, so the service is resolved by opening a
    /// TCP connection and reading back the endpoint it landed on.
    private static func resolve(_ result: NWBrowser.Result, timeout: Duration) async -> ProPresenterEndpoint? {
        await withCheckedContinuation { continuation in
            let box = ResolutionBox(continuation)
            let connection = NWConnection(to: result.endpoint, using: .tcp)
            connection.stateUpdateHandler = { state in
                switch state {
                case .ready:
                    box.finish(endpoint(of: connection))
                    connection.cancel()
                case .failed, .cancelled:
                    box.finish(nil)
                default:
                    break
                }
            }
            connection.start(queue: .global())
            DispatchQueue.global().asyncAfter(deadline: .now() + timeout.seconds) {
                box.finish(nil)
                connection.cancel()
            }
        }
    }

    /// The remote `host:port` a ready connection resolved to. IPv6-only services
    /// are skipped: their scoped addresses do not survive a round trip through a
    /// URL, and localhost/manual entry covers those cases.
    private static func endpoint(of connection: NWConnection) -> ProPresenterEndpoint? {
        guard case let .hostPort(host, port) = connection.currentPath?.remoteEndpoint else { return nil }
        let name: String? = switch host {
        case let .ipv4(address): "\(address)"
        case let .name(name, _): name
        default: nil
        }
        guard let name, !name.isEmpty else { return nil }
        return ProPresenterEndpoint(host: name, port: Int(port.rawValue))
    }

    /// Bonjour callbacks arrive on a dispatch queue; this keeps the last set of
    /// results readable from the awaiting task.
    private final class ResultCollector: @unchecked Sendable {
        private let lock = NSLock()
        private var stored: [NWBrowser.Result] = []

        func store(_ results: [NWBrowser.Result]) {
            lock.lock(); defer { lock.unlock() }
            stored = results
        }

        func results() -> [NWBrowser.Result] {
            lock.lock(); defer { lock.unlock() }
            return stored
        }
    }

    /// Resolution finishes on whichever comes first — ready, failure or the
    /// timeout — so the continuation is guarded against a second resume.
    private final class ResolutionBox: @unchecked Sendable {
        private let lock = NSLock()
        private var continuation: CheckedContinuation<ProPresenterEndpoint?, Never>?

        init(_ continuation: CheckedContinuation<ProPresenterEndpoint?, Never>) {
            self.continuation = continuation
        }

        func finish(_ endpoint: ProPresenterEndpoint?) {
            lock.lock()
            let pending = continuation
            continuation = nil
            lock.unlock()
            pending?.resume(returning: endpoint)
        }
    }
}

private extension Duration {
    var seconds: Double {
        Double(components.seconds) + Double(components.attoseconds) / 1e18
    }
}
