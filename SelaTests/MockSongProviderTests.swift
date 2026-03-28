@testable import Sela
import Testing

@MainActor
struct MockSongProviderTests {
    @Test("loads 6 songs")
    func loadsSongs() async {
        let songs = await MockSongProvider().loadSongs()
        #expect(songs.count == 6)
    }

    @Test("songs have correct titles")
    func songTitles() async {
        let songs = await MockSongProvider().loadSongs()
        let titles = songs.map(\.title)
        #expect(titles.contains("Way Maker"))
        #expect(titles.contains("Build My Life"))
        #expect(titles.contains("Amazing Grace"))
    }

    @Test("some songs have existing translations")
    func someTranslated() async {
        let songs = await MockSongProvider().loadSongs()
        let translated = songs.filter(\.hasTranslation)
        let untranslated = songs.filter { !$0.hasTranslation }
        #expect(!translated.isEmpty)
        #expect(!untranslated.isEmpty)
    }

    @Test("Build My Life is fully translated")
    func buildMyLifeFullyTranslated() {
        let song = MockSongProvider.buildMyLife
        #expect(song.translationProgress == 1.0)
    }

    @Test("Way Maker has no translations")
    func wayMakerUntranslated() {
        let song = MockSongProvider.wayMaker
        #expect(!song.hasTranslation)
        #expect(song.translationProgress == 0)
    }

    @Test("all songs have slide groups")
    func allSongsHaveGroups() async {
        let songs = await MockSongProvider().loadSongs()
        for song in songs {
            #expect(!song.slideGroups.isEmpty, "'\(song.title)' has no slide groups")
        }
    }

    @Test("all songs have authors")
    func allSongsHaveAuthors() async {
        let songs = await MockSongProvider().loadSongs()
        for song in songs {
            #expect(!song.author.isEmpty, "'\(song.title)' has no author")
        }
    }
}
