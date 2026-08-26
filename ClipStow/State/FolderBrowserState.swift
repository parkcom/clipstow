import CoreServices
import Foundation

struct FolderItem: Identifiable, Equatable {
    let url: URL
    let isDirectory: Bool
    let byteCount: Int64?
    let modifiedAt: Date?

    var id: String {
        url.standardizedFileURL.path
    }

    var name: String {
        url.lastPathComponent
    }
}

enum FolderSortColumn: Equatable {
    case name
    case modifiedDate
    case size
}

enum FolderSortDirection: Equatable {
    case ascending
    case descending

    mutating func toggle() {
        self = self == .ascending ? .descending : .ascending
    }
}

struct TextFilePreviewContent: Equatable {
    let text: String
    let isTruncated: Bool
}

enum TextFilePreviewLoader {
    static let byteLimit = 512 * 1_024

    static func load(from url: URL) throws -> TextFilePreviewContent {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }

        let data = try handle.read(upToCount: byteLimit + 1) ?? Data()
        let isTruncated = data.count > byteLimit
        let previewData = isTruncated ? Data(data.prefix(byteLimit)) : data
        let fallbackEncodings: [String.Encoding] = [
            .unicode,
            .utf16LittleEndian,
            .utf16BigEndian,
            .isoLatin1,
        ]
        let text = decodeUTF8(previewData)
            ?? fallbackEncodings.lazy.compactMap { String(data: previewData, encoding: $0) }.first
            ?? L10n.string("이 텍스트 파일의 인코딩을 읽을 수 없습니다.")

        return TextFilePreviewContent(text: text, isTruncated: isTruncated)
    }

    private static func decodeUTF8(_ data: Data) -> String? {
        if let text = String(data: data, encoding: .utf8) {
            return text
        }

        var trimmedData = data
        for _ in 0..<3 where !trimmedData.isEmpty {
            trimmedData.removeLast()
            if let text = String(data: trimmedData, encoding: .utf8) {
                return text
            }
        }
        return nil
    }
}

protocol FolderContentsLoading {
    func contents(of directoryURL: URL) throws -> [FolderItem]
}

struct FileManagerFolderContentsLoader: FolderContentsLoading {
    private let fileManager: FileManager

    init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
    }

    func contents(of directoryURL: URL) throws -> [FolderItem] {
        let keys: Set<URLResourceKey> = [
            .contentModificationDateKey,
            .fileSizeKey,
            .isDirectoryKey,
            .isPackageKey,
        ]
        let urls = try fileManager.contentsOfDirectory(
            at: directoryURL,
            includingPropertiesForKeys: Array(keys),
            options: [.skipsHiddenFiles]
        )

        return urls.map { url in
            let values = try? url.resourceValues(forKeys: keys)
            let isDirectory = values?.isDirectory == true && values?.isPackage != true
            return FolderItem(
                url: url,
                isDirectory: isDirectory,
                byteCount: isDirectory ? nil : values?.fileSize.map(Int64.init),
                modifiedAt: values?.contentModificationDate
            )
        }
    }
}

protocol FolderChangeMonitoring: AnyObject {
    func startMonitoring(_ url: URL, onChange: @escaping () -> Void)
    func stopMonitoring()
}

final class FSEventsFolderChangeMonitor: FolderChangeMonitoring {
    private var stream: FSEventStreamRef?
    private var onChange: (() -> Void)?

    deinit {
        stopMonitoring()
    }

    func startMonitoring(_ url: URL, onChange: @escaping () -> Void) {
        stopMonitoring()
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory),
              isDirectory.boolValue else {
            return
        }
        self.onChange = onChange

        var context = FSEventStreamContext(
            version: 0,
            info: Unmanaged.passUnretained(self).toOpaque(),
            retain: nil,
            release: nil,
            copyDescription: nil
        )
        let callback: FSEventStreamCallback = { _, info, _, _, _, _ in
            guard let info else { return }
            let monitor = Unmanaged<FSEventsFolderChangeMonitor>
                .fromOpaque(info)
                .takeUnretainedValue()
            monitor.onChange?()
        }
        let flags = FSEventStreamCreateFlags(
            kFSEventStreamCreateFlagFileEvents
                | kFSEventStreamCreateFlagNoDefer
                | kFSEventStreamCreateFlagWatchRoot
        )
        guard let nextStream = FSEventStreamCreate(
            nil,
            callback,
            &context,
            [url.standardizedFileURL.path] as CFArray,
            FSEventStreamEventId(kFSEventStreamEventIdSinceNow),
            0.2,
            flags
        ) else {
            self.onChange = nil
            return
        }

