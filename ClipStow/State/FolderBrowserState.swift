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
    @Published private(set) var accessError: String?
    @Published private(set) var sortColumn: FolderSortColumn = .name
    @Published private(set) var sortDirection: FolderSortDirection = .ascending

    private let userDefaults: UserDefaults
    private let contentsLoader: FolderContentsLoading
    private let accessManager: SecurityScopedFolderAccessManaging
    private var scopedRootURL: URL?

    init(
        userDefaults: UserDefaults = .standard,
        contentsLoader: FolderContentsLoading = FileManagerFolderContentsLoader(),
        accessManager: SecurityScopedFolderAccessManaging = SecurityScopedFolderAccessManager()
    ) {
        self.userDefaults = userDefaults
        self.contentsLoader = contentsLoader
        self.accessManager = accessManager
        restoreFolder()
    }

    deinit {
        if let scopedRootURL {
            accessManager.stopAccessing(scopedRootURL)
        }
    }

    var selectedItem: FolderItem? {
        guard let selectedItemID else { return nil }
        return items.first { $0.id == selectedItemID }
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
        if let scopedRootURL {
            accessManager.stopAccessing(scopedRootURL)
        }
        scopedRootURL = nil
        rootURL = nil
        currentURL = nil
        items = []
        selectedItemID = nil
        accessError = nil
        userDefaults.removeObject(forKey: Self.bookmarkDefaultsKey)
    }

    func select(_ item: FolderItem) {
        selectedItemID = item.id
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
        guard let currentURL else { return }
        do {
            let nextItems = try contentsLoader.contents(of: currentURL)
            items = sortedItems(nextItems)
            if let selectedItemID,
               !nextItems.contains(where: { $0.id == selectedItemID }) {
                self.selectedItemID = nil
            }
            accessError = nil
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
        if let scopedRootURL {
            accessManager.stopAccessing(scopedRootURL)
        }
        scopedRootURL = url
        rootURL = url
        currentURL = url
        self.items = sortedItems(items)
        selectedItemID = nil
        accessError = nil
        userDefaults.set(bookmark, forKey: Self.bookmarkDefaultsKey)
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
}

private extension URL {
    func isContained(in directoryURL: URL) -> Bool {
        let directoryComponents = directoryURL.standardizedFileURL.pathComponents
        let candidateComponents = standardizedFileURL.pathComponents
        guard candidateComponents.count >= directoryComponents.count else { return false }
        return Array(candidateComponents.prefix(directoryComponents.count)) == directoryComponents
    }
}
