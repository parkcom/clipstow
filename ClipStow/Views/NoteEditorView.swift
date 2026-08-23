import MarkdownUI
import SwiftUI

private extension NoteEditorMode {
    var title: LocalizedStringKey {
        switch self {
        case .edit: "편집"
        case .preview: "미리보기"
        }
    }
}

final class MarkdownPreviewCache: ObservableObject {
    @Published private(set) var content = MarkdownContent("")
    private(set) var source: String?
    private(set) var parseCount = 0

    func prepare(markdown: String) {
        guard source != markdown else { return }
        source = markdown
        content = MarkdownContent(Self.preservingLineBreaks(in: markdown))
        parseCount += 1
    }

    static func preservingLineBreaks(in markdown: String) -> String {
        let normalized = markdown
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
        var lines = normalized.components(separatedBy: "\n")
        var fencedCodeMarker: Character?

        for index in lines.indices.dropLast() {
            let line = lines[index]
            let trimmedLine = line.trimmingCharacters(in: .whitespaces)

            if let marker = Self.fencedCodeMarker(in: trimmedLine) {
                if fencedCodeMarker == marker {
                    fencedCodeMarker = nil
                } else if fencedCodeMarker == nil {
                    fencedCodeMarker = marker
                }
                continue
            }

            guard fencedCodeMarker == nil,
                  !trimmedLine.isEmpty,
                  !line.hasSuffix("  "),
                  !line.hasSuffix("\\") else {
                continue
            }
            lines[index] += "  "
        }

        return lines.joined(separator: "\n")
    }

    private static func fencedCodeMarker(in line: String) -> Character? {
        guard let marker = line.first, marker == "`" || marker == "~" else {
            return nil
        }
        return line.prefix { $0 == marker }.count >= 3 ? marker : nil
    }
}

struct NoteEditorView: View {
    @ObservedObject var store: AppStore
    @ObservedObject private var editorDraft: EditorDraft
    @StateObject private var previewCache = MarkdownPreviewCache()
    @State private var noteToDelete: Note?
    @FocusState private var focusedField: EditorFocusTarget?

    init(store: AppStore) {
        self.store = store
        _editorDraft = ObservedObject(wrappedValue: store.editorDraft)
    }

    var body: some View {
        Group {
            if let note = store.selectedNote {
                VStack(spacing: 0) {
                    editorHeader(note: note)
                    Divider()
                    editorBody
                }
            } else {
                VStack(spacing: 12) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .fill(Color(nsColor: .controlBackgroundColor))
                        Image(systemName: "rectangle.and.pencil.and.ellipsis")
                            .stashFont(24, weight: .light)
                            .foregroundStyle(.secondary)
                    }
                    .frame(width: 54, height: 54)
                    Text("편집할 노트를 선택하세요")
                        .stashFont(13, weight: .medium)
                    Text("가운데 목록에서 노트를 선택하거나 새로 만드세요")
                        .stashFont(11)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .onChange(of: store.focusRequest?.id) { _ in
            guard let target = store.focusRequest?.target else { return }
            DispatchQueue.main.async {
                focusedField = target
            }
        }
        .onChange(of: store.selectedNoteID) { _ in
            guard store.editorMode == .preview else { return }
            previewCache.prepare(markdown: editorDraft.body)
        }
        .onAppear {
            guard store.editorMode == .preview else { return }
            previewCache.prepare(markdown: editorDraft.body)
        }
        .confirmationDialog(
            "노트 삭제",
            isPresented: Binding(
                get: { noteToDelete != nil },
                set: { if !$0 { noteToDelete = nil } }
            ),
            presenting: noteToDelete
        ) { note in
            Button("노트 삭제", role: .destructive) {
                _ = store.deleteNote(note.id)
                noteToDelete = nil
            }
            Button("취소", role: .cancel) {
                noteToDelete = nil
            }
        } message: { note in
            Text(
                L10n.format(
                    "‘%@’ 노트를 영구 삭제합니다. 이 작업은 되돌릴 수 없습니다.",
                    note.displayTitle
                )
            )
        }
    }

    private func editorHeader(note: Note) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "folder")
                .stashFont(11, weight: .medium)
                .foregroundStyle(.secondary)

            Picker(
                "카테고리",
                selection: Binding<UUID?>(
                    get: { store.selectedNote?.categoryID },
                    set: store.updateSelectedNoteCategory
                )
            ) {
                Text("미분류").tag(UUID?.none)
                ForEach(store.categories) { category in
                    Text(category.name).tag(Optional(category.id))
                }
            }
            .labelsHidden()
            .frame(width: 132)
            .disabled(store.isPersistenceReadOnly)
            .controlSize(.small)

            Spacer()

            Picker("Mode", selection: modeBinding) {
                ForEach(NoteEditorMode.allCases) { item in
                    Text(item.title).tag(item)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .frame(width: 154)
            .controlSize(.small)
            .id(store.appLanguage)

            Button(role: .destructive) {
                noteToDelete = note
            } label: {
                Label("삭제", systemImage: "trash")
                    .stashFont(10, weight: .medium)
                    .padding(.horizontal, 8)
                    .frame(height: 24)
                    .background(Color.red.opacity(0.10))
                    .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
            }
            .buttonStyle(.plain)
            .foregroundStyle(.red)
            .help("현재 노트 삭제")
            .disabled(store.isPersistenceReadOnly)
        }
        .padding(.horizontal, 14)
        .frame(height: 44)
    }

    @ViewBuilder
    private var editorBody: some View {
        switch store.editorMode {
        case .edit:
            TextEditor(
                text: Binding(
                    get: { editorDraft.body },
                    set: store.updateSelectedNoteBody
                )
            )
            .font(.system(size: store.noteFontSize, design: .monospaced))
            .focused($focusedField, equals: .body)
            .scrollContentBackground(.hidden)
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(Color(nsColor: .textBackgroundColor).opacity(0.35))
            .disabled(store.isPersistenceReadOnly)

        case .preview:
            ScrollView {
                Markdown(previewCache.content)
                    .markdownTheme(.gitHub)
                    .markdownTextStyle {
                        FontSize(store.noteFontSize)
                    }
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(20)
            }
            .background(Color(nsColor: .textBackgroundColor).opacity(0.35))
        }
    }

    private var modeBinding: Binding<NoteEditorMode> {
        Binding(
            get: { store.editorMode },
            set: { newMode in
                if newMode == .preview {
                    previewCache.prepare(markdown: editorDraft.body)
                }
                store.setEditorMode(newMode)
            }
        )
    }
}
