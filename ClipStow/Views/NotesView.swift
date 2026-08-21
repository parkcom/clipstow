import SwiftUI

struct NotesView: View {
    @ObservedObject var store: AppStore
    @State private var isManagingCategories = false
    @State private var editingTitleNoteID: UUID?
    @State private var editingTitle = ""

    var body: some View {
        let filteredNotes = store.filteredNotes
        let noteCounts = store.noteCounts

        HSplitView {
            if store.isCategorySidebarVisible {
                categorySidebar(noteCounts: noteCounts)
                    .frame(minWidth: 160, idealWidth: 176, maxWidth: 210)
            }

            noteListPane(filteredNotes: filteredNotes)
                .frame(minWidth: 220, idealWidth: 248, maxWidth: 290)

            NoteEditorView(store: store)
                .frame(minWidth: 440, maxWidth: .infinity, maxHeight: .infinity)
        }
        .sheet(isPresented: $isManagingCategories) {
            CategoryManagerSheet(store: store)
        }
    }

    private func categorySidebar(noteCounts: NoteCountSummary) -> some View {
        VStack(spacing: 0) {
            HStack {
                Text("카테고리")
                    .stashFont(11, weight: .semibold)
                    .foregroundStyle(.secondary)
                    .textCase(.uppercase)
                    .tracking(0.5)

                Spacer()

                Button {
                    isManagingCategories = true
                } label: {
                    Image(systemName: "slider.horizontal.3")
                        .stashFont(12, weight: .medium)
                }
                .buttonStyle(.borderless)
                .help("카테고리 추가, 이름 변경 및 삭제")
                .disabled(store.isPersistenceReadOnly)

                Button {
                    store.setCategorySidebarVisible(false)
                } label: {
                    Image(systemName: "sidebar.left")
                        .stashFont(12, weight: .medium)
                }
                .buttonStyle(.borderless)
                .help("카테고리 접기")
            }
            .padding(.horizontal, 14)
            .frame(height: 48)

            ScrollView {
                LazyVStack(spacing: 3) {
                    CategorySidebarRow(
                        title: L10n.string("모든 노트"),
                        systemImage: "tray.full",
                        count: store.notes.count,
                        selected: store.noteFilter == .all
                    ) {
                        store.setFilter(.all)
                    }

                    CategorySidebarRow(
                        title: L10n.string("미분류"),
                        systemImage: "tray",
                        count: noteCounts.uncategorized,
                        selected: store.noteFilter == .uncategorized
                    ) {
                        store.setFilter(.uncategorized)
                    }

                    if !store.categories.isEmpty {
                        Text("내 카테고리")
                            .stashFont(10, weight: .semibold)
                            .foregroundStyle(.tertiary)
                            .textCase(.uppercase)
                            .tracking(0.5)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.top, 14)
                            .padding(.horizontal, 10)
                            .padding(.bottom, 3)
                    }

                    ForEach(store.categories) { category in
                        CategorySidebarRow(
                            title: category.name,
                            systemImage: "folder",
                            count: noteCounts.byCategory[category.id, default: 0],
                            selected: store.noteFilter == .category(category.id)
                        ) {
                            store.setFilter(.category(category.id))
                        }
                    }
                }
                .padding(8)
            }
        }
        .background(Color(nsColor: .controlBackgroundColor).opacity(0.48))
    }

    private func noteListPane(filteredNotes: [Note]) -> some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                if store.isCategorySidebarVisible {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(activeCategoryTitle)
                            .stashFont(15, weight: .semibold)
                            .lineLimit(1)
                        Text(L10n.format("노트 %d개", filteredNotes.count))
                            .stashFont(10)
                            .foregroundStyle(.secondary)
                    }
                } else {
                    Button {
                        store.setCategorySidebarVisible(true)
                    } label: {
                        Image(systemName: "sidebar.left")
                            .stashFont(13, weight: .medium)
                            .frame(width: 25, height: 24)
                    }
                    .buttonStyle(.borderless)
                    .help("카테고리 펼치기")

                    Picker("카테고리", selection: filterBinding) {
                        Text("모든 노트").tag(NoteFilter.all)
                        Text("미분류").tag(NoteFilter.uncategorized)
                        if !store.categories.isEmpty {
                            Divider()
                        }
                        ForEach(store.categories) { category in
                            Text(category.name).tag(NoteFilter.category(category.id))
                        }
                    }
                    .pickerStyle(.menu)
                    .labelsHidden()
                    .frame(maxWidth: 150)
                    .help("카테고리 선택")

                    Text(String(filteredNotes.count))
                        .stashFont(10, weight: .medium, design: .rounded)
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Button {
                    createNoteAndBeginTitleEditing()
                } label: {
                    Image(systemName: "square.and.pencil")
                        .stashFont(14, weight: .medium)
                        .frame(width: 28, height: 24)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                .help("새 노트")
                .disabled(store.isPersistenceReadOnly)
            }
            .padding(.horizontal, 12)
            .frame(height: 58)

            Divider()

            noteList(filteredNotes)
        }
    }

    private func noteList(_ filteredNotes: [Note]) -> some View {
        ScrollView {
            LazyVStack(spacing: 5) {
                ForEach(filteredNotes) { note in
                    NoteListRow(
                        note: note,
                        selected: store.selectedNoteID == note.id,
                        isEditingTitle: editingTitleNoteID == note.id,
                        editingTitle: $editingTitle,
                        onSelect: { store.selectNote(note.id) },
                        onBeginTitleEditing: { beginTitleEditing(note) },
                        onCommitTitleEditing: { commitTitleEditing(note.id) },
                        onCancelTitleEditing: cancelTitleEditing
                    )
                }
            }
            .padding(7)
        }
        .overlay {
            if filteredNotes.isEmpty {
                VStack(spacing: 10) {
                    Image(systemName: "doc.text")
                        .stashFont(24, weight: .light)
                        .foregroundStyle(.tertiary)
                    Text("노트가 없습니다")
                        .stashFont(12, weight: .medium)
                    Text("새 노트를 만들어 기록을 시작하세요")
                        .stashFont(10)
                        .foregroundStyle(.secondary)
                    Button("새 노트") {
                        createNoteAndBeginTitleEditing()
                    }
                    .controlSize(.small)
                    .disabled(store.isPersistenceReadOnly)
                }
                .multilineTextAlignment(.center)
            }
        }
    }

    private var activeCategoryTitle: String {
        switch store.noteFilter {
        case .all:
            return L10n.string("모든 노트")
        case .uncategorized:
            return L10n.string("미분류")
        case .category(let id):
            return store.categories.first(where: { $0.id == id })?.name
                ?? L10n.string("카테고리")
        }
    }

    private var filterBinding: Binding<NoteFilter> {
        Binding(
            get: { store.noteFilter },
            set: store.setFilter
        )
    }

    private func createNoteAndBeginTitleEditing() {
        guard let noteID = store.createNote() else { return }
        editingTitleNoteID = noteID
        editingTitle = ""
    }

    private func beginTitleEditing(_ note: Note) {
        if let editingTitleNoteID, editingTitleNoteID != note.id {
            commitTitleEditing(editingTitleNoteID)
        }
        store.selectNote(note.id)
        editingTitle = note.title
        self.editingTitleNoteID = note.id
    }

    private func commitTitleEditing(_ noteID: UUID) {
        guard editingTitleNoteID == noteID else { return }
        store.updateNoteTitle(noteID, title: editingTitle)
        editingTitleNoteID = nil
        editingTitle = ""
    }

    private func cancelTitleEditing() {
        editingTitleNoteID = nil
        editingTitle = ""
    }
}

