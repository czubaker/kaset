import SwiftUI

// MARK: - YouTubeQueuePanel

/// The videos queued after the one playing, beside the page like YouTube
/// Music's queue: click one to play it, drag to reorder, swipe or use its
/// menu to remove it.
struct YouTubeQueuePanel: View {
    @Environment(YouTubePlayerService.self) private var youtubePlayer
    @Namespace private var queueNamespace

    var body: some View {
        CompatGlassContainer(spacing: 0) {
            VStack(spacing: 0) {
                self.header
                Divider()
                    .opacity(0.3)
                self.content
            }
            .frame(width: 300)
            .compatGlass(interactive: true, in: .rect(cornerRadius: 20))
            .compatGlassID("youtubeQueuePanel", in: self.queueNamespace)
        }
        .compatGlassTransition(.materialize)
    }

    private var header: some View {
        HStack {
            Text("Queue", comment: "Header of the YouTube video queue panel")
                .font(.headline)
            Spacer()
            if !self.youtubePlayer.videoQueue.isEmpty {
                Button(String(localized: "Clear")) {
                    withAnimation(AppAnimation.quick) {
                        self.youtubePlayer.clearQueue()
                    }
                }
                .buttonStyle(.plain)
                .font(.subheadline)
                .foregroundStyle(.red)
            }
            Button {
                withAnimation(AppAnimation.standard) {
                    self.youtubePlayer.showsQueue = false
                }
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(String(localized: "Close"))
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    @ViewBuilder
    private var content: some View {
        if self.youtubePlayer.videoQueue.isEmpty {
            VStack(spacing: 8) {
                Image(systemName: "text.append")
                    .font(.system(size: 26))
                    .foregroundStyle(.tertiary)
                Text("Nothing queued", comment: "YouTube queue panel when empty")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                Text("Right-click a video and choose Play Next or Add to Queue.", comment: "YouTube queue panel hint")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .multilineTextAlignment(.center)
            }
            .padding(24)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            List {
                ForEach(Array(self.youtubePlayer.videoQueue.enumerated()), id: \.element.videoId) { index, video in
                    YouTubeQueueRow(video: video) {
                        self.youtubePlayer.playFromQueue(at: index)
                    }
                    .contextMenu {
                        Button(String(localized: "Play Now")) {
                            self.youtubePlayer.playFromQueue(at: index)
                        }
                        Button(String(localized: "Remove from Queue"), role: .destructive) {
                            self.youtubePlayer.removeFromQueue(atOffsets: IndexSet(integer: index))
                        }
                    }
                }
                .onMove { source, destination in
                    self.youtubePlayer.moveInQueue(fromOffsets: source, toOffset: destination)
                }
                .onDelete { offsets in
                    self.youtubePlayer.removeFromQueue(atOffsets: offsets)
                }
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
        }
    }
}

// MARK: - YouTubeQueueRow

private struct YouTubeQueueRow: View {
    let video: YouTubeVideo
    let action: () -> Void

    var body: some View {
        Button(action: self.action) {
            HStack(spacing: 10) {
                CachedAsyncImage(url: self.video.thumbnailURL, targetSize: CGSize(width: 96, height: 54)) { image in
                    image
                        .resizable()
                        .scaledToFill()
                } placeholder: {
                    Rectangle().fill(.quaternary)
                }
                .frame(width: 72, height: 40)
                .clipShape(.rect(cornerRadius: 5))

                VStack(alignment: .leading, spacing: 2) {
                    Text(self.video.title)
                        .font(.system(size: 12, weight: .medium))
                        .lineLimit(2)
                    if let channel = self.video.channelName {
                        Text(channel)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
                Spacer(minLength: 0)
            }
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
    }
}
