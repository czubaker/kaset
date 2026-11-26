import SwiftUI

// MARK: - SleepTimerMenuContent

/// The sleep timer's choices, for the Playback menu and the bar's button.
struct SleepTimerMenuContent: View {
    @Bindable private var timer = SleepTimer.shared

    var body: some View {
        if let status = self.status {
            Text(status)
            Button(String(localized: "Turn Off Sleep Timer")) {
                self.timer.cancel()
            }
            Divider()
        }
        ForEach(SleepTimer.presets, id: \.self) { minutes in
            Toggle(SleepTimer.title(forMinutes: minutes), isOn: self.binding(for: .minutes(minutes)))
        }
        Toggle(self.endOfItemTitle, isOn: self.binding(for: .endOfItem))
    }

    private var status: String? {
        switch self.timer.setting {
        case nil:
            nil
        case .minutes:
            self.timer.remaining.map { String(localized: "Pausing in \(SleepTimer.formatted($0))") }
        case .endOfItem:
            self.endOfItemTitle
        }
    }

    private var endOfItemTitle: String {
        self.timer.nowPlaying?()?.isVideo == true
            ? String(localized: "When the Current Video Ends")
            : String(localized: "When the Current Track Ends")
    }

    private func binding(for setting: SleepTimer.Setting) -> Binding<Bool> {
        Binding(
            get: { self.timer.setting == setting },
            set: { isOn in
                if isOn {
                    self.timer.start(setting)
                } else {
                    self.timer.cancel()
                }
            }
        )
    }
}

// MARK: - SleepTimerBarButton

/// The sleep timer on a player bar or the toolbar: a moon, filled and tinted
/// while it runs, with its choices in a menu.
struct SleepTimerBarButton: View {
    @Bindable private var timer = SleepTimer.shared

    var body: some View {
        PlayerBarIconMenu(
            isSelected: self.timer.isActive,
            accessibilityLabel: String(localized: "Sleep Timer"),
            menuContent: { SleepTimerMenuContent() },
            icon: {
                Image(systemName: self.timer.isActive ? "moon.zzz.fill" : "moon.zzz")
                    .font(.system(size: 15, weight: .regular))
                    .frame(width: 16, height: 16)
                    .foregroundStyle(self.timer.isActive ? PackageResourceLookup.brandAccent : .primary)
                    .contentTransition(.symbolEffect(.replace))
            }
        )
        .help(self.help)
    }

    private var help: String {
        if let remaining = self.timer.remaining {
            return String(localized: "Sleep Timer: pausing in \(SleepTimer.formatted(remaining))")
        }
        return String(localized: "Sleep Timer")
    }
}
