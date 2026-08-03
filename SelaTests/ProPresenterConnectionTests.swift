import Foundation
@testable import Sela
import Testing

/// The `GET /version` body every reachable stub answers with.
private let versionJSON = Data(#"{"host_description":"ProPresenter 7.13"}"#.utf8)

/// The connection state machine, driven entirely by injected fakes: a client
/// factory backed by stub transports, a stub Bonjour discovery and a recording
/// sleep. Nothing here touches the network or the clock.
@MainActor
struct ProPresenterConnectionTests {
    // MARK: - Fixtures

    private func makeDefaults() -> UserDefaults {
        UserDefaults(suiteName: "test.\(UUID().uuidString)")!
    }

    /// A client whose `GET /version` succeeds for `reachable` and fails everywhere else.
    private func makeClientFactory(
        reachable: Set<ProPresenterEndpoint>,
        probed: Probes
    ) -> @Sendable (ProPresenterEndpoint) -> ProPresenterAPIClient? {
        { endpoint in
            ProPresenterAPIClient(baseURL: URL(string: "http://\(endpoint.host):\(endpoint.port)")!) { request in
                probed.record(endpoint)
                guard reachable.contains(endpoint) else {
                    throw ProPresenterAPIError.unreachable("connection refused")
                }
                let response = HTTPURLResponse(
                    url: request.url!,
                    statusCode: 200,
                    httpVersion: nil,
                    headerFields: nil
                )!
                return (versionJSON, response)
            }
        }
    }

    private func makeConnection(
        preferences: UserPreferences,
        reachable: Set<ProPresenterEndpoint> = [],
        discovered: [ProPresenterEndpoint] = [],
        probed: Probes = Probes(),
        wait: @escaping @Sendable (Duration) async throws -> Void = { _ in }
    ) -> ProPresenterConnection {
        ProPresenterConnection(
            preferences: preferences,
            makeClient: makeClientFactory(reachable: reachable, probed: probed),
            discover: { discovered },
            wait: wait
        )
    }

    private static let localhost = ProPresenterEndpoint(host: "localhost", port: 1025)

    // MARK: - Connecting

    @Test("a reachable endpoint connects and exposes a client")
    func connectsToReachableEndpoint() async {
        let preferences = UserPreferences(defaults: makeDefaults())
        let connection = makeConnection(preferences: preferences, reachable: [Self.localhost])

        let connected = await connection.connectOnce()

        #expect(connected)
        #expect(connection.status.isConnected)
        #expect(connection.client?.baseURL.absoluteString == "http://localhost:1025")
        if case let .connected(endpoint, version) = connection.status {
            #expect(endpoint == Self.localhost)
            #expect(version.hostDescription == "ProPresenter 7.13")
        } else {
            Issue.record("expected a connected status, got \(connection.status)")
        }
    }

    @Test("a successful connection is remembered for the next launch")
    func remembersLastKnownEndpoint() async {
        let defaults = makeDefaults()
        let preferences = UserPreferences(defaults: defaults)
        let endpoint = ProPresenterEndpoint(host: "localhost", port: 50727)
        let connection = makeConnection(preferences: preferences, reachable: [endpoint])

        await connection.connectOnce()

        #expect(preferences.proPresenterLastKnownEndpoint == endpoint)
        #expect(UserPreferences(defaults: defaults).proPresenterLastKnownEndpoint == endpoint)
    }

    @Test("a failed probe leaves the connection searching, without a client")
    func failedProbeKeepsSearching() async {
        let preferences = UserPreferences(defaults: makeDefaults())
        let connection = makeConnection(preferences: preferences, reachable: [])

        let connected = await connection.connectOnce()

        #expect(!connected)
        #expect(connection.status == .searching)
        #expect(connection.client == nil)
    }

    // MARK: - Candidate order

    @Test("auto mode probes the last known endpoint, then Bonjour, then localhost")
    func candidateOrder() async {
        let preferences = UserPreferences(defaults: makeDefaults())
        let lastKnown = ProPresenterEndpoint(host: "10.0.0.5", port: 1025)
        let discovered = ProPresenterEndpoint(host: "10.0.0.9", port: 4242)
        preferences.proPresenterLastKnownEndpoint = lastKnown
        let probed = Probes()
        let connection = makeConnection(
            preferences: preferences,
            reachable: [],
            discovered: [discovered],
            probed: probed
        )

        await connection.connectOnce()

        #expect(probed.endpoints() == [lastKnown, discovered] + ProPresenterConnection.localhostCandidates)
    }

    @Test("the candidate list keeps its order and drops duplicates")
    func candidateListDeduplicates() {
        let preferences = UserPreferences(defaults: makeDefaults())
        preferences.proPresenterLastKnownEndpoint = Self.localhost
        let connection = makeConnection(preferences: preferences)

        let candidates = connection.automaticCandidates(discovered: [Self.localhost])

        #expect(candidates == ProPresenterConnection.localhostCandidates)
    }

    @Test("manual mode probes only the configured endpoint")
    func manualModeUsesConfiguredEndpoint() async {
        let preferences = UserPreferences(defaults: makeDefaults())
        preferences.proPresenterMode = .manual
        preferences.proPresenterHost = "10.0.0.5"
        preferences.proPresenterPort = 50727
        preferences.proPresenterLastKnownEndpoint = Self.localhost
        let manual = ProPresenterEndpoint(host: "10.0.0.5", port: 50727)
        let probed = Probes()
        let connection = makeConnection(preferences: preferences, reachable: [manual], probed: probed)

        let connected = await connection.connectOnce()

        #expect(connected)
        #expect(probed.endpoints() == [manual])
    }

    @Test("manual mode without a usable host never probes")
    func manualModeWithoutHost() async {
        let preferences = UserPreferences(defaults: makeDefaults())
        preferences.proPresenterMode = .manual
        preferences.proPresenterHost = "  "
        let probed = Probes()
        let connection = makeConnection(preferences: preferences, probed: probed)

        let connected = await connection.connectOnce()

        #expect(!connected)
        #expect(probed.endpoints().isEmpty)
        #expect(connection.status == .searching)
    }

    // MARK: - Backoff

    @Test("the backoff doubles up to a 30 second cap")
    func backoffSequence() {
        let delays = (1 ... 8).map { ProPresenterConnection.backoffDelay(forAttempt: $0) }
        #expect(delays == [1, 2, 4, 8, 16, 30, 30, 30].map { Duration.seconds($0) })
    }

    @Test("the loop retries with growing delays while nothing answers")
    func loopBacksOff() async {
        let preferences = UserPreferences(defaults: makeDefaults())
        let waits = Waits(stopAfter: 4)
        let connection = makeConnection(
            preferences: preferences,
            reachable: [],
            wait: { duration in try waits.record(duration) }
        )

        await connection.runLoop(generation: 0)

        #expect(waits.durations() == [1, 2, 4, 8].map { Duration.seconds($0) })
        #expect(connection.status == .searching)
    }

    @Test("the loop stops retrying once an endpoint answers")
    func loopStopsAfterConnecting() async {
        let preferences = UserPreferences(defaults: makeDefaults())
        let waits = Waits(stopAfter: 4)
        let connection = makeConnection(
            preferences: preferences,
            reachable: [Self.localhost],
            wait: { duration in try waits.record(duration) }
        )

        // The loop parks on the connection instead of backing off, so it has to
        // be cancelled from the outside.
        let task = Task { await connection.runLoop(generation: 0) }
        while !connection.status.isConnected { await Task.yield() }
        connection.stop()
        await task.value

        #expect(waits.durations().isEmpty)
        #expect(connection.status == .disconnected)
        #expect(connection.client == nil)
    }

}

// MARK: - Test doubles

/// Records the endpoints a probe was attempted against, in order.
private final class Probes: @unchecked Sendable {
    private let lock = NSLock()
    private var attempted: [ProPresenterEndpoint] = []

    func record(_ endpoint: ProPresenterEndpoint) {
        lock.lock(); defer { lock.unlock() }
        attempted.append(endpoint)
    }

    func endpoints() -> [ProPresenterEndpoint] {
        lock.lock(); defer { lock.unlock() }
        return attempted
    }
}

/// Records the backoff delays and ends the loop after a fixed number of them.
private final class Waits: @unchecked Sendable {
    private let lock = NSLock()
    private var recorded: [Duration] = []
    private let stopAfter: Int

    init(stopAfter: Int) {
        self.stopAfter = stopAfter
    }

    func record(_ duration: Duration) throws {
        lock.lock()
        recorded.append(duration)
        let count = recorded.count
        lock.unlock()
        if count >= stopAfter { throw CancellationError() }
    }

    func durations() -> [Duration] {
        lock.lock(); defer { lock.unlock() }
        return recorded
    }
}
