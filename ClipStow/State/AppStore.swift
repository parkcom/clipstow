import Combine
import Foundation

enum CategoryCreationError: LocalizedError, Equatable {
    case emptyName
    case duplicateName
    case notFound

    var errorDescription: String? {
        switch self {
        case .emptyName:
            return L10n.string("카테고리 이름을 입력하세요.")
        case .duplicateName:
            return L10n.string("이미 같은 이름의 카테고리가 있습니다.")
        case .notFound:
            return L10n.string("카테고리를 찾을 수 없습니다.")
        }
    }
}

final class EditorDraft: ObservableObject {
    @Published private(set) var body = ""
    private(set) var noteID: UUID?
    private(set) var isDirty = false

    func load(_ note: Note?) {
        noteID = note?.id
        let nextBody = note?.body ?? ""
        if body != nextBody {
            body = nextBody
        }
        isDirty = false
    }

    func updateBody(_ body: String) {
        guard self.body != body else { return }
        self.body = body
        isDirty = true
    }

    func markCommitted() {
        isDirty = false
    }
}

final class ScratchpadState: ObservableObject {
    @Published private(set) var items: [ScratchItem] = []

    func append(text: String, capturedAt: Date) {
        guard text.containsNonWhitespaceAndNewline else { return }
        items.append(ScratchItem(text: text, capturedAt: capturedAt))
    }

    func clear() {
        items.removeAll()
    }

    func delete(_ itemID: UUID) {
        items.removeAll { $0.id == itemID }
    }
}

struct NoteCountSummary {
    let uncategorized: Int
    let byCategory: [UUID: Int]

    init(notes: [Note]) {
        var uncategorized = 0
        var byCategory: [UUID: Int] = [:]

        for note in notes {
            if let categoryID = note.categoryID {
                byCategory[categoryID, default: 0] += 1
            } else {
                uncategorized += 1
            }
        }

        self.uncategorized = uncategorized
        self.byCategory = byCategory
    }
}

enum NoteEditorMode: String, CaseIterable, Identifiable {
    case edit
    case preview

    var id: Self { self }
}

final class AppStore: ObservableObject {
    static let captureDefaultsKey = "copyCaptureEnabled"
    static let uiFontSizeDefaultsKey = "uiFontSize"
    static let noteFontSizeDefaultsKey = "noteFontSize"
    static let scratchpadFontSizeDefaultsKey = "scratchpadFontSize"
    static let categorySidebarVisibleDefaultsKey = "categorySidebarVisible"
    static let keepPopoverOpenDefaultsKey = "keepPopoverOpen"
    static let appLanguageDefaultsKey = L10n.languageDefaultsKey
    static let editorModeDefaultsKey = "noteEditorMode"

    static let defaultUIFontSize = 13.0
    static let defaultNoteFontSize = 14.0
    static let defaultScratchpadFontSize = 13.0
    static let uiFontSizeRange = 11.0...16.0
    static let contentFontSizeRange = 11.0...24.0

    @Published private(set) var notes: [Note] = []
    @Published private(set) var categories: [NoteCategory] = []
    @Published var selectedNoteID: UUID?
    @Published private(set) var noteFilter: NoteFilter = .all
    @Published private(set) var isCaptureEnabled: Bool
    @Published private(set) var focusRequest: FocusRequest?
    @Published private(set) var persistenceError: String?
    @Published private(set) var pasteboardAccessMessage: String?
    @Published var shortcutWarning: String?
    @Published private(set) var isPersistenceReadOnly = false
    @Published private(set) var launchAtLoginEnabled: Bool
    @Published private(set) var loginItemNeedsApproval: Bool
    @Published private(set) var isUpdatingLoginItem = false
    @Published private(set) var settingsError: String?
    @Published private(set) var uiFontSize: Double
    @Published private(set) var noteFontSize: Double
    @Published private(set) var scratchpadFontSize: Double
    @Published private(set) var isCategorySidebarVisible: Bool
    @Published private(set) var keepsPopoverOpen: Bool
    @Published private(set) var appLanguage: AppLanguage
    @Published private(set) var editorMode: NoteEditorMode

