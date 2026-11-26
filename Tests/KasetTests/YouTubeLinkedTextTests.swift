import Foundation
import Testing
@testable import Kaset

// MARK: - YouTubeLinkedTextTests

@Suite(.tags(.model))
struct YouTubeLinkedTextTests {
    private static func links(in text: AttributedString) -> [(String, URL)] {
        text.runs.compactMap { run in
            run.link.map { (String(text[run.range].characters), $0) }
        }
    }

    @Test("Timestamps read as M:SS and H:MM:SS; anything else isn't one")
    func readsTimestamps() {
        #expect(YouTubeLinkedText.seconds(fromTimestamp: "1:05") == 65)
        #expect(YouTubeLinkedText.seconds(fromTimestamp: "12:00") == 720)
        #expect(YouTubeLinkedText.seconds(fromTimestamp: "1:02:03") == 3723)
        #expect(YouTubeLinkedText.seconds(fromTimestamp: "1:75") == nil)
        #expect(YouTubeLinkedText.seconds(fromTimestamp: "5") == nil)
    }

    @Test("Timestamps within the video seek; later ones, or with no length, stay text")
    func linksTimestamps() {
        let text = YouTubeLinkedText.attributed("Intro 0:00, the drop at 2:30 🎉, credits 1:02:03", duration: 300)
        let links = Self.links(in: text)
        #expect(links.map(\.0) == ["0:00", "2:30"])
        #expect(links.map { YouTubeLinkedText.seekSeconds(from: $0.1) } == [0, 150])
        #expect(Self.links(in: YouTubeLinkedText.attributed("at 2:30", duration: 0)).isEmpty)
    }

    @Test("Web links open; a timestamp inside one stays part of the link")
    func linksURLs() {
        let text = YouTubeLinkedText.attributed("Source: https://example.com/watch?t=1:30 and 1:30", duration: 600)
        let links = Self.links(in: text)
        #expect(links.count == 2)
        #expect(links[0].1.absoluteString.hasPrefix("https://example.com/"))
        #expect(YouTubeLinkedText.seekSeconds(from: links[0].1) == nil)
        #expect(YouTubeLinkedText.seekSeconds(from: links[1].1) == 90)
    }

    @Test("Only kasetseek links are seeks")
    func readsSeekLinks() throws {
        #expect(try YouTubeLinkedText.seekSeconds(from: #require(URL(string: "kasetseek://42"))) == 42)
        #expect(try YouTubeLinkedText.seekSeconds(from: #require(URL(string: "https://42.example.com"))) == nil)
    }
}
