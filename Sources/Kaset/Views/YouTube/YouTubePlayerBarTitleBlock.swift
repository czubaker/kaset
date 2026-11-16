import SwiftUI

// MARK: - YouTubePlayerBarTitleBlock

/// The video title over the channel name, which opens the channel. While a
/// chapter preview shows, the title line names the chapter and the channel
/// line stays empty.
struct YouTubePlayerBarTitleBlock: View {
    let title: String
    let titleIdentity: String
    let channelName: String
    let showsChannel: Bool
    let canOpenChannel: Bool
    let onOpenChannel: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            PlayerBarMarqueeText(
                text: self.title,
                font: .systemFont(ofSize: 13),
                color: .labelColor,
                height: 13,
                reduceMotion: self.reduceMotion
            )
            .id(self.titleIdentity)

            if self.showsChannel {
                PlayerBarMetadataButton(
                    text: self.channelName,
                    isEnabled: self.canOpenChannel,
                    action: self.onOpenChannel
                )
            } else {
                Spacer()
                    .frame(height: 11)
            }
        }
        .frame(width: YouTubePlayerBarMetrics.titleWidth, height: 29, alignment: .leading)
    }
}

// MARK: - YouTubePlayerBarChannelAvatar

/// The channel's avatar, which opens the channel. Shows a placeholder until
/// the watch page has loaded the channel.
struct YouTubePlayerBarChannelAvatar: View {
    let url: URL?
    let canOpenChannel: Bool
    let onOpenChannel: () -> Void

    var body: some View {
        Button(action: self.onOpenChannel) {
            CachedAsyncImage(
                url: self.url,
                targetSize: CGSize(width: 48, height: 48)
            ) { image in
                image
                    .resizable()
                    .scaledToFill()
            } placeholder: {
                Circle()
                    .fill(.quaternary)
                    .overlay {
                        Image(systemName: "person.fill")
                            .font(.system(size: 11))
                            .foregroundStyle(.tertiary)
                    }
            }
            .frame(width: YouTubePlayerBarMetrics.avatarSize, height: YouTubePlayerBarMetrics.avatarSize)
            .clipShape(.circle)
            .contentShape(.circle)
        }
        .buttonStyle(.plain)
        .disabled(!self.canOpenChannel)
        .accessibilityLabel(String(localized: "Go to Channel"))
    }
}
