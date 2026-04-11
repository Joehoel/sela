import CryptoKit
import Foundation

/// On-disk cache of parsed ProPresenter songs, keyed by absolute file path
/// and validated by `(mtime, size)`. On subsequent loads of an unchanged
/// library the provider skips decoding entirely and serves cached
/// `ParsedSong` DTOs, turning cold-start into an O(files) stat walk.
///
/// The index is invalidated by:
/// - a version mismatch (bump `currentVersion` whenever the cache format,
///   RTF stripper behavior, or reader output changes);
/// - a corrupt/unreadable file (silently falls back to empty);
/// - any file whose mtime or size no longer matches what we recorded.
struct LibraryIndex: Codable {
    /// Bump whenever the serialized shape changes or the parser output
    /// semantics change — old entries will be treated as misses.
    static let currentVersion = 1

    var version: Int
    var entries: [String: Entry]

    struct Entry: Codable {
        var mtime: TimeInterval
        var size: Int64
        var parsed: ParsedSong
    }

    init() {
        self.version = Self.currentVersion
        self.entries = [:]
    }

    /// Load from disk. Returns an empty index if the file is missing,
    /// unreadable, malformed JSON, or from a different version — never
    /// throws. Index corruption should self-heal on the next load.
    static func load(from url: URL) -> LibraryIndex {
        guard let data = try? Data(contentsOf: url) else { return LibraryIndex() }
        guard let decoded = try? JSONDecoder().decode(LibraryIndex.self, from: data) else {
            return LibraryIndex()
        }
        if decoded.version != currentVersion {
            return LibraryIndex()
        }
        return decoded
    }

    /// Write the index to disk atomically, creating parent directories as
    /// needed. Throws on I/O or encoding failures.
    func save(to url: URL) throws {
        let encoder = JSONEncoder()
        let data = try encoder.encode(self)
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try data.write(to: url, options: .atomic)
    }

    /// Default on-disk location for a library, keyed by a hash of its path
    /// so the user can swap between libraries without cross-contamination.
    static func defaultURL(for libraryURL: URL) -> URL {
        let pathBytes = Data(libraryURL.standardizedFileURL.path.utf8)
        let digest = Insecure.MD5.hash(data: pathBytes)
        let hex = digest.map { String(format: "%02x", $0) }.joined()
        let support = (try? FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )) ?? FileManager.default.temporaryDirectory
        return support
            .appendingPathComponent("com.sela.app", isDirectory: true)
            .appendingPathComponent("library-index-\(hex).json")
    }
}
