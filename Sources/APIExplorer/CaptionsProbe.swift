import Foundation

// MARK: - Captions probe

/// `captions <videoId>`: lists the video's caption tracks from the `player`
/// endpoint and reads the first written English track (or the first track)
/// as `fmt=json3`, the way Kaset's video summary does. Track URLs carry the
/// caller's IP address, so they are never printed.
func exploreCaptions(videoId: String) async {
    print("🎬 Caption tracks for \(videoId)")
    do {
        let (data, statusCode) = try await makeRequest(
            endpoint: "player",
            body: ["videoId": videoId],
            authenticated: actionNeedsAuthentication("player")
        )
        print("   player: HTTP \(statusCode)")
        let captions = data["captions"] as? [String: Any]
        let renderer = captions?["playerCaptionsTracklistRenderer"] as? [String: Any]
        let tracks = renderer?["captionTracks"] as? [[String: Any]] ?? []
        guard !tracks.isEmpty else {
            print("   No caption tracks")
            return
        }
        for track in tracks {
            let code = track["languageCode"] as? String ?? "?"
            let kind = track["kind"] as? String == "asr" ? "speech recognition" : "written"
            print("   • \(code) (\(kind))")
        }

        let chosen = tracks.first { $0["languageCode"] as? String == "en" && $0["kind"] == nil } ?? tracks[0]
        guard let base = chosen["baseUrl"] as? String,
              var components = URLComponents(string: base),
              components.host?.hasSuffix("youtube.com") == true
        else {
            print("   ❌ The track has no YouTube timed-text URL")
            return
        }
        components.queryItems = (components.queryItems ?? []).filter { $0.name != "fmt" }
            + [URLQueryItem(name: "fmt", value: "json3")]
        guard let url = components.url else { return }

        let (body, response) = try await URLSession.shared.data(from: url)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        print("   timedtext (\(chosen["languageCode"] as? String ?? "?")): HTTP \(status), \(body.count) bytes")
        guard !body.isEmpty,
              let json = try JSONSerialization.jsonObject(with: body) as? [String: Any]
        else {
            print("   ⚠️ Empty or non-JSON body: the track may need a token")
            return
        }
        let events = json["events"] as? [[String: Any]] ?? []
        let text = events
            .map { event in
                (event["segs"] as? [[String: Any]] ?? []).compactMap { $0["utf8"] as? String }.joined()
            }
            .joined(separator: " ")
            .split(whereSeparator: \.isWhitespace)
            .joined(separator: " ")
        print("   \(events.count) events, \(text.count) characters")
        print("   \"\(text.prefix(160))\"")
    } catch {
        print("❌ Error: \(error.localizedDescription)")
    }
}