    let editorDraft = EditorDraft()
    let scratchpadState = ScratchpadState()

    var onCaptureSettingChanged: ((Bool) -> Void)?
    var onKeepPopoverOpenChanged: ((Bool) -> Void)?
    var onShortcutSettingChanged: (() -> Void)?
    var onLanguageChanged: (() -> Void)?

    private let repository: NoteRepository
    private let userDefaults: UserDefaults
    private let saveDebounce: TimeInterval
    private let now: () -> Date
    private let loginItemManager: LoginItemManaging
    private let persistenceQueue = DispatchQueue(
        label: "com.parkcom.clipstow.persistence",
        qos: .utility
    )
    private var saveWorkItem: DispatchWorkItem?
    private var latestSaveGeneration = 0

    init(
        repository: NoteRepository,
        userDefaults: UserDefaults = .standard,
        saveDebounce: TimeInterval = 0.3,
        now: @escaping () -> Date = Date.init,
        loginItemManager: LoginItemManaging = SystemLoginItemManager()
    ) {
        self.repository = repository
        self.userDefaults = userDefaults
        self.saveDebounce = saveDebounce
        self.now = now
        self.loginItemManager = loginItemManager
        isCaptureEnabled = userDefaults.bool(forKey: Self.captureDefaultsKey)
        uiFontSize = Self.storedFontSize(
            in: userDefaults,
            key: Self.uiFontSizeDefaultsKey,
            defaultValue: Self.defaultUIFontSize,
            range: Self.uiFontSizeRange
        )
        noteFontSize = Self.storedFontSize(
            in: userDefaults,
            key: Self.noteFontSizeDefaultsKey,
            defaultValue: Self.defaultNoteFontSize,
            range: Self.contentFontSizeRange
        )
        scratchpadFontSize = Self.storedFontSize(
            in: userDefaults,
            key: Self.scratchpadFontSizeDefaultsKey,
            defaultValue: Self.defaultScratchpadFontSize,
            range: Self.contentFontSizeRange
        )
        isCategorySidebarVisible = userDefaults.object(
            forKey: Self.categorySidebarVisibleDefaultsKey
        ) == nil || userDefaults.bool(forKey: Self.categorySidebarVisibleDefaultsKey)
        keepsPopoverOpen = userDefaults.bool(forKey: Self.keepPopoverOpenDefaultsKey)
        appLanguage = userDefaults.string(forKey: Self.appLanguageDefaultsKey)
            .flatMap(AppLanguage.init(rawValue:))
            ?? .system
        editorMode = userDefaults.string(forKey: Self.editorModeDefaultsKey)
            .flatMap(NoteEditorMode.init(rawValue:))
            ?? .edit
        let loginItemState = loginItemManager.state
        launchAtLoginEnabled = loginItemState == .enabled || loginItemState == .requiresApproval
        loginItemNeedsApproval = loginItemState == .requiresApproval

        do {
            let snapshot = try repository.load()
            notes = snapshot.notes
            categories = snapshot.categories
            if let selectedID = snapshot.lastSelectedNoteID,
               notes.contains(where: { $0.id == selectedID }) {
                selectedNoteID = selectedID
            } else {
                selectedNoteID = sortedNotes.first?.id
            }
        } catch {
            persistenceError = error.localizedDescription
            isPersistenceReadOnly = true
        }
        editorDraft.load(selectedNote)
    }

    deinit {
        saveWorkItem?.cancel()
    }

    var sortedNotes: [Note] {
        notes.sorted {
            if $0.updatedAt == $1.updatedAt {
                return $0.createdAt > $1.createdAt
            }
            return $0.updatedAt > $1.updatedAt
        }
    }

    var filteredNotes: [Note] {
        sortedNotes.filter { note in
            switch noteFilter {
            case .all:
                return true
            case .uncategorized:
                return note.categoryID == nil
            case .category(let categoryID):
                return note.categoryID == categoryID
            }
        }
    }

