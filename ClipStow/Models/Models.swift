import Foundation

struct Note: Codable, Identifiable, Equatable {
    let id: UUID
    var title: String
    var body: String
    var categoryID: UUID?
    let createdAt: Date
    var updatedAt: Date

    init(
        id: UUID = UUID(),
        title: String = "",
        body: String = "",
        categoryID: UUID? = nil,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.title = title
        self.body = body
        self.categoryID = categoryID
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    var displayTitle: String {
        title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? L10n.string("제목 없음")
            : title
    }
}

struct NoteCategory: Codable, Identifiable, Equatable {
    let id: UUID
    var name: String
    let createdAt: Date

    init(id: UUID = UUID(), name: String, createdAt: Date = Date()) {
        self.id = id
        self.name = name
        self.createdAt = createdAt
    }
}

struct ScratchItem: Identifiable, Equatable {
    static let previewCharacterLimit = 1_200
    static let previewLineLimit = 8

    let id: UUID
    let text: String
    let capturedAt: Date
    let previewText: String
    let isPreviewTruncated: Bool

    init(id: UUID = UUID(), text: String, capturedAt: Date = Date()) {
        self.id = id
        self.text = text
        self.capturedAt = capturedAt
        let preview = Self.makePreview(for: text)
        previewText = preview.text
        isPreviewTruncated = preview.isTruncated
    }

    private static func makePreview(for text: String) -> (text: String, isTruncated: Bool) {
        var index = text.startIndex
        var characterCount = 0
        var lineBreakCount = 0

        while index < text.endIndex && characterCount < previewCharacterLimit {
            let character = text[index]
            if character.isNewline {
                lineBreakCount += 1
                if lineBreakCount >= previewLineLimit {
                    break
                }
            }
            index = text.index(after: index)
            characterCount += 1
        }

        guard index < text.endIndex else { return (text, false) }
        return (String(text[..<index]) + "…", true)
    }
}

extension String {
    var containsNonWhitespaceAndNewline: Bool {
        unicodeScalars.contains { !CharacterSet.whitespacesAndNewlines.contains($0) }
    }
}

struct StoreSnapshot: Codable, Equatable {
    static let currentVersion = 1

    var version: Int
    var notes: [Note]
    var categories: [NoteCategory]
    var lastSelectedNoteID: UUID?

    init(
        version: Int = StoreSnapshot.currentVersion,
        notes: [Note] = [],
        categories: [NoteCategory] = [],
        lastSelectedNoteID: UUID? = nil
    ) {
        self.version = version
        self.notes = notes
        self.categories = categories
        self.lastSelectedNoteID = lastSelectedNoteID
    }
}

enum NoteFilter: Hashable {
    case all
    case uncategorized
    case category(UUID)
}

enum EditorFocusTarget: Hashable {
    case title
    case body
}

struct FocusRequest: Equatable {
    let id = UUID()
    let target: EditorFocusTarget
}

enum MainSection: CaseIterable, Identifiable {
    case notes
    case scratchpad
    case folder

    var id: Self { self }
}
