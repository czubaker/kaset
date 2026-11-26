# ADR-0050: One customization sheet for the toolbar and the player bar

## Status

Accepted. Supersedes the toolbar part of
[ADR-0044](0044-youtube-navigation-customization.md).

## Context

The window toolbar used AppKit's own customization (`toolbar(id:)`, View →
Customize Toolbar…), and the player bars used Kaset's sheet (ADR-0042). Users
wanted to move player controls (play/pause, skips, captions, the sleep timer,
…) up into the toolbar as well, and to arrange both in one place rather than
two unrelated sheets. AppKit's palette can only offer items declared in code
and can't share a layout with the bars.

## Decision

- The toolbar is one more area of each source's `PlayerBarConfiguration`
  (`PlayerBarArea.toolbar`). An item still appears at most once (spaces
  repeat), so moving a button up takes it off the bar.
- Items say where they may go. Buttons that read well as toolbar buttons may
  go in the toolbar or on the bar. Media details blocks (artwork, title,
  thumbnail, avatar, details, the Subscribe button), Mix tracks, and Float on
  Top (detached window only) stay on the bar. The toolbar's own buttons are
  items too, allowed only there: Command Bar and Customize for YouTube Music;
  Refresh, Notifications, Zoom, Customize Watch Page, and Customize for
  YouTube.
- `PlayerBarItemKind.standardToolbar` is the toolbar as it was (Command Bar;
  Refresh and Notifications). A layout saved before this change decodes with
  it, so nothing moves until the user customizes; an emptied toolbar stays
  empty.
- The window draws `WindowToolbar`, the toolbar area's items in order, each a
  plain `ToolbarItem`. Space is a fixed `ToolbarSpacer` (a gap between Liquid
  Glass groups) and Flexible Space a flexible one; macOS 15 has no toolbar
  spacers, so spaces are skipped there. Items that draw nothing right now
  (rating when signed out, captions without tracks, Command Bar without Apple
  Intelligence) are left out, as on the bars.
- Bar buttons render through `PlayerBarIconButton`/`PlayerBarIconMenu`, which
  read `\.playerBarItemStyle`: on the bar they keep their capsule look; in the
  toolbar they become ordinary toolbar buttons and menus, so the toolbar's
  hover, grouping, and Icon and Text labels apply. Controls that were private
  to the bars have small toolbar versions (`MusicToolbarItem`,
  `YouTubeToolbarItem`); volume becomes a slider in a popover.
- The sheet (View → Customize Toolbar and Player Bar…, the bar's context menu,
  the YouTube gear menu, and the Customize toolbar item) shows the toolbar as
  a strip above the bar preview, its items at the trailing end as in the
  window, and one palette for both. The watch page's "Hide What the Player Bar
  Shows" looks only at the bar's areas.
- AppKit's toolbar customization is gone: the right-click Customize Toolbar…
  menu and its saved configuration no longer apply. Keyboard shortcuts that
  toolbar buttons carried live in the menus (⇧⌘R Refresh, ⌘K Command Bar).

## Consequences

- A new toolbar-capable control is an item whose `allowedAreas` include
  `.toolbar`, with a case in the source's toolbar item view.
- Toolbar items can't be reordered by dragging in the window itself; the
  sheet is the one place to arrange them.
