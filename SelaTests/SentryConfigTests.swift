import Foundation
@testable import Sela
import Testing

/// TDD tests for the Sentry PII scrubbers and metric gating logic.
///
/// These are pure-function tests — no SDK init, no network. They exercise
/// `SentryScrubber` directly rather than going through the Sentry `beforeSend`
/// hooks, so they run in-process without polluting any real Sentry project.
struct SentryConfigTests {
    // MARK: - Path scrubbing

    @Test("absolute user paths get reduced to the last path component")
    func pathsCollapseToFilename() {
        let input = "Failed to read /Users/joel/Documents/ProPresenter/Libraries/Default/Welkom.pro"
        let output = SentryScrubber.scrubText(input)
        #expect(output.contains("Welkom.pro"))
        #expect(!output.contains("/Users/joel"))
        #expect(!output.contains("Documents"))
    }

    @Test("volume paths are scrubbed")
    func volumePathsScrubbed() {
        let input = "Error at /Volumes/External/Songs/Amazing Grace.pro"
        let output = SentryScrubber.scrubText(input)
        #expect(!output.contains("/Volumes/External"))
        #expect(output.contains("Amazing Grace.pro"))
    }

    @Test("multiple paths in one string are all scrubbed")
    func multiplePathsScrubbed() {
        let input = "Can't copy /Users/joel/A.pro to /Users/joel/B.pro"
        let output = SentryScrubber.scrubText(input)
        #expect(!output.contains("/Users/joel"))
        #expect(output.contains("A.pro"))
        #expect(output.contains("B.pro"))
    }

    @Test("text without paths passes through untouched")
    func plainTextUntouched() {
        let input = "Failed to decode protobuf message"
        let output = SentryScrubber.scrubText(input)
        #expect(output == input)
    }

    // MARK: - Secret redaction

    @Test("DeepL-shaped API keys are redacted")
    func deeplKeyRedacted() {
        let input = "Authorization: DeepL-Auth-Key abc123def456ghi789jkl012mno345pqr678stu901vwx234yz"
        let output = SentryScrubber.scrubText(input)
        #expect(!output.contains("abc123def456"))
        #expect(output.contains("<redacted>"))
    }

    @Test("Gemini-shaped API keys are redacted")
    func geminiKeyRedacted() {
        let input = "Request failed with key=AIzaSyB0123456789abcdefghijklmnopqrstuv"
        let output = SentryScrubber.scrubText(input)
        #expect(!output.contains("AIzaSyB"))
    }

    // MARK: - HTTP breadcrumb dropping

    @Test("translation API breadcrumbs are dropped entirely")
    func translationAPIBreadcrumbsDropped() {
        #expect(SentryScrubber.shouldDropBreadcrumb(url: "https://api.deepl.com/v2/translate"))
        #expect(SentryScrubber.shouldDropBreadcrumb(url: "https://generativelanguage.googleapis.com/v1/models"))
        #expect(SentryScrubber.shouldDropBreadcrumb(url: "https://translation.googleapis.com/language/translate/v2"))
        #expect(SentryScrubber.shouldDropBreadcrumb(url: "https://api.mymemory.translated.net/get"))
    }

    @Test("non-translation URLs do not match the drop filter")
    func unrelatedBreadcrumbsKept() {
        #expect(!SentryScrubber.shouldDropBreadcrumb(url: "https://example.com/ping"))
        #expect(!SentryScrubber.shouldDropBreadcrumb(url: nil))
    }

    // MARK: - Metric gating

    @Test("metrics outside the sela namespace are dropped")
    func nonSelaMetricsDropped() {
        #expect(SentryScrubber.shouldDropMetric(
            key: "library.load.duration",
            attributeValues: []
        ))
        #expect(SentryScrubber.shouldDropMetric(
            key: "random.metric",
            attributeValues: []
        ))
    }

    @Test("sela-prefixed metrics with safe attributes pass")
    func selaMetricsWithSafeAttributesKept() {
        #expect(!SentryScrubber.shouldDropMetric(
            key: "sela.library.load.duration",
            attributeValues: ["gemini", "false", "42"]
        ))
    }

    @Test("metric with path-like attribute value is dropped")
    func metricWithPathAttributeDropped() {
        #expect(SentryScrubber.shouldDropMetric(
            key: "sela.library.load.started",
            attributeValues: ["/Users/joel/Documents/Songs"]
        ))
    }

    @Test("metric with long attribute value is dropped (likely lyric leakage)")
    func metricWithLongAttributeDropped() {
        let longValue = String(repeating: "a", count: 128)
        #expect(SentryScrubber.shouldDropMetric(
            key: "sela.library.load.started",
            attributeValues: [longValue]
        ))
    }

    @Test("metric with email-like attribute value is dropped")
    func metricWithEmailAttributeDropped() {
        #expect(SentryScrubber.shouldDropMetric(
            key: "sela.app.launched",
            attributeValues: ["user@example.com"]
        ))
    }

    // MARK: - Enable gating

    @Test("SDK should not start in the test process environment")
    func sdkDisabledInTests() {
        // When running under XCTest, the env var XCTestConfigurationFilePath is set.
        // SentryConfig should early-return without initializing.
        #expect(SentryConfig.shouldEnableInCurrentProcess() == false)
    }
}
