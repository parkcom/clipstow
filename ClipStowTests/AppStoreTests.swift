import Combine
import UniformTypeIdentifiers
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

    func testFolderBrowserListsNavigatesAndForgetsSelectedFolder() throws {
        let fileManager = FileManager.default
        let rootURL = fileManager.temporaryDirectory
            .appendingPathComponent("ClipStowFolderBrowserTests-\(UUID().uuidString)", isDirectory: true)
        let nestedURL = rootURL.appendingPathComponent("Nested", isDirectory: true)
        try fileManager.createDirectory(at: nestedURL, withIntermediateDirectories: true)
        try Data("alpha".utf8).write(to: rootURL.appendingPathComponent("Alpha.txt"))
        try Data("zulu".utf8).write(to: rootURL.appendingPathComponent("Zulu.txt"))
        try Data("hidden".utf8).write(to: rootURL.appendingPathComponent(".Hidden.txt"))
        try Data("nested".utf8).write(to: nestedURL.appendingPathComponent("Inside.md"))
        defer { try? fileManager.removeItem(at: rootURL) }

        let accessManager = FakeSecurityScopedFolderAccessManager()
        let state = FolderBrowserState(
            userDefaults: defaults,
            accessManager: accessManager
        )

        XCTAssertTrue(state.selectFolder(rootURL))
        XCTAssertEqual(state.items.map(\.name), ["Nested", "Alpha.txt", "Zulu.txt"])
        XCTAssertTrue(state.items[0].isDirectory)
        XCTAssertEqual(state.items[1].byteCount, 5)
        XCTAssertEqual(state.currentPathDescription, rootURL.lastPathComponent)
        XCTAssertNotNil(defaults.data(forKey: FolderBrowserState.bookmarkDefaultsKey))

        state.open(state.items[0])
        XCTAssertEqual(state.currentURL, nestedURL.standardizedFileURL)
        XCTAssertEqual(state.items.map(\.name), ["Inside.md"])
        XCTAssertFalse(state.isAtRoot)

        state.goUp()
        XCTAssertEqual(state.currentURL, rootURL.standardizedFileURL)
        XCTAssertTrue(state.isAtRoot)

        state.forgetFolder()
        XCTAssertNil(state.rootURL)
        XCTAssertTrue(state.items.isEmpty)
        XCTAssertNil(defaults.data(forKey: FolderBrowserState.bookmarkDefaultsKey))
        XCTAssertEqual(accessManager.startedURLs, [rootURL.standardizedFileURL])
        XCTAssertEqual(accessManager.stoppedURLs, [rootURL.standardizedFileURL])
    }

    func testFolderBrowserSortsEachColumnInBothDirections() {
        let rootURL = URL(fileURLWithPath: "/tmp/ClipStowFolderSortTests", isDirectory: true)
        let folder = FolderItem(
            url: rootURL.appendingPathComponent("Folder", isDirectory: true),
            isDirectory: true,
            byteCount: nil,
            modifiedAt: Date(timeIntervalSince1970: 400)
        )
        let alpha = FolderItem(
            url: rootURL.appendingPathComponent("Alpha.txt"),
            isDirectory: false,
            byteCount: 300,
            modifiedAt: Date(timeIntervalSince1970: 200)
        )
        let bravo = FolderItem(
            url: rootURL.appendingPathComponent("Bravo.txt"),
            isDirectory: false,
            byteCount: 100,
            modifiedAt: Date(timeIntervalSince1970: 300)
        )
        let charlie = FolderItem(
            url: rootURL.appendingPathComponent("Charlie.txt"),
            isDirectory: false,
            byteCount: 200,
            modifiedAt: Date(timeIntervalSince1970: 100)
        )
        let state = FolderBrowserState(
            userDefaults: defaults,
            contentsLoader: StubFolderContentsLoader(items: [charlie, folder, alpha, bravo]),
            accessManager: FakeSecurityScopedFolderAccessManager()
        )

        XCTAssertTrue(state.selectFolder(rootURL))
        XCTAssertEqual(state.sortColumn, .name)
        XCTAssertEqual(state.sortDirection, .ascending)
        XCTAssertEqual(state.items.map(\.name), ["Folder", "Alpha.txt", "Bravo.txt", "Charlie.txt"])

        state.select(alpha)
        state.sort(by: .name)
        XCTAssertEqual(state.sortDirection, .descending)
        XCTAssertEqual(state.items.map(\.name), ["Folder", "Charlie.txt", "Bravo.txt", "Alpha.txt"])
        XCTAssertEqual(state.selectedItem, alpha)

        state.sort(by: .modifiedDate)
        XCTAssertEqual(state.sortDirection, .ascending)
        XCTAssertEqual(state.items.map(\.name), ["Folder", "Charlie.txt", "Alpha.txt", "Bravo.txt"])

        state.sort(by: .modifiedDate)
        XCTAssertEqual(state.sortDirection, .descending)
        XCTAssertEqual(state.items.map(\.name), ["Folder", "Bravo.txt", "Alpha.txt", "Charlie.txt"])

        state.sort(by: .size)
        XCTAssertEqual(state.sortDirection, .ascending)
        XCTAssertEqual(state.items.map(\.name), ["Folder", "Bravo.txt", "Charlie.txt", "Alpha.txt"])

        state.sort(by: .size)
        XCTAssertEqual(state.sortDirection, .descending)
        XCTAssertEqual(state.items.map(\.name), ["Folder", "Alpha.txt", "Charlie.txt", "Bravo.txt"])

        state.forgetFolder()
    }

    func testFolderBrowserSelectsAllAndMovesSelectionToTrash() {
        let rootURL = URL(fileURLWithPath: "/tmp/ClipStowFolderTrashTests", isDirectory: true)
        let folder = FolderItem(
            url: rootURL.appendingPathComponent("Folder", isDirectory: true),
            isDirectory: true,
            byteCount: nil,
            modifiedAt: nil
        )
        let alpha = FolderItem(
            url: rootURL.appendingPathComponent("Alpha.txt"),
            isDirectory: false,
            byteCount: 10,
            modifiedAt: nil
        )
        let bravo = FolderItem(
            url: rootURL.appendingPathComponent("Bravo.txt"),
            isDirectory: false,
            byteCount: 20,
            modifiedAt: nil
        )
        let trasher = FakeFolderItemTrasher()
        let state = FolderBrowserState(
            userDefaults: defaults,
            contentsLoader: StubFolderContentsLoader(items: [bravo, folder, alpha]),
            accessManager: FakeSecurityScopedFolderAccessManager(),
            itemTrasher: trasher
        )

        XCTAssertTrue(state.selectFolder(rootURL))
        state.selectAll()

        XCTAssertEqual(state.selectionCount, 3)
        XCTAssertNil(state.selectedItem)
        XCTAssertTrue(state.moveToTrash(state.selectedItems))
        XCTAssertEqual(trasher.requestedURLs, [folder.url, alpha.url, bravo.url])
        XCTAssertTrue(state.items.isEmpty)
        XCTAssertEqual(state.selectionCount, 0)
        XCTAssertNil(state.accessError)

        state.forgetFolder()
    }

    func testFolderBrowserKeepsTrashFailuresSelectedAfterPartialSuccess() {
        let rootURL = URL(fileURLWithPath: "/tmp/ClipStowFolderTrashFailureTests", isDirectory: true)
        let alpha = FolderItem(
            url: rootURL.appendingPathComponent("Alpha.txt"),
            isDirectory: false,
            byteCount: 10,
            modifiedAt: nil
        )
        let bravo = FolderItem(
            url: rootURL.appendingPathComponent("Bravo.txt"),
            isDirectory: false,
            byteCount: 20,
            modifiedAt: nil
        )
        let trasher = FakeFolderItemTrasher(failingURLs: [bravo.url])
        let state = FolderBrowserState(
            userDefaults: defaults,
            contentsLoader: StubFolderContentsLoader(items: [alpha, bravo]),
            accessManager: FakeSecurityScopedFolderAccessManager(),
            itemTrasher: trasher
        )

        XCTAssertTrue(state.selectFolder(rootURL))
        state.selectAll()

        XCTAssertFalse(state.moveToTrash(state.selectedItems))
        XCTAssertEqual(trasher.requestedURLs, [alpha.url, bravo.url])
        XCTAssertEqual(state.items, [bravo])
        XCTAssertEqual(state.selectedItems, [bravo])
        XCTAssertEqual(state.selectedItem, bravo)
        XCTAssertNotNil(state.accessError)

        state.forgetFolder()
    }

    func testFolderBrowserAutomaticallyReloadsAfterMonitoredFolderChange() {
        let rootURL = URL(fileURLWithPath: "/tmp/ClipStowFolderMonitorTests", isDirectory: true)
        let alpha = FolderItem(
            url: rootURL.appendingPathComponent("Alpha.txt"),
            isDirectory: false,
            byteCount: 10,
            modifiedAt: nil
        )
        let bravo = FolderItem(
            url: rootURL.appendingPathComponent("Bravo.txt"),
            isDirectory: false,
            byteCount: 20,
            modifiedAt: nil
        )
        let loader = MutableFolderContentsLoader(items: [alpha])
        let monitor = FakeFolderChangeMonitor()
        let state = FolderBrowserState(
            userDefaults: defaults,
            contentsLoader: loader,
            accessManager: FakeSecurityScopedFolderAccessManager(),
            changeMonitor: monitor,
            autoReloadDelay: 0
        )

        XCTAssertTrue(state.selectFolder(rootURL))
        XCTAssertEqual(monitor.monitoredURLs, [rootURL.standardizedFileURL])
        XCTAssertEqual(state.items, [alpha])

        state.select(alpha)
        loader.items = [bravo]
        monitor.sendChange()

        XCTAssertEqual(state.items, [bravo])
        XCTAssertEqual(loader.requestedURLs.count, 2)
        XCTAssertEqual(state.selectionCount, 0)

        state.forgetFolder()
        XCTAssertFalse(monitor.isMonitoring)
    }

    func testFolderBrowserDuplicatesAndRenamesItems() throws {
        let rootURL = URL(fileURLWithPath: "/tmp/ClipStowFolderFileActionTests", isDirectory: true)
        let alpha = FolderItem(
            url: rootURL.appendingPathComponent("Alpha.txt"),
            isDirectory: false,
            byteCount: 10,
            modifiedAt: Date(timeIntervalSince1970: 100)
        )
        let firstCopyName = L10n.format("%@ 복사본%@", "Alpha", ".txt")
        let firstCopyURL = rootURL.appendingPathComponent(firstCopyName)
        let loader = MutableFolderContentsLoader(items: [alpha])
        let fileManager = FakeFolderItemFileManager(existingURLs: [alpha.url, firstCopyURL])
        fileManager.onCopy = { sourceURL, destinationURL in
            let source = try XCTUnwrap(loader.items.first { $0.url == sourceURL })
            loader.items.append(
                FolderItem(
                    url: destinationURL,
                    isDirectory: source.isDirectory,
                    byteCount: source.byteCount,
                    modifiedAt: source.modifiedAt
                )
            )
        }
        fileManager.onMove = { sourceURL, destinationURL in
            let source = try XCTUnwrap(loader.items.first { $0.url == sourceURL })
            loader.items.removeAll { $0.url == sourceURL }
            loader.items.append(
                FolderItem(
                    url: destinationURL,
                    isDirectory: source.isDirectory,
                    byteCount: source.byteCount,
                    modifiedAt: source.modifiedAt
                )
            )
        }
        let state = FolderBrowserState(
            userDefaults: defaults,
            contentsLoader: loader,
            accessManager: FakeSecurityScopedFolderAccessManager(),
            itemFileManager: fileManager,
            changeMonitor: FakeFolderChangeMonitor()
        )

        XCTAssertTrue(state.selectFolder(rootURL))
        XCTAssertTrue(state.duplicate([alpha]))

        let secondCopyName = L10n.format("%@ 복사본 %d%@", "Alpha", 2, ".txt")
        let duplicatedURL = rootURL.appendingPathComponent(secondCopyName).standardizedFileURL
        XCTAssertEqual(fileManager.copyRequests.count, 1)
        XCTAssertEqual(fileManager.copyRequests.first?.source, alpha.url.standardizedFileURL)
        XCTAssertEqual(fileManager.copyRequests.first?.destination, duplicatedURL)
        let duplicatedItem = try XCTUnwrap(state.selectedItem)
        XCTAssertEqual(duplicatedItem.url, duplicatedURL)

        XCTAssertTrue(state.rename(duplicatedItem, to: "Renamed.txt"))

        let renamedURL = rootURL.appendingPathComponent("Renamed.txt").standardizedFileURL
        XCTAssertEqual(fileManager.moveRequests.count, 1)
        XCTAssertEqual(fileManager.moveRequests.first?.source, duplicatedURL)
        XCTAssertEqual(fileManager.moveRequests.first?.destination, renamedURL)
        XCTAssertEqual(state.selectedItem?.url, renamedURL)

        state.forgetFolder()
    }

    func testFolderBrowserRestoresPersistedSecurityScopedBookmark() throws {
        let fileManager = FileManager.default
        let rootURL = fileManager.temporaryDirectory
            .appendingPathComponent("ClipStowFolderRestoreTests-\(UUID().uuidString)", isDirectory: true)
        try fileManager.createDirectory(at: rootURL, withIntermediateDirectories: true)
        try Data("restored".utf8).write(to: rootURL.appendingPathComponent("Restored.txt"))
        defer { try? fileManager.removeItem(at: rootURL) }

        let accessManager = FakeSecurityScopedFolderAccessManager()
        var firstState: FolderBrowserState? = FolderBrowserState(
            userDefaults: defaults,
            accessManager: accessManager
        )
        XCTAssertTrue(firstState?.selectFolder(rootURL) == true)

        let restoredState = FolderBrowserState(
            userDefaults: defaults,
            accessManager: accessManager
        )

        XCTAssertEqual(restoredState.rootURL, rootURL.standardizedFileURL)
        XCTAssertEqual(restoredState.items.map(\.name), ["Restored.txt"])
        XCTAssertEqual(accessManager.resolvedBookmarkCount, 1)

        firstState?.forgetFolder()
        firstState = nil
        restoredState.forgetFolder()
    }

    func testFolderBrowserKeepsExistingSelectionWhenNewFolderAccessFails() throws {
        let fileManager = FileManager.default
        let rootURL = fileManager.temporaryDirectory
            .appendingPathComponent("ClipStowFolderAccessTests-\(UUID().uuidString)", isDirectory: true)
        let rejectedURL = fileManager.temporaryDirectory
            .appendingPathComponent("ClipStowRejectedFolder-\(UUID().uuidString)", isDirectory: true)
        try fileManager.createDirectory(at: rootURL, withIntermediateDirectories: true)
        try fileManager.createDirectory(at: rejectedURL, withIntermediateDirectories: true)
        defer {
            try? fileManager.removeItem(at: rootURL)
            try? fileManager.removeItem(at: rejectedURL)
        }

        let accessManager = FakeSecurityScopedFolderAccessManager()
        let state = FolderBrowserState(
            userDefaults: defaults,
            accessManager: accessManager
        )
        XCTAssertTrue(state.selectFolder(rootURL))

        accessManager.rejectedURL = rejectedURL.standardizedFileURL
        XCTAssertFalse(state.selectFolder(rejectedURL))

        XCTAssertEqual(state.rootURL, rootURL.standardizedFileURL)
        XCTAssertNotNil(state.accessError)
    }

    func testTextFilePreviewIsBoundedWithoutChangingTheSourceFile() throws {
        let fileURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("ClipStowTextPreview-\(UUID().uuidString).txt")
        let source = String(repeating: "미리보기 줄\n", count: 60_000)
        try Data(source.utf8).write(to: fileURL)
        defer { try? FileManager.default.removeItem(at: fileURL) }

        let preview = try TextFilePreviewLoader.load(from: fileURL)

        XCTAssertTrue(preview.isTruncated)
        XCTAssertLessThanOrEqual(preview.text.utf8.count, TextFilePreviewLoader.byteLimit)
        XCTAssertTrue(source.hasPrefix(preview.text))
        XCTAssertEqual(try String(contentsOf: fileURL, encoding: .utf8), source)
    }

    func testFileDragProviderExportsAFileURLAndReadableFileRepresentation() throws {
        let fileURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("ClipStowDrag-\(UUID().uuidString).txt")
        try Data("drag me".utf8).write(to: fileURL)
        defer { try? FileManager.default.removeItem(at: fileURL) }

        let provider = FileDragProvider.make(for: fileURL)
        XCTAssertTrue(provider.registeredTypeIdentifiers.contains(UTType.fileURL.identifier))
        XCTAssertTrue(provider.registeredTypeIdentifiers.contains(UTType.plainText.identifier))

        let loaded = expectation(description: "file representation loaded")
        provider.loadFileRepresentation(forTypeIdentifier: UTType.plainText.identifier) { url, error in
            XCTAssertNil(error)
            do {
                let loadedURL = try XCTUnwrap(url)
                XCTAssertEqual(try String(contentsOf: loadedURL, encoding: .utf8), "drag me")
            } catch {
                XCTFail("Could not read dragged file representation: \(error)")
            }
            loaded.fulfill()
        }
        wait(for: [loaded], timeout: 2)
    }
}