        FSEventStreamSetDispatchQueue(nextStream, .main)
        guard FSEventStreamStart(nextStream) else {
            FSEventStreamInvalidate(nextStream)
            FSEventStreamRelease(nextStream)
            self.onChange = nil
            return
        }
        stream = nextStream
    }

    func stopMonitoring() {
        onChange = nil
        guard let stream else { return }
        FSEventStreamStop(stream)
        FSEventStreamInvalidate(stream)
        FSEventStreamRelease(stream)
        self.stream = nil
    }
}

protocol FolderItemFileManaging {
    func moveItem(at sourceURL: URL, to destinationURL: URL) throws
    func copyItem(at sourceURL: URL, to destinationURL: URL) throws
    func itemExists(at url: URL) -> Bool
}

struct FileManagerFolderItemFileManager: FolderItemFileManaging {
    private let fileManager: FileManager

    init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
    }

    func moveItem(at sourceURL: URL, to destinationURL: URL) throws {
        try fileManager.moveItem(at: sourceURL, to: destinationURL)
    }

    func copyItem(at sourceURL: URL, to destinationURL: URL) throws {
        try fileManager.copyItem(at: sourceURL, to: destinationURL)
    }

    func itemExists(at url: URL) -> Bool {
        fileManager.fileExists(atPath: url.path)
    }
}

protocol FolderItemTrashing {
    func moveToTrash(_ url: URL) throws
}

struct FileManagerFolderItemTrasher: FolderItemTrashing {
    private let fileManager: FileManager

    init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
    }

    func moveToTrash(_ url: URL) throws {
        try fileManager.trashItem(at: url, resultingItemURL: nil)
    }
}

protocol SecurityScopedFolderAccessManaging {
    func startAccessing(_ url: URL) -> Bool
    func stopAccessing(_ url: URL)
    func makeBookmark(for url: URL) throws -> Data
    func resolveBookmark(_ data: Data) throws -> (url: URL, isStale: Bool)
}

struct SecurityScopedFolderAccessManager: SecurityScopedFolderAccessManaging {
    func startAccessing(_ url: URL) -> Bool {
        url.startAccessingSecurityScopedResource()
    }

    func stopAccessing(_ url: URL) {
        url.stopAccessingSecurityScopedResource()
    }

    func makeBookmark(for url: URL) throws -> Data {
        try url.bookmarkData(
            options: .withSecurityScope,
            includingResourceValuesForKeys: nil,
            relativeTo: nil
        )
    }

    func resolveBookmark(_ data: Data) throws -> (url: URL, isStale: Bool) {
        var isStale = false
        let url = try URL(
            resolvingBookmarkData: data,
            options: [.withSecurityScope, .withoutUI],
            relativeTo: nil,
            bookmarkDataIsStale: &isStale
        )
        return (url, isStale)
    }
}

final class FolderBrowserState: ObservableObject {
    static let bookmarkDefaultsKey = "selectedFolderBookmark"

    @Published private(set) var rootURL: URL?
    @Published private(set) var currentURL: URL?
    @Published private(set) var items: [FolderItem] = []
    @Published private(set) var selectedItemID: String?
    @Published private(set) var selectedItemIDs: Set<String> = []
    @Published private(set) var accessError: String?
    @Published private(set) var sortColumn: FolderSortColumn = .name
    @Published private(set) var sortDirection: FolderSortDirection = .ascending

    private let userDefaults: UserDefaults
    private let contentsLoader: FolderContentsLoading
    private let accessManager: SecurityScopedFolderAccessManaging
    private let itemTrasher: FolderItemTrashing
    private let itemFileManager: FolderItemFileManaging
    private let changeMonitor: FolderChangeMonitoring
    private let autoReloadDelay: TimeInterval
    private var scopedRootURL: URL?
    private var autoReloadWorkItem: DispatchWorkItem?

