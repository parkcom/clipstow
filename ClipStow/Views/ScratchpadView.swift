import SwiftUI

struct ScratchpadView: View {
    @ObservedObject var store: AppStore
    @ObservedObject private var scratchpadState: ScratchpadState
    let onSaved: () -> Void

    @State private var isConfirmingClear = false
    @State private var isSaving = false
    @State private var itemToCopy: ScratchItem?

    init(store: AppStore, onSaved: @escaping () -> Void) {
        self.store = store
        _scratchpadState = ObservedObject(wrappedValue: store.scratchpadState)
        self.onSaved = onSaved
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .fill(Color.accentColor.opacity(0.12))
                    Image(systemName: "doc.on.clipboard")
                        .stashFont(16, weight: .semibold)
                        .foregroundStyle(Color.accentColor)
                }
                .frame(width: 36, height: 36)

                VStack(alignment: .leading, spacing: 2) {
                    Text("Scratchpad")
                        .stashFont(15, weight: .semibold)
                    Text("복사한 텍스트를 임시로 모읍니다 · 앱 종료 시 삭제")
                        .stashFont(10)
                        .foregroundStyle(.secondary)
                }
                Spacer()

                HStack(spacing: 8) {
                    Circle()
                        .fill(store.isCaptureEnabled ? Color.green : Color.secondary.opacity(0.45))
                        .frame(width: 7, height: 7)
                    Text(
                        store.isCaptureEnabled
                            ? L10n.string("수집 중")
                            : L10n.string("수집 꺼짐")
                    )
                        .stashFont(10, weight: .medium)
                        .foregroundStyle(.secondary)

                    Toggle(
                        "Copy Capture",
                        isOn: Binding(
                            get: { store.isCaptureEnabled },
                            set: store.setCaptureEnabled
                        )
                    )
                    .toggleStyle(.switch)
                    .controlSize(.small)
                }
                .padding(.leading, 10)
                .padding(.trailing, 8)
                .frame(height: 32)
                .background(Color(nsColor: .controlBackgroundColor))
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))

                Text("\(scratchpadState.items.count)")
                    .stashFont(11, weight: .semibold, design: .rounded)
                    .monospacedDigit()
                    .foregroundStyle(scratchpadState.items.isEmpty ? Color.secondary : Color.accentColor)
                    .frame(minWidth: 26, minHeight: 24)
                    .background(Color(nsColor: .controlBackgroundColor))
                    .clipShape(Capsule())
            }
            .padding(.horizontal, 16)
            .frame(height: 62)

            Divider()

            if let message = store.pasteboardAccessMessage {
                HStack(spacing: 6) {
                    Image(systemName: "exclamationmark.triangle.fill")
                    Text(message)
                        .lineLimit(1)
                    Spacer()
                }
                .stashFont(10)
                .foregroundStyle(.orange)
                .padding(.horizontal, 14)
                .frame(height: 30)
                .background(Color.orange.opacity(0.08))
                Divider()
            }

            ScrollView {
                LazyVStack(alignment: .leading, spacing: 10) {
                    if scratchpadState.items.isEmpty {
                        VStack(spacing: 12) {
                            ZStack {
                                RoundedRectangle(cornerRadius: 16, style: .continuous)
                                    .fill(Color(nsColor: .controlBackgroundColor))
                                Image(systemName: "doc.on.clipboard")
                                    .stashFont(28, weight: .light)
                                    .foregroundStyle(.secondary)
                            }
                            .frame(width: 64, height: 64)
                            Text("아직 수집된 텍스트가 없습니다")
                                .stashFont(13, weight: .medium)
                            Text("Copy Capture를 켜고 다른 앱에서 텍스트를 복사하세요")
                                .stashFont(11)
                                .foregroundStyle(.secondary)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.top, 110)
                    } else {
                        ForEach(scratchpadState.items) { item in
                            ScratchItemRow(
                                item: item,
                                fontSize: store.scratchpadFontSize,
                                isReadOnly: store.isPersistenceReadOnly,
                                onCopy: { itemToCopy = item },
                                onDelete: { store.deleteScratchItem(item.id) }
                            )
                            .equatable()
                        }
                    }
                }
                .padding(16)
            }

            Divider()

            HStack {
                Button(role: .destructive) {
                    isConfirmingClear = true
                } label: {
                    Label("모두 지우기", systemImage: "trash")
                }
                .disabled(scratchpadState.items.isEmpty)

                Spacer()

                Button {
                    isSaving = true
                } label: {
                    Label("모두 노트로 저장", systemImage: "note.text.badge.plus")
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
                .disabled(scratchpadState.items.isEmpty || store.isPersistenceReadOnly)
            }
            .padding(.horizontal, 16)
            .frame(height: 52)
        }
        .confirmationDialog(
            "Scratchpad 내용을 모두 삭제할까요?",
            isPresented: $isConfirmingClear
        ) {
            Button("삭제", role: .destructive) {
                store.clearScratchpad()
            }
            Button("취소", role: .cancel) {}
        }
        .sheet(isPresented: $isSaving) {
            SaveScratchpadSheet(store: store, item: nil) {
                isSaving = false
                onSaved()
            }
        }
        .sheet(item: $itemToCopy) { item in
            SaveScratchpadSheet(store: store, item: item) {
                itemToCopy = nil
            }
        }
    }
}

