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

    // MARK: - Line Resolution

    @Test("resolveLines for emptySlides returns only untranslated lines")
    func resolveLinesEmpty() {
        let song = makeSong()
        song.slideGroups[0].slides[0].lines[0].translation = "Translated"
        let controller = EditorController(song: song)

        let lines = controller.resolveLines(for: .emptySlides)

        #expect(lines.count == 2)
        #expect(lines.filter { !$0.translation.isEmpty }.isEmpty)
    }

    @Test("resolveLines for allSlides returns every line")
    func resolveLinesAll() {
        let song = makeSong()
        let controller = EditorController(song: song)

        let lines = controller.resolveLines(for: .allSlides)

        #expect(lines.count == 3)
    }

    @Test("resolveLines for specific IDs returns matching lines")
    func resolveLinesSpecific() {
        let song = makeSong()
        let controller = EditorController(song: song)
        let targetID = song.slideGroups[1].slides[0].lines[0].id

        let lines = controller.resolveLines(for: .lines([targetID]))

        #expect(lines.count == 1)
        #expect(lines[0].id == targetID)
    }

    // MARK: - Build Items

    @Test("buildItems produces items for pending lines with group names")
    func buildItems() {
        let song = makeSong()
        let controller = EditorController(song: song)
        let lineA = song.slideGroups[0].slides[0].lines[0]
        let lineC = song.slideGroups[1].slides[0].lines[0]
        controller.setPendingLineIDs([lineA.id, lineC.id])

        let items = controller.buildItems()

        #expect(items.count == 2)
        #expect(items[0].lineID == lineA.id)
        #expect(items[0].groupName == "V1")
        #expect(items[1].lineID == lineC.id)
        #expect(items[1].groupName == "Chorus")
    }

    @Test("buildItems returns empty when no pending IDs")
    func buildItemsEmpty() {
        let controller = EditorController(song: makeSong())

        let items = controller.buildItems()

        #expect(items.isEmpty)
    }

    // MARK: - Write Back

    @Test("writeBack applies translations to song lines and triggers save")
    func writeBack() {
        let song = makeSong()
        let controller = EditorController(song: song)
        let lineA = song.slideGroups[0].slides[0].lines[0]
        controller.setPendingLineIDs([lineA.id])

        var item = TranslationItem(sourceText: "Line A", lineID: lineA.id, groupName: "V1")
        item.currentText = "Lijn A"
        let items = [item]
        controller.writeBack(items)

        #expect(lineA.translation == "Lijn A")
        #expect(controller.isDirty)
    }

    // MARK: - Translation Requests

    @Test("requestTranslation with emptySlides triggers immediately")
    func requestEmpty() {
        let song = makeSong()
        let controller = EditorController(song: song)
        let prefs = UserPreferences()
        prefs.translationEngine = .deepl
        prefs.deeplAPIKey = "test"
        controller.preferences = prefs

        controller.requestTranslation(.emptySlides)

        // Should have set pending lines (all 3 are empty)
        #expect(controller.hasPendingLines)
    }

    @Test("requestTranslation with allSlides shows confirmation")
    func requestAllShowsConfirmation() {
        let controller = EditorController(song: makeSong())

        controller.requestTranslation(.allSlides)

        #expect(controller.showRetranslateConfirmation)
        #expect(!controller.hasPendingLines)
    }

    @Test("translateSlide requests translation for that slide's lines")
    func translateSlideTest() {
        let song = makeSong()
        let controller = EditorController(song: song)
        let prefs = UserPreferences()
        prefs.translationEngine = .deepl
        prefs.deeplAPIKey = "test"
        controller.preferences = prefs
        let slide = song.slideGroups[0].slides[0]

        controller.translateSlide(slide)

        #expect(controller.hasPendingLines)
    }

    // MARK: - Status / Error

    @Test("dismissTranslationError clears the error")
    func dismissError() {
        let controller = EditorController(song: makeSong())
        controller.setTranslationError("Something failed")

        controller.dismissTranslationError()

        #expect(controller.translationError == nil)
    }
}
