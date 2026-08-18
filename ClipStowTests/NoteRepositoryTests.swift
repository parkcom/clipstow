import XCTest
@testable import ClipStow

final class NoteRepositoryTests: XCTestCase {
    func testJSONRoundTripPreservesIDsDatesAndRelationships() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("ClipStowRepositoryTests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let repository = try JSONNoteRepository(baseDirectory: root)
        let category = NoteCategory(
            id: UUID(),
            name: "개발",
            createdAt: Date(timeIntervalSince1970: 100)
        )
        let note = Note(
            id: UUID(),
            title: "Markdown",
            body: "# Heading",
            categoryID: category.id,
            createdAt: Date(timeIntervalSince1970: 200),
            updatedAt: Date(timeIntervalSince1970: 300)
        )
        let snapshot = StoreSnapshot(
            notes: [note],
            categories: [category],
            lastSelectedNoteID: note.id
        )

        try repository.save(snapshot)
        let loaded = try repository.load()

        XCTAssertEqual(loaded, snapshot)
    }

    func testMissingStoreStartsEmpty() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("ClipStowRepositoryTests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let repository = try JSONNoteRepository(baseDirectory: root)
        XCTAssertEqual(try repository.load(), StoreSnapshot())
    }

    func testCorruptStoreIsReportedAndNotOverwrittenByLoad() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("ClipStowRepositoryTests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let repository = try JSONNoteRepository(baseDirectory: root)
        let corruptData = Data("not-json".utf8)
        try corruptData.write(to: repository.storeURL)

        XCTAssertThrowsError(try repository.load())
        XCTAssertEqual(try Data(contentsOf: repository.storeURL), corruptData)
    }
}
