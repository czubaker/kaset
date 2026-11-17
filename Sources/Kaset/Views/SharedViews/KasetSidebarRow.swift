import SwiftUI

// MARK: - KasetSidebarRow

/// A stable Apple-Music-style sidebar row.
///
/// SwiftUI's source-list `NavigationLink` chrome changes when the sidebar list
/// becomes the active control: selected rows switch to the system accent fill
/// and symbols become selected-text colored. Kaset drives detail content from
/// explicit selection state, so use a plain button row with our own selected
/// background and brand-accent symbol instead of relying on `NavigationLink`'s
/// active/inactive source-list styling.
struct KasetSidebarRow: View {
    let title: String
    let systemImage: String
    let isSelected: Bool
    /// Extra leading space, for rows nested under another (a playlist under
    /// Playlists).
    var indent: CGFloat = 0
    /// A control pinned to the row's trailing edge, outside its button, such as
    /// a disclosure chevron.
    var accessory: AnyView?
    /// Set on the row's button alone, so an accessory doesn't share it.
    var accessibilityIdentifier: String?
    let action: () -> Void

    var body: some View {
        HStack(spacing: 4) {
            Button(action: self.action) {
                Label {
                    Text(self.title)
                        .lineLimit(1)
                        .fontWeight(self.isSelected ? .semibold : .regular)
                        .foregroundStyle(.primary)
                } icon: {
                    Image(systemName: self.systemImage)
                        .foregroundStyle(PackageResourceLookup.brandAccent)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, 5)
                .padding(.leading, self.indent)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityAddTraits(self.isSelected ? .isSelected : [])
            .modifier(OptionalAccessibilityIdentifier(identifier: self.accessibilityIdentifier))

            if let accessory = self.accessory {
                accessory
            }
        }
        .listRowInsets(EdgeInsets(top: 1, leading: 10, bottom: 1, trailing: 10))
        .listRowBackground(self.selectionBackground)
    }

    @ViewBuilder
    private var selectionBackground: some View {
        if self.isSelected {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color.secondary.opacity(0.22))
                .padding(.horizontal, 8)
                .padding(.vertical, 2)
        }
    }
}

// MARK: - OptionalAccessibilityIdentifier

/// Sets an accessibility identifier only when there is one, so a row without
/// it keeps the identifier its caller sets on the whole row.
private struct OptionalAccessibilityIdentifier: ViewModifier {
    let identifier: String?

    func body(content: Content) -> some View {
        if let identifier {
            content.accessibilityIdentifier(identifier)
        } else {
            content
        }
    }
}

#Preview {
    List {
        KasetSidebarRow(
            title: "Home",
            systemImage: "house",
            isSelected: true,
            action: {}
        )
        KasetSidebarRow(
            title: "Search",
            systemImage: "magnifyingglass",
            isSelected: false,
            action: {}
        )
    }
    .listStyle(.sidebar)
    .frame(width: 220)
}
