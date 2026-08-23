import Combine
import XCTest
@testable import ClipStow

final class AppStoreTests: XCTestCase {
    private var defaults: UserDefaults!
    private var suiteName: String!

    override func setUp() {
        super.setUp()
        suiteName = "ClipStowTests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)!
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        defaults = nil
        suiteName = nil
        super.tearDown()
    }

    func testCreatesEditsAndSortsNotesByMostRecentlyUpdated() {
        let firstDate = Date(timeIntervalSince1970: 100)
        let secondDate = Date(timeIntervalSince1970: 200)
        let first = Note(title: "First", createdAt: firstDate, updatedAt: firstDate)
        let second = Note(title: "Second", createdAt: secondDate, updatedAt: secondDate)
        let repository = InMemoryNoteRepository(
            snapshot: StoreSnapshot(notes: [first, second], lastSelectedNoteID: first.id)
        )
        var currentDate = Date(timeIntervalSince1970: 300)
        let store = AppStore(
            repository: repository,
            userDefaults: defaults,
            saveDebounce: 60,
            now: { currentDate }
        )

        XCTAssertEqual(store.sortedNotes.map(\.id), [second.id, first.id])
        store.updateSelectedNoteBody("Updated")
        XCTAssertEqual(store.editorDraft.body, "Updated")
        XCTAssertEqual(store.notes.first(where: { $0.id == first.id })?.body, "")
        XCTAssertEqual(store.sortedNotes.first?.id, second.id)
        XCTAssertTrue(store.flushNow())
        XCTAssertEqual(store.sortedNotes.first?.id, first.id)
        XCTAssertEqual(repository.snapshot?.notes.first(where: { $0.id == first.id })?.body, "Updated")

        currentDate = Date(timeIntervalSince1970: 400)
        _ = store.createNote()
        XCTAssertEqual(store.sortedNotes.first?.updatedAt, currentDate)
    }

    func testUpdatesTitleForSpecificNoteWithoutChangingSelection() {
        let first = Note(title: "First")
        let second = Note(title: "Second")
        let repository = InMemoryNoteRepository(
            snapshot: StoreSnapshot(notes: [first, second], lastSelectedNoteID: first.id)
        )
        let store = AppStore(repository: repository, userDefaults: defaults, saveDebounce: 60)

        store.updateNoteTitle(second.id, title: "Renamed")

        XCTAssertEqual(store.notes.first(where: { $0.id == second.id })?.title, "Renamed")
        XCTAssertEqual(store.selectedNoteID, first.id)
        XCTAssertTrue(store.flushNow())
        XCTAssertEqual(repository.snapshot?.notes.first(where: { $0.id == second.id })?.title, "Renamed")
    }

    func testCategoryValidationAndFiltering() throws {
        let uncategorized = Note(title: "Loose")
        let repository = InMemoryNoteRepository(
            snapshot: StoreSnapshot(notes: [uncategorized], lastSelectedNoteID: uncategorized.id)
        )
        let store = AppStore(repository: repository, userDefaults: defaults, saveDebounce: 60)

        XCTAssertThrowsError(try store.createCategory(named: "   ")) { error in
            XCTAssertEqual(error as? CategoryCreationError, .emptyName)
        }

        let categoryID = try store.createCategory(named: " 개발 ")
        XCTAssertThrowsError(try store.createCategory(named: "개발")) { error in
            XCTAssertEqual(error as? CategoryCreationError, .duplicateName)
        }

        store.updateSelectedNoteCategory(categoryID)
        store.setFilter(.category(categoryID))
        XCTAssertEqual(store.filteredNotes.map(\.id), [uncategorized.id])
        store.setFilter(.uncategorized)
        XCTAssertTrue(store.filteredNotes.isEmpty)
    }

    func testCategoryCanBeRenamedAndDeletionCascadesToItsNotes() throws {
        let work = NoteCategory(name: "Work")
        let personal = NoteCategory(name: "Personal")
        let workNote1 = Note(title: "W1", categoryID: work.id)
        let workNote2 = Note(title: "W2", categoryID: work.id)
        let personalNote = Note(title: "P1", categoryID: personal.id)
        let repository = InMemoryNoteRepository(
            snapshot: StoreSnapshot(
                notes: [workNote1, workNote2, personalNote],
                categories: [work, personal],
                lastSelectedNoteID: workNote1.id
            )
        )
        let store = AppStore(repository: repository, userDefaults: defaults, saveDebounce: 60)

        try store.renameCategory(work.id, to: "Projects")
        XCTAssertEqual(store.categories.first(where: { $0.id == work.id })?.name, "Projects")
        XCTAssertThrowsError(try store.renameCategory(work.id, to: "personal")) { error in
            XCTAssertEqual(error as? CategoryCreationError, .duplicateName)
        }

        store.setFilter(.category(work.id))
        XCTAssertEqual(store.noteCount(in: work.id), 2)
        XCTAssertTrue(store.deleteCategory(work.id))

        XCTAssertFalse(store.categories.contains(where: { $0.id == work.id }))
        XCTAssertEqual(store.notes.map(\.id), [personalNote.id])
        XCTAssertEqual(store.noteFilter, .all)
        XCTAssertEqual(store.selectedNoteID, personalNote.id)
        XCTAssertEqual(repository.snapshot?.notes.map(\.id), [personalNote.id])
    }

