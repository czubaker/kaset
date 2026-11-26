import SwiftUI

/// Shared bottom area for both sidebars: source toggle above the profile section.
///
/// Used by `Sidebar` (YouTube Music) and `YouTubeSidebar` so the toggle and
/// account control render identically in both experiences.
struct SidebarFooterView: View {
    private let settings = SettingsManager.shared

    var body: some View {
        VStack(spacing: 0) {
            Divider()
                .opacity(0.3)

            SidebarProfileView()

            // Only when the app shows both experiences.
            if self.settings.appMode == .both {
                SourceToggleView()
                    .padding(.horizontal, 12)
                    .padding(.bottom, 8)
            }
        }
    }
}

#Preview {
    SidebarFooterView()
        .frame(width: 220)
}
