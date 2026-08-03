import Foundation

enum BookmarkManager {
    /// Security-scoped bookmark for the libraries root folder. The pre-multi-
    /// library `libraryBookmark` is not migrated — the app isn't sandboxed, so
    /// path access keeps working; the user can re-pick the folder if needed.
    private static let bookmarkKey = "librariesRootBookmark"

    static func saveBookmark(for url: URL) {
        guard let data = try? url.bookmarkData(
            options: .withSecurityScope,
            includingResourceValuesForKeys: nil,
            relativeTo: nil
        ) else { return }
        UserDefaults.standard.set(data, forKey: bookmarkKey)
    }

    static func resolveBookmark() -> URL? {
        guard let data = UserDefaults.standard.data(forKey: bookmarkKey) else { return nil }
        var isStale = false
        guard let url = try? URL(
            resolvingBookmarkData: data,
            options: .withSecurityScope,
            relativeTo: nil,
            bookmarkDataIsStale: &isStale
        ) else { return nil }

        if isStale {
            saveBookmark(for: url)
        }
        return url
    }
}
