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
    /// Bumped by Try Again to restart polling.
    @State private var attempt = 0

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
                    self.emptyState
                }
            }

            if self.allowsPosting, let model = self.model {
                if model.canSend {
                    Divider()
                    self.composer(model)
                    if model.sendFailed {
                        Text("Couldn't send the message.", comment: "Shown under the live chat field when posting fails")
                            .font(.caption)
                            .foregroundStyle(.red)
                            .padding(.horizontal, 12)
                            .padding(.bottom, 8)
                    }
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
        .task(id: "\(self.continuation)|\(self.attempt)") {
            let model = YouTubeLiveChatViewModel(client: self.client)
            self.model = model
            await model.run(continuation: self.continuation)
        }
    }

    @ViewBuilder
    private var emptyState: some View {
        if let model = self.model, model.didFail {
            VStack(spacing: 8) {
                Text("Couldn't load the chat.", comment: "Live chat panel when polling failed")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                Button(String(localized: "Try Again")) {
                    self.attempt += 1
                }
            }
        } else if let model = self.model, model.isFinished {
            Text("The chat has ended.", comment: "Live chat panel after the chat stops")
                .font(.callout)
                .foregroundStyle(.secondary)
        } else {
            ProgressView()
                .controlSize(.small)
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

            Text(self.attributedLine)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .accessibilityElement(children: .combine)
    }

    /// The author in bold, then the message.
    private var attributedLine: AttributedString {
        var author = AttributedString(self.message.author)
        author.font = .system(size: 12, weight: .semibold)
        author.foregroundColor = self.authorColor
        var text = AttributedString("  " + self.message.message)
        text.font = .system(size: 12)
        return author + text
    }

    /// The owner, moderators, and members stand out, as on YouTube.
    private var authorColor: Color {
        if self.message.isOwner {
            return .orange
        }
        if self.message.isModerator {
            return .blue
        }
        if self.message.isMember {
            return .green
        }
        return .secondary
    }
}