    var noteCounts: NoteCountSummary {
        NoteCountSummary(notes: notes)
    }

    var selectedNote: Note? {
        guard let selectedNoteID else { return nil }
        return notes.first(where: { $0.id == selectedNoteID })
    }

    var scratchItems: [ScratchItem] {
        scratchpadState.items
    }

    var scratchSuggestedTitle: String {
        scratchItems.first.map(scratchSuggestedTitle(for:)) ?? "Scratchpad"
    }

    var scratchMarkdownBody: String {
        scratchItems.map(\.text).joined(separator: "\n\n---\n\n")
    }

    func prepareForPresentation(focus target: EditorFocusTarget = .body) {
        if notes.isEmpty {
            _ = createNote(focus: target)
            return
        }

        if selectedNote == nil {
            selectedNoteID = sortedNotes.first?.id
            editorDraft.load(selectedNote)
        } else if editorDraft.noteID != selectedNoteID {
            editorDraft.load(selectedNote)
        }
        if editorMode == .edit {
            requestFocus(target, switchesToEditMode: false)
        }
    }

    @discardableResult
    func createNote(focus target: EditorFocusTarget = .title) -> UUID? {
        guard !isPersistenceReadOnly else { return nil }

        commitEditorDraftIfNeeded()

        let categoryID: UUID?
        if case .category(let selectedCategoryID) = noteFilter {
            categoryID = selectedCategoryID
        } else {
            categoryID = nil
        }

        let timestamp = now()
        let note = Note(categoryID: categoryID, createdAt: timestamp, updatedAt: timestamp)
        notes.append(note)
        selectedNoteID = note.id
        editorDraft.load(note)
        scheduleSave()
        requestFocus(target)
        return note.id
    }

    func selectNote(_ noteID: UUID?) {
        guard selectedNoteID != noteID else { return }
        _ = flushNow()
        selectedNoteID = noteID
        editorDraft.load(selectedNote)
        scheduleSave()
    }

    func setFilter(_ filter: NoteFilter) {
        noteFilter = filter
        let visibleNotes = filteredNotes
        if let selectedNoteID,
           visibleNotes.contains(where: { $0.id == selectedNoteID }) {
            return
        }
        commitEditorDraftIfNeeded()
        self.selectedNoteID = visibleNotes.first?.id
        editorDraft.load(selectedNote)
        scheduleSave()
    }

    func updateSelectedNoteTitle(_ title: String) {
        updateSelectedNote { $0.title = title }
    }

    func updateNoteTitle(_ noteID: UUID, title: String) {
        guard !isPersistenceReadOnly,
              let index = notes.firstIndex(where: { $0.id == noteID }) else { return }
        notes[index].title = title
        notes[index].updatedAt = now()
        scheduleSave()
    }

    func updateSelectedNoteBody(_ body: String) {
        guard !isPersistenceReadOnly, selectedNoteID != nil else { return }
        if editorDraft.noteID != selectedNoteID {
            editorDraft.load(selectedNote)
        }
        editorDraft.updateBody(body)
        scheduleSave()
    }

    func updateSelectedNoteCategory(_ categoryID: UUID?) {
        updateSelectedNote { $0.categoryID = categoryID }
        if case .category(let filterCategoryID) = noteFilter,
           categoryID != filterCategoryID {
            setFilter(.all)
        } else if noteFilter == .uncategorized, categoryID != nil {
            setFilter(.all)
        }
    }

    @discardableResult
    func createCategory(named rawName: String) throws -> UUID {
        guard !isPersistenceReadOnly else {
            throw NoteRepositoryError.unreadableStore(L10n.string("저장소가 읽기 전용 상태입니다."))
        }

        let name = rawName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { throw CategoryCreationError.emptyName }
        guard !categories.contains(where: {
            $0.name.compare(name, options: [.caseInsensitive, .diacriticInsensitive]) == .orderedSame
        }) else {
            throw CategoryCreationError.duplicateName
        }

        let category = NoteCategory(name: name, createdAt: now())
        categories.append(category)
        categories.sort { $0.createdAt < $1.createdAt }
        scheduleSave()
        return category.id
    }

