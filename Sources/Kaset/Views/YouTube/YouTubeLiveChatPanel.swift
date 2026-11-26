import SwiftUI

// MARK: - YouTubeLiveChatPanel

/// A live stream's chat beside the video: the latest messages, following the
/// newest unless the user scrolls up, and a field to post when YouTube allows
/// it. Polls only while it's on screen.
struct YouTubeLiveChatPanel: View {
    let continuation: String
    let client: any YouTubeClientProtocol
    let allowsPosting: Bool

    @State private var model: YouTubeLiveChatViewModel?
    @State private var draft = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Live Chat", comment: "Header of a live stream's chat beside the video")
                .font(.headline)
                .padding(.horizontal, 12)
                .padding(.vertical, 10)

            Divider()

            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 8) {
                        ForEach(self.model?.messages ?? []) { message in
                            YouTubeLiveChatRow(message: message)
                                .id(message.id)
                        }
                    }
                    .padding(12)
                }
                .defaultScrollAnchor(.bottom)
                .onChange(of: self.model?.messages.last?.id) { _, id in
                    guard let id else { return }
                    withAnimation(.easeOut(duration: 0.2)) {
                        proxy.scrollTo(id, anchor: .bottom)
                    }
                }
            }
            .overlay {
                if self.model?.messages.isEmpty ?? true {
                    ProgressView()
                        .controlSize(.small)
                }
            }

            if self.allowsPosting, let model = self.model {
                if model.canSend {
                    Divider()
                    self.composer(model)
                } else if let restriction = model.restrictionMessage {
                    Divider()
                    Label(restriction, systemImage: "info.circle")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 10)
                }
            }
        }
        .frame(height: 460)
        .background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .clipShape(.rect(cornerRadius: 12, style: .continuous))
        .task(id: self.continuation) {
            let model = YouTubeLiveChatViewModel(client: self.client)
            self.model = model
            await model.run(continuation: self.continuation)
        }
    }

    private func composer(_ model: YouTubeLiveChatViewModel) -> some View {
        HStack(spacing: 8) {
            TextField(String(localized: "Chat…"), text: self.$draft)
                .textFieldStyle(.plain)
                .onSubmit { self.post(model) }
            Button {
                self.post(model)
            } label: {
                Image(systemName: "paperplane.fill")
            }
            .buttonStyle(.plain)
            .foregroundStyle(self.draft.isEmpty ? AnyShapeStyle(.tertiary) : AnyShapeStyle(.tint))
            .disabled(self.draft.trimmingCharacters(in: .whitespaces).isEmpty || model.isSending)
            .accessibilityLabel(String(localized: "Send"))
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
    }

    private func post(_ model: YouTubeLiveChatViewModel) {
        let text = self.draft
        Task {
            if await model.send(text) {
                self.draft = ""
            }
        }
    }
}

// MARK: - YouTubeLiveChatRow

private struct YouTubeLiveChatRow: View {
    let message: YouTubeLiveChatMessage

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            CachedAsyncImage(url: self.message.authorAvatarURL, targetSize: CGSize(width: 20, height: 20)) { image in
                image
                    .resizable()
                    .scaledToFill()
            } placeholder: {
                Circle().fill(.quaternary)
            }
            .frame(width: 20, height: 20)
            .clipShape(.circle)

            (Text(self.message.author).font(.system(size: 12, weight: .semibold)).foregroundStyle(self.authorStyle)
                + Text("  ") + Text(self.message.message).font(.system(size: 12)))
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .accessibilityElement(children: .combine)
    }

    /// The owner, moderators, and members stand out, as on YouTube.
    private var authorStyle: AnyShapeStyle {
        if self.message.isOwner {
            return AnyShapeStyle(.orange)
        }
        if self.message.isModerator {
            return AnyShapeStyle(.blue)
        }
        if self.message.isMember {
            return AnyShapeStyle(.green)
        }
        return AnyShapeStyle(.secondary)
    }
}
