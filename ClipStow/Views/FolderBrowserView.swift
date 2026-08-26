import AppKit
import QuickLook
import QuickLookUI
import SwiftUI
import UniformTypeIdentifiers

struct FolderBrowserView: View {
    @ObservedObject var state: FolderBrowserState

    @State private var isChoosingFolder = false
    @State private var isConfirmingForget = false
    @State private var isConfirmingTrash = false
    @State private var trashCandidates: [FolderItem] = []
    @State private var isRenamingItem = false
    @State private var renameCandidate: FolderItem?
    @State private var renameText = ""
    @State private var infoItem: FolderItem?
    @State private var quickLookURL: URL?

    var body: some View {
        VStack(spacing: 0) {
            toolbar
            Divider()

            if state.rootURL == nil {
                emptyState
            } else {
                browser
            }

            if let accessError = state.accessError {
                Divider()
                errorBanner(accessError)
            }
        }
        .fileImporter(
            isPresented: $isChoosingFolder,
            allowedContentTypes: [.folder],
            allowsMultipleSelection: false
        ) { result in
            if case .success(let urls) = result, let url = urls.first {
                state.selectFolder(url)
            }
        }
        .quickLookPreview($quickLookURL)
        .confirmationDialog(
            "폴더 연결을 해제할까요?",
            isPresented: $isConfirmingForget,
            titleVisibility: .visible
        ) {
            Button("연결 해제", role: .destructive) {
                quickLookURL = nil
                state.forgetFolder()
            }
            Button("취소", role: .cancel) {}
        } message: {
            Text("ClipStow의 접근 권한만 지우며 폴더와 파일은 삭제하지 않습니다.")
        }
        .alert(
            "휴지통으로 이동할까요?",
            isPresented: $isConfirmingTrash
        ) {
            Button("휴지통으로 이동", role: .destructive) {
                quickLookURL = nil
                state.moveToTrash(trashCandidates)
                trashCandidates = []
            }
            Button("취소", role: .cancel) {
                trashCandidates = []
            }
        } message: {
            Text(trashConfirmationMessage)
        }
        .alert(
            "이름 변경",
            isPresented: $isRenamingItem
        ) {
            TextField("새 이름", text: $renameText)
            Button("이름 변경") {
                if let renameCandidate {
                    state.rename(renameCandidate, to: renameText)
                }
                self.renameCandidate = nil
            }
            Button("취소", role: .cancel) {
                renameCandidate = nil
            }
        } message: {
            Text("파일 또는 폴더의 새 이름을 입력하세요.")
        }
        .sheet(item: $infoItem) { item in
            FolderItemInfoView(item: item)
        }
        .onAppear {
            state.reload()
        }
    }

