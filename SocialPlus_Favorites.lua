local ADDON_NAME, ns = ...

-- Favourites, lifted out of SocialPlus.lua unchanged.
--
-- Sixth slice, and the only one that needed nothing at all: no locals from
-- outside, no writes across the boundary, and nothing reaching back in. It
-- talks to SavedVariables and to already-global helpers, which is why it came
-- out without a single promotion or export.

-- [[ SocialPlus-managed favorites ]]
-- A stable key independent of the volatile friend-list index. presenceID is
-- only valid for the current session -- the client can assign a different
-- presenceID to the same BNet friend after a relog, so it can't be used for
-- anything persisted across sessions. battleTag is the permanent per-account
-- identifier and is used for BNet friends instead; character name is used
-- for native WoW-only friends.
local function SocialPlus_GetFavoriteKey(buttonType,id)
	if buttonType==FRIENDS_BUTTON_TYPE_BNET then
		local _,_,battleTag=FG_BNGetFriendInfo(id)
		return battleTag and battleTag~="" and ("BNET:"..battleTag)
	elseif buttonType==FRIENDS_BUTTON_TYPE_WOW then
		local info=FG_GetFriendInfoByIndex(id)
		return info and info.name and info.name~="" and ("WOW:"..info.name)
	end
	return nil
end

----------------------------------------------------------------
-- Recently added
----------------------------------------------------------------

-- Everyone on the list right now, by the same stable key favourites use.
-- Global for the 200-locals reason above.
function SocialPlus_CollectFriendKeys()
	local keys={}

	for i=1,(FG_BNGetNumFriends and FG_BNGetNumFriends() or 0) do
		local key=SocialPlus_GetFavoriteKey(FRIENDS_BUTTON_TYPE_BNET,i)
		if key then keys[key]=true end
	end

	local wow=C_FriendList and C_FriendList.GetNumFriends and C_FriendList.GetNumFriends() or 0
	for i=1,wow do
		local key=SocialPlus_GetFavoriteKey(FRIENDS_BUTTON_TYPE_WOW,i)
		if key then keys[key]=true end
	end

	return keys
end

-- A fresh session: everyone here now counts as already known, and nobody is
-- recent. Without this the entire friends list would show up as newly added
-- the first time the feature ran.
function SocialPlus_StartFriendSession()
	if not SocialPlus_SavedVars then return end
	SocialPlus_SavedVars.recent={}
	SocialPlus_SavedVars.known=SocialPlus_CollectFriendKeys()
	-- Primed to match the snapshot so the first rebuild afterwards does not
	-- see a changed count and rescan the list it was just handed.
	local bnet=(FG_BNGetNumFriends and FG_BNGetNumFriends()) or 0
	local wow=(C_FriendList and C_FriendList.GetNumFriends and C_FriendList.GetNumFriends()) or 0
	SOCIALPLUS_LAST_FRIEND_COUNT=bnet+wow
end

-- Waits for the list to STOP GROWING rather than trusting a fixed delay.
--
-- BNGetFriendInfo answers nothing for a friend whose account data has not
-- streamed in yet, so a snapshot taken mid-stream records only part of the
-- list. Everyone arriving afterwards is then absent from `known`, and the next
-- rebuild files them all under "Recently Added" -- exactly what the snapshot
-- exists to prevent, just moved later. A fixed five seconds was a guess that a
-- slow login or a large Battle.net list can beat.
--
-- Two consecutive reads agreeing is the signal. Bounded so that a genuinely
-- empty list (which never grows) still starts a session promptly, and a list
-- that somehow never settles cannot poll forever.
function SocialPlus_StartFriendSessionWhenReady(tries,lastCount)
	tries=(tries or 0)+1

	local count=0
	for _ in pairs(SocialPlus_CollectFriendKeys()) do count=count+1 end

	if (lastCount and count==lastCount) or tries>=10 then
		SocialPlus_StartFriendSession()
		return
	end

	C_Timer.After(2,function()
		SocialPlus_StartFriendSessionWhenReady(tries,count)
	end)
end

-- Anyone on the list who was not there at login. Called from the rebuild, so an
-- addition is noticed as soon as anything redraws.
function SocialPlus_NoteNewFriends()
	if not (SocialPlus_SavedVars and SocialPlus_SavedVars.known) then return end

	-- Gated on the friend count changing, because the scan below costs one
	-- BNGetFriendInfo per friend and this is called from every rebuild --
	-- including collapsing a group, scrolling, and toggling offline friends,
	-- none of which can add anybody. On a large list that was hundreds of API
	-- calls to re-answer a question whose inputs had not moved.
	--
	-- Counts are the cheap gate: nobody can appear without the total changing.
	-- The one case this misses is a removal and an addition between the same
	-- two rebuilds, which leaves the total equal -- that friend simply is not
	-- flagged as recent, which is a far better trade than rescanning always.
	local bnet=(FG_BNGetNumFriends and FG_BNGetNumFriends()) or 0
	local wow=(C_FriendList and C_FriendList.GetNumFriends and C_FriendList.GetNumFriends()) or 0
	local total=bnet+wow
	if SOCIALPLUS_LAST_FRIEND_COUNT==total then return end
	SOCIALPLUS_LAST_FRIEND_COUNT=total

	SocialPlus_SavedVars.recent=type(SocialPlus_SavedVars.recent)=="table"
		and SocialPlus_SavedVars.recent or {}

	for key in pairs(SocialPlus_CollectFriendKeys()) do
		if not SocialPlus_SavedVars.known[key] then
			SocialPlus_SavedVars.known[key]=true
			SocialPlus_SavedVars.recent[key]=true
		end
	end
