import SwiftUI

struct RootView: View {
    @ObservedObject var store: AppStore
    let quitAction: () -> Void
    let resizeAction: (CGSize) -> Void

    @State private var section: MainSection = .notes
    @State private var isShowingSettings = false

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()

            Group {
                switch section {
                case .notes:
                    NotesView(store: store)
                case .scratchpad:
                    ScratchpadView(store: store) {
                        section = .notes
                    }
                }
            }
            .id(store.appLanguage)
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            if let message = store.persistenceError ?? store.shortcutWarning {
                Divider()
                statusBanner(message)
            }
        }
        .frame(
            minWidth: 820,
            idealWidth: 920,
            maxWidth: .infinity,
            minHeight: 480,
            idealHeight: 600,
            maxHeight: .infinity
        )
        .background(Color(nsColor: .windowBackgroundColor))
        .environment(\.stashUIFontSize, store.uiFontSize)
        .environment(\.locale, store.appLanguage.locale)
        .font(.system(size: store.uiFontSize))
        .overlay {
            GeometryReader { geometry in
                PopoverResizeHandle(
                    containerSize: geometry.size,
                    resizeAction: resizeAction
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
            }
        }
        .sheet(isPresented: $isShowingSettings) {
            SettingsView(store: store, quitAction: quitAction)
                .environment(\.stashUIFontSize, store.uiFontSize)
        }
    }

    private var header: some View {
        ZStack {
            HStack(spacing: 10) {
                ZStack {
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .fill(Color.accentColor.gradient)
                    Image(systemName: "note.text")
                        .stashFont(13, weight: .semibold)
                        .foregroundStyle(.white)
                }
                .frame(width: 28, height: 28)

                VStack(alignment: .leading, spacing: 0) {
                    Text("ClipStow")
                        .stashFont(13, weight: .semibold)
                    Text("빠르게 기록하고 다시 찾기")
                        .stashFont(10)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Button {
                    isShowingSettings = true
                } label: {
                    Image(systemName: "gearshape")
                        .stashFont(14, weight: .medium)
                        .foregroundStyle(.secondary)
                        .frame(width: 28, height: 28)
                }
                .buttonStyle(.plain)
                .help("설정")
            }
            .padding(.horizontal, 16)

            Picker("Section", selection: $section) {
                Label("노트", systemImage: "note.text")
                    .tag(MainSection.notes)
                Label("Scratchpad", systemImage: "doc.on.clipboard")
                    .tag(MainSection.scratchpad)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .frame(width: 246)
            .id(store.appLanguage)
        }
        .frame(height: 54)
    }

    private func statusBanner(_ message: String) -> some View {
        HStack(spacing: 7) {
            Image(systemName: "exclamationmark.triangle.fill")
            Text(message)
                .lineLimit(1)
            Spacer()
        }
        .stashFont(10)
        .foregroundStyle(.orange)
        .padding(.horizontal, 14)
        .frame(height: 28)
        .background(Color.orange.opacity(0.08))
    }
}

private struct PopoverResizeHandle: View {
    let containerSize: CGSize
    let resizeAction: (CGSize) -> Void

    @State private var startingSize: CGSize?
    @State private var isDragging = false

    var body: some View {
        Image(systemName: "arrow.up.left.and.arrow.down.right")
            .stashFont(9, weight: .semibold)
            .foregroundStyle(isDragging ? Color.accentColor : Color.secondary.opacity(0.65))
            .frame(width: 24, height: 24)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
            .contentShape(Rectangle())
            .padding(5)
            .help("드래그하여 창 크기 조절")
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        if startingSize == nil {
                            startingSize = containerSize
                        }
                        isDragging = true
                        guard let startingSize else { return }
                        resizeAction(
                            CGSize(
                                width: startingSize.width + value.translation.width,
                                height: startingSize.height + value.translation.height
                            )
                        )
                    }
                    .onEnded { _ in
                        startingSize = nil
                        isDragging = false
                    }
            )
    }
}
