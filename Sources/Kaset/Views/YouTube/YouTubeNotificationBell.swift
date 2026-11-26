import SwiftUI

// MARK: - YouTubeNotificationBell

/// The bell beside Subscribe: a menu of YouTube's own options (All,
/// Personalized, None, in the account's language) with the current one
/// checked. Ported from KasetPlus (github.com/Yoddikko/kasetPlus, MIT).
struct YouTubeNotificationBell: View {
    let preference: ChannelNotificationPreference
    let select: (ChannelNotificationPreference.Option) -> Void

    var body: some View {
        Menu {
            Picker(String(localized: "Notifications"), selection: self.selection) {
                ForEach(self.preference.options) { option in
                    Label(option.label, systemImage: option.level.symbolName)
                        .tag(option.id)
                }
            }
            .pickerStyle(.inline)
        } label: {
            Image(systemName: self.preference.currentLevel.symbolName)
                .font(.system(size: 14, weight: .regular))
                .foregroundStyle(.primary)
                .frame(width: 36, height: 36)
                .compatGlass(interactive: true, in: Circle())
                .contentShape(Circle())
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
        .fixedSize()
        .help(String(localized: "Notifications"))
        .accessibilityLabel(String(localized: "Notifications"))
        .accessibilityValue(self.preference.current?.label ?? "")
    }

    private var selection: Binding<String> {
        Binding(
            get: { self.preference.current?.id ?? "" },
            set: { id in
                if let option = self.preference.options.first(where: { $0.id == id }) {
                    self.select(option)
                }
            }
        )
    }
}