    func testFailedCategoryDeletionKeepsCategoryAndNotes() {
        let category = NoteCategory(name: "Protected")
        let note = Note(title: "Keep", categoryID: category.id)
        let repository = InMemoryNoteRepository(
            snapshot: StoreSnapshot(notes: [note], categories: [category], lastSelectedNoteID: note.id)
        )
        let store = AppStore(repository: repository, userDefaults: defaults, saveDebounce: 60)
        repository.saveError = TestError.saveFailed

        XCTAssertFalse(store.deleteCategory(category.id))
        XCTAssertEqual(store.categories, [category])
        XCTAssertEqual(store.notes, [note])
    }

    func testNoteDeletionSelectsNextVisibleNoteAndRollsBackOnFailure() {
        let first = Note(title: "First", updatedAt: Date(timeIntervalSince1970: 200))
        let second = Note(title: "Second", updatedAt: Date(timeIntervalSince1970: 100))
        let repository = InMemoryNoteRepository(
            snapshot: StoreSnapshot(notes: [first, second], lastSelectedNoteID: first.id)
        )
        let store = AppStore(repository: repository, userDefaults: defaults, saveDebounce: 60)

        repository.saveError = TestError.saveFailed
        XCTAssertFalse(store.deleteNote(first.id))
        XCTAssertEqual(store.notes.map(\.id), [first.id, second.id])

        repository.saveError = nil
        XCTAssertTrue(store.deleteNote(first.id))
        XCTAssertEqual(store.notes.map(\.id), [second.id])
        XCTAssertEqual(store.selectedNoteID, second.id)
        XCTAssertEqual(repository.snapshot?.notes.map(\.id), [second.id])
    }

    func testCaptureSettingIsRestoredButScratchpadIsNotPersisted() {
        defaults.set(true, forKey: AppStore.captureDefaultsKey)
        let repository = InMemoryNoteRepository()
        let firstStore = AppStore(repository: repository, userDefaults: defaults, saveDebounce: 60)
        firstStore.appendScratchItem(text: "temporary", capturedAt: Date())

        let relaunchedStore = AppStore(repository: repository, userDefaults: defaults, saveDebounce: 60)

        XCTAssertTrue(relaunchedStore.isCaptureEnabled)
        XCTAssertTrue(relaunchedStore.scratchItems.isEmpty)
    }

    func testScratchpadChangesDoNotPublishTheWholeAppStore() {
        let store = AppStore(repository: InMemoryNoteRepository(), userDefaults: defaults)
        var appStoreDidPublish = false
        let cancellable = store.objectWillChange.sink {
            appStoreDidPublish = true
        }

        store.appendScratchItem(text: "Captured", capturedAt: Date())

        XCTAssertEqual(store.scratchItems.map(\.text), ["Captured"])
        XCTAssertFalse(appStoreDidPublish)
        withExtendedLifetime(cancellable) {}
    }

    func testScratchItemBuildsBoundedPreviewWithoutChangingOriginalText() {
        let longText = String(repeating: "Long text ", count: 200)
        let item = ScratchItem(text: longText)

        XCTAssertEqual(item.text, longText)
        XCTAssertTrue(item.isPreviewTruncated)
        XCTAssertLessThan(item.previewText.count, item.text.count)

        let shortItem = ScratchItem(text: "Short")
        XCTAssertFalse(shortItem.isPreviewTruncated)
        XCTAssertEqual(shortItem.previewText, "Short")
    }