    func noteCount(in categoryID: UUID) -> Int {
        notes.lazy.filter { $0.categoryID == categoryID }.count
    }

    func renameCategory(_ categoryID: UUID, to rawName: String) throws {
        guard !isPersistenceReadOnly else {
            throw NoteRepositoryError.unreadableStore(L10n.string("저장소가 읽기 전용 상태입니다."))
        }
        guard let index = categories.firstIndex(where: { $0.id == categoryID }) else {
            throw CategoryCreationError.notFound
        }

        let name = rawName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { throw CategoryCreationError.emptyName }
        guard !categories.contains(where: {
            $0.id != categoryID &&
                $0.name.compare(name, options: [.caseInsensitive, .diacriticInsensitive]) == .orderedSame
        }) else {
            throw CategoryCreationError.duplicateName
        }

        cancelScheduledSaveAndCommitEditorDraft()

        var nextCategories = categories
        nextCategories[index].name = name
        let nextSnapshot = StoreSnapshot(
            notes: notes,
            categories: nextCategories,
            lastSelectedNoteID: selectedNoteID
        )

        do {
            try saveSnapshotSynchronously(nextSnapshot).get()
            categories = nextCategories
            persistenceError = nil
        } catch {
            persistenceError = L10n.format(
                "카테고리 이름을 변경하지 못했습니다. %@",
                error.localizedDescription
            )
            throw error
        }
    }

    @discardableResult
    func deleteCategory(_ categoryID: UUID) -> Bool {
        guard !isPersistenceReadOnly,
              categories.contains(where: { $0.id == categoryID }) else { return false }

        cancelScheduledSaveAndCommitEditorDraft()

        let nextCategories = categories.filter { $0.id != categoryID }
        let nextNotes = notes.filter { $0.categoryID != categoryID }
        let nextFilter: NoteFilter = noteFilter == .category(categoryID) ? .all : noteFilter
        let nextSelectedNoteID = nextSelectedNoteID(
            currentSelection: selectedNoteID,
            notes: nextNotes,
            filter: nextFilter
        )
        let nextSnapshot = StoreSnapshot(
            notes: nextNotes,
            categories: nextCategories,
            lastSelectedNoteID: nextSelectedNoteID
        )

        do {
            try saveSnapshotSynchronously(nextSnapshot).get()
            categories = nextCategories
            notes = nextNotes
            noteFilter = nextFilter
            selectedNoteID = nextSelectedNoteID
            editorDraft.load(selectedNote)
            persistenceError = nil
            return true
        } catch {
            persistenceError = L10n.format(
                "카테고리와 포함된 노트를 삭제하지 못했습니다. %@",
                error.localizedDescription
            )
            return false
        }
    }

    @discardableResult
    func deleteNote(_ noteID: UUID) -> Bool {
        guard !isPersistenceReadOnly,
              notes.contains(where: { $0.id == noteID }) else { return false }

        cancelScheduledSaveAndCommitEditorDraft()

        let nextNotes = notes.filter { $0.id != noteID }
        let nextSelectedNoteID = nextSelectedNoteID(
            currentSelection: selectedNoteID == noteID ? nil : selectedNoteID,
            notes: nextNotes,
            filter: noteFilter
        )
        let nextSnapshot = StoreSnapshot(
            notes: nextNotes,
            categories: categories,
            lastSelectedNoteID: nextSelectedNoteID
        )

        do {
            try saveSnapshotSynchronously(nextSnapshot).get()
            notes = nextNotes
            selectedNoteID = nextSelectedNoteID
            editorDraft.load(selectedNote)
            persistenceError = nil
            return true
        } catch {
            persistenceError = L10n.format("노트를 삭제하지 못했습니다. %@", error.localizedDescription)
            return false
        }
    }

