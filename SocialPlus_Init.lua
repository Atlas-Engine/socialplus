local ADDON_NAME, ns = ...
local L = ns.L

-- Taken off ns and aliased back to locals, so the handler below reads exactly
-- as it did in SocialPlus.lua and pays an upvalue rather than a table lookup on
-- every event.
--
-- All read-only from here. SocialPlus_ScanWarmupUntil is deliberately absent:
-- this file WRITES it, so it stays a global rather than becoming a stale copy.

local frame = ns.frame
local Hook = ns.Hook
local HookButtons = ns.HookButtons
local FriendsScrollFrame = ns.FriendsScrollFrame
local FriendButtonTemplate = ns.FriendButtonTemplate
local FG_InitFactionIcon = ns.FG_InitFactionIcon
local SocialPlus_EnsureSavedVars = ns.SocialPlus_EnsureSavedVars
local SocialPlus_GetTopButton = ns.SocialPlus_GetTopButton
local SocialPlus_HardResetScrollRows = ns.SocialPlus_HardResetScrollRows
local SocialPlus_HideRowTooltip = ns.SocialPlus_HideRowTooltip
local SocialPlus_QueueFriendScan = ns.SocialPlus_QueueFriendScan
local SocialPlus_QueueNotifyCheck = ns.SocialPlus_QueueNotifyCheck
local SocialPlus_ScheduleCollapseSettle = ns.SocialPlus_ScheduleCollapseSettle
local SocialPlus_UpdateFriends = ns.SocialPlus_UpdateFriends
local GetFriendInfoById = ns.GetFriendInfoById

-- The event dispatcher, lifted out of SocialPlus.lua unchanged.
--
-- Third slice. It is one top-level statement -- frame:SetScript("OnEvent", ...)
-- -- so it moves whole. Nothing else in the addon reaches into it, and it runs
-- after this file loads because no event dispatches during load.

-- [[ Initialization on PLAYER_LOGIN ]]