    func testFontSettingsAreClampedAndRestored() {
        let repository = InMemoryNoteRepository()
        let store = AppStore(repository: repository, userDefaults: defaults, saveDebounce: 60)

        store.setUIFontSize(15)
        store.setNoteFontSize(20)
        store.setScratchpadFontSize(18)

        let relaunchedStore = AppStore(repository: repository, userDefaults: defaults, saveDebounce: 60)
        XCTAssertEqual(relaunchedStore.uiFontSize, 15)
        XCTAssertEqual(relaunchedStore.noteFontSize, 20)
        XCTAssertEqual(relaunchedStore.scratchpadFontSize, 18)

        relaunchedStore.setUIFontSize(100)
        relaunchedStore.setNoteFontSize(1)
        XCTAssertEqual(relaunchedStore.uiFontSize, AppStore.uiFontSizeRange.upperBound)
        XCTAssertEqual(relaunchedStore.noteFontSize, AppStore.contentFontSizeRange.lowerBound)
    }

    func testCategorySidebarVisibilityIsRestored() {
        let repository = InMemoryNoteRepository()
        let store = AppStore(repository: repository, userDefaults: defaults, saveDebounce: 60)
        XCTAssertTrue(store.isCategorySidebarVisible)

        store.setCategorySidebarVisible(false)
        let relaunchedStore = AppStore(repository: repository, userDefaults: defaults, saveDebounce: 60)
        XCTAssertFalse(relaunchedStore.isCategorySidebarVisible)

        relaunchedStore.setCategorySidebarVisible(true)
        XCTAssertTrue(relaunchedStore.isCategorySidebarVisible)
    }

    func testPopoverPinSettingIsRestoredAndNotifiesShell() {
        let repository = InMemoryNoteRepository()
        let store = AppStore(repository: repository, userDefaults: defaults, saveDebounce: 60)
        var notifiedValue: Bool?
        store.onKeepPopoverOpenChanged = { notifiedValue = $0 }

        store.setKeepsPopoverOpen(true)

        XCTAssertTrue(store.keepsPopoverOpen)
        XCTAssertEqual(notifiedValue, true)
        let relaunchedStore = AppStore(repository: repository, userDefaults: defaults, saveDebounce: 60)
        XCTAssertTrue(relaunchedStore.keepsPopoverOpen)
    }

    func testLaunchAtLoginUsesSystemRegistrationState() {
        let loginItems = FakeLoginItemManager(state: .disabled)
        let store = AppStore(
            repository: InMemoryNoteRepository(),
            userDefaults: defaults,
            saveDebounce: 60,
            loginItemManager: loginItems
        )

        store.setLaunchAtLoginEnabled(true)
        XCTAssertEqual(loginItems.registerCount, 1)
        XCTAssertTrue(store.launchAtLoginEnabled)

        store.setLaunchAtLoginEnabled(false)
        let updated = expectation(description: "login item state refreshed")
        DispatchQueue.main.async {
            XCTAssertEqual(loginItems.unregisterCount, 1)
            XCTAssertFalse(store.launchAtLoginEnabled)
            updated.fulfill()
        }
        wait(for: [updated], timeout: 1)

        loginItems.state = .requiresApproval
        store.refreshLoginItemState()
        XCTAssertTrue(store.launchAtLoginEnabled)
        XCTAssertTrue(store.loginItemNeedsApproval)
    }

    func testScratchpadSaveBuildsMarkdownAndClearsOnlyAfterSuccessfulWrite() {
        let repository = InMemoryNoteRepository()
        let store = AppStore(repository: repository, userDefaults: defaults, saveDebounce: 60)
        store.appendScratchItem(text: "First", capturedAt: Date(timeIntervalSince1970: 1))
        store.appendScratchItem(text: "Second", capturedAt: Date(timeIntervalSince1970: 2))

        XCTAssertEqual(store.scratchSuggestedTitle, "First")
        XCTAssertTrue(store.saveScratchpadAsNote(title: "Saved", categoryID: nil))
        XCTAssertTrue(store.scratchItems.isEmpty)
        XCTAssertEqual(store.selectedNote?.body, "First\n\n---\n\nSecond")

        store.appendScratchItem(text: "Keep me", capturedAt: Date())
        repository.saveError = TestError.saveFailed
        XCTAssertFalse(store.saveScratchpadAsNote(title: "Failure", categoryID: nil))
        XCTAssertEqual(store.scratchItems.map(\.text), ["Keep me"])
    }

    func testIndividualScratchItemCanBeCopiedAndDeletedIndependently() {
        let repository = InMemoryNoteRepository()
        let store = AppStore(repository: repository, userDefaults: defaults, saveDebounce: 60)
        store.appendScratchItem(text: "First item", capturedAt: Date(timeIntervalSince1970: 1))
        store.appendScratchItem(text: "Second item", capturedAt: Date(timeIntervalSince1970: 2))
        let firstItem = store.scratchItems[0]

        XCTAssertEqual(store.scratchSuggestedTitle(for: firstItem), "First item")
        XCTAssertTrue(
            store.copyScratchItemToNote(
                itemID: firstItem.id,
                title: "Copied",
                categoryID: nil
            )
        )
        XCTAssertEqual(store.selectedNote?.body, "First item")
        XCTAssertEqual(store.scratchItems.map(\.text), ["First item", "Second item"])

        store.deleteScratchItem(firstItem.id)
        XCTAssertEqual(store.scratchItems.map(\.text), ["Second item"])
    }

