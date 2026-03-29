import Foundation
@testable import Sela
import Testing

@MainActor
struct EditorControllerTests {
    private func makeSong() -> Song {
        Song(title: "Test", slideGroups: [
            SlideGroup(name: "V1", slides: [
                Slide(lines: [
                    SlideLine(original: "Line A"),
                    SlideLine(original: "Line B"),
                ]),
            ]),
            SlideGroup(name: "Chorus", slides: [
                Slide(lines: [
                    SlideLine(original: "Line C"),
                ]),
            ]),
        ])
    }

    // MARK: - Navigation

    @Test("advance moves focus to the next line")
    func advanceToNext() {
        let song = makeSong()
        let controller = EditorController(song: song)
        let lineA = song.slideGroups[0].slides[0].lines[0]
        let lineB = song.slideGroups[0].slides[0].lines[1]

        controller.advanceFromLine(lineA.id)

        #expect(controller.focusedLineID == lineB.id)
    }

    @Test("advance wraps from last line to first")
    func advanceWraps() {
        let song = makeSong()
        let controller = EditorController(song: song)
        let lineC = song.slideGroups[1].slides[0].lines[0]
        let lineA = song.slideGroups[0].slides[0].lines[0]

        controller.advanceFromLine(lineC.id)

        #expect(controller.focusedLineID == lineA.id)
    }

    @Test("retreat moves focus to the previous line")
    func retreatToPrev() {
        let song = makeSong()
        let controller = EditorController(song: song)
        let lineB = song.slideGroups[0].slides[0].lines[1]
        let lineA = song.slideGroups[0].slides[0].lines[0]

        controller.retreatFromLine(lineB.id)

        #expect(controller.focusedLineID == lineA.id)
    }

    @Test("retreat wraps from first line to last")
    func retreatWraps() {
        let song = makeSong()
        let controller = EditorController(song: song)
        let lineA = song.slideGroups[0].slides[0].lines[0]
        let lineC = song.slideGroups[1].slides[0].lines[0]

        controller.retreatFromLine(lineA.id)

        #expect(controller.focusedLineID == lineC.id)
    }

    @Test("advance with unknown line ID is a no-op")
    func advanceUnknown() {
        let song = makeSong()
        let controller = EditorController(song: song)

        controller.advanceFromLine("nonexistent")

        #expect(controller.focusedLineID == nil)
    }

    // MARK: - Save

    @Test("save state starts clean")
    func saveStartsClean() {
        let controller = EditorController(song: makeSong())

        #expect(!controller.isDirty)
        #expect(!controller.isSaving)
        #expect(controller.saveError == nil)
    }

    @Test("successful save transitions from dirty to clean")
    func saveSuccess() async {
        let controller = EditorController(song: makeSong(), save: {})
        controller.debounceSave()
        #expect(controller.isDirty)

        await controller.performSave()

        #expect(!controller.isDirty)
        #expect(!controller.isSaving)
        #expect(controller.saveError == nil)
    }

    @Test("failed save surfaces error and stays dirty")
    func saveFailure() async {
        let controller = EditorController(song: makeSong(), save: {
            throw NSError(domain: "test", code: 1, userInfo: [NSLocalizedDescriptionKey: "Disk full"])
        })
        controller.debounceSave()

        await controller.performSave()

        #expect(controller.isDirty)
        #expect(!controller.isSaving)
        #expect(controller.saveError == "Disk full")
    }

    @Test("debounceSave marks dirty and saves after delay")
    func debounceSave() async throws {
        var saveCount = 0
        let controller = EditorController(song: makeSong(), save: { saveCount += 1 })

        controller.debounceSave()
        #expect(controller.isDirty)
        #expect(saveCount == 0)

        try await Task.sleep(for: .seconds(2.5))

        #expect(saveCount == 1)
        #expect(!controller.isDirty)
    }
}
