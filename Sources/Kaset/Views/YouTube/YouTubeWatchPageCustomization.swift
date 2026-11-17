import SwiftUI

// MARK: - YouTubeDetailLinePickers

/// First Line and Second Line pickers for a YouTube details block, as
/// submenus in an item's context menu.
struct YouTubeDetailLinePickers: View {
    let item: YouTubePlayerBarItem

    @Bindable private var settings = SettingsManager.shared

    var body: some View {
        Picker(String(localized: "First Line"), selection: self.firstLine) {
            ForEach(YouTubePlayerBarDetailField.allCases) { field in
                Text(field.title).tag(field)
            }
        }
        .pickerStyle(.menu)

        Picker(String(localized: "Second Line"), selection: self.secondLine) {
            Text("None", comment: "No second line in a player bar details block")
                .tag(YouTubePlayerBarDetailField?.none)
            ForEach(YouTubePlayerBarDetailField.allCases) { field in
                Text(field.title).tag(YouTubePlayerBarDetailField?.some(field))
            }
        }
        .pickerStyle(.menu)
    }

    private var lines: YouTubePlayerBarDetailLines {
        self.settings.youtubePlayerBarDetails.lines(for: self.item) ?? .standard
    }

    private var firstLine: Binding<YouTubePlayerBarDetailField> {
        Binding(
            get: { self.lines.first },
            set: { field in
                var lines = self.lines
                lines.first = field
                self.settings.youtubePlayerBarDetails.setLines(lines, for: self.item)
            }
        )
    }

    private var secondLine: Binding<YouTubePlayerBarDetailField?> {
        Binding(
            get: { self.lines.second },
            set: { field in
                var lines = self.lines
                lines.second = field
                self.settings.youtubePlayerBarDetails.setLines(lines, for: self.item)
            }
        )
    }
}

// MARK: - YouTubeDetailLinesForm

/// The same pickers in a popover, for clicking a details block on the bar
/// preview. The real bar updates as they change.
struct YouTubeDetailLinesForm: View {
    let item: YouTubePlayerBarItem

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(self.item.title)
                .font(.headline)
            Form {
                YouTubeDetailLinePickers(item: self.item)
            }
            .formStyle(.columns)
        }
        .padding(16)
        .frame(width: 280)
    }
}

// MARK: - YouTubeWatchPageCustomizationEditor

/// The Watch Page tab of YouTube's customization sheet: which parts of the
/// page show, and whether the page leaves out what the player bar shows.
struct YouTubeWatchPageCustomizationEditor: View {
    @Bindable private var settings = SettingsManager.shared

    var body: some View {
        HStack(alignment: .top, spacing: 40) {
            VStack(alignment: .leading, spacing: 10) {
                Text("Below the Video", comment: "Watch page customization section")
                    .font(.headline)
                ForEach(YouTubeWatchPageElement.belowVideo) { element in
                    self.toggle(for: element)
                }
            }

            VStack(alignment: .leading, spacing: 10) {
                Text("Beside the Video", comment: "Watch page customization section")
                    .font(.headline)
                self.toggle(for: .related)

                Divider()
                    .padding(.vertical, 6)

                Toggle(isOn: self.$settings.youtubeWatchPage.hidesPlayerBarItems) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Hide What the Player Bar Shows", comment: "Watch page customization option")
                        Text(
                            "For example, the Subscribe button leaves the page once it's on the player bar.",
                            comment: "Explains the watch page option that hides what the player bar shows"
                        )
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            .frame(maxWidth: 380, alignment: .leading)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 8)
    }

    private func toggle(for element: YouTubeWatchPageElement) -> some View {
        Toggle(isOn: self.isShown(element)) {
            HStack(spacing: 6) {
                Text(element.title)
                if self.isOnPlayerBar(element) {
                    Text("On the player bar", comment: "Marks a watch page element the player bar shows instead")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    /// Whether the page leaves `element` out because the player bar shows it.
    private func isOnPlayerBar(_ element: YouTubeWatchPageElement) -> Bool {
        self.settings.youtubeWatchPage.hidesPlayerBarItems
            && YouTubeWatchPageLayout.playerBarShows(
                element,
                playerBar: self.settings.youtubePlayerBar,
                details: self.settings.youtubePlayerBarDetails
            )
    }

    private func isShown(_ element: YouTubeWatchPageElement) -> Binding<Bool> {
        Binding(
            get: { !self.settings.youtubeWatchPage.hiddenElements.contains(element) },
            set: { isShown in
                if isShown {
                    self.settings.youtubeWatchPage.hiddenElements.remove(element)
                } else {
                    self.settings.youtubeWatchPage.hiddenElements.insert(element)
                }
            }
        )
    }
}
