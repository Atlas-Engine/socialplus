- Much less lag on a large friends list (reported live around 460 friends), both opening the panel and while scrolling. Friend updates arrive in bursts on a big list, and every single one was rebuilding the whole list from scratch -- a burst now costs one rebuild instead of one each.
- The background check that watches for friends coming and going no longer creates and throws away a piece of bookkeeping per friend every time it runs, which it did several times a second whether or not the friends list was even open.
- Searching a large friends list is much faster: every friend was being looked up twice per keystroke instead of once.
- Joining or leaving a group no longer rebuilds the whole friends list, which it did every time the group changed -- constantly, in a raid. The invite icons now update straight away instead, which they previously did not until something else happened to redraw them.
- Typing in the search box waits for you to stop before rebuilding the list, rather than rebuilding on every letter.
- The friends list no longer rebuilds itself during combat. Anything that changed while you were fighting is picked up the moment you leave it.
- Friend updates that used to arrive in bursts -- one per friend changing zone, going away, or switching character -- are now gathered into a single refresh instead of one apiece.
- SocialPlus now sits under Chat in the in-game AddOn list, in your client's own language, with its own icon beside it.
- Closing the friends list no longer forces a memory sweep. It was there to mop up the churn the fixes above remove, and the sweep itself paused every addon in the game, not just this one.
- Sorting no longer re-processes the same names thousands of times per rebuild.
- Fixed occasional "You are not in a party." messages in Dungeon Finder and other instance groups whenever the roster changed.
- Adding or removing a favorite from a search result now clears the search, so you can see the friend move into or out of Favorites. Group changes already did this.


View all changelogs: https://github.com/Atlas-Engine/socialplus/blob/main/CHANGELOG.md
