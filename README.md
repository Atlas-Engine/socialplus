# SocialPlus

**A complete Friends List upgrade for MoP Classic and TBC Classic** — reliable cross-realm invites, custom friend groups, favorites, rich online/offline notifications, and instant search, all in the original Blizzard look and feel. Available in English, French, and Spanish.

---

## Why SocialPlus?

The Classic clients ship with a bare-bones friends list and notoriously unreliable cross-realm invites. SocialPlus fixes the invites, then rebuilds the rest of the social experience around them — with the same full feature set on both MoP Classic and TBC Classic.

## Features

### 📌 Reliable Cross-Realm Invites
Invites that work consistently — and when one isn't possible, SocialPlus tells you *why* (region, faction, or game version) instead of failing silently.

### 🗂️ Friend Groups
Organize your friends into custom groups:
- Create, rename, and delete groups at any time
- Drag & drop a friend into a group, or move them through the right-click menu
- Collapse and expand groups individually or all at once, with online/total counters
- Right-click a group header for group-wide actions: invite everyone, rename, delete, or mute notifications

### ⭐ Favorites
Pin the friends you actually play with:
- Right-click any friend → **Add to Favorites**
- Favorites are marked with a star and listed at the top of their group, in alphabetical order
- Completely independent of Blizzard's own Battle.net favorites
- Stored locally, like all SocialPlus settings — see [Known Limitations](#known-limitations) if you play one Battle.net account across multiple WoW licenses

### 🔀 Smart Sorting
Your list reads the way you'd expect:
- Online friends first, then DND, then away
- Friends grouped by the game or client they're playing, with Battle.net-app idlers last
- Alphabetical within each cluster
- Optional **Prioritize [your version] friends** — moves friends on your exact game version to the top, same-faction first

### 🔔 Smart Notifications
Far more useful than Blizzard's default "X has come online":
- **Class-colored, clickable name** — click it to open a whisper instantly, faction- and cross-realm-safe
- Displays class, level, game version (Retail, TBC, WotLK, Cata, MoP), faction icon, and region (NA/EU)
- Shows which of your groups the friend belongs to
- Per-group mute, plus master and offline-notification toggles in the settings panel
- The default **General** group (ungrouped friends) starts muted — unmute it from its group header to get notified about everyone

### 🎯 Enhanced Right-Click Menu
Everything one click away: invite, whisper, copy character name, set note, add to favorites, move or remove from groups, and remove friend.

### 🔍 Instant Search
Accent-insensitive and filters in real time as you type — matching both character names *and* classes ("lock" finds your Warlock friends).

### 🎨 Polished Visuals
Class-colored names, faction crests, and consistent game icons. Friends you can't invite fade subtly, so you always see who's actually available.

### 🌀 Smooth Scrolling
Inertia-based scrolling that keeps large friend lists fluid instead of choppy.

### 🌍 Localization
Fully translated into English, French, and Spanish — SocialPlus follows your client language automatically.

## Known Limitations

**Favorites (and groups' mute state, notification settings, etc.) don't sync across multiple WoW licenses on one Battle.net account.** Groups themselves *do* carry over, because they're stored in the friend's note — a Blizzard-synced, server-side field. Favorites have no such field to piggyback on (Blizzard's own Battle.net favorite flag can't be read or toggled by addons), so they're saved locally instead, in that license's own SavedVariables file.

If you use several linked WoW licenses under the same Battle.net account and want them to share favorites, symlink the SavedVariables file between the two license folders so they read/write the same physical file:

```
mklink "C:\World of Warcraft\_classic_\WTF\Account\WOW2\SavedVariables\SocialPlus.lua" "C:\World of Warcraft\_classic_\WTF\Account\WOW1\SavedVariables\SocialPlus.lua"
```

(Run as Administrator, from the license that doesn't have the file yet — delete/rename its existing copy first. Replace the paths and `WOW1`/`WOW2` account-folder names with your own.)

## Feedback

Found a bug or have a suggestion? Leave a comment on CurseForge or open an issue on GitHub — every report helps.

## Credits

| Version | Contributor |
|---|---|
| Original | frankkkkk |
| 6.2 fixes | ClassZ |
| 7.1 fixes | Mikeprod |
| 8.2 fixes | y368413 |
| 8.2.5 fixes | Mudohir |
| 8.3 / 9.0.5 / 10.0 | Hayato2846 |
| MoP & TBC Classic modernization | Atlas-Engine |
