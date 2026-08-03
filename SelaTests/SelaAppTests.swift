import Foundation
@testable import Sela
import Testing

/// The launch guard that keeps the live ProPresenter loops out of the test host.
///
/// `SelaApp` conforms to `App`, so it is main-actor isolated and so is its
/// launch guard; the suite runs on the main actor to call it directly.
@MainActor
struct SelaAppTests {
    /// Stand-in for `XCTestCase` — any class works, only its presence matters.
    private final class FakeTestCase {}

    @Test("the app hosting this very test bundle does not start the live services")
    func testHostDoesNotStartServices() {
        // No arguments: exactly the situation `onAppear` is in while
        // `xcodebuild test` runs the suite inside the Sela app.
        var started = false
        SelaApp.startLiveServices { started = true }

        #expect(started == false)
    }

    @Test("an XCTest configuration in the environment blocks the start")
    func testConfigurationPathBlocksStart() {
        var started = false
        SelaApp.startLiveServices(
            environment: ["XCTestConfigurationFilePath": "/tmp/Sela.xctestconfiguration"],
            testCaseClass: nil
        ) { started = true }

        #expect(started == false)
    }

    @Test("a loaded XCTestCase class blocks the start")
    func testCaseClassBlocksStart() {
        var started = false
        SelaApp.startLiveServices(environment: [:], testCaseClass: FakeTestCase.self) { started = true }

        #expect(started == false)
    }

    @Test("a normal app launch starts the live services")
    func normalLaunchStartsServices() {
        var started = false
        SelaApp.startLiveServices(environment: ["HOME": "/Users/someone"], testCaseClass: nil) {
            started = true
        }

        #expect(started)
    }
}