enum TestError: Error {
    case saveFailed
    case trashFailed
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

final class FakeSecurityScopedFolderAccessManager: SecurityScopedFolderAccessManaging {
    var rejectedURL: URL?
    private(set) var startedURLs: [URL] = []
    private(set) var stoppedURLs: [URL] = []
    private(set) var resolvedBookmarkCount = 0

    func startAccessing(_ url: URL) -> Bool {
        let standardizedURL = url.standardizedFileURL
        guard standardizedURL != rejectedURL else { return false }
        startedURLs.append(standardizedURL)
        return true
    }

    func stopAccessing(_ url: URL) {
        stoppedURLs.append(url.standardizedFileURL)
    }

    func makeBookmark(for url: URL) throws -> Data {
        Data(url.standardizedFileURL.path.utf8)
    }

    func resolveBookmark(_ data: Data) throws -> (url: URL, isStale: Bool) {
        resolvedBookmarkCount += 1
        let path = try XCTUnwrap(String(data: data, encoding: .utf8))
        return (URL(fileURLWithPath: path), false)
    }
}

struct StubFolderContentsLoader: FolderContentsLoading {
    let items: [FolderItem]

    func contents(of directoryURL: URL) throws -> [FolderItem] {
        items
    }
}

final class MutableFolderContentsLoader: FolderContentsLoading {
    var items: [FolderItem]
    private(set) var requestedURLs: [URL] = []

