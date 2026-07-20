# Changelog

## 1.7a

- Friend level tags ("L90") now match the BattleTag's blue instead of the class color, for both Battle.net and in-game friends.
- Fixed clicking a friend sometimes showing a completely different friend's tooltip instead of the one clicked.

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
