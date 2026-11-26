import SwiftUI

/// Settings for the regular YouTube video experience (distinct from the Music
/// experience): playback, the video window, the watch page, and the layout of
/// the toolbar and player bar.
struct YouTubeSettingsView: View {
    @State private var settings = SettingsManager.shared

    var body: some View {
        Form {
            Section {
                Toggle(String(localized: "Autoplay"), isOn: self.$settings.youtubeAutoplayEnabled)
                    .help(String(localized: "When a video ends, count down and play the next related video."))
            } header: {
                Text(String(localized: "Playback"))
            } footer: {
                Text(String(localized: "Videos you queue with Play Next or Add to Queue play first, with or without Autoplay."))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section {
                Toggle(String(localized: "Float on Top"), isOn: self.$settings.keepYouTubeVideoOnTop)
                    .help(String(localized: "Keep the video above standard windows on this Space."))

                Toggle(String(localized: "Pop Out Video When Navigating Away"), isOn: self.$settings.popOutVideoOnNavigateAway)
                    .help(String(localized: "Keep a playing video in a floating window when you leave the page. When off, the video stops instead."))
            } header: {
                Text(String(localized: "Video Window"))
            } footer: {
                Text(String(localized: "When off, navigating back from a playing video stops it instead of opening the floating player. The pop-out and full-view buttons still work."))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section {
                Toggle(String(localized: "Show Controls on Video"), isOn: self.$settings.showYouTubeControlsOnVideo)
                    .help(String(localized: "Controls appear when you move the pointer over the video and fade out while it plays."))

                Toggle(String(localized: "Find Lyrics Automatically"), isOn: self.$settings.youtubeLyricsAutoFind)
                    .help(String(localized: "Look up lyrics on LRCLib for every video you open."))

                Button(String(localized: "Customize Watch Page…")) {
                    PlayerBarCustomization.shared.presentWatchPage()
                }
            } header: {
                Text(String(localized: "Watch Page"))
            } footer: {
                Text(String(localized: "Lyrics come from LRCLib, a public lyrics site, which gets each video’s title when Kaset looks its song up."))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section {
                Toggle(String(localized: "Ambient Color Backdrop"), isOn: self.$settings.ambientBackdropEnabled)
                    .help(String(localized: "Show a soft color glow, drawn from the video, behind the player"))

                if self.settings.ambientBackdropEnabled {
                    Picker(String(localized: "Style"), selection: self.$settings.ambientBackdropStyle) {
                        ForEach(AmbientBackdropStyle.userSelectableCases) { style in
                            Text(style.displayName).tag(style)
                        }
                    }
                    .help(String(localized: "\"Live\" shifts the colors as the video plays; the others stay constant"))
                }
            } header: {
                Text(String(localized: "Ambient Backdrop"))
            } footer: {
                Text(String(localized: "A soft color glow drawn from the video plays behind the player. Applies to YouTube videos, not Music."))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section {
                Button(String(localized: "Customize Toolbar and Player Bar…")) {
                    PlayerBarCustomization.shared.present(for: .video)
                }
            } header: {
                Text(String(localized: "Toolbar and Player Bar"))
            }
        }
        .formStyle(.grouped)
    }
}
