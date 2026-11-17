# ADR-0044: YouTube sidebar order, grid zoom, and a customizable toolbar

## Status

Accepted

## Context

Users wanted to arrange the YouTube sidebar, reach their playlists from it,
make the video grids larger or smaller without scaling the whole app, and add
controls such as zoom to the window's toolbar the way Finder allows.

## Decision

- **Sidebar playlists.** Playlists sits last in Collection and has a chevron
  at its trailing edge that lists the account's playlists (without Liked
  Videos and Watch Later) as rows of their own below it. A listed playlist is
  a sidebar selection, `YouTubeNavigationItem.playlist(id:)`, so the enum
  loses its String raw value; `id` keeps the old names for the fixed items.
  An account change moves a playlist selection back to the Playlists page.
- **Sidebar order.** With ⌘ held, rows drag within their section; without it
  they don't drag at all, so a click or a stray drag never reorders. The
  sidebar tracks ⌘ with a local modifier monitor and reads the keys again
  when the app becomes active. `YouTubeSidebarOrder` saves item IDs per
  section; unknown IDs are dropped and new items go to the end.
- **Grid zoom.** One zoom level (`settings.youtubeGridZoom`, 70% to 200%)
  scales every YouTube card grid's columns and rail cards: Home,
  Subscriptions, Explore, channels, playlists, History. The watch page,
  Search, and Shorts keep their size. View → Zoom In (⌘+, and ⌘= through a
  hidden button) / Zoom Out (⌘−) / Actual Size are enabled only while a grid
  is on screen; ⌘0 stays Window → Kaset. Thumbnails decode at two sizes
  (standard, and double above 1×) so zoom steps reuse decoded images.
- **Toolbar.** The main window's toolbar is `toolbar(id:)`, so Customize
  Toolbar… works. Its defaults are the toolbar as it was; Zoom, Customize
  Player Bar…, and Customize Watch Page… can be added. Items use the automatic
  placement, with which the customization palette shows their icons.

## Consequences

- A new sidebar item needs a case in `YouTubeSidebarSection.standardItems`.
- A new grid page should read `YouTubeGridZoom.columns(zoom:)` and say so in
  `YouTubeGridZoom.isGridPage`.
- Toolbar customization is stored by AppKit under the toolbar's identifier;
  changing an item's ID drops it from users' customized toolbars.
