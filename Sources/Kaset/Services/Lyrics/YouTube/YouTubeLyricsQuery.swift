import Foundation

// MARK: - YouTubeLyricsQuery

/// What to look a music video's lyrics up by, from its title and channel:
/// "Artist - Song (Official Video)" gives artist and song; a title without a
/// dash takes the artist from the channel ("Artist - Topic", "ArtistVEVO").
struct YouTubeLyricsQuery: Equatable {
    var artist: String?
    var title: String

    /// The words for a free-text search.
    var text: String {
        [self.artist, self.title].compactMap(\.self).joined(separator: " ")
    }

    init(artist: String?, title: String) {
        self.artist = artist
        self.title = title
    }

    init(videoTitle: String, channelName: String?) {
        var title = Self.removingDecorations(from: videoTitle)
        var artist: String?
        // The earliest separator of any kind: "Artist – Song - Remastered".
        let separators = [" - ", " – ", " — ", " ~ "].compactMap { title.range(of: $0) }
        if let range = separators.min(by: { $0.lowerBound < $1.lowerBound }) {
            artist = String(title[..<range.lowerBound])
            title = String(title[range.upperBound...])
        }
        if artist == nil, let channelName {
            artist = Self.artist(fromChannel: channelName)
        }
        self.artist = artist.map { Self.trimmed(Self.removingFeatured(from: $0)) }.flatMap { $0.isEmpty ? nil : $0 }
        self.title = Self.trimmed(Self.removingFeatured(from: title))
    }

    /// Brackets that only describe the upload, "| …" tails, and quotes.
    private static func removingDecorations(from title: String) -> String {
        var result = title
        if let bar = result.range(of: " | ") ?? result.range(of: " // ") {
            result = String(result[..<bar.lowerBound])
        }
        let brackets = try? NSRegularExpression(pattern: #"\s*[\(\[【「](?<inner>[^\)\]】」]*)[\)\]】」]"#)
        let nsRange = NSRange(result.startIndex..., in: result)
        let matches = brackets?.matches(in: result, range: nsRange) ?? []
        for match in matches.reversed() {
            guard let innerRange = Range(match.range(withName: "inner"), in: result),
                  let fullRange = Range(match.range, in: result)
            else { continue }
            let inner = String(result[innerRange])
            let innerNSRange = NSRange(inner.startIndex..., in: inner)
            if Self.decorationPattern?.firstMatch(in: inner, range: innerNSRange) != nil || inner.contains("公式") {
                result.removeSubrange(fullRange)
            }
        }
        return result.replacingOccurrences(of: "\"", with: "")
            .replacingOccurrences(of: "“", with: "")
            .replacingOccurrences(of: "”", with: "")
    }

    /// "ft. Someone" and "feat. Someone" to the end.
    private static func removingFeatured(from title: String) -> String {
        guard let range = title.range(of: #"\s(ft\.?|feat\.?|featuring)\s.*$"#, options: [.regularExpression, .caseInsensitive])
        else { return title }
        return String(title[..<range.lowerBound])
    }

    private static func artist(fromChannel channel: String) -> String {
        var name = channel
        for suffix in [" - Topic", "VEVO", " Official"] where name.hasSuffix(suffix) {
            name = String(name.dropLast(suffix.count))
        }
        return name
    }

    private static func trimmed(_ text: String) -> String {
        text.trimmingCharacters(in: .whitespacesAndNewlines.union(CharacterSet(charactersIn: "-–—|")))
    }

    /// Whole words that mark a bracket as describing the upload, not the song.
    private static let decorationPattern = try? NSRegularExpression(
        pattern: #"(?<![\p{L}\p{N}])(official|video|audio|lyrics?|visuali[sz]er|mv|m/v|hd|hq|4k|remaster(ed)?|explicit|clip|live|ft|feat|featuring|prod)(?![\p{L}\p{N}])"#,
        options: .caseInsensitive
    )
}
