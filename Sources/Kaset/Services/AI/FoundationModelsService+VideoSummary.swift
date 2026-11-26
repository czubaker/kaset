import Foundation
import FoundationModels

// MARK: - Video Summary

@available(macOS 26.0, *)
extension FoundationModelsService {
    /// Whether the watch page can offer a summary: Apple Intelligence on and
    /// ready, in a language it writes.
    var canSummarizeVideos: Bool {
        self.isAvailable && self.supportsLocale(Locale.current)
    }

    /// Summarizes a video from its captions, on this Mac. `onProgress` gets
    /// which part is being read (1-based) of how many, and the summary as it
    /// is written.
    func summarizeVideo(
        title: String,
        transcript: String,
        onProgress: @escaping @MainActor (YouTubeVideoSummaryProgress) -> Void
    ) async throws -> YouTubeVideoSummary {
        self.refreshAvailability()
        guard self.canSummarizeVideos else {
            throw AIError.notAvailable(reason: "Apple Intelligence is off or doesn't support this language")
        }

        let language = Self.summaryLanguageName
        let parts = YouTubeVideoSummaryPlan.parts(of: transcript)
        let material: String
        if parts.count <= 1 {
            material = "Transcript:\n\(parts.first ?? transcript)"
        } else {
            var notes: [String] = []
            for (index, part) in parts.enumerated() {
                try Task.checkCancellation()
                onProgress(.readingPart(index + 1, of: parts.count))
                let session = LanguageModelSession(instructions: """
                You take notes on part of a YouTube video's transcript. Write 3 to 5 short \
                notes on what this part says, using only the transcript. Write in English.
                """)
                let response = try await session.respond(to: """
                Video: \(title)
                Part \(index + 1) of \(parts.count) of the transcript:
                \(part)
                """)
                notes.append("Part \(index + 1):\n\(response.content)")
            }
            material = "Notes on the transcript, part by part:\n\(notes.joined(separator: "\n\n"))"
        }

        try Task.checkCancellation()
        onProgress(.writing(nil))
        let session = LanguageModelSession(instructions: """
        You summarize YouTube videos from what is said in them. Be accurate and concise, use \
        only the material given, and never add facts. Write in \(language).
        """)
        let stream = session.streamResponse(
            to: "Video: \(title)\n\n\(material)\n\nSummarize the whole video.",
            generating: VideoSummary.self
        )
        var latest: VideoSummary.PartiallyGenerated?
        for try await snapshot in stream {
            latest = snapshot.content
            onProgress(.writing(YouTubeVideoSummary(
                overview: snapshot.content.overview ?? "",
                keyPoints: snapshot.content.keyPoints ?? []
            )))
        }
        guard let overview = latest?.overview, !overview.isEmpty else {
            throw AIError.decodingFailure
        }
        return YouTubeVideoSummary(overview: overview, keyPoints: latest?.keyPoints ?? [])
    }

    /// The app's language in English ("German"; "Chinese, Traditional"), for
    /// the instructions.
    private static var summaryLanguageName: String {
        let language = Locale.current.language
        let code = language.languageCode?.identifier ?? "en"
        // Chinese names its script, or the model writes Simplified.
        let identifier = code == "zh" ? [code, language.script?.identifier].compactMap(\.self).joined(separator: "-") : code
        return Locale(identifier: "en").localizedString(forIdentifier: identifier) ?? "English"
    }
}

// MARK: - YouTubeVideoSummaryProgress

enum YouTubeVideoSummaryProgress: Equatable {
    /// Taking notes on a long transcript, part by part (1-based).
    case readingPart(Int, of: Int)
    /// Writing the summary; what is written so far.
    case writing(YouTubeVideoSummary?)
}
