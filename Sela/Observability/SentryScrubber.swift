import Foundation
import Sentry

/// Pure string-level scrubbing logic for Sentry events, breadcrumbs, and
/// metrics. Split from `SentryConfig` so the rules can be unit-tested without
/// initializing the SDK.
///
/// The scrubbers are conservative by design — we'd rather lose some debug
/// signal than leak a user's lyric text, file paths, or API keys to Sentry.
enum SentryScrubber {
    // MARK: - Constants

    /// URL substring matches for translation APIs whose breadcrumbs must be
    /// dropped entirely. Query strings on these endpoints contain lyric text.
    private static let droppedBreadcrumbHosts: [String] = [
        "api.deepl.com",
        "api-free.deepl.com",
        "generativelanguage.googleapis.com",
        "translation.googleapis.com",
        "translate.googleapis.com",
        "api.mymemory.translated.net",
    ]

    /// Max length of a metric attribute value before we treat it as likely
    /// lyric/path leakage and drop the metric.
    private static let maxMetricAttributeLength = 64

    /// Required prefix for all Sela-emitted metrics. Metrics without this
    /// prefix originate from third-party code (or bugs) and are dropped.
    private static let selaMetricPrefix = "sela."

    // MARK: - Text scrubbing

    /// Apply all text-level scrubbers in sequence: path collapsing first,
    /// then secret redaction.
    static func scrubText(_ input: String) -> String {
        redactSecrets(scrubPaths(input))
    }

    /// Collapse absolute `/Users/...` and `/Volumes/...` paths to just their
    /// last path component, so we keep the filename (useful for debugging)
    /// without leaking the user's home layout.
    static func scrubPaths(_ input: String) -> String {
        let pattern = #"/(?:Users|Volumes)/[^\s\)\]\"']+"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else {
            return input
        }
        let range = NSRange(input.startIndex..., in: input)
        let matches = regex.matches(in: input, range: range).reversed()
        var result = input
        for match in matches {
            guard let range = Range(match.range, in: result) else { continue }
            let path = String(result[range])
            let lastComponent = (path as NSString).lastPathComponent
            result.replaceSubrange(range, with: lastComponent)
        }
        return result
    }

    /// Redact long alphanumeric runs that look like API keys. Catches DeepL,
    /// Gemini / Google API keys, and generic bearer tokens.
    static func redactSecrets(_ input: String) -> String {
        let patterns = [
            // Google API keys start with "AIza" followed by 35 chars.
            #"AIza[0-9A-Za-z\-_]{35}"#,
            // Any 32+ char alphanumeric run (DeepL-ish, bearer tokens).
            #"[A-Za-z0-9]{32,}"#,
        ]
        var result = input
        for pattern in patterns {
            guard let regex = try? NSRegularExpression(pattern: pattern) else { continue }
            let range = NSRange(result.startIndex..., in: result)
            result = regex.stringByReplacingMatches(
                in: result, range: range, withTemplate: "<redacted>"
            )
        }
        return result
    }

    // MARK: - Breadcrumb decisions

    /// Returns `true` if a breadcrumb with this URL should be dropped because
    /// it targets an endpoint that carries user lyric text in request/URL.
    static func shouldDropBreadcrumb(url: String?) -> Bool {
        guard let url else { return false }
        return droppedBreadcrumbHosts.contains { url.contains($0) }
    }

    // MARK: - Metric gating

    /// Returns `true` if a metric should be dropped based on its key (must
    /// start with `sela.`) or if any of its attribute values look like PII
    /// (paths, emails, or anything unexpectedly long).
    static func shouldDropMetric(key: String, attributeValues: [String]) -> Bool {
        if !key.hasPrefix(selaMetricPrefix) { return true }
        for value in attributeValues {
            if value.count > maxMetricAttributeLength { return true }
            if value.contains("/Users/") || value.contains("/Volumes/") || value.contains("/private/") {
                return true
            }
            if value.contains("@"), value.contains(".") { return true } // email-ish
        }
        return false
    }

    // MARK: - Sentry type adapters

    /// Apply scrubbing to a Sentry `Event`. Walks message, exception values,
    /// and extras. Returns `nil` only in extreme cases (never, currently —
    /// we prefer to scrub in-place so crash signal isn't lost).
    static func scrub(event: Event) -> Event? {
        if let message = event.message?.formatted {
            event.message = SentryMessage(formatted: scrubText(message))
        }
        if let exceptions = event.exceptions {
            for exception in exceptions {
                if let value = exception.value {
                    exception.value = scrubText(value)
                }
            }
        }
        if var extras = event.extra {
            for (key, value) in extras {
                if let string = value as? String {
                    extras[key] = scrubText(string)
                }
            }
            event.extra = extras
        }
        return event
    }

    /// Apply scrubbing to a Sentry `Breadcrumb`. Drops translation-API
    /// breadcrumbs entirely; otherwise scrubs the message and string data.
    static func scrub(breadcrumb: Breadcrumb) -> Breadcrumb? {
        if let data = breadcrumb.data {
            if let urlString = data["url"] as? String, shouldDropBreadcrumb(url: urlString) {
                return nil
            }
        }
        if let message = breadcrumb.message {
            breadcrumb.message = scrubText(message)
        }
        if var data = breadcrumb.data {
            for (key, value) in data {
                if let string = value as? String {
                    data[key] = scrubText(string)
                }
            }
            breadcrumb.data = data
        }
        return breadcrumb
    }

    /// Apply scrubbing to a Sentry metric. Drops metrics outside the `sela.`
    /// namespace and metrics with suspicious attribute values.
    static func scrub(metric: SentryMetric) -> SentryMetric? {
        let values = metric.attributes.values.compactMap { attributeValueString($0) }
        if shouldDropMetric(key: metric.name, attributeValues: values) {
            return nil
        }
        return metric
    }

    private static func attributeValueString(_ value: SentryAttributeContent) -> String? {
        switch value {
        case let .string(str): str
        default: nil
        }
    }
}
