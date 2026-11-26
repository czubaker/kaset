import SwiftUI

// MARK: - YouTubeWatchCollaborators

/// The owner row of a collaboration upload: the channels' avatars stacked,
/// their names together, and a list with each channel and its own Subscribe
/// button. Ported from KasetPlus (github.com/Yoddikko/kasetPlus, MIT).
struct YouTubeWatchCollaborators: View {
    let title: String
    let collaborators: [VideoCollaborator]
    let allowsSubscribing: Bool
    let client: any YouTubeClientProtocol
    let openChannel: (String) -> Void

    @State private var showsList = false

    var body: some View {
        HStack(spacing: 12) {
            Button {
                self.showsList = true
            } label: {
                HStack(spacing: 10) {
                    self.avatarStack
                    VStack(alignment: .leading, spacing: 2) {
                        Text(self.title)
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(.primary)
                            .lineLimit(1)
                        Text(String(localized: "\(self.collaborators.count) channels"))
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                    }
                }
                .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .help(String(localized: "Collaborators"))
            .popover(isPresented: self.$showsList, arrowEdge: .bottom) {
                self.list
            }

            if self.allowsSubscribing {
                Button {
                    self.showsList = true
                } label: {
                    Text(String(localized: "Subscribe…"))
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.primary)
                        .padding(.horizontal, 16)
                        .frame(height: 36)
                        .compatGlass(interactive: true, in: Capsule())
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var avatarStack: some View {
        HStack(spacing: -12) {
            ForEach(self.collaborators.prefix(3)) { collaborator in
                self.avatar(collaborator.avatarURL, size: 36)
                    .overlay(Circle().stroke(.background, lineWidth: 2))
            }
        }
    }

    private var list: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(String(localized: "Collaborators"))
                .font(.headline)
                .padding(.horizontal, 16)
                .padding(.top, 14)
                .padding(.bottom, 8)
            ForEach(self.collaborators) { collaborator in
                self.row(collaborator)
            }
        }
        .padding(.bottom, 10)
        .frame(width: 400)
    }

    private func row(_ collaborator: VideoCollaborator) -> some View {
        HStack(spacing: 10) {
            Button {
                self.showsList = false
                self.openChannel(collaborator.channelId)
            } label: {
                HStack(spacing: 10) {
                    self.avatar(collaborator.avatarURL, size: 36)
                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 4) {
                            Text(collaborator.name)
                                .font(.system(size: 13, weight: .semibold))
                                .lineLimit(1)
                            if collaborator.isVerified {
                                Image(systemName: "checkmark.seal.fill")
                                    .font(.system(size: 10))
                                    .foregroundStyle(.secondary)
                                    .accessibilityLabel(String(localized: "Verified"))
                            }
                        }
                        if let detail = collaborator.detail {
                            Text(detail)
                                .font(.system(size: 11))
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                    }
                    Spacer(minLength: 8)
                }
                .contentShape(.rect)
            }
            .buttonStyle(.plain)

            if self.allowsSubscribing {
                YouTubePlayerBarSubscribeButton(channelId: collaborator.channelId, client: self.client)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 6)
    }

    private func avatar(_ url: URL?, size: CGFloat) -> some View {
        CachedAsyncImage(url: url, targetSize: CGSize(width: size, height: size)) { image in
            image
                .resizable()
                .scaledToFill()
        } placeholder: {
            Circle().fill(.quaternary)
        }
        .frame(width: size, height: size)
        .clipShape(.circle)
    }
}
