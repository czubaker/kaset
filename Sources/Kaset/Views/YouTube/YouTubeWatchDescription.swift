import SwiftUI

// MARK: - YouTubeWatchDescription

/// The video's description under its title, three lines until expanded, with
/// its links and timestamps clickable.
struct YouTubeWatchDescription: View {
    let text: String
    /// Timestamps up to this many seconds seek the video; 0 links none.
    let linkDuration: TimeInterval

    @Environment(YouTubePlayerService.self) private var youtubePlayer
    @State private var isExpanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(YouTubeLinkedText.attributed(self.text, duration: self.linkDuration))
                .font(.system(size: 13))
                .foregroundStyle(.primary)
                .lineLimit(self.isExpanded ? nil : 3)
                .textSelection(.enabled)
                .youtubeSeekLinks(self.youtubePlayer)
                .frame(maxWidth: .infinity, alignment: .leading)

            Button {
                withAnimation(AppAnimation.quick) {
                    self.isExpanded.toggle()
                }
            } label: {
                Text(self.isExpanded ? String(localized: "Show Less") : String(localized: "Show More"))
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
        }
        .padding(12)
        .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .accessibilityElement(children: .contain)
        .accessibilityLabel(String(localized: "Description"))
    }
}
