# Changelog

## 1.10b

- Battle.net friends' tooltip now shows a faction crest next to each character name, including any other simultaneous WoW sessions listed below it.

## 1.10a

- Fixed the note icon not showing on the friends list for a long character/realm name (it was getting truncated away along with the name); it now sits under the status icon instead.
- Fixed the status icon sometimes showing in the middle of a row instead of at the top, depending on scroll history.
- Battle.net friends' names in the list no longer show the realm (already shown in the row's location line and in the tooltip).
- Removed the "*" Blizzard shows next to a character's name when they can't currently group with you -- it read as a stray character rather than a meaningful indicator in this row.
- Fixed the group cogwheel sometimes not actually closing (and playing its closing sound twice) when clicking right at its edge while its menu was already open.
- Battle.net friends' tooltip now also shows their region (NA/EU) next to their name, matching the version line it already showed for a friend on a different WoW version than you.

## 1.9c

- Battle.net friends' tooltip now also lists any other WoW sessions they have online at the same time (e.g. logged in on both NA and EU at once), instead of only showing whichever one Blizzard picks.
- The Invite/Suggest Invite submenu now shows a region tag (NA/EU) on the left of each character when a friend has multiple accounts online.

## 1.9b

- Fixed some Battle.net friends showing "?" instead of their WoW version when Blizzard's own account data for them was incomplete, for every expansion.

## 1.9a

- Battle.net friends on a different WoW version than you now also show their region next to it (e.g. "Retail EU").

## 1.8c

- Fixed the friend right-click menu's Whisper (and View Friends List) sometimes acting on a different friend than the one actually clicked, if the list reindexed while the menu was open (e.g. after scrolling).

## 1.8b

- Fixed a newly created (or never drag-reordered) group's real header not showing when searching its exact name.
- Deleting a group now also clears its saved custom sort position, instead of leaving a stale entry behind.

## 1.8a