    func setCaptureEnabled(_ enabled: Bool) {
        guard isCaptureEnabled != enabled else { return }
        isCaptureEnabled = enabled
        userDefaults.set(enabled, forKey: Self.captureDefaultsKey)
        onCaptureSettingChanged?(enabled)
        if !enabled {
            pasteboardAccessMessage = nil
        }
    }

    func setLaunchAtLoginEnabled(_ enabled: Bool) {
        guard !isUpdatingLoginItem else { return }
        settingsError = nil
        isUpdatingLoginItem = true

        if enabled {
            do {
                try loginItemManager.register()
                isUpdatingLoginItem = false
                refreshLoginItemState()
            } catch {
                isUpdatingLoginItem = false
                refreshLoginItemState()
                settingsError = L10n.format(
                    "로그인 시 실행을 켜지 못했습니다. %@",
                    error.localizedDescription
                )
            }
        } else {
            loginItemManager.unregister { [weak self] error in
                DispatchQueue.main.async {
                    guard let self else { return }
                    self.isUpdatingLoginItem = false
                    self.refreshLoginItemState()
                    if let error {
                        self.settingsError = L10n.format(
                            "로그인 시 실행을 끄지 못했습니다. %@",
                            error.localizedDescription
                        )
                    }
                }
            }
        }
    }

    func refreshLoginItemState() {
        switch loginItemManager.state {
        case .disabled:
            launchAtLoginEnabled = false
            loginItemNeedsApproval = false
        case .enabled:
            launchAtLoginEnabled = true
            loginItemNeedsApproval = false
        case .requiresApproval:
            launchAtLoginEnabled = true
            loginItemNeedsApproval = true
        case .unavailable:
            launchAtLoginEnabled = false
            loginItemNeedsApproval = false
            if settingsError == nil {
                settingsError = L10n.string("이 빌드에서는 로그인 시 실행을 사용할 수 없습니다.")
            }
        }
    }

    func setUIFontSize(_ value: Double) {
        uiFontSize = value.clamped(to: Self.uiFontSizeRange)
        userDefaults.set(uiFontSize, forKey: Self.uiFontSizeDefaultsKey)
    }

    func setNoteFontSize(_ value: Double) {
        noteFontSize = value.clamped(to: Self.contentFontSizeRange)
        userDefaults.set(noteFontSize, forKey: Self.noteFontSizeDefaultsKey)
    }

    func setScratchpadFontSize(_ value: Double) {
        scratchpadFontSize = value.clamped(to: Self.contentFontSizeRange)
        userDefaults.set(scratchpadFontSize, forKey: Self.scratchpadFontSizeDefaultsKey)
    }

    func resetFontSizes() {
        setUIFontSize(Self.defaultUIFontSize)
        setNoteFontSize(Self.defaultNoteFontSize)
        setScratchpadFontSize(Self.defaultScratchpadFontSize)
    }

    func setCategorySidebarVisible(_ visible: Bool) {
        guard isCategorySidebarVisible != visible else { return }
        isCategorySidebarVisible = visible
        userDefaults.set(visible, forKey: Self.categorySidebarVisibleDefaultsKey)
    }

    func setKeepsPopoverOpen(_ keepsOpen: Bool) {
        guard keepsPopoverOpen != keepsOpen else { return }
        keepsPopoverOpen = keepsOpen
        userDefaults.set(keepsOpen, forKey: Self.keepPopoverOpenDefaultsKey)
        onKeepPopoverOpenChanged?(keepsOpen)
    }

    func setAppLanguage(_ language: AppLanguage) {
        guard appLanguage != language else { return }
        appLanguage = language
        if language == .system {
            userDefaults.removeObject(forKey: Self.appLanguageDefaultsKey)
        } else {
            userDefaults.set(language.rawValue, forKey: Self.appLanguageDefaultsKey)
        }
        onLanguageChanged?()
    }

    func setEditorMode(_ mode: NoteEditorMode) {
        guard editorMode != mode else { return }
        editorMode = mode
        userDefaults.set(mode.rawValue, forKey: Self.editorModeDefaultsKey)
    }

