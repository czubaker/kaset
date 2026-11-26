import SwiftUI

// MARK: - YouTubePlayerBar

/// The Liquid Glass player bar for inline and detached YouTube playback.
struct YouTubePlayerBar: View {
    private static var brandAccent: Color {
        PackageResourceLookup.brandAccent
    }

    private struct ChapterProgressSpan {
        let chapter: YouTubeChapter
        let start: TimeInterval
        let end: TimeInterval
    }

    @Environment(AuthService.self) private var authService
    @Environment(YouTubePlayerService.self) private var youtubePlayer
    @Environment(YouTubeViewModelStore.self) private var youtubeStore: YouTubeViewModelStore?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorScheme) private var colorScheme

    private let isDetachedWindow: Bool
    private let onVolumeOverlayChange: (Bool) -> Void

    /// Namespace for glass effect morphing.
    @Namespace private var playerNamespace

    @State private var settings = SettingsManager.shared
    @State private var volumeValue: Double = 1.0
    @State private var isAdjustingVolume = false
    @State private var showsVolumeOverlay = false
    @State private var chapterPreviewMarker: PlayerBarProgressMarker?
    @State private var airPlayAnchor = AirPlayPickerAnchor()

    init(isDetachedWindow: Bool, onVolumeOverlayChange: @escaping (Bool) -> Void = { _ in }) {
        self.isDetachedWindow = isDetachedWindow
        self.onVolumeOverlayChange = onVolumeOverlayChange
    }

    var body: some View {
        CompatGlassContainer(spacing: 0) {
            GeometryReader { proxy in
                let usesCompactDetails = proxy.size.width <= PlayerBarLayout.compactDetailsBreakpoint
                // Only the resizable detached window gets this narrow; below it
                // the leading side's details would collide with the transport controls.
                let hidesDetails = proxy.size.width <= YouTubePlayerBarMetrics.hiddenDetailsBreakpoint(
                    leading: self.shownItems(in: .leading, compact: true),
                    trailing: self.shownItems(in: .trailing, compact: true),
                    center: self.shownItems(in: .center, compact: true)
                )
                let fullLeading = self.shownItems(in: .leading, compact: usesCompactDetails)
                let leading = hidesDetails ? YouTubePlayerBarMetrics.narrowLeading(fullLeading) : fullLeading
                let trailing = self.shownItems(in: .trailing, compact: usesCompactDetails)

                HStack(spacing: 10) {
                    if !leading.isEmpty {
                        self.sideRow(leading, area: .leading, compact: usesCompactDetails)
                            .frame(
                                width: YouTubePlayerBarMetrics.sideWidth(leading, area: .leading, compact: usesCompactDetails),
                                height: 52
                            )
                    }

                    self.youtubeProgressSection
                        .padding(.leading, leading.isEmpty ? PlayerBarItemSpacing.emptySideInset : 0)
                        .padding(.trailing, trailing.isEmpty ? PlayerBarItemSpacing.emptySideInset : 0)
                        .frame(maxWidth: .infinity)
                        .frame(height: 52)

                    if !trailing.isEmpty {
                        self.sideRow(trailing, area: .trailing, compact: usesCompactDetails)
                            .frame(
                                width: YouTubePlayerBarMetrics.sideWidth(trailing, area: .trailing, compact: usesCompactDetails),
                                height: 52
                            )
                    }
                }
            }
            .frame(maxWidth: .infinity)
            .frame(height: 52)
            .contextMenu {
                Button(String(localized: "Customize Player Bar…")) {
                    PlayerBarCustomization.shared.present(for: .video)
                }
            }
            .compatGlass(interactive: true, in: .capsule)
            .compatGlassID("youtubePlayerBar", in: self.playerNamespace)
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 8)
        .background(alignment: .bottom) {
            self.playerAreaFade
        }
        .onChange(of: self.currentSeekIdentity) { _, _ in
            self.chapterPreviewMarker = nil
        }
        .onChange(of: self.canSeek) { _, _ in
            self.chapterPreviewMarker = nil
        }
        .onChange(of: self.youtubePlayer.volume) { _, newValue in
            if !self.isAdjustingVolume {
                self.volumeValue = newValue
            }
        }
        .onChange(of: self.showsVolumeOverlay) { _, isPresented in self.onVolumeOverlayChange(isPresented) }
        .onAppear {
            self.volumeValue = self.youtubePlayer.volume
        }
    }

    private var playerAreaFade: some View {
        LinearGradient(
            colors: [
                Color(nsColor: .windowBackgroundColor).opacity(0),
                Color(nsColor: .windowBackgroundColor).opacity(0.22),
            ],
            startPoint: .top,
            endPoint: .bottom
        )
        .frame(height: 44)
        .frame(maxWidth: .infinity)
        .padding(.bottom, -8)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    // MARK: - Updated Player Layout

    // MARK: - Items

    /// Which items the bar shows, and where (customizable).
    private var layout: PlayerBarConfiguration<YouTubePlayerBarItem> {
        self.settings.youtubePlayerBar
    }

    /// The area's items that draw something right now.
    private func shownItems(in area: PlayerBarArea, compact: Bool) -> [YouTubePlayerBarItem] {
        self.layout.items(in: area).filter { self.isShown($0, compact: compact) }
    }

    private func isShown(_ item: YouTubePlayerBarItem, compact: Bool) -> Bool {
        switch item {
        case .videoInfo:
            !compact
        case .like, .dislike, .watchLater, .saveToPlaylist:
            self.hasPersonalAccount
        case .subscribe, .subscribeIcon:
            self.hasPersonalAccount && self.currentChannelId != nil
        case .skipBack, .skipForward, .skipBack5, .skipForward5, .skipBack10, .skipForward10,
             .skipBack15, .skipForward15, .skipBack60, .skipForward60:
            !self.isUnseekableLive
        case .floatOnTop:
            self.showsFloatOnTopControl
        case .settingsMenu:
            // Always has Customize Player Bar…, even with no picker to show.
            true
        case .captions, .quality, .playbackSpeed, .audioTrack:
            YouTubePlayerBarMenu.isShown(item, player: self.youtubePlayer)
        default:
            true
        }
    }

    /// One side of the bar, inset from the capsule's end.
    private func sideRow(_ items: [YouTubePlayerBarItem], area: PlayerBarArea, compact: Bool) -> some View {
        let isLeading = area == .leading
        return PlayerBarItemRow(items: items, isBlock: YouTubePlayerBarMetrics.isBlock) { item in
            self.itemView(item, compact: compact)
        }
        .padding(
            isLeading ? .leading : .trailing,
            isLeading ? YouTubePlayerBarMetrics.leadingInset : YouTubePlayerBarMetrics.trailingInset
        )
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: isLeading ? .leading : .trailing)
    }

    @ViewBuilder
    private func itemView(_ item: YouTubePlayerBarItem, compact: Bool) -> some View { // swiftlint:disable:this cyclomatic_complexity
        switch item {
        case .thumbnail:
            self.thumbnailView
        case .channelAvatar:
            self.channelAvatar
        case .videoInfo:
            self.detailsBlock(for: .videoInfo)
        case .channelInfo:
            HStack(spacing: YouTubePlayerBarMetrics.avatarTitleSpacing) {
                self.channelAvatar
                if !compact {
                    self.detailsBlock(for: .channelInfo)
                }
            }
        case .subscribe, .subscribeIcon:
            if let channelId = self.currentChannelId {
                YouTubePlayerBarSubscribeButton(
                    channelId: channelId,
                    client: self.youtubePlayer.youtubeClient,
                    isCompact: item == .subscribeIcon
                )
            }
        case .like:
            self.likeButton
        case .dislike:
            self.dislikeButton
        case .skipBack, .skipForward, .skipBack5, .skipForward5, .skipBack10, .skipForward10,
             .skipBack15, .skipForward15, .skipBack60, .skipForward60:
            if let seek = item.seek {
                YouTubePlayerBarSeekButton(seconds: seek.seconds, isForward: seek.isForward, canSeek: self.canSeek)
            }
        case .previousVideo, .nextVideo:
            YouTubePlayerBarVideoSkipButton(isForward: item == .nextVideo)
        case .playPause:
            self.playPauseButton
        case .share:
            YouTubePlayerBarShareButton()
        case .volume:
            self.volumeButton
        case .fullView:
            self.fullViewButton
        case .watchLater:
            self.watchLaterButton
        case .saveToPlaylist:
            YouTubePlayerBarPlaylistMenu()
        case .airPlay:
            self.airPlayButton
        case .captions, .quality, .playbackSpeed, .audioTrack:
            YouTubePlayerBarMenu(item: item)
        case .settingsMenu:
            YouTubeVideoSettingsMenu(items: self.layout.items(in: .settingsMenu))
        case .floatOnTop:
            self.youtubeFloatOnTopButton
        case .pictureInPicture:
            self.pictureInPictureButton
        case .space, .flexibleSpace:
            PlayerBarSpace(isFlexible: item == .flexibleSpace)
        }
    }

    private var channelAvatar: some View {
        YouTubePlayerBarChannelAvatar(
            url: self.youtubePlayer.currentChannel?.thumbnailURL,
            canOpenChannel: self.canNavigateToCurrentChannel,
            onOpenChannel: self.openCurrentChannel
        )
    }

    /// A details block with the lines the user picked for `item`. While a
    /// chapter preview shows, the first line names the chapter and the second
    /// stays empty, as the title block always did.
    private func detailsBlock(for item: YouTubePlayerBarItem) -> some View {
        let lines = self.settings.youtubePlayerBarDetails.lines(for: item) ?? .standard
        if self.isShowingChapterPreview {
            return YouTubePlayerBarDetailsBlock(
                first: .text(self.videoDetailsTitle, identity: self.currentTitleIdentity),
                second: nil
            )
        }
        return YouTubePlayerBarDetailsBlock(
            first: self.detailLine(lines.first),
            second: lines.second.map { self.detailLine($0) }
        )
    }

    private func detailLine(_ field: YouTubePlayerBarDetailField) -> YouTubePlayerBarDetailsBlock.Line {
        switch field {
        case .title:
            return .text(self.videoDetailsTitle, identity: self.currentTitleIdentity)
        case .channel:
            let name = self.youtubePlayer.currentVideo?.channelName
                ?? self.youtubePlayer.currentChannel?.name
                ?? String(localized: "YouTube")
            return .link(name, isEnabled: self.canNavigateToCurrentChannel, action: self.openCurrentChannel)
        case .views:
            return .text(self.youtubePlayer.currentViewCountText ?? "", identity: "views")
        case .date:
            return .text(self.youtubePlayer.currentPublishedText ?? "", identity: "date")
        case .viewsAndDate:
            let text = [self.youtubePlayer.currentViewCountText, self.youtubePlayer.currentPublishedText]
                .compactMap(\.self)
                .joined(separator: " · ")
            return .text(text, identity: "viewsAndDate")
        case .subscribers:
            // Opens the channel too: the count belongs to it.
            let text = self.youtubePlayer.currentChannel?.subscriberCountText ?? ""
            var action: (() -> Void)?
            if self.canNavigateToCurrentChannel {
                action = { self.openCurrentChannel() }
            }
            return .text(text, identity: "subscribers", action: action)
        }
    }

    private var thumbnailView: some View {
        PlayerBarArtworkView(
            width: 57,
            height: 32,
            cornerRadius: 6,
            glowSources: self.currentVideoGlowSources,
            glowIdentity: self.currentVideoGlowIdentity,
            glowTargetSize: CGSize(width: 64, height: 36),
            showsHoverOverlay: false
        ) {
            CachedAsyncImage(
                url: self.youtubePlayer.currentVideo?.thumbnailURL,
                targetSize: CGSize(width: 64, height: 36)
            ) { image in
                image
                    .resizable()
                    .scaledToFill()
            } placeholder: {
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(.quaternary)
                    .overlay {
                        Image(systemName: "play.rectangle")
                            .font(.system(size: 16))
                            .foregroundStyle(.secondary)
                    }
            }
            .frame(width: 57, height: 32)
            .clipShape(.rect(cornerRadius: 6, style: .continuous))
        }
        .accessibilityHidden(self.youtubePlayer.currentVideo == nil)
    }

    private var likeButton: some View {
        PlayerBarIconButton(
            action: {
                Task {
                    await self.youtubePlayer.toggleLike()
                }
            },
            isSelected: self.youtubePlayer.currentRating == .like,
            accessibilityID: AccessibilityID.YouTubeContent.watchLikeButton,
            accessibilityLabel: String(localized: "Like"),
            icon: {
                Image(systemName: self.youtubePlayer.currentRating == .like ? "hand.thumbsup.fill" : "hand.thumbsup")
                    .font(.system(size: 16, weight: .regular))
                    .frame(width: 10, height: 16)
                    .foregroundStyle(self.youtubePlayer.currentRating == .like ? Self.brandAccent : .primary)
                    .contentTransition(.symbolEffect(.replace))
            }
        )
        .symbolEffect(.bounce, value: self.youtubePlayer.currentRating == .like)
        .disabled(self.youtubePlayer.currentVideo == nil)
    }

    private var dislikeButton: some View {
        PlayerBarIconButton(
            action: {
                Task {
                    await self.youtubePlayer.toggleDislike()
                }
            },
            isSelected: self.youtubePlayer.currentRating == .dislike,
            accessibilityID: AccessibilityID.YouTubeContent.watchDislikeButton,
            accessibilityLabel: String(localized: "Dislike"),
            icon: {
                Image(systemName: self.youtubePlayer.currentRating == .dislike ? "hand.thumbsdown.fill" : "hand.thumbsdown")
                    .font(.system(size: 16, weight: .regular))
                    .frame(width: 10, height: 16)
                    .foregroundStyle(self.youtubePlayer.currentRating == .dislike ? Self.brandAccent : .primary)
                    .contentTransition(.symbolEffect(.replace))
            }
        )
        .symbolEffect(.bounce, value: self.youtubePlayer.currentRating == .dislike)
        .disabled(self.youtubePlayer.currentVideo == nil)
    }

    private var currentVideoGlowSources: [URL] {
        guard let video = self.youtubePlayer.currentVideo else { return [] }
        return self.uniqueURLs([
            self.fallbackThumbnailURL(for: video.videoId),
            video.thumbnailURL,
        ])
    }

    private var currentVideoGlowIdentity: String? {
        guard let video = self.youtubePlayer.currentVideo else { return nil }
        return video.videoId
    }

    private func fallbackThumbnailURL(for videoId: String) -> URL? {
        URL(string: "https://i.ytimg.com/vi/\(videoId)/mqdefault.jpg")
    }

    private var currentTitleIdentity: String {
        [
            self.youtubePlayer.currentVideo?.id ?? "none",
            self.youtubePlayer.currentVideo?.title ?? "none",
            self.chapterPreviewMarker?.id ?? "none",
        ].joined(separator: "|")
    }

    private var videoDetailsTitle: String {
        guard let chapterPreviewMarker, let title = chapterPreviewMarker.title else {
            return self.youtubePlayer.currentVideo?.title ?? String(localized: "Not Playing")
        }
        if let subtitle = chapterPreviewMarker.subtitle {
            return "\(subtitle) · \(title)"
        }
        return title
    }

    private var isShowingChapterPreview: Bool {
        self.chapterPreviewMarker?.title != nil
    }

    private var youtubeProgressSection: some View {
        ZStack(alignment: .top) {
            Group {
                if self.youtubePlayer.isShowingAd {
                    PlayerBarAdIndicator()
                } else {
                    YouTubePlayerBarTimelineLane(
                        accent: Self.brandAccent,
                        markers: self.chapterProgressMarkers,
                        segments: self.chapterProgressSegments,
                        isLive: self.isUnseekableLive,
                        canSeek: self.canSeek,
                        onMarkerPreviewChange: { self.chapterPreviewMarker = $0 }
                    )
                }
            }
            .padding(.top, 18)
            // Match the music player's segmented lane layering so chapter tooltips stay above
            // transport controls without intercepting their clicks.
            .zIndex(1)

            self.youtubeTransportControls
                .padding(.top, 2)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    /// The buttons above the timeline, from the layout's center items.
    private var youtubeTransportControls: some View {
        PlayerBarItemRow(items: self.shownItems(in: .center, compact: false), isBlock: YouTubePlayerBarMetrics.isBlock) { item in
            self.itemView(item, compact: false)
        }
    }

    private var playPauseButton: some View {
        PlayerBarIconButton(
            action: {
                HapticService.playback()
                self.youtubePlayer.playPause()
            },
            accessibilityID: AccessibilityID.YouTubeContent.watchPlayPause,
            accessibilityLabel: self.youtubePlayer.isPlaying ? String(localized: "Pause") : String(localized: "Play"),
            icon: {
                Image(systemName: self.youtubePlayer.isPlaying ? "pause.fill" : "play.fill")
                    .font(.system(size: 20, weight: .regular))
                    .frame(width: 12, height: 20)
                    .foregroundStyle(.primary)
                    .contentTransition(.symbolEffect(.replace))
            }
        )
        .compatGlassID("youtubePlayPause", in: self.playerNamespace)
        .disabled(self.youtubePlayer.currentVideo == nil)
    }

    private var volumeButton: some View {
        PlayerBarIconButton(
            action: self.toggleYouTubeVolumeOverlay,
            accessibilityLabel: String(localized: "Volume"),
            accessibilityValue: "\(Int(self.displayedVolume * 100))%",
            icon: {
                Image(systemName: self.volumeIcon)
                    .font(.system(size: 15, weight: .regular))
                    .frame(width: 10, height: 15)
                    .foregroundStyle(.primary)
                    .contentTransition(.symbolEffect(.replace))
            }
        )
        .playerBarVolumeOverlay(isPresented: self.$showsVolumeOverlay) {
            self.youtubeVolumeOverlay
        }
    }

    private var fullViewButton: some View {
        PlayerBarIconButton(
            action: self.openYouTubeFullView,
            accessibilityID: AccessibilityID.YouTubeContent.watchFullView,
            accessibilityLabel: String(localized: "Full view"),
            icon: {
                Image(systemName: "arrow.up.left.and.arrow.down.right")
                    .font(.system(size: 15, weight: .regular))
                    .frame(width: 16, height: 16)
                    .foregroundStyle(.primary)
            }
        )
        .disabled(self.youtubePlayer.currentVideo == nil)
    }

    private var watchLaterButton: some View {
        PlayerBarIconButton(
            action: {
                Task {
                    await self.youtubePlayer.toggleWatchLater()
                }
            },
            isSelected: self.youtubePlayer.isInWatchLater,
            accessibilityID: AccessibilityID.YouTubeContent.watchLaterButton,
            accessibilityLabel: String(localized: "Add to Watch Later"),
            icon: {
                Image(systemName: self.youtubePlayer.isInWatchLater ? "clock.fill" : "clock")
                    .font(.system(size: 15, weight: .regular))
                    .frame(width: 16, height: 16)
                    .foregroundStyle(self.youtubePlayer.isInWatchLater ? Self.brandAccent : .primary)
                    .contentTransition(.symbolEffect(.replace))
            }
        )
        .symbolEffect(.bounce, value: self.youtubePlayer.isInWatchLater)
        .disabled(self.youtubePlayer.currentVideo == nil)
    }

    private var airPlayButton: some View {
        PlayerBarIconButton(
            action: {
                HapticService.toggle()
                self.youtubePlayer.showAirPlayPicker(at: self.airPlayAnchor.screenPoint)
            },
            accessibilityLabel: String(localized: "AirPlay"),
            icon: {
                Image(systemName: "airplayvideo")
                    .font(.system(size: 16, weight: .regular))
                    .frame(width: 10, height: 16)
                    .foregroundStyle(.primary)
            }
        )
        .background {
            AirPlayPickerAnchorView(anchor: self.airPlayAnchor)
                .allowsHitTesting(false)
                .accessibilityHidden(true)
        }
        .disabled(self.youtubePlayer.currentVideo == nil)
    }

    private var pictureInPictureButton: some View {
        PlayerBarIconButton(
            action: self.toggleYouTubePictureInPicture,
            isSelected: self.youtubePlayer.surfaceLocation == .floating,
            accessibilityID: AccessibilityID.YouTubeContent.watchPictureInPicture,
            accessibilityLabel: self.youtubePlayer.surfaceLocation == .floating
                ? String(localized: "Pop video back into Kaset")
                : String(localized: "Picture in Picture")
        ) {
            Image(systemName: self.youtubePlayer.surfaceLocation == .floating ? "pip.exit" : "pip.enter")
                .font(.system(size: 15, weight: .regular))
                .frame(width: 13, height: 14)
                .foregroundStyle(self.youtubePlayer.surfaceLocation == .floating ? Self.brandAccent : .primary)
                .contentTransition(.symbolEffect(.replace))
        }
        .disabled(self.youtubePlayer.currentVideo == nil || self.youtubePlayer.isWindowFullscreen)
    }

    private var youtubeVolumeOverlay: some View {
        CompatGlassContainer(spacing: 0) {
            VStack(spacing: 10) {
                Image(systemName: self.volumeIcon)
                    .font(.system(size: 15, weight: .regular))
                    .frame(width: 16, height: 16)
                    .foregroundStyle(.primary)

                PlayerBarVerticalSlider(
                    value: self.$volumeValue,
                    accent: Self.brandAccent,
                    accessibilityIdentifier: nil,
                    accessibilityLabel: String(localized: "Volume"),
                    onEditingChanged: { editing in
                        self.isAdjustingVolume = editing
                        if !editing {
                            self.youtubePlayer.volume = self.volumeValue
                        }
                    },
                    onValueChanged: { oldValue, newValue in
                        if self.isAdjustingVolume {
                            if (oldValue > 0 && newValue == 0) || (oldValue < 1 && newValue == 1) {
                                HapticService.sliderBoundary()
                            }
                            self.youtubePlayer.volume = newValue
                        }
                    }
                )
            }
            .padding(.horizontal, 6)
            .padding(.vertical, 16)
            .frame(width: 46, height: 168)
            .background {
                Capsule()
                    .fill(self.volumeOverlayFill)
            }
            .compatGlass(interactive: true, tint: self.volumeOverlayTint, in: .capsule)
            .shadow(color: self.volumeOverlayShadow, radius: 14, y: 5)
        }
    }

    private var volumeOverlayFill: Color {
        self.colorScheme == .dark ? .black.opacity(0.22) : .white.opacity(0.72)
    }

    private var volumeOverlayTint: Color {
        self.colorScheme == .dark ? .white.opacity(0.10) : .black.opacity(0.06)
    }

    private var volumeOverlayShadow: Color {
        self.colorScheme == .dark ? .black.opacity(0.36) : .black.opacity(0.18)
    }

    private var currentSeekIdentity: String {
        self.youtubePlayer.currentVideo?.videoId ?? "none"
    }

    private var chapterProgressMarkers: [PlayerBarProgressMarker] {
        guard self.canSeek else { return [] }
        return self.youtubePlayer.chapters.compactMap { chapter in
            guard chapter.startTime > 0, chapter.startTime < self.youtubePlayer.duration else { return nil }
            return PlayerBarProgressMarker(
                id: chapter.id,
                fraction: chapter.startTime / self.youtubePlayer.duration,
                title: chapter.title,
                subtitle: chapter.timeText ?? Self.formatTime(chapter.startTime)
            )
        }
    }

    private var chapterProgressSegments: [PlayerBarProgressSegment] {
        guard self.canSeek else { return [] }
        return Self.chapterProgressSegments(
            chapters: self.youtubePlayer.chapters,
            duration: self.youtubePlayer.duration
        )
    }

    /// Converts YouTube's chapter starts and optional bounds into the same normalized spans used by
    /// the music player's segmented mix seek bar. Marker data remains separate so chapter snapping
    /// and the existing metadata preview continue to work while segment visuals are active.
    static func chapterProgressSegments(
        chapters: [YouTubeChapter],
        duration: TimeInterval
    ) -> [PlayerBarProgressSegment] {
        guard duration.isFinite, duration > 0 else { return [] }

        let sortedChapters = chapters
            .filter { chapter in
                chapter.startTime.isFinite
                    && chapter.startTime >= 0
                    && chapter.startTime < duration
            }
            .sorted { lhs, rhs in
                if lhs.startTime != rhs.startTime {
                    return lhs.startTime < rhs.startTime
                }
                return lhs.title < rhs.title
            }

        var uniqueChapters: [YouTubeChapter] = []
        for chapter in sortedChapters where uniqueChapters.last?.startTime != chapter.startTime {
            uniqueChapters.append(chapter)
        }

        let resolvedChapters: [ChapterProgressSpan] = uniqueChapters.enumerated().compactMap { index, chapter in
            let start = chapter.startTime
            let nextStart = uniqueChapters.indices.contains(index + 1)
                ? uniqueChapters[index + 1].startTime
                : duration
            let upperBound = min(nextStart, duration)
            let explicitEnd = chapter.endTime.flatMap { endTime in
                endTime.isFinite && endTime > start ? endTime : nil
            }
            let end = min(explicitEnd ?? upperBound, upperBound)
            guard end > start else { return nil }
            return ChapterProgressSpan(chapter: chapter, start: start, end: end)
        }

        let count = resolvedChapters.count
        return resolvedChapters.enumerated().map { index, resolved in
            PlayerBarProgressSegment(
                id: resolved.chapter.id,
                start: resolved.start / duration,
                end: resolved.end / duration,
                index: index,
                count: count,
                title: resolved.chapter.title,
                itemLabel: String(localized: "Chapter"),
                rangeText: "\(Self.formatTime(resolved.start)) – \(Self.formatTime(resolved.end))"
            )
        }
    }

    private var isLive: Bool {
        self.youtubePlayer.currentVideo?.isLive == true
    }

    /// A live stream seeks only when the streamer allows rewinding (DVR); the
    /// page then reports its seekable window as the duration.
    private var canSeek: Bool {
        self.youtubePlayer.duration > 0 && !self.youtubePlayer.isShowingAd
            && (!self.isLive || self.youtubePlayer.isLiveSeekable)
    }

    /// A live stream without DVR: nothing to scrub or skip, and the lane
    /// shows LIVE instead of times.
    private var isUnseekableLive: Bool {
        self.isLive && !self.youtubePlayer.isLiveSeekable
    }

    private var canNavigateToCurrentChannel: Bool {
        self.navigationStore != nil && self.currentChannelId != nil
    }

    /// Pushed pages and the detached window sit outside the store's
    /// environment, so fall back to the store of the pages on screen, which
    /// the content view hands the page refresher.
    private var navigationStore: YouTubeViewModelStore? {
        self.youtubeStore ?? YouTubePageRefresh.shared.store
    }

    /// The video's channel, or the channel the watch page loaded for it when
    /// the card it was opened from carried none.
    private var currentChannelId: String? {
        if let channelId = self.youtubePlayer.currentVideo?.channelId, !channelId.isEmpty {
            return channelId
        }
        guard let channelId = self.youtubePlayer.currentChannel?.channelId, !channelId.isEmpty else {
            return nil
        }
        return channelId
    }

    private func openCurrentChannel() {
        guard let channelId = self.currentChannelId else { return }
        self.navigationStore?.navigationPath.append(YouTubeRoute.channel(channelId: channelId))
    }

    private var volumeIcon: String {
        if self.displayedVolume == 0 {
            "speaker.slash.fill"
        } else if self.displayedVolume < 0.5 {
            "speaker.wave.1.fill"
        } else {
            "speaker.wave.2.fill"
        }
    }

    private var displayedVolume: Double {
        self.isAdjustingVolume ? self.volumeValue : self.youtubePlayer.volume
    }

    private func toggleYouTubeVolumeOverlay() {
        HapticService.toggle()
        let isPresented = !self.showsVolumeOverlay
        withAnimation(AppAnimation.quick) {
            self.showsVolumeOverlay = isPresented
        }
    }

    private func openYouTubeFullView() {
        HapticService.toggle()
        if self.youtubePlayer.surfaceLocation == .inline {
            self.youtubePlayer.popOutToWindow()
            Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(250))
                YouTubeVideoWindowController.shared.toggleFullscreen(returnInlineOnExit: true)
            }
        } else {
            YouTubeVideoWindowController.shared.toggleFullscreen()
        }
    }

    private func toggleYouTubePictureInPicture() {
        guard !self.youtubePlayer.isWindowFullscreen else { return }
        HapticService.toggle()
        if self.youtubePlayer.surfaceLocation == .floating {
            self.youtubePlayer.requestPopIn()
        } else {
            self.youtubePlayer.popOutToWindow()
        }
    }
}