end

function SocialPlus_ClearRecentFriends()
	if not SocialPlus_SavedVars then return end
	SocialPlus_SavedVars.recent={}
	SocialPlus_Update(true)
end

function SocialPlus_HasRecentFriends()
	local recent=SocialPlus_SavedVars and SocialPlus_SavedVars.recent
	return recent~=nil and next(recent)~=nil
end

-- key is optional: a caller that already holds this friend's key (the rebuild's
-- per-friend pass does, from the BNGetFriendInfo it made while bucketing) can
-- pass it and skip the lookup, which is an API call per friend per rebuild.
-- Pass false for "known to have no key" so it isn't mistaken for "not supplied".
-- Global: the friend row dropdown lives in its own file now.
function SocialPlus_IsFavorite(buttonType,id,key)
	if key==nil then key=SocialPlus_GetFavoriteKey(buttonType,id) end
	return key and SocialPlus_SavedVars and SocialPlus_SavedVars.favorites and SocialPlus_SavedVars.favorites[key]==true
end

-- In the recently-added group: added this session, not favourited, and not yet
-- filed into a group of your own.
--
-- Filing is the same intent as pressing the X, so it dismisses on its own --
-- which is why moving somebody into a group makes them leave here without any
-- extra bookkeeping.
-- Global for the 200-locals reason above.
-- key is optional, for the same reason as SocialPlus_IsFavorite above.
function SocialPlus_IsRecent(buttonType,id,groups,key)
	local recent=SocialPlus_SavedVars and SocialPlus_SavedVars.recent
	if not recent then return false end

	-- Nothing recent at all is the normal state, and it is answerable without
	-- touching the friend APIs. Checked FIRST because this runs once per friend
	-- per rebuild in two separate loops, and every step below costs a
	-- BNGetFriendInfo.
	if not next(recent) then return false end

	-- One key derivation, not two. This used to call SocialPlus_IsFavorite
	-- first, which derives the very same key through its own
	-- BNGetFriendInfo -- so every friend paid for the lookup twice before
	-- anything had even been decided.
	if key==nil then key=SocialPlus_GetFavoriteKey(buttonType,id) end
	if not (key and recent[key]) then return false end

	-- The favourite test, inlined against the key already in hand: a
	-- favourited friend belongs in Favorites rather than here.
	local favorites=SocialPlus_SavedVars.favorites
	if favorites and favorites[key]==true then return false end

	-- groups carries "" alone when the friend has no tags at all.
	if groups then
		for name in pairs(groups) do
			if name~="" then return false end
		end
	end

	return true
end

function SocialPlus_ToggleFavorite(buttonType,id)
	local key=SocialPlus_GetFavoriteKey(buttonType,id)
	if not key then return end
	SocialPlus_SavedVars.favorites=type(SocialPlus_SavedVars.favorites)=="table" and SocialPlus_SavedVars.favorites or {}
	if SocialPlus_SavedVars.favorites[key] then
		SocialPlus_SavedVars.favorites[key]=nil
	else
		SocialPlus_SavedVars.favorites[key]=true
	end

	-- Clear search so the full list comes back, matching what every other
	-- action that moves a row already does (add/remove group). Favoriting
	-- lifts the friend into the Favorites section at the top, so leaving the
	-- filter on hides the result of the thing you just asked for.
	if SocialPlus_ClearSearch then
		SocialPlus_ClearSearch()
	end

	SocialPlus_Update(true)

	-- Toggling favorite status can make the whole Favorites divider appear
	-- or disappear, shifting every subsequent row's position -- Blizzard's
	-- HybridScrollFrame doesn't always fully re-anchor its pooled buttons
	-- from a single re-update, leaving stale/overlapping rows until an
	-- actual scroll event forces its own layout pass (confirmed live). This
	-- wasn't just cosmetic: right-clicking a row during that stale window
	-- could open the context menu for a completely different friend than
	-- the one visually under the cursor, silently favoriting/acting on the
	-- wrong person (confirmed live -- favoriting two friends back to back
	-- ended up favoriting two unrelated ones instead). Call again
	-- immediately, synchronously, so no user interaction can land inside
	-- that stale window; also keep a deferred pass for the same reason the
	-- original fix was deferred (Blizzard's own layout pass may only fully
	-- apply on the next frame).
	SocialPlus_Update(true)
	C_Timer.After(0,function()
		SocialPlus_Update(true)
	end)
end