private struct ScratchItemRow: View, Equatable {
    let item: ScratchItem
    let fontSize: Double
    let isReadOnly: Bool
    let onCopy: () -> Void
    let onDelete: () -> Void

    @State private var isExpanded = false

    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.item == rhs.item &&
            lhs.fontSize == rhs.fontSize &&
            lhs.isReadOnly == rhs.isReadOnly
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Label {
                    Text(item.capturedAt, format: .dateTime.hour().minute().second())
                } icon: {
                    Image(systemName: "clock")
                }
                .stashFont(10)
                .monospacedDigit()
                .foregroundStyle(.tertiary)

                Spacer()

                Button(action: onCopy) {
                    Label("노트로 복사", systemImage: "note.text.badge.plus")
                }
                .buttonStyle(.borderless)
                .controlSize(.small)
                .disabled(isReadOnly)

                Button(role: .destructive, action: onDelete) {
                    Image(systemName: "trash")
                }
                .buttonStyle(.borderless)
                .controlSize(.small)
                .help("항목 삭제")
            }

            Text(isExpanded ? item.text : item.previewText)
                .font(.system(size: fontSize))
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)

            if item.isPreviewTruncated {
                Button(isExpanded ? L10n.string("접기") : L10n.string("더 보기")) {
                    isExpanded.toggle()
                }
                .buttonStyle(.borderless)
                .controlSize(.small)
            }
        }
        .padding(13)
        .background(Color(nsColor: .controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.05))
        }
    }
}

private struct SaveScratchpadSheet: View {
    @ObservedObject var store: AppStore
    let item: ScratchItem?
    let onSaved: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var title = ""
    @State private var categoryID: UUID?
    @State private var saveError: String?
    @FocusState private var isTitleFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(
                item == nil
                    ? L10n.string("Scratchpad를 노트로 저장")
                    : L10n.string("항목을 노트로 복사")
            )
                .stashFont(14, weight: .semibold)

            TextField("제목", text: $title)
                .focused($isTitleFocused)

            Picker("카테고리", selection: $categoryID) {
                Text("미분류").tag(UUID?.none)
                ForEach(store.categories) { category in
                    Text(category.name).tag(Optional(category.id))
                }
            }

            if let saveError {
                Text(saveError)
                    .stashFont(10)
                    .foregroundStyle(.red)
            }

            HStack {
                Spacer()
                Button("취소") { dismiss() }
                Button(item == nil ? L10n.string("저장") : L10n.string("복사")) {
                    let didSave: Bool
                    if let item {
                        didSave = store.copyScratchItemToNote(
                            itemID: item.id,
                            title: title,
                            categoryID: categoryID
                        )
                    } else {
                        didSave = store.saveScratchpadAsNote(title: title, categoryID: categoryID)
                    }

                    if didSave {
                        dismiss()
                        onSaved()
                    } else {
                        saveError = store.persistenceError
                            ?? L10n.string("노트를 저장하지 못했습니다.")
                    }
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 380)
        .onAppear {
            title = item.map(store.scratchSuggestedTitle(for:)) ?? store.scratchSuggestedTitle
            isTitleFocused = true
        }
    }
}
