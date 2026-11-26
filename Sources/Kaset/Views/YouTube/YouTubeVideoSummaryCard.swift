import SwiftUI

// MARK: - YouTubeVideoSummaryCard

/// A summary of the video by Apple Intelligence, written on this Mac from the
/// video's captions when the user asks. Adapted from KasetPlus
/// (github.com/Yoddikko/kasetPlus, MIT).
struct YouTubeVideoSummaryCard: View {
    let title: String

    @State private var model: YouTubeVideoSummaryViewModel

    init(videoId: String, title: String, client: any YouTubeClientProtocol) {
        self.title = title
        _model = State(initialValue: YouTubeVideoSummaryViewModel(videoId: videoId, client: client))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Label(String(localized: "Summary"), systemImage: "sparkles")
                    .font(.system(size: 13, weight: .semibold))
                Spacer(minLength: 8)
                if self.model.isWorking {
                    ProgressView()
                        .controlSize(.small)
                } else if self.showsSummarizeButton {
                    Button(self.buttonTitle) {
                        self.model.summarize(title: self.title)
                    }
                    .controlSize(.small)
                }
            }

            self.content
        }
        .padding(12)
        .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .accessibilityElement(children: .contain)
        .accessibilityLabel(String(localized: "Summary"))
        .onDisappear {
            self.model.cancel()
        }
    }

    @ViewBuilder
    private var content: some View {
        switch self.model.state {
        case .idle:
            self.note(String(localized: "Apple Intelligence can summarize this video on your Mac from its captions."))
        case .fetchingCaptions:
            self.note(String(localized: "Reading the captions…"))
        case let .readingPart(part, total):
            self.note(String(localized: "Reading part \(part) of \(total)…"))
        case let .writing(partial):
            if let partial, !partial.overview.isEmpty {
                self.summary(partial)
            } else {
                self.note(String(localized: "Writing the summary…"))
            }
        case let .done(summary):
            self.summary(summary)
            self.note(String(localized: "Written on your Mac by Apple Intelligence from the video’s captions. It can make mistakes."))
        case let .failed(failure):
            self.note(self.message(for: failure))
        }
    }

    private func summary(_ summary: YouTubeVideoSummary) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(summary.overview)
                .font(.system(size: 13))
            ForEach(Array(summary.keyPoints.enumerated()), id: \.offset) { _, point in
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(verbatim: "•")
                        .foregroundStyle(.secondary)
                    Text(point)
                        .font(.system(size: 13))
                }
            }
        }
        .textSelection(.enabled)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func note(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 12))
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var showsSummarizeButton: Bool {
        switch self.model.state {
        case .idle: true
        case let .failed(failure): failure != .noCaptions
        default: false
        }
    }

    private var buttonTitle: String {
        if case .failed = self.model.state {
            return String(localized: "Try Again")
        }
        return String(localized: "Summarize")
    }

    private func message(for failure: YouTubeVideoSummaryViewModel.Failure) -> String {
        switch failure {
        case .noCaptions:
            String(localized: "This video has no captions to summarize.")
        case .declined:
            String(localized: "Apple Intelligence can’t summarize this video.")
        case .unavailable:
            String(localized: "Apple Intelligence isn’t available right now.")
        case .other:
            String(localized: "Couldn’t summarize this video.")
        }
    }
}
