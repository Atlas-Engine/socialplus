# Changelog

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
