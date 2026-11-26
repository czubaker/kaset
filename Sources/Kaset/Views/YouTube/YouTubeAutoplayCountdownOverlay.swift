import SwiftUI

// MARK: - YouTubeAutoplayCountdownOverlay

/// The "Up Next" card over the video after it finishes with Autoplay on: the
/// next video's title, a countdown ring that plays it now when clicked, and
/// Cancel. Shared by the watch page and the pop-out window; draws nothing when
/// no autoplay is pending. Ported from KasetPlus (github.com/Yoddikko/kasetPlus,
/// MIT).
struct YouTubeAutoplayCountdownOverlay: View {
    @Environment(YouTubePlayerService.self) private var youtubePlayer

    var body: some View {
        if let next = self.youtubePlayer.autoplayPendingVideo {
            self.card(next: next)
                .transition(.opacity)
        }
    }

    private func card(next: YouTubeVideo) -> some View {
        let total = YouTubePlayerService.autoplayCountdownSeconds
        let remaining = max(self.youtubePlayer.autoplayCountdownRemaining, 0)
        let fraction = CGFloat(remaining) / CGFloat(max(total, 1))

        return ZStack {
            Rectangle()
                .fill(.black.opacity(0.62))

            VStack(spacing: 14) {
                Text("Up Next")
                    .font(.system(size: 12, weight: .semibold))
                    .textCase(.uppercase)
                    .foregroundStyle(.white.opacity(0.7))

                Text(next.title)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.white)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)

                Button {
                    self.youtubePlayer.confirmAutoplayNow()
                } label: {
                    ZStack {
                        Circle()
                            .stroke(.white.opacity(0.25), lineWidth: 3)
                        Circle()
                            .trim(from: 0, to: fraction)
                            .stroke(.white, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                            .rotationEffect(.degrees(-90))
                        Text("\(remaining)")
                            .font(.system(size: 22, weight: .semibold).monospacedDigit())
                            .foregroundStyle(.white)
                    }
                    .frame(width: 62, height: 62)
                    .contentShape(Circle())
                }
                .buttonStyle(.plain)
                .help(String(localized: "Play Now"))
                .accessibilityLabel(String(localized: "Play Now"))

                Button {
                    self.youtubePlayer.cancelAutoplay()
                } label: {
                    Text("Cancel")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 16)
                        .frame(height: 30)
                        .compatGlass(interactive: true, tint: nil, in: Capsule())
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
            }
            .padding(24)
            .frame(maxWidth: 440)
        }
        .animation(.linear(duration: 1), value: remaining)
    }
}
