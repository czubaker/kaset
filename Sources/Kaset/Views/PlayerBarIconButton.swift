import SwiftUI

// MARK: - PlayerBarIconButton

struct PlayerBarIconButton<Icon: View>: View {
    let action: () -> Void
    var isSelected = false
    var accessibilityID: String?
    var accessibilityLabel: String?
    var accessibilityValue: String?
    @ViewBuilder var icon: () -> Icon

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.playerBarItemStyle) private var style
    @State private var isHovering = false

    var body: some View {
        switch self.style {
        case .bar:
            self.barButton
        case .toolbar:
            // A plain toolbar button: the toolbar draws its own hover and
            // grouping, and names it in Icon and Text.
            Button(action: self.action) {
                Label {
                    Text(self.accessibilityLabel ?? "")
                } icon: {
                    self.icon()
                }
            }
            .help(self.accessibilityLabel ?? "")
            .playerBarAccessibilityIdentifier(self.accessibilityID)
            .playerBarAccessibilityValue(self.accessibilityValue)
            // The bars' icons set their own colors, which the toolbar's
            // disabled look can't dim.
            .opacity(self.isEnabled ? 1 : 0.4)
        }
    }

    private var barButton: some View {
        Button(action: self.action) {
            Label {
                Text(self.accessibilityLabel ?? "")
            } icon: {
                self.icon()
                    .frame(width: PlayerBarIconButtonMetrics.size, height: PlayerBarIconButtonMetrics.size)
                    .background {
                        RoundedRectangle(cornerRadius: PlayerBarIconButtonMetrics.cornerRadius, style: .continuous)
                            .fill(self.backgroundColor)
                    }
                    .contentShape(RoundedRectangle(cornerRadius: PlayerBarIconButtonMetrics.cornerRadius, style: .continuous))
            }
            .labelStyle(.iconOnly)
        }
        .buttonStyle(PlayerBarIconButtonStyle())
        .frame(width: PlayerBarIconButtonMetrics.size, height: PlayerBarIconButtonMetrics.size)
        .contentShape(RoundedRectangle(cornerRadius: PlayerBarIconButtonMetrics.cornerRadius, style: .continuous))
        .playerBarAccessibilityIdentifier(self.accessibilityID)
        .playerBarAccessibilityLabel(self.accessibilityLabel)
        .playerBarAccessibilityValue(self.accessibilityValue)
        .opacity(self.isEnabled ? 1 : 0.38)
        .onHover { hovering in
            withAnimation(AppAnimation.quick) {
                self.isHovering = hovering
            }
        }
    }

    private var backgroundColor: Color {
        let baseColor: Color = self.colorScheme == .dark ? .white : .black
        if self.isHovering, self.isEnabled {
            return baseColor.opacity(PlayerBarIconButtonMetrics.hoverOpacity)
        }
        if self.isSelected {
            return baseColor.opacity(PlayerBarIconButtonMetrics.selectedOpacity)
        }
        return .clear
    }
}

// MARK: - PlayerBarItemStyle

/// How bar buttons draw: on a player bar's glass capsule, or as ordinary
/// buttons of the window toolbar.
enum PlayerBarItemStyle {
    case bar
    case toolbar
}

extension EnvironmentValues {
    @Entry var playerBarItemStyle: PlayerBarItemStyle = .bar
}

// MARK: - PlayerBarIconButtonMetrics

private enum PlayerBarIconButtonMetrics {
    static let size: CGFloat = 28
    static let cornerRadius: CGFloat = 8
    static let hoverOpacity = 0.08
    static let selectedOpacity = 0.06
}

// MARK: - PlayerBarIconButtonStyle

private struct PlayerBarIconButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.92 : 1)
            .opacity(configuration.isPressed ? 0.72 : 1)
            .animation(AppAnimation.quick, value: configuration.isPressed)
    }
}

// MARK: - Accessibility Helpers

private extension View {
    @ViewBuilder
    func playerBarAccessibilityIdentifier(_ identifier: String?) -> some View {
        if let identifier {
            self.accessibilityIdentifier(identifier)
        } else {
            self
        }
    }

    @ViewBuilder
    func playerBarAccessibilityLabel(_ label: String?) -> some View {
        if let label {
            self.accessibilityLabel(label)
        } else {
            self
        }
    }

    @ViewBuilder
    func playerBarAccessibilityValue(_ value: String?) -> some View {
        if let value {
            self.accessibilityValue(value)
        } else {
            self
        }
    }
}
