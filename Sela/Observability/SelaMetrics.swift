import Foundation
@preconcurrency import Sentry

/// Typed wrapper around `SentrySDK.metrics` so call sites stay clean and
/// every metric key lives in exactly one place.
///
/// All keys are prefixed `sela.` — the `beforeSendMetric` scrubber in
/// `SentryScrubber` drops anything without that prefix, so third-party
/// metrics can't accidentally leak into our namespace.
///
/// Attribute values are deliberately low-cardinality (engine name, bucketed
/// reason enums, booleans, small integers). Filenames, paths, song IDs, and
/// lyric text must NEVER be passed as attributes — they would explode
/// cardinality and leak user data.
enum SelaMetrics {
    // MARK: - App lifecycle

    static func appLaunched() {
        SentrySDK.metrics.count(key: "sela.app.launched", value: 1)
    }

    // MARK: - Library load

    static func libraryLoadStarted() {
        SentrySDK.metrics.count(key: "sela.library.load.started", value: 1)
    }

    static func libraryLoadCompleted(
        durationMs: Double,
        fileCount: Int,
        cacheHits: Int,
        cacheMisses: Int
    ) {
        let cacheWarm = cacheHits > 0 && cacheMisses == 0
        let attributes: [String: any SentryAttributeValue] = [
            "cache.warm": cacheWarm,
        ]
        SentrySDK.metrics.count(key: "sela.library.load.completed", value: 1, attributes: attributes)
        SentrySDK.metrics.distribution(
            key: "sela.library.load.duration",
            value: durationMs,
            unit: .millisecond,
            attributes: attributes
        )
        SentrySDK.metrics.distribution(
            key: "sela.library.load.file_count",
            value: Double(fileCount),
            unit: .generic("file"),
            attributes: attributes
        )
        if fileCount > 0 {
            let ratio = Double(cacheHits) / Double(fileCount)
            SentrySDK.metrics.distribution(
                key: "sela.library.load.cache.hit_ratio",
                value: ratio,
                unit: .ratio
            )
        }
        SentrySDK.metrics.gauge(
            key: "sela.library.size",
            value: Double(fileCount),
            unit: .generic("song")
        )
    }

    static func libraryLoadCancelled() {
        SentrySDK.metrics.count(key: "sela.library.load.cancelled", value: 1)
    }

    // MARK: - Parse failures

    enum ParseFailureReason: String {
        case io
        case proto
        case rtf
    }

    static func parseFailed(reason: ParseFailureReason) {
        SentrySDK.metrics.count(
            key: "sela.parse.failed",
            value: 1,
            attributes: ["reason": reason.rawValue]
        )
    }

    // MARK: - Save

    static func saveSucceeded() {
        SentrySDK.metrics.count(key: "sela.save.succeeded", value: 1)
    }

    enum SaveFailureReason: String {
        case io
        case serialize
        case write
    }

    static func saveFailed(reason: SaveFailureReason) {
        SentrySDK.metrics.count(
            key: "sela.save.failed",
            value: 1,
            attributes: ["reason": reason.rawValue]
        )
    }

    // MARK: - Translation pipeline

    static func translationRequested(engine: String, lineCount: Int) {
        SentrySDK.metrics.count(
            key: "sela.translation.requested",
            value: 1,
            attributes: ["engine": engine]
        )
        SentrySDK.metrics.distribution(
            key: "sela.translation.lines_per_request",
            value: Double(lineCount),
            unit: .generic("line"),
            attributes: ["engine": engine]
        )
    }

    static func translationCompleted(engine: String, durationMs: Double) {
        SentrySDK.metrics.count(
            key: "sela.translation.completed",
            value: 1,
            attributes: ["engine": engine]
        )
        SentrySDK.metrics.distribution(
            key: "sela.translation.duration",
            value: durationMs,
            unit: .millisecond,
            attributes: ["engine": engine]
        )
    }

    enum TranslationFailureReason: String {
        case network
        case auth
        case parse
        case other
    }

    static func translationFailed(engine: String, reason: TranslationFailureReason) {
        SentrySDK.metrics.count(
            key: "sela.translation.failed",
            value: 1,
            attributes: ["engine": engine, "reason": reason.rawValue]
        )
    }
}