    private var toolbar: some View {
        HStack(spacing: 10) {
            Button {
                state.goUp()
            } label: {
                Image(systemName: "chevron.left")
                    .frame(width: 24, height: 24)
            }
            .buttonStyle(.plain)
            .disabled(state.isAtRoot)
            .help("상위 폴더")

            VStack(alignment: .leading, spacing: 2) {
                Text("폴더")
                    .stashFont(14, weight: .semibold)
                Text(state.rootURL == nil ? L10n.string("폴더를 선택하세요") : state.currentPathDescription)
                    .stashFont(10)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }

            Spacer()

            if state.rootURL != nil {
                Button {
                    state.reload()
                } label: {
                    Image(systemName: "arrow.clockwise")
                        .frame(width: 26, height: 26)
                }
                .buttonStyle(.plain)
                .help("새로 고침")

                Button {
                    state.selectAll()
                } label: {
                    Image(systemName: "checkmark.circle")
                        .frame(width: 26, height: 26)
                }
                .buttonStyle(.plain)
                .disabled(state.items.isEmpty)
                .keyboardShortcut("a", modifiers: .command)
                .help("모두 선택 (⌘A)")

                Button {
                    isConfirmingForget = true
                } label: {
                    Image(systemName: "xmark.circle")
                        .frame(width: 26, height: 26)
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .help("폴더 연결 해제")
            }

            Button {
                isChoosingFolder = true
            } label: {
                Label(state.rootURL == nil ? "폴더 선택" : "폴더 변경", systemImage: "folder.badge.plus")
            }
            .controlSize(.small)
        }
        .padding(.horizontal, 14)
        .frame(height: 54)
    }

    private var emptyState: some View {
        VStack(spacing: 14) {
            Image(systemName: "folder.badge.plus")
                .stashFont(42, weight: .light)
                .foregroundStyle(Color.accentColor)

            VStack(spacing: 6) {
                Text("폴더를 선택하세요")
                    .stashFont(17, weight: .semibold)
                Text("선택한 폴더의 파일을 탐색하고 미리볼 수 있습니다.")
                    .stashFont(12)
                    .foregroundStyle(.secondary)
            }

            Button("폴더 선택") {
                isChoosingFolder = true
            }
            .keyboardShortcut(.defaultAction)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var browser: some View {
        HSplitView {
            fileList
                .frame(minWidth: 430, idealWidth: 560)

            previewPane
                .frame(minWidth: 270, idealWidth: 330)
        }
    }

    private var fileList: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                FolderSortHeader(
                    title: "이름",
                    column: .name,
                    activeColumn: state.sortColumn,
                    direction: state.sortDirection,
                    alignment: .leading
                ) {
                    state.sort(by: .name)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                FolderSortHeader(
                    title: "수정일",
                    column: .modifiedDate,
                    activeColumn: state.sortColumn,
                    direction: state.sortDirection,
                    alignment: .leading
                ) {
                    state.sort(by: .modifiedDate)
                }
                .frame(width: 122, alignment: .leading)
                FolderSortHeader(
                    title: "크기",
                    column: .size,
                    activeColumn: state.sortColumn,
                    direction: state.sortDirection,
                    alignment: .trailing
                ) {
                    state.sort(by: .size)
                }
                .frame(width: 72, alignment: .trailing)
            }
            .stashFont(10, weight: .medium)
            .foregroundStyle(.secondary)
            .padding(.horizontal, 12)
            .frame(height: 28)
            .background(Color(nsColor: .controlBackgroundColor))

            Divider()

            if state.items.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "folder")
                        .stashFont(26, weight: .light)
                        .foregroundStyle(.secondary)
                    Text("폴더가 비어 있습니다")
                        .stashFont(12)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(spacing: 2) {
                        ForEach(state.items) { item in
                            FolderItemRow(
                                item: item,
                                isSelected: state.isSelected(item),
                                selectedItemCount: state.selectionCount,
                                onSelect: {
                                    if NSEvent.modifierFlags.contains(.command) {
                                        state.toggleSelection(of: item)
                                    } else {
                                        state.select(item)
                                    }
                                },
                                onOpen: {
                                    if item.isDirectory {
                                        state.open(item)
                                    } else {
                                        state.select(item)
                                        quickLookURL = item.url
                                    }
                                },
                                onContextOpen: {
                                    openContextItems(for: item)
                                },
                                onOpenWith: { applicationURL in
                                    state.select(item)
                                    let configuration = NSWorkspace.OpenConfiguration()
                                    configuration.activates = true
                                    NSWorkspace.shared.open(
                                        [item.url],
                                        withApplicationAt: applicationURL,
                                        configuration: configuration,
                                        completionHandler: nil
                                    )
                                },
                                onQuickLook: {
                                    if !state.isSelected(item) {
                                        state.select(item)
                                    }
                                    quickLookURL = item.url
                                },
                                onRevealInFinder: {
                                    let items = contextItems(for: item)
                                    NSWorkspace.shared.activateFileViewerSelecting(items.map(\.url))
                                },
                                onRename: {
                                    state.select(item)
                                    renameCandidate = item
                                    renameText = item.name
                                    isRenamingItem = true
                                },
                                onDuplicate: {
                                    state.duplicate(contextItems(for: item))
                                },
                                onCopy: {
                                    copyToPasteboard(contextItems(for: item))
                                },
                                onGetInfo: {
                                    state.select(item)
                                    infoItem = item
                                },
                                onRequestTrash: {
                                    requestTrash(contextItems(for: item))
                                }
                            )
                        }
                    }
                    .padding(6)
                }
            }
        }
    }

    @ViewBuilder
    private var previewPane: some View {
        if state.selectionCount > 1 {
            VStack(spacing: 9) {
                Image(systemName: "doc.on.doc")
                    .stashFont(34, weight: .light)
                    .foregroundStyle(.secondary)
                Text(L10n.format("%d개 항목 선택됨", state.selectionCount))
                    .stashFont(12, weight: .medium)
                Text("오른쪽 클릭하여 선택한 항목에 작업을 수행할 수 있습니다.")
                    .stashFont(10)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if let item = state.selectedItem {
            VStack(spacing: 0) {
                HStack(spacing: 10) {
                    FolderItemIcon(item: item, size: 30)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(item.name)
                            .stashFont(12, weight: .semibold)
                            .lineLimit(2)
                        Text(item.isDirectory ? L10n.string("폴더") : FileMetadataFormatter.kind(for: item.url))
                            .stashFont(10)
                            .foregroundStyle(.secondary)
                    }

                    Spacer()

                    if !item.isDirectory {
                        Button {
                            quickLookURL = item.url
                        } label: {
                            Label("미리보기 열기", systemImage: "eye")
                        }
                        .controlSize(.small)
                    }
                }
                .padding(12)
                .fileDragSource(item.isDirectory ? nil : item.url)

                Divider()

                if item.isDirectory {
                    VStack(spacing: 10) {
                        Image(systemName: "folder.fill")
                            .stashFont(48, weight: .light)
                            .foregroundStyle(Color.accentColor)
                        Text("폴더를 더블클릭하여 엽니다")
                            .stashFont(11)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if FileMetadataFormatter.isTextFile(item.url) {
                    TextFilePreview(url: item.url)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    QuickLookFilePreview(url: item.url)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }

                if !item.isDirectory {
                    Divider()

                    HStack(spacing: 6) {
                        Image(systemName: "paperclip")
                        Text("파일을 다른 앱으로 드래그해 첨부할 수 있습니다.")
                        Spacer()
                    }
                    .stashFont(10)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 12)
                    .frame(height: 32)
                }
            }
        } else {
            VStack(spacing: 9) {
                Image(systemName: "doc.text.magnifyingglass")
                    .stashFont(34, weight: .light)
                    .foregroundStyle(.secondary)
                Text("미리볼 파일을 선택하세요")
                    .stashFont(12, weight: .medium)
                Text("파일을 더블클릭하면 Quick Look으로 열립니다.")
                    .stashFont(10)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private func errorBanner(_ message: String) -> some View {
        HStack(spacing: 7) {
            Image(systemName: "exclamationmark.triangle.fill")
            Text(message)
                .lineLimit(2)
            Spacer()
        }
        .stashFont(10)
        .foregroundStyle(.orange)
        .padding(.horizontal, 14)
        .frame(minHeight: 32)
        .background(Color.orange.opacity(0.08))
    }

    private var trashConfirmationMessage: String {
        if trashCandidates.count == 1, let item = trashCandidates.first {
            return L10n.format(
                "‘%@’ 항목을 macOS 휴지통으로 이동합니다. Finder에서 복구할 수 있습니다.",
                item.name
            )
        }
        guard !trashCandidates.isEmpty else { return "" }
        return L10n.format(
            "%d개 항목을 macOS 휴지통으로 이동합니다. Finder에서 복구할 수 있습니다.",
            trashCandidates.count
        )
    }

    private func requestTrash(_ items: [FolderItem]) {
        guard !items.isEmpty else { return }
        trashCandidates = items
        isConfirmingTrash = true
    }

    private func contextItems(for item: FolderItem) -> [FolderItem] {
        if state.isSelected(item), !state.selectedItems.isEmpty {
            return state.selectedItems
        }
        state.select(item)
        return [item]
    }

    private func openContextItems(for item: FolderItem) {
        let items = contextItems(for: item)
        if items.count == 1, let item = items.first, item.isDirectory {
            state.open(item)
            return
        }
        for item in items {
            NSWorkspace.shared.open(item.url)
        }
    }

    private func copyToPasteboard(_ items: [FolderItem]) {
        guard !items.isEmpty else { return }
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.writeObjects(items.map { $0.url as NSURL })
    }
}

private struct FolderSortHeader: View {
    let title: LocalizedStringKey
    let column: FolderSortColumn
    let activeColumn: FolderSortColumn
    let direction: FolderSortDirection
    let alignment: Alignment
    let action: () -> Void

    private var isActive: Bool {
        column == activeColumn
    }

    private var accessibilityDirection: String {
        guard isActive else { return "" }
        return L10n.string(direction == .ascending ? "오름차순" : "내림차순")
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Text(title)
                if isActive {
                    Image(systemName: direction == .ascending ? "chevron.up" : "chevron.down")
                        .stashFont(7, weight: .bold)
                }
            }
            .frame(maxWidth: .infinity, alignment: alignment)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(isActive ? .primary : .secondary)
        .accessibilityValue(Text(accessibilityDirection))
        .accessibilityHint("클릭하여 정렬 순서 변경")
        .help("클릭하여 정렬 순서 변경")
    }
}

private struct FolderItemRow: View {
    let item: FolderItem
    let isSelected: Bool
    let selectedItemCount: Int
    let onSelect: () -> Void
    let onOpen: () -> Void
    let onContextOpen: () -> Void
    let onOpenWith: (URL) -> Void
    let onQuickLook: () -> Void
    let onRevealInFinder: () -> Void
    let onRename: () -> Void
    let onDuplicate: () -> Void
    let onCopy: () -> Void
    let onGetInfo: () -> Void
    let onRequestTrash: () -> Void

    private var contextItemCount: Int {
        isSelected ? max(selectedItemCount, 1) : 1
    }

    private var openMenuTitle: String {
        contextItemCount == 1
            ? L10n.string("열기")
            : L10n.format("%d개 항목 열기", contextItemCount)
    }

    private var duplicateMenuTitle: String {
        contextItemCount == 1
            ? L10n.string("복제")
            : L10n.format("%d개 항목 복제", contextItemCount)
    }

    private var copyMenuTitle: String {
        contextItemCount == 1
            ? L10n.string("복사")
            : L10n.format("%d개 항목 복사", contextItemCount)
    }

    private var trashMenuTitle: String {
        guard contextItemCount > 1 else {
            return L10n.string("휴지통으로 이동")
        }
        return L10n.format("%d개 항목을 휴지통으로 이동", contextItemCount)
    }

    private var openWithApplications: [URL] {
        var seenPaths: Set<String> = []
        return NSWorkspace.shared.urlsForApplications(toOpen: item.url)
            .filter { seenPaths.insert($0.standardizedFileURL.path).inserted }
            .sorted {
                FileManager.default.displayName(atPath: $0.path)
                    .localizedStandardCompare(FileManager.default.displayName(atPath: $1.path))
                    == .orderedAscending
            }
    }

    var body: some View {
        HStack(spacing: 10) {
            HStack(spacing: 8) {
                FolderItemIcon(item: item, size: 22)
                Text(item.name)
                    .stashFont(11)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Text(FileMetadataFormatter.modifiedDate(item.modifiedAt))
                .stashFont(10)
                .foregroundStyle(.secondary)
                .frame(width: 122, alignment: .leading)

            Text(FileMetadataFormatter.size(item.byteCount))
                .stashFont(10)
                .foregroundStyle(.secondary)
                .frame(width: 72, alignment: .trailing)
        }
        .padding(.horizontal, 7)
        .frame(height: 34)
        .background(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(isSelected ? Color.accentColor.opacity(0.16) : Color.clear)
        )
        .contentShape(Rectangle())
        .onTapGesture(count: 2, perform: onOpen)
        .onTapGesture(count: 1, perform: onSelect)
        .fileDragSource(item.isDirectory ? nil : item.url, onBegan: onSelect)
        .contextMenu {
            Button(action: onContextOpen) {
                Label(openMenuTitle, systemImage: "arrow.up.forward.app")
            }

            if contextItemCount == 1, !item.isDirectory, !openWithApplications.isEmpty {
                Menu {
                    ForEach(openWithApplications, id: \.path) { applicationURL in
                        Button {
                            onOpenWith(applicationURL)
                        } label: {
                            Label {
                                Text(FileManager.default.displayName(atPath: applicationURL.path))
                            } icon: {
                                Image(nsImage: NSWorkspace.shared.icon(forFile: applicationURL.path))
                            }
                        }
                    }
                } label: {
                    Label("다음으로 열기", systemImage: "square.and.arrow.up")
                }
            }

            Divider()

            Button(action: onQuickLook) {
                Label("빠른 보기", systemImage: "eye")
            }

            Button(action: onRevealInFinder) {
                Label("Finder에서 보기", systemImage: "folder")
            }

            Divider()

            Button(action: onRename) {
                Label("이름 변경", systemImage: "pencil")
            }
            .disabled(contextItemCount != 1)

            Button(action: onDuplicate) {
                Label(duplicateMenuTitle, systemImage: "plus.square.on.square")
            }

            Button(action: onCopy) {
                Label(copyMenuTitle, systemImage: "doc.on.doc")
            }

            Divider()

            Button(action: onGetInfo) {
                Label("정보 가져오기", systemImage: "info.circle")
            }
            .disabled(contextItemCount != 1)

            Divider()

            Button(role: .destructive, action: onRequestTrash) {
                Label {
                    Text(trashMenuTitle)
                } icon: {
                    Image(systemName: "trash")
                }
            }
        }
        .accessibilityLabel(item.name)
        .accessibilityHint(item.isDirectory
            ? L10n.string("더블클릭하여 폴더 열기")
            : L10n.string("드래그하여 다른 앱에 파일 첨부"))
    }
}

private struct FolderItemInfoView: View {
    @Environment(\.dismiss) private var dismiss

    let item: FolderItem

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 12) {
                FolderItemIcon(item: item, size: 48)
                VStack(alignment: .leading, spacing: 3) {
                    Text(item.name)
                        .stashFont(15, weight: .semibold)
                        .lineLimit(2)
                    Text(item.isDirectory ? L10n.string("폴더") : FileMetadataFormatter.kind(for: item.url))
                        .stashFont(11)
                        .foregroundStyle(.secondary)
                }
            }

            Divider()

            Grid(alignment: .leading, horizontalSpacing: 14, verticalSpacing: 9) {
                infoRow("종류", value: item.isDirectory
                    ? L10n.string("폴더")
                    : FileMetadataFormatter.kind(for: item.url))
                infoRow("크기", value: FileMetadataFormatter.size(item.byteCount))
                infoRow("수정일", value: FileMetadataFormatter.modifiedDate(item.modifiedAt))
                infoRow("위치", value: item.url.deletingLastPathComponent().path)
            }

            HStack {
                Spacer()
                Button("닫기") {
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 440)
    }

    @ViewBuilder
    private func infoRow(_ label: LocalizedStringKey, value: String) -> some View {
        GridRow {
            Text(label)
                .stashFont(11, weight: .medium)
                .foregroundStyle(.secondary)
            Text(value)
                .stashFont(11)
                .textSelection(.enabled)
        }
    }
}

private struct FolderItemIcon: View {
    let item: FolderItem
    let size: CGFloat

    var body: some View {
        Image(nsImage: NSWorkspace.shared.icon(forFile: item.url.path))
            .resizable()
            .scaledToFit()
            .frame(width: size, height: size)
    }
}

private struct QuickLookFilePreview: NSViewRepresentable {
    let url: URL

    func makeNSView(context: Context) -> QLPreviewView {
        let previewView = QLPreviewView(frame: .zero, style: .normal)
        previewView?.autostarts = true
        return previewView!
    }

    func updateNSView(_ previewView: QLPreviewView, context: Context) {
        previewView.previewItem = url as NSURL
    }
}

private struct TextFilePreview: View {
    let url: URL

    @State private var content: TextFilePreviewContent?
    @State private var errorMessage: String?

    var body: some View {
        Group {
            if let content {
                VStack(spacing: 0) {
                    ScrollView {
                        Text(content.text)
                            .font(.system(size: 11, design: .monospaced))
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .topLeading)
                            .padding(12)
                    }

                    if content.isTruncated {
                        Divider()
                        Text("큰 파일은 처음 512KB만 미리봅니다.")
                            .stashFont(9)
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 10)
                            .frame(height: 26)
                    }
                }
            } else if let errorMessage {
                VStack(spacing: 8) {
                    Image(systemName: "doc.badge.ellipsis")
                        .stashFont(28, weight: .light)
                        .foregroundStyle(.secondary)
                    Text(errorMessage)
                        .stashFont(10)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ProgressView()
                    .controlSize(.small)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .background(Color(nsColor: .textBackgroundColor))
        .task(id: url) {
            content = nil
            errorMessage = nil
            let result = await Task.detached(priority: .utility) {
                Result { try TextFilePreviewLoader.load(from: url) }
            }.value
            guard !Task.isCancelled else { return }
            switch result {
            case .success(let content):
                self.content = content
            case .failure(let error):
                errorMessage = L10n.format("파일 미리보기를 불러올 수 없습니다. %@", error.localizedDescription)
            }
        }
    }
}

private enum FileMetadataFormatter {
    static func modifiedDate(_ date: Date?) -> String {
        guard let date else { return "—" }
        return DateFormatter.localizedString(
            from: date,
            dateStyle: .short,
            timeStyle: .short
        )
    }

    static func size(_ byteCount: Int64?) -> String {
        guard let byteCount else { return "—" }
        return ByteCountFormatter.string(fromByteCount: byteCount, countStyle: .file)
    }

    static func kind(for url: URL) -> String {
        guard
            let type = UTType(filenameExtension: url.pathExtension),
            let description = type.localizedDescription
        else {
            return L10n.string("파일")
        }
        return description
    }

    static func isTextFile(_ url: URL) -> Bool {
        UTType(filenameExtension: url.pathExtension)?.conforms(to: .text) == true
    }
}

enum FileDragProvider {
    static func make(for url: URL) -> NSItemProvider {
        let provider = NSItemProvider(contentsOf: url)
            ?? NSItemProvider(object: url as NSURL)
        provider.suggestedName = url.lastPathComponent
        return provider
    }
}

private extension View {
    @ViewBuilder
    func fileDragSource(
        _ url: URL?,
        onBegan: @escaping () -> Void = {}
    ) -> some View {
        if let url {
            onDrag {
                onBegan()
                return FileDragProvider.make(for: url)
            }
        } else {
            self
        }
    }
}
