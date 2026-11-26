import Foundation
import FoundationModels

// MARK: - YouTubeVideoSummary

/// What the watch page shows for a summarized video.
struct YouTubeVideoSummary: Equatable {
    var overview: String
    var keyPoints: [String]
}

// MARK: - VideoSummary

/// A YouTube video's summary as the on-device model writes it, from the
/// video's captions. Adapted from KasetPlus
/// (github.com/Yoddikko/kasetPlus, MIT).
@available(macOS 26.0, *)
@Generable
struct VideoSummary {
    @Guide(description: "One or two sentences on what the video is about.")
    let overview: String

    @Guide(description: "The video's main points in the order they come up, each one short sentence.", .count(3 ... 6))
    let keyPoints: [String]
}

// MARK: - YouTubeVideoSummaryPlan

/// How a transcript is fed to the on-device model, whose context holds 4,096
/// tokens for instructions, prompt, and answer together: a short one in one
/// go; a long one in parts, each boiled down to notes, and the summary written
/// from the notes.
enum YouTubeVideoSummaryPlan {
    /// Estimated tokens per part, leaving room for the instructions and the
    /// answer.
    static let partTokenBudget = 1500.0
    /// At most this many parts are read; a longer transcript is sampled
    /// evenly from start to end.
    static let maximumParts = 8
    /// Shorter than this, there isn't enough to summarize.
    static let minimumLength = 200

    /// A rough token count: about one per Chinese, Japanese, or Korean
    /// character, two characters per token in other non-Latin scripts, and
    /// four in Latin ones.
    static func estimatedTokens(_ text: some StringProtocol) -> Double {
        text.unicodeScalars.reduce(0) { $0 + Self.weight(of: $1) }
    }

    /// `transcript` cut into parts of at most `budget` estimated tokens, at
    /// word boundaries where there are any (a run without spaces, as in
    /// Chinese or Japanese, is cut where it fills a part), at most
    /// `maximumParts` of them, spread over the whole.
    static func parts(
        of transcript: String,
        budget: Double = Self.partTokenBudget,
        maximumParts: Int = Self.maximumParts
    ) -> [String] {
        var parts: [String] = []
        var current = ""
        var currentTokens = 0.0
        for word in transcript.split(whereSeparator: \.isWhitespace) {
            for (index, piece) in Self.pieces(of: word, budget: budget).enumerated() {
                // Pieces of one word join without a space.
                let separator = !current.isEmpty && index == 0 ? " " : ""
                let tokens = Self.estimatedTokens(piece)
                if !current.isEmpty, currentTokens + Self.estimatedTokens(separator) + tokens > budget {
                    parts.append(current)
                    current = piece
                    currentTokens = tokens
                    continue
                }
                current += separator + piece
                currentTokens += Self.estimatedTokens(separator) + tokens
            }
        }
        if !current.isEmpty {
            parts.append(current)
        }
        guard parts.count > maximumParts, maximumParts > 0 else { return parts }
        // Evenly spaced, always keeping the first and the last.
        let step = Double(parts.count - 1) / Double(max(1, maximumParts - 1))
        return (0 ..< maximumParts).map { parts[Int((Double($0) * step).rounded())] }
    }

    /// `word` itself, or cut into pieces that each fit `budget`.
    private static func pieces(of word: Substring, budget: Double) -> [String] {
        guard self.estimatedTokens(word) > budget else { return [String(word)] }
        var pieces: [String] = []
        var piece = ""
        var tokens = 0.0
        for character in word {
            let weight = Self.estimatedTokens(String(character))
            if !piece.isEmpty, tokens + weight > budget {
                pieces.append(piece)
                piece = ""
                tokens = 0
            }
            piece.append(character)
            tokens += weight
        }
        if !piece.isEmpty {
            pieces.append(piece)
        }
        return pieces
    }

    private static func weight(of scalar: Unicode.Scalar) -> Double {
        switch scalar.value {
        case 0x0000 ... 0x024F: 0.3 // Latin
        case 0x1100 ... 0x11FF, 0x2E80 ... 0x9FFF, 0xA960 ... 0xA97F, 0xAC00 ... 0xD7FF, 0xF900 ... 0xFAFF,
             0xFF00 ... 0xFFEF, 0x20000 ... 0x3FFFF:
            1 // CJK, kana, Hangul, full-width forms
        default: 0.5
        }
    }
}
