## [1.0.3] — 2025-12-01

### New Features
- **Search Box Added**
  - Integrated a custom search input directly into the Friends Frame.
  - Search is fully **accent-insensitive**, **symbol-insensitive**, and ignores casing.
  - Instant filtering with normalized comparisons for both WoW friends and BNet friends.
  - Maintains full compatibility with MoP Classic’s older UI XML structures.

### Improvements
- **Copy Character Name: Auto-Close**
  - Added Ctrl+C detection inside the “Copy character name” popup.
  - Popup now closes automatically after a short delay, allowing the clipboard to receive the copy 100% reliably.
  - Popup still supports Enter/Escape.

- **High-Quality UI Polish**
  - Reworked icon placement for WoW and BNet icons (faction, Battlenet, project).
  - Fixed alignment issues and overlapping name text.
  - Improved color handling with class colors, gray offline colors, and mobile indicators.

- **Secure API Wrappers**
  - Wrapped friend/BNet APIs (`GetFriendInfo`, `BNGetFriendInfo`, `SetFriendNotes`, `BNSetFriendNote`) to eliminate MoP-era inconsistencies.
  - Improved safety around invite checks, project ID mismatches, mobile friends, and realm resolution.
  - Ensured compatibility with both MoP Classic and Retail-style structures.

- **Grouping System Stability**
  - Strengthened group parsing logic (using `#groupname` tags).
  - Improved collapsed-state behavior.
  - More robust group counters (online/offline).
  - Cleaned separator rendering and header buttons.

### Fixes
- Fixed ordering and alignment issues affecting BNet and WoW friend rows.
- Eliminated several causes of misalignment when faction or game icons were missing.
- Fixed rare issues where notes or names could return nil and create taint or errors.
- Prevented popup menus from hooking protected Blizzard dropdowns on MoP Classic.
- Corrected handling for mixed BNet/WoW indexing and offline state transitions.

### Internal Cleanup
- Standardized update flow for `SocialPlus_UpdateFriends`.
- Normalized all references to modern and classic WoW APIs.
- More defensive nil-checking everywhere to prevent edge-case errors.
- Added safer tooltip refreshing logic.
