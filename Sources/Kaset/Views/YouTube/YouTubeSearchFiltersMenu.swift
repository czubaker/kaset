import SwiftUI

// MARK: - YouTubeSearchFiltersMenu

/// YouTube's search filters beside the result-kind tabs: Upload date,
/// Duration, Features, and sorting, each option YouTube's own, with the ones
/// in effect checked, and a way back to no filters.
struct YouTubeSearchFiltersMenu: View {
    let viewModel: YouTubeSearchViewModel

    var body: some View {
        Menu {
            ForEach(self.viewModel.filterGroups) { group in
                Section(group.title) {
                    ForEach(group.options) { option in
                        Button {
                            self.viewModel.applySearchFilter(option)
                        } label: {
                            if option.isSelected {
                                Label(option.label, systemImage: "checkmark")
                            } else {
                                Text(option.label)
                            }
                        }
                        .disabled(option.params == nil)
                    }
                }
            }
            if self.viewModel.hasSearchFilters {
                Divider()
                Button(String(localized: "Clear Filters")) {
                    self.viewModel.clearSearchFilters()
                }
            }
        } label: {
            Label(
                String(localized: "Filters"),
                systemImage: self.viewModel.hasSearchFilters
                    ? "line.3.horizontal.decrease.circle.fill"
                    : "line.3.horizontal.decrease.circle"
            )
        }
        .menuStyle(.button)
        .fixedSize()
        .help(String(localized: "Filters"))
    }
}
