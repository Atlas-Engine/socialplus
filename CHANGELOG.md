# Changelog

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
