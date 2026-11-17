import SwiftUI

// MARK: - YouTubeCaptionsPicker

// Menus of the YouTube player bar. Captions, quality, playback speed, and
// audio track each work as a button of their own or inside the video
// settings (gear) menu, wherever the customized layout puts them.

/// Captions: Off plus each caption track. An inline picker gives the active
/// row the menu's own checkmark; a Label's icon isn't drawn in macOS 26 menus.
private struct YouTubeCaptionsPicker: View {
    @Environment(YouTubePlayerService.self) private var player
    let style: YouTubePlayerBarMenuPickerStyle

    var body: some View {
        let picker = Picker(String(localized: "Closed captions"), selection: self.selection) {
            Text("Off", comment: "Captions off menu item")
                .tag(String?.none)
            ForEach(self.player.captionTracks) { track in
                Text(track.displayName)
                    .tag(String?.some(track.languageCode))
            }
        }
        switch self.style {
        case .inline:
            picker.pickerStyle(.inline).labelsHidden()
        case .submenu:
            picker.pickerStyle(.menu)
        }
    }

    /// The active caption track; `nil` is Off.
    private var selection: Binding<String?> {
        Binding(
            get: { self.player.activeCaptionLanguageCode },
            set: { self.player.selectCaptionTrack(languageCode: $0) }
        )
    }
}

// MARK: - YouTubeQualityPicker

/// Quality levels, with Auto selected while none is pinned.
private struct YouTubeQualityPicker: View {
    @Environment(YouTubePlayerService.self) private var player

    var body: some View {
        Picker(String(localized: "Video quality"), selection: self.selection) {
            ForEach(self.player.qualityLevels, id: \.self) { level in
                Text(YouTubeQuality.displayName(for: level))
                    .tag(level)
            }
        }
        .pickerStyle(.inline)
        .labelsHidden()
    }

    private var selection: Binding<String> {
        Binding(
            get: { self.player.userPinnedQuality ?? "auto" },
            set: { self.player.selectQuality($0) }
        )
    }
}

// MARK: - YouTubePlaybackSpeedPicker

private struct YouTubePlaybackSpeedPicker: View {
    @Environment(YouTubePlayerService.self) private var player
    let style: YouTubePlayerBarMenuPickerStyle

    var body: some View {
        let picker = Picker(String(localized: "Playback speed"), selection: self.selection) {
            ForEach(self.player.playbackRateOptions, id: \.self) { rate in
                Text(YouTubePlaybackRate.displayName(for: rate)).tag(rate)
            }
        }
        .accessibilityIdentifier(AccessibilityID.YouTubeContent.playbackSpeedMenu)
        switch self.style {
        case .inline:
            picker.pickerStyle(.inline).labelsHidden()
        case .submenu:
            picker.pickerStyle(.menu)
        }
    }

    private var selection: Binding<Double> {
        Binding(
            get: { self.player.playbackRate },
            set: { self.player.selectPlaybackRate($0) }
        )
    }
}

// MARK: - YouTubeAudioTrackPicker

private struct YouTubeAudioTrackPicker: View {
    @Environment(YouTubePlayerService.self) private var player
    let style: YouTubePlayerBarMenuPickerStyle

    var body: some View {
        let picker = Picker(String(localized: "Audio track"), selection: self.selection) {
            ForEach(self.player.audioTracks) { track in
                Text(track.displayName).tag(track.id)
            }
        }
        .accessibilityIdentifier(AccessibilityID.YouTubeContent.audioTrackMenu)
        switch self.style {
        case .inline:
            picker.pickerStyle(.inline).labelsHidden()
        case .submenu:
            picker.pickerStyle(.menu)
        }
    }

    private var selection: Binding<String> {
        Binding(
            get: { self.player.activeAudioTrackID ?? "" },
            set: { self.player.selectAudioTrack(id: $0) }
        )
    }
}

// MARK: - YouTubePlayerBarMenuPickerStyle

/// How a picker shows in its menu: its options right in the menu, or as a
/// submenu named after it.
private enum YouTubePlayerBarMenuPickerStyle {
    case inline
    case submenu
}

// MARK: - YouTubePlayerBarMenu

/// A player bar button that opens one of the pickers above.
struct YouTubePlayerBarMenu: View {
    let item: YouTubePlayerBarItem

    @Environment(YouTubePlayerService.self) private var player

    private static let brandAccent = PackageResourceLookup.brandAccent

    var body: some View {
        PlayerBarIconMenu(
            isSelected: self.isSelected,
            accessibilityID: self.accessibilityID,
            accessibilityLabel: self.item.title
        ) {
            switch self.item {
            case .captions:
                YouTubeCaptionsPicker(style: .inline)
            case .quality:
                YouTubeQualityPicker()
            case .playbackSpeed:
                YouTubePlaybackSpeedPicker(style: .inline)
            case .audioTrack:
                YouTubeAudioTrackPicker(style: .inline)
            default:
                EmptyView()
            }
        } icon: {
            Image(systemName: self.iconName)
                .font(.system(size: 16, weight: .regular))
                .frame(width: 16, height: 16)
                .foregroundStyle(self.isSelected ? AnyShapeStyle(Self.brandAccent) : AnyShapeStyle(.primary))
        }
        .disabled(self.player.currentVideo == nil)
    }