extension YouTubePlayerBar {
    static func shouldShowFloatOnTopControl(
        isDetachedWindow: Bool,
        surfaceLocation: YouTubePlayerService.SurfaceLocation,
        isFullscreenOrTransitioning: Bool
    ) -> Bool {
        isDetachedWindow && YouTubeVideoWindowLevelPolicy.canToggleFloatOnTop(
            isFloating: surfaceLocation == .floating,
            isFullscreenOrTransitioning: isFullscreenOrTransitioning
        )
    }
}

private extension YouTubePlayerBar {
    func uniqueURLs(_ urls: [URL?]) -> [URL] {
        var seen = Set<URL>()
        return urls.compactMap { url in
            guard let url, seen.insert(url).inserted else { return nil }
            return url
        }
    }

    static func formatTime(_ seconds: Double) -> String {
        guard seconds.isFinite, seconds >= 0 else { return "0:00" }
        let total = Int(seconds)
        let hours = total / 3600
        let mins = (total % 3600) / 60
        let secs = total % 60
        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, mins, secs)
        }
        return String(format: "%d:%02d", mins, secs)
    }

    var hasPersonalAccount: Bool {
        self.authService.hasPersonalAccount
    }

    var youtubeFloatOnTopButton: some View {
        let help = String(localized: "Keep the video above standard windows on this Space.")

        return PlayerBarIconButton(
            action: self.toggleYouTubeFloatOnTop,
            isSelected: self.settings.keepYouTubeVideoOnTop,
            accessibilityID: AccessibilityID.YouTubeContent.videoWindowFloatOnTop,
            accessibilityLabel: String(localized: "Float on Top"),
            accessibilityValue: self.settings.keepYouTubeVideoOnTop
                ? String(localized: "On")
                : String(localized: "Off")
        ) {
            Image(systemName: self.settings.keepYouTubeVideoOnTop ? "pin.fill" : "pin")
                .font(.system(size: 15, weight: .regular))
                .frame(width: 14, height: 16)
                .foregroundStyle(self.settings.keepYouTubeVideoOnTop ? Self.brandAccent : .primary)
                .contentTransition(.symbolEffect(.replace))
        }
        .accessibilityHint(Text(help))
        .help(help)
    }

    var showsFloatOnTopControl: Bool {
        Self.shouldShowFloatOnTopControl(
            isDetachedWindow: self.isDetachedWindow,
            surfaceLocation: self.youtubePlayer.surfaceLocation,
            isFullscreenOrTransitioning: self.youtubePlayer.isWindowFullscreen
        )
    }

    func toggleYouTubeFloatOnTop() {
        HapticService.toggle()
        self.settings.keepYouTubeVideoOnTop.toggle()
    }
}

// MARK: - AccessibilityID Additions

extension AccessibilityID.YouTubeContent {
    static let watchPlayPause = "youtubeContent.watchPlayPause"
    static let watchLikeButton = "youtubeContent.watchLikeButton"
    static let watchDislikeButton = "youtubeContent.watchDislikeButton"
    static let watchLaterButton = "youtubeContent.watchLaterButton"
    static let watchPictureInPicture = "youtubeContent.watchPictureInPicture"
    static let watchFullView = "youtubeContent.watchFullView"
    static let captionsButton = "youtubeContent.captionsButton"
    static let qualityButton = "youtubeContent.qualityButton"
    static let qualityMenuButton = "youtubeContent.qualityMenuButton"
    static let playbackSpeedButton = "youtubeContent.playbackSpeedButton"
    static let audioTrackButton = "youtubeContent.audioTrackButton"
    static let audioTrackMenu = "youtubeContent.audioTrackMenu"
    static let playbackSpeedMenu = "youtubeContent.playbackSpeedMenu"
}
