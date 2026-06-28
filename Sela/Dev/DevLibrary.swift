#if DEBUG
import Foundation
import os

/// Developer convenience: on a machine without a real ProPresenter library
/// (e.g. no ProPresenter installed), Sela falls back to a writable copy of the
/// repo's test fixtures so the full load → translate → save pipeline can be
/// exercised end to end.
///
/// DEBUG-only — none of this is compiled into release builds. The fixtures are
/// copied into Application Support rather than read in place, so saving never
/// mutates the tracked `SelaTests/Fixtures/*.pro` files.
enum DevLibrary {
    private static let log = Logger(subsystem: "com.sela.app", category: "DevLibrary")

    /// The repo's fixtures directory, resolved from this source file's location
    /// (valid on the dev machine where the sources live).
    static var fixturesSourceURL: URL {
        URL(fileURLWithPath: #filePath) // .../sela/Sela/Dev/DevLibrary.swift
            .deletingLastPathComponent() // .../sela/Sela/Dev
            .deletingLastPathComponent() // .../sela/Sela
            .deletingLastPathComponent() // .../sela
            .appendingPathComponent("SelaTests/Fixtures", isDirectory: true)
    }

    /// Writable dev library, seeded from the fixtures.
    static var libraryURL: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return base.appendingPathComponent("Sela/DevLibrary", isDirectory: true)
    }

    /// `true` when the library at `realLibraryURL` is missing or contains no
    /// `.pro` files — i.e. there's nothing real to load.
    static func shouldUseFixtures(realLibraryURL: URL) -> Bool {
        !containsProFiles(realLibraryURL)
    }

    /// Ensures the writable dev library exists and is seeded from the fixtures,
    /// then returns its URL. Re-seeds only when empty, so edits made while
    /// developing survive across launches (delete the folder to reset).
    static func seededLibraryURL() -> URL {
        let dest = libraryURL
        if !containsProFiles(dest) {
            seed(into: dest, from: fixturesSourceURL)
            log.notice("Seeded dev library at \(dest.path, privacy: .public) from fixtures")
        } else {
            log.notice("Using existing dev library at \(dest.path, privacy: .public)")
        }
        return dest
    }

    /// Copies every `.pro` file from `source` into `destination` (creating it as
    /// needed), overwriting any existing copies. Exposed for testing.
    static func seed(into destination: URL, from source: URL) {
        let fm = FileManager.default
        try? fm.createDirectory(at: destination, withIntermediateDirectories: true)
        guard let entries = try? fm.contentsOfDirectory(at: source, includingPropertiesForKeys: nil) else { return }
        for file in entries where file.pathExtension == "pro" {
            let target = destination.appendingPathComponent(file.lastPathComponent)
            try? fm.removeItem(at: target)
            try? fm.copyItem(at: file, to: target)
        }
    }

    private static func containsProFiles(_ directory: URL) -> Bool {
        guard let enumerator = FileManager.default.enumerator(at: directory, includingPropertiesForKeys: nil) else {
            return false
        }
        for case let url as URL in enumerator where url.pathExtension == "pro" {
            return true
        }
        return false
    }
}
#endif
