import Foundation

protocol NoteRepository {
    var storeURL: URL { get }
    func load() throws -> StoreSnapshot
    func save(_ snapshot: StoreSnapshot) throws
}

enum NoteRepositoryError: LocalizedError, Equatable {
    case unsupportedVersion(Int)
    case unreadableStore(String)

    var errorDescription: String? {
        switch self {
        case .unsupportedVersion(let version):
            return L10n.format("지원하지 않는 저장 형식입니다 (version %d).", version)
        case .unreadableStore(let detail):
            return L10n.format(
                "노트 저장 파일을 읽을 수 없습니다. 원본은 덮어쓰지 않았습니다. %@",
                detail
            )
        }
    }
}

final class JSONNoteRepository: NoteRepository {
    let storeURL: URL

    private let fileManager: FileManager
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    convenience init(fileManager: FileManager = .default) throws {
        guard let applicationSupport = fileManager.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first else {
            throw CocoaError(.fileNoSuchFile)
        }
        try self.init(baseDirectory: applicationSupport, fileManager: fileManager)
    }

    init(baseDirectory: URL, fileManager: FileManager = .default) throws {
        self.fileManager = fileManager
        let directory = baseDirectory.appendingPathComponent("ClipStow", isDirectory: true)
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        storeURL = directory.appendingPathComponent("store.json", isDirectory: false)

        encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]

        decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
    }

    func load() throws -> StoreSnapshot {
        guard fileManager.fileExists(atPath: storeURL.path) else {
            return StoreSnapshot()
        }

        do {
            let data = try Data(contentsOf: storeURL)
            let snapshot = try decoder.decode(StoreSnapshot.self, from: data)
            guard snapshot.version == StoreSnapshot.currentVersion else {
                throw NoteRepositoryError.unsupportedVersion(snapshot.version)
            }
            return snapshot
        } catch let error as NoteRepositoryError {
            throw error
        } catch {
            throw NoteRepositoryError.unreadableStore(error.localizedDescription)
        }
    }

    func save(_ snapshot: StoreSnapshot) throws {
        let data = try encoder.encode(snapshot)
        try data.write(to: storeURL, options: .atomic)
    }
}

final class UnavailableNoteRepository: NoteRepository {
    let storeURL = URL(fileURLWithPath: "/dev/null")
    private let underlyingError: Error

    init(underlyingError: Error) {
        self.underlyingError = underlyingError
    }

    func load() throws -> StoreSnapshot {
        throw underlyingError
    }

    func save(_ snapshot: StoreSnapshot) throws {
        throw underlyingError
    }
}