    func testDebouncedAutosave() {
        let saved = expectation(description: "debounced save")
        let repository = InMemoryNoteRepository(snapshot: StoreSnapshot(notes: [Note()]))
        repository.onSave = { saved.fulfill() }
        let store = AppStore(repository: repository, userDefaults: defaults, saveDebounce: 0.02)
        store.selectNote(store.notes.first?.id)

        store.updateSelectedNoteBody("one")
        store.updateSelectedNoteBody("two")

        wait(for: [saved], timeout: 1)
        XCTAssertEqual(repository.saveCount, 1)
        XCTAssertEqual(repository.snapshot?.notes.first?.body, "two")
    }

    func testBodyEditingStaysInDraftUntilDebounceCommitsIt() {
        let note = Note(body: "Original")
        let saved = expectation(description: "draft committed")
        let repository = InMemoryNoteRepository(
            snapshot: StoreSnapshot(notes: [note], lastSelectedNoteID: note.id)
        )
        repository.onSave = { saved.fulfill() }
        let store = AppStore(
            repository: repository,
            userDefaults: defaults,
            saveDebounce: 0.02
        )

        store.updateSelectedNoteBody("Draft")

        XCTAssertEqual(store.editorDraft.body, "Draft")
        XCTAssertEqual(store.selectedNote?.body, "Original")

        wait(for: [saved], timeout: 1)
        XCTAssertEqual(store.selectedNote?.body, "Draft")
        XCTAssertEqual(repository.snapshot?.notes.first?.body, "Draft")
    }

    func testSwitchingNotesFlushesDraftAndLoadsNextDraft() {
        let first = Note(body: "First")
        let second = Note(body: "Second")
        let repository = InMemoryNoteRepository(
            snapshot: StoreSnapshot(
                notes: [first, second],
                lastSelectedNoteID: first.id
            )
        )
        let store = AppStore(
            repository: repository,
            userDefaults: defaults,
            saveDebounce: 60
        )

        store.updateSelectedNoteBody("Edited first")
        store.selectNote(second.id)

        XCTAssertEqual(store.selectedNoteID, second.id)
        XCTAssertEqual(store.editorDraft.body, "Second")
        XCTAssertEqual(
            repository.snapshot?.notes.first(where: { $0.id == first.id })?.body,
            "Edited first"
        )
    }

    func testDebouncedPersistenceRunsOffMainThread() {
        let note = Note()
        let saved = expectation(description: "background save")
        let repository = InMemoryNoteRepository(
            snapshot: StoreSnapshot(notes: [note], lastSelectedNoteID: note.id)
        )
        var saveWasOnMainThread: Bool?
        repository.onSave = {
            saveWasOnMainThread = Thread.isMainThread
            saved.fulfill()
        }
        let store = AppStore(
            repository: repository,
            userDefaults: defaults,
            saveDebounce: 0.02
        )

        store.updateSelectedNoteBody("Background")

        wait(for: [saved], timeout: 1)
        XCTAssertEqual(saveWasOnMainThread, false)
    }

    func testMarkdownPreviewCacheParsesOnlyWhenSourceChanges() {
        let cache = MarkdownPreviewCache()

        cache.prepare(markdown: "# Heading")
        cache.prepare(markdown: "# Heading")
        XCTAssertEqual(cache.parseCount, 1)

        cache.prepare(markdown: "# Changed")
        XCTAssertEqual(cache.parseCount, 2)
    }

    func testMarkdownPreviewPreservesEditorLineBreaks() {
        let markdown = """
        First line
        Second line

        Third line
        """

        XCTAssertEqual(
            MarkdownPreviewCache.preservingLineBreaks(in: markdown),
            "First line  \nSecond line  \n\nThird line"
        )
    }

    func testMarkdownPreviewDoesNotChangeExplicitBreaksOrFencedCode() {
        let markdown = [
            "Intro\\",
            "Next  ",
            "```swift",
            "let first = 1",
            "let second = 2",
            "```",
            "Outro",
        ].joined(separator: "\n")

        XCTAssertEqual(
            MarkdownPreviewCache.preservingLineBreaks(in: markdown),
            markdown
        )
    }

