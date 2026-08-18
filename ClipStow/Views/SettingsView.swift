import AppKit
import KeyboardShortcuts
import SwiftUI

struct SettingsView: View {
    @ObservedObject var store: AppStore
    let quitAction: () -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()

            ScrollView {
                VStack(spacing: 16) {
                    launchSection
                    languageSection
                    shortcutSection
                    typographySection
                }
                .id(store.appLanguage)
                .padding(20)
            }

            Divider()
            HStack {
                Button(role: .destructive, action: quit) {
                    Label("ClipStow 종료", systemImage: "power")
                }
                .controlSize(.small)
                Spacer()
                Text("변경 사항은 자동으로 저장됩니다")
                    .stashFont(10)
                    .foregroundStyle(.secondary)
                Button("완료") { dismiss() }
                    .keyboardShortcut(.defaultAction)
            }
            .padding(.horizontal, 20)
            .frame(height: 52)
        }
        .frame(width: 520, height: 500)
        .background(Color(nsColor: .windowBackgroundColor))
        .onAppear { store.refreshLoginItemState() }
    }

    private func quit() {
        dismiss()
        DispatchQueue.main.async(execute: quitAction)
    }

    private var languageSection: some View {
        SettingsCard(title: "언어", systemImage: "globe") {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("앱 표시 언어")
                        .stashFont(12, weight: .medium)
                    Text("변경 사항은 즉시 전체 화면에 적용됩니다")
                        .stashFont(10)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Picker(
                    "앱 표시 언어",
                    selection: Binding(
                        get: { store.appLanguage },
                        set: store.setAppLanguage
                    )
                ) {
                    Text("시스템 기본값").tag(AppLanguage.system)
                    Divider()
                    Text("English").tag(AppLanguage.english)
                    Text("한국어").tag(AppLanguage.korean)
                    Text("日本語").tag(AppLanguage.japanese)
                }
                .labelsHidden()
                .frame(width: 150)
            }
        }
    }

    private var shortcutSection: some View {
        SettingsCard(title: "호출 단축키", systemImage: "keyboard") {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("ClipStow 열기/닫기")
                        .stashFont(12, weight: .medium)
                    Text("입력 칸을 클릭한 뒤 원하는 키 조합을 누르세요")
                        .stashFont(10)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                KeyboardShortcuts.Recorder(for: .toggleClipStow) { _ in
                    store.shortcutSettingDidChange()
                }
                .fixedSize()
            }

            if let warning = store.shortcutWarning {
                Label(warning, systemImage: "exclamationmark.triangle.fill")
                    .stashFont(10)
                    .foregroundStyle(.orange)
            } else {
                Label(
                    "메뉴막대 아이콘은 단축키와 관계없이 항상 사용할 수 있습니다.",
                    systemImage: "menubar.rectangle"
                )
                .stashFont(10)
                .foregroundStyle(.secondary)
            }
        }
    }

    private var header: some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(Color.accentColor.opacity(0.14))
                Image(systemName: "gearshape.fill")
                    .stashFont(16, weight: .semibold)
                    .foregroundStyle(Color.accentColor)
            }
            .frame(width: 36, height: 36)

            VStack(alignment: .leading, spacing: 2) {
                Text("설정")
                    .stashFont(16, weight: .semibold)
                Text("앱 실행 방식, 언어, 단축키와 글자 크기를 조절합니다")
                    .stashFont(11)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(.horizontal, 20)
        .frame(height: 68)
    }

    private var launchSection: some View {
        SettingsCard(title: "일반", systemImage: "macwindow") {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("로그인 시 실행")
                        .stashFont(12, weight: .medium)
                    Text("Mac에 로그인하면 ClipStow를 자동으로 시작합니다")
                        .stashFont(10)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Toggle(
                    "로그인 시 실행",
                    isOn: Binding(
                        get: { store.launchAtLoginEnabled },
                        set: store.setLaunchAtLoginEnabled
                    )
                )
                .labelsHidden()
                .toggleStyle(.switch)
                .disabled(store.isUpdatingLoginItem)
            }

            Divider()

            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("팝오버 고정")
                        .stashFont(12, weight: .medium)
                    Text("다른 앱을 클릭해도 ClipStow를 열어 둡니다")
                        .stashFont(10)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Toggle(
                    "팝오버 고정",
                    isOn: Binding(
                        get: { store.keepsPopoverOpen },
                        set: store.setKeepsPopoverOpen
                    )
                )
                .labelsHidden()
                .toggleStyle(.switch)
            }

            if store.loginItemNeedsApproval {
                Label(
                    "시스템 설정 › 일반 › 로그인 항목에서 ClipStow를 허용해 주세요.",
                    systemImage: "exclamationmark.triangle.fill"
                )
                .stashFont(10)
                .foregroundStyle(.orange)
            }

            if let message = store.settingsError {
                Label(message, systemImage: "xmark.circle.fill")
                    .stashFont(10)
                    .foregroundStyle(.red)
            }
        }
    }

    private var typographySection: some View {
        SettingsCard(title: "글자 크기", systemImage: "textformat.size") {
            FontSizeSettingRow(
                title: "전체 UI",
                detail: "탐색, 버튼, 메뉴와 보조 정보",
                value: Binding(
                    get: { store.uiFontSize },
                    set: store.setUIFontSize
                ),
                range: AppStore.uiFontSizeRange
            )

            Divider()

            FontSizeSettingRow(
                title: "노트",
                detail: "노트 편집기와 Markdown 미리보기",
                value: Binding(
                    get: { store.noteFontSize },
                    set: store.setNoteFontSize
                ),
                range: AppStore.contentFontSizeRange
            )

            Divider()

            FontSizeSettingRow(
                title: "Scratchpad",
                detail: "수집된 텍스트 본문",
                value: Binding(
                    get: { store.scratchpadFontSize },
                    set: store.setScratchpadFontSize
                ),
                range: AppStore.contentFontSizeRange
            )

            HStack {
                Text("Aa")
                    .font(.system(size: store.noteFontSize))
                Text("설정한 크기를 바로 미리볼 수 있습니다")
                    .stashFont(10)
                    .foregroundStyle(.secondary)
                Spacer()
                Button("기본값으로 복원") {
                    store.resetFontSizes()
                }
                .controlSize(.small)
            }
            .padding(10)
            .background(Color(nsColor: .windowBackgroundColor))
            .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
        }
    }
}

private struct SettingsCard<Content: View>: View {
    let title: LocalizedStringKey
    let systemImage: String
    let content: Content

    init(
        title: LocalizedStringKey,
        systemImage: String,
        @ViewBuilder content: () -> Content
    ) {
        self.title = title
        self.systemImage = systemImage
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Label(title, systemImage: systemImage)
                .stashFont(11, weight: .semibold)
                .foregroundStyle(.secondary)

            content
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(nsColor: .controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.06))
        }
    }
}

private struct FontSizeSettingRow: View {
    let title: LocalizedStringKey
    let detail: LocalizedStringKey
    @Binding var value: Double
    let range: ClosedRange<Double>

    var body: some View {
        HStack(spacing: 14) {
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .stashFont(12, weight: .medium)
                Text(detail)
                    .stashFont(10)
                    .foregroundStyle(.secondary)
            }
            .frame(width: 180, alignment: .leading)

            Slider(value: $value, in: range, step: 1)

            Text(String(Int(value)) + " pt")
                .stashFont(11, weight: .semibold, design: .rounded)
                .monospacedDigit()
                .frame(width: 42, alignment: .trailing)
        }
    }
}