    func shortcutSettingDidChange() {
        onShortcutSettingChanged?()
    }

    func updateShortcutRegistration(hasShortcut: Bool, isRegistered: Bool) {
        guard hasShortcut else {
            shortcutWarning = nil
            return
        }
        shortcutWarning = isRegistered
            ? nil
            : L10n.string("선택한 단축키가 시스템 또는 다른 앱에서 사용 중입니다. 다른 조합을 선택하세요.")
    }

    func appendScratchItem(text: String, capturedAt: Date) {
        scratchpadState.append(text: text, capturedAt: capturedAt)
    }

    func clearScratchpad() {
        scratchpadState.clear()
    }

    func deleteScratchItem(_ itemID: UUID) {
        scratchpadState.delete(itemID)
    }

    func scratchSuggestedTitle(for item: ScratchItem) -> String {
        if let line = item.text
            .split(whereSeparator: \Character.isNewline)
            .map(String.init)
            .first(where: { !$0.trimmingCharacters(in: .whitespaces).isEmpty }) {
            return String(line.trimmingCharacters(in: .whitespaces).prefix(60))
        }
        return "Scratchpad"
    }

    @discardableResult
    func copyScratchItemToNote(itemID: UUID, title: String, categoryID: UUID?) -> Bool {
        guard let item = scratchItems.first(where: { $0.id == itemID }) else { return false }
        return persistNewNote(title: title, body: item.text, categoryID: categoryID)
    }

    @discardableResult
    func saveScratchpadAsNote(title: String, categoryID: UUID?) -> Bool {
        guard !isPersistenceReadOnly, !scratchItems.isEmpty else { return false }
        if persistNewNote(title: title, body: scratchMarkdownBody, categoryID: categoryID) {
            scratchpadState.clear()
            return true
        }
        return false
    }

    func updatePasteboardAccessState(_ state: PasteboardAccessState) {
        guard isCaptureEnabled else {
            pasteboardAccessMessage = nil
            return
        }
        switch state {
        case .unrestricted:
            pasteboardAccessMessage = nil
        case .asksPermission:
            pasteboardAccessMessage = L10n.string("클립보드를 읽을 때 macOS가 접근 허용을 요청할 수 있습니다.")
        case .denied:
            pasteboardAccessMessage = L10n.string("클립보드 접근이 차단되어 Copy Capture가 일시 중지되었습니다.")
        }
    }

    func requestFocus(
        _ target: EditorFocusTarget,
        switchesToEditMode: Bool = true
    ) {
        if switchesToEditMode {
            setEditorMode(.edit)
        }
        focusRequest = FocusRequest(target: target)
    }

    @discardableResult
    func flushNow() -> Bool {
        cancelScheduledSaveAndCommitEditorDraft()
        guard !isPersistenceReadOnly else { return false }

        do {
            try saveSnapshotSynchronously(snapshot()).get()
            persistenceError = nil
            return true
        } catch {
            persistenceError = L10n.format(
                "자동 저장에 실패했습니다. 편집 내용은 앱이 실행되는 동안 유지됩니다. %@",
                error.localizedDescription
            )
            return false
        }
    }

    private func updateSelectedNote(_ mutation: (inout Note) -> Void) {
        guard !isPersistenceReadOnly,
              let selectedNoteID,
              let index = notes.firstIndex(where: { $0.id == selectedNoteID }) else { return }
        commitEditorDraftIfNeeded()
        mutation(&notes[index])
        notes[index].updatedAt = now()
        scheduleSave()
    }

