import Foundation
import Testing
@testable import Kaset

// MARK: - YouTubeLyricsTests

/// Looking up a music video's lyrics on LRCLib: what the title and channel
/// give to search by, which result counts, and the panel's states.
@Suite(.serialized)
@MainActor
struct YouTubeLyricsTests {
    nonisolated static let synced = "[00:01.00] First line\n[00:04.50] Second line"

    nonisolated static func result(
        _ track: String,
        artist: String = "Artist",
        duration: Double,
        synced: String? = Self.synced,
        plain: String? = "First line\nSecond line",
        instrumental: Bool = false
    ) -> [String: Any] {
        var result: [String: Any] = ["id": track.hashValue, "trackName": track, "artistName": artist, "duration": duration, "instrumental": instrumental]
        result["syncedLyrics"] = synced
        result["plainLyrics"] = plain
        return result
    }

    private static func models(_ results: [[String: Any]]) throws -> [LRCLibModel] {
        try JSONDecoder().decode([LRCLibModel].self, from: JSONSerialization.data(withJSONObject: results))
    }

    @Test("Artist and song come from the title; decorations and featured artists go")
    func parsesTitles() {
        #expect(YouTubeLyricsQuery(videoTitle: "Rick Astley - Never Gonna Give You Up (Official Music Video)", channelName: "Rick Astley")
            == YouTubeLyricsQuery(artist: "Rick Astley", title: "Never Gonna Give You Up"))
        #expect(YouTubeLyricsQuery(videoTitle: "Daft Punk – Get Lucky ft. Pharrell Williams [4K Remastered]", channelName: nil)
            == YouTubeLyricsQuery(artist: "Daft Punk", title: "Get Lucky"))
        #expect(YouTubeLyricsQuery(videoTitle: "Song Title | Official Lyric Video", channelName: "Band - Topic")
            == YouTubeLyricsQuery(artist: "Band", title: "Song Title"))
        #expect(YouTubeLyricsQuery(videoTitle: "\"Quoted\" (Audio)", channelName: "SingerVEVO")
            == YouTubeLyricsQuery(artist: "Singer", title: "Quoted"))
        // A bracket that's part of the name stays, even with a decoration
        // word inside another word.
        #expect(YouTubeLyricsQuery(videoTitle: "Artist - Song (Part 2)", channelName: nil).title == "Song (Part 2)")
        #expect(YouTubeLyricsQuery(videoTitle: "Artist - Total (Eclipse)", channelName: nil).title == "Total (Eclipse)")
        #expect(YouTubeLyricsQuery(videoTitle: "Artist ft. Guest - Song", channelName: nil).artist == "Artist")
        #expect(YouTubeLyricsQuery(videoTitle: "Artist – Song - Remastered 2011", channelName: nil).artist == "Artist")
        #expect(YouTubeLyricsQuery(artist: "Artist", title: "Song").text == "Artist Song")
    }

    @Test("Only songs close to the video's length count; synced lyrics win a tie")
    func picksBestMatch() throws {
        let results = try Self.models([
            Self.result("Far", duration: 300),
            Self.result("Plain", duration: 212, synced: nil),
            Self.result("Synced", duration: 213),
            Self.result("Instrumental", duration: 212, instrumental: true),
        ])
        let match = try #require(YouTubeLyricsLookup.bestMatch(in: results, duration: 212))
        #expect(match.trackName == "Synced")
        guard case let .synced(lyrics) = match.lyrics else {
            Issue.record("Expected synced lyrics")
            return
        }
        #expect(lyrics.lines.map(\.text).filter { !$0.isEmpty } == ["First line", "Second line"])

        #expect(YouTubeLyricsLookup.bestMatch(in: results, duration: 600) == nil)

        // The closest wins over ones up to two seconds further in LRCLib's order.
        let chain = try Self.models([
            Self.result("Three off", duration: 203),
            Self.result("Two off", duration: 201.5),
            Self.result("Exact", duration: 200),
            Self.result("Far synced", duration: 215),
        ])
        #expect(YouTubeLyricsLookup.bestMatch(in: chain, duration: 200)?.trackName == "Exact")

        // An intro makes the video longer: the lyrics show, but not synced.
        let intro = try #require(YouTubeLyricsLookup.bestMatch(in: chain, duration: 210))
        #expect(intro.trackName == "Far synced")
        guard case .plain = intro.lyrics else {
            Issue.record("Expected plain lyrics for a song 5 s shorter than the video")
            return
        }

        // A typed search takes the closest even beyond the tolerance.
        #expect(YouTubeLyricsLookup.bestMatch(in: chain, duration: 260, enforcingLength: false)?.trackName == "Far synced")
        // Without the video's length, any synced one will do.
        #expect(YouTubeLyricsLookup.bestMatch(in: results, duration: nil)?.trackName != "Plain")
    }

    @Test("Artist and song are searched first, then free text")
    func fallsBackToFreeText() async throws {
        let requested = RequestLog()
        var lookup = YouTubeLyricsLookup()
        lookup.fetch = { url in
            await requested.append(url)
            let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
            let results: [[String: Any]] = items.contains { $0.name == "q" } ? [Self.result("Found", duration: 200)] : []
            return try JSONSerialization.data(withJSONObject: results)
        }
        let match = try await lookup.find(YouTubeLyricsQuery(artist: "Artist", title: "Song"), duration: 205)
        #expect(match?.trackName == "Found")
        let urls = await requested.urls
        #expect(urls.map(\.host) == ["lrclib.net", "lrclib.net"])
        #expect(urls.last?.query?.contains("q=Artist%20Song") == true)
    }

    @Test("The panel finds lyrics, says when there are none or LRCLib fails, and searches what's typed")
    func panelStates() async {
        let video = YouTubeVideo(videoId: "video01", title: "Artist - Song", channelName: "Artist")
        var lookup = YouTubeLyricsLookup()
        lookup.fetch = { url in
            let query = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
            if query.contains(where: { $0.value == "offline" }) {
                throw URLError(.notConnectedToInternet)
            }
            let found = query.contains { $0.value == "Song" || $0.value == "typed words" }
            return try JSONSerialization.data(withJSONObject: found ? [Self.result("Song", duration: 180)] : [])
        }
        let model = YouTubeLyricsViewModel(videoId: video.videoId, title: video.title, channelName: video.channelName, lookup: lookup)
        #expect(model.query == YouTubeLyricsQuery(artist: "Artist", title: "Song"))
        await model.run(duration: 180)
        guard case let .found(match) = model.state else {
            Issue.record("Expected lyrics")
            return
        }
        #expect(match.trackName == "Song")

        model.query = YouTubeLyricsQuery(artist: nil, title: "nothing here")
        await model.run(duration: 180)
        #expect(model.state == .notFound)

        model.query = YouTubeLyricsQuery(artist: nil, title: "offline")
        await model.run(duration: 180)
        #expect(model.state == .failed)

        model.search("  typed words ", duration: 180)
        #expect(model.query == YouTubeLyricsQuery(artist: nil, title: "typed words"))
        model.cancel()

        // Searching again shows the field without saying nothing was found.
        model.showSearch()
        #expect(model.state == .editing)
    }

    @Test("The query follows the watch page's title until something is looked up")
    func queryFollowsTitle() async {
        var lookup = YouTubeLyricsLookup()
        lookup.fetch = { _ in try JSONSerialization.data(withJSONObject: [[String: Any]]()) }
        let model = YouTubeLyricsViewModel(videoId: "video01", title: "", channelName: nil, lookup: lookup)
        model.updateQuery(title: "Artist - Song (Official Video)", channelName: "Artist")
        #expect(model.query == YouTubeLyricsQuery(artist: "Artist", title: "Song"))

        await model.run(duration: 200)
        model.updateQuery(title: "Something else", channelName: nil)
        #expect(model.query == YouTubeLyricsQuery(artist: "Artist", title: "Song"))
    }

    @Test("Listed lengths read as seconds")
    func readsListedLengths() {
        #expect(YouTubeLyricsPanel.seconds(fromLength: "3:33") == 213)
        #expect(YouTubeLyricsPanel.seconds(fromLength: "1:02:03") == 3723)
        #expect(YouTubeLyricsPanel.seconds(fromLength: "LIVE") == nil)
    }
}

// MARK: - RequestLog

private actor RequestLog {
    private(set) var urls: [URL] = []

    func append(_ url: URL) {
        self.urls.append(url)
    }
}