    init(
        userDefaults: UserDefaults = .standard,
        contentsLoader: FolderContentsLoading = FileManagerFolderContentsLoader(),
        accessManager: SecurityScopedFolderAccessManaging = SecurityScopedFolderAccessManager(),
        itemTrasher: FolderItemTrashing = FileManagerFolderItemTrasher(),
        itemFileManager: FolderItemFileManaging = FileManagerFolderItemFileManager(),
        changeMonitor: FolderChangeMonitoring = FSEventsFolderChangeMonitor(),
        autoReloadDelay: TimeInterval = 0.2
    ) {
        self.userDefaults = userDefaults
        self.contentsLoader = contentsLoader
        self.accessManager = accessManager
        self.itemTrasher = itemTrasher
        self.itemFileManager = itemFileManager
        self.changeMonitor = changeMonitor
        self.autoReloadDelay = autoReloadDelay
        restoreFolder()
    }

    deinit {
        autoReloadWorkItem?.cancel()
        changeMonitor.stopMonitoring()
        if let scopedRootURL {
            accessManager.stopAccessing(scopedRootURL)
        }
    }

    var selectedItem: FolderItem? {
        guard let selectedItemID else { return nil }
        return items.first { $0.id == selectedItemID }
    }

    var selectedItems: [FolderItem] {
        items.filter { selectedItemIDs.contains($0.id) }
    }

    var selectionCount: Int {
        selectedItemIDs.count
    }

    var isAtRoot: Bool {
        guard let rootURL, let currentURL else { return true }
        return rootURL.standardizedFileURL == currentURL.standardizedFileURL
    }

    var currentPathDescription: String {
        guard let rootURL, let currentURL else { return "" }
        let rootName = rootURL.lastPathComponent
        guard rootURL.standardizedFileURL != currentURL.standardizedFileURL else {
            return rootName
        }

        let rootComponents = rootURL.standardizedFileURL.pathComponents
        let currentComponents = currentURL.standardizedFileURL.pathComponents
        let relativeComponents = currentComponents.dropFirst(rootComponents.count)
        return ([rootName] + relativeComponents).joined(separator: " / ")
    }

    @discardableResult
    func selectFolder(_ url: URL) -> Bool {
        let nextRootURL = url.standardizedFileURL
        guard accessManager.startAccessing(nextRootURL) else {
            accessError = L10n.string("선택한 폴더에 접근할 수 없습니다. 폴더를 다시 선택하세요.")
            return false
        }

        do {
            let bookmark = try accessManager.makeBookmark(for: nextRootURL)
            let nextItems = try contentsLoader.contents(of: nextRootURL)
            replaceActiveFolder(
                with: nextRootURL,
                bookmark: bookmark,
                items: nextItems
            )
            return true
        } catch {
            accessManager.stopAccessing(nextRootURL)
            accessError = L10n.format("폴더를 열 수 없습니다. %@", error.localizedDescription)
            return false
        }
    }

    func forgetFolder() {
        autoReloadWorkItem?.cancel()
        autoReloadWorkItem = nil
        changeMonitor.stopMonitoring()
        if let scopedRootURL {
            accessManager.stopAccessing(scopedRootURL)
        }
        scopedRootURL = nil
        rootURL = nil
        currentURL = nil
        items = []
        selectedItemID = nil
        selectedItemIDs = []
        accessError = nil
        userDefaults.removeObject(forKey: Self.bookmarkDefaultsKey)
    }

    func select(_ item: FolderItem) {
        selectedItemID = item.id
        selectedItemIDs = [item.id]
    }

    func toggleSelection(of item: FolderItem) {
        guard items.contains(where: { $0.id == item.id }) else { return }
        if selectedItemIDs.contains(item.id) {
            selectedItemIDs.remove(item.id)
        } else {
            selectedItemIDs.insert(item.id)
        }
        updatePrimarySelection()
    }

    func selectAll() {
        selectedItemIDs = Set(items.map(\.id))
        updatePrimarySelection()
    }