    private func persistNewNote(title: String, body: String, categoryID: UUID?) -> Bool {
        guard !isPersistenceReadOnly else { return false }

        cancelScheduledSaveAndCommitEditorDraft()

        let timestamp = now()
        let note = Note(
            title: title.trimmingCharacters(in: .whitespacesAndNewlines),
            body: body,
            categoryID: categoryID,
            createdAt: timestamp,
            updatedAt: timestamp
        )
        var nextNotes = notes
        nextNotes.append(note)
        let nextSnapshot = StoreSnapshot(
            notes: nextNotes,
            categories: categories,
            lastSelectedNoteID: note.id
        )

        do {
            try saveSnapshotSynchronously(nextSnapshot).get()
            notes = nextNotes
            selectedNoteID = note.id
            editorDraft.load(note)
            persistenceError = nil
            requestFocus(.body)
            return true
        } catch {
            persistenceError = L10n.format(
                "노트를 저장하지 못했습니다. Scratchpad는 유지됩니다. %@",
                error.localizedDescription
            )
            return false
        }
    }

    private func nextSelectedNoteID(
        currentSelection: UUID?,
        notes candidateNotes: [Note],
        filter: NoteFilter
    ) -> UUID? {
        if let currentSelection,
           candidateNotes.contains(where: { $0.id == currentSelection && note($0, matches: filter) }) {
            return currentSelection
        }
        return candidateNotes
            .filter { note($0, matches: filter) }
            .sorted {
                if $0.updatedAt == $1.updatedAt {
                    return $0.createdAt > $1.createdAt
                }
                return $0.updatedAt > $1.updatedAt
            }
            .first?
            .id
    }

    private func note(_ note: Note, matches filter: NoteFilter) -> Bool {
        switch filter {
        case .all:
            return true
        case .uncategorized:
            return note.categoryID == nil
        case .category(let categoryID):
            return note.categoryID == categoryID
        }
    }

    private func scheduleSave() {
        guard !isPersistenceReadOnly else { return }
        saveWorkItem?.cancel()
        let workItem = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.saveWorkItem = nil
            self.commitEditorDraftIfNeeded()
            self.enqueueSave(self.snapshot())
        }
        saveWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + saveDebounce, execute: workItem)
    }

    private func cancelScheduledSaveAndCommitEditorDraft() {
        saveWorkItem?.cancel()
        saveWorkItem = nil
        commitEditorDraftIfNeeded()
    }

    private func commitEditorDraftIfNeeded() {
        guard editorDraft.isDirty,
              let noteID = editorDraft.noteID,
              let index = notes.firstIndex(where: { $0.id == noteID }) else { return }

        notes[index].body = editorDraft.body
        notes[index].updatedAt = now()
        editorDraft.markCommitted()
    }

    private func enqueueSave(_ snapshot: StoreSnapshot) {
        latestSaveGeneration += 1
        let generation = latestSaveGeneration
        let repository = repository

        persistenceQueue.async { [weak self] in
            let result = Result<Void, Error> {
                try repository.save(snapshot)
            }
            DispatchQueue.main.async { [weak self] in
                guard let self, generation == self.latestSaveGeneration else { return }
                switch result {
                case .success:
                    self.persistenceError = nil
                case .failure(let error):
                    self.persistenceError = L10n.format(
                        "자동 저장에 실패했습니다. 편집 내용은 앱이 실행되는 동안 유지됩니다. %@",
                        error.localizedDescription
                    )
                }
            }
        }
    }

    private func saveSnapshotSynchronously(
        _ snapshot: StoreSnapshot
    ) -> Result<Void, Error> {
        latestSaveGeneration += 1
        let repository = repository
        return persistenceQueue.sync {
            Result {
                try repository.save(snapshot)
            }
        }
    }

    private func snapshot() -> StoreSnapshot {
        StoreSnapshot(notes: notes, categories: categories, lastSelectedNoteID: selectedNoteID)
    }

    private static func storedFontSize(
        in defaults: UserDefaults,
        key: String,
        defaultValue: Double,
        range: ClosedRange<Double>
    ) -> Double {
        guard defaults.object(forKey: key) != nil else { return defaultValue }
        return defaults.double(forKey: key).clamped(to: range)
    }
}

private extension Comparable {
    func clamped(to range: ClosedRange<Self>) -> Self {
        min(max(self, range.lowerBound), range.upperBound)
    }
}
