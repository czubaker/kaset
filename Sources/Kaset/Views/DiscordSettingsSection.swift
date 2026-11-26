import SwiftUI

// MARK: - DiscordSettingsSection

/// Settings → Scrobbling → Discord: shows what's playing on the user's Discord
/// profile, with the connection's state so a failure is visible.
struct DiscordSettingsSection: View {
    @Bindable private var settings = SettingsManager.shared
    private let service = DiscordRichPresenceService.shared

    var body: some View {
        Section {
            Toggle(String(localized: "Show What's Playing on Discord"), isOn: self.$settings.discordRichPresenceEnabled)

            if self.settings.discordRichPresenceEnabled {
                HStack(spacing: 6) {
                    Image(systemName: self.statusIcon)
                        .foregroundStyle(self.statusColor)
                    Text(self.statusText)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        } header: {
            Text("Discord", comment: "Settings section for Discord Rich Presence")
        } footer: {
            Text(String(localized: "Your Discord profile shows the song or video playing in Kaset, through the Discord app on this Mac. Nothing is sent anywhere else, and it clears when playback stops."))
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var statusText: String {
        switch self.service.status {
        case .disabled:
            String(localized: "Off")
        case .waitingForDiscord:
            String(localized: "Waiting for Discord to open on this Mac.")
        case .connected:
            String(localized: "Connected to Discord.")
        case let .rejected(message):
            String(localized: "Discord refused the connection: \(message)")
        case let .failed(message):
            String(localized: "Couldn't reach Discord: \(message)")
        }
    }

    private var statusIcon: String {
        switch self.service.status {
        case .connected: "checkmark.circle.fill"
        case .rejected, .failed: "exclamationmark.triangle.fill"
        default: "clock"
        }
    }

    private var statusColor: Color {
        switch self.service.status {
        case .connected: .green
        case .rejected, .failed: .orange
        default: .secondary
        }
    }
}