    /// Whether the button shows: an audio track button only for a video with
    /// a choice of tracks, a quality button only once levels are known.
    static func isShown(_ item: YouTubePlayerBarItem, player: YouTubePlayerService) -> Bool {
        switch item {
        case .audioTrack: player.audioTracks.count > 1
        case .quality: !player.qualityLevels.isEmpty
        default: true
        }
    }

    private var isSelected: Bool {
        switch self.item {
        case .captions: self.player.activeCaptionLanguageCode != nil
        case .quality: self.player.userPinnedQuality != nil
        case .playbackSpeed: self.player.playbackRate != 1
        default: false
        }
    }

    private var iconName: String {
        switch self.item {
        case .captions: self.isSelected ? "captions.bubble.fill" : "captions.bubble"
        default: self.item.systemImage
        }
    }

    private var accessibilityID: String {
        switch self.item {
        case .captions: AccessibilityID.YouTubeContent.captionsButton
        case .quality: AccessibilityID.YouTubeContent.qualityMenuButton
        case .playbackSpeed: AccessibilityID.YouTubeContent.playbackSpeedButton
        case .audioTrack: AccessibilityID.YouTubeContent.audioTrackButton
        default: ""
        }
    }
}

// MARK: - YouTubeVideoSettingsMenu

/// The gear menu, in the spirit of YouTube's own: Customize Player Bar…
/// first (always there, so the bar can be set up from the bar itself), then
/// the layout's settings menu items as submenus and the quality levels right
/// in the menu.
struct YouTubeVideoSettingsMenu: View {
    let items: [YouTubePlayerBarItem]

    @Environment(YouTubePlayerService.self) private var player

    private static let brandAccent = PackageResourceLookup.brandAccent

    var body: some View {
        PlayerBarIconMenu(
            isSelected: self.isSelected,
            accessibilityID: AccessibilityID.YouTubeContent.qualityButton,
            accessibilityLabel: String(localized: "Video settings")
        ) {
            Button {
                PlayerBarCustomization.shared.present(for: .video)
            } label: {
                Label(String(localized: "Customize Player Bar…"), systemImage: "slider.horizontal.3")
            }

            if !self.shownItems.isEmpty {
                Divider()
            }

            // The pickers need a video; Customize Player Bar… doesn't.
            Group {
                ForEach(self.shownItems, id: \.self) { item in
                    switch item {
                    case .captions:
                        YouTubeCaptionsPicker(style: .submenu)
                    case .audioTrack:
                        YouTubeAudioTrackPicker(style: .submenu)
                    case .playbackSpeed:
                        YouTubePlaybackSpeedPicker(style: .submenu)
                    case .quality:
                        Section(String(localized: "Video quality")) {
                            YouTubeQualityPicker()
                        }
                    default:
                        EmptyView()
                    }
                }
            }
            .disabled(self.player.currentVideo == nil)
        } icon: {
            Image(systemName: "gearshape")
                .font(.system(size: 16, weight: .regular))
                .frame(width: 16, height: 16)
                .foregroundStyle(self.isSelected ? AnyShapeStyle(Self.brandAccent) : AnyShapeStyle(.primary))
        }
    }

    private var shownItems: [YouTubePlayerBarItem] {
        self.items.filter { YouTubePlayerBarMenu.isShown($0, player: self.player) }
    }

    /// Accented while a non-default speed is set from inside it.
    private var isSelected: Bool {
        self.items.contains(.playbackSpeed) && self.player.playbackRate != 1
    }
}

// MARK: - YouTubePlayerBarPlaylistMenu

/// Save to Playlist for the video playing: the user's playlists, checked
/// where it already is; picking one adds it there or takes it off.
struct YouTubePlayerBarPlaylistMenu: View {
    @Environment(YouTubePlayerService.self) private var player

    @State private var membership = YouTubePlaylistMembership()

    var body: some View {
        PlayerBarIconMenu(
            isSelected: false,
            accessibilityID: AccessibilityID.YouTubeContent.saveToPlaylistButton,
            accessibilityLabel: String(localized: "Save to Playlist")
        ) {
            if let video = self.player.currentVideo {
                YouTubePlaylistMembershipItems(video: video, membership: self.membership)
            }
        } icon: {
            Image(systemName: "text.badge.plus")
                .font(.system(size: 16, weight: .regular))
                .frame(width: 16, height: 16)
                .foregroundStyle(.primary)
        }
        .disabled(self.player.currentVideo == nil)
        // Loaded as each video starts, so the menu opens with its checkmarks:
        // a menu doesn't redraw once it's open.
        .task(id: self.player.currentVideo?.videoId) {
            guard let video = self.player.currentVideo else { return }
            await self.membership.load(for: video)
        }
    }
}

extension AccessibilityID.YouTubeContent {
    static let saveToPlaylistButton = "youtubeContent.saveToPlaylistButton"
}
