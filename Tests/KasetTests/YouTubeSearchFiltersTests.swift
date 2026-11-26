import Foundation
import Testing
@testable import Kaset

// MARK: - YouTubeSearchFiltersTests

/// Search filters as the search response's filter dialog carries them
/// (captured with api-explorer, November 2026).
@Suite(.serialized, .tags(.parser))
@MainActor
struct YouTubeSearchFiltersTests {
    private static func filter(_ label: String, params: String?, selected: Bool = false) -> [String: Any] {
        var renderer: [String: Any] = ["label": ["simpleText": label]]
        if let params {
            renderer["navigationEndpoint"] = ["searchEndpoint": ["query": "q", "params": params]]
        }
        if selected {
            renderer["status"] = "FILTER_STATUS_SELECTED"
        }
        return ["searchFilterRenderer": renderer]
    }

    private static var response: [String: Any] {
        let groups: [[String: Any]] = [
            ["searchFilterGroupRenderer": ["title": ["simpleText": "Type"], "filters": [Self.filter("Videos", params: "EgIQAQ%3D%3D")]]],
            ["searchFilterGroupRenderer": ["title": ["simpleText": "Upload date"], "filters": [
                Self.filter("Today", params: "EgIIAg%3D%3D"),
                Self.filter("This week", params: "EgIIAw%3D%3D"),
            ]]],
            ["searchFilterGroupRenderer": ["title": ["simpleText": "Prioritize"], "filters": [
                Self.filter("Relevance", params: nil, selected: true),
                Self.filter("Popularity", params: "CAM%3D"),
            ]]],
        ]
        return ["header": ["searchHeaderRenderer": ["searchFilterButton": ["buttonRenderer": ["command": [
            "openPopupAction": ["popup": ["searchFilterOptionsDialogRenderer": ["groups": groups]]],
        ]]]]]]
    }

    @Test("The filter groups come without Type (Kaset's tabs), with decoded params and the one in effect")
    func parsesGroups() {
        let groups = YouTubeSearchParser.filterGroups(in: Self.response)
        #expect(groups.map(\.title) == ["Upload date", "Prioritize"])
        #expect(groups[0].options.map(\.params) == ["EgIIAg==", "EgIIAw=="])
        #expect(groups[1].options.first?.isSelected == true)
        #expect(groups[1].options.first?.params == nil)
        #expect(YouTubeSearchParser.filterGroups(in: [:]).isEmpty)
    }

    @Test("A filter searches again with its params; a new query or another tab drops it")
    func appliesFilters() async throws {
        let client = MockYouTubeClient()
        var response = YouTubeSearchResponse.empty
        response.filterGroups = YouTubeSearchParser.filterGroups(in: Self.response)
        client.searchResponse = response
        let model = YouTubeSearchViewModel(client: client)
        model.query = "swift"
        await model.search()
        let today = try #require(model.filterGroups.first?.options.first)

        model.applySearchFilter(today)
        try await Task.sleep(for: .milliseconds(50))
        #expect(client.lastSearchFilterParams == "EgIIAg==")
        #expect(model.hasSearchFilters)

        // The old tab's options carry its kind, so they go at once.
        model.selectedFilter = .videos
        #expect(model.filterGroups.isEmpty)
        try await Task.sleep(for: .milliseconds(50))
        #expect(!model.hasSearchFilters)
        #expect(client.lastSearchFilterParams == nil)
        #expect(!model.filterGroups.isEmpty)

        model.applySearchFilter(today)
        model.query = "swiftui"
        #expect(!model.hasSearchFilters)
        #expect(model.filterGroups.isEmpty)
    }
}