    init(items: [FolderItem]) {
        self.items = items
    }

    func contents(of directoryURL: URL) throws -> [FolderItem] {
        requestedURLs.append(directoryURL.standardizedFileURL)
        return items
    }
}

final class FakeFolderChangeMonitor: FolderChangeMonitoring {
    private var onChange: (() -> Void)?
    private(set) var monitoredURLs: [URL] = []

    var isMonitoring: Bool {
        onChange != nil
    }

    func startMonitoring(_ url: URL, onChange: @escaping () -> Void) {
        monitoredURLs.append(url.standardizedFileURL)
        self.onChange = onChange
    }

    func stopMonitoring() {
        onChange = nil
    }

    func sendChange() {
        onChange?()
    }
}

final class FakeFolderItemFileManager: FolderItemFileManaging {
    struct Request {
        let source: URL
        let destination: URL
    }

    var onMove: ((URL, URL) throws -> Void)?
    var onCopy: ((URL, URL) throws -> Void)?
    private(set) var moveRequests: [Request] = []
    private(set) var copyRequests: [Request] = []
    private var existingURLs: Set<URL>

    init(existingURLs: Set<URL> = []) {
        self.existingURLs = Set(existingURLs.map(\.standardizedFileURL))
    }

    func moveItem(at sourceURL: URL, to destinationURL: URL) throws {
        let sourceURL = sourceURL.standardizedFileURL
        let destinationURL = destinationURL.standardizedFileURL
        moveRequests.append(Request(source: sourceURL, destination: destinationURL))
        try onMove?(sourceURL, destinationURL)
        existingURLs.remove(sourceURL)
        existingURLs.insert(destinationURL)
    }

    func copyItem(at sourceURL: URL, to destinationURL: URL) throws {
        let sourceURL = sourceURL.standardizedFileURL
        let destinationURL = destinationURL.standardizedFileURL
        copyRequests.append(Request(source: sourceURL, destination: destinationURL))
        try onCopy?(sourceURL, destinationURL)
        existingURLs.insert(destinationURL)
    }

    func itemExists(at url: URL) -> Bool {
        existingURLs.contains(url.standardizedFileURL)
    }
}

final class FakeFolderItemTrasher: FolderItemTrashing {
    let failingURLs: Set<URL>
    private(set) var requestedURLs: [URL] = []

    init(failingURLs: Set<URL> = []) {
        self.failingURLs = Set(failingURLs.map(\.standardizedFileURL))
    }

    func moveToTrash(_ url: URL) throws {
        let standardizedURL = url.standardizedFileURL
        requestedURLs.append(standardizedURL)
        if failingURLs.contains(standardizedURL) {
            throw TestError.trashFailed
        }
    }
}