    func testMarkdownFixtureContainsAllRequiredSyntax() {
        let fixture = """
        # Heading
        **bold** and *italic*
        - bullet
        1. numbered
        - [x] task
        `inline`
        ```swift
        let value = true
        ```
        [link](https://example.com)
        """

        ["# ", "**", "*italic*", "- bullet", "1. numbered", "- [x]", "`inline`", "```", "](https://"]
            .forEach { XCTAssertTrue(fixture.contains($0)) }
    }

    func testShortcutRegistrationWarningReflectsConflictState() {
        let store = AppStore(repository: InMemoryNoteRepository(), userDefaults: defaults)

        store.updateShortcutRegistration(hasShortcut: true, isRegistered: false)
        XCTAssertNotNil(store.shortcutWarning)

        store.updateShortcutRegistration(hasShortcut: true, isRegistered: true)
        XCTAssertNil(store.shortcutWarning)

        store.updateShortcutRegistration(hasShortcut: false, isRegistered: false)
        XCTAssertNil(store.shortcutWarning)
    }

    func testAppLanguageCanBeChangedAndRestored() {
        let store = AppStore(repository: InMemoryNoteRepository(), userDefaults: defaults)
        XCTAssertEqual(store.appLanguage, .system)

        store.setAppLanguage(.japanese)
        let restoredStore = AppStore(
            repository: InMemoryNoteRepository(),
            userDefaults: defaults
        )

        XCTAssertEqual(restoredStore.appLanguage, .japanese)
        XCTAssertEqual(restoredStore.appLanguage.locale.language.languageCode?.identifier, "ja")

        restoredStore.setAppLanguage(.system)
        XCTAssertNil(defaults.string(forKey: AppStore.appLanguageDefaultsKey))
    }

    func testEditorModeIsPreservedAcrossPresentationAndRelaunch() {
        let note = Note(body: "# Preview")
        let repository = InMemoryNoteRepository(
            snapshot: StoreSnapshot(notes: [note], lastSelectedNoteID: note.id)
        )
        let store = AppStore(repository: repository, userDefaults: defaults)

        store.setEditorMode(.preview)
        store.prepareForPresentation()

        XCTAssertEqual(store.editorMode, .preview)
        XCTAssertNil(store.focusRequest)

        let relaunchedStore = AppStore(repository: repository, userDefaults: defaults)
        XCTAssertEqual(relaunchedStore.editorMode, .preview)
    }

    func testCreatingNoteSwitchesPreviewBackToEditMode() {
        let store = AppStore(repository: InMemoryNoteRepository(), userDefaults: defaults)
        store.setEditorMode(.preview)

        _ = store.createNote()

        XCTAssertEqual(store.editorMode, .edit)
        XCTAssertEqual(store.focusRequest?.target, .title)
    }

    func testPopoverSizeIsClampedToSupportedBounds() {
        XCTAssertEqual(
            PopoverLayout.clamped(CGSize(width: 100, height: 100)),
            PopoverLayout.minimumSize
        )
        XCTAssertEqual(
            PopoverLayout.clamped(CGSize(width: 2_000, height: 2_000)),
            PopoverLayout.maximumSize
        )
        XCTAssertEqual(
            PopoverLayout.clamped(CGSize(width: 1_000, height: 700)),
            CGSize(width: 1_000, height: 700)
        )
    }
}

enum TestError: Error {
    case saveFailed
}

final class InMemoryNoteRepository: NoteRepository {
    let storeURL = URL(fileURLWithPath: "/tmp/clipstow-test.json")
    var snapshot: StoreSnapshot?
    var saveError: Error?
    var saveCount = 0
    var onSave: (() -> Void)?

    init(snapshot: StoreSnapshot = StoreSnapshot()) {
        self.snapshot = snapshot
    }

    func load() throws -> StoreSnapshot {
        snapshot ?? StoreSnapshot()
    }

    func save(_ snapshot: StoreSnapshot) throws {
        if let saveError { throw saveError }
        self.snapshot = snapshot
        saveCount += 1
        onSave?()
    }
}

final class FakeLoginItemManager: LoginItemManaging {
    var state: LoginItemState
    var registerError: Error?
    var unregisterError: Error?
    var registerCount = 0
    var unregisterCount = 0

    init(state: LoginItemState) {
        self.state = state
    }

    func register() throws {
        registerCount += 1
        if let registerError { throw registerError }
        state = .enabled
    }

    func unregister(completion: @escaping (Error?) -> Void) {
        unregisterCount += 1
        if unregisterError == nil {
            state = .disabled
        }
        completion(unregisterError)
    }
}
