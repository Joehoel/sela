import Foundation

/// Finds the ProPresenter libraries inside a "Libraries" root folder.
///
/// A library is any direct subfolder of the root that contains at least one
/// `.pro` file (at any depth). Pure and side-effect free apart from reading the
/// file system, so it can be exercised against temp directories in tests.
enum LibraryDiscovery {
    /// The library folders inside `root`, sorted by name.
    ///
    /// When `root` itself directly contains `.pro` files the user picked a
    /// single library folder rather than the libraries root — in that case the
    /// root is returned as the one and only library.
    static func libraries(in root: URL, fileManager: FileManager = .default) -> [URL] {
        guard let entries = try? fileManager.contentsOfDirectory(
            at: root,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else { return [] }

        if entries.contains(where: { $0.pathExtension == "pro" && !$0.hasDirectoryPath }) {
            return [root]
        }

        return entries
            .filter { $0.hasDirectoryPath && containsProFile($0, fileManager: fileManager) }
            .sorted { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending }
    }

    /// `libraries(in:)`, run off the calling actor.
    ///
    /// The scan walks every candidate folder to the bottom, so on the main
    /// actor a root that holds thousands of documents beachballs the app —
    /// `SettingsView` hops off for exactly that reason. `scan` is injectable so
    /// tests can see which thread the file-system work lands on.
    static func librariesOffMain(
        in root: URL,
        scan: @escaping @Sendable (URL) -> [URL] = { libraries(in: $0) }
    ) async -> [URL] {
        await Task.detached(priority: .userInitiated) { scan(root) }.value
    }

    /// `true` when `directory` contains a `.pro` file at any depth.
    private static func containsProFile(_ directory: URL, fileManager: FileManager) -> Bool {
        guard let enumerator = fileManager.enumerator(
            at: directory,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles, .skipsPackageDescendants]
        ) else { return false }

        for case let url as URL in enumerator where url.pathExtension == "pro" {
            return true
        }
        return false
    }
}
