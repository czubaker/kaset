import SwiftUI

// MARK: - YouTubePlayerBarSeekButton

/// Seeks back or forward by a fixed number of seconds; the bar offers 5, 10,
/// 15, 30, and 60.
struct YouTubePlayerBarSeekButton: View {
    let seconds: Int
    let isForward: Bool
    let canSeek: Bool

    @Environment(YouTubePlayerService.self) private var youtubePlayer

    var body: some View {
        PlayerBarIconButton(
            action: {
                HapticService.playback()
                if self.isForward {
                    self.youtubePlayer.seekForward(by: Double(self.seconds))
                } else {
                    self.youtubePlayer.seekBackward(by: Double(self.seconds))
                }
            },
            accessibilityLabel: self.label,
            icon: {
                Image(systemName: "\(self.isForward ? "goforward" : "gobackward").\(self.seconds)")
                    .font(.system(size: 16, weight: .regular))
                    .frame(width: 16, height: 16)
                    .foregroundStyle(.primary)
            }
        )
        .disabled(!self.canSeek)
    }

    private var label: String {
        switch (self.seconds, self.isForward) {
        case (5, false): String(localized: "Back 5 seconds")
        case (5, true): String(localized: "Forward 5 seconds")
        case (10, false): String(localized: "Back 10 seconds")
        case (10, true): String(localized: "Forward 10 seconds")
        case (15, false): String(localized: "Back 15 seconds")
        case (15, true): String(localized: "Forward 15 seconds")
        case (60, false): String(localized: "Back 1 minute")
        case (60, true): String(localized: "Forward 1 minute")
        case (_, false): String(localized: "Back 30 seconds")
        case (_, true): String(localized: "Forward 30 seconds")
        }
    }
}

// MARK: - YouTubePlayerBarVideoSkipButton

/// Previous Video (back through what played here, or to the start) and Next
/// Video (the first related video), as the media keys do.
struct YouTubePlayerBarVideoSkipButton: View {
    let isForward: Bool

    @Environment(YouTubePlayerService.self) private var youtubePlayer

    var body: some View {
        PlayerBarIconButton(
            action: {
                HapticService.playback()
                if self.isForward {
                    Task { await self.youtubePlayer.skipForward() }
                } else {
                    self.youtubePlayer.skipBackward()
                }
            },
            accessibilityLabel: self.isForward ? String(localized: "Next Video") : String(localized: "Previous Video"),
            icon: {
                Image(systemName: self.isForward ? "forward.end.fill" : "backward.end.fill")
                    .font(.system(size: 14, weight: .regular))
                    .frame(width: 16, height: 16)
                    .foregroundStyle(.primary)
            }
        )
        .disabled(self.youtubePlayer.currentVideo == nil || self.youtubePlayer.isShowingAd)
    }
}

// MARK: - YouTubePlayerBarShareButton

/// Shares the video's YouTube link, with Copy Link first.
struct YouTubePlayerBarShareButton: View {
    @Environment(YouTubePlayerService.self) private var youtubePlayer

    var body: some View {
        let url = self.youtubePlayer.currentVideo?.shareURL
        PlayerBarIconButton(
            action: {
                guard let url else { return }
                HapticService.toggle()
                ShareContextMenu.showSharePicker(for: url)
            },
            accessibilityLabel: String(localized: "Share"),
            icon: {
                Image(systemName: "square.and.arrow.up")
                    .font(.system(size: 15, weight: .regular))
                    .frame(width: 16, height: 16)
                    .offset(y: -1)
                    .foregroundStyle(.primary)
            }
        )
        .disabled(url == nil)
    }
}