private struct CategorySidebarRow: View {
    let title: String
    let systemImage: String
    let count: Int
    let selected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: systemImage)
                    .stashFont(12, weight: .medium)
                    .foregroundStyle(selected ? Color.accentColor : Color.secondary)
                    .frame(width: 16)
                Text(title)
                    .stashFont(12, weight: selected ? .semibold : .regular)
                    .lineLimit(1)
                Spacer(minLength: 4)
                Text("\(count)")
                    .stashFont(10, design: .rounded)
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 9)
            .frame(height: 31)
            .contentShape(Rectangle())
            .background(selected ? Color.accentColor.opacity(0.14) : Color.clear)
            .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
        }
        .buttonStyle(.plain)
    }
}

private struct NoteListRow: View {
    let note: Note
    let selected: Bool
    let isEditingTitle: Bool
    @Binding var editingTitle: String
    let onSelect: () -> Void
    let onBeginTitleEditing: () -> Void
    let onCommitTitleEditing: () -> Void
    let onCancelTitleEditing: () -> Void

    @FocusState private var isTitleFocused: Bool

    private var excerpt: String {
        let value = String(note.body.prefix(280))
            .replacingOccurrences(of: "\n", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? L10n.string("내용 없음") : value
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                if isEditingTitle {
                    TextField("제목 없음", text: $editingTitle)
                        .textFieldStyle(.plain)
                        .stashFont(12, weight: .semibold)
                        .focused($isTitleFocused)
                        .onSubmit(onCommitTitleEditing)
                        .onExitCommand(perform: onCancelTitleEditing)
                } else {
                    Text(note.displayTitle)
                        .stashFont(12, weight: .semibold)
                        .lineLimit(1)
                }
                Spacer(minLength: 4)
                Text(note.updatedAt, style: .relative)
                    .stashFont(9)
                    .foregroundStyle(.tertiary)
            }

            Text(excerpt)
                .stashFont(10)
                .foregroundStyle(.secondary)
                .lineLimit(2)
                .multilineTextAlignment(.leading)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 9)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(selected ? Color.accentColor.opacity(0.14) : Color.clear)
        .overlay {
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .strokeBorder(selected ? Color.accentColor.opacity(0.25) : Color.clear)
        }
        .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
        .contentShape(Rectangle())
        .onTapGesture(count: 2) {
            guard !isEditingTitle else { return }
            onBeginTitleEditing()
        }
        .onTapGesture(count: 1) {
            guard !isEditingTitle else { return }
            onSelect()
        }
        .onAppear {
            if isEditingTitle {
                DispatchQueue.main.async {
                    isTitleFocused = true
                }
            }
        }
        .onChange(of: isEditingTitle) { isEditing in
            guard isEditing else { return }
            DispatchQueue.main.async {
                isTitleFocused = true
            }
        }
        .onChange(of: isTitleFocused) { isFocused in
            if !isFocused && isEditingTitle {
                onCommitTitleEditing()
            }
        }
        .help(
            isEditingTitle
                ? L10n.string("Enter로 저장 · Esc로 취소")
                : L10n.string("더블클릭하여 제목 변경")
        )
    }
}

