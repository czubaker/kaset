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

    @Bindable private var settings = SettingsManager.shared

    /// Remembered across launches, like a Finder sidebar section.
    @AppStorage("youtubeSidebar.playlistsExpanded") private var isPlaylistsExpanded = false

    /// Rows drag to a new place only while ⌘ is held, so a plain click or a
    /// stray drag never reorders the sidebar.
    @State private var isCommandHeld = NSEvent.modifierFlags.contains(.command)
    @State private var modifierMonitor: Any?
    /// The row a dragged item would land before, for the insertion line.
    @State private var dropTarget: YouTubeNavigationItem?

    var body: some View {
        // The footer sits below the list rather than over it, so a long list
        // (expanded playlists) doesn't show through the profile and toggle.
        VStack(spacing: 0) {
            List {
                Section {
                    self.rows(in: .main)
                }

                Section(String(localized: "Discover")) {
                    self.rows(in: .discover)
                }

                if self.hasPersonalAccount {
                    Section(String(localized: "Collection")) {
                        self.rows(in: .collection)
                    }
                }
            }
            .listStyle(.sidebar)
            .accessibilityIdentifier(AccessibilityID.YouTubeSidebar.container)

            SidebarFooterView()
        }
        .compatTranslucentSidebar()
        .navigationSplitViewColumnWidth(min: SidebarLayout.minimumWidth, ideal: 220, max: 300)
        .onAppear(perform: self.startWatchingModifiers)
        .onDisappear(perform: self.stopWatchingModifiers)
        // A ⌘ released while another app is in front never reaches the
        // monitor; read the keys again whenever the app comes back.
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            self.isCommandHeld = NSEvent.modifierFlags.contains(.command)
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didResignActiveNotification)) { _ in
            self.isCommandHeld = false
        }
    }

    private var hasPersonalAccount: Bool {
        self.authService.hasPersonalAccount
    }

    // MARK: Rows

    /// A section's items in the user's order; Subscriptions needs an account.
    /// An expanded Playlists brings its playlists as rows right below it.
    private func rows(in section: YouTubeSidebarSection) -> some View {
        let items = self.settings.youtubeSidebarOrder.items(in: section).filter { item in
            item != .subscriptions || self.hasPersonalAccount
        }
        return ForEach(items) { item in
            self.row(for: item, accessory: item == .playlists ? AnyView(self.playlistsChevron) : nil)
                .modifier(SidebarReorderModifier(
                    item: item,
                    section: section,
                    isDragEnabled: self.isCommandHeld,
                    dropTarget: self.$dropTarget,
                    order: self.$settings.youtubeSidebarOrder
                ))
                .task(id: PlaylistsLoadKey(
                    isExpanded: item == .playlists && self.isPlaylistsExpanded,
                    model: self.playlists.map(ObjectIdentifier.init)
                )) {
                    // Loads when first expanded, and again for the fresh model
                    // an account switch brings; cached otherwise.
                    guard item == .playlists, self.isPlaylistsExpanded else { return }
                    await self.playlists?.load()
                }

            if item == .playlists, self.isPlaylistsExpanded {
                ForEach(self.sidebarPlaylists) { playlist in
                    let child = YouTubeNavigationItem.playlist(id: playlist.playlistId)
                    KasetSidebarRow(
                        title: playlist.title,
                        systemImage: child.icon,
                        isSelected: self.selection == child,
                        indent: 14,
                        accessibilityIdentifier: AccessibilityID.YouTubeSidebar.item(for: child)
                    ) {
                        self.select(child)
                    }
                }
            }
        }
    }

    /// The chevron at Playlists' trailing edge lists the user's playlists
    /// right in the sidebar; the row itself opens the Playlists page, and its
    /// icon and title line up with the other rows.
    private var playlistsChevron: some View {
        Button {
            withAnimation(AppAnimation.quick) {
                self.isPlaylistsExpanded.toggle()
            }
        } label: {
            Image(systemName: "chevron.right")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.secondary)
                .rotationEffect(.degrees(self.isPlaylistsExpanded ? 90 : 0))
                .frame(width: 20, height: 20)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(
            self.isPlaylistsExpanded ? String(localized: "Hide Playlists") : String(localized: "Show Playlists")
        )
        .accessibilityIdentifier(AccessibilityID.YouTubeSidebar.playlistsDisclosure)
    }

    /// The user's own playlists. Liked Videos and Watch Later have rows of
    /// their own above.
    private var sidebarPlaylists: [YouTubePlaylist] {
        (self.playlists?.playlists ?? []).filter { $0.playlistId != "LL" && $0.playlistId != "WL" }
    }

    private func row(for item: YouTubeNavigationItem, accessory: AnyView? = nil) -> some View {
        KasetSidebarRow(
            title: item.displayName,
            systemImage: item.icon,
            isSelected: self.selection == item,
            accessory: accessory,
            accessibilityIdentifier: AccessibilityID.YouTubeSidebar.item(for: item)
        ) {
            self.select(item)
        }
    }

    // MARK: ⌘ Tracking

    private func startWatchingModifiers() {
        guard self.modifierMonitor == nil else { return }
        self.isCommandHeld = NSEvent.modifierFlags.contains(.command)
        self.modifierMonitor = NSEvent.addLocalMonitorForEvents(matching: .flagsChanged) { event in
            let isHeld = event.modifierFlags.contains(.command)
            if isHeld != self.isCommandHeld {
                self.isCommandHeld = isHeld
            }
            return event
        }
    }

    private func stopWatchingModifiers() {
        if let modifierMonitor {
            NSEvent.removeMonitor(modifierMonitor)
        }
        self.modifierMonitor = nil
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

// MARK: - PlaylistsLoadKey

/// What the Playlists rows' load depends on: being expanded, and which
/// playlists model the store holds (a new one after an account switch).
private struct PlaylistsLoadKey: Hashable {
    let isExpanded: Bool
    let model: ObjectIdentifier?
}

// MARK: - SidebarReorderModifier

/// Drags a sidebar row to a new place within its section while ⌘ is held,
/// as menu bar items move. A row takes drops from its own section: before it
/// on its top half, after it on its bottom half.
private struct SidebarReorderModifier: ViewModifier {
    let item: YouTubeNavigationItem
    let section: YouTubeSidebarSection
    let isDragEnabled: Bool
    @Binding var dropTarget: YouTubeNavigationItem?
    @Binding var order: YouTubeSidebarOrder

    /// A sidebar row is about 30pt tall; below this a drop lands after it.
    private static let rowMidline: CGFloat = 15

    func body(content: Content) -> some View {
        Group {
            if self.isDragEnabled {
                content.draggable(self.item.id) {
                    Label(self.item.displayName, systemImage: self.item.icon)
                        .padding(6)
                }
            } else {
                content
            }
        }
        .overlay(alignment: .top) {
            if self.dropTarget == self.item {
                Capsule()
                    .fill(PackageResourceLookup.brandAccent)
                    .frame(height: 2)
                    .padding(.horizontal, 10)
                    .offset(y: -1)
                    .allowsHitTesting(false)
            }
        }
        .dropDestination(for: String.self) { ids, location in
            self.dropTarget = nil
            guard let id = ids.first,
                  let dragged = self.section.standardItems.first(where: { $0.id == id })
            else { return false }
            let target = location.y > Self.rowMidline ? self.item(after: self.item) : self.item
            withAnimation(AppAnimation.quick) {
                _ = self.order.move(dragged, before: target, in: self.section)
            }
            return true
        } isTargeted: { isTargeted in
            if isTargeted {
                self.dropTarget = self.item
            } else if self.dropTarget == self.item {
                self.dropTarget = nil
            }
        }
    }

    /// The item after `item` in the section's order, or nil at the end.
    private func item(after item: YouTubeNavigationItem) -> YouTubeNavigationItem? {
        let items = self.order.items(in: self.section)
        guard let index = items.firstIndex(of: item), index + 1 < items.count else { return nil }
        return items[index + 1]
    }
}

// MARK: - AccessibilityID.YouTubeSidebar

extension AccessibilityID {
    enum YouTubeSidebar {
        static let container = "youtubeSidebar"
        static let playlistsDisclosure = "youtubeSidebar.Playlists.disclosure"

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
