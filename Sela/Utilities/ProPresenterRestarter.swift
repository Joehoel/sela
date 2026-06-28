import Foundation

/// Restarts the ProPresenter app so it reloads the song files Sela just wrote to
/// disk. ProPresenter keeps its library cached in memory, so on-disk edits only
/// become visible after a relaunch — which is why the save notice asks the user to
/// restart it.
///
/// The orchestration (script building, error mapping) is kept separate from the
/// actual execution: the `runAppleScript` runner is injectable so tests can drive
/// success and failure paths without touching the real app or triggering an
/// Automation permission prompt.
struct ProPresenterRestarter: Sendable {
    /// Runs an AppleScript source string. Returns `nil` on success, or a
    /// human-readable error message on failure.
    var runAppleScript: @Sendable (String) async -> String?

    /// The ProPresenter application name as AppleScript addresses it.
    static let appName = "ProPresenter"

    /// Quits ProPresenter (only if it is running, so we never *launch* it just to
    /// quit it) and relaunches it after a short delay so it re-reads the library.
    static func restartScript(appName: String = appName, delaySeconds: Int = 2) -> String {
        """
        if application "\(appName)" is running then
        \ttell application "\(appName)" to quit
        \tdelay \(delaySeconds)
        end if
        tell application "\(appName)" to activate
        """
    }

    /// Restarts ProPresenter, throwing `ProPresenterRestartError` if the script
    /// reports a failure (e.g. the user denied Automation permission).
    func restart() async throws {
        if let message = await runAppleScript(Self.restartScript()) {
            throw ProPresenterRestartError.restartFailed(message)
        }
    }

    /// Live runner that executes the script via `NSAppleScript` off the main
    /// thread. Sending Apple events to another app requires the user to grant
    /// Automation permission (see `NSAppleEventsUsageDescription`).
    static let live = ProPresenterRestarter { source in
        await Task.detached {
            guard let script = NSAppleScript(source: source) else {
                return "Could not build the ProPresenter restart script."
            }
            var errorInfo: NSDictionary?
            script.executeAndReturnError(&errorInfo)
            if let errorInfo {
                return errorInfo[NSAppleScript.errorMessage] as? String
                    ?? "ProPresenter could not be restarted."
            }
            return nil
        }.value
    }
}

/// Error surfaced when restarting ProPresenter fails.
enum ProPresenterRestartError: LocalizedError, Equatable {
    case restartFailed(String)

    var errorDescription: String? {
        switch self {
        case let .restartFailed(message):
            "Couldn't restart ProPresenter: \(message)"
        }
    }
}