private struct CategoryManagerSheet: View {
    @ObservedObject var store: AppStore
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var errorMessage: String?
    @State private var categoryToRename: NoteCategory?
    @State private var categoryToDelete: NoteCategory?
    @FocusState private var isNameFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                Image(systemName: "folder")
                    .stashFont(14, weight: .semibold)
                    .foregroundStyle(Color.accentColor)
                Text("카테고리 관리")
                    .stashFont(15, weight: .semibold)
                Spacer()
                Text(L10n.format("%d개", store.categories.count))
                    .stashFont(10, weight: .medium, design: .rounded)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 16)
            .frame(height: 52)

            Divider()

            HStack(spacing: 8) {
                TextField("새 카테고리 이름", text: $name)
                    .focused($isNameFocused)
                    .onSubmit(create)
                Button("추가", action: create)
                    .buttonStyle(.borderedProminent)
                    .disabled(store.isPersistenceReadOnly)
            }
            .padding(12)

            if let errorMessage {
                Label(errorMessage, systemImage: "exclamationmark.circle.fill")
                    .stashFont(10)
                    .foregroundStyle(.red)
                    .padding(.horizontal, 12)
                    .padding(.bottom, 8)
            }

            Divider()

            if store.categories.isEmpty {
                Text("등록된 카테고리가 없습니다")
                    .stashFont(11)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(spacing: 2) {
                        ForEach(store.categories) { category in
                            HStack(spacing: 9) {
                                Image(systemName: "folder")
                                    .stashFont(12, weight: .medium)
                                    .foregroundStyle(Color.accentColor)
                                    .frame(width: 18)

                                Text(category.name)
                                    .stashFont(12, weight: .medium)
                                    .lineLimit(1)

                                Spacer()

                                Text(L10n.format("%d개", store.noteCount(in: category.id)))
                                    .stashFont(10, design: .rounded)
                                    .foregroundStyle(.secondary)

                                Menu {
                                    Button("이름 변경") {
                                        categoryToRename = category
                                    }
                                    Button("카테고리 삭제", role: .destructive) {
                                        categoryToDelete = category
                                    }
                                } label: {
                                    Image(systemName: "ellipsis")
                                        .stashFont(11, weight: .semibold)
                                        .frame(width: 22, height: 22)
                                }
                                .menuStyle(.borderlessButton)
                                .disabled(store.isPersistenceReadOnly)
                            }
                            .padding(.horizontal, 10)
                            .frame(height: 38)
                            .background(Color(nsColor: .controlBackgroundColor))
                            .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                        }
                    }
                    .padding(8)
                }
            }

            Divider()

            HStack {
                Spacer()
                Button("닫기") { dismiss() }
                    .keyboardShortcut(.cancelAction)
            }
            .padding(.horizontal, 16)
            .frame(height: 46)
        }
        .frame(width: 420, height: 380)
        .background(Color(nsColor: .windowBackgroundColor))
        .onAppear { isNameFocused = true }
        .sheet(item: $categoryToRename) { category in
            RenameCategorySheet(store: store, category: category)
        }
        .confirmationDialog(
            "카테고리 삭제",
            isPresented: Binding(
                get: { categoryToDelete != nil },
                set: { if !$0 { categoryToDelete = nil } }
            ),
            presenting: categoryToDelete
        ) { category in
            Button("카테고리와 모든 노트 삭제", role: .destructive) {
                if !store.deleteCategory(category.id) {
                    errorMessage = store.persistenceError
                        ?? L10n.string("카테고리를 삭제하지 못했습니다.")
                }
                categoryToDelete = nil
            }
            Button("취소", role: .cancel) {
                categoryToDelete = nil
            }
        } message: { category in
            Text(
                L10n.format(
                    "‘%@’ 카테고리를 삭제하면 포함된 노트 %d개도 모두 영구 삭제됩니다. 이 작업은 되돌릴 수 없습니다.",
                    category.name,
                    store.noteCount(in: category.id)
                )
            )
        }
    }

    private func create() {
        do {
            _ = try store.createCategory(named: name)
            name = ""
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

private struct RenameCategorySheet: View {
    @ObservedObject var store: AppStore
    let category: NoteCategory

    @Environment(\.dismiss) private var dismiss
    @State private var name: String
    @State private var errorMessage: String?
    @FocusState private var isNameFocused: Bool

    init(store: AppStore, category: NoteCategory) {
        self.store = store
        self.category = category
        _name = State(initialValue: category.name)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("카테고리 이름 변경")
                .stashFont(14, weight: .semibold)
            TextField("카테고리 이름", text: $name)
                .focused($isNameFocused)
                .onSubmit(rename)

            if let errorMessage {
                Text(errorMessage)
                    .stashFont(10)
                    .foregroundStyle(.red)
            }

            HStack {
                Spacer()
                Button("취소") { dismiss() }
                Button("변경", action: rename)
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 340)
        .onAppear { isNameFocused = true }
    }

    private func rename() {
        do {
            try store.renameCategory(category.id, to: name)
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
