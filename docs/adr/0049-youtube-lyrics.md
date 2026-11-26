# ADR-0049: Lyrics beside YouTube music videos

## Status

Accepted

## Context

Users wanted lyrics for music videos on YouTube, as KasetPlus
(github.com/Yoddikko/kasetPlus, MIT) shows them from LRCLib. Kaset already
reads LRCLib for YouTube Music (`LRCLibProvider`), but a YouTube video has a
free-form title instead of a song and an artist, and most videos aren't songs.

## Decision

- **What to search by.** `YouTubeLyricsQuery` takes artist and song from
  "Artist - Song" titles, drops brackets that describe the upload ("Official
  Video", "4K Remastered", "Lyrics"), "| …" tails, quotes, and featured
  artists, and otherwise takes the artist from the channel ("Artist - Topic",
  "ArtistVEVO").
- **What counts.** `YouTubeLyricsLookup` searches LRCLib by artist and song,
  then by free text, and keeps only songs within 20 seconds of the video's
  length (videos add intros and outros), taking the closest and preferring
  synced lyrics within two seconds of it. Synced lines are used only when the
  song is within three seconds of the video; further off, an intro would make
  them run ahead, so the lyrics show as plain text. A video
  that isn't a song finds nothing instead of someone else's lyrics.
- **When.** A Lyrics panel sits beside the video, above Related, as a watch
  page element. It looks lyrics up when the user clicks Find Lyrics, or for
  every video with Find Automatically on (off by default), since each lookup
  sends the video's title to LRCLib. The automatic lookup waits until the
  video's length is known (the player's, or the length YouTube lists), so the
  length check always applies. Synced lines follow the video and seek it
  when clicked, through the same `SyncedLyricsDisplayView` YouTube Music uses.
  When the wrong song or none is found, the user can search their own words;
  a typed search takes the closest song whatever its length.
  The panel isn't shown for live streams.

## Consequences

- One or two LRCLib requests per lookup; none unless the user asks or turns
  on Find Automatically.
- Covers, remixes, and live versions of other lengths find nothing until the
  user searches by hand, and music videos with long intros get plain lyrics.
