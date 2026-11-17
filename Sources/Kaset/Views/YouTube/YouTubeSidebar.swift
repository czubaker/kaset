import SwiftUI

// MARK: - YouTubeSidebar

/// Sidebar navigation for the YouTube (video) experience.
///
/// Mirrors the music `Sidebar` structure so toggling sources feels native:
/// main items on top, a Discover section, and a Collection section, with the
/// shared footer (source toggle + profile) at the bottom.
struct YouTubeSidebar: View {
    @Binding var selection: YouTubeNavigationItem?
    /// The user's playlists, listed under Playlists when it's expanded.
    var playlists: YouTubePlaylistsViewModel?
    var onReselect: ((YouTubeNavigationItem) -> Void)?
    @Environment(AuthService.self) private var authService

    /// Remembered across launches, like a Finder sidebar section.
    @AppStorage("youtubeSidebar.playlistsExpanded") private var isPlaylistsExpanded = false

    var body: some View {
        // The footer sits below the list rather than over it, so a long list
        // (expanded playlists) doesn't show through the profile and toggle.
        VStack(spacing: 0) {
            List {
                // Main navigation
                Section {
                    self.row(for: .search)
                    self.row(for: .home)
                    if self.hasPersonalAccount {
                        self.row(for: .subscriptions)
                    }
                }

                // Discover section
                Section(String(localized: "Discover")) {
                    self.row(for: .explore)
                    self.row(for: .shorts)
                }

                if self.hasPersonalAccount {
                    // Collection section
                    Section(String(localized: "Collection")) {
                        self.row(for: .likedVideos)
                        self.row(for: .watchLater)
                        self.row(for: .history)
                        self.playlistsRow
                    }
                }
            }
            .listStyle(.sidebar)
            .accessibilityIdentifier(AccessibilityID.YouTubeSidebar.container)

            SidebarFooterView()
        }
        .compatTranslucentSidebar()
        .navigationSplitViewColumnWidth(min: 200, ideal: 220, max: 300)
    }

    private var hasPersonalAccount: Bool {
        self.authService.hasPersonalAccount
    }

    /// Playlists, with a disclosure triangle that lists the user's playlists
    /// right in the sidebar. The row itself still opens the Playlists page.
    private var playlistsRow: some View {
        DisclosureGroup(isExpanded: self.$isPlaylistsExpanded) {
            ForEach(self.sidebarPlaylists) { playlist in
                KasetSidebarRow(
                    title: playlist.title,
                    systemImage: YouTubeNavigationItem.playlist(id: playlist.playlistId).icon,
                    isSelected: self.selection == .playlist(id: playlist.playlistId)
                ) {
                    self.select(.playlist(id: playlist.playlistId))
                }
                .accessibilityIdentifier(AccessibilityID.YouTubeSidebar.item(for: .playlist(id: playlist.playlistId)))
            }
        } label: {
            self.row(for: .playlists)
        }
        // Loads once, when first expanded; the list is cached after that.
        .task(id: self.isPlaylistsExpanded) {
            guard self.isPlaylistsExpanded else { return }
            await self.playlists?.load()
        }
    }

    /// The user's own playlists. Liked Videos and Watch Later have rows of
    /// their own above.
    private var sidebarPlaylists: [YouTubePlaylist] {
        (self.playlists?.playlists ?? []).filter { $0.playlistId != "LL" && $0.playlistId != "WL" }
    }

    private func row(for item: YouTubeNavigationItem) -> some View {
        KasetSidebarRow(
            title: item.displayName,
            systemImage: item.icon,
            isSelected: self.selection == item
        ) {
            self.select(item)
        }
        .accessibilityIdentifier(AccessibilityID.YouTubeSidebar.item(for: item))
    }

    private func select(_ item: YouTubeNavigationItem) {
        if self.selection == item {
            self.onReselect?(item)
            HapticService.navigation()
            return
        }
        self.selection = item
        HapticService.navigation()
    }
}

// MARK: - AccessibilityID.YouTubeSidebar

extension AccessibilityID {
    enum YouTubeSidebar {
        static let container = "youtubeSidebar"

        static func item(for item: YouTubeNavigationItem) -> String {
            "youtubeSidebar.\(item.id)"
        }
    }
}

#Preview {
    YouTubeSidebar(selection: .constant(.home))
        .frame(width: 220)
        .environment(AuthService())
}