    func isSelected(_ item: FolderItem) -> Bool {
        selectedItemIDs.contains(item.id)
    }

    @discardableResult
    func moveToTrash(_ requestedItems: [FolderItem]) -> Bool {
        let availableIDs = Set(items.map(\.id))
        var seenIDs: Set<String> = []
        let candidates = requestedItems.filter { item in
            availableIDs.contains(item.id) && seenIDs.insert(item.id).inserted
        }
        guard !candidates.isEmpty else { return false }

        var movedIDs: Set<String> = []
        var failures: [(item: FolderItem, error: Error)] = []
        for item in candidates {
            do {
                try itemTrasher.moveToTrash(item.url)
                movedIDs.insert(item.id)
            } catch {
                failures.append((item, error))
            }
        }

        if !movedIDs.isEmpty {
            items.removeAll { movedIDs.contains($0.id) }
            selectedItemIDs.subtract(movedIDs)
            updatePrimarySelection()
        }

        if let firstFailure = failures.first {
            if failures.count == 1 {
                accessError = L10n.format(
                    "‘%@’ 항목을 휴지통으로 이동할 수 없습니다. %@",
                    firstFailure.item.name,
                    firstFailure.error.localizedDescription
                )
            } else {
                accessError = L10n.format(
                    "%d개 항목을 휴지통으로 이동하지 못했습니다. %@",
                    failures.count,
                    firstFailure.error.localizedDescription
                )
            }
        } else {
            accessError = nil
        }

        return failures.isEmpty
    }

    @discardableResult
    func rename(_ item: FolderItem, to proposedName: String) -> Bool {
        guard items.contains(where: { $0.id == item.id }) else { return false }
        let name = proposedName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else {
            accessError = L10n.string("새 이름을 입력하세요.")
            return false
        }
        guard name != ".", name != "..", !name.contains("/") else {
            accessError = L10n.string("파일 이름에는 ‘/’를 사용할 수 없습니다.")
            return false
        }
        guard name != item.name else {
            accessError = nil
            return true
        }

        let destinationURL = item.url
            .deletingLastPathComponent()
            .appendingPathComponent(name, isDirectory: item.isDirectory)
            .standardizedFileURL
        guard !itemFileManager.itemExists(at: destinationURL) else {
            accessError = L10n.format("‘%@’ 이름의 항목이 이미 있습니다.", name)
            return false
        }

        do {
            try itemFileManager.moveItem(at: item.url, to: destinationURL)
            reload()
            if let renamedItem = items.first(where: { $0.id == destinationURL.path }) {
                select(renamedItem)
            }
            return true
        } catch {
            accessError = L10n.format(
                "‘%@’ 항목의 이름을 변경할 수 없습니다. %@",
                item.name,
                error.localizedDescription
            )
            return false
        }
    }

    @discardableResult
    func duplicate(_ requestedItems: [FolderItem]) -> Bool {
        let availableIDs = Set(items.map(\.id))
        var seenIDs: Set<String> = []
        let candidates = requestedItems.filter { item in
            availableIDs.contains(item.id) && seenIDs.insert(item.id).inserted
        }
        guard !candidates.isEmpty else { return false }

        var duplicatedURLs: [URL] = []
        var failures: [(item: FolderItem, error: Error)] = []
        for item in candidates {
            let destinationURL = uniqueDuplicateURL(for: item)
            do {
                try itemFileManager.copyItem(at: item.url, to: destinationURL)
                duplicatedURLs.append(destinationURL)
            } catch {
                failures.append((item, error))
            }
        }

        if !duplicatedURLs.isEmpty {
            reload()
            let duplicatedIDs = Set(duplicatedURLs.map { $0.standardizedFileURL.path })
            selectedItemIDs = Set(items.map(\.id)).intersection(duplicatedIDs)
            updatePrimarySelection()
        }

        if let firstFailure = failures.first {
            if failures.count == 1 {
                accessError = L10n.format(
                    "‘%@’ 항목을 복제할 수 없습니다. %@",
                    firstFailure.item.name,
                    firstFailure.error.localizedDescription
                )
            } else {
                accessError = L10n.format(
                    "%d개 항목을 복제하지 못했습니다. %@",
                    failures.count,
                    firstFailure.error.localizedDescription
                )
            }
        } else if !duplicatedURLs.isEmpty {
            accessError = nil
        }

        return failures.isEmpty
    }

