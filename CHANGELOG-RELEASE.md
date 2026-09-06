- Fixed setting a note on a Battle.net friend sometimes applying to a different friend, and moving that friend into a group they were never in. Battle.net reorders its friend list whenever anyone logs on or off, and the note was written to whoever ended up in that position rather than to the friend you clicked.
- Fixed the settings panel drawing past its own edge: the notifications section and the scroll speed slider had outgrown the window and were being drawn over the world with no panel behind them.
- "Create a Group" is now available for a friend who is already in one, and moves them into the new group. It used to be greyed out for anyone grouped, so building a group around an existing friend took three steps.
- Renaming a group is now immediate. Every member appears under the new name at once instead of crossing over one at a time while Battle.net saved each note, and the addon reports how many were saved when it is done.
- A note that Battle.net silently drops is now sent again during a group rename, so members no longer occasionally stay behind in the old group.


View all changelogs: https://github.com/Atlas-Engine/socialplus/blob/main/CHANGELOG.md
