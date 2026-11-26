import SwiftUI

// MARK: - YouTubePlayerBarDetailsBlock

/// Two lines of details, each one the user picked: the first in the title
/// style (scrolling when it's too long), the second smaller below it. The
/// channel opens its page from either line.
struct YouTubePlayerBarDetailsBlock: View {
    /// One rendered line.
    enum Line {
        /// Text in the line's style; with an action, a button.
        case text(String, identity: String, action: (() -> Void)? = nil)
        /// The channel name as a link (second line only).
        case link(String, isEnabled: Bool, action: () -> Void)
    }

    let first: Line
    /// Nil leaves the second line empty, as while a chapter preview shows.
    let second: Line?

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            self.firstLine

            if let second {
                self.secondLine(second)
            } else {
                Spacer()
                    .frame(height: 11)
            }
        }
        .frame(width: YouTubePlayerBarMetrics.titleWidth, height: 29, alignment: .leading)
    }

    @ViewBuilder
    private var firstLine: some View {
        switch self.first {
        case let .text(text, identity, action):
            let marquee = PlayerBarMarqueeText(
                text: text,
                font: .systemFont(ofSize: 13),
                color: .labelColor,
                height: 13,
                reduceMotion: self.reduceMotion
            )
            .id(identity)
            if let action {
                Button(action: action) { marquee.contentShape(.rect) }
                    .buttonStyle(.plain)
            } else {
                marquee
            }
        case let .link(text, isEnabled, action):
            // The first line keeps the title style; the link is the whole line.
            Button(action: action) {
                PlayerBarMarqueeText(
                    text: text,
                    font: .systemFont(ofSize: 13),
                    color: .labelColor,
                    height: 13,
                    reduceMotion: self.reduceMotion
                )
                .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .disabled(!isEnabled)
        }
    }

    @ViewBuilder
    private func secondLine(_ line: Line) -> some View {
        switch line {
        case let .link(text, isEnabled, action):
            PlayerBarMetadataButton(text: text, isEnabled: isEnabled, action: action)
        case let .text(text, _, action):
            let label = Text(text)
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.tail)
                .frame(maxWidth: .infinity, alignment: .leading)
            if let action {
                Button(action: action) { label.contentShape(.rect) }
                    .buttonStyle(.plain)
            } else {
                label
            }
        }
    }
}

// MARK: - YouTubePlayerBarSubscribeButton

/// Subscribe / Subscribed for the current video's channel, sharing its state
/// with the watch page's button. Disabled until a watch page has said whether
/// the account is subscribed. The compact style is an icon button the size
/// of the bar's other buttons.
struct YouTubePlayerBarSubscribeButton: View {
    let channelId: String
    let client: (any YouTubeClientProtocol)?
    var isCompact = false

    private let subscriptions = YouTubeChannelSubscriptions.shared
    private static let brandAccent = PackageResourceLookup.brandAccent

    var body: some View {
        let state = self.subscriptions.isSubscribed(to: self.channelId)
        let isSubscribed = state ?? false
        Group {
            if self.isCompact {
                PlayerBarIconButton(
                    action: { self.toggle(isSubscribed: isSubscribed) },
                    isSelected: isSubscribed,
                    accessibilityID: AccessibilityID.YouTubeContent.playerBarSubscribeButton,
                    accessibilityLabel: isSubscribed ? String(localized: "Subscribed") : String(localized: "Subscribe"),
                    icon: {
                        Image(systemName: isSubscribed ? "person.crop.circle.badge.checkmark" : "person.crop.circle.badge.plus")
                            .font(.system(size: 16, weight: .regular))
                            .frame(width: 20, height: 16)
                            .foregroundStyle(isSubscribed ? AnyShapeStyle(.primary) : AnyShapeStyle(Self.brandAccent))
                            .contentTransition(.symbolEffect(.replace))
                    }
                )
                .help(isSubscribed ? String(localized: "Subscribed") : String(localized: "Subscribe"))
            } else {
                Button {
                    self.toggle(isSubscribed: isSubscribed)
                } label: {
                    Text(isSubscribed ? String(localized: "Subscribed") : String(localized: "Subscribe"))
                        .font(.system(size: 12, weight: .semibold))
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)
                        .foregroundStyle(isSubscribed ? AnyShapeStyle(.primary) : AnyShapeStyle(.white))
                        .frame(width: YouTubePlayerBarMetrics.subscribeWidth, height: 26)
                        .background(
                            isSubscribed ? AnyShapeStyle(.quaternary) : AnyShapeStyle(Self.brandAccent),
                            in: Capsule()
                        )
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier(AccessibilityID.YouTubeContent.playerBarSubscribeButton)
            }
        }
        .disabled(state == nil || self.client == nil)
    }

    private func toggle(isSubscribed: Bool) {
        guard let client else { return }
        Task {
            await self.subscriptions.setSubscribed(!isSubscribed, channelId: self.channelId, client: client)
        }
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

// MARK: - AccessibilityID Additions

extension AccessibilityID.YouTubeContent {
    static let playerBarSubscribeButton = "youtubeContent.playerBarSubscribeButton"
}
