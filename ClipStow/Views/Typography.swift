import SwiftUI

private struct StashUIFontSizeKey: EnvironmentKey {
    static let defaultValue: Double = AppStore.defaultUIFontSize
}

extension EnvironmentValues {
    var stashUIFontSize: Double {
        get { self[StashUIFontSizeKey.self] }
        set { self[StashUIFontSizeKey.self] = newValue }
    }
}

private struct StashFontModifier: ViewModifier {
    @Environment(\.stashUIFontSize) private var uiFontSize

    let baseSize: CGFloat
    let weight: Font.Weight
    let design: Font.Design

    func body(content: Content) -> some View {
        let scale = uiFontSize / AppStore.defaultUIFontSize
        content.font(.system(size: baseSize * scale, weight: weight, design: design))
    }
}

extension View {
    func stashFont(
        _ baseSize: CGFloat,
        weight: Font.Weight = .regular,
        design: Font.Design = .default
    ) -> some View {
        modifier(StashFontModifier(baseSize: baseSize, weight: weight, design: design))
    }
}
