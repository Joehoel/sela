import Foundation
@testable import Sela
import Testing

struct LibraryDiscoveryTests {
    // MARK: - Helpers

    private func makeTempRoot() throws -> URL {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("sela-libdisc-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return root
    }

    @discardableResult
    private func makeFolder(_ name: String, in root: URL) throws -> URL {
        let url = root.appendingPathComponent(name, isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func makeFile(_ name: String, in directory: URL) throws {
        try Data().write(to: directory.appendingPathComponent(name))
    }

    private func names(_ urls: [URL]) -> [String] {
        urls.map(\.lastPathComponent)
    }

    // MARK: - Tests

    @Test("finds every subfolder containing a .pro file")
    func findsLibraries() throws {
        let root = try makeTempRoot()
        try makeFile("song.pro", in: try makeFolder("Default", in: root))
        try makeFile("kids.pro", in: try makeFolder("Kids", in: root))

        #expect(names(LibraryDiscovery.libraries(in: root)) == ["Default", "Kids"])
    }

    @Test("ignores empty and irrelevant subfolders")
    func ignoresIrrelevantFolders() throws {
        let root = try makeTempRoot()
        try makeFile("song.pro", in: try makeFolder("Default", in: root))
        try makeFolder("Empty", in: root)
        try makeFile("notes.txt", in: try makeFolder("Media", in: root))

        #expect(names(LibraryDiscovery.libraries(in: root)) == ["Default"])
    }

    @Test("finds .pro files nested deeper in a subfolder")
    func findsNestedProFiles() throws {
        let root = try makeTempRoot()
        let library = try makeFolder("Default", in: root)
        try makeFile("song.pro", in: try makeFolder("Christmas", in: library))

        #expect(names(LibraryDiscovery.libraries(in: root)) == ["Default"])
    }

    @Test("treats a root with .pro files directly in it as a single library")
    func rootWithProFilesIsSingleLibrary() throws {
        let root = try makeTempRoot()
        try makeFile("song.pro", in: root)
        try makeFile("other.pro", in: try makeFolder("Kids", in: root))

        #expect(LibraryDiscovery.libraries(in: root) == [root])
    }

    @Test("returns nothing for an empty or missing root")
    func emptyRoot() throws {
        let root = try makeTempRoot()
        #expect(LibraryDiscovery.libraries(in: root).isEmpty)

        let missing = root.appendingPathComponent("nope", isDirectory: true)
        #expect(LibraryDiscovery.libraries(in: missing).isEmpty)
    }

    @Test("sorts libraries by name")
    func sortsByName() throws {
        let root = try makeTempRoot()
        for name in ["Zang", "Default", "kids"] {
            try makeFile("song.pro", in: try makeFolder(name, in: root))
        }

        #expect(names(LibraryDiscovery.libraries(in: root)) == ["Default", "kids", "Zang"])
    }

    // MARK: - Off the main actor

    @Test("the scan a main-actor caller kicks off does not run on the main thread")
    @MainActor
    func scanRunsOffTheMainThread() async throws {
        let root = try makeTempRoot()
        try makeFile("song.pro", in: try makeFolder("Default", in: root))
        // ContentView.task is main-actor isolated, so a plain call would walk
        // the whole subtree right here and beachball the app for a big root.
        let recorder = ThreadRecorder()

        let urls = await LibraryDiscovery.librariesOffMain(in: root) { root in
            recorder.record(isMainThread: Thread.isMainThread)
            return LibraryDiscovery.libraries(in: root)
        }

        #expect(recorder.calls == 1)
        #expect(recorder.mainThreadCalls == 0)
        #expect(names(urls) == ["Default"])
    }

    @Test("the off-main scan returns what the direct scan returns")
    func offMainMatchesDirectScan() async throws {
        let root = try makeTempRoot()
        try makeFile("song.pro", in: try makeFolder("Default", in: root))
        try makeFile("kids.pro", in: try makeFolder("Kids", in: root))

        let urls = await LibraryDiscovery.librariesOffMain(in: root)

        #expect(urls == LibraryDiscovery.libraries(in: root))
    }
}

/// Counts the injected scan's calls and how many of them ran on the main
/// thread, across the actor hop.
private final class ThreadRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var callCount = 0
    private var mainThreadCallCount = 0

    func record(isMainThread: Bool) {
        lock.lock()
        defer { lock.unlock() }
        callCount += 1
        if isMainThread { mainThreadCallCount += 1 }
    }

    var calls: Int {
        lock.lock()
        defer { lock.unlock() }
        return callCount
    }

    var mainThreadCalls: Int {
        lock.lock()
        defer { lock.unlock() }
        return mainThreadCallCount
    }
}
