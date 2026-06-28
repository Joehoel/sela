import Foundation
@testable import Sela
import Testing

struct ProPresenterRestarterTests {
    // MARK: - Script building

    @Test("script guards quit behind an is-running check so it never launches just to quit")
    func scriptGuardsQuit() {
        let script = ProPresenterRestarter.restartScript()
        #expect(script.contains("if application \"ProPresenter\" is running then"))
        #expect(script.contains("tell application \"ProPresenter\" to quit"))
        // quit lives inside the guard; relaunch is unconditional.
        #expect(script.contains("tell application \"ProPresenter\" to activate"))
    }

    @Test("script waits between quit and relaunch")
    func scriptWaits() {
        let script = ProPresenterRestarter.restartScript(delaySeconds: 3)
        #expect(script.contains("delay 3"))
    }

    @Test("script targets a custom app name")
    func scriptCustomName() {
        let script = ProPresenterRestarter.restartScript(appName: "ProPresenter 7")
        #expect(script.contains("\"ProPresenter 7\""))
    }

    // MARK: - Restart orchestration (runner injected — no real app)

    @Test("restart runs the AppleScript and succeeds when the runner reports no error")
    func restartSucceeds() async throws {
        let captured = ScriptCapture()
        let restarter = ProPresenterRestarter { source in
            captured.store(source)
            return nil
        }
        try await restarter.restart()
        #expect(captured.script?.contains("ProPresenter") == true)
    }

    @Test("restart throws restartFailed carrying the runner's message")
    func restartFails() async {
        let restarter = ProPresenterRestarter { _ in "Not authorized to send Apple events" }
        await #expect(throws: ProPresenterRestartError.restartFailed("Not authorized to send Apple events")) {
            try await restarter.restart()
        }
    }

    @Test("restart error has a user-friendly description")
    func errorDescription() {
        let error = ProPresenterRestartError.restartFailed("permission denied")
        #expect(error.errorDescription?.contains("permission denied") == true)
        #expect(error.errorDescription?.contains("ProPresenter") == true)
    }
}

/// Thread-safe capture of the script passed to the injected runner.
private final class ScriptCapture: @unchecked Sendable {
    private let lock = NSLock()
    private var value: String?

    var script: String? {
        lock.lock(); defer { lock.unlock() }
        return value
    }

    func store(_ source: String) {
        lock.lock(); defer { lock.unlock() }
        value = source
    }
}
