# ADR-0048: Video summaries with Apple Intelligence

## Status

Accepted

## Context

Users wanted the video summary KasetPlus (github.com/Yoddikko/kasetPlus, MIT)
has: Apple Intelligence's on-device model summarizing a YouTube video. KasetPlus
reads the captions with yt-dlp, a dependency Kaset doesn't ship, and summarizes
only the first 9,000 characters.

## Decision

- **Captions from the API client.** `YouTubeClient.getTranscriptTracks(videoId:)`
  reads `captions.playerCaptionsTracklistRenderer.captionTracks` from the
  `player` endpoint, and `getTranscript(_:)` fetches the chosen track's
  timed-text URL as `fmt=json3`. Only `https://*.youtube.com/api/timedtext`
  URLs are fetched. Verified with api-explorer, November 2026; `get_transcript`
  answered 400 ("Precondition check failed"), so it isn't used.
- **Which track.** Written captions in one of the user's languages, then
  written English, then the speech-recognition track, then whatever there is.
- **Long videos.** The on-device context holds 4,096 tokens. A transcript is
  cut into parts of at most about 1,500 estimated tokens (one per Chinese,
  Japanese, or Korean character, two characters per token in other non-Latin
  scripts, four in Latin ones), at word boundaries where there are any; more
  than eight parts are sampled evenly from start to end. Each part is
  boiled down to notes, and the summary (an overview and three to six key
  points) is written from the notes, streamed as it comes.
- **On request only.** The watch page shows a Summary card under the
  description while Apple Intelligence is on and supports the app's language,
  except for streams that are live. Nothing is fetched or generated until the
  user clicks Summarize; leaving the page cancels it. The card is a watch page
  element, so Customize Watch Page can hide it.

## Consequences

- No new dependency, and nothing leaves the Mac beyond the two YouTube requests.
- If YouTube starts requiring a token on timed-text URLs, the response body is
  empty and the card says the video has no captions to summarize.
- A long video takes one model call per part plus one for the summary.
