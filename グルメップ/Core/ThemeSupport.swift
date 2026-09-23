import SwiftUI

private struct ThemeScreenBackground: ViewModifier {
    @Environment(ProAccessController.self) private var proAccess
    @Environment(ProPreferences.self) private var proPreferences

    private var canvasColor: Color {
        proAccess.isProUnlocked ? proPreferences.canvasColor : Color("PinterestCanvas")
    }

    func body(content: Content) -> some View {
        content
            .scrollContentBackground(.hidden)
            .background(canvasColor.ignoresSafeArea())
    }
}

extension View {
    /// Applies the currently selected Pro theme to scrollable screen backgrounds.
    func themeScreenBackground() -> some View {
        modifier(ThemeScreenBackground())
    }
}
