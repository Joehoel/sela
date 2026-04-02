import Cocoa

/// AppleScript wrapper for Song. Each instance maps to one Song in AppState.
class SelaScriptSong: NSObject {
    let song: Song

    init(song: Song) {
        self.song = song
    }

    @objc var id: String {
        song.id
    }

    @objc var name: String {
        song.title
    }

    @objc var author: String {
        song.author
    }

    @objc var translationProgress: Double {
        song.translationProgress
    }

    @objc var slideCount: Int {
        song.slideCount
    }

    @objc var translatedSlideCount: Int {
        song.translatedSlideCount
    }

    override var objectSpecifier: NSScriptObjectSpecifier? {
        guard let appDescription = NSApplication.shared.classDescription as? NSScriptClassDescription else {
            return nil
        }
        return NSUniqueIDSpecifier(
            containerClassDescription: appDescription,
            containerSpecifier: nil,
            key: "scriptSongs",
            uniqueID: id
        )
    }
}
