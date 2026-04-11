import Foundation
import Sentry

/// Central Sentry configuration for Sela.
///
/// One call to `SentryConfig.start()` at the top of `SelaApp.init()` sets up:
/// - the DSN, release, environment, and sample rates;
/// - conservative PII scrubbing via `beforeSend`, `beforeBreadcrumb`, and
///   `beforeSendMetric` (see `SentryScrubber` for the pure logic);
/// - a flush-on-terminate hook so buffered metrics survive app quit;
/// - a no-op path when running under XCTest so test runs don't pollute the
///   real Sentry project.
enum SentryConfig {
    /// Public DSN for the Sela project on `de-nieuwe-psalmberijming`.
    /// The DSN is a write-only endpoint and is safe to ship in source.
    private static let dsn =
        "https://075cf657d3d22130f0dfd8458b2a8fd2@o4504564317749248.ingest.us.sentry.io/4511201554792448"

    /// The maximum time `SentrySDK.flush` is allowed to block app quit.
    private static let shutdownFlushTimeout: TimeInterval = 1.0

    /// Call once at app startup, before any other work.
    static func start() {
        guard shouldEnableInCurrentProcess() else { return }

        SentrySDK.start { options in
            options.dsn = dsn
            options.environment = currentEnvironment()

            // Error & crash capture
            options.enableCrashHandler = true
            options.enableUncaughtNSExceptionReporting = true
            options.enableSigtermReporting = true
            options.enableAppHangTracking = true
            options.enableAutoSessionTracking = true

            // Tracing — 10% sample rate as agreed.
            options.tracesSampleRate = 0.1

            // Privacy defaults (explicit even when they match the defaults).
            // `attachScreenshot` and `attachViewHierarchy` are iOS-only, so
            // there's nothing to opt out of on macOS — sensitive view data
            // won't be attached to events regardless.
            options.sendDefaultPii = false

            // Translation engines POST lyric text to third-party APIs. We must
            // not let the SDK auto-capture those bodies or their URLs.
            options.enableCaptureFailedRequests = false
            options.enableNetworkBreadcrumbs = false
            options.enableNetworkTracking = false

            // File I/O tracing adds a span per file read — way too noisy for
            // a library-load pipeline that reads thousands of .pro files.
            options.enableFileIOTracing = false
            options.enableFileManagerSwizzling = false

            options.beforeSend = { event in
                SentryScrubber.scrub(event: event)
            }
            options.beforeBreadcrumb = { crumb in
                SentryScrubber.scrub(breadcrumb: crumb)
            }
            options.experimental.beforeSendMetric = { metric in
                SentryScrubber.scrub(metric: metric)
            }
        }

        installTerminateFlushHook()
    }

    /// `false` when running under XCTest (detected via
    /// `XCTestConfigurationFilePath`), `true` otherwise. Separate from
    /// `start()` so it's unit-testable without calling `SentrySDK.start`.
    static func shouldEnableInCurrentProcess() -> Bool {
        ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] == nil
    }

    private static func currentEnvironment() -> String {
        #if DEBUG
            return "debug"
        #else
            return "production"
        #endif
    }

    private static func installTerminateFlushHook() {
        NotificationCenter.default.addObserver(
            forName: NSNotification.Name("NSApplicationWillTerminateNotification"),
            object: nil,
            queue: .main
        ) { _ in
            SentrySDK.flush(timeout: shutdownFlushTimeout)
        }
    }
}
