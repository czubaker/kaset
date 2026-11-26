import SwiftUI

// MARK: - YouTubeLinkedText

/// Text from YouTube (a description, a comment) with its web links and its
/// timestamps made clickable, as YouTube shows them: `M:SS`, `MM:SS`, and
/// `H:MM:SS` within the video's length seek the player. Ported in spirit from
/// KasetPlus (github.com/Yoddikko/kasetPlus, MIT).
enum YouTubeLinkedText {
    /// Timestamps link to `kasetseek://<seconds>`, which `youtubeSeekLinks`
    /// turns into a seek.
    static let seekScheme = "kasetseek"

    /// Built once: comments render this on every update, and making a data
    /// detector is costly. Both are immutable and safe to share.
    nonisolated(unsafe) static let linkDetector = try? NSDataDetector(
        types: NSTextCheckingResult.CheckingType.link.rawValue
    )
    nonisolated(unsafe) static let timestampRegex = try? NSRegularExpression(
        pattern: "(?<![\\d:])\\d{1,2}:\\d{2}(?::\\d{2})?(?![\\d:])"
    )

    /// The seconds a `M:SS` or `H:MM:SS` timestamp stands for.
    static func seconds(fromTimestamp token: String) -> Int? {
        let parts = token.split(separator: ":").map { Int($0) }
        guard !parts.contains(nil) else { return nil }
        let numbers = parts.compactMap(\.self)
        switch numbers.count {
        case 2 where numbers[1] < 60:
            return numbers[0] * 60 + numbers[1]
        case 3 where numbers[1] < 60 && numbers[2] < 60:
            return numbers[0] * 3600 + numbers[1] * 60 + numbers[2]
        default:
            return nil
        }
    }

    /// `text` with web links, and with timestamps up to `duration` linked to
    /// a seek (none when `duration` is 0, as when the page's video isn't the
    /// one playing).
    static func attributed(_ text: String, duration: TimeInterval) -> AttributedString {
        var result = AttributedString(text)
        let whole = NSRange(text.startIndex..., in: text)
        var linked: [Range<String.Index>] = []

        if let detector = Self.linkDetector {
            for match in detector.matches(in: text, range: whole) {
                guard let url = match.url, url.scheme == "https" || url.scheme == "http",
                      let range = Range(match.range, in: text),
                      let attributedRange = Range(range, in: result)
                else { continue }
                result[attributedRange].link = url
                linked.append(range)
            }
        }

        guard duration > 0, let regex = Self.timestampRegex else { return result }
        for match in regex.matches(in: text, range: whole) {
            guard let range = Range(match.range, in: text),
                  !linked.contains(where: { $0.overlaps(range) }),
                  let seconds = Self.seconds(fromTimestamp: String(text[range])),
                  Double(seconds) <= duration,
                  let url = URL(string: "\(Self.seekScheme)://\(seconds)"),
                  let attributedRange = Range(range, in: result)
            else { continue }
            result[attributedRange].link = url
        }
        return result
    }

    /// The seconds a seek link points at, or nil for any other link.
    static func seekSeconds(from url: URL) -> Double? {
        guard url.scheme == self.seekScheme, let host = url.host, let seconds = Double(host) else { return nil }
        return seconds
    }
}

extension View {
    /// Seeks `player` for timestamp links in this text; other links open as
    /// usual.
    func youtubeSeekLinks(_ player: YouTubePlayerService) -> some View {
        self.environment(\.openURL, OpenURLAction { url in
            guard let seconds = YouTubeLinkedText.seekSeconds(from: url) else { return .systemAction }
            player.seek(to: seconds)
            return .handled
        })
    }
}