- Searching (or clicking a group tag) for an exact group name now shows that group's real header (cogwheel, mute/rename/delete, collapse arrow) with everything else hidden, instead of just a flat filtered list.
- Fixed the group cogwheel and the Invite/travel-pass button not responding to clicks while a search is active; clicking the cogwheel to manage a group no longer cancels the search.
- Fixed tooltips (including the Invite button's) not showing on mouseover while a search is active, and made sure none pop up from underneath while a right-click/group menu is open.
- Fixed the Invite button not greying out as "already grouped" for a friend on a different (but connected) realm than you.
- Fixed a friend who's both a Battle.net friend and a separately-added character friend showing up twice in search results.

## 1.7c

- Battle.net friends' tooltip now also shows their Battle.net broadcast message, with its own icon, below the note.
- The note icon shown next to a friend's name in the list now matches the tooltip's note icon.

## 1.7b

- Fixed the wrong faction icon showing on the friends-list row and invite button/menu for a friend with multiple WoW licenses online at once (was picking a different account than the one actually being shown/invited).
- The multi-license invite submenu now shows a faction crest next to each name, and opposite-faction entries render fully gray.
- Friends list tooltips are now fully custom-built instead of relying on Blizzard's own tooltip system, fixing several long-standing cases of showing the wrong friend or getting stuck.
- Faster friend-list updates for large friend lists (400+): note/group parsing is now cached and only redone when a friend's note actually changes.
- Friend Requests now shows above Favorites instead of below it.
- Fixed removing a friend from a group not actually working in some cases (and, separately, could silently drop their other group tags).
- Fixed erasing a Battle.net friend's note not saving.
- The faction icon no longer fades just because that friend is already in your party/raid.
- Tooltip position nudged so it doesn't overlap the scrollbar.

## 1.7a

- Friend level tags ("L90") now match the BattleTag's blue instead of the class color, for both Battle.net and in-game friends.
- Fixed clicking a friend sometimes showing a completely different friend's tooltip instead of the one clicked.
- Fixed a crash when removing a friend while they were selected/highlighted.
- Fixed Favorites status silently coming back when re-adding a friend who was previously removed.
- Fixed the quick-invite button not working for friends on a different WoW version than you (region/faction/coop checks now match the working right-click invite).

## 1.6c

- Fixed clicking to select a friend sometimes showing a different friend's tooltip.

## 1.6b

- Battle.net friends on a different WoW version than you now show that version (TBC, MoP, Retail, etc.) where their zone would normally appear, instead of a generic "World of Warcraft" label.
- The opposite-faction crest icon no longer fades along with genuinely blocked invites — it already shows the faction mismatch on its own.
- New setting: "Display friends levels" — shows each Battle.net friend's level (e.g. "L63") to the left of their BattleTag, on by default.
- The multi-license invite submenu now groups accounts under a header for their WoW version (e.g. "[TBC]").
- Fixed a friend randomly appearing highlighted on opening the Friends List, sometimes even jumping to a different friend, without any click.
- Fixed Send Message occasionally sending to the wrong friend after scrolling while someone was selected.

## 1.6a

- Actually fixed the Settings panel version text not showing on real releases: the packager was substituting our own placeholder-check string along with the .toc, silently defeating it every time.

## 1.5c

- Fixed the Accept button on Battle.net friend requests sometimes not responding to clicks.

## 1.5b

- "Color names by class" now colors the whole Battle.net name line, not just the character name in parentheses.
- The multi-license invite submenu now greys out accounts in a different region, or that otherwise can't group with you, same as the regular invite button — and the level/class text is class-colored.
- Class-name search no longer surfaces same-version friends who are in a different region than you.
- The Settings panel now lines up flush with the top of the Friends List panel.
- Fixed a rare case where a friend's tooltip could briefly show a different friend's info while hovering the same row without moving the mouse.

## 1.5a

- New setting: "Play a sound with notifications" — reproduces Blizzard's own friend online/offline chime, on by default.
- The Settings panel background is now solid instead of see-through, matching the same look as the right-click menus, and the notification checkboxes all line up at the same indent.
- The Settings panel now shows the addon's version in the top-right corner, always matching what's actually installed.

## 1.4c

- Much faster online/offline notifications: typically ~1 second after the client learns of the change (was up to ~5–8 seconds), still with flap protection so a character switch produces exactly one notification.
- The Favorites tag in notifications is now clickable like group names — opens the friends panel filtered to your favorites.

## 1.4b

- The "Show WoW friends first" setting is now version-aware: it reads "Show MoP friends first" on MoP Classic and "Show TBC friends first" on TBC Classic, in all languages.
- Offline notifications ("friend went offline") are now on by default for new installs.

## 1.4a

- Fixed "Copy Character Name" being blocked (ADDON_ACTION_FORBIDDEN) in chat and unit right-click menus: group-name links in notifications are now wired through the client's official link-handler registry instead of replacing a global.
- The /who list gets a proper SocialPlus right-click menu (Invite, Whisper, Ignore, Report Player, Copy Character Name) matching the stock layout — fixing the same blocked-copy error there, which stock couldn't avoid alongside the addon.
- Right-click menus on friends and /who results now play the same open/close sounds as Blizzard's own menus.

## 1.3b

- New: ungrouped in-game (character) friends now get their own "In-game Friends" section above General, with collapse/expand. Tagging them into a group moves them out of it automatically, same as favoriting.
- Fixed Battle.net friend-request Accept doing nothing; the Friend Requests header also got matching icons, joins Collapse All/Expand All, and no longer offers the group menu (rename/delete/mute never applied to it). If a request is broken server-side and can't be accepted by any means, SocialPlus now says so instead of ignoring the click.
- Smoother collapsing: toggling a group no longer scrolls the list back to the top, and the brief bounce/blank-gap when collapsing near the top or bottom of the list is gone.
- The search box is disabled and cleared on the Ignore tab.
- The panel-close memory flush now only runs when it's actually worth it (usage above 25 MB).

## 1.3a

- Fixed a long-standing scroll glitch: the list could visibly shift a beat after scrolling stopped, sometimes hiding a group header or moving the hover highlight to a different friend on its own.
- Offline friends are now sorted A–Z like everyone else (previously they appeared in an arbitrary order).
- Big memory improvements: far less allocation churn when scrolling, hovering, and collapsing/expanding, plus a garbage flush when the Friends panel closes so usage drops right back down.
- Deleting a group now asks for confirmation first.
- Removing a Battle.net friend now just needs "YES" (no period), case- and accent-insensitive.
- Notes can no longer fake group membership: "#" typed in the note popup is stripped, and "# text" with a space is not treated as a group tag.
- Notifications are more compact: dropped the [SocialPlus] prefix, and the Battle.net name is shown in [brackets].
- The Favorites header shows a star on each side, and the group menu wording was polished in all three languages.
- Toggling Mute Notifications now closes the menu.

## 1.2a and earlier (1.1a–1.2a)

- Search matches group tags only, not free-text note content.
- Fixed the search box clear button not responding, and the group cogwheel double-click toggling collapse.
- Invites grey out with a reason when the friend is already in your group.

## 1.0

First stable release. Highlights:

- Group your friends, drag-and-drop to reorder groups, and collapse/expand any group (including the ungrouped "General" bucket) individually or all at once.
- Favorite friends independently of Blizzard's own Battle.net favorite, pinned to the top of their group.
- Smarter sorting (status, then game/client, then alphabetical), with an option to prioritize friends on your current WoW version.
- Configurable online/offline notifications, with per-group muting.
- Smooth, adjustable-speed scrolling for large friend lists.
- Full French and Spanish localization alongside English.
