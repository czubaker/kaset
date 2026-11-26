import SwiftUI

// MARK: - YouTubeNotificationsButton

/// The toolbar's bell: a badge with how many notifications arrived since the
/// inbox was last opened, and the inbox in a popover. Ported from KasetPlus
/// (github.com/Yoddikko/kasetPlus, MIT).
struct YouTubeNotificationsButton: View {
    let viewModel: YouTubeNotificationsViewModel
    let onOpen: (YouTubeVideo) -> Void

    @State private var isPresented = false

    var body: some View {
        Button {
            self.isPresented.toggle()
        } label: {
            if self.viewModel.unseenCount > 0 {
                // A red dot, as on YouTube's bell.
                Label(String(localized: "Notifications"), systemImage: "bell.badge")
                    .font(.system(size: 14))
                    .symbolRenderingMode(.palette)
                    .foregroundStyle(.red, .primary)
            } else {
                Label(String(localized: "Notifications"), systemImage: "bell")
                    .font(.system(size: 14))
                    .foregroundStyle(.primary)
            }
        }
        .help(String(localized: "Notifications"))
        .accessibilityValue(self.accessibilityValue)
        .popover(isPresented: self.$isPresented, arrowEdge: .bottom) {
            YouTubeNotificationsList(viewModel: self.viewModel) { video in
                self.isPresented = false
                self.onOpen(video)
            }
        }
        .task(id: self.viewModel.pollID) {
            await self.viewModel.poll()
        }
        .task(id: self.isPresented) {
            guard self.isPresented else { return }
            await self.viewModel.open()
        }
    }

    private var accessibilityValue: String {
        let count = self.viewModel.unseenCount
        return count > 0 ? String(localized: "\(count) new") : ""
    }
}

// MARK: - YouTubeNotificationsList

private struct YouTubeNotificationsList: View {
    let viewModel: YouTubeNotificationsViewModel
    let onOpen: (YouTubeVideo) -> Void

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text(String(localized: "Notifications"))
                    .font(.headline)
                Spacer()
                if self.viewModel.isLoading {
                    ProgressView()
                        .controlSize(.small)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)

            Divider()

            if self.viewModel.notifications.isEmpty {
                self.emptyState
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(self.viewModel.notifications) { notification in
                            YouTubeNotificationRow(
                                notification: notification,
                                isNew: self.viewModel.isNew(notification)
                            ) {
                                self.onOpen(notification.video)
                            }
                        }
                    }
                    .padding(.vertical, 4)
                }
                .frame(maxHeight: 420)
            }
        }
        .frame(width: 360)
    }

    private var emptyState: some View {
        VStack(spacing: 10) {
            Image(systemName: self.viewModel.didFail ? "exclamationmark.triangle" : "bell.slash")
                .font(.system(size: 26))
                .foregroundStyle(.tertiary)
            Text(self.emptyMessage)
                .font(.callout)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 36)
    }

    private var emptyMessage: String {
        if self.viewModel.didFail {
            return String(localized: "Couldn’t load notifications.")
        }
        if self.viewModel.isLoading {
            return String(localized: "Loading…")
        }
        return String(localized: "No notifications")
    }
}

// MARK: - YouTubeNotificationRow

private struct YouTubeNotificationRow: View {
    let notification: YouTubeNotification
    let isNew: Bool
    let action: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: self.action) {
            HStack(alignment: .top, spacing: 10) {
                Circle()
                    .fill(self.isNew ? Color.accentColor : Color.clear)
                    .frame(width: 7, height: 7)
                    .padding(.top, 20)

                CachedAsyncImage(
                    url: self.notification.thumbnailURL,
                    targetSize: CGSize(width: 96, height: 54)
                ) { image in
                    image
                        .resizable()
                        .scaledToFill()
                } placeholder: {
                    Rectangle()
                        .fill(.quaternary)
                }
                .frame(width: 86, height: 48)
                .clipShape(.rect(cornerRadius: 6))

                VStack(alignment: .leading, spacing: 3) {
                    Text(self.notification.message)
                        .font(.system(size: 12, weight: self.isNew ? .semibold : .regular))
                        .foregroundStyle(.primary)
                        .lineLimit(3)
                        .multilineTextAlignment(.leading)
                    if let time = self.notification.sentTimeText {
                        Text(time)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }

                Spacer(minLength: 0)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(
                self.isHovered ? Color.primary.opacity(0.06) : Color.clear,
                in: .rect(cornerRadius: 8)
            )
            .padding(.horizontal, 4)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .onHover { self.isHovered = $0 }
        .accessibilityElement(children: .combine)
    }
}
