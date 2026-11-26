import SwiftUI

// MARK: - ToolbarVolumeButton

/// Volume in the window toolbar: the speaker, with a slider in a popover.
struct ToolbarVolumeButton: View {
    let volume: Double
    let setVolume: (Double) -> Void

    @State private var isPresented = false

    var body: some View {
        PlayerBarIconButton(
            action: { self.isPresented.toggle() },
            accessibilityLabel: String(localized: "Volume"),
            accessibilityValue: "\(Int(self.volume * 100))%",
            icon: {
                Image(systemName: Self.symbol(for: self.volume))
                    .contentTransition(.symbolEffect(.replace))
            }
        )
        .popover(isPresented: self.$isPresented, arrowEdge: .bottom) {
            HStack(spacing: 10) {
                Image(systemName: "speaker.fill")
                    .foregroundStyle(.secondary)
                Slider(
                    value: Binding(get: { self.volume }, set: { self.setVolume($0) }),
                    in: 0 ... 1
                )
                .frame(width: 160)
                .accessibilityLabel(String(localized: "Volume"))
                Image(systemName: "speaker.wave.3.fill")
                    .foregroundStyle(.secondary)
            }
            .padding(14)
        }
    }

    static func symbol(for volume: Double) -> String {
        if volume == 0 {
            "speaker.slash.fill"
        } else if volume < 0.5 {
            "speaker.wave.1.fill"
        } else {
            "speaker.wave.2.fill"
        }
    }
}

// MARK: - ToolbarButton

/// A toolbar button with a symbol that turns the accent color while on.
struct ToolbarButton: View {
    let title: String
    let systemImage: String
    var isSelected = false
    let action: () -> Void

    var body: some View {
        PlayerBarIconButton(action: self.action, isSelected: self.isSelected, accessibilityLabel: self.title) {
            // Untinted unless on, so the toolbar's own colors apply.
            if self.isSelected {
                Image(systemName: self.systemImage)
                    .foregroundStyle(PackageResourceLookup.brandAccent)
            } else {
                Image(systemName: self.systemImage)
            }
        }
    }
}
