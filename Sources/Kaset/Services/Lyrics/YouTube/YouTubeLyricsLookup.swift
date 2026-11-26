import Foundation

// MARK: - YouTubeLyricsLookup

/// Finds a music video's lyrics on LRCLib: by artist and song first, then by
/// free text, keeping only songs whose length is close to the video's, so a
/// video that isn't a song finds nothing rather than someone else's lyrics.
/// Adapted from KasetPlus (github.com/Yoddikko/kasetPlus, MIT).
struct YouTubeLyricsLookup {
    struct Match: Equatable {
        let lyrics: LyricResult
        let trackName: String
        let artistName: String?
    }

    /// A song this much shorter or longer than the video still counts:
    /// music videos often add an intro or an outro.
    static let durationTolerance: TimeInterval = 20
    /// Synced lines follow the video only when the song is this close to its
    /// length; further off (an intro), they would run ahead, so the lyrics
    /// show as plain text.
    static let syncTolerance: TimeInterval = 3

    var fetch: @Sendable (URL) async throws -> Data = { url in
        var request = URLRequest(url: url)
        request.setValue("Kaset/1.0 (https://github.com/sozercan/kaset)", forHTTPHeaderField: "User-Agent")
        request.timeoutInterval = 15
        let (data, response) = try await URLSession.shared.data(for: request)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else {
            throw URLError(.badServerResponse)
        }
        return data
    }

    /// `enforcingLength` turns away songs more than `durationTolerance` off
    /// the video's length; a search the user typed takes the closest anyway.
    func find(_ query: YouTubeLyricsQuery, duration: TimeInterval?, enforcingLength: Bool = true) async throws -> Match? {
        if let artist = query.artist,
           let match = try await self.search([
               URLQueryItem(name: "track_name", value: query.title),
               URLQueryItem(name: "artist_name", value: artist),
           ], duration: duration, enforcingLength: enforcingLength)
        {
            return match
        }
        return try await self.search(
            [URLQueryItem(name: "q", value: query.text)],
            duration: duration,
            enforcingLength: enforcingLength
        )
    }

    private func search(_ items: [URLQueryItem], duration: TimeInterval?, enforcingLength: Bool) async throws -> Match? {
        var components = URLComponents()
        components.scheme = "https"
        components.host = "lrclib.net"
        components.path = "/api/search"
        components.queryItems = items
        guard let url = components.url else { return nil }
        let results = try await JSONDecoder().decode([LRCLibModel].self, from: self.fetch(url))
        return Self.bestMatch(in: results, duration: duration, enforcingLength: enforcingLength)
    }

    /// The closest in length among those with lyrics, preferring synced ones
    /// within two seconds of the closest; none if a known length matches
    /// nothing.
    static func bestMatch(in results: [LRCLibModel], duration: TimeInterval?, enforcingLength: Bool = true) -> Match? {
        let usable = results.filter {
            $0.instrumental != true && ($0.syncedLyrics?.isEmpty == false || $0.plainLyrics?.isEmpty == false)
        }
        let best: LRCLibModel?
        if let duration, duration > 0 {
            func distance(_ result: LRCLibModel) -> TimeInterval {
                abs((result.duration ?? 0) - duration)
            }
            let inRange = enforcingLength ? usable.filter { distance($0) <= Self.durationTolerance } : usable
            guard let closest = inRange.map(distance).min() else { return nil }
            let nearest = inRange
                .filter { distance($0) <= closest + 2 }
                .sorted { distance($0) < distance($1) }
            best = nearest.first { $0.syncedLyrics?.isEmpty == false } ?? nearest.first
        } else {
            best = usable.first { $0.syncedLyrics?.isEmpty == false } ?? usable.first
        }
        guard let best else { return nil }
        let parsed = best.syncedLyrics.flatMap(LRCParser.parse).flatMap { $0.isEmpty ? nil : $0 }
        let followsVideo = duration.map { abs((best.duration ?? 0) - $0) <= Self.syncTolerance } ?? true
        let lyrics: LyricResult
        if let parsed, followsVideo {
            lyrics = .synced(SyncedLyrics(lines: parsed.lines, source: "LRCLib"))
        } else if let plain = best.plainLyrics, !plain.isEmpty {
            lyrics = .plain(Lyrics(text: plain, source: "LRCLib"))
        } else if let parsed {
            let text = parsed.lines.map(\.text).filter { !$0.isEmpty }.joined(separator: "\n")
            lyrics = .plain(Lyrics(text: text, source: "LRCLib"))
        } else {
            return nil
        }
        return Match(lyrics: lyrics, trackName: best.trackName ?? "", artistName: best.artistName)
    }
}