    func sort(by column: FolderSortColumn) {
        if sortColumn == column {
            sortDirection.toggle()
        } else {
            sortColumn = column
            sortDirection = .ascending
        }
        items = sortedItems(items)
    }

    func open(_ item: FolderItem) {
        select(item)
        guard item.isDirectory else { return }
        navigate(to: item.url)
    }

    func goUp() {
        guard let rootURL, let currentURL, !isAtRoot else { return }
        let parentURL = currentURL.deletingLastPathComponent().standardizedFileURL
        guard parentURL.isContained(in: rootURL) else { return }
        navigate(to: parentURL)
    }

    func reload() {
        reload(preservingExistingError: false)
    }

    private func reload(preservingExistingError: Bool) {
        guard let currentURL else { return }
        let existingError = accessError
        do {
            let nextItems = try contentsLoader.contents(of: currentURL)
            items = sortedItems(nextItems)
            selectedItemIDs.formIntersection(Set(nextItems.map(\.id)))
            updatePrimarySelection()
            accessError = preservingExistingError ? existingError : nil
        } catch {
            accessError = L10n.format("폴더 내용을 새로 고칠 수 없습니다. %@", error.localizedDescription)
        }
    }

    private func restoreFolder() {
        guard let bookmark = userDefaults.data(forKey: Self.bookmarkDefaultsKey) else {
            return
        }

        do {
            let resolved = try accessManager.resolveBookmark(bookmark)
            let restoredURL = resolved.url.standardizedFileURL
            guard accessManager.startAccessing(restoredURL) else {
                accessError = L10n.string("저장된 폴더 접근 권한을 복원할 수 없습니다. 폴더를 다시 선택하세요.")
                return
            }

            do {
                let restoredItems = try contentsLoader.contents(of: restoredURL)
                let refreshedBookmark = resolved.isStale
                    ? try accessManager.makeBookmark(for: restoredURL)
                    : bookmark
                replaceActiveFolder(
                    with: restoredURL,
                    bookmark: refreshedBookmark,
                    items: restoredItems
                )
            } catch {
                accessManager.stopAccessing(restoredURL)
                throw error
            }
        } catch {
            accessError = L10n.format(
                "저장된 폴더 접근 권한을 복원할 수 없습니다. 폴더를 다시 선택하세요. %@",
                error.localizedDescription
            )
        }
    }

    private func replaceActiveFolder(
        with url: URL,
        bookmark: Data,
        items: [FolderItem]
    ) {
        autoReloadWorkItem?.cancel()
        autoReloadWorkItem = nil
        changeMonitor.stopMonitoring()
        if let scopedRootURL {
            accessManager.stopAccessing(scopedRootURL)
        }
        scopedRootURL = url
        rootURL = url
        currentURL = url
        self.items = sortedItems(items)
        selectedItemID = nil
        selectedItemIDs = []
        accessError = nil
        userDefaults.set(bookmark, forKey: Self.bookmarkDefaultsKey)
        startMonitoringChanges(in: url)
    }

    private func navigate(to url: URL) {
        guard let rootURL else { return }
        let nextURL = url.standardizedFileURL
        guard nextURL.isContained(in: rootURL) else { return }

        do {
            let nextItems = try contentsLoader.contents(of: nextURL)
            currentURL = nextURL
            items = sortedItems(nextItems)
            selectedItemID = nil
            selectedItemIDs = []
            accessError = nil
        } catch {
            accessError = L10n.format("폴더를 열 수 없습니다. %@", error.localizedDescription)
        }
    }