frame:SetScript("OnEvent",function(self,event,...)
	-- ANY registered event marks the friend data as possibly changed.
	--
	-- Set here, once, rather than in each branch below: this frame is
	-- registered only for events that can plausibly affect what the list
	-- shows, and the cost of being wrong in this direction is one extra
	-- rebuild, while the cost of missing one is a stale list. Deliberately
	-- before the branches, so an early return cannot skip it.
	--
	-- Read by the scroll-window skip in SocialPlus_Update: that skip only
	-- suppresses a data pass when NOTHING here has fired since the last one.
	--
	-- GROUP_ROSTER_UPDATE is the one exception, and it is worth the branch.
	-- Joining or leaving a group changes whether a friend can be invited --
	-- which is drawn per row, from SocialPlus_GetInviteStatus, at render time
	-- -- but it cannot move anybody between groups, rename one, or change who
	-- is online. Nothing the derivation reads. Marking the data dirty for it
	-- bought a full per-friend pass (~32ms across a large list) for a result
	-- identical to the one already held, and in a raid this event fires
	-- constantly, which is exactly when the frames are least affordable.
	-- The rows still need repainting, so the branch below does that instead.
	if event~="GROUP_ROSTER_UPDATE" then
		SOCIALPLUS_DATA_DIRTY=true
	end

	-- A fresh login empties the recently-added group; a /reload does not.
	--
	-- The distinction is the whole reason the group can be session-scoped and
	-- still survive reloading: isInitialLogin and isReloadingUi arrive as the
	-- two arguments of this event, and nothing else in the client tells them
	-- apart afterwards.
	if event=="PLAYER_ENTERING_WORLD" then
		local isInitialLogin=...
		if isInitialLogin and SocialPlus_StartFriendSessionWhenReady then
			-- Deliberately NOT a fixed delay -- see that function: it retries
			-- until the friend list stops growing, because a snapshot taken
			-- while Battle.net is still streaming marks the remainder of the
			-- list as newly added.
			C_Timer.After(2,SocialPlus_StartFriendSessionWhenReady)
		end
		return
	end

	if event=="PLAYER_LOGIN" then
		SocialPlus_EnsureSavedVars()
		SocialPlus_ApplyToastCVars()

		-- Give friends' game-account data a few seconds to finish streaming
		-- in before trusting the scan to detect real transitions.
		SocialPlus_ScanWarmupUntil=GetTime()+5

		-- Safety net for "left/entered WoW while staying connected" detection:
		-- a passive AFK disconnect, or launching WoW from an already-open
		-- Battle.net app, doesn't reliably fire FRIENDLIST_UPDATE (confirmed
		-- live for both), so don't depend on events alone. Short enough to
		-- keep the worst-case notification delay reasonable. Not a
		-- false-positive risk (just polling frequency), so kept short.
		C_Timer.NewTicker(5,SocialPlus_QueueFriendScan)

		-- Out-of-date version alert: the prefix must be registered before
		-- CHAT_MSG_ADDON will ever deliver it to us. The opening broadcast
		-- is delayed so guild/group rosters have actually finished loading
		-- (sending into an empty roster right at login just gets dropped).
		local registerPrefix=(C_ChatInfo and C_ChatInfo.RegisterAddonMessagePrefix) or RegisterAddonMessagePrefix
		if registerPrefix then
			pcall(registerPrefix,SOCIALPLUS_VERSION_PREFIX)
		end
		C_Timer.After(10,SocialPlus_BroadcastVersion)
		-- Staggered behind the guild/group broadcast so the two openers
		-- don't stack into one burst of addon traffic at login.
		C_Timer.After(15,SocialPlus_SendVersionToBNetFriends)

		FG_InitFactionIcon()

		Hook("FriendsList_Update",SocialPlus_Update,true)

		-- The two spammy events come off Blizzard's own frame, and this addon
		-- drives them instead.
		--
		-- That hook is a hooksecurefunc, so Blizzard's WHOLE FriendsList_Update
		-- body runs before ours does -- on every single one of these events. On
		-- a large list they arrive in bursts (every friend changing zone,
		-- flipping AFK or switching character sends one), so the burst cost was
		-- never just this addon's derivation: it was Blizzard's full list
		-- rebuild too, N times over, and nothing here could throttle that from
		-- inside a hook that only runs after it has already happened.
		--
		-- Deliberately NOT re-implementing what their handler does. The events
		-- are unregistered, but FriendsList_Update itself is still called --
		-- once per burst, from SocialPlus_RequestListRefresh -- so every side
		-- effect it has (tab counts, the rest of the panel) still happens,
		-- just at a rate somebody chose. Only the two high-frequency events
		-- move; invites, connects and disconnects stay on Blizzard's frame
		-- where they are rare and want to be immediate.
		--
		-- SOCIALPLUS_DRIVE_REFRESH=false (via /run, before this point) leaves
		-- Blizzard's registration alone, as an escape hatch if this ever proves
		-- to have taken something with it.
		if SOCIALPLUS_DRIVE_REFRESH~=false and FriendsFrame and FriendsFrame.UnregisterEvent then
			FriendsFrame:UnregisterEvent("FRIENDLIST_UPDATE")
			FriendsFrame:UnregisterEvent("BN_FRIEND_INFO_CHANGED")
			SOCIALPLUS_DRIVING_REFRESH=true
		end

		-- Force a real render on every panel open, in isolation this time
		-- (no debounce/dirty-check machinery to race against -- both fully
		-- reverted). If the friend list data hasn't changed since it was
		-- last open, Blizzard's own FriendsList_Update may not fire at all
		-- on reopen, so our own render pass (which is what keeps the
		-- tooltip in sync -- see the SocialPlus_MouseIsOver check above) never
		-- ran, and whatever tooltip showed came from Blizzard's own stale
		-- internal state instead (reported live: closed while hovering one
		-- friend, reopened without moving the mouse, got a completely
		-- unrelated friend's tooltip).
		if FriendsFrame and FriendsFrame.HookScript then
			FriendsFrame:HookScript("OnShow",function()
				SocialPlus_HardResetScrollRows()
				SocialPlus_Update(true)
				-- KEEP THIS. Removing it as a "redundant" second rebuild sent
				-- the open path from 3 rebuilds to 15 (51ms, measured): without
				-- the settle pass the content height never stabilises, so the
				-- scrollbar's OnValueChanged keeps re-entering Blizzard's
				-- HybridScrollFrame update, which fires FriendsList_Update
				-- again -- the self-sustaining churn documented throughout
				-- SocialPlus_UpdateFriends. One extra rebuild here BUYS the
				-- absence of a dozen.
				SocialPlus_ScheduleCollapseSettle()
			end)
		end

		-- The panel-close garbage sweep used to live here, and is gone.
		--
		-- It forced collectgarbage("collect") when this addon's attributed
		-- memory passed 25 MB, to flush transient garbage that heavy
		-- scrolling and collapse spam left parked -- tens of MB of it,
		-- reported live.
		--
		-- Two reasons it went rather than being tuned. The first is that
		-- the churn it was mopping up is largely gone: the per-friend
		-- table thrown away for every friend on every notification scan,
		-- the sort comparator re-lowercasing the same names thousands of
		-- times a rebuild, a full derivation per event in a burst, a
		-- rebuild per keystroke, and Blizzard's own list rebuild running
		-- just as often -- all of those were the source, and all of them
		-- are fixed. Measured after: a simulated 460-friend list no longer
		-- climbs anywhere near the threshold that made this fire.
		--
		-- The second is that the cure was heavier than it looked. There is
		-- one Lua state for every addon in the game, so "collect" was never
		-- this addon tidying up after itself -- it was a stop-the-world
		-- collection of everyone's garbage, triggered by one addon's own
		-- accounting. And UpdateAddOnMemoryUsage, the guard meant to avoid
		-- paying that, walks every loaded addon to recompute attribution --
		-- so the cheap path still paid a real cost on every single panel
		-- close, to answer a question that is now always "no".
		--
		-- Garbage sitting uncollected is not a leak. Lua's incremental
		-- collector reclaiming it lazily is the collector working, and the
		-- number in an addon-memory readout is not memory lost. If that
		-- number ever climbs like it used to, the fix is to find what is
		-- allocating -- not to stop the world on the way out.

		FriendsScrollFrame.dynamic=SocialPlus_GetTopButton
		-- Scrolling only re-rendered the cached FriendButtons[].id indices
		-- from the last full update, without re-verifying they still point
		-- to the same friends -- Blizzard's own friend-list index-to-friend
		-- mapping can shift in the background between updates, so a stale
		-- index could silently render a completely different friend after
		-- scrolling (confirmed live: a friend playing Hearthstone appeared
		-- to vanish/replace-with-someone-else on scroll). A full recompute
		-- fixes this, but doing it on every single scroll tick is expensive
		-- for large friend lists (rebuilds + re-sorts everyone on every
		-- frame of an inertia scroll). Instead: keep scrolling itself cheap
		-- (just reposition/re-render with the cached data, as before), and
		-- debounce the actual full recompute to run once ~150ms after
		-- scrolling settles -- short enough that a stale row is corrected
		-- almost immediately, without paying the full cost on every tick.
		--
		-- This used to allocate a fresh C_Timer.NewTimer on every single
		-- scroll tick (cancelling the previous one first) -- during a fast
		-- inertia scroll .update() fires dozens of times per second, so a
		-- sustained fast scroll allocates and discards dozens of timer
		-- objects a second (reported live as a memory bump during fast
		-- scrolling, worse than the collapse-toggle case). Replaced with a
		-- single ticker, created once and never recreated: each scroll tick
		-- only touches two cheap upvalues (a flag and a timestamp), and the
		-- ticker itself just polls whether scrolling has gone quiet.
		local SocialPlus_ScrollDirty=false
		local SocialPlus_LastScrollTick=0
		local SocialPlus_LastScrollValue=nil
		FriendsScrollFrame.update=function()
			-- The scrollbar quantizes every SetValue to multiples of 32px
			-- (a built-in value step), so the value our wheel handler
			-- requests vs. what the slider stores always differ slightly
			-- -- compare ROUNDED values, or "did it change?" checks are
			-- unreliable (confirmed live via an event trace). Blizzard
			-- only invokes .update() when the TOP ROW actually changes,
			-- and it applies the new sub-row pixel offset itself,
			-- immediately -- so every real change MUST re-render right
			-- away. An earlier rate-throttle here skipped some of these
			-- renders, leaving the old rows displayed shifted by the new
			-- row's remainder until the settle pass corrected it ~200ms
			-- later -- that delayed correction was the long-hunted
			-- "refresh that moves things / hides a group header" glitch
			-- (confirmed by matching an event trace against a screen
			-- recording). Only true no-ops (rounded value unchanged)
			-- may return early.
			local value=FriendsScrollFrame.scrollBar and FriendsScrollFrame.scrollBar:GetValue()
			value=value and math.floor(value+0.5)
			if value==SocialPlus_LastScrollValue then
				-- No-op guard: only a real value change counts as
				-- "still scrolling" (also keeps these calls from pushing
				-- the settle countdown back indefinitely).
				return
			end
			-- Hide outright rather than trust the per-row resync to catch
			-- it here -- the mouse-focus check can misreport during/right after a
			-- mouse-wheel scroll event (focus can transiently shift to the
			-- scroll frame itself), so the resync's "is the cursor over ME"
			-- check silently failed to match ANY row and the tooltip just
			-- stayed at its old position/content (reported live: scrolling
			-- without moving the mouse left the tooltip stuck in place).
			-- The resync logic still recovers it correctly on the next
			-- genuine hover.
			SocialPlus_HideRowTooltip()
			SocialPlus_ScrollDirty=true
			SocialPlus_LastScrollTick=GetTime()
			SocialPlus_UpdateFriends()
			-- Cache the value as it settled AFTER rendering, not the value
			-- that triggered this call -- SocialPlus_UpdateFriends clamps
			-- the scrollbar's value itself (the scrollbar-range fix), so
			-- comparing against the pre-render value here would make our
			-- own clamp look like a "real" scroll change on the very next
			-- call. Rounded, same as the comparison above.
			local settled=FriendsScrollFrame.scrollBar and FriendsScrollFrame.scrollBar:GetValue()
			SocialPlus_LastScrollValue=settled and math.floor(settled+0.5)
		end
		C_Timer.NewTicker(0.1,function()
			if SocialPlus_ScrollDirty and (GetTime()-SocialPlus_LastScrollTick)>=0.15 then
				SocialPlus_ScrollDirty=false
				-- A full data pass ONLY if something actually changed while
				-- scrolling. Measured: this settle was 36 of 41 data passes in
				-- a 16-second run -- ~32ms each, re-deriving all 866 friends to
				-- rebuild a list that scrolling cannot have altered.
				--
				-- What the settle is for is finishing the render once the rows
				-- have stopped moving, and SocialPlus_UpdateFriends is that.
				-- The per-friend derivation was only ever coming along for the
				-- ride because SocialPlus_Update(true) is the whole pipeline.
				if SOCIALPLUS_DATA_DIRTY then
					SocialPlus_Update(true)
				else
					SocialPlus_UpdateFriends()
				end
			end
		end)

		if FriendsScrollFrame and FriendsScrollFrame.buttons and FriendsScrollFrame.buttons[1] and FRIENDS_FRAME_FRIENDS_FRIENDS_HEIGHT then
			pcall(FriendsScrollFrame.buttons[1].SetHeight,FriendsScrollFrame.buttons[1],FRIENDS_FRAME_FRIENDS_FRIENDS_HEIGHT)
		end
		if HybridScrollFrame_CreateButtons then
			pcall(HybridScrollFrame_CreateButtons,FriendsScrollFrame,FriendButtonTemplate)
		end

		HookButtons()
		SocialPlus_HookWhoButtons()
	elseif event=="BN_FRIEND_ACCOUNT_ONLINE" then
		local bnetIDAccount=...
		SocialPlus_QueueNotifyCheck(bnetIDAccount)
		SocialPlus_QueueFriendScan()
		-- Delayed: their game-account data (which is what carries the
		-- gameAccountID we'd send to) hasn't streamed in yet at this point.
		C_Timer.After(10,function()
			SocialPlus_SendVersionToBNetFriend(bnetIDAccount)
		end)
	elseif event=="BN_FRIEND_ACCOUNT_OFFLINE" then
		local bnetIDAccount=...
		SocialPlus_QueueNotifyCheck(bnetIDAccount)
		SocialPlus_QueueFriendScan()
	elseif event=="FRIENDLIST_UPDATE" then
		SocialPlus_QueueFriendScan()
		-- Only when Blizzard's frame is no longer listening for this itself --
		-- otherwise their handler already ran and asking again would double it.
		--
		-- Suppressed during a bulk note write for the same reason as the branch
		-- below: a note landing fires this too, so leaving it open let the burst
		-- redraw the list one member at a time through the other door.
		if SOCIALPLUS_DRIVING_REFRESH and not SocialPlus_BulkNotesActive() then
			SocialPlus_RequestListRefresh()
		end
	elseif event=="BN_FRIEND_INFO_CHANGED" then
		SocialPlus_QueueFriendScan()

		-- Not while a bulk note write is in flight. A group rename confirms one
		-- note at a time over the better part of a minute, and rebuilding the
		-- whole list on each is what made the members appear to move across one
		-- by one. SocialPlus_BeginBulkNotes redraws once the notes have all read
		-- back, which is the only point at which the list is actually right.
		if SocialPlus_BulkNotesActive() then
			SocialPlus_BulkNotesSaw()
		elseif SOCIALPLUS_DRIVING_REFRESH then
			SocialPlus_RequestListRefresh()
		end
	elseif event=="CHAT_MSG_ADDON" then
		local prefix,message,_,sender=...
		SocialPlus_OnVersionMessage(prefix,message,sender)
	elseif event=="BN_CHAT_MSG_ADDON" then
		local prefix,message,_,senderPresenceID=...
		SocialPlus_OnVersionMessage(prefix,message,SocialPlus_ResolveBNetSenderName(senderPresenceID))
	elseif event=="PLAYER_REGEN_ENABLED" then
		-- Whatever the combat guard turned away, collected now.
		--
		-- Unforced on purpose, so the panel-hidden guard still applies: coming
		-- out of a fight with the friends list closed owes nobody a rebuild,
		-- and the dirty flag keeps the debt until it is actually opened.
		if SOCIALPLUS_COMBAT_DEFERRED then
			SOCIALPLUS_COMBAT_DEFERRED=false
			SocialPlus_Update()
		end
	elseif event=="GROUP_ROSTER_UPDATE" then
		SocialPlus_QueueVersionBroadcast()

		-- Repaint, without re-deriving (see the dirty note at the top).
		--
		-- The invite icon dims for somebody already in your group, so the rows
		-- genuinely are stale after this event -- but that state is read per
		-- row while rendering, so the cheap half is the whole fix. Previously
		-- this did the opposite of what it needed: it marked the data dirty,
		-- which bought a full pass later, and never repainted, so the icons
		-- stayed wrong until something unrelated redrew them.
		--
		-- Only while the list is actually up. In combat this event arrives
		-- constantly and the panel is almost never open, so the guard is what
		-- keeps a raid from paying for renders nobody is looking at.
		if FriendsListFrame and FriendsListFrame:IsShown() then
			SocialPlus_UpdateFriends()
		end
	end
end)


-- Handed to the split-out modules, which load after this file.
--
-- Only for names that must NOT become globals. A prefixed one -- FG_*,
-- SocialPlus_* -- is safe to promote in place, and 60-odd already are; a bare
-- GetFriendInfoById is not, because the global namespace is shared with every
-- other addon and with whatever Blizzard adds next.
--
-- The local stays exactly as it was, so none of its call sites in this file
-- change and they keep the upvalue rather than paying for a table lookup.
