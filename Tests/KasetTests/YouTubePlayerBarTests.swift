import AppKit
import Foundation
import Testing
@testable import Kaset

@Suite("YouTube player bar", .tags(.model))
@MainActor
struct YouTubePlayerBarTests {
    @Test("Float on Top control appears for a windowed floating surface")
    func floatOnTopControlAppearsForWindowedFloatingSurface() {
        #expect(YouTubePlayerBar.shouldShowFloatOnTopControl(
            isDetachedWindow: true,
            surfaceLocation: .floating,
            isFullscreenOrTransitioning: false
        ))
    }

    @Test("Float on Top control stays hidden outside a windowed floating surface")
    func floatOnTopControlStaysHiddenOutsideWindowedFloatingSurface() {
        #expect(!YouTubePlayerBar.shouldShowFloatOnTopControl(
            isDetachedWindow: true,
            surfaceLocation: .none,
            isFullscreenOrTransitioning: false
        ))
        #expect(!YouTubePlayerBar.shouldShowFloatOnTopControl(
            isDetachedWindow: true,
            surfaceLocation: .inline,
            isFullscreenOrTransitioning: false
        ))
        #expect(!YouTubePlayerBar.shouldShowFloatOnTopControl(
            isDetachedWindow: true,
            surfaceLocation: .floating,
            isFullscreenOrTransitioning: true
        ))
        #expect(!YouTubePlayerBar.shouldShowFloatOnTopControl(
            isDetachedWindow: false,
            surfaceLocation: .floating,
            isFullscreenOrTransitioning: false
        ))
    }

    @Test("The standard layout keeps the bar's widths and details-hiding breakpoint")
    func standardLayoutKeepsWidths() {
        let layout = PlayerBarConfiguration<YouTubePlayerBarItem>.standard
        let leading = layout.items(in: .leading)
        // Float on Top shows only in the detached window.
        let trailing = layout.items(in: .trailing).filter { $0 != .floatOnTop }
        let pinnedTrailing = layout.items(in: .trailing)
        // Compact details drop the title; signed out drops the rating and
        // Watch Later buttons.
        let compactLeading = leading.filter { $0 != .videoInfo }
        let signedOutTrailing = trailing.filter { $0 != .watchLater }

        #expect(YouTubePlayerBarMetrics.sideWidth(leading, area: .leading, compact: false) == 294)
        #expect(YouTubePlayerBarMetrics.sideWidth(compactLeading, area: .leading, compact: true) == 141)
        #expect(YouTubePlayerBarMetrics.sideWidth(trailing, area: .trailing, compact: false) == 210)
        #expect(YouTubePlayerBarMetrics.sideWidth(pinnedTrailing, area: .trailing, compact: false) == 244)
        #expect(YouTubePlayerBarMetrics.sideWidth(signedOutTrailing, area: .trailing, compact: false) == 176)

        let center = layout.items(in: .center)
        let liveCenter = center.filter { $0 != .skipBack && $0 != .skipForward }
        let breakpoint = YouTubePlayerBarMetrics.hiddenDetailsBreakpoint(
            leading: compactLeading, trailing: trailing, center: center
        )
        let pinnedBreakpoint = YouTubePlayerBarMetrics.hiddenDetailsBreakpoint(
            leading: compactLeading, trailing: pinnedTrailing, center: center
        )
        let liveBreakpoint = YouTubePlayerBarMetrics.hiddenDetailsBreakpoint(
            leading: compactLeading, trailing: trailing, center: liveCenter
        )
        #expect(breakpoint == 580)
        #expect(pinnedBreakpoint - breakpoint == 34)
        #expect(liveBreakpoint == breakpoint)
        // Below it the standard leading side hides entirely.
        #expect(YouTubePlayerBarMetrics.narrowLeading(leading).isEmpty)
    }

    @Test("A wider center row raises the breakpoint, and narrowing keeps placed controls")
    func narrowLayoutFollowsItems() {
        let center: [YouTubePlayerBarItem] = [.skipBack, .playPause, .skipForward, .volume]
        let widerCenter = center + [.airPlay, .captions]
        let added: CGFloat = 2 * (28 + 6)
        let breakpoint = YouTubePlayerBarMetrics.hiddenDetailsBreakpoint(leading: [], trailing: [], center: center)
        let widerBreakpoint = YouTubePlayerBarMetrics.hiddenDetailsBreakpoint(leading: [], trailing: [], center: widerCenter)
        #expect(widerBreakpoint - breakpoint == added)

        let expectedLeading: [YouTubePlayerBarItem] = [.playPause, .space, .pictureInPicture]
        let leading: [YouTubePlayerBarItem] = [.thumbnail, .channelInfo, .playPause, .space, .like, .pictureInPicture]
        #expect(YouTubePlayerBarMetrics.narrowLeading(leading) == expectedLeading)
        #expect(YouTubePlayerBarMetrics.narrowLeading([.thumbnail, .space, .videoInfo]).isEmpty)
    }

    @Test("Side widths follow the items placed, and an empty side takes none")
    func sideWidthsFollowItems() {
        // Channel block: avatar, its gap, and the title; 16pt of room after it.
        let channelBlock: CGFloat = 14 + 24 + 6 + 129 + 16
        let compactChannelBlock: CGFloat = 14 + 24
        // A space between two buttons: 6pt gaps on both sides of its 12pt.
        let spacedButtons: CGFloat = 12 + 28 + 6 + 12 + 6 + 28
        #expect(YouTubePlayerBarMetrics.sideWidth([.channelInfo], area: .leading, compact: false) == channelBlock)
        #expect(YouTubePlayerBarMetrics.sideWidth([.channelInfo], area: .leading, compact: true) == compactChannelBlock)
        #expect(YouTubePlayerBarMetrics.sideWidth([.airPlay, .space, .captions], area: .trailing, compact: false) == spacedButtons)
        #expect(YouTubePlayerBarMetrics.sideWidth([], area: .trailing, compact: false) == 0)
        // Channel avatar and Subscribe: two blocks, 8pt apart.
        let avatarAndSubscribe: CGFloat = 14 + 24 + 8 + 92
        #expect(YouTubePlayerBarMetrics.sideWidth([.channelAvatar, .subscribe], area: .leading, compact: true) == avatarAndSubscribe)
    }

    @Test("Detached controls stay visible while the volume overlay is presented")
    func detachedControlsStayVisibleWhileVolumeOverlayIsPresented() {
        #expect(!YouTubeVideoWindowLevelPolicy.shouldShowChrome(
            isWindowHovered: false,
            isVolumeOverlayPresented: false
        ))
        #expect(YouTubeVideoWindowLevelPolicy.shouldShowChrome(
            isWindowHovered: true,
            isVolumeOverlayPresented: false
        ))
        #expect(YouTubeVideoWindowLevelPolicy.shouldShowChrome(
            isWindowHovered: false,
            isVolumeOverlayPresented: true
        ))
    }

    @Test("Chapter segments resolve explicit, next-chapter, and duration end times")
    func chapterSegmentsResolveEndTimes() throws {
        let chapters = [
            self.chapter(title: "Opening", start: 0, end: 45),
            self.chapter(title: "Main topic", start: 60),
            self.chapter(title: "Closing", start: 180),
        ]

        let segments = YouTubePlayerBar.chapterProgressSegments(chapters: chapters, duration: 300)
        #expect(segments.count == 3)

        let opening = try #require(segments.first)
        #expect(opening.start == 0)
        #expect(abs(opening.end - 0.15) < 0.000_001)
        #expect(opening.title == "Opening")
        #expect(opening.itemLabel == String(localized: "Chapter"))
        #expect(opening.rangeText == "0:00 – 0:45")

        let mainTopic = segments[1]
        #expect(abs(mainTopic.start - 0.2) < 0.000_001)
        #expect(abs(mainTopic.end - 0.6) < 0.000_001)
        #expect(mainTopic.title == "Main topic")
        #expect(mainTopic.itemLabel == String(localized: "Chapter"))
        #expect(mainTopic.rangeText == "1:00 – 3:00")

        let closing = try #require(segments.last)
        #expect(abs(closing.start - 0.6) < 0.000_001)
        #expect(closing.end == 1)
        #expect(closing.title == "Closing")
        #expect(closing.itemLabel == String(localized: "Chapter"))
        #expect(closing.rangeText == "3:00 – 5:00")

        #expect(segments.map(\.index) == [0, 1, 2])
        #expect(segments.allSatisfy { $0.count == 3 })
    }

    @Test("Explicit chapter ends are capped by the next chapter and video duration")
    func explicitEndsAreCapped() throws {
        let chapters = [
            self.chapter(title: "Overlaps next", start: 0, end: 180),
            self.chapter(title: "Past duration", start: 100, end: 500),
        ]

        let segments = YouTubePlayerBar.chapterProgressSegments(chapters: chapters, duration: 240)
        #expect(segments.count == 2)

        let first = try #require(segments.first)
        #expect(first.start == 0)
        #expect(abs(first.end - (100.0 / 240.0)) < 0.000_001)
        #expect(first.rangeText == "0:00 – 1:40")

        let second = try #require(segments.last)
        #expect(abs(second.start - (100.0 / 240.0)) < 0.000_001)
        #expect(second.end == 1)
        #expect(second.rangeText == "1:40 – 4:00")
    }

    @Test("Invalid starts and duplicate boundaries are omitted and valid spans are reindexed")
    func invalidChaptersAreOmittedAndSegmentsAreReindexed() {
        let chapters = [
            self.chapter(title: "Intro", start: 0, end: 80),
            self.chapter(title: "Recovered end", start: 80, end: 80),
            self.chapter(title: "Final", start: 180),
            self.chapter(title: "Final", start: 180),
            self.chapter(title: "Negative", start: -1, end: 20),
            self.chapter(title: "Not a number", start: .nan, end: 20),
            self.chapter(title: "Infinite", start: .infinity, end: nil),
            self.chapter(title: "At duration", start: 300, end: nil),
            self.chapter(title: "Past duration", start: 450, end: nil),
        ]

        let segments = YouTubePlayerBar.chapterProgressSegments(chapters: chapters, duration: 300)

        #expect(segments.count == 3)
        #expect(segments.map(\.index) == [0, 1, 2])
        #expect(segments.allSatisfy { $0.count == 3 })
        #expect(segments.map(\.title) == ["Intro", "Recovered end", "Final"])

        #expect(segments[0].start == 0)
        #expect(abs(segments[0].end - (80.0 / 300.0)) < 0.000_001)
        #expect(abs(segments[1].start - (80.0 / 300.0)) < 0.000_001)
        #expect(abs(segments[1].end - (180.0 / 300.0)) < 0.000_001)
        #expect(segments[1].rangeText == "1:20 – 3:00")
        #expect(abs(segments[2].start - (180.0 / 300.0)) < 0.000_001)
        #expect(segments[2].end == 1)
    }

    private func chapter(
        title: String,
        start: TimeInterval,
        end: TimeInterval? = nil
    ) -> YouTubeChapter {
        YouTubeChapter(
            videoId: "video-id",
            title: title,
            startTime: start,
            endTime: end,
            timeText: nil,
            thumbnailURL: nil
        )
    }

    @Test("Every item's symbol exists, so the palette and the seek buttons draw")
    func itemSymbolsExist() {
        for item in YouTubePlayerBarItem.allCases {
            #expect(NSImage(systemSymbolName: item.systemImage, accessibilityDescription: nil) != nil, "\(item)")
        }
        for seconds in [5, 10, 15, 30, 60] {
            #expect(NSImage(systemSymbolName: "gobackward.\(seconds)", accessibilityDescription: nil) != nil)
            #expect(NSImage(systemSymbolName: "goforward.\(seconds)", accessibilityDescription: nil) != nil)
        }
        for name in ["person.crop.circle.badge.plus", "person.crop.circle.badge.checkmark"] {
            #expect(NSImage(systemSymbolName: name, accessibilityDescription: nil) != nil, "\(name)")
        }
    }

    @Test("Skip buttons seek 5, 10, 15, 30, and 60 seconds each way; other items don't seek")
    func seekIntervals() {
        let back: [YouTubePlayerBarItem] = [.skipBack5, .skipBack10, .skipBack15, .skipBack, .skipBack60]
        let forward: [YouTubePlayerBarItem] = [.skipForward5, .skipForward10, .skipForward15, .skipForward, .skipForward60]
        #expect(back.compactMap(\.seek?.seconds) == [5, 10, 15, 30, 60])
        #expect(forward.compactMap(\.seek?.seconds) == [5, 10, 15, 30, 60])
        #expect(back.allSatisfy { $0.seek?.isForward == false })
        #expect(forward.allSatisfy { $0.seek?.isForward == true })
        #expect(YouTubePlayerBarItem.skipBack.systemImage == "gobackward.30")
        #expect(YouTubePlayerBarItem.skipForward60.systemImage == "goforward.60")
        #expect(YouTubePlayerBarItem.playPause.seek == nil)
        #expect(YouTubePlayerBarItem.nextVideo.seek == nil)
    }

    @Test("A video shares its watch link; a Short shares its Shorts link")
    func shareURLs() {
        let video = YouTubeVideo(videoId: "abc123", title: "Video")
        let short = YouTubeVideo(videoId: "short1", title: "Short", isShort: true)
        #expect(video.shareURL?.absoluteString == "https://www.youtube.com/watch?v=abc123")
        #expect(short.shareURL?.absoluteString == "https://www.youtube.com/shorts/short1")
    }
}