    private func sortedItems(_ items: [FolderItem]) -> [FolderItem] {
        items.sorted { lhs, rhs in
            if lhs.isDirectory != rhs.isDirectory {
                return lhs.isDirectory
            }

            switch sortColumn {
            case .name:
                return orderedBefore(
                    lhs,
                    rhs,
                    comparison: lhs.name.localizedStandardCompare(rhs.name)
                )
            case .modifiedDate:
                return orderedBefore(
                    lhs,
                    rhs,
                    lhsValue: lhs.modifiedAt,
                    rhsValue: rhs.modifiedAt
                )
            case .size:
                return orderedBefore(
                    lhs,
                    rhs,
                    lhsValue: lhs.byteCount,
                    rhsValue: rhs.byteCount
                )
            }
        }
    }

    private func orderedBefore<Value: Comparable>(
        _ lhs: FolderItem,
        _ rhs: FolderItem,
        lhsValue: Value?,
        rhsValue: Value?
    ) -> Bool {
        switch (lhsValue, rhsValue) {
        case let (.some(lhsValue), .some(rhsValue)):
            let comparison: ComparisonResult
            if lhsValue < rhsValue {
                comparison = .orderedAscending
            } else if lhsValue > rhsValue {
                comparison = .orderedDescending
            } else {
                comparison = .orderedSame
            }
            return orderedBefore(lhs, rhs, comparison: comparison)
        case (.some, .none):
            return true
        case (.none, .some):
            return false
        case (.none, .none):
            return nameTieBreak(lhs, rhs)
        }
    }

    private func orderedBefore(
        _ lhs: FolderItem,
        _ rhs: FolderItem,
        comparison: ComparisonResult
    ) -> Bool {
        guard comparison != .orderedSame else {
            return nameTieBreak(lhs, rhs)
        }
        switch sortDirection {
        case .ascending:
            return comparison == .orderedAscending
        case .descending:
            return comparison == .orderedDescending
        }
    }

    private func nameTieBreak(_ lhs: FolderItem, _ rhs: FolderItem) -> Bool {
        let comparison = lhs.name.localizedStandardCompare(rhs.name)
        guard comparison != .orderedSame else {
            return lhs.id < rhs.id
        }
        return comparison == .orderedAscending
    }

    private func updatePrimarySelection() {
        selectedItemID = selectedItemIDs.count == 1 ? selectedItemIDs.first : nil
    }

    private func startMonitoringChanges(in rootURL: URL) {
        changeMonitor.startMonitoring(rootURL) { [weak self] in
            guard let self else { return }
            if Thread.isMainThread {
                self.scheduleAutoReload()
            } else {
                DispatchQueue.main.async { [weak self] in
                    self?.scheduleAutoReload()
                }
            }
        }
    }

    private func scheduleAutoReload() {
        autoReloadWorkItem?.cancel()
        if autoReloadDelay == 0 {
            reload(preservingExistingError: true)
            return
        }

        let workItem = DispatchWorkItem { [weak self] in
            self?.reload(preservingExistingError: true)
        }
        autoReloadWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + autoReloadDelay, execute: workItem)
    }

    private func uniqueDuplicateURL(for item: FolderItem) -> URL {
        let parentURL = item.url.deletingLastPathComponent()
        let pathExtension = item.isDirectory ? "" : item.url.pathExtension
        let extensionSuffix = pathExtension.isEmpty ? "" : ".\(pathExtension)"
        let baseName = pathExtension.isEmpty
            ? item.name
            : item.url.deletingPathExtension().lastPathComponent

        var copyNumber = 1
        while true {
            let name: String
            if copyNumber == 1 {
                name = L10n.format("%@ 복사본%@", baseName, extensionSuffix)
            } else {
                name = L10n.format("%@ 복사본 %d%@", baseName, copyNumber, extensionSuffix)
            }
            let candidateURL = parentURL
                .appendingPathComponent(name, isDirectory: item.isDirectory)
                .standardizedFileURL
            if !itemFileManager.itemExists(at: candidateURL) {
                return candidateURL
            }
            copyNumber += 1
        }
    }
}

private extension URL {
    func isContained(in directoryURL: URL) -> Bool {
        let directoryComponents = directoryURL.standardizedFileURL.pathComponents
        let candidateComponents = standardizedFileURL.pathComponents
        guard candidateComponents.count >= directoryComponents.count else { return false }
        return Array(candidateComponents.prefix(directoryComponents.count)) == directoryComponents
    }
}
