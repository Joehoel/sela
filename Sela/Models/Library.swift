import Foundation

/// A single ProPresenter library: one folder holding `.pro` files, discovered
/// under the libraries root by `LibraryDiscovery`.
///
/// Songs are not stored here — they live centrally in `AppState.songs` and
/// carry their library attribution (`Song.libraryID` / `Song.libraryName`), so
/// search, selection and the sidebar sections keep working across libraries.
struct Library: Identifiable, Hashable, Sendable {
    /// The library folder on disk.
    let url: URL

    /// Absolute folder path — stable across launches and used to attribute
    /// songs and to route saves back to the right provider.
    var id: String { url.path }

    /// Folder name, shown as the library's title in the UI.
    var name: String { url.lastPathComponent }

    init(url: URL) {
        self.url = url
    }
}
