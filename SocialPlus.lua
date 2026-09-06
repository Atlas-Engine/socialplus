local ADDON_NAME, ns = ...
local L = ns.L

local LibDD = LibStub("LibUIDropDownMenu-4.0")

local hooks = {}

-- Shared click sound for the settings/group cogwheels and reorder arrows
-- (the same "open a menu" sound as clicking Options from the Escape menu).
-- Guarded since SOUNDKIT entries can vary slightly by client version.
-- Global: the settings panel plays it.
function SocialPlus_PlayMenuClickSound()
	if SOUNDKIT and SOUNDKIT.IG_MAINMENU_OPTION then
		PlaySound(SOUNDKIT.IG_MAINMENU_OPTION)
	end
end

-- Companion "menu closed" sound, played only when a dropdown menu we opened
-- actually closes (not when the search box merely loses focus).
-- Global: the settings panel plays it.
function SocialPlus_PlayMenuCloseSound()
	if SOUNDKIT and SOUNDKIT.IG_MAINMENU_CLOSE then
		PlaySound(SOUNDKIT.IG_MAINMENU_CLOSE)
	end
end

-- "Menu opened" sound for right-click context menus (friend rows, who
-- rows), matching the sound Blizzard's own unit popup makes.
-- Global, not local: SocialPlus_Who.lua plays the same sound.
function SocialPlus_PlayMenuOpenSound()
	if SOUNDKIT and SOUNDKIT.IG_MAINMENU_OPEN then
		PlaySound(SOUNDKIT.IG_MAINMENU_OPEN)
	end
end

-- SetPropagateKeyboardInput, but only when the client will accept it.
--
-- It is protected in combat. Called during a lockdown it does not quietly fail
-- -- the client blocks it and names this addon:
--
--   AddOn 'SocialPlus' tried to call the protected function
--   'FriendsFrameFriendsScrollFrameButton6:SetPropagateKeyboardInput()'
--
-- which is what hovering a friend row mid-fight produced. Every call in this
-- file goes through here, because all six had the same hole and only the one on
-- a Blizzard-owned row happened to be found first.
--
-- Returns whether it went through, so a caller that must not arm itself without
-- the propagate can check rather than assume.
function SocialPlus_SetPropagate(frame,allow)
	if not (frame and frame.SetPropagateKeyboardInput) then return false end
	if InCombatLockdown() then return false end

	frame:SetPropagateKeyboardInput(allow)
	return true
end

-- Set true right before showing the click catcher for menus that should
-- play a close sound when they go away: cogwheel-opened dropdowns
-- (settings button, group-header gear) and the friend/who right-click
-- context menus. Left false for the search-box focus case and the
-- group-header right-click menu, so those stay silent.
-- Global, not local: SocialPlus_Who.lua sets this when it opens its own menu.
SocialPlus_ClickCatcherIsForMenu = false


-- Also expose to global to allow calls from any scope

-- NOTE: _G.SocialPlus_GetInviteStatus will be set after the function is defined below

-- Debug helper to trace id resolution and menu actions (set FG_DEBUG = true to enable)
local FG_DEBUG = false

-- Global: the friend row dropdown lives in its own file now.
function FG_Debug(...)
	if not FG_DEBUG then return end
	local t = {}
	for i=1,select('#',...) do
		local v=select(i,...)
		t[#t+1]=tostring(v)
	end
	if DEFAULT_CHAT_FRAME and DEFAULT_CHAT_FRAME.AddMessage then
		pcall(DEFAULT_CHAT_FRAME.AddMessage,DEFAULT_CHAT_FRAME,"[SocialPlus DEBUG] "..table.concat(t," | "))
	end
end

-- Handle drag stop: determine target group and reorder	
local function Hook(source,target,secure)
	-- MoP Classic: skip hooking UnitPopup_* entirely; its implementation differs from modern retail
	if source=="UnitPopup_ShowMenu" or source=="UnitPopup_OnClick" or source=="UnitPopup_HideButtons" then
		return
	end
	local orig=_G[source]
	hooks[source]=orig
	if secure then
		if type(orig)=="function" then
			hooksecurefunc(source,target)
		end
	else
		if type(orig)=="function" then
			_G[source]=target
		end
	end
end

local SocialPlus_NAME_COLOR=NORMAL_FONT_COLOR

-- Forward declaration for invite helper so early functions can reference it

-- Declared here and defined much further down, because the invite fallback
-- calls it some hundred and seventy lines before its definition. Without this
-- the name resolved to a global nil there, so BNInviteFriend never got a
-- presence ID and that fallback silently did nothing.

-- Same reason: the collapse settle timer, ~1900 lines above the definition,
-- renders instead of re-deriving when nothing changed. Without this
-- declaration that call resolved to a global nil and threw -- which also
-- stranded the in-progress flag, so the friends list rendered empty and stayed
-- that way until a reload (seen live).
--
-- Costs no extra local: the definition below becomes an assignment to THIS
-- name rather than declaring its own, so the file's 200-local ceiling is
-- unmoved.
local SocialPlus_SetCustomGroupOrderFromMove
local SocialPlus_IsRowInDraggedGroup
local SocialPlus_CancelGroupDrag
local SocialPlus_HardResetScrollRows
local SocialPlus_ScheduleCollapseSettle
-- SocialPlus_GetVersionLabelText is a global: it is defined in the settings
-- panel file and called from here, and a global needs no forward declaration.
-- No forward declarations here for the names defined with "function X()"
-- further down.
--
-- "local X" followed later by "function X()" assigns the LOCAL, so the name
-- reads like a global and is invisible to every other file. That is how
-- SocialPlus_HideRowTooltip reached the settings panel as a nil call. All six
-- that had this shape are real globals now; references above their definition
-- resolve at call time, which ordercheck already proves is safe.
-- settings panel in its own file can call it. With a "local" here, the
-- "function SocialPlus_HideRowTooltip()" below would assign THAT instead
-- and the name would be nil everywhere outside this file.

local CURRENT_DB_VERSION = 2

-- Ensure savedvars exist and set reasonable defaults
-- Scroll speed base: the slider value is divided by this to get the internal
-- multiplier.
--
-- Declared up here because SocialPlus_EnsureSavedVars below reads it. It used
-- to sit ~230 lines further down with the other constants, which put it out of
-- scope at the point of use -- so the read compiled to a global lookup, found
-- nil, and every fresh install saved a scroll speed of nil rather than 2.5.
local SCROLL_BASE = 2.5

function SocialPlus_EnsureSavedVars()
    if not SocialPlus_SavedVars then SocialPlus_SavedVars = {} end
    local db = SocialPlus_SavedVars

    -- Version migrations: run each step in order
    if type(db.version)~="number" then
        -- Legacy (pre-versioning) save, or a corrupted/hand-edited version
        -- field: treat as v0, apply defaults below
        db.version = 0
    end

    -- Migration table: add entries here as the schema evolves
    local migrations = {
        -- [1] = function(d) ... end,  -- example future migration
        [2] = function(d)
            -- Old favorites keys were "BNET:<presenceID>" -- stale numeric IDs
            -- that can point at the wrong friend after relog. BattleTags always
            -- contain "#", presence IDs never do. Drop the numeric ones; users
            -- must re-favorite once.
            if type(d.favorites)=="table" then
                for k in pairs(d.favorites) do
                    if k:match("^BNET:") and not k:find("#",1,true) then
                        d.favorites[k]=nil
                    end
                end
            end
        end,
    }
    while db.version < CURRENT_DB_VERSION do
        local next = db.version + 1
        if migrations[next] then migrations[next](db) end
        db.version = next
    end

    -- Existing settings
    if SocialPlus_SavedVars.hide_offline==nil then
        SocialPlus_SavedVars.hide_offline=false
    end
    if SocialPlus_SavedVars.colour_classes==nil then
        SocialPlus_SavedVars.colour_classes=true
    end
    if SocialPlus_SavedVars.show_level==nil then
        SocialPlus_SavedVars.show_level=true
    end
    if type(SocialPlus_SavedVars.scrollSpeed)~="number" then
        SocialPlus_SavedVars.scrollSpeed=SCROLL_BASE
    end

    -- Default ON, but it shows nothing at all unless ArenaPlus is installed
    -- and the friend is on the ladder, so it cannot clutter a tooltip for
    -- somebody who has neither.
    if SocialPlus_SavedVars.pvp_ratings==nil then
        SocialPlus_SavedVars.pvp_ratings=true
    end

    -- Which brackets the block lists, keyed by the same 1-4 ArenaPlus uses.
    -- All of them until told otherwise: someone who only cares about 3v3 can
    -- say so, but guessing that for them would be worse than showing all four.
    -- Separate from the block below it on purpose: the icon beside a name and
    -- the ratings under the tooltip are two different things to want, and one
    -- can be useful without the other.
    -- On by default: it replaces text that was already there rather than
    -- adding something new to a crowded line.
    if SocialPlus_SavedVars.region_flag==nil then
        SocialPlus_SavedVars.region_flag=true
    end

    -- Off by default: the real name is what Blizzard shows and what most
    -- people expect to see. This is for the case where those names are long
    -- enough to crowd the row.
    if SocialPlus_SavedVars.show_battletag==nil then
        SocialPlus_SavedVars.show_battletag=false
    end

    if SocialPlus_SavedVars.pvp_spec_icon==nil then
        SocialPlus_SavedVars.pvp_spec_icon=true
    end

    if type(SocialPlus_SavedVars.pvp_brackets)~="table" then
        SocialPlus_SavedVars.pvp_brackets={ [1]=true,[2]=true,[3]=true,[4]=true }
    end

    -- Default ON for "Prioritize [current client] friends"
    if SocialPlus_SavedVars.prioritize_current_client==nil then
        SocialPlus_SavedVars.prioritize_current_client=true
    end

    SocialPlus_SavedVars.collapsed=type(SocialPlus_SavedVars.collapsed)=="table" and SocialPlus_SavedVars.collapsed or {}
    SocialPlus_SavedVars.groupOrder=type(SocialPlus_SavedVars.groupOrder)=="table" and SocialPlus_SavedVars.groupOrder or {}

    -- Friend online/offline notifications
    SocialPlus_SavedVars.notifications=type(SocialPlus_SavedVars.notifications)=="table" and SocialPlus_SavedVars.notifications or {}
    if SocialPlus_SavedVars.notifications.enabled==nil then
        SocialPlus_SavedVars.notifications.enabled=true
    end
    if SocialPlus_SavedVars.notifications.offline_too==nil then
        SocialPlus_SavedVars.notifications.offline_too=true
    end
    if SocialPlus_SavedVars.notifications.same_version_only==nil then
        SocialPlus_SavedVars.notifications.same_version_only=false
    end
    if SocialPlus_SavedVars.notifications.sound==nil then
        SocialPlus_SavedVars.notifications.sound=true
    end
    local notifyFirstRun=(type(SocialPlus_SavedVars.notifications.mutedGroups)~="table")
    SocialPlus_SavedVars.notifications.mutedGroups=notifyFirstRun and {} or SocialPlus_SavedVars.notifications.mutedGroups
    if notifyFirstRun then
        -- Default OFF for ungrouped friends: only friends the user has sorted
        -- into a group are noisy by default; everyone else stays quiet until
        -- explicitly unmuted via the "General" header's right-click menu.
        SocialPlus_SavedVars.notifications.mutedGroups[L.GROUP_UNGROUPED]=true
    end

    -- SocialPlus-managed favorites (independent of Blizzard's own BNet
    -- favorite, which pins a friend to the top on its own with no
    -- addon-level control -- confirmed live on TBC).
    SocialPlus_SavedVars.favorites=type(SocialPlus_SavedVars.favorites)=="table" and SocialPlus_SavedVars.favorites or {}

    -- NEW: ensure icon profile has a sane default, but don't override a saved value
    if SocialPlus_GetDefaultIconProfileID and SocialPlus_SavedVars.iconProfile==nil then
        SocialPlus_SavedVars.iconProfile=SocialPlus_GetDefaultIconProfileID()
    end

    -- NEW: rebuild icon mapping AFTER SavedVars are ready
    if SocialPlus_RebuildGameIcons then
        SocialPlus_RebuildGameIcons()
    end
end

-- Group / leader helpers
local function SocialPlus_IsPlayerInGroup()
	if IsInGroup and IsInGroup() then
		return true
	end
	if GetNumPartyMembers and GetNumPartyMembers()>0 then
		return true
	end
	if GetNumRaidMembers and GetNumRaidMembers()>0 then
		return true
	end
	return false
end

local function SocialPlus_IsPlayerGroupLeader()
	if UnitIsGroupLeader and UnitIsGroupLeader("player") then
		return true
	end
	if IsPartyLeader and IsPartyLeader() then
		return true
	end
	if IsRaidLeader and IsRaidLeader("player") then
		return true
	end
	return false
end

function SocialPlus_ShouldSuggestInvite()
	return SocialPlus_IsPlayerInGroup() and not SocialPlus_IsPlayerGroupLeader()
end

-- MoP Classic restriction codes (REALM is unused/nil in Classic)
local INVITE_RESTRICTION_NO_GAME_ACCOUNTS=0
local INVITE_RESTRICTION_CLIENT=1
local INVITE_RESTRICTION_LEADER=2
local INVITE_RESTRICTION_FACTION=3
local INVITE_RESTRICTION_REALM=nil
local INVITE_RESTRICTION_INFO=4
local INVITE_RESTRICTION_WOW_PROJECT_ID=5
local INVITE_RESTRICTION_WOW_PROJECT_MAINLINE=6
local INVITE_RESTRICTION_WOW_PROJECT_CLASSIC=7
local INVITE_RESTRICTION_NONE=8
local INVITE_RESTRICTION_MOBILE=9
-- Own code (not a Blizzard restriction ID), split out from the generic
-- INVITE_RESTRICTION_INFO catch-all so icon-fade logic can exclude JUST
-- this reason -- being already in the player's own party/raid isn't
-- really "wrong" with the friend, unlike being offline or otherwise
-- ineligible (reported live: the icon shouldn't dim just because they're
-- already grouped).
local INVITE_RESTRICTION_ALREADY_GROUPED=10

-- Online-status tier for sorting: plain online ranks above DND, which
-- ranks above away/AFK. Matches the same isAFK/isGameAFK/isDND/isGameBusy
-- precedence already used for the status icon (AFK checked before DND).
local function SocialPlus_GetStatusRank(isAFK,isGameAFK,isDND,isGameBusy)
    if isAFK or isGameAFK then return 3 end
    if isDND or isGameBusy then return 2 end
    return 1
end

-- Plain string.lower() is locale-dependent (WoW's C runtime tolower()),
-- which can do unpredictable things to non-ASCII bytes like UTF-8
-- accented characters -- confirmed live: two names tied on every other
-- sort field still sorted in the wrong order, and the only difference was
-- one containing an accented character. Only touch literal A-Z bytes and
-- leave everything else untouched, so behavior is deterministic
-- regardless of the client's locale/accented characters.
--
-- Cached by input string. This is the friends-list sort comparator's own
-- lowercaser -- called twice on every comparison, and table.sort makes
-- O(n log n) of those per group -- so on a large list (reported live:
-- ~460 friends, laggy on open and again after every scroll settle) the
-- same handful of names were being re-scanned and re-closured thousands of
-- times a rebuild for a result that never changes between one comparison
-- and the next. The domain is small and stable (friend names, plus search
-- terms through SocialPlus_NormalizeText below) so nothing here evicts.
-- Bounded, because the keys are not a closed set.
--
-- This caches names, notes, zones and every search term ever typed, so it grows
-- for as long as the session lasts and nothing ever removed anything. Emptied
-- wholesale rather than evicted one at a time: the entries cost a gsub each to
-- rebuild, there is no ordering to reason about, and the friends actually on
-- screen refill it within a redraw or two.
--
-- The ceiling is generous on purpose. A 460-friend list was measured at roughly
-- three keys per friend, so this is several times the working set of the
-- largest list reported and will not clear in ordinary use.
--
-- Count and ceiling live ON the cache table rather than beside it as their own
-- locals. This file's main chunk is at Lua's 200-local limit: two extra names
-- here took it over, and the client reports that as
-- "main function has more than 200 local variables" against line 1, which says
-- nothing about where it came from. The entries hang off `n` and `max` while
-- the cached strings sit under `map`, so an arbitrary key can never collide
-- with the bookkeeping.
local SocialPlus_AsciiLowerCache={ map={}, n=0, max=6000 }

local function SocialPlus_AsciiLower(s)
    local cached=SocialPlus_AsciiLowerCache.map[s]
    if cached then return cached end

    local lowered=(s:gsub("[A-Z]",function(c) return c:lower() end))

    if SocialPlus_AsciiLowerCache.n>=SocialPlus_AsciiLowerCache.max then
        SocialPlus_AsciiLowerCache.map={}
        SocialPlus_AsciiLowerCache.n=0
    end

    SocialPlus_AsciiLowerCache.map[s]=lowered
    SocialPlus_AsciiLowerCache.n=SocialPlus_AsciiLowerCache.n+1
    return lowered
end

-- Whether the mouse is over this frame right now.
--
-- GetMouseFocus is gone from this client -- confirmed live, /run print(GetMouseFocus)
-- answers nil. The single call site guarded itself with "if GetMouseFocus and",
-- so the tooltip resync has been quietly doing nothing for as long as that has
-- been true: a guard that turns a missing API into a dead feature leaves
-- nothing to debug and nothing in the log, which is worse than the error would
-- have been.
--
-- A global rather than a local on purpose. This file's main chunk is at Lua's
-- 200-local limit and one more name there stops the whole addon loading.
--
-- Tried in the order this client is likeliest to have them, and false if it has
-- none -- which is exactly today's behaviour rather than a new failure.
function SocialPlus_MouseIsOver(frame)
	if not frame then return false end

	if frame.IsMouseMotionFocus then
		return frame:IsMouseMotionFocus() and true or false
	end

	if GetMouseFoci then
		for _,focused in ipairs(GetMouseFoci() or {}) do
			if focused==frame then return true end
		end
		return false
	end

	if GetMouseFocus then return GetMouseFocus()==frame end
	return false
end

-- The player's region, as the 1-5 id Battle.net game accounts also use.
--
-- GetCurrentRegion first: it is the client's own answer, it already returns
-- exactly this numbering, and it cannot be absent or spelled unexpectedly.
-- The "portal" CVar is the fallback -- it was the only source here, and it
-- goes through a list of spellings that has to be kept in step with
-- whatever Blizzard sets, returning nil for anything unrecognised.
local playerRegionID=nil

local function SocialPlus_GetClientRegionID()
	if playerRegionID~=nil then
		return playerRegionID
	end

	if GetCurrentRegion then
		local ok,id=pcall(GetCurrentRegion)
		if ok and type(id)=="number" and id>=1 and id<=5 then
			playerRegionID=id
			return playerRegionID
		end
	end

	local portal=nil
	if GetCVar then
		pcall(function()
			portal=GetCVar("portal")
		end)
	end

	if portal then
		portal=portal:lower()
		if portal=="us" or portal=="us-realms" or portal=="test" or portal=="ptr" then
			playerRegionID=1 -- Americas
		elseif portal=="kr" then
			playerRegionID=2 -- Korea
		elseif portal=="eu" then
			playerRegionID=3 -- Europe
		elseif portal=="tw" then
			playerRegionID=4 -- Taiwan
		elseif portal=="cn" or portal=="cn-realms" then
			playerRegionID=5 -- China
		else
			playerRegionID=nil
		end
	end

	return playerRegionID
end

-- Time constants
local ONE_MINUTE=60
local ONE_HOUR=60*ONE_MINUTE
local ONE_DAY=24*ONE_HOUR
local ONE_MONTH=30*ONE_DAY
local ONE_YEAR=12*ONE_MONTH

-- No notifications until the first scans have settled: a snapshot taken too
-- early reads as a false transition. Declared here rather than beside its main
-- users, because a guard far above them needs it in scope.
-- the dead warmup gate this file already had once.
-- the original, and the reader here would go on seeing 0 -- which is exactly
-- An ns alias would not do. A write through an alias updates the alias, not
--
-- Global, not local: SocialPlus_Init.lua writes it and this file reads it.
SocialPlus_ScanWarmupUntil=0

-- Friend list state
local FriendButtons={count=0}
-- Per-friend note-group parse cache, persistent across rebuilds -- keyed
-- by a STABLE identity (BNet presenceID / WoW character name), never by
-- list index (established repeatedly this session: Blizzard's positional
-- index isn't stable across rebuilds, so caching by index could reuse a
-- DIFFERENT friend's parsed groups after a reorder). NoteAndGroups
-- (string-split + table build) ran for every friend on EVERY single
-- rebuild regardless of whether their note actually changed -- on a large
-- friend list (400+), reported live as a real cost. Skipped when the raw
-- note string matches what's cached.
local SocialPlus_BNetNoteCache={}
local SocialPlus_WoWNoteCache={}
-- Set on each rebuild when the search text matches an existing group name
-- (see the "focus" search mode below) -- module-level rather than local to
-- SocialPlus_Update so the divider row's arrow-icon rendering
-- (SocialPlus_UpdateFriendButton, a different function) can also show the
-- correct expand/collapse state during focus mode, not just member
-- visibility.
local SocialPlus_SearchFocusGroup=nil
-- Tracked entirely ourselves, set ONLY inside our own row click handler --
-- Blizzard's FriendsFrame.selectedFriendType/selectedFriend (and
-- GetSelectedFriend()/BNGetSelectedFriend()) reflect client-side state
-- that persists/gets set independent of any click in this session, and
-- even hooking FriendsFrame_SelectFriend doesn't isolate a real user
-- click from Blizzard's own internal calls into it (both tried, both
-- reported live as still auto-highlighting/jumping between friends with
-- no click). This is the only source of truth for "did the player
-- actually pick this row."
-- Global: written by the settings panel.
SocialPlus_SelectedRow=nil
local GroupCount=0
local GroupTotal={}
local GroupOnline={}
local GroupSorted={}
local FriendRequestString=string.sub(FRIEND_REQUESTS,1,-6)

-- [[ Custom group ordering + drag state ]]
local SP_GENERAL_GROUP="\001GENERAL"   -- sentinel: hovering over an ungrouped friend row

-- Virtual "Favorites" group: control-character prefix guarantees it can
-- never collide with a user-typed group name (the create/rename popups are
-- plain EditBoxes, which can't produce \001). It is never written into
-- GroupSorted's persisted order or a friend's note -- it's synthesized at
-- render time from SocialPlus_SavedVars.favorites, so favoriting never
-- touches a friend's real group assignment.
local SP_FAVORITES_GROUP="\001FAVORITES"

-- Same sentinel trick for the automatic "In-game Friends" bucket: native
-- character friends (non-Battle.net) with no group tags render here, right
-- after General, instead of mixing into General. WoW friends the user has
-- explicitly tagged into custom groups keep those groups. Collapse/expand
-- only -- no cogwheel, no context menu, not draggable, never a submenu
-- target.
local SP_INGAME_GROUP="\001INGAME"

-- Friends added during this play session, shown in their own group under
-- Favorites until you file them or log out.
--
-- The client has no "added at" for a friend, so this is worked out by diffing
-- against a snapshot rather than read. The snapshot is retaken at every real
-- login, which is what makes the group mean "this session" exactly, instead of
-- "recently" for some arbitrary value of recently.
--
-- Kept in saved variables rather than in memory so that /reload does not empty
-- it: PLAYER_ENTERING_WORLD says whether it was a login or a reload, and only a
-- login starts a new session.
-- Global, not a file-local: this chunk is at Lua's 200-locals ceiling.
SocialPlus_RECENT_GROUP=string.char(1).."RECENT"

-- Blizzard ships a global FAVORITES string (Mount/Pet Journal use it) --
-- prefer it so the label matches the client's own language/terminology
-- automatically; L.GROUP_FAVORITES is the fallback if that global is ever
-- absent on some client build.
local function SocialPlus_GetFavoritesLabel()
	return FAVORITES or L.GROUP_FAVORITES
end

local SocialPlus_DragSourceGroup=nil   -- non-nil while dragging a group header
local SocialPlus_DragHoverGroup=nil    -- group key under the cursor during a group-header drag
local SocialPlus_DragHoverEverSet=false -- true once hover tracking has fired at least once this drag
local SocialPlus_DragSourceButton=nil
local SocialPlus_DragGhostFrame=nil

-- Global collapse/expand button state
-- SocialPlus_CollapseAllButton is a global: the settings panel reads it, and it
-- is created at runtime, so an ns snapshot taken at load would have been nil.

-- Returns anyCollapsed, anyExpanded across every header row -- custom
-- groups, General, Favorites, and Friend Requests alike (they can all be
-- collapsed individually, so Collapse All/Expand All covers all of them).
local function SocialPlus_GetAnyGroupCollapsed()
	local anyCollapsed=false
	local anyExpanded=false

	if not GroupSorted or not SocialPlus_SavedVars or not SocialPlus_SavedVars.collapsed then
		return false,false
	end

	for _,groupName in ipairs(GroupSorted) do
		if SocialPlus_SavedVars.collapsed[groupName] then
			anyCollapsed=true
		else
			anyExpanded=true
		end
	end

	return anyCollapsed,anyExpanded
end

-- Update icon (+/-), visibility, and mode
-- Global: called from the settings panel.
function SocialPlus_UpdateCollapseAllButtonVisual()
	if not SocialPlus_CollapseAllButton then return end
	if not FriendsFrame or not FriendsFrame:IsShown() then
		SocialPlus_CollapseAllButton:Hide()
		return
	end

	-- Only show on the Friends tab
	if FriendsFrame.selectedTab~=1 then
		SocialPlus_CollapseAllButton:Hide()
		return
	end

	local anyCollapsed,anyExpanded=SocialPlus_GetAnyGroupCollapsed()

	-- No groups at all → just hide it
	if not anyCollapsed and not anyExpanded then
		SocialPlus_CollapseAllButton:Hide()
		return
	end

	SocialPlus_CollapseAllButton:Show()

	-- Rule:
	-- - if there is a mix or all open → show "-" (collapse all)
	-- - if all closed → show "+" (expand all)
	if anyExpanded then
		SocialPlus_CollapseAllButton.mode="COLLAPSE"
		SocialPlus_CollapseAllButton:SetNormalTexture("Interface\\Buttons\\UI-MinusButton-Up")
		SocialPlus_CollapseAllButton:SetPushedTexture("Interface\\Buttons\\UI-MinusButton-Down")
	else
		SocialPlus_CollapseAllButton.mode="EXPAND"
		SocialPlus_CollapseAllButton:SetNormalTexture("Interface\\Buttons\\UI-PlusButton-Up")
		SocialPlus_CollapseAllButton:SetPushedTexture("Interface\\Buttons\\UI-PlusButton-Down")
	end

	SocialPlus_CollapseAllButton:SetHighlightTexture("Interface\\Buttons\\UI-PlusButton-Hilight")
end

-- Get or create the drag ghost frame	
local function SocialPlus_GetDragGhost()
	if not SocialPlus_DragGhostFrame then
		local f=CreateFrame("Frame","SocialPlusDragGhost",UIParent,"BackdropTemplate")
		f:SetFrameStrata("TOOLTIP")
		f:SetFrameLevel(1000)

		f.bg=f:CreateTexture(nil,"BACKGROUND")
		f.bg:SetAllPoints(true)

		f:SetBackdrop({
			edgeFile="Interface\\Tooltips\\UI-Tooltip-Border",
			tile=false,
			edgeSize=8,
		})

        f:SetBackdropBorderColor(0,0,0,0.25)
        -- soft blue ghost background
		f.bg:SetColorTexture(0.15, 0.35, 0.65, 0.28)


		-- header text (group name)
		f.text=f:CreateFontString(nil,"OVERLAY","GameFontNormal")
		f.text:ClearAllPoints()
		f.text:SetPoint("TOP",0,-3)          -- centered at top
		f.text:SetJustifyH("CENTER")

		-- Mirror the real header row's collapse/expand indicator (left)
		-- and cogwheel (right), so the ghost reads like a preview of the
		-- actual row instead of a generic tooltip.
		f.statusIcon=f:CreateTexture(nil,"OVERLAY")
		f.statusIcon:SetSize(14,14)
		f.statusIcon:SetPoint("LEFT",f,"TOPLEFT",6,-11)

		f.gearIcon=f:CreateTexture(nil,"OVERLAY")
		f.gearIcon:SetSize(14,14)
		f.gearIcon:SetTexture("Interface\\Buttons\\UI-OptionsButton")
		f.gearIcon:SetPoint("RIGHT",f,"TOPRIGHT",-6,-11)

		-- Up to 5 sample friend rows (status dot + name + location, mirroring
		-- what the real friend rows show), plus a final dimmed "+N more"
		-- line if the group has more than that.
		f.friendLines={}
		local prevBottom=nil
		for i=1,5 do
			local entry={}
			entry.icon=f:CreateTexture(nil,"OVERLAY")
			entry.icon:SetSize(10,10)
			entry.icon:ClearAllPoints()
			if not prevBottom then
				entry.icon:SetPoint("TOPLEFT",f,"TOPLEFT",8,-22) -- fixed left margin
			else
				entry.icon:SetPoint("TOPLEFT",prevBottom,"BOTTOMLEFT",0,-3)
			end

			-- Mirror the real row's faction/game-client icon and invite
			-- (travel-pass) button, pinned to the ghost's right edge like
			-- the real row (not a fixed offset from the name) so they never
			-- collide with a long name. TOP anchors to the status dot for
			-- the row's vertical position; RIGHT anchors to the frame/the
			-- next icon for horizontal position -- different axes, so this
			-- doesn't stretch the fixed-size textures.
			entry.gameIcon=f:CreateTexture(nil,"OVERLAY")
			entry.gameIcon:SetSize(18,18)
			entry.gameIcon:ClearAllPoints()
			entry.gameIcon:SetPoint("TOP",entry.icon,"TOP",0,0)
			entry.gameIcon:SetPoint("RIGHT",f,"RIGHT",-8,0)

			entry.inviteIcon=f:CreateTexture(nil,"OVERLAY")
			entry.inviteIcon:SetSize(12,12)
			entry.inviteIcon:ClearAllPoints()
			entry.inviteIcon:SetPoint("TOP",entry.icon,"TOP",0,0)
			entry.inviteIcon:SetPoint("RIGHT",entry.gameIcon,"LEFT",-4,0)

			-- Name is pinned between the status dot and the invite icon on
			-- both sides, so it's genuinely clipped (not just visually
			-- crowded) regardless of how long the name is.
			entry.name=f:CreateFontString(nil,"OVERLAY","GameFontHighlightSmall")
			entry.name:ClearAllPoints()
			entry.name:SetPoint("LEFT",entry.icon,"RIGHT",4,0)
			entry.name:SetPoint("RIGHT",entry.inviteIcon,"LEFT",-4,0)
			entry.name:SetJustifyH("LEFT")
			entry.name:SetWordWrap(false)

			entry.location=f:CreateFontString(nil,"OVERLAY","GameFontDisableSmall")
			entry.location:ClearAllPoints()
			entry.location:SetPoint("TOPLEFT",entry.icon,"BOTTOMLEFT",1,-1)
			entry.location:SetJustifyH("LEFT")
			entry.location:SetWordWrap(false)

			f.friendLines[i]=entry
			prevBottom=entry.location
		end

		f.moreLine=f:CreateFontString(nil,"OVERLAY","GameFontDisableSmall")
		f.moreLine:ClearAllPoints()
		f.moreLine:SetPoint("TOPLEFT",prevBottom,"BOTTOMLEFT",0,-3)
		f.moreLine:SetJustifyH("LEFT")

		f:SetAlpha(0.80)
		f:Hide()

		-- Escape cancels an active drag. Only swallows the key (stops
		-- propagation) when a drag is actually in progress; otherwise every
		-- key passes through untouched.
		--
		-- The propagate is asked for FIRST and the keyboard armed only if it
		-- was granted. SetPropagateKeyboardInput is protected in combat, so
		-- the request can be refused -- and a frame holding the keyboard while
		-- propagating nothing swallows every key, for the rest of the session,
		-- in an arena. This frame is built the first time somebody drags, so
		-- combat is a perfectly ordinary time for it to appear.
		--
		-- Asked again on every show, because the one built during combat would
		-- otherwise never get its keyboard at all.
	-- Arm, ask, and disarm again if the answer is no.
		--
		-- The previous shape asked first and armed only if granted, which reads
		-- safer and is broken: SetPropagateKeyboardInput does nothing on a frame
		-- whose keyboard is still off, so the propagate never stuck and the frame
		-- came up armed and swallowing everything. That shipped as 1.15b and took
		-- the search box with it. The keyboard has to be on for the request to mean
		-- anything, so the only safe order is to turn it on, ask, and turn it back
		-- off if the request was refused -- which it is in combat, since the call is
		-- protected.
		f:EnableKeyboard(true)
		if not SocialPlus_SetPropagate(f,true) then f:EnableKeyboard(false) end
		f:HookScript("OnShow",function(self)
			self:EnableKeyboard(true)
			if not SocialPlus_SetPropagate(self,true) then self:EnableKeyboard(false) end
		end)
		f:SetScript("OnKeyDown",function(self,key)
			if key=="ESCAPE" and SocialPlus_DragSourceGroup then
				SocialPlus_SetPropagate(self,false)
				SocialPlus_CancelGroupDrag()
			else
				SocialPlus_SetPropagate(self,true)
			end
		end)

		SocialPlus_DragGhostFrame=f
	end
	return SocialPlus_DragGhostFrame
end

-- Read the invite icon straight off a real, currently-visible travel-pass
-- button instead of guessing a hardcoded texture path, so the ghost's
-- invite icon always matches whatever this client actually uses.
local function SocialPlus_GetInviteIconTexture()
	if FriendsScrollFrame and FriendsScrollFrame.buttons then
		for _,btn in ipairs(FriendsScrollFrame.buttons) do
			if btn.travelPassButton then
				local tex=btn.travelPassButton:GetNormalTexture()
				local path=tex and tex:GetTexture()
				if path then
					return path
				end
			end
		end
	end
	return nil
end

-- Given a visible friends-list button, resolve which group it belongs to.
-- If it's a header row, return that group. If it's a friend row, walk
-- backwards in FriendButtons until we find its group divider.
function SocialPlus_GetGroupKeyFromRow(btn)
	if not btn or not btn.index then
		return nil
	end

	local fb=FriendButtons[btn.index]
	if not fb then
		return nil
	end

	-- If this row *is* a divider, its text is the group key
	if fb.buttonType==FRIENDS_BUTTON_TYPE_DIVIDER then
		return fb.text
	end

	-- Otherwise, scan up to find the nearest divider above
	for i=btn.index-1,1,-1 do
		local row=FriendButtons[i]
		if row and row.buttonType==FRIENDS_BUTTON_TYPE_DIVIDER then
			return row.text
		end
	end

	return nil
end

-- Returns true if this visible row belongs to the group currently being dragged.
local function SocialPlus_IsRowInDraggedGroup(button)
    if not SocialPlus_DragSourceGroup or not button or not button.index then
        return false
    end

    -- Header rows: the group divider itself
    if button.buttonType==FRIENDS_BUTTON_TYPE_DIVIDER then
        local groupName=button.SocialPlusGroupName or SocialPlus_GetGroupKeyFromRow(button)
        return groupName==SocialPlus_DragSourceGroup
    end

    -- Regular friend rows: resolve group via helper
    local groupName=SocialPlus_GetGroupKeyFromRow(button)
    return groupName~=nil and groupName==SocialPlus_DragSourceGroup
end

-- [[ Drag insertion-line indicator ]]
-- One reusable line, repositioned on hover changes (never on OnUpdate).
-- Parented to UIParent (always exists) rather than FriendsScrollFrame --
-- confirmed live that this can be first created from inside a nested
-- Blizzard call chain (FriendsFrameTooltip_Show -> our hooked OnEnter,
-- itself triggered from FriendsList_Update during drag-start) where
-- FriendsScrollFrame was unexpectedly nil. SetPoint below anchors it to
-- specific row buttons regardless of its own parent, so this doesn't
-- affect positioning.
local SocialPlus_DragInsertLine=nil
local function SocialPlus_GetDragInsertLine()
	if not SocialPlus_DragInsertLine then
		local line=UIParent:CreateTexture(nil,"OVERLAY")
		line:SetHeight(2)
		local c=NORMAL_FONT_COLOR
		line:SetColorTexture(c.r,c.g,c.b,0.9)
		line:Hide()
		SocialPlus_DragInsertLine=line
	end
	return SocialPlus_DragInsertLine
end

local function SocialPlus_HideDragInsertLine()
	if SocialPlus_DragInsertLine then
		SocialPlus_DragInsertLine:Hide()
	end
end

local function SocialPlus_GetGroupSortedIndex(name)
	for i,g in ipairs(GroupSorted) do
		if g==name then return i end
	end
	return nil
end

-- Reposition the drop-target line for the currently hovered group,
-- direction-aware to match SocialPlus_SetCustomGroupOrderFromMove: above
-- the hovered group's header when dragging up (source currently sits
-- after it in GroupSorted, so the move will land above it), below the
-- hovered group's last visible row -- or its header, if collapsed/no
-- visible members are on screen -- when dragging down.
local function SocialPlus_UpdateDragInsertionLine(groupKey)
	local line=SocialPlus_GetDragInsertLine()
	if not SocialPlus_DragSourceGroup or not groupKey or groupKey==SocialPlus_DragSourceGroup
		or groupKey==FriendRequestString or groupKey==SP_FAVORITES_GROUP
		or groupKey==SP_INGAME_GROUP then
		line:Hide()
		return
	end

	local sourceIdx=SocialPlus_GetGroupSortedIndex(SocialPlus_DragSourceGroup)
	local targetIdx=SocialPlus_GetGroupSortedIndex(groupKey)
	if not sourceIdx or not targetIdx then
		line:Hide()
		return
	end
	local draggingDown=(sourceIdx<targetIdx)

	local headerButton,lastMemberButton
	if FriendsScrollFrame and FriendsScrollFrame.buttons then
		for _,btn in ipairs(FriendsScrollFrame.buttons) do
			if btn:IsShown() and btn.index then
				if btn.buttonType==FRIENDS_BUTTON_TYPE_DIVIDER and btn.SocialPlusGroupName==groupKey then
					headerButton=btn
				elseif btn.buttonType~=FRIENDS_BUTTON_TYPE_DIVIDER then
					local rowGroup=SocialPlus_GetGroupKeyFromRow(btn)
					if rowGroup==groupKey then
						lastMemberButton=btn
					end
				end
			end
		end
	end

	line:ClearAllPoints()
	if draggingDown then
		local anchor=lastMemberButton or headerButton
		if not anchor then line:Hide() return end
		line:SetPoint("TOPLEFT",anchor,"BOTTOMLEFT",0,0)
		line:SetPoint("TOPRIGHT",anchor,"BOTTOMRIGHT",0,0)
	else
		if not headerButton then line:Hide() return end
		line:SetPoint("BOTTOMLEFT",headerButton,"TOPLEFT",0,0)
		line:SetPoint("BOTTOMRIGHT",headerButton,"TOPRIGHT",0,0)
	end
	line:Show()
end

-- Rebuild GroupSorted based on GroupTotal and saved custom order
local function SocialPlus_ApplyGroupOrder()
	wipe(GroupSorted)

	if not GroupTotal then return end
	local groupOrder=SocialPlus_SavedVars and SocialPlus_SavedVars.groupOrder or nil
	local indexByName={}

	if groupOrder then
		for i,name in ipairs(groupOrder) do
			if type(name)=="string" and name~="" then
				indexByName[name]=i
			end
		end
	end

	local hasFriendReq=false
	local hasGeneral=false
	local hasFavorites=false
	local hasRecent=false
	local hasInGame=false
	local others={}

	for groupName in pairs(GroupTotal) do
		if groupName==FriendRequestString then
			hasFriendReq=true
		elseif groupName==SP_FAVORITES_GROUP then
			hasFavorites=true
		elseif groupName==SocialPlus_RECENT_GROUP then
			hasRecent=true
		elseif groupName==SP_INGAME_GROUP then
			hasInGame=true
		elseif groupName=="" then
			hasGeneral=true
		else
			table.insert(others,groupName)
		end
	end

	-- A group not yet in the persisted custom order -- freshly created,
	-- just renamed, or pre-existing from before this backfill existed --
	-- gets appended here so a later exact-name search recognizes it right
	-- away via the fast groupOrder lookup above, instead of never matching
	-- until the group happened to get drag-reordered at least once
	-- (reported live: a brand-new group's header never showed on search).
	if groupOrder then
		for _,name in ipairs(others) do
			if not indexByName[name] then
				table.insert(groupOrder,name)
				indexByName[name]=#groupOrder
			end
		end
	end

	table.sort(others,function(a,b)
		local ai=indexByName[a] or math.huge
		local bi=indexByName[b] or math.huge
		if ai~=bi then
			return ai<bi       -- custom order from SavedVars wins
		end
		return a<b            -- fallback: alphabetical
	end)

	-- Friend Requests is always index 0 -- pinned above everything,
	-- including Favorites, on request -- and neither it nor Favorites ever
	-- enters the user-reorderable "others" list, so neither can be dragged
	-- or persisted into groupOrder.
	if hasFriendReq then
		table.insert(GroupSorted,FriendRequestString)
	end
	if hasFavorites then
		table.insert(GroupSorted,SP_FAVORITES_GROUP)
	end
	-- Directly under Favorites, and like Favorites never enters the
	-- user-reorderable list: it is not a group you made, and it will be gone by
	-- tomorrow, so a persisted position for it would mean nothing.
	if hasRecent then
		table.insert(GroupSorted,SocialPlus_RECENT_GROUP)
	end
	for _,name in ipairs(others) do
		table.insert(GroupSorted,name)
	end
	-- In-game Friends (ungrouped native friends) always renders right
	-- above General, pinned like the other synthetic buckets.
	if hasInGame then
		table.insert(GroupSorted,SP_INGAME_GROUP)
	end
	if hasGeneral then
		table.insert(GroupSorted,"")
	end
end

-- Move source group based on current visible order (GroupSorted),
-- with direction-aware behavior (drag up = above target, drag down = below).
SocialPlus_SetCustomGroupOrderFromMove=function(source,target)
	if not source or not target or source==target then return end
	-- don’t drag Friend Requests or the implicit General bucket
	if source==FriendRequestString or source=="" then return end
	if target==FriendRequestString or target=="" then return end
	-- Favorites and In-game Friends are synthetic and pinned -- never a
	-- drag source or target, and never persisted into groupOrder.
	if source==SP_FAVORITES_GROUP or target==SP_FAVORITES_GROUP then return end
	if source==SP_INGAME_GROUP or target==SP_INGAME_GROUP then return end

	SocialPlus_EnsureSavedVars()

	-- Build base from current visible order (excluding pinned buckets)
	local base={}
	local sourceIndex,targetIndex

	for _,name in ipairs(GroupSorted or {}) do
		if name~=FriendRequestString and name~="" and name~=SP_FAVORITES_GROUP and name~=SP_INGAME_GROUP then
			table.insert(base,name)
			local idx=#base
			if name==source then sourceIndex=idx end
			if name==target then targetIndex=idx end
		end
	end

	if not sourceIndex or not targetIndex or sourceIndex==targetIndex then
		return
	end

	local originalSourceIndex=sourceIndex
	local originalTargetIndex=targetIndex

	-- Remove source from its old position
	local moving=table.remove(base,sourceIndex)

	-- If source was before target, removing it shifts target left by 1
	if sourceIndex<targetIndex then
		targetIndex=targetIndex-1
	end

	-- Direction-aware insert:
	local insertIndex
	if originalSourceIndex<originalTargetIndex then
		insertIndex=targetIndex+1 -- below target
	else
		insertIndex=targetIndex    -- above target
	end

	-- Safety clamps
	if insertIndex<1 then insertIndex=1 end
	if insertIndex>#base+1 then insertIndex=#base+1 end

	table.insert(base,insertIndex,moving)

	SocialPlus_SavedVars.groupOrder=base

	-- Rebuild & refresh immediately
	SocialPlus_Update(true)
	if FriendsList_Update then
		pcall(FriendsList_Update)
	end
end

local function SocialPlus_OnGroupDragStart(self)
	local group=self and self.SocialPlusGroupName
	-- don’t drag pinned buckets
	if not group or group==FriendRequestString or group=="" or group==SP_FAVORITES_GROUP or group==SP_INGAME_GROUP then
		return
	end

	SocialPlus_DragSourceGroup=group
	SocialPlus_DragSourceButton=self
	SocialPlus_DragHoverEverSet=false
	SocialPlus_HideDragInsertLine()

	-- Immediately refresh so the entire group fades visually
    if FriendsList_Update then
        pcall(FriendsList_Update)
    end

	-- ghost frame
	local ghost=SocialPlus_GetDragGhost()

	-- sample friends from this group
	local headerIndex=self.index
	local samples=SocialPlus_SampleGroupFriends(headerIndex,5) -- soft cap at 5

	-- set header text, with the same "(online/total)" count list headers show
	if ghost.text then
		local counts="("..(GroupOnline[group] or 0).."/"..(GroupTotal[group] or 0)..")"
		ghost.text:SetText(group.." "..counts)
	end

	-- Mirror the header row's current collapse/expand state.
	if ghost.statusIcon then
		if SocialPlus_SavedVars.collapsed[group] then
			ghost.statusIcon:SetTexture("Interface\\Buttons\\UI-PlusButton-UP")
		else
			ghost.statusIcon:SetTexture("Interface\\Buttons\\UI-MinusButton-UP")
		end
	end

	-- set sample friend rows -- status dot + name + location + game icon +
	-- invite icon, mirroring what the real rows show (loop over the up-to-5
	-- entries created in SocialPlus_GetDragGhost, instead of 5 copy-pasted
	-- blocks)
	local inviteTex=SocialPlus_GetInviteIconTexture()
	local extraH=0
	for i,entry in ipairs(ghost.friendLines) do
		local s=samples[i]
		if s then
			local tex
			if s.status=="afk" then
				tex=FRIENDS_TEXTURE_AFK
			elseif s.status=="dnd" then
				tex=FRIENDS_TEXTURE_DND
			elseif s.status=="online" then
				tex=FRIENDS_TEXTURE_ONLINE
			else
				tex=FRIENDS_TEXTURE_OFFLINE
			end
			entry.icon:SetTexture(tex)
			entry.icon:Show()
			entry.name:SetText(s.name)
			entry.name:Show()

			if s.icon then
				entry.gameIcon:SetTexture(s.icon)
				entry.gameIcon:SetAlpha(s.iconAlpha or 1)
				entry.gameIcon:Show()
			else
				entry.gameIcon:Hide()
			end

			if s.icon and inviteTex then
				entry.inviteIcon:SetTexture(inviteTex)
				entry.inviteIcon:SetAlpha(s.inviteAllowed and 1 or 0.4)
				entry.inviteIcon:Show()
			else
				entry.inviteIcon:Hide()
			end

			if s.location and s.location~="" then
				entry.location:SetText(s.location)
				entry.location:Show()
				extraH=extraH+24
			else
				entry.location:SetText("")
				entry.location:Hide()
				extraH=extraH+13
			end
		else
			entry.icon:Hide()
			entry.name:SetText("")
			entry.name:Hide()
			entry.gameIcon:Hide()
			entry.inviteIcon:Hide()
			entry.location:SetText("")
			entry.location:Hide()
		end
	end

	-- "+N more" if the group has more members than the 5 samples shown
	local total=GroupTotal[group] or 0
	if ghost.moreLine then
		if total>5 then
			ghost.moreLine:SetText("+"..(total-5).." more")
			ghost.moreLine:Show()
			extraH=extraH+14
		else
			ghost.moreLine:SetText("")
			ghost.moreLine:Hide()
		end
	end

	-- size ghost: header height + the actual stacked height of the sample
	-- rows shown above (so the ghost respects how much content it's
	-- actually displaying instead of a flat per-line guess)
	local baseW=self:GetWidth()
	local baseH=self:GetHeight()
	extraH=(extraH>0) and (extraH+8) or 0

	ghost:SetSize(baseW,baseH+extraH)
	ghost:Show()

	-- Follow cursor. This is the one legitimate exception to the
	-- no-OnUpdate rule elsewhere in this file -- there's no event for raw
	-- cursor movement, so polling here is unavoidable.
	ghost:SetScript("OnUpdate",function(frame)
		if not SocialPlus_DragSourceGroup then
			frame:Hide()
			frame:SetScript("OnUpdate",nil)
			return
		end
		local x,y=GetCursorPosition()
		local scale=UIParent:GetEffectiveScale()
		frame:ClearAllPoints()
		-- TOPLEFT with an offset instead of CENTER, so the ghost trails
		-- below-right of the cursor instead of covering the hovered row.
		frame:SetPoint("TOPLEFT",UIParent,"BOTTOMLEFT",x/scale+16,y/scale-8)
	end)
end

local function SocialPlus_OnGroupDragStop(self)
	if not SocialPlus_DragSourceGroup then
		return
	end

	-- hide ghost + stop tracking cursor
	if SocialPlus_DragGhostFrame then
		SocialPlus_DragGhostFrame:Hide()
		SocialPlus_DragGhostFrame:SetScript("OnUpdate",nil)
	end
	SocialPlus_HideDragInsertLine()

	local source=SocialPlus_DragSourceGroup
	local target=SocialPlus_DragHoverGroup  -- usually set by OnEnter while dragging
	local hoverEverSet=SocialPlus_DragHoverEverSet -- captured before state resets below

	-- Fallback: if hover target is invalid, infer it from the button we
	-- released on -- but only if hover tracking fired at LEAST once this
	-- drag. If it never fired at all, something about tracking missed
	-- entirely, and guessing a target from wherever the mouse happened to
	-- land is more likely to produce a surprise move than a useful one --
	-- cancel instead.
	if hoverEverSet
		and (not target or target==source or target==FriendRequestString or target=="" or target==SP_FAVORITES_GROUP or target==SP_INGAME_GROUP)
		and self then
		local fallback
		if self.buttonType==FRIENDS_BUTTON_TYPE_DIVIDER then
			fallback=self.SocialPlusGroupName
		else
			fallback=SocialPlus_GetGroupKeyFromRow(self)
		end

		if fallback and fallback~=source and fallback~=FriendRequestString and fallback~="" and fallback~=SP_FAVORITES_GROUP and fallback~=SP_INGAME_GROUP then
			target=fallback
		end
	end

    SocialPlus_DragSourceButton=nil
    SocialPlus_DragSourceGroup=nil
    SocialPlus_DragHoverGroup=nil
    SocialPlus_DragHoverEverSet=false

    -- Refresh rows so drag fade is immediately removed even on cancel
    if FriendsList_Update then
        pcall(FriendsList_Update)
    end

    -- still no valid target, or hover never fired at all? Cancel.
    if not hoverEverSet or not target or target==source
		or target==FriendRequestString or target=="" or target==SP_FAVORITES_GROUP or target==SP_INGAME_GROUP then
        return
    end
	-- Perform the move
	SocialPlus_SetCustomGroupOrderFromMove(source,target)
end

-- Escape-to-cancel: same cleanup as OnGroupDragStop, but never performs a
-- move. Assigned (not "local function") to satisfy the forward
-- declaration near the top of the file, since it's referenced from
-- SocialPlus_GetDragGhost's OnKeyDown handler, defined earlier in the file.
SocialPlus_CancelGroupDrag=function()
	if not SocialPlus_DragSourceGroup then return end

	if SocialPlus_DragGhostFrame then
		SocialPlus_DragGhostFrame:Hide()
		SocialPlus_DragGhostFrame:SetScript("OnUpdate",nil)
	end
	SocialPlus_HideDragInsertLine()

	SocialPlus_DragSourceButton=nil
	SocialPlus_DragSourceGroup=nil
	SocialPlus_DragHoverGroup=nil
	SocialPlus_DragHoverEverSet=false

	if FriendsList_Update then
		pcall(FriendsList_Update)
	end
end

-------------------------------------------------
-- SocialPlus simple search (accent/symbol-insensitive)
-------------------------------------------------
-- SocialPlus_Searchbox is a global: the settings panel reads it, and it is
-- created at runtime, so an ns snapshot taken at load would have been nil.
-- Global: written by the settings panel, which lives in its own file now.
SocialPlus_SearchTerm=nil  -- always normalized or nil

-- Global: the friend row dropdown lives in its own file now.
function SocialPlus_ClearSearch()
	if SocialPlus_Searchbox then
		SocialPlus_Searchbox:SetText("")
		SocialPlus_Searchbox:ClearFocus()
	end
	SocialPlus_SearchTerm=nil
end

-- Accent map at module scope so it is built once, not on every call
local SOCIALPLUS_ACCENT_MAP={
    ["à"]="a",["á"]="a",["â"]="a",["ä"]="a",["ã"]="a",["å"]="a",["ā"]="a",
    ["ç"]="c",
    ["è"]="e",["é"]="e",["ê"]="e",["ë"]="e",["ē"]="e",
    ["ì"]="i",["í"]="i",["î"]="i",["ï"]="i",["ī"]="i",
    ["ñ"]="n",
    ["ò"]="o",["ó"]="o",["ô"]="o",["ö"]="o",["õ"]="o",["ō"]="o",
    ["ù"]="u",["ú"]="u",["û"]="u",["ü"]="u",["ū"]="u",
    ["ý"]="y",["ÿ"]="y",

    -- The capitals as well.
    --
    -- SocialPlus_AsciiLower only folds [A-Z]: it deliberately leaves every
    -- non-ASCII byte alone, because :lower() mangles them (see the note on
    -- the normalizer below). So an accented capital arrives here still
    -- capitalised, misses a table of lower-case keys, and is then removed
    -- outright by the [^a-z0-9] strip -- silently losing the letter rather
    -- than failing. "Élodie" normalised to "lodie" and could not be found by
    -- typing any prefix of her name; "Ämber" became "mber", "LOÏC" became
    -- "loc". Reported against 1.14d.
    ["À"]="a",["Á"]="a",["Â"]="a",["Ä"]="a",["Ã"]="a",["Å"]="a",["Ā"]="a",
    ["Ç"]="c",
    ["È"]="e",["É"]="e",["Ê"]="e",["Ë"]="e",["Ē"]="e",
    ["Ì"]="i",["Í"]="i",["Î"]="i",["Ï"]="i",["Ī"]="i",
    ["Ñ"]="n",
    ["Ò"]="o",["Ó"]="o",["Ô"]="o",["Ö"]="o",["Õ"]="o",["Ō"]="o",
    ["Ù"]="u",["Ú"]="u",["Û"]="u",["Ü"]="u",["Ū"]="u",
    ["Ý"]="y",["Ÿ"]="y",
}

-- Normalize text: lowercase, strip accents, remove non-alphanumerics.
-- Uses SocialPlus_AsciiLower, not plain :lower(), since the latter is
-- locale-dependent and can corrupt non-ASCII bytes before the accent map
-- below ever gets a chance to recognize them (confirmed live: this is the
-- same root cause already fixed for sorting -- "Loïc" failed to match a
-- search for "loic" because :lower() mangled the "ï" byte sequence so it
-- no longer matched SOCIALPLUS_ACCENT_MAP's ["ï"]="i" key, and the
-- unrecognized bytes were then silently stripped instead of converted).
local function SocialPlus_NormalizeText(str)
    if not str then return "" end
    str=SocialPlus_AsciiLower(str)
    str=str:gsub("[%z\1-\127\194-\244][\128-\191]*",function(c)
        return SOCIALPLUS_ACCENT_MAP[c] or c
    end)
    str=str:gsub("[^a-z0-9]","")
    return str
end

-- Search helpers hoisted from SocialPlus_Update (defined once, not per call)
local function startsWith(haystack,needle)
    if not haystack or haystack=="" or not needle or needle=="" then return false end
    return haystack:sub(1,#needle)==needle
end

local function firstWord(s)
    if not s or s=="" then return "" end
    return (s:match("^(%S+)")) or ""
end

-- Plain substring match (not anchored to the start), used for class search
-- so "lock" finds "Warlock" -- unlike names, class shouldn't require
-- typing from the beginning.
local function containsPlain(haystack,needle)
    if not haystack or haystack=="" or not needle or needle=="" then return false end
    return haystack:find(needle,1,true)~=nil
end

-- Detects WoW's "|K...|k" masked-name escape -- a friend's Battle.net
-- account name can transiently be this opaque token before it finishes
-- resolving, from EITHER the C_BattleNet path or the raw BNGetFriendInfo
-- tuple (confirmed live: neither source is reliably safe at an arbitrary
-- point in time, it's a timing issue, not a "use this API instead" one).
-- The chat frame silently renders it as the real name when printed --
-- including through %q in a print() call, which is what made this so
-- hard to pin down -- but plain string comparison/normalization operates
-- on the real, still-masked bytes. Detect and reject the shape outright
-- rather than trust either source blindly.
local function SocialPlus_IsMaskedPlaceholder(s)
    return type(s)=="string" and s:match("^|K.+|k$")~=nil
end

local function SocialPlus_CreateSearchBox()
	if SocialPlus_Searchbox or not FriendsFrame then return end

	SocialPlus_Searchbox=CreateFrame("EditBox","SocialPlusSearchBox",FriendsFrame,"SearchBoxTemplate")
	SocialPlus_Searchbox:SetAutoFocus(false)

		-- Subtle neon glow around the search box
	local glow=CreateFrame("Frame",nil,SocialPlus_Searchbox,"BackdropTemplate")
	glow:SetFrameLevel(SocialPlus_Searchbox:GetFrameLevel()+2)
	-- Top/bottom inset deeper than left/right: the box is only 24px tall,
	-- so the backdrop edge's own line width bleeds past a 1px inset there
	-- much more noticeably than on the 170px-wide sides (confirmed live).
	glow:SetPoint("TOPLEFT",SocialPlus_Searchbox,-4,-3)
	glow:SetPoint("BOTTOMRIGHT",SocialPlus_Searchbox,0,3)
	glow:SetBackdrop({
	edgeFile="Interface\\Buttons\\WHITE8x8",
	edgeSize=1.5, -- thinner neon line
	})
	glow:SetBackdropBorderColor(0,0.65,1,0.7) -- softer, muted neon
	glow:Hide()

	-- Soft bloom (very subtle) -- flush with glow instead of extending
	-- beyond it, so it stays contained within the search box.
	local outer=CreateFrame("Frame",nil,glow,"BackdropTemplate")
	outer:SetFrameLevel(glow:GetFrameLevel()-1)
	outer:SetPoint("TOPLEFT",glow,0,0)
	outer:SetPoint("BOTTOMRIGHT",glow,0,0)
	outer:SetBackdrop({
	edgeFile="Interface\\Buttons\\WHITE8x8",
	edgeSize=2, -- small bloom -- was 5, too wide for the 24px-tall box
})
outer:SetBackdropBorderColor(0,0.5,1,0.15) -- light glow, barely there
outer:Hide()

SocialPlus_SearchGlow=glow
SocialPlus_SearchGlowOuter=outer

	-- Top-right, 24 tall (was 20) so the text isn't cramped vertically. 170 is
	-- the PREFERRED width -- SocialPlus_LayoutSearchBox below shrinks it when
	-- the Friends/Ignore tabs need the room.
	local sbWidth = 170
	SocialPlus_Searchbox:SetSize(sbWidth,24)
	SocialPlus_Searchbox:SetPoint("TOPRIGHT",FriendsFrame,"TOPRIGHT",-9,-61)
	-- Global collapse / expand groups button just left of the search box
	if not SocialPlus_CollapseAllButton then
		SocialPlus_CollapseAllButton=CreateFrame("Button","SocialPlusCollapseAllButton",FriendsFrame)
		SocialPlus_CollapseAllButton:SetSize(18,18)
		SocialPlus_CollapseAllButton:SetPoint("TOPRIGHT",FriendsFrame,"TOPLEFT",22,-64)

		-- Default icon (will be refreshed by SocialPlus_UpdateCollapseAllButtonVisual)
		SocialPlus_CollapseAllButton:SetNormalTexture("Interface\\Buttons\\UI-MinusButton-Up")
		SocialPlus_CollapseAllButton:SetPushedTexture("Interface\\Buttons\\UI-MinusButton-Down")
		SocialPlus_CollapseAllButton:SetHighlightTexture("Interface\\Buttons\\UI-PlusButton-Hilight")

		SocialPlus_CollapseAllButton:SetScript("OnClick",function(self)
	SocialPlus_EnsureSavedVars()

	local anyCollapsed,anyExpanded=SocialPlus_GetAnyGroupCollapsed()

	-- When there is at least one expanded header, we "collapse all". When
	-- everything is collapsed, we "expand all". Covers every header row --
	-- custom groups, General, Favorites, and Friend Requests alike.
	if anyExpanded then
		if GroupSorted then
			for _,groupName in ipairs(GroupSorted) do
				SocialPlus_SavedVars.collapsed[groupName]=true
			end
		end
	else
		if GroupSorted then
			for _,groupName in ipairs(GroupSorted) do
				SocialPlus_SavedVars.collapsed[groupName]=nil
			end
		end
	end

	SocialPlus_HardResetScrollRows()
	SocialPlus_Update(true)
	SocialPlus_ScheduleCollapseSettle()
	SocialPlus_UpdateCollapseAllButtonVisual()
end)


		SocialPlus_CollapseAllButton:Hide()
	end

	-- Configure search box appearance and behavior
	SocialPlus_Searchbox.Instructions:SetText(L.SEARCH_PLACEHOLDER)
	local font,size,flags=SocialPlus_Searchbox:GetFont()
	SocialPlus_Searchbox:SetFont(font,size,flags)
	SocialPlus_Searchbox:SetTextColor(1,1,1)
	SocialPlus_Searchbox.Instructions:SetTextColor(0.5,0.5,0.5)
	-- Placeholder is set a size smaller than the text you type. It shares a
	-- 170px box with the magnifier and the clear "X", leaving roughly 120px,
	-- so at the input size anything longer than a couple of words truncated --
	-- and a hint reading smaller than real input is the usual convention
	-- anyway, so this both fits and looks less like typed text.
	local insFont,insSize,insFlags=SocialPlus_Searchbox.Instructions:GetFont()
	if insFont and insSize then
		SocialPlus_Searchbox.Instructions:SetFont(insFont,insSize-1,insFlags)
	end
	-- Single-line placeholder: truncates with "..." instead of wrapping to
	-- a second line if a locale string is still too long for the box.
	SocialPlus_Searchbox.Instructions:SetWordWrap(false)

	local function SocialPlus_UpdateSearchGlow(self)
		if SocialPlus_SearchGlow then
			local focused=self:HasFocus()
			local hasText=SocialPlus_SearchTerm and true or false
			if focused or hasText then
				SocialPlus_SearchGlow:Show()
				if SocialPlus_SearchGlowOuter then SocialPlus_SearchGlowOuter:Show() end
			else
				SocialPlus_SearchGlow:Hide()
				if SocialPlus_SearchGlowOuter then SocialPlus_SearchGlowOuter:Hide() end
			end
		end
	end

	SocialPlus_Searchbox:SetScript("OnTextChanged",function(self)
		SearchBoxTemplate_OnTextChanged(self)
		-- The template re-shows the placeholder whenever the box is empty,
		-- including while focused -- e.g. after clearing with backspace. Keep
		-- it hidden for as long as the box has focus.
		if self.Instructions and self:HasFocus() then
			self.Instructions:Hide()
		end
		local txt=self:GetText() or ""
		txt=txt:match("^%s*(.-)%s*$") or ""
		local norm=SocialPlus_NormalizeText(txt)
		local newTerm=norm~="" and norm or nil
		local termChanged=(newTerm~=SocialPlus_SearchTerm)
		SocialPlus_SearchTerm=newTerm
		SocialPlus_UpdateSearchGlow(self)
		-- OnTextChanged also fires when the box is (re)initialised as the panel
		-- opens, with the term going nil -> nil. Rebuilding the whole list for
		-- a term that did not change cost one of the 3-4 rebuilds per open,
		-- for no visible difference.
		if termChanged then
			-- Debounced, because a keystroke is not a decision.
			--
			-- The term itself is set above, immediately -- only the rebuild
			-- waits. Typing "warlock" used to be seven full rebuilds, and the
			-- search path is the expensive one: it walks every friend rather
			-- than only the online ones, so on a large list six of those seven
			-- were work for a string the player was still in the middle of
			-- typing. Now the last keystroke wins and the rest cost nothing.
			--
			-- A generation counter rather than a cancellable timer: each
			-- keystroke invalidates the pending one by bumping the count, so
			-- the callback that finally runs is the only one that finds its own
			-- number still current. One closure per keystroke is affordable at
			-- human typing speed -- unlike the per-scroll-tick timers this file
			-- already had to remove -- and each replaces a whole rebuild.
			SOCIALPLUS_SEARCH_GEN=(SOCIALPLUS_SEARCH_GEN or 0)+1
			local myGen=SOCIALPLUS_SEARCH_GEN
			C_Timer.After(0.3,function()
				if SOCIALPLUS_SEARCH_GEN~=myGen then return end
				FriendsList_Update()
			end)
		end
	end)

	SocialPlus_Searchbox:SetScript("OnEditFocusGained",function(self)
		SocialPlus_ShowClickCatcher()
		-- Placeholder clears the moment the box lights up, instead of sitting
		-- under the caret until the first keystroke.
		if self.Instructions then self.Instructions:Hide() end
		SocialPlus_UpdateSearchGlow(self)
	end)

	SocialPlus_Searchbox:SetScript("OnEditFocusLost",function(self)
		-- Back only if nothing was typed -- with text present the placeholder
		-- must stay hidden regardless of focus.
		if self.Instructions and (self:GetText() or "")=="" then
			self.Instructions:Show()
		end
		SocialPlus_UpdateSearchGlow(self)
	end)

	SocialPlus_Searchbox:SetScript("OnEscapePressed",function(self)
		self:SetText("")
		self:ClearFocus()
		SocialPlus_SearchTerm=nil
		SocialPlus_UpdateSearchGlow(self)
		FriendsList_Update()
	end)

end

-- Ensure it’s created when the UI is ready
local SocialPlus_SearchFrame=CreateFrame("Frame")
SocialPlus_SearchFrame:RegisterEvent("PLAYER_LOGIN")
SocialPlus_SearchFrame:RegisterEvent("ADDON_LOADED")
SocialPlus_SearchFrame:SetScript("OnEvent",function(_,event,addon)
	if event=="PLAYER_LOGIN" or addon=="Blizzard_FriendsFrame" then
		SocialPlus_EnsureSavedVars()
		SocialPlus_CreateSearchBox()
		SocialPlus_InitSmoothScroll()
		-- Create settings UI on login / Friends frame ready
		SocialPlus_CreateSettingsButton()
		SocialPlus_CreateSettingsPanel()
	end
end)

-- [[ Faction + BNet/WoW icon helpers ]]
local playerFaction=nil
local FACTION_ICON_PATH=nil

local function FG_InitFactionIcon()
	if not UnitFactionGroup then return end
	playerFaction=select(1,UnitFactionGroup("player"))
	if playerFaction=="Horde" then
		FACTION_ICON_PATH="Interface\\FriendsFrame\\plusmanz-horde"
	elseif playerFaction=="Alliance" then
		FACTION_ICON_PATH="Interface\\FriendsFrame\\plusmanz-alliance"
	else
		FACTION_ICON_PATH=nil
	end
end

-- --------------------------------------------------------------------
-- Icon preset: single custom profile (built-in & shop/chat icons)
-- --------------------------------------------------------------------

local SOCIALPLUS_ICON_IDS_CUSTOM={
	APP ="Interface\\FriendsFrame\\plusmanz-battlenet",

	-- WoW (shop atlas, cropped via texcoords)
	WoW ="Interface\\Shop\\CatalogShopProductLogos2x",

	-- Native Blizzard chat icons
	SC2 ="Interface\\ChatFrame\\UI-ChatIcon-SC2",
	D2  ="Interface\\ChatFrame\\UI-ChatIcon-DiabloIIResurrected",
	D3  ="Interface\\ChatFrame\\UI-ChatIcon-D3",
	HS  ="Interface\\ChatFrame\\UI-ChatIcon-WTCG",
	HOTS="Interface\\ChatFrame\\UI-ChatIcon-HOTS",
	OW  ="Interface\\ChatFrame\\UI-ChatIcon-Overwatch",
	COD ="Interface\\ChatFrame\\UI-ChatIcon-CallOfDutyMWIcon",
	WC3 ="Interface\\ChatFrame\\UI-ChatIcon-Warcraft3Reforged",
	D4  ="Interface\\ChatFrame\\UI-ChatIcon-DiabloImmortal",
}

-- Core icon state (single custom profile)
SOCIALPLUS_ICON_IDS=SOCIALPLUS_ICON_IDS_CUSTOM
SOCIALPLUS_GAME_ICONS=SOCIALPLUS_GAME_ICONS or {}
SOCIALPLUS_DEFAULT_BNET_ICON=(SOCIALPLUS_ICON_IDS and (SOCIALPLUS_ICON_IDS.BNET or SOCIALPLUS_ICON_IDS.APP)) or -6
SOCIALPLUS_UNKNOWN_CLIENTS=SOCIALPLUS_UNKNOWN_CLIENTS or {}

local function SocialPlus_RegisterIcon(clientConst,fileID)
	if clientConst and fileID then
		SOCIALPLUS_GAME_ICONS[clientConst]=fileID
	end
end

local function SocialPlus_PickIcon(key,defaultID)
	local ids=SOCIALPLUS_ICON_IDS or SOCIALPLUS_ICON_IDS_CUSTOM
	local id=ids[key]
	return id or defaultID or SOCIALPLUS_DEFAULT_BNET_ICON
end

function SocialPlus_RebuildGameIcons()
	-- Always use the custom table, no SavedVars / region logic
	SOCIALPLUS_ICON_IDS=SOCIALPLUS_ICON_IDS_CUSTOM
	SOCIALPLUS_DEFAULT_BNET_ICON=(SOCIALPLUS_ICON_IDS and (SOCIALPLUS_ICON_IDS.BNET or SOCIALPLUS_ICON_IDS.APP)) or -6

	if wipe then wipe(SOCIALPLUS_GAME_ICONS) end

	SocialPlus_RegisterIcon(BNET_CLIENT_WOW        or "WoW" ,SocialPlus_PickIcon("WoW" ))
	SocialPlus_RegisterIcon(BNET_CLIENT_SC2        or "S2"  ,SocialPlus_PickIcon("SC2" ))
	SocialPlus_RegisterIcon(BNET_CLIENT_D2         or "OSI" ,SocialPlus_PickIcon("D2"  ))
	SocialPlus_RegisterIcon(BNET_CLIENT_D3         or "D3"  ,SocialPlus_PickIcon("D3"  ))
	SocialPlus_RegisterIcon(BNET_CLIENT_D4    	   or "Fen" ,SocialPlus_PickIcon("D4"  ))
	SocialPlus_RegisterIcon(BNET_CLIENT_WTCG       or "WTCG",SocialPlus_PickIcon("HS"  ))
	SocialPlus_RegisterIcon(BNET_CLIENT_HEROES     or "Hero",SocialPlus_PickIcon("HOTS"))
	SocialPlus_RegisterIcon(BNET_CLIENT_OVERWATCH  or "Pro" ,SocialPlus_PickIcon("OW"  ))
	SocialPlus_RegisterIcon(BNET_CLIENT_CLNT       or "CLNT",SocialPlus_PickIcon("BNET"))
	SocialPlus_RegisterIcon(BNET_CLIENT_COD        or "COD" ,SocialPlus_PickIcon("COD" ))
	SocialPlus_RegisterIcon(BNET_CLIENT_WC3        or "W3"  ,SocialPlus_PickIcon("WC3" ))

	-- Battle.net app / launcher / Remix
	SocialPlus_RegisterIcon(BNET_CLIENT_APP or "App",SocialPlus_PickIcon("APP"))
	SocialPlus_RegisterIcon("BSAp",                 SocialPlus_PickIcon("APP"))
end

-- Initial apply on load
SocialPlus_RebuildGameIcons()

-- TexCoords
SOCIALPLUS_TEXCOORD_BY_ICONPATH={
	-- CatalogShopProductLogos.blp: crop right logo with a bit of padding (DEFAULT)
	--
	-- Cropped tight to the logo art rather than loosely around it. The loose
	-- crop {0.26,0.65,0.10,0.90} left a wide transparent margin, which was
	-- compensated for by drawing the icon in a 64px box -- double every other
	-- icon -- so the art came out the right size while the BOX was twice as
	-- big as it looked. That box is what neighbours anchor against and what
	-- overhangs the row, so the size had to come out of the crop instead.
	--
	-- Measured in a client with /spsim wcrop + wnudge, not derived: the logo
	-- is nowhere near the middle of the region it was being cropped from. Its
	-- centre sits at about v 0.314, well above the 0.50 you get by assuming
	-- the art is centred, which is why every attempt to fix this by resizing
	-- the crop failed -- resizing happens about the crop's own centre, so it
	-- changed how big the logo was without ever moving it onto the row's
	-- centre line.
	["Interface\\Shop\\CatalogShopProductLogos2x"]={0.370,0.565,0.114,0.514},
}

-- Apply a game/faction icon to a button's gameIcon texture
-- If iconPath is nil or empty, hides the icon
local function FG_ApplyGameIcon(button,iconPath,size,point,relPoint,offX,offY)
	if not iconPath or iconPath=="" or not button or not button.gameIcon then
		if button and button.gameIcon then
			button.gameIcon:Hide()
		end
		-- Clear the recorded offset too. Rows are pooled, so leaving the
		-- previous occupant's value behind would misplace anything anchored
		-- against this icon on the next row to reuse this button.
		if button then
			button.SocialPlusIconOffY=nil
		end
		return
	end

	local icon=button.gameIcon
	icon:ClearAllPoints()

	size=size or 24
	point=point or "RIGHT"
	relPoint=relPoint or "RIGHT"
	offX=offX or -30
	offY=offY or 0

	-- No special case for the generic WoW logo any more. It used to be drawn
	-- at size=64 with offX=-8 while every other icon is 30-32 at about -22,
	-- to make up for a loose texture crop that left the art small inside its
	-- box. Sizing the BOX to fix the ART is what broke placement:
	--
	--   * the box is anchored RIGHT->RIGHT, so it is centred on the row, but
	--     at 64px on a ~32px icon row it overhung ~16px into the rows above
	--     and below, and magnified any off-centre art inside the crop 2x;
	--   * the arena swords anchor to this icon's LEFT edge, which for a 64px
	--     box sits at -72 against a crest's -52 -- so the swords jumped ~20px
	--     left on any row that got the logo instead of a crest.
	--
	-- The art keeps its on-screen size via a tighter texcoord (see
	-- SOCIALPLUS_TEXCOORD_BY_ICONPATH); the box now matches every other icon,
	-- so neighbours anchored to it line up whichever variant a friend gets.

	-- Published for anything anchoring itself against this icon (the arena
	-- swords do). Every icon is currently placed on the row's centre line, so
	-- this is 0 in practice and the swords' cancel is a no-op -- it is kept
	-- because a sibling anchored to the icon silently inherits any vertical
	-- shift, and that failure is invisible until someone puts an icon beside
	-- another one. Recording the value keeps it a single source of truth, so
	-- a future icon needing its own placement can't drag those siblings out
	-- of the row the way the 64px logo box did.
	button.SocialPlusIconOffY=offY

	icon:SetPoint(point,button,relPoint,offX,offY)
	icon:SetSize(size,size)



	-- Special texcoords for atlas-based icons
	local tc=SOCIALPLUS_TEXCOORD_BY_ICONPATH[iconPath]
	if tc then
		icon:SetTexCoord(tc[1],tc[2],tc[3],tc[4])
	else
		icon:SetTexCoord(0,1,0,1)
	end

	icon:SetTexture(iconPath)
	icon:Show()
end

-- --------------------------------------------------------------------
-- SocialPlus icon styles
-- Central place to tweak size/position of every icon type
-- --------------------------------------------------------------------
local SocialPlus_IconStyles={
	game={
		size=32,
		point="RIGHT",
		relPoint="RIGHT",
		offX=-21,
		offY=0,
	},
	crest={
		size=30,
		point="RIGHT",
		relPoint="RIGHT",
		offX=-22,
		offY=0,
	},
}

-- Apply an icon to a button using a named style	
local function SocialPlus_ApplyIcon(button,iconPath,styleKey,overrideSize)
	-- styleKey: "game","crest","smallGame", etc.
	local style=SocialPlus_IconStyles[styleKey] or SocialPlus_IconStyles.game
	local size=overrideSize or style.size or 48
	local point=style.point or "RIGHT"
	local relPoint=style.relPoint or "RIGHT"
	local offX=style.offX or -10
	local offY=style.offY or -8

	FG_ApplyGameIcon(button,iconPath,size,point,relPoint,offX,offY)
end

-- Safe BNet client texture helper using clean MoP file-ID icons
local function FG_GetClientTextureSafe(client)
	-- Preferred: explicit file-ID map (gives the crisp icons you tested)
	if client and SOCIALPLUS_GAME_ICONS[client] then
		return SOCIALPLUS_GAME_ICONS[client]
	end

	-- Debug unknown clients once
	if client and FG_DEBUG and not SOCIALPLUS_UNKNOWN_CLIENTS[client] then
		SOCIALPLUS_UNKNOWN_CLIENTS[client]=true
		FG_Debug("Unknown BNet client:",client)
	end

	-- Fallback to Blizzard’s helper (may return atlas/paths)
	if BNet_GetClientTexture then
		local tex=BNet_GetClientTexture(client)
		if tex and tex~="" then
			return tex
		end
	end

	-- Last resort: generic Battle.net logo
	return SOCIALPLUS_DEFAULT_BNET_ICON
end

-- [[ Friends list frame references ]]	
local FriendsScrollFrame
local FriendButtonTemplate

if FriendsListFrameScrollFrame then
	FriendsScrollFrame=FriendsListFrameScrollFrame
	FriendButtonTemplate="FriendsListButtonTemplate"
else
	FriendsScrollFrame=FriendsFrameFriendsScrollFrame
	FriendButtonTemplate="FriendsFrameButtonTemplate"
end

-- Collapsing/expanding a group can shift every row after it by a large
-- amount; hide every pooled row so nothing carries over stale state into
-- the rebuild that follows. This used to ALSO snap the scrollbar to 0 --
-- a "clean slate" workaround from before the real scroll desync causes
-- were found (scroll child height, remainder re-assert, range clamping,
-- all handled in SocialPlus_UpdateFriends now). With those fixed, the
-- snap-to-top was pure leftover harm: every collapse toggle yanked the
-- view back to the top (reported live as jarring). The render's own range
-- clamp already pulls the position in-bounds when the shrunken content
-- no longer reaches that far, so the scroll position is left alone here.
SocialPlus_HardResetScrollRows=function()
	local sf=FriendsScrollFrame
	if not sf then return end
	if sf.buttons then
		for _,btn in ipairs(sf.buttons) do
			btn.index=nil
			btn:Hide()
		end
	end
end

-- The collapse-toggle handlers below used to fire an extra synchronous
-- SocialPlus_Update(true) plus a fresh C_Timer.After closure on every
-- single click, to guard against the stale-row/scrollbar issue above. That
-- meant spam-clicking collapse/expand queued up a new full list rebuild
-- and a new timer object per click instead of coalescing them -- real,
-- avoidable memory/CPU churn under repeated clicks (confirmed live).
-- Debounce the safety-net settle pass the same way scroll-triggered
-- recompute already is elsewhere in this file: cancel any pending one and
-- schedule a single new one, so a rapid burst of clicks only pays for one
-- extra pass total, not one per click.
local SocialPlus_CollapseSettleTimer=nil
SocialPlus_ScheduleCollapseSettle=function()
	if SocialPlus_CollapseSettleTimer then
		SocialPlus_CollapseSettleTimer:Cancel()
	end
	SocialPlus_CollapseSettleTimer=C_Timer.NewTimer(0.15,function()
		SocialPlus_CollapseSettleTimer=nil
		SocialPlus_HardResetScrollRows()
		-- Render unless something genuinely changed, exactly as the scroll
		-- settle does. Measured as 9 of 22 forced data passes in one run.
		--
		-- Whatever scheduled this -- a collapse click, or the panel opening --
		-- has already run a full rebuild of its own moments ago, so the friend
		-- data is current and re-deriving all of it produces the same list at
		-- ~32ms a time. What the settle is actually for is re-rendering after
		-- HardResetScrollRows and letting the content height settle, and the
		-- render does both: the height it clamps against is still right,
		-- because the data behind it has not moved.
		if SOCIALPLUS_DATA_DIRTY then
			SocialPlus_Update(true)
		else
			SocialPlus_UpdateFriends()
		end
	end)
end

-- A single BattleTag can have multiple WoW licenses online at the same
-- time (already established for the faction-preference fix). Returns one
-- entry per currently-online WoW game account linked to this BNet friend
-- (friend-list index), so the invite menu can offer a choice instead of
-- silently inviting whichever one gets picked automatically.
-- Global, not local: SocialPlus_Version.lua needs it.
function SocialPlus_GetOnlineWoWGameAccounts(bnetIndex)
	local accounts={}
	if not (C_BattleNet and C_BattleNet.GetFriendNumGameAccounts and C_BattleNet.GetFriendGameAccountInfo) then
		return accounts
	end
	local num=C_BattleNet.GetFriendNumGameAccounts(bnetIndex) or 0
	for gaIndex=1,num do
		local ga=C_BattleNet.GetFriendGameAccountInfo(bnetIndex,gaIndex)
		if ga and ga.isOnline and ga.clientProgram==BNET_CLIENT_WOW and ga.characterName and ga.characterName~="" then
			table.insert(accounts,{
				characterName=ga.characterName,
				-- Recovered alongside the project ID below: the same broken
				-- payload drops both, and these entries feed the invite
				-- submenu's "Character-Realm" labels.
				realmName=SocialPlus_RepairRealmName(ga.realmName,ga.richPresence),
				className=ga.className,
				level=ga.characterLevel,
				-- Repaired at the point of read -- see SocialPlus_RepairProjectID.
				-- This copy feeds the invite eligibility checks, which reject a
				-- project mismatch, so a broken 0 here blocks inviting someone
				-- you can actually play with.
				wowProjectID=SocialPlus_RepairProjectID(ga.wowProjectID,ga.richPresence),
				factionName=ga.factionName,
				regionID=ga.regionID,
				gameAccountID=ga.gameAccountID,
			})
		end
	end
	return accounts
end

-- [[ Unified invite helpers (WOW + BNET) ]]
-- Global: the friend row dropdown lives in its own file now.
function SocialPlus_PerformInvite(kind,id)
	if not kind or not id then
		return false,L.INVITE_GENERIC_FAIL
	end

	-- Use your existing logic (region, faction, project, canCoop, etc.)
	local allowed,reason=SocialPlus_GetInviteStatus(kind,id)
	if not allowed then
		return false,reason or L.INVITE_GENERIC_FAIL
	end

	if kind=="WOW" then
		-- Normal WoW friend
		local info=FG_GetFriendInfoByIndex(id)
		local name=info and info.name

		-- Mirror GetInviteStatus: only block on explicit false (offline), not nil (unknown)
		if not info or info.connected==false or not name or name=="" then
			return false,L.INVITE_GENERIC_FAIL
		end

		if C_PartyInfo and C_PartyInfo.InviteUnit then
			pcall(C_PartyInfo.InviteUnit,name)
			return true
		end
		return false,L.INVITE_GENERIC_FAIL
	elseif kind=="BNET" then
		-- Battle.net friend -- pick the first ONLINE account that actually
		-- passes the same eligibility checks as the multi-license submenu
		-- (project, faction, region, coop), not just whichever account
		-- C_BattleNet.GetFriendAccountInfo(id).gameAccountInfo considers
		-- "the" one. That single-account field is Blizzard's own pick and
		-- isn't guaranteed to be the current-version/eligible character --
		-- for a friend with more than one WoW license online, the quick-
		-- invite button could show enabled (based on GetInviteStatus, which
		-- resolves differently) yet silently target the WRONG account,
		-- while the right-click submenu (which already iterates every
		-- account) invited correctly (reported live: a TBC friend's quick-
		-- invite button did nothing, but right-click Invite worked fine).
		if not playerFaction then FG_InitFactionIcon() end
		local playerRegionID=SocialPlus_GetClientRegionID()
		local accounts=SocialPlus_GetOnlineWoWGameAccounts(id)
		for _,acct in ipairs(accounts) do
			local factionMismatch=acct.factionName and playerFaction and acct.factionName~=playerFaction
			local projectMismatch=WOW_PROJECT_ID and acct.wowProjectID and acct.wowProjectID~=WOW_PROJECT_ID
			local regionMismatch=acct.regionID and playerRegionID and acct.regionID~=playerRegionID
			local coopBlocked=acct.gameAccountID and CanCooperateWithGameAccount
				and CanCooperateWithGameAccount(acct.gameAccountID)==false
			if not (factionMismatch or projectMismatch or regionMismatch or coopBlocked) then
				local target=acct.characterName
				if acct.realmName and acct.realmName~="" then
					target=target.."-"..acct.realmName
				end
				if C_PartyInfo and C_PartyInfo.InviteUnit then
					pcall(C_PartyInfo.InviteUnit,target)
					return true
				end
				break
			end
		end

		-- Fallback: BNInviteFriend/BNSendGameInvite expect presenceID, not list index.
		-- BNGetFriendInfo(index) returns presenceID as its first value.
		local presenceID=FG_BNGetFriendInfo(id)
		if BNInviteFriend and presenceID then
			pcall(BNInviteFriend,presenceID)
			return true
		end

		return false,L.INVITE_GENERIC_FAIL
	end

	return false,L.INVITE_GENERIC_FAIL
end

function SocialPlus_PerformInviteFromButton(button)
	if not button or not button.buttonType or not button.id then return end

	local kind=nil
	if button.buttonType==FRIENDS_BUTTON_TYPE_WOW then
		kind="WOW"
	elseif button.buttonType==FRIENDS_BUTTON_TYPE_BNET then
		kind="BNET"
	else
		return
	end

	local ok,reason=SocialPlus_PerformInvite(kind,button.id)
	if not ok and reason and UIErrorsFrame and UIErrorsFrame.AddMessage then
		UIErrorsFrame:AddMessage(reason,1,0.1,0.1,1.0)
	end
end

function SocialPlus_InitSmoothScroll()
	local frame=FriendsScrollFrame
	if not frame or not frame.scrollBar then return end

	frame:EnableMouseWheel(true)

	frame:SetScript("OnMouseWheel",function(self,delta)
		local sb=self.scrollBar
		if not sb then return end

		local min,max=sb:GetMinMaxValues()
		local current=sb:GetValue() or 0

		if delta==0 then return end

		-- Slider 1..5 → step 20..80px per notch
		local displayValue=(SocialPlus_SavedVars and SocialPlus_SavedVars.scrollSpeed) or SCROLL_BASE
		displayValue=math.max(1.0,math.min(5.0,tonumber(displayValue) or SCROLL_BASE))
		local step=20+15*(displayValue-1)  -- 1→20, 3→50, 5→80

		local target=current-(delta>0 and step or -step)
		target=math.max(min,math.min(max,target))
		if target==current then return end

		sb:SetValue(target)
	end)
end

-- [[ Friend API wrappers (MoP / modern compatibility) ]]

local function FG_GetNumFriends()
	if C_FriendList and C_FriendList.GetNumFriends then
		return C_FriendList.GetNumFriends()
	end
	return 0
end

local function FG_GetNumOnlineFriends()
	if C_FriendList and C_FriendList.GetNumOnlineFriends then
		return C_FriendList.GetNumOnlineFriends()
	end
	return 0
end

-- Memoised for the frame it is asked in.
--
-- C_FriendList.GetFriendInfoByIndex builds a fresh table on every call, and
-- one WoW friend is read several times to draw a single row: twice inside
-- SocialPlus_UpdateFriendButton, and again in the derivation that decides
-- ordering and grouping. On a list with a few hundred WoW friends that is
-- hundreds of throwaway tables per repaint.
--
-- Keyed on GetTime(), which is constant for the whole of one frame, so the
-- cache empties itself every frame rather than needing to be told when the
-- friend list changed. Anything that reads a friend twice in one frame gets
-- one table; anything reading across frames sees fresh data, same as before.
--
-- Not a correctness change: a value cannot move mid-frame, and a note
-- written by us is not readable back immediately in any case -- which is
-- what SocialPlus_RefreshAfterNoteWrite already exists to handle.
SOCIALPLUS_FRIEND_INFO_CACHE={}
SOCIALPLUS_FRIEND_INFO_FRAME=nil

-- For the rare caller that changes a friend and must re-read inside the same
-- frame rather than waiting for the next one.
function SocialPlus_InvalidateFriendInfo()
	SOCIALPLUS_FRIEND_INFO_CACHE={}
	SOCIALPLUS_FRIEND_INFO_FRAME=nil
end

function FG_GetFriendInfoByIndex(index)
	if C_FriendList and C_FriendList.GetFriendInfoByIndex then
		local now=(GetTime and GetTime()) or 0
		if SOCIALPLUS_FRIEND_INFO_FRAME~=now then
			SOCIALPLUS_FRIEND_INFO_FRAME=now
			SOCIALPLUS_FRIEND_INFO_CACHE={}
		end

		local hit=SOCIALPLUS_FRIEND_INFO_CACHE[index]
		if hit~=nil then return hit end

		local info=C_FriendList.GetFriendInfoByIndex(index)
		SOCIALPLUS_FRIEND_INFO_CACHE[index]=info
		return info
	end
	return nil
end

-- Blizzard's friend-list index is positional, not a stable identity -- the
-- SAME friend can shift from index 6 to index 15 (or anywhere else) if
-- Blizzard reorders its internal list between two of our own refreshes,
-- which happens more often now that online/offline rescans are faster
-- (see afb1bff). Row-identity comparisons that trust the raw index (like
-- deciding whether the tooltip still matches what's under the cursor) need
-- something that survives that reorder instead -- BattleTag for BNet
-- friends, character GUID for WoW friends (reported live: a tooltip
-- briefly flashed a different friend's info while hovering the same row,
-- with the row's own name never changing -- traced to this).
-- Global: the friend row dropdown lives in its own file now.
function SocialPlus_GetRowIdentityKey(buttonType,id)
	if not id then return nil end
	if buttonType==FRIENDS_BUTTON_TYPE_BNET then
		if C_BattleNet and C_BattleNet.GetFriendAccountInfo then
			local acct=C_BattleNet.GetFriendAccountInfo(id)
			return acct and (acct.bnetAccountID or acct.battleTag)
		end
	elseif buttonType==FRIENDS_BUTTON_TYPE_WOW then
		local info=FG_GetFriendInfoByIndex(id)
		return info and (info.guid or info.name)
	end
	return nil
end

local function FG_GetSelectedFriend()
	if C_FriendList and C_FriendList.GetSelectedFriend then
		return C_FriendList.GetSelectedFriend()
	elseif GetSelectedFriend then
		return GetSelectedFriend()
	end
	return 0
end

local function FG_SetFriendNotes(index,note)
	-- The per-frame memo has to go: this changes the very record it caches,
	-- and a reader later in the same frame would otherwise be handed the note
	-- as it was before the write.
	if SocialPlus_InvalidateFriendInfo then SocialPlus_InvalidateFriendInfo() end

	-- Always resolve the real friend first by index
	local info=FG_GetFriendInfoByIndex(index)
	local name=info and info.name or nil

	-- Preferred: legacy API using the friend NAME (stable, no ordering issues)
	if name and name~="" and SetFriendNotes then
		pcall(SetFriendNotes,name,note)
		return
	end

	-- Fallback: if no name but modern API exists, use index-based setter
	if C_FriendList and C_FriendList.SetFriendNotesByIndex then
		pcall(C_FriendList.SetFriendNotesByIndex,index,note)
	end
end

-- [[ Safe BN wrappers for compatibility on older clients ]]
-- Global, not local: SocialPlus_Version.lua needs it.
function FG_BNGetNumFriends()
	if BNGetNumFriends then
		return BNGetNumFriends()
	end
	return 0
end

-- Assigns to the local declared at the top of the file rather than making a
-- second one, which is what lets the earlier caller see it.
function FG_BNGetFriendInfo(idx)
	if BNGetFriendInfo then
		return BNGetFriendInfo(idx)
	end
	return nil
end

local function FG_BNGetFriendInfoByID(id)
	if type(id)~="number" then
		for i=1,FG_BNGetNumFriends() do
			local tt={FG_BNGetFriendInfo(i)}
			if tt then
				for _,v in ipairs(tt) do
					if type(v)=="string" and v==id then
						local presence=tt[1]
						if presence and BNGetFriendInfoByID then
							return BNGetFriendInfoByID(presence)
						end
						return unpack(tt)
					end
				end
			end
		end
		return nil
	end
	if BNGetFriendInfoByID then
		return BNGetFriendInfoByID(id)
	end
	return nil
end

local function FG_BNGetNumFriendInvites()
	if BNGetNumFriendInvites then
		return BNGetNumFriendInvites()
	end
	return 0
end

local function FG_BNGetFriendInviteInfo(idx)
	if BNGetFriendInviteInfo then
		return BNGetFriendInviteInfo(idx)
	end
	return nil
end

local function FG_BNGetSelectedFriend()
	if BNGetSelectedFriend then
		return BNGetSelectedFriend()
	end
	return 0
end

local function FG_BNGetInfo()
	if BNGetInfo then
		return BNGetInfo()
	end
	return nil
end

-- BNet note setter using BN friend LIST INDEX
local function FG_SetBNetFriendNote(index,note)
	-- Either setter, modern one first.
	--
	-- This file reads friend data through C_BattleNet in twenty-odd places and
	-- then wrote notes through the legacy global, which is the one our own
	-- comment below records as being silently dropped. FriendGroups prefers
	-- C_BattleNet.SetFriendNote on this same client, which is good evidence it
	-- exists and works here; the old call stays as the fallback rather than
	-- being replaced, since nothing proves the new one is present everywhere
	-- this addon loads.
	local setNote=(C_BattleNet and C_BattleNet.SetFriendNote) or BNSetFriendNote
	if not setNote then
		return
	end

	local t={FG_BNGetFriendInfo(index)}
	if not t or #t==0 then
		return
	end

	local presenceID=t[1]
	if not presenceID then
		return
	end

	-- REVERTED: passing nil for an empty note (instead of "") was a
	-- speculative fix for a note-not-clearing report that turned out to
	-- have a different cause (SocialPlus_ModifyGroupFromDropdown's own
	-- group-tag bug, fixed separately). nil confirmed live to make
	-- BNSetFriendNote silently no-op instead -- a friend whose note became
	-- fully empty after removing their only group tag stayed stuck in
	-- that group, while one with leftover free text (never hitting this
	-- path) removed fine. Empty string is what actually works.
	pcall(setNote,presenceID,note)
end


-- [[ Class colour helper ]]
-- Reverse-lookup cache: localized class name → internal key (built once on first use)
local SocialPlus_LocalizedClassToKey=nil
local function SocialPlus_BuildClassMap()
	if SocialPlus_LocalizedClassToKey then return end
	SocialPlus_LocalizedClassToKey={}
	if LOCALIZED_CLASS_NAMES_FEMALE then
		for k,v in pairs(LOCALIZED_CLASS_NAMES_FEMALE) do SocialPlus_LocalizedClassToKey[v]=k end
	end
	if LOCALIZED_CLASS_NAMES_MALE then
		for k,v in pairs(LOCALIZED_CLASS_NAMES_MALE) do SocialPlus_LocalizedClassToKey[v]=k end
	end
end

-- LOCALIZED_CLASS_NAMES_MALE/FEMALE only ever reflect the client's own
-- current locale (on a French client they're French, never English), so
-- there's no client-side API to recover the English name from those --
-- hardcode it here so class search can match the English word as a
-- fallback regardless of client language.
local SOCIALPLUS_ENGLISH_CLASS_NAMES={
	WARRIOR="Warrior",PALADIN="Paladin",HUNTER="Hunter",ROGUE="Rogue",
	PRIEST="Priest",DEATHKNIGHT="Death Knight",SHAMAN="Shaman",MAGE="Mage",
	WARLOCK="Warlock",MONK="Monk",DRUID="Druid",
}

-- Searchable class text for a friend: their localized class name, plus the
-- English name too (when it differs) so "shaman" still matches on a
-- non-English client.
local function SocialPlus_BuildClassSearchBlob(class)
	if not class or class=="" then return "" end
	SocialPlus_BuildClassMap()
	local key=SocialPlus_LocalizedClassToKey[class]
	local english=key and SOCIALPLUS_ENGLISH_CLASS_NAMES[key]
	if english and english~=class then
		return class.." "..english
	end
	return class
end

-- MoP Classic shaman blue — stored locally to avoid mutating the shared RAID_CLASS_COLORS table
local SHAMAN_COLOR_CLASSIC={r=0,g=0.44,b=0.87}

local function ClassColourCode(class,returnTable)
	if not class then
		return returnTable and FRIENDS_GRAY_COLOR or string.format("|cFF%02x%02x%02x",FRIENDS_GRAY_COLOR.r*255,FRIENDS_GRAY_COLOR.g*255,FRIENDS_GRAY_COLOR.b*255)
	end
	SocialPlus_BuildClassMap()
	local key=SocialPlus_LocalizedClassToKey[class] or class
	local colour
	if WOW_PROJECT_ID==WOW_PROJECT_CLASSIC and key=="SHAMAN" then
		colour=SHAMAN_COLOR_CLASSIC
	else
		colour=(key~="" and RAID_CLASS_COLORS[key]) or FRIENDS_GRAY_COLOR
	end
	if returnTable then
		return colour
	else
		return string.format("|cFF%02x%02x%02x",colour.r*255,colour.g*255,colour.b*255)
	end
end

-- [[ Scroll helpers ]]
local function SocialPlus_GetTopButton(offset)
	local usedHeight=0
	-- count can be nil right after a wipe (e.g. a search that matched
	-- nothing wipes FriendButtons and nothing re-sets count when zero
	-- rows get added) -- confirmed live as a hard error from the
	-- render-end remainder re-assert.
	for i=1,FriendButtons.count or 0 do
		local buttonHeight=FRIENDS_BUTTON_HEIGHTS[FriendButtons[i].buttonType]
		if usedHeight+buttonHeight>=offset then
			return i-1,offset-usedHeight
		else
			usedHeight=usedHeight+buttonHeight
		end
	end
	return 0,0
end


-- [[ BNet friend detail helper ]]
local function GetFriendInfoById(id)
	local accountName,characterName,class,level,isFavoriteFriend,isOnline,
		bnetAccountId,client,canCoop,wowProjectID,lastOnline,
		isAFK,isGameAFK,isDND,isGameBusy,mobile,zoneName,gameText,realmName,regionID,
		factionName,battleTag

	if C_BattleNet and C_BattleNet.GetFriendAccountInfo then
		local accountInfo=C_BattleNet.GetFriendAccountInfo(id)
		if accountInfo then
			accountName=accountInfo.accountName
			isFavoriteFriend=accountInfo.isFavorite
			bnetAccountId=accountInfo.bnetAccountID
			isAFK=accountInfo.isAFK
			isGameAFK=accountInfo.isGameAFK
			isDND=accountInfo.isDND
			isGameBusy=accountInfo.isGameBusy
			-- C_BattleNet's own isAFK/isDND come back false (not nil) even
			-- when wrong on this client, so a nil-check can't tell a real
			-- "not away" from "field unpopulated" -- confirmed live: it let
			-- a friend who was genuinely DND still read as online. Revert to
			-- the original unconditional fallback: BNGetFriendInfo (pos
			-- 10/11) and BNGetGameAccountInfo (pos 18/19) are what actually
			-- reflect true AFK/DND for most friends on this client family.
			--
			-- Positional destructure rather than {tuple} wrappers. These two
			-- calls run once per online friend per rebuild, and wrapping each
			-- in a table threw away two ~19-slot tables per friend every time
			-- -- roughly 1700 of them per rebuild on an 800-friend list. That
			-- is the same GC churn SocialPlus_GetBNetSortName was rewritten to
			-- avoid ("reported live as GC-churn memory peaks"), and collecting
			-- it is exactly what a lag SPIKE looks like.
			--
			-- Same positions as before: BNGetFriendInfo 6=gameAccountID,
			-- 10=isAFK, 11=isDND; BNGetGameAccountInfo 18=isGameAFK,
			-- 19=isGameBusy.
			if BNGetFriendInfo then
				local _,_,_,_,_,gameAcctId,_,_,_,ftAFK,ftDND=BNGetFriendInfo(id)
				isAFK=ftAFK or false
				isDND=ftDND or false
				if gameAcctId and BNGetGameAccountInfo then
					local _,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,gAFK,gBusy=
						BNGetGameAccountInfo(gameAcctId)
					isGameAFK=gAFK or false
					isGameBusy=gBusy or false
				end
			end
			-- Carried so the row can show it instead of a Real ID name, which
			-- arrives as an opaque token (see SocialPlus_GetBNetButtonNameText).
			-- This call already holds it; reading it again from the row would be
			-- another GetFriendAccountInfo per visible friend.
			battleTag=accountInfo.battleTag

			mobile=accountInfo.isWowMobile
			zoneName=accountInfo.areaName
			lastOnline=accountInfo.lastOnlineTime

			local gameAccountInfo=accountInfo.gameAccountInfo

			-- A single BattleTag can have multiple linked WoW licenses/
			-- characters (e.g. one Horde, one Alliance) -- GetFriendAccountInfo
			-- only ever returns whichever ONE Blizzard considers "current",
			-- not necessarily the one relevant to the viewing player. Prefer
			-- whichever linked game account matches the player's own faction
			-- -- but GetFriendNumGameAccounts/GetFriendGameAccountInfo
			-- enumerate EVERY linked license, including ones the friend
			-- isn't currently playing at all, not just simultaneously active
			-- sessions. Without also requiring the candidate to be online,
			-- this could silently substitute in a same-faction character
			-- the friend isn't even logged into right now, showing the
			-- wrong faction/class/everything for whichever character they
			-- actually ARE connected on (confirmed live: a friend online
			-- only on their Horde Rogue showed an Alliance faction icon,
			-- from an offline Alliance license on the same BattleTag).
			if C_BattleNet.GetFriendNumGameAccounts and C_BattleNet.GetFriendGameAccountInfo then
				if not playerFaction then FG_InitFactionIcon() end
				local numGameAccounts=C_BattleNet.GetFriendNumGameAccounts(id) or 0
				if numGameAccounts>1 and playerFaction then
					for gaIndex=1,numGameAccounts do
						local candidate=C_BattleNet.GetFriendGameAccountInfo(id,gaIndex)
						if candidate and candidate.isOnline and candidate.factionName==playerFaction then
							gameAccountInfo=candidate
							break
						end
					end
				end
			end

			if gameAccountInfo then
				-- Which region that character plays in, for the row's flag.
				-- Taken here because this call already has it: reading it again
				-- from the row would be a second GetFriendAccountInfo per
				-- visible friend, which is the cost this function exists to
				-- avoid.
				regionID=gameAccountInfo.regionID
				-- Same reasoning as regionID: this call already holds it. The
				-- rebuild's per-friend pass otherwise made a SECOND
				-- C_BattleNet.GetFriendAccountInfo purely to read this one
				-- field, for every online same-version friend -- and
				-- "prioritise current client" is on by default, so that was
				-- most of the list.
				factionName=gameAccountInfo.factionName

				isOnline=gameAccountInfo.isOnline
				characterName=gameAccountInfo.characterName
				class=gameAccountInfo.className
				level=gameAccountInfo.characterLevel
				client=gameAccountInfo.clientProgram
				wowProjectID=gameAccountInfo.wowProjectID
				gameText=gameAccountInfo.richPresence
				zoneName=gameAccountInfo.areaName
				realmName=gameAccountInfo.realmName
			end

			-- Blizzard's "default" game-account summary above can come back
			-- with a real WoW client but a garbage project ID (0, not a
			-- valid expansion) and no character name at all -- confirmed
			-- live, consistently, for one specific friend while every other
			-- friend resolved fine. The per-account enumeration API (used a
			-- few lines below for multi-license faction disambiguation) had
			-- this friend's real, complete data even when the "default"
			-- summary didn't. Fall back to it whenever the summary looks
			-- incomplete for someone we otherwise know is in WoW.
			if not characterName or characterName=="" or not wowProjectID or wowProjectID==0 then
				local acct=SocialPlus_GetOnlineWoWGameAccounts(id)[1]
				if acct then
					characterName=acct.characterName
					class=acct.className
					level=acct.level
					wowProjectID=acct.wowProjectID
					realmName=acct.realmName
					client=BNET_CLIENT_WOW

					-- These two as well, from the SAME account as the name above.
					--
					-- They were left behind, still holding whatever the summary we
					-- just rejected had put there. So the row and the tooltip drew a
					-- character from one game account beside a region flag and a
					-- faction crest from another -- and when the broken summary
					-- carried neither, the flag simply vanished for that friend.
					--
					-- Every other field here is taken from `acct` precisely so the
					-- line describes one account; these two were the exception by
					-- omission rather than on purpose.
					regionID=acct.regionID
					factionName=acct.factionName
				end
			end

			local coopArg=nil
			if gameAccountInfo and gameAccountInfo.gameAccountID then
				coopArg=gameAccountInfo.gameAccountID
			elseif bnetAccountId then
				coopArg=bnetAccountId
			end

			if coopArg and CanCooperateWithGameAccount then
				canCoop=CanCooperateWithGameAccount(coopArg)
			else
				canCoop=nil
			end
		end
	end

	-- Repaired once here, after every branch above has had its chance to set
	-- the field, so all ~13 downstream "same version?" comparisons keep working
	-- unchanged -- see SocialPlus_RepairProjectID for why a raw 0 is worse than
	-- a nil. Deliberately after the assignments and before the return: the
	-- multi-account branch above can overwrite wowProjectID with its own copy.
	wowProjectID=SocialPlus_RepairProjectID(wowProjectID,gameText)
	-- Same broken-payload recovery for the realm, and it must run BEFORE the
	-- composition below -- that is what puts " - <realm>" on the row's
	-- location line, so a realm recovered afterwards would never reach it.
	realmName=SocialPlus_RepairRealmName(realmName,gameText)

	if realmName and realmName~="" then
		if zoneName and zoneName~="" then
			zoneName=zoneName.." - "..realmName
		else
			zoneName=realmName
		end
	end

	-- regionID and factionName last, so callers that unpack only the first
	-- nineteen are untouched by their arrival.
	return accountName,characterName,class,level,isFavoriteFriend,isOnline,
		bnetAccountId,client,canCoop,wowProjectID,lastOnline,
		isAFK,isGameAFK,isDND,isGameBusy,mobile,zoneName,gameText,realmName,regionID,
		factionName,battleTag
end

-- [[ BNet button name text builder ]]

local function SocialPlus_GetBNetButtonNameText(accountName,client,canCoop,characterName,class,level,realmName,battleTag)
	local nameText

	-- Optionally swap a Real ID name for the BattleTag.
	--
	-- Only the part before the "#": a non-Real ID friend already shows exactly
	-- that, so this makes every row read the same way rather than mixing
	-- "Rurkk" with "Rurkk#0347".
	--
	-- Guarded on the discriminator being present so a BattleTag that somehow
	-- arrives without one is left alone rather than blanked.
	if SocialPlus_SavedVars and SocialPlus_SavedVars.show_battletag
		and type(battleTag)=="string" and battleTag~="" then
		local short=battleTag:match("^(.-)#") or battleTag
		if short~="" then accountName=short end
	end

	-- NOT abbreviated, and it cannot be.
	--
	-- Real ID friends do not arrive as a name at all: Blizzard hands out an
	-- opaque substitution token ("|Kj58|k", seven characters) and the CLIENT
	-- swaps the real name in when the font string is drawn. Confirmed live by
	-- printing the raw value. So "Sacha Bourassa-Beaudoin" never exists as a
	-- Lua string here, and no amount of pattern matching can shorten it to
	-- "Sacha B." -- the addon never sees those characters.
	--
	-- Anything that prints the token appears to disprove this, because print
	-- goes through the same substitution. Compare #accountName, not its text.

	-- Class color, when known and enabled, applies to the WHOLE line --
	-- the Battle.net name too, not just the "(CharacterName)" part -- so
	-- "Color names by class" reads as one consistent color per friend
	-- instead of a colored name tucked inside an unrelated-colored tag.
	local classColor=(client==BNET_CLIENT_WOW) and SocialPlus_SavedVars.colour_classes and ClassColourCode(class)

	-- Level prefix ("L90"), left of the BattleTag -- LEVEL_ABBR was tried
	-- first assuming it'd be Blizzard's own localized "L%d" global, but on
	-- this client it's actually "Lvl %d" (reported live), not the compact
	-- tag look wanted here, so "L" is hardcoded instead. Colored to match
	-- the BattleTag's own blue (FRIENDS_BNET_NAME_COLOR, read live so it
	-- always matches Blizzard's actual color exactly), not the class color
	-- -- kept as its own self-contained code (closed before the name
	-- starts) so it stays outside whatever color wraps the rest of the line.
	local levelPrefix=""
	if client==BNET_CLIENT_WOW and SocialPlus_SavedVars.show_level and level and level~=0 then
		local bnetHex=string.format("|cFF%02x%02x%02x",
			FRIENDS_BNET_NAME_COLOR.r*255,FRIENDS_BNET_NAME_COLOR.g*255,FRIENDS_BNET_NAME_COLOR.b*255)
		levelPrefix=bnetHex..string.format("L%d",level).."|r "
	end

	if accountName and accountName~="" then
		if classColor then
			nameText=levelPrefix..classColor..accountName..FONT_COLOR_CODE_CLOSE
		else
			nameText=levelPrefix..accountName
		end
	else
		nameText=levelPrefix..UNKNOWN
	end

	if characterName and characterName~="" then
		-- Realm deliberately left off here (on request) -- it's already
		-- shown in this row's zone/location line and in the tooltip, so
		-- appending it a third time just ate into the row's limited width
		-- for no benefit (and was part of what pushed the note icon off
		-- the end of long names).
		--
		-- Blizzard's own CANNOT_COOPERATE_LABEL ("*") used to be appended
		-- here too when canCoop was false -- dropped on request (it read as
		-- a stray/broken character, not a meaningful indicator, in this
		-- row). Invite eligibility still checks the real canCoop flag
		-- elsewhere (SocialPlus_GetInviteStatus); this only affects the
		-- displayed name.
		local charLabel=characterName

		if client==BNET_CLIENT_WOW then
			if classColor then
				nameText=nameText.." "..classColor.."("..charLabel..")"..FONT_COLOR_CODE_CLOSE
			else
				nameText=nameText.." ("..charLabel..")"
			end
		else
			nameText=nameText.." "..FRIENDS_OTHER_NAME_COLOR_CODE.."("..charLabel..")"..FONT_COLOR_CODE_CLOSE
		end
	end

	return nameText
end

-- Returns up to maxCount {name=coloredNameString, status="online"/"afk"/
-- "dnd"/"offline", location=zoneOrRichPresenceText, icon=factionOrClientIconPath,
-- iconAlpha=number, inviteAllowed=bool} tables for the drag ghost, mirroring
-- the same status/location/game-icon/invite detail the real rows show.
function SocialPlus_SampleGroupFriends(headerIndex,maxCount)
	local samples={}
	if not headerIndex or not FriendButtons or not maxCount or maxCount<=0 then
		return samples
	end

	local total=FriendButtons.count or 0
	for i=headerIndex+1,total do
		local row=FriendButtons[i]
		if not row or row.buttonType==FRIENDS_BUTTON_TYPE_DIVIDER then
			break -- end of this group
		end

		local display,status,location,icon,iconAlpha,inviteAllowed

		if row.buttonType==FRIENDS_BUTTON_TYPE_WOW then
			if FG_GetFriendInfoByIndex then
				local info=FG_GetFriendInfoByIndex(row.id)
				if info then
					display=info.name or info.name_with_realm or info.characterName or info.nameText
					if not info.connected then
						status="offline"
					elseif info.dnd then
						status="dnd"
					elseif info.afk then
						status="afk"
					else
						status="online"
					end
					location=info.area or ""

					if info.connected then
						local wowAllowed=SocialPlus_GetInviteStatus and SocialPlus_GetInviteStatus("WOW",row.id)
						icon=FACTION_ICON_PATH
						iconAlpha=wowAllowed and 1 or 0.4
						inviteAllowed=wowAllowed and true or false
					end
				end
			end

		elseif row.buttonType==FRIENDS_BUTTON_TYPE_BNET then
			if GetFriendInfoById and SocialPlus_GetBNetButtonNameText then
				local id=row.id
				local accountName,characterName,class,level,isFavoriteFriend,
					isOnline,bnetAccountId,client,canCoop,wowProjectID,lastOnline,
					isAFK,isGameAFK,isDND,isGameBusy,mobile,zoneName,gameText,realmName=
					GetFriendInfoById(id)

				if accountName or characterName then
					display=SocialPlus_GetBNetButtonNameText(
						accountName,client,canCoop,characterName,class,level,realmName
					)
					if not isOnline then
						status="offline"
					elseif isDND or isGameBusy then
						status="dnd"
					elseif isAFK or isGameAFK then
						status="afk"
					else
						status="online"
					end
					location=(mobile and LOCATION_MOBILE_APP) or zoneName or gameText or ""

					if isOnline then
						-- Same faction-crest-vs-client-logo resolution used
						-- by the real row rendering (button.gameIcon).
						local iconPath
						local acct,ga
						if C_BattleNet and C_BattleNet.GetFriendAccountInfo then
							acct=C_BattleNet.GetFriendAccountInfo(id)
							ga=acct and acct.gameAccountInfo or nil
						end
						local hasRealm=(realmName and realmName~="")
							or (ga and ga.realmName and ga.realmName~="")
						local friendFaction=ga and ga.factionName or nil

						-- Unknown faction falls through to the client logo, same
						-- as the real row -- see the note there on why the
						-- player's own crest is not an acceptable stand-in.
						if client==BNET_CLIENT_WOW and wowProjectID==WOW_PROJECT_ID and hasRealm then
							if friendFaction=="Horde" then
								iconPath="Interface\\FriendsFrame\\plusmanz-horde"
							elseif friendFaction=="Alliance" then
								iconPath="Interface\\FriendsFrame\\plusmanz-alliance"
							end
						end
						if not iconPath then
							iconPath=FG_GetClientTextureSafe(client)
						end

						local bnetAllowed=SocialPlus_GetInviteStatus and SocialPlus_GetInviteStatus("BNET",id)
						local fadeWowIcon=(client==BNET_CLIENT_WOW and not bnetAllowed)

						icon=iconPath
						iconAlpha=fadeWowIcon and 0.4 or 1
						inviteAllowed=bnetAllowed and true or false
					end
				end
			end
		end

		if display and display~="" then
			samples[#samples+1]={
				name=display,
				status=status or "offline",
				location=location or "",
				icon=icon,
				iconAlpha=iconAlpha or 1,
				inviteAllowed=inviteAllowed or false,
			}
			if #samples>=maxCount then
				break
			end
		end
	end

	return samples
end


-- [[ Core per-row button update ]]
local function SocialPlus_UpdateFriendButton(button)
	local index=button.index
	button.buttonType=FriendButtons[index].buttonType
	button.id=FriendButtons[index].id

	-- Is this row still drawing the friend it was built for?
	--
	-- SocialPlus_ListShape catches the reorders that change a count, which is
	-- all of the ones we can name. This catches the rest by asking the only
	-- question that cannot be got wrong: the index says this friend, the row
	-- was built for that friend, do they match. Free on the happy path -- the
	-- lookup is one raw call for the ~20 rows actually on screen, and the WoW
	-- one is memoised for the frame already.
	--
	-- Only a POSITIVE mismatch counts. An index that resolves to nothing at
	-- all means the list shrank, which moves a count, which the shape test
	-- has already turned into a real derivation -- whereas treating a
	-- transiently unresolved name as a mismatch would force one derivation
	-- per render for as long as it stayed unresolved.
	local rowKey=FriendButtons[index].key
	if rowKey then
		local nowKey
		if button.buttonType==FRIENDS_BUTTON_TYPE_BNET then
			nowKey=FG_BNGetFriendInfo(button.id)
		elseif button.buttonType==FRIENDS_BUTTON_TYPE_WOW then
			local rowInfo=FG_GetFriendInfoByIndex(button.id)
			nowKey=rowInfo and rowInfo.name
		end
		if nowKey and nowKey~=rowKey then
			SOCIALPLUS_ROWS_STALE=true
		end
	end
	local height=FRIENDS_BUTTON_HEIGHTS[button.buttonType]
	local nameText,nameColor,infoText,isFavoriteFriend
	local hasTravelPassButton=false

	-- Hard reset icon so we don't see any Blizzard leftovers for a frame
	if button.gameIcon then
		button.gameIcon:SetAlpha(0)
		button.gameIcon:SetTexture(nil)
		button.gameIcon:SetSize(32,32) -- baseline, our ApplyIcon will overwrite
	end

	-- Clear per-button friend metadata (used by custom menu)
	button.rawName=nil
	button.accountName=nil
	button.characterName=nil
	button.realmName=nil
	button.SocialPlusRegionID=nil

	-- Put the name field back the way Blizzard's template had it.
	--
	-- Friend rows re-anchor it below, pinning it between the status dot and
	-- whichever icon is leftmost, so it clips against the icons actually on
	-- that row. Rows are pooled, and a GROUP HEADER reuses this same field for
	-- its "(3/5)" counts while relying on the original layout -- so without
	-- restoring it here, a header landing on a recycled friend row would
	-- inherit an anchor pointing at a faction crest that is no longer there.
	--
	-- Captured once, on first sight, rather than hardcoded: the template owns
	-- these numbers, not us. The width is only re-applied when the original had
	-- a single anchor -- with two, the width is derived from them, and forcing
	-- one would fight the anchors we just restored.
	if button.name then
		if not button.SocialPlusNameAnchors then
			local pts={}
			for i=1,(button.name.GetNumPoints and button.name:GetNumPoints() or 0) do
				pts[i]={button.name:GetPoint(i)}
			end
			button.SocialPlusNameAnchors=pts
			button.SocialPlusNameWidth=(#pts<2) and button.name:GetWidth() or nil
		end
		if #button.SocialPlusNameAnchors>0 then
			button.name:ClearAllPoints()
			for _,p in ipairs(button.SocialPlusNameAnchors) do
				button.name:SetPoint(unpack(p))
			end
			if button.SocialPlusNameWidth then
				button.name:SetWidth(button.SocialPlusNameWidth)
			end
		end
	end
	button.SocialPlusGroupName=nil -- only used on divider (group header) rows

	if button.SocialPlusGroupGearButton then
		button.SocialPlusGroupGearButton:Hide()
	end

	-- Rows are pooled/recycled across types (a button previously showing a
	-- friend's note icon can get reused as a group divider) -- default to
	-- hidden here; the BNET/WOW branch below re-shows it when applicable.
	if button.SocialPlusNoteIcon then
		button.SocialPlusNoteIcon:Hide()
	end
	-- Same pooling hazard: without this, a row that showed the arena icon keeps
	-- showing it after being recycled as a divider or a non-arena friend.
	if button.SocialPlusArenaIcon then
		button.SocialPlusArenaIcon:Hide()
	end
	-- The same pooling hazard for the flag beside it.
	if button.SocialPlusRegionFlag then
		button.SocialPlusRegionFlag:Hide()
	end
	-- Stale-state hazard again: a recycled row must not inherit the previous
	-- friend's zone, or a non-arena friend can show the swords.
	button.SocialPlusZoneName=nil

	-- And the recently-added X, for the same reason.
	--
	-- It is shown or hidden in the DIVIDER branch below, and that branch only
	-- runs for rows that are headers on THIS draw. A row that was the Recently
	-- Added header and is now an ordinary friend never reaches the line that
	-- would hide it, so the X stayed where it was -- which is how it came to sit
	-- beside a name in Favorites after the last recent friend was given a group
	-- and the header stopped being drawn at all.
	if button.spRecentClear then
		button.spRecentClear:Hide()
	end

	-- Update based on button type
	if button.buttonType==FRIENDS_BUTTON_TYPE_WOW then
		local info=FG_GetFriendInfoByIndex(FriendButtons[index].id)
		if info and info.connected then
			button.background:SetColorTexture(
				FRIENDS_WOW_BACKGROUND_COLOR.r,
				FRIENDS_WOW_BACKGROUND_COLOR.g,
				FRIENDS_WOW_BACKGROUND_COLOR.b,
				FRIENDS_WOW_BACKGROUND_COLOR.a
			)
			if info.afk then
				button.status:SetTexture(FRIENDS_TEXTURE_AFK)
			elseif info.dnd then
				button.status:SetTexture(FRIENDS_TEXTURE_DND)
			else
				button.status:SetTexture(FRIENDS_TEXTURE_ONLINE)
			end

			nameColor=SocialPlus_SavedVars.colour_classes and ClassColourCode(info.className,true) or FRIENDS_WOW_NAME_COLOR

			-- "L90 Rannzz (Death Knight)" -- matches the BNet row format
			-- (level prefix, name, class in parentheses) instead of
			-- Blizzard's own "Name, Level 90 Death Knight" (reported live).
			-- Name portion wrapped in an explicit color code covering the
			-- whole rest of the string (not just relying on the
			-- SetTextColor call below, which didn't reliably color the
			-- prefix). Level prefix matches the BattleTag blue
			-- (FRIENDS_BNET_NAME_COLOR) instead of the class color, same as
			-- the BNet row, for a consistent look across both row types --
			-- its own self-contained code, kept outside the name's color wrap.
			local levelPrefix=""
			if SocialPlus_SavedVars.show_level and info.level and info.level~=0 then
				local bnetHex=string.format("|cFF%02x%02x%02x",
					FRIENDS_BNET_NAME_COLOR.r*255,FRIENDS_BNET_NAME_COLOR.g*255,FRIENDS_BNET_NAME_COLOR.b*255)
				levelPrefix=bnetHex..string.format("L%d",info.level).."|r "
			end
			local nameColorHex=string.format("|cFF%02x%02x%02x",nameColor.r*255,nameColor.g*255,nameColor.b*255)
			nameText=levelPrefix..nameColorHex..info.name.." ("..info.className..")".."|r"

			local wowAllowed,wowReason,wowRestriction=SocialPlus_GetInviteStatus("WOW",FriendButtons[index].id)

			if FACTION_ICON_PATH then
				FG_ApplyGameIcon(button,FACTION_ICON_PATH,30,"RIGHT","RIGHT",-22,0)
				-- Same already-grouped exclusion as the BNet row below.
				button.SocialPlusIconAlpha=(wowAllowed or wowRestriction==INVITE_RESTRICTION_ALREADY_GROUPED) and 1 or 0.4
			elseif button.gameIcon then
				button.gameIcon:Hide()
				button.SocialPlusIconAlpha=nil
			end

			hasTravelPassButton=true
			if button.travelPassButton then
				button.travelPassButton.fgInviteAllowed=wowAllowed
				button.travelPassButton.fgInviteReason=wowReason
				if wowAllowed then
					button.travelPassButton:Enable()
				else
					button.travelPassButton:Disable()
				end
			end
		else
			button.background:SetColorTexture(
				FRIENDS_OFFLINE_BACKGROUND_COLOR.r,
				FRIENDS_OFFLINE_BACKGROUND_COLOR.g,
				FRIENDS_OFFLINE_BACKGROUND_COLOR.b,
				FRIENDS_OFFLINE_BACKGROUND_COLOR.a
			)
			button.status:SetTexture(FRIENDS_TEXTURE_OFFLINE)
			nameText=info and info.name or ""
			nameColor=FRIENDS_GRAY_COLOR
			infoText=FRIENDS_LIST_OFFLINE

			if button.gameIcon then
				button.gameIcon:Hide()
			end

			hasTravelPassButton=false
			if button.travelPassButton then
				button.travelPassButton.fgInviteAllowed=false
				button.travelPassButton.fgInviteReason=FRIENDS_LIST_OFFLINE or "This friend is offline."
				button.travelPassButton:Disable()
			end
		end

		infoText=(info and info.mobile) and LOCATION_MOBILE_APP or (info and info.area) or infoText

		-- Store raw identifiers for whisper/invite
		if info then
			button.rawName=info.name
			button.characterName=info.name
			button.realmName=nil

			-- Deliberately no region: a plain WoW friend is on your own realm,
			-- so a flag beside their name can only ever say "same region as
			-- you", which is the one thing the flag was never needed to tell
			-- you. It earns its place on Battle.net rows precisely because
			-- those CAN be elsewhere. Left nil by the reset above.
		end
		button.accountName=nil

	elseif button.buttonType==FRIENDS_BUTTON_TYPE_BNET then
		local id=FriendButtons[index].id
		local accountName,characterName,class,level,isFavorite,
			isOnline,bnetAccountId,client,canCoop,wowProjectID,lastOnline,
			isAFK,isGameAFK,isDND,isGameBusy,mobile,zoneName,gameText,realmName,regionID,
			_,battleTag=
			GetFriendInfoById(id)

		-- Stashed for the shared section further down, which needs the area but
		-- runs outside this branch's scope. Carrying it on the button costs
		-- nothing; re-reading it there meant a SECOND GetFriendInfoById for
		-- every visible row, doubling the per-row cost of the very call the
		-- rebuild was optimised to avoid.
		-- Only for friends on the SAME WoW version. A TBC friend's zone can be
		-- "Nagrand Arena" too -- the maps share names across versions -- but you
		-- can't play with them, so the icon is noise.
		--
		-- This deliberately does NOT also require the faction crest to be
		-- showing. That used to be justified with "same-version friends always
		-- get the faction crest", which is false: the crest additionally
		-- requires a resolved realm name (see the icon selection further
		-- down), so a same-version friend whose realm hasn't come through
		-- falls back to the generic WoW logo -- which is placed larger and
		-- lower, and dragged the swords anchored to it down between two rows
		-- (reported live). The swords anchor now cancels the icon's own
		-- offset, so their placement no longer depends on which icon variant
		-- a friend happens to get.
		button.SocialPlusZoneName=(client==BNET_CLIENT_WOW
			and wowProjectID==WOW_PROJECT_ID) and zoneName or nil

		nameText=SocialPlus_GetBNetButtonNameText(accountName,client,canCoop,characterName,class,level,realmName,battleTag)

		button.accountName=accountName
		button.characterName=characterName
		button.realmName=realmName
		-- Only for a friend actually in WoW -- any version of it, since the
		-- region is just as true on Classic Era as on this client. A friend
		-- sitting in the Battle.net app or playing another game has a region
		-- too, but a flag beside their name reads as "playing WoW over here",
		-- which is exactly what they are not doing.
		--
		-- client is nil for an offline friend (it comes from the online game
		-- account), so this drops their flag as well, matching the game icon
		-- that is already hidden on those rows.
		button.SocialPlusRegionID=(client==BNET_CLIENT_WOW) and regionID or nil
		button.rawName=nameText

		isFavoriteFriend=isFavorite

		if isOnline then
			button.background:SetColorTexture(
				FRIENDS_BNET_BACKGROUND_COLOR.r,
				FRIENDS_BNET_BACKGROUND_COLOR.g,
				FRIENDS_BNET_BACKGROUND_COLOR.b,
				FRIENDS_BNET_BACKGROUND_COLOR.a
			)
			if isAFK or isGameAFK then
				button.status:SetTexture(FRIENDS_TEXTURE_AFK)
			elseif isDND or isGameBusy then
				button.status:SetTexture(FRIENDS_TEXTURE_DND)
			else
				button.status:SetTexture(FRIENDS_TEXTURE_ONLINE)
			end

        local iconPath
        local ga
        -- Match the SPECIFIC account this row is actually displaying
        -- (characterName/realmName, already resolved above via
        -- GetFriendInfoById), not just whichever account
        -- C_BattleNet.GetFriendAccountInfo(id).gameAccountInfo considers
        -- "the" one -- for a friend with multiple WoW licenses online at
        -- once, those two APIs can resolve to DIFFERENT accounts, so the
        -- row showed one character's name with a completely different
        -- character's faction crest (reported live: an Alliance Rogue
        -- shown with the Horde crest, because the friend also had a Horde
        -- character online under the same BattleTag). Moved above the
        -- infoText block below so the different-version branch can also
        -- use ga.regionID to show which region they're playing in.
        for _,acct in ipairs(SocialPlus_GetOnlineWoWGameAccounts(id)) do
            if acct.characterName==characterName
                and (not realmName or realmName=="" or acct.realmName==realmName) then
                ga={realmName=acct.realmName,factionName=acct.factionName,regionID=acct.regionID}
                break
            end
        end
        if not ga and C_BattleNet and C_BattleNet.GetFriendAccountInfo then
            local acct=C_BattleNet.GetFriendAccountInfo(id)
            ga=acct and acct.gameAccountInfo or nil
        end

			if client==BNET_CLIENT_WOW and wowProjectID==WOW_PROJECT_ID then
				if not zoneName or zoneName=="" then
					infoText=UNKNOWN
				else
					infoText=mobile and LOCATION_MOBILE_APP or zoneName
				end
			elseif client==BNET_CLIENT_WOW then
				-- Different WoW version than ours -- Blizzard's own game
				-- icon is the same generic WoW logo for every expansion
				-- (FG_GetClientTextureSafe/SOCIALPLUS_GAME_ICONS below key
				-- only by client, not by wowProjectID -- Blizzard doesn't
				-- expose separate per-expansion icons here), and gameText
				-- is just "World of Warcraft" with no version detail, so
				-- there was no way to tell a TBC friend from a Retail one
				-- at a glance (reported live). Same version label already
				-- used in notifications (SocialPlus_BuildFriendDetailBlock)
				-- shown here instead. Region appended too (e.g. "Retail
				-- EU"), same reasoning -- a same-version-name friend in a
				-- different region still isn't someone you can actually
				-- group with, so it's worth knowing at a glance too.
				local versionLabel=SocialPlus_GetVersionLabelText(wowProjectID)
				if versionLabel=="?" then
					versionLabel=SocialPlus_GetVersionLabelFromGameText(gameText)
				end
				if not versionLabel then
					-- This used to claim "Character Selection". It cannot: a
					-- full game-account dump for a friend who was demonstrably
					-- playing showed characterName, realmID, characterLevel,
					-- classID, wowProjectID and richPresence ALL empty or zero,
					-- with only isOnline/clientProgram set. Sitting at the
					-- character-select screen produces exactly the same empty
					-- payload, so the two are indistinguishable and asserting
					-- either one is wrong half the time.
					--
					-- Say only what Blizzard actually tells us: its own
					-- presence text if there is any, otherwise just the game.
					if not characterName or characterName=="" then
						versionLabel=(gameText and gameText~="" and gameText) or L.WOW_ONLINE_NO_DETAILS
					else
						versionLabel="?"
					end
				end
				infoText=versionLabel..SocialPlus_FormatRegionText(ga and ga.regionID)
			else
				infoText=gameText
			end

        local hasRealm=(realmName and realmName~="")
            or (ga and ga.realmName and ga.realmName~="")

        -- Friend’s faction (if applicable)
        local friendFaction
        if ga and ga.factionName then
            friendFaction=ga.factionName  -- "Alliance" or "Horde"
        end

        -- If same-project WoW with a real realm, prefer a faction crest.
        --
        -- Only when the friend's OWN faction is known. This used to fall back
        -- to FACTION_ICON_PATH -- the PLAYER's faction crest -- for a friend
        -- whose factionName hadn't resolved, which displayed a Horde friend
        -- with an Alliance crest (or vice versa) as confidently as a correct
        -- one. There is no neutral crest to show instead, so an unknown
        -- faction now falls through to the generic client logo below: saying
        -- "WoW friend" is honest, saying the wrong faction is not.
        if client==BNET_CLIENT_WOW and wowProjectID==WOW_PROJECT_ID and hasRealm then
            if friendFaction=="Horde" then
                iconPath="Interface\\FriendsFrame\\plusmanz-horde"
            elseif friendFaction=="Alliance" then
                iconPath="Interface\\FriendsFrame\\plusmanz-alliance"
            end
        end

        -- Fallback: generic client logo
        if not iconPath then
            iconPath=FG_GetClientTextureSafe(client)
        end

        -- Crest vs game logo?
        --
        -- Matched against the faction crest textures themselves rather than
        -- against FACTION_ICON_PATH, which is the PLAYER's crest: that
        -- comparison only ever matched a friend who shares your faction, so an
        -- Alliance player's Horde friends fell through to the game-icon style
        -- and were drawn 32px at -21 instead of the crest's 30px at -22.
        -- FACTION_ICON_PATH is itself one of these two textures, so nothing
        -- that matched before stops matching now.
        --
        -- plusmanz-battlenet is deliberately NOT matched despite the shared
        -- prefix -- it is the Battle.net app logo, not a faction crest.
        local isCrest=false
        if type(iconPath)=="string" then
            if iconPath:find("plusmanz-horde",1,true)
                or iconPath:find("plusmanz-alliance",1,true) then
                isCrest=true
            elseif iconPath:find("UI%-PVP%-") then
                isCrest=true
            end
        end

        -- Actually place the icon
        if isCrest then
            SocialPlus_ApplyIcon(button,iconPath,"crest")
        else
            SocialPlus_ApplyIcon(button,iconPath,"game")
        end

        -- Name color for BNet friends is always the same
        nameColor=FRIENDS_BNET_NAME_COLOR

        -- Invite logic
        local allowed,reason,restriction=SocialPlus_GetInviteStatus("BNET",id)
        button.travelPassButton.fgInviteAllowed=allowed
        button.travelPassButton.fgInviteReason=reason

        -- Icon fading: ONLY un-inviteable WoW icons fade (never non-WoW
        -- client icons). Opposite-faction friends are excluded on request --
        -- their Horde/Alliance crest (set above) stays full-strength instead
        -- of fading along with genuinely blocked cases (region, project,
        -- coop), since the crest itself already communicates the faction
        -- mismatch without needing to look dimmed too. Already-grouped
        -- friends are excluded too, on request -- them already being in the
        -- player's party isn't really "wrong" with them the way an offline
        -- or ineligible friend is.
        local fadeWowIcon=(client==BNET_CLIENT_WOW and not allowed
            and restriction~=INVITE_RESTRICTION_FACTION
            and restriction~=INVITE_RESTRICTION_ALREADY_GROUPED)
        button.SocialPlusIconAlpha=fadeWowIcon and 0.4 or 1
		-- Show invite button	
			hasTravelPassButton=true

			if allowed then
				button.travelPassButton:Enable()
			else
				button.travelPassButton:Disable()
			end
		else
			button.background:SetColorTexture(
				FRIENDS_OFFLINE_BACKGROUND_COLOR.r,
				FRIENDS_OFFLINE_BACKGROUND_COLOR.g,
				FRIENDS_OFFLINE_BACKGROUND_COLOR.b,
				FRIENDS_OFFLINE_BACKGROUND_COLOR.a
			)
			button.status:SetTexture(FRIENDS_TEXTURE_OFFLINE)
			nameColor=FRIENDS_GRAY_COLOR
			button.gameIcon:Hide()
			if not lastOnline or lastOnline==0 or time()-lastOnline>=ONE_YEAR then
				infoText=FRIENDS_LIST_OFFLINE
			else
				infoText=string.format(BNET_LAST_ONLINE_TIME,FriendsFrame_GetLastOnline(lastOnline))
			end
		end

		button.summonButton:ClearAllPoints()
		button.summonButton:SetPoint("CENTER",button.gameIcon,"CENTER",1,0)
		if FriendsFrame_SummonButton_Update then
			pcall(FriendsFrame_SummonButton_Update,button.summonButton)
		end

		elseif button.buttonType==FRIENDS_BUTTON_TYPE_DIVIDER then
		-- Group header row
		local group=FriendButtons[index].text
		local title
		if group=="" or not group then
		title=L.GROUP_UNGROUPED
		elseif group==SP_FAVORITES_GROUP then
		local star="|TInterface\\Common\\FavoritesIcon:20:20:0:-3|t"
		title=star.." "..SocialPlus_GetFavoritesLabel().." "..star
		elseif group==FriendRequestString then
		-- Same flanking-icon treatment as Favorites, using the glyph
		-- WoW's own friend-request toast uses.
		-- 14px, not the 20px the Favorites stars use: this texture has
		-- less internal padding, so at 20 it rendered oversized and sat
		-- low against the label (confirmed live).
		local reqIcon="|TInterface\\FriendsFrame\\UI-Toast-FriendRequestIcon:14:14:0:-1|t"
		title=reqIcon.." "..group.." "..reqIcon
		elseif group==SocialPlus_RECENT_GROUP then
		title=L.GROUP_RECENT
		elseif group==SP_INGAME_GROUP then
		title=L.GROUP_INGAME
		else
		title=group
		end
		local counts="("..(GroupOnline[group] or 0).."/"..(GroupTotal[group] or 0)..")"


		if button["text"] then
			button.text:SetText(title)
			button.text:Show()
			nameText=counts
			button.name:SetJustifyH("RIGHT")
		else
			nameText=title.." "..counts
			button.name:SetJustifyH("CENTER")
		end
		nameColor=SocialPlus_NAME_COLOR

		-- Same focus-mode override as the member-visibility check in
		-- SocialPlus_Update -- otherwise the arrow could show "+" (collapsed)
		-- on the one group whose members ARE actually showing during a
		-- group-name search.
		local isCollapsedNow=SocialPlus_SearchFocusGroup and group~=SocialPlus_SearchFocusGroup
			or (not SocialPlus_SearchFocusGroup and SocialPlus_SavedVars.collapsed[group])
		if isCollapsedNow then
			button.status:SetTexture("Interface\\Buttons\\UI-PlusButton-UP")
		else
			button.status:SetTexture("Interface\\Buttons\\UI-MinusButton-UP")
		end
		-- Re-anchor to the row's own vertical center (mirrors the gear
		-- button's "RIGHT" anchor on the other side) so it lines up on the
		-- same axis instead of wherever Blizzard's template placed it.
		button.status:ClearAllPoints()
		button.status:SetPoint("LEFT",button,"LEFT",4,0)

		-- An X on the recently-added header, and only there.
		--
		-- Rows are pooled and reused for whatever lands on them next, so this
		-- is created once per row and shown or hidden every rebuild -- a button
		-- left visible from a previous draw would sit on somebody else's group.
		if not button.spRecentClear then
			local clear=CreateFrame("Button",nil,button,"UIPanelCloseButton")
			clear:SetSize(20,20)
			clear:SetPoint("RIGHT",button,"RIGHT",-4,0)
			clear:SetScript("OnClick",function()
				if SocialPlus_ClearRecentFriends then SocialPlus_ClearRecentFriends() end
			end)
			clear:SetScript("OnEnter",function(self)
				GameTooltip:SetOwner(self,"ANCHOR_LEFT")
				GameTooltip:SetText(L.GROUP_RECENT_CLEAR,1,1,1,1,true)
				GameTooltip:Show()
			end)
			clear:SetScript("OnLeave",function() GameTooltip:Hide() end)
			button.spRecentClear=clear
		end

		button.spRecentClear:SetShown(FriendButtons[index].text==SocialPlus_RECENT_GROUP)

		infoText=group
		button.info:Hide()
		button.gameIcon:Hide()
		button.background:SetColorTexture(
			FRIENDS_OFFLINE_BACKGROUND_COLOR.r,
			FRIENDS_OFFLINE_BACKGROUND_COLOR.g,
			FRIENDS_OFFLINE_BACKGROUND_COLOR.b,
			FRIENDS_OFFLINE_BACKGROUND_COLOR.a
		)
		button.background:SetAlpha(0.5)

	-- drag-and-drop for group headers (set every render so role-switches are correct)
	button.SocialPlusGroupName=group
	button:RegisterForDrag("LeftButton")
	button:SetScript("OnDragStart",SocialPlus_OnGroupDragStart)
	button:SetScript("OnDragStop",SocialPlus_OnGroupDragStop)

	-- Cogwheel: same texture as the settings button, opens the same group
	-- menu as right-clicking the header (mute notifications, rename, etc.)
	-- Friend Requests and In-game Friends are pseudo-groups -- none of the
	-- menu's actions (invite all, rename, delete, mute) apply, so no
	-- cogwheel.
	if button.SocialPlusGroupGearButton then
		if group==FriendRequestString or group==SP_INGAME_GROUP then
			button.SocialPlusGroupGearButton:Hide()
		else
			button.SocialPlusGroupGearButton:Show()
		end
	end

	elseif button.buttonType==FRIENDS_BUTTON_TYPE_INVITE_HEADER then
		local header=FriendsScrollFrame.PendingInvitesHeaderButton
		header:SetPoint("TOPLEFT",button,1,0)
		header:Show()
		header:SetFormattedText(FRIEND_REQUESTS,FG_BNGetNumFriendInvites())
		local collapsed=GetCVarBool("friendInvitesCollapsed")
		if collapsed then
			header.DownArrow:Hide()
			header.RightArrow:Show()
		else
			header.DownArrow:Show()
			header.RightArrow:Hide()
		end
		nameText=nil

	elseif button.buttonType==FRIENDS_BUTTON_TYPE_INVITE then
		local scrollFrame=FriendsScrollFrame
		-- Reposition only -- keep Blizzard's own handlers and fields
		-- untouched. This code used to mirror Blizzard's population
		-- verbatim (writing invite.inviteID/.inviteIndex itself) and later
		-- replaced the click handlers with direct BN API calls -- both
		-- risk a tainted value/execution chain, and BNAcceptFriendInvite
		-- can silently ignore insecure calls. Confirmed live that fresh
		-- invites accept flawlessly through Blizzard's untouched secure
		-- handler under this reposition-only rendering (and keep working
		-- across sessions). Blizzard's own FriendsList_Update always runs
		-- before this posthook and populates these pool entries with
		-- secure values -- leave every one of them alone.
		-- (Historical note: one real invite proved unacceptable by ANY
		-- means -- stock UI with all addons disabled and a direct /run
		-- with the verified-correct ID both silently failed -- i.e. a
		-- server-side ghost invite. The notice below covers that case.)
		--
		-- Pick the frame whose SECURE inviteID matches this row's invite
		-- (reading the field is harmless; only writing it was the taint
		-- problem) -- never acquire blindly, or with 2+ pending invites
		-- the arbitrary pool order could pair this row's display with a
		-- frame whose Accept/Decline act on a DIFFERENT invite.
		local wantID,inviteAccountName=FG_BNGetFriendInviteInfo(button.id)
		local invite
		if wantID and scrollFrame.invitePool.EnumerateActive then
			for inviteFrame in scrollFrame.invitePool:EnumerateActive() do
				if inviteFrame.inviteID==wantID then
					invite=inviteFrame
					break
				end
			end
		end
		-- Fallback (no securely-populated frame found -- shouldn't happen,
		-- since Blizzard's update precedes ours): acquire one so the row
		-- at least displays; its buttons may act on a stale ID until the
		-- next Blizzard pass corrects the pairing.
		if not invite then
			invite=scrollFrame.invitePool:Acquire()
		end
		-- The Name text is display-only (the handler never reads it), so
		-- setting it is safe -- and needed, since Blizzard laid the frame
		-- out for ITS list position, not ours.
		invite:SetAllPoints(button)
		-- Above button's own click surface (and its gear child, which sits
		-- at button level+2) -- otherwise our row button, which every row
		-- gets an OnClick handler on regardless of type, intercepts clicks
		-- meant for invite.AcceptButton/DeclineButton since it fully
		-- overlaps them and WoW hit-tests by topmost frame level, not by
		-- which specific child widget is visually under the cursor
		-- (reported live: friend saw the request but Accept did nothing
		-- when clicked).
		invite:SetFrameLevel(button:GetFrameLevel()+10)
		invite:Show()
		if inviteAccountName and invite.Name then
			invite.Name:SetText(inviteAccountName)
		end
		nameText=nil

		-- Ghost-invite fallback: non-destructive post-hook (Blizzard's
		-- handler still runs first, untouched). Rarely, an invite can be
		-- broken server-side and unacceptable by ANY means (confirmed
		-- live -- see above); if the invite is demonstrably still pending
		-- a moment after Accept was clicked, explain instead of letting
		-- the button look like it ignores the user. Never fires when an
		-- accept succeeds.
		if invite.AcceptButton and not invite.SocialPlusAcceptNotice then
			invite.SocialPlusAcceptNotice=true
			invite.AcceptButton:HookScript("OnClick",function()
				local before=FG_BNGetNumFriendInvites()
				if before<=0 then return end
				C_Timer.After(2,function()
					if FG_BNGetNumFriendInvites()>=before then
						print(L.MSG_INVITE_ACCEPT_BROKEN)
					end
				end)
			end)
		end
	end


    -- Hook travelPassButton once to ensure we invite the right friend (our ordering,
    -- not Blizzard's scroll index which diverges when friends are grouped).
    if button.travelPassButton and not button.travelPassButton.SocialPlusClickHooked then
        button.travelPassButton.SocialPlusClickHooked=true
        button.travelPassButton:SetScript("OnClick",function(self,...)
            if self.fgInviteAllowed then
                SocialPlus_PerformInviteFromButton(button)
            end
        end)
    end

    -- Explicitly above the row's own level on EVERY render, not just once --
    -- confirmed live (diagnostic: OnClick never even fired, row highlighted
    -- instead) this is the same class of bug as the Friend Request Accept
    -- button fixed earlier: a row that's been reused/recycled for something
    -- else (e.g. as a group header, where sibling elements get explicitly
    -- leveled above it) can leave the travel-pass button sitting at or below
    -- the row's own level, so the row's full-area click surface swallows
    -- clicks meant for this child instead of passing them through. Search
    -- results in particular tend to reuse buttons that previously served
    -- other roles more than the normal steady-state view does.
    if button.travelPassButton then
        button.travelPassButton:SetFrameLevel(button:GetFrameLevel()+5)
    end

    -- Show/hide travel pass button
    if hasTravelPassButton then
        button.travelPassButton:Show()
    else
        button.travelPassButton:Hide()
    end

    -- Match by stable identity (BattleTag/GUID) when available, same as
    -- the tooltip fix -- the raw id/buttonType pair alone can drift to a
    -- different friend if Blizzard reorders its list while someone's
    -- selected. Falls back to the raw pair only if an identity key
    -- couldn't be resolved for either side.
    local rowIdentity=SocialPlus_GetRowIdentityKey(FriendButtons[index].buttonType,FriendButtons[index].id)
    local isSelectedRow=SocialPlus_SelectedRow and (
        (SocialPlus_SelectedRow.identityKey and rowIdentity and SocialPlus_SelectedRow.identityKey==rowIdentity)
        or (not SocialPlus_SelectedRow.identityKey
            and SocialPlus_SelectedRow.buttonType==FriendButtons[index].buttonType
            and SocialPlus_SelectedRow.id==FriendButtons[index].id)
    )
    if isSelectedRow then
        button:LockHighlight()
    else
        button:UnlockHighlight()
    end

	-- While dragging a group header, softly fade that group (header + members)
    if SocialPlus_IsRowInDraggedGroup and SocialPlus_IsRowInDraggedGroup(button) then
    -- Extra fade *on top* of the existing icon rules
        button:SetAlpha(0.35)
    else
        button:SetAlpha(1)
    end

    -- Finalize icon alpha AFTER Blizzard has done its own layout/updates
    if button.gameIcon then
        if button.SocialPlusIconAlpha ~= nil then
            button.gameIcon:SetAlpha(button.SocialPlusIconAlpha)
        else
            button.gameIcon:SetAlpha(1)
        end
    end
    button.SocialPlusIconAlpha=nil

	-- Search filtering
	if nameText then
		if button.buttonType~=FRIENDS_BUTTON_TYPE_DIVIDER then
			if button["text"] then
				button.text:Hide()
			end
			button.name:SetJustifyH("LEFT")
			button.background:SetAlpha(1)
			button.info:Show()
		end
		if button.buttonType==FRIENDS_BUTTON_TYPE_BNET or button.buttonType==FRIENDS_BUTTON_TYPE_WOW then
			-- Pinned explicitly every render, not just left wherever
			-- Blizzard's template put it. Rows are pooled/recycled, and the
			-- ONLY other place this addon touches button.status is the
			-- group-divider branch below, which re-anchors it to a
			-- vertically-centered LEFT point -- a widget last used as a
			-- divider and then recycled into a friend row kept that centered
			-- position instead of reverting, so the status icon appeared to
			-- randomly drift between top and middle depending on scroll
			-- history (reported live). Anchoring it ourselves here, always,
			-- makes its position deterministic regardless of prior reuse --
			-- and gives the note icon below a stable point to anchor to.
			button.status:ClearAllPoints()
			button.status:SetPoint("TOPLEFT",button,"TOPLEFT",4,-3)

			-- Favorite star stays on the left, in front of the name.
			local prefix=""

			if SocialPlus_IsFavorite(button.buttonType,button.id) then
				prefix=prefix.."|TInterface\\Common\\FavoritesIcon:26:26:0:-3|t"
			end

			-- "Has a note" means real free text, not just the group tags
			-- SocialPlus stores in the same note field ("Sacha#Friends") --
			-- strip everything from the first "#" onward (NoteAndGroups does
			-- the same split, but isn't in scope yet at this point in the
			-- file) before checking.
			local rawNote
			if button.buttonType==FRIENDS_BUTTON_TYPE_BNET then
				rawNote=select(13,FG_BNGetFriendInfo(button.id))
			else
				local info=FG_GetFriendInfoByIndex(button.id)
				rawNote=info and info.notes
			end
			local baseNote=rawNote and strtrim(rawNote:match("^([^#]*)") or "")
			local hasNote=baseNote and baseNote~=""

			-- The note icon used to be appended as inline text after the
			-- name (suffix..) but that put it INSIDE the same truncated,
			-- fixed-width name string -- a long character/realm name (e.g.
			-- "Lifeosuction-Nebupeach-Nazgrim") truncates before reaching
			-- it, so the icon silently never rendered (reported live). It's
			-- now a real texture anchored directly under the (now-pinned,
			-- see above) status icon, so it never competes with the name
			-- column's width at all.
			if not button.SocialPlusNoteIcon then
				local icon=button:CreateTexture(nil,"OVERLAY")
				icon:SetTexture("Interface\\Buttons\\UI-GuildButton-PublicNote-Up")
				icon:SetSize(10,10)
				icon:SetPoint("TOP",button.status,"BOTTOM",0,-2)
				button.SocialPlusNoteIcon=icon
			end
			if hasNote then
				button.SocialPlusNoteIcon:Show()
			else
				button.SocialPlusNoteIcon:Hide()
			end

			-- The spec icon and the region flag, to the left of the faction
			-- crest.
			--
			-- Textures on the row rather than characters in the name string:
			-- the name is a fixed-width truncating field, and anything put
			-- inside it silently vanishes for long character and realm names.
			-- That is the same reason the note icon and the swords live out
			-- here, and it is written down twice because it keeps being
			-- rediscovered the hard way.
			if not button.SocialPlusRegionFlag then
				local icon=button:CreateTexture(nil,"OVERLAY")
				button.SocialPlusRegionFlag=icon
			end

			button.SocialPlusRegionFlag:Hide()

			-- The spec belongs on the tooltip, not here.
			--
			-- It was on the row for a version and taken off: the row already
			-- carries an arena mark, a flag and a faction crest, and a fourth
			-- picture past a truncated name is where a list stops being read
			-- and starts being decoded.
			local rowFlag=SocialPlus_RowRegionFlag(button)

			if rowFlag then
				local art=SocialPlus_RegionFlagArt
				button.SocialPlusRegionFlag:SetTexture(rowFlag.texture)
				button.SocialPlusRegionFlag:SetTexCoord(
					rowFlag.texels[1]/128,rowFlag.texels[2]/128,
					rowFlag.texels[3]/64,rowFlag.texels[4]/64)
				button.SocialPlusRegionFlag:SetSize(math.floor(13*art.aspect+0.5),13)
				button.SocialPlusRegionFlag:Show()
			end

			-- Crossed swords for a friend on an arena map. Anchored to the
			-- status icon like the note icon, NOT appended to the name string:
			-- the name is a fixed-width truncating field, and anything put
			-- inside it silently vanishes for long character/realm names (the
			-- exact bug the note icon was moved out of the name to fix).
			if not button.SocialPlusArenaIcon then
				local icon=button:CreateTexture(nil,"OVERLAY")
				-- A UI texture, not a spell icon: everything under Interface\Icons
				-- is a square with a baked-in black background. This one is
				-- crossed swords on transparency, so it sits cleanly next to the
				-- faction crest.
				icon:SetTexture([[Interface\GossipFrame\BattleMasterGossipIcon]])
				-- 20 rather than 14: this texture has transparent padding around
				-- the swords, so the art renders noticeably smaller than its box.
				icon:SetSize(20,20)
				button.SocialPlusArenaIcon=icon
			end
			-- Anchored each pass, not once at creation: button.gameIcon (the
			-- faction crest) may not exist yet the first time a pooled row is
			-- built, and a SetPoint against a missing frame silently leaves the
			-- icon unanchored in the corner.
			-- Right to left, each against the last one actually shown.
			--
			-- Three things now want the space beside the crest -- the flag, the
			-- spec icon and the swords -- and anchoring each of them to the
			-- crest put all three in one place on any row that had more than
			-- one. Chained, a row shows whichever it has, in a fixed order,
			-- with no gaps for the ones it does not.
			--
			-- Rebuilt every pass rather than once: rows are pooled, and the
			-- previous occupant's chain is not this one's.
			local rightOf=button.gameIcon
			local rightOfShown=rightOf and rightOf:IsShown()

			local function Chain(icon,gap)
				if not (icon and icon:IsShown()) then return end

				icon:ClearAllPoints()
				if rightOfShown then
					icon:SetPoint("RIGHT",rightOf,"LEFT",-(gap or 3),
						-(button.SocialPlusIconOffY or 0))
				else
					icon:SetPoint("RIGHT",button,"RIGHT",-8,0)
				end

				rightOf,rightOfShown=icon,true
			end

			Chain(button.SocialPlusRegionFlag,3)

			button.SocialPlusArenaIcon:ClearAllPoints()
			if rightOfShown then
				-- Cancel whatever vertical offset the game icon was placed
				-- with. FG_ApplyGameIcon shifts some icons off the row's
				-- centre line -- the generic WoW logo is applied at 64px with
				-- offY=-15 -- and anchoring to the icon inherited that shift,
				-- dropping the swords into the gap between two rows (reported
				-- live, on a same-version friend who got the logo instead of a
				-- crest because their realm hadn't resolved -- see the
				-- SocialPlusZoneName note in the BNet branch above).
				--
				-- Read back from the icon rather than repeated here, so the
				-- offset stays defined in exactly one place.
				button.SocialPlusArenaIcon:SetPoint("RIGHT",rightOf,"LEFT",-4,
					-(button.SocialPlusIconOffY or 0))
			else
				-- Also covers a HIDDEN game icon, not just a missing one: a
				-- hidden texture keeps its last anchor, so a pooled row would
				-- otherwise place the swords against the previous occupant's
				-- icon position.
				button.SocialPlusArenaIcon:SetPoint("LEFT",button.status,"RIGHT",2,0)
			end
			-- Re-read the area here rather than using the BNET branch's
			-- zoneName: this block is the SHARED section after the per-type
			-- branches, so that local is out of scope and was always nil --
			-- which is why the tooltip (which fetches its own copy) showed
			-- "In Arena" while the row icon never appeared.
			local arenaZone=(button.buttonType==FRIENDS_BUTTON_TYPE_BNET)
				and button.SocialPlusZoneName or nil
			if SocialPlus_IsArenaZone(arenaZone) then
				button.SocialPlusArenaIcon:Show()
				rightOf,rightOfShown=button.SocialPlusArenaIcon,true
			else
				button.SocialPlusArenaIcon:Hide()
			end

			-- Pin the name between the status dot and whatever icon is
			-- leftmost on THIS row, instead of leaving it at the fixed width
			-- Blizzard's template gives it.
			--
			-- That fixed width knows nothing about what the row is actually
			-- carrying, so a long BattleTag was cut off well before the icons
			-- began -- wasting the gap -- while a row with no icons at all was
			-- cut off at the same place despite having the whole width free.
			-- Adding the region flag made it worse by putting one more thing in
			-- that space.
			--
			-- Two anchors instead of a width is what genuinely clips the text
			-- rather than letting it run underneath the icons; it is the same
			-- treatment the drag-ghost row already gets, and for the same
			-- reason. SetWidth(0) first because an explicit width would win
			-- over the anchors and nothing would change.
			--
			-- Done here rather than earlier because the swords' visibility is
			-- only settled just above, and they can be the leftmost thing.
			if button.name then
				button.name:ClearAllPoints()
				button.name:SetWidth(0)
				button.name:SetPoint("LEFT",button.status,"RIGHT",6,0)
				if rightOfShown and rightOf then
					button.name:SetPoint("RIGHT",rightOf,"LEFT",-4,0)
				else
					-- No icons on this row: clip against the row itself so a
					-- long name still stops before the edge.
					button.name:SetPoint("RIGHT",button,"RIGHT",-8,0)
				end
			end

			nameText=prefix..nameText
		end
		button.name:SetText(nameText)
		button.name:SetTextColor(nameColor.r,nameColor.g,nameColor.b)
		button.info:SetText(infoText)
		button:Show()
		if isFavoriteFriend and button.Favorite then
			button.Favorite:Show()
			button.Favorite:ClearAllPoints()
			-- Placed just after the text ENDS, but never past the field.
			--
			-- GetStringWidth reports the width the name would need if nothing
			-- clipped it, so on a long BattleTag it reported well past the
			-- field's own edge and put the star out beyond the icons -- or off
			-- the row entirely. Clamped to the field, it lands against the
			-- truncation instead.
			local textW=button.name:GetStringWidth() or 0
			local fieldW=button.name:GetWidth() or 0
			if fieldW>0 and textW>fieldW then textW=fieldW end
			button.Favorite:SetPoint("TOPLEFT",button.name,"TOPLEFT",textW,0)
		elseif button.Favorite then
			button.Favorite:Hide()
		end
	else
		button:Hide()
	end

	-- Tooltip handling: check whether THIS row is the one the mouse is
	-- actually over right now (SocialPlus_MouseIsOver) and, if our own custom
	-- tooltip (see SocialPlus_ShowRowTooltip) isn't already showing THIS
	-- friend's identity, refresh it. A rebuild (list reorder, online/
	-- offline rescan) can reassign which widget-to-friend mapping sits
	-- under a stationary cursor, so this is what keeps the tooltip in sync
	-- without needing a real mouse movement.
	if SocialPlus_MouseIsOver(button) then
		local identityKey=SocialPlus_GetRowIdentityKey(button.buttonType,button.id)
		-- A nil identityKey (lookup momentarily failed) must NOT be treated
		-- as "unchanged": nil==nil would wrongly count as still matching.
		local sameFriend=identityKey and GameTooltip and GameTooltip.SocialPlusShownKey==identityKey and GameTooltip:IsShown()
		if not sameFriend then
			SocialPlus_ShowRowTooltip(button)
		end
	end

	return height
end

-- [[ Full friends list rebuild ]]
local SocialPlus_InUpdateFriends=false
-- Assigns to the local forward-declared at the top of the file rather than
-- making a second one, which is what lets the collapse settle timer above see
-- it.
function SocialPlus_UpdateFriends()
	-- Counts every actual rebuild, for /spsim rate to sample.
	--
	-- It has to live HERE rather than on SocialPlus_Update, which is what an
	-- outside hook can reach: SocialPlus_Update bails early when the panel is
	-- hidden (counting work that never happened), and the scroll handler calls
	-- this function DIRECTLY without going through it (missing work that did).
	-- Measuring the wrong one reported "no bursts" while every scroll was
	-- quietly running a full rebuild.
	--
	-- One increment on a global. Left in the shipped build deliberately: it
	-- costs nothing measurable, and the alternative is that this can only ever
	-- be measured by first editing the addon.
	--
	-- REQUESTS counts every call, REBUILD_COUNT further down counts the ones
	-- that actually did the work. The gap between them is what the coalescing
	-- below is saving.
	SOCIALPLUS_REBUILD_REQUESTS=(SOCIALPLUS_REBUILD_REQUESTS or 0)+1
	-- Defensive reentrancy guard: this function calls
	-- scrollFrame.scrollBar:SetValue() below, which could plausibly
	-- re-enter this function synchronously via the scrollbar's own
	-- OnValueChanged. Tested live and it did NOT stop the hover-triggered
	-- repeat-call issue reported live (the real culprit turned out to be
	-- the unconditional SetValue/SetMinMaxValues/HybridScrollFrame_Update
	-- calls below, now made conditional / removed) -- kept anyway as cheap
	-- insurance against genuine synchronous reentrancy from any source.
	local nowFrame=(GetTime and GetTime()) or 0

	if SocialPlus_InUpdateFriends then
		-- Stuck-flag recovery.
		--
		-- The body below is not wrapped in pcall, so a Lua error anywhere
		-- inside it returns WITHOUT clearing this flag. Every later rebuild
		-- then bails right here, and the friends list silently stops updating
		-- -- it renders empty and stays empty until a /reload (seen live). One
		-- transient error should not permanently disable the list.
		--
		-- Genuine reentrancy is synchronous: it happens inside this same frame
		-- and unwinds before the next one. So a flag still set on a LATER frame
		-- cannot be reentrancy -- it is a leak from an error, and clearing it
		-- is the correct recovery.
		if SocialPlus_InUpdateFrame==nowFrame then return end
		SocialPlus_InUpdateFriends=false
	end
	SocialPlus_InUpdateFrame=nowFrame

	-- No same-frame coalescing here, deliberately.
	--
	-- It was tried: a second render in the same frame was deferred to the next
	-- one. It worked -- 3-per-frame became 1 -- but it caused visible
	-- flickering, and the reason is structural rather than tunable. Callers
	-- like the collapse settle run HardResetScrollRows() first, which HIDES
	-- every row, and then render. Deferring that render leaves one whole frame
	-- with the rows hidden and nothing drawn in their place: a blank flash.
	--
	-- And it was not worth defending. Measured on an 800-friend list it
	-- collapsed about 20 calls in 15 seconds, and a render costs ~2.5ms -- some
	-- 51ms, or 0.34% of wall time. The real wins came from the two settle
	-- timers no longer re-deriving unchanged friend data (~-50% of data
	-- passes) and from the cheaper pass itself (~-28%), neither of which
	-- touches what is on screen mid-frame.
	--
	-- Renders are cheap; a frame that draws nothing is not.
	SocialPlus_InUpdateFriends=true
	SOCIALPLUS_REBUILD_COUNT=(SOCIALPLUS_REBUILD_COUNT or 0)+1

	-- Times the render itself, accumulated into SOCIALPLUS_RENDER_MS.
	--
	-- /spsim bench only ever timed SocialPlus_Update, the full data pass. Most
	-- calls that reach here are NOT that -- the scroll handler calls this
	-- directly, skipping every per-friend pass -- so multiplying a render count
	-- by the bench figure overstates the cost, and there was no number for what
	-- a render alone costs. There is now.
	--
	-- Safe to bracket the whole body: there is no early return between here and
	-- the accumulate at the end, so the start time can never be stranded.
	local spRenderT0=debugprofilestop and debugprofilestop() or nil

	local scrollFrame=FriendsScrollFrame
	local buttons=scrollFrame.buttons
	local numButtons=#buttons
	local numFriendButtons=FriendButtons.count or 0

	-- Collapsing everything (worst case: General, our biggest group) can
	-- shrink content below the visible frame height. When that happens,
	-- Blizzard's own HybridScrollFrame code disables mouse-wheel input on
	-- the scroll frame since nothing needs scrolling -- but we only ever
	-- call frame:EnableMouseWheel(true) once, at login
	-- (SocialPlus_InitSmoothScroll). Nothing re-enables it once Blizzard's
	-- code turns it back off, so scrolling stays dead even after content
	-- grows again (a group gets re-expanded). Re-assert it on every render
	-- so it can never get stuck disabled.
	scrollFrame:EnableMouseWheel(true)

	scrollFrame.dividerPool:ReleaseAll()
	-- Invite frames: HIDE the active ones instead of ReleaseAll. Blizzard's
	-- own (secure) FriendsList_Update established which pool frame carries
	-- which invite's secure inviteID -- releasing and blindly re-acquiring
	-- scrambles that pairing (pool acquire order is arbitrary), and since
	-- we deliberately never write inviteID ourselves (taint safety, see the
	-- invite render branch), with 2+ pending invites a row could end up
	-- displaying one invite while its Accept/Decline act on another. The
	-- render branch below re-shows and repositions exactly the frame whose
	-- secure ID matches each row.
	if scrollFrame.invitePool.EnumerateActive then
		for inviteFrame in scrollFrame.invitePool:EnumerateActive() do
			inviteFrame:Hide()
		end
	else
		scrollFrame.invitePool:ReleaseAll()
	end
	scrollFrame.PendingInvitesHeaderButton:Hide()

	-- Confirmed live: on this client, Blizzard's own HybridScrollFrame_Update
	-- never produces a usable scrollbar range -- GetMinMaxValues() came back
	-- (0,-1) regardless of actual content height, which made
	-- SocialPlus_InitSmoothScroll's OnMouseWheel handler clamp every scroll
	-- attempt to 0 (math.min(-1,target) is always -1, math.max(0,-1) is
	-- always 0), i.e. dead scrolling. No longer calling it at all -- set the
	-- real range ourselves from our own known-accurate content height and
	-- the frame's actual visible height.
	--
	-- This block runs BEFORE the row render on purpose: when content
	-- shrinks a lot (collapsing General from deep in the list), the value
	-- clamp below fires OnValueChanged -> Blizzard's SetOffset -> .update()
	-- -- whose re-render our reentrancy guard swallows. When the clamp ran
	-- AFTER the rows were drawn, that swallowed re-render meant the rows
	-- stayed laid out for the pre-clamp position until the settle pass
	-- ~150ms later -- visible as a beat of blank space below the list that
	-- then snapped up into place (confirmed frame-by-frame from a live
	-- recording). Clamping first, the row loop below always renders at the
	-- final, post-clamp position within this same pass.
	if scrollFrame.scrollBar then
		-- INTEGER-ROUND everything here, exactly like Blizzard's own
		-- HybridScrollFrame_Update does (floor(x+0.5)) -- and for the same
		-- reason. GetHeight() returns sub-pixel floats that can jitter
		-- frame to frame, and the scrollbar itself quantizes values to its
		-- own step, so an unrounded comparison sees a "change" on nearly
		-- every render -> SetMinMaxValues/SetValue fire -> OnValueChanged
		-- -> HybridScrollFrame_SetOffset -> .update() -> another render ->
		-- self-sustaining churn (confirmed live via counter diagnostics
		-- during the scroll-glitch hunt).
		local totalHeight=scrollFrame.totalFriendListEntriesHeight or 0
		local frameHeight=scrollFrame:GetHeight() or 0
		local scrollRange=math.floor(math.max(totalHeight-frameHeight,0)+0.5)
		local curValue=scrollFrame.scrollBar:GetValue() or 0
		local clampedValue=math.min(curValue,scrollRange)

		-- Only touch the scrollbar's min/max/value when something actually
		-- needs to change (rounded comparisons, per the above): SetValue/
		-- SetMinMaxValues can trigger the scrollbar's own OnValueChanged
		-- (wired to re-run this whole update) even when set to the same
		-- values, so calling them unconditionally fed the loop.
		local curMin,curMax=scrollFrame.scrollBar:GetMinMaxValues()
		if math.floor(curMin+0.5)~=0 or math.floor(curMax+0.5)~=scrollRange then
			scrollFrame.scrollBar:SetMinMaxValues(0,scrollRange)
		end
		if math.floor(clampedValue+0.5)~=math.floor(curValue+0.5) then
			scrollFrame.scrollBar:SetValue(clampedValue)
		end

		if scrollRange<=0 then
			if scrollFrame.scrollBar:IsShown() then
				scrollFrame.scrollBar:Hide()
			end
		else
			if not scrollFrame.scrollBar:IsShown() then
				scrollFrame.scrollBar:Show()
			end
		end
	end

	-- Captured AFTER the clamp above so the rows render at the final
	-- position (the clamp's OnValueChanged already refreshed the cached
	-- offset synchronously).
	local offset=HybridScrollFrame_GetOffset(scrollFrame)

	SOCIALPLUS_ROWS_STALE=false
	for i=1,numButtons do
		local button=buttons[i]
		local index=offset+i
		if index<=numFriendButtons then
			button.index=index
			local height=SocialPlus_UpdateFriendButton(button)
			button:SetHeight(height)
		else
			button.index=nil
			button:Hide()
		end
	end

	-- A row above proved it was drawing somebody else. The rows are wrong,
	-- not repairable in place -- their GROUP placement came from the same
	-- stale mapping -- so the answer is the derivation that was skipped.
	--
	-- Forced, so it runs even in combat: the combat guard exists to skip work
	-- that would only re-confirm what is on screen, and we have just measured
	-- that what is on screen is wrong.
	--
	-- Next frame rather than here. This is called from inside the render, with
	-- SocialPlus_InUpdateFriends set and the row loop's own state live; a
	-- synchronous re-entry would rebuild the rows underneath it. One frame of
	-- wrong names is the cost, against a whole fight of them before.
	if SOCIALPLUS_ROWS_STALE then
		SOCIALPLUS_ROWS_STALE=false
		if not SOCIALPLUS_ROWS_REPAIRING then
			SOCIALPLUS_ROWS_REPAIRING=true
			C_Timer.After(0,function()
				SOCIALPLUS_ROWS_REPAIRING=false
				SocialPlus_Update(true)
			end)
		end
	end

	-- The scroll child's height is what gives the scroll frame room to
	-- apply the sub-row pixel offset (SetVerticalScroll with the remainder
	-- from our dynamic/GetTopButton callback) that makes variable-height
	-- rows scroll smoothly. Keep it at a STABLE value -- the full content
	-- height -- updated only when content genuinely changes. A first
	-- attempt set it to the visible rows' summed height on every render:
	-- that fluctuates with the divider/friend row mix, and every rect
	-- change (plus the unconditional UpdateScrollChildRect that came with
	-- it) could reset the frame's vertical-scroll remainder to 0. During
	-- active scrolling Blizzard re-applies the remainder every tick so
	-- it's invisible -- but on the idle settle pass nothing follows, so
	-- the view visibly jumped by up to a row a beat after scrolling
	-- stopped, moving the hover highlight under a stationary cursor
	-- (confirmed frame-by-frame from a live recording).
	local scrollChild=scrollFrame.scrollChild or scrollFrame.ScrollChild
	if scrollChild then
		local h=math.floor((scrollFrame.totalFriendListEntriesHeight or 0)+0.5)
		local minH=math.floor((scrollFrame:GetHeight() or 0)+0.5)+1
		if h<minH then h=minH end
		-- HIGH-WATER MARK: only ever grow the child, never shrink it. An
		-- oversized child is harmless (our scrollbar range, not the child
		-- rect, bounds how far the list can scroll), but SHRINKING it on a
		-- collapse toggle perturbs the scroll frame's rect -- and the
		-- engine applies rect recalculation a frame later, resetting the
		-- vertical scroll AFTER our end-of-render remainder re-assert
		-- already ran. With a tiny scroll range (e.g. General folded) that
		-- produced a visible ping-pong: the view bounced between remainder
		-- 16 and 0 for several re-layouts before converging (confirmed
		-- frame-by-frame from a live recording of toggling General).
		if math.floor((scrollChild:GetHeight() or 0)+0.5)<h then
			scrollChild:SetHeight(h)
			scrollFrame:UpdateScrollChildRect()
		end
	end

	-- Self-healing remainder: rows above were rendered for the current
	-- scrollbar value's top element; re-assert the matching sub-row pixel
	-- offset unconditionally, so no scroll-child rect change (or anything
	-- else that resets a scroll frame's vertical scroll) can leave the
	-- view shifted by a partial row against the rendered rows. This is
	-- the same SetVerticalScroll call Blizzard's own
	-- HybridScrollFrame_SetOffset performs on every value change --
	-- idempotent and cheap.
	if scrollFrame.scrollBar then
		local _,remainder=SocialPlus_GetTopButton(scrollFrame.scrollBar:GetValue() or 0)
		scrollFrame:SetVerticalScroll(remainder or 0)
	end

	-- Keep global collapse/expand button state in sync
	SocialPlus_UpdateCollapseAllButtonVisual()

	-- Clean up collapsed groups that no longer exist
	for key,_ in pairs(SocialPlus_SavedVars.collapsed) do
		if not GroupTotal[key] then
			SocialPlus_SavedVars.collapsed[key]=nil
		end
	end

	if spRenderT0 then
		SOCIALPLUS_RENDER_MS=(SOCIALPLUS_RENDER_MS or 0)+(debugprofilestop()-spRenderT0)
	end

	SocialPlus_InUpdateFriends=false
end

-- [[ Group tag helpers ]]
local function FillGroups(groups,note,...)
	wipe(groups)
	local n=select('#',...)
	local added=false
	for i=1,n do
		local v=select(i,...)
		-- A "#" immediately followed by whitespace ("# test") is not a
		-- group tag -- only "#test" (no space right after the #) counts.
		-- Checked on the raw segment, before trimming, since trimming
		-- would otherwise make "# test" indistinguishable from "#test".
		if not v:match("^%s") then
			v=strtrim(v)
			-- A stray "|" here would desync the |H...|h hyperlink escape
			-- sequences group names get spliced into elsewhere (group links,
			-- headers) -- strip it rather than trust that this addon is the
			-- only thing that ever wrote this note (Blizzard's own "Set Note"
			-- UI can edit it freely). Only count non-empty tags as real group
			-- membership -- an empty segment (from "##", a trailing "#", or a
			-- tag that was nothing but pipes) must not collide with the same
			-- "" sentinel used for "no tags at all" below.
			v=v:gsub("|","")
			if v~="" then
				groups[v]=true
				added=true
			end
		end
	end
	if not added then
		groups[""]=true
	end
	return note
end

local function NoteAndGroups(note,groups)
	if not note then
		return FillGroups(groups,"")
	end
	if groups then
		return FillGroups(groups,strsplit("#",note))
	end
	return strsplit("#",note)
end

-- Search-bar text for a friend's note: free text is unaffected, but the
-- group-tag portion is favorite-aware, same as rendering already is --
-- a favorited friend's real group tags don't count as a search match
-- (they're effectively moved out of that group), only the localized
-- "Favorites" label does; a non-favorited friend matches their real
-- tags as before, never "Favorites".
local function SocialPlus_BuildNoteSearchBlob(buttonType,id,note)
	-- Only the "#group" tags are searchable, not the free-text part of the
	-- note before the first "#" -- a note like "God Tank#raid" should match
	-- a search for "raid", not "tank".
	local groups={}
	NoteAndGroups(note,groups)
	local groupText
	if SocialPlus_IsFavorite(buttonType,id) then
		groupText=SocialPlus_GetFavoritesLabel()
	else
		local names={}
		for group in pairs(groups) do
			if group~="" then table.insert(names,group) end
		end
		groupText=table.concat(names," ")
	end
	return groupText
end

-- Best-effort UNMASKED sort name for a BNet friend. Both the raw
-- BNGetFriendInfo tuple's accountName AND GetFriendInfoById's can
-- transiently be a masked "|K...|k" placeholder (confirmed live for the
-- search path -- neither source is safe at an arbitrary point in time),
-- and sorting on masked bytes produces a stable-looking but scrambled
-- order that's invisible in debug prints, because the chat frame silently
-- renders masked tokens as the real name (confirmed live: the offline
-- block looked "randomly ordered" in-game while a debug dump printed sane
-- names -- the sort had compared masked bytes). Fall back through
-- sources; the battleTag ("Name#1234") is not subject to |K masking, so
-- there's always a stable, human-sensible final key.
-- resolvedName is optional: pass the account name if you already hold it.
--
-- The raw tuple's name is masked for essentially every friend on this client,
-- so the cheap path above is never taken and this used to mean one full
-- C_BattleNet.GetFriendAccountInfo per friend per rebuild purely to produce a
-- sort key -- measured at 256 of 432 calls, the single largest source. The
-- rebuild's per-friend pass already fetches that name for online friends, so it
-- hands it in rather than paying for it twice.
--
-- Pass `false` (not nil) for "no name available" to suppress the refetch.
-- Resolved sort names, keyed on presenceID.
--
-- Keyed on the friend's STABLE identity, never the list index: an index-keyed
-- cache renders one friend's data under another's row as soon as Blizzard
-- reindexes the list (tried during this work; it corrupted the display).
local SocialPlus_SortNameCache={}

-- True when a friend's reported area is an arena map.
--
-- areaName is the arena's own map name for someone in one -- a friend in a
-- skirmish reads "Ruins of Lordaeron" (confirmed live), not their parent zone --
-- so matching the map list in Locales.lua is enough. Blizzard localizes the
-- string, which is why that list lives in the locale file.
--
-- Deliberately a GLOBAL, not a file-local: this chunk is at Lua's 200-locals
-- ceiling (adding two here hit 201), and a global is also visible to the row
-- renderer above, which would otherwise call it before its declaration.
-- Accent-insensitive key for zone matching.
--
-- Blizzard's own strings carry accents -- the locale file's "Arene de Nagrand"
-- is really "Ar\195\168ne de Nagrand" in game -- so both sides have to be
-- or the arena icon simply never appears, with nothing to debug.
--
-- Folded through the search normaliser rather than through a table of its own.
-- The table that used to live here had its escape sequences mangled at some
-- point: every key held a control byte and some literal digits where a UTF-8
-- pair belonged, and two keys collided on top of that. Nothing accented has
-- ever matched, so French and Spanish arena detection has never worked.
--
-- escapecheck does not see this class of damage, and a second copy of a map we
-- already maintain is what let it rot unnoticed -- so the copy is gone rather
-- than repaired. SOCIALPLUS_ACCENT_MAP is exercised by every search.
--
-- NormalizeText also drops spaces and punctuation. Harmless here: the lookup
-- table and the query are both built with this same function.
function SocialPlus_FoldZoneName(text)
	if type(text)~="string" then return "" end
	return SocialPlus_NormalizeText(text)
end

SocialPlus_ArenaZoneLookup=nil
function SocialPlus_IsArenaZone(areaName)
	if type(areaName)~="string" or areaName=="" then return false end
	if not SocialPlus_ArenaZoneLookup then
		SocialPlus_ArenaZoneLookup={}
		local list=L and L.ARENA_ZONES
		if type(list)=="table" then
			for _,z in ipairs(list) do
				if type(z)=="string" and z~="" then
					SocialPlus_ArenaZoneLookup[SocialPlus_FoldZoneName(z)]=true
				end
			end
		end
	end
	-- The row appends " - Realm" to the location, but areaName itself is bare;
	-- trim defensively in case a caller passes the composed string.
	local bare=areaName:match("^(.-)%s+%-%s+.*$") or areaName
	return SocialPlus_ArenaZoneLookup[SocialPlus_FoldZoneName(bare)]==true
end

local function SocialPlus_GetBNetSortName(i,resolvedName)
	-- Multiple assignment instead of a {tuple} wrapper: this runs once per BNet
	-- friend per full rebuild, and the 19-slot throwaway table added up
	-- under collapse/scroll spam (reported live as GC-churn memory peaks).
	local presenceID,rawName,battleTag=FG_BNGetFriendInfo(i)
	if rawName and rawName~="" and not SocialPlus_IsMaskedPlaceholder(rawName) then
		return rawName
	end
	-- The cache holds the FINAL sort name, not the resolved account name.
	-- Caching only the resolved name achieved nothing: for these friends the
	-- account name is masked too, so the function fell through to the battleTag
	-- branch below and never stored anything, refetching every rebuild to reach
	-- the same answer (measured: unchanged at 172 calls).
	if resolvedName==nil then
		local cached=presenceID and SocialPlus_SortNameCache[presenceID]
		if cached then return cached end
		resolvedName=GetFriendInfoById(i)
	end

	local final
	if resolvedName and resolvedName~="" and not SocialPlus_IsMaskedPlaceholder(resolvedName) then
		final=resolvedName
	elseif battleTag and battleTag~="" then
		-- Strip the numeric discriminator so "Dusk#12735" sorts as "Dusk"
		final=battleTag:match("^([^#]+)") or battleTag
	else
		final=rawName
	end

	-- Not cached during the post-login warmup: account data streams in for a
	-- few seconds, and a name derived from the battleTag fallback then would
	-- stick for the session instead of being replaced by the real one once it
	-- arrives. After warmup, a masked name is masked for good.
	if presenceID and type(final)=="string" and final~=""
		and GetTime()>(SocialPlus_ScanWarmupUntil or 0) then
		SocialPlus_SortNameCache[presenceID]=final
	end
	return final
end

local function CreateNote(note,groups)
	local value=""
	if note then
		value=note
	end
	for group in pairs(groups) do
		-- "" is the ungrouped sentinel, never a real tag -- skip it so a
		-- note that picked up an empty tag from corruption doesn't keep
		-- re-persisting it every time any other group gets renamed/edited.
		if group~="" then
			value=value.."#"..group
		end
	end
	return value
end

local function AddGroup(note,group)
	local groups={}
	note=NoteAndGroups(note,groups)
	groups[""]=nil
	groups[group]=true
	return CreateNote(note,groups)
end

local function RemoveGroup(note,group)
	local groups={}
	note=NoteAndGroups(note,groups)
	groups[""]=nil
	groups[group]=nil
	return CreateNote(note,groups)
end

local function IncrementGroup(group,online)
	if not GroupTotal[group] then
		GroupCount=GroupCount+1
		GroupTotal[group]=0
		GroupOnline[group]=0
	end
	GroupTotal[group]=GroupTotal[group]+1
	if online then
		GroupOnline[group]=GroupOnline[group]+1
	end
end

-- [[ Friend-list shape: totals and online counts, as one comparable value ]]
--
-- A FriendButtons entry holds a LIST INDEX, and Blizzard re-sorts both friend
-- lists when somebody logs on or off -- so an index recorded by one derivation
-- can point at a different friend by the time anything renders it. Both
-- deferral paths in SocialPlus_Update repaint WITHOUT re-deriving, and that is
-- where the mismatch reaches the screen: the rows keep the group placement the
-- old pass gave them while their names come from the new order, so friends
-- appear under groups they are not in and the count beside a header no longer
-- describes the names under it.
--
-- Reported live from combat, where the deferral holds for a whole fight rather
-- than the single frame the coalescing path holds for.
--
-- Four O(1) counts. It cannot see a reorder that leaves every count identical,
-- but a reorder comes from a login, a logout, or a friend added or removed,
-- and each of those moves one of these numbers.
--
-- Global rather than a file local: this chunk is at Lua's 200-local ceiling
-- (see the notes on the click catcher and the tooltip).
function SocialPlus_ListShape()
	local bnetTotal,bnetOnline=FG_BNGetNumFriends()
	return format("%d/%d/%d/%d",bnetTotal or 0,bnetOnline or 0,
		FG_GetNumFriends() or 0,FG_GetNumOnlineFriends() or 0)
end

-- [[ Master update: builds FriendButtons + groups ]]
    function SocialPlus_Update(forceUpdate)

	-- Guards come first — before any Blizzard API call.
	-- Our hooksecurefunc fires for EVERY FriendsList_Update regardless of which
	-- tab is active.  Calling Blizzard APIs (BNGetNumFriends, QuickJoinToast…)
	-- from this tainted closure taints their side-effects and blocks
	-- CopyToClipboard in the /who unit popup.  Skip everything when not needed.
	if not forceUpdate then
		if FriendsListFrame and not FriendsListFrame:IsShown() then return end
		if FriendsFrame then
			local tabID=PanelTemplates_GetSelectedTab(FriendsFrame) or FriendsFrame.selectedTab
			if tabID and tabID~=1 then return end
		end
	end

	-- At most one full per-friend derivation per frame.
	--
	-- This is hooked onto Blizzard's FriendsList_Update, which they call from
	-- FRIENDLIST_UPDATE and BN_FRIEND_INFO_CHANGED -- and on a large list those
	-- do not arrive one at a time. Every friend who changes zone, flips AFK,
	-- switches character or updates a broadcast fires one, so they land in
	-- bursts of many within a single frame, and each one was paying the whole
	-- derivation again: measured at ~32ms across 866 friends, so a burst of
	-- five in one frame is 160ms of one frame spent re-deriving data that
	-- cannot have changed enough between two calls to be worth it. Reported
	-- live as heavy lag opening and scrolling a ~460-friend list.
	--
	-- Deferred, never dropped. The extras schedule one catch-up pass on the
	-- next frame instead of each doing their own now, so nothing goes stale --
	-- a burst of twenty collapses to two derivations rather than twenty. The
	-- render still runs on every call, because it is the cheap half (~2.5ms)
	-- and it is what keeps rows and the tooltip in sync.
	--
	-- Globals rather than file-locals on purpose: this chunk is at Lua's
	-- 200-local ceiling (see the notes on the click catcher and tooltip).
	-- Only the unforced calls coalesce. Forced ones are the deliberate,
	-- user-initiated passes -- a collapse toggle runs HardResetScrollRows
	-- (which hides every row) and then forces a pass, so deferring THAT
	-- derivation would re-render the pre-collapse list for a frame. Bursts
	-- only ever arrive through the unforced FriendsList_Update hook, so
	-- exempting forced calls costs nothing and keeps every interaction exact.
	local nowDataFrame=(GetTime and GetTime()) or 0
	-- ...unless the list itself moved. Coalescing assumes the rows already
	-- built still describe the same friends, and a login landing mid-burst
	-- breaks that for every row after it. Cheap enough to test on every
	-- call, and it only costs a second derivation in the frame somebody
	-- actually came online. See SocialPlus_ListShape.
	if not forceUpdate and SOCIALPLUS_LAST_DATA_FRAME==nowDataFrame
		and SocialPlus_ListShape()==SOCIALPLUS_LIST_SHAPE then
		SOCIALPLUS_COALESCED_PASSES=(SOCIALPLUS_COALESCED_PASSES or 0)+1
		if not SOCIALPLUS_DATA_CATCHUP_QUEUED then
			SOCIALPLUS_DATA_CATCHUP_QUEUED=true
			C_Timer.After(0,function()
				SOCIALPLUS_DATA_CATCHUP_QUEUED=false
				-- Unforced, so the panel-hidden and wrong-tab guards above
				-- still apply: a burst that ends with the list closed must
				-- not buy itself one last full pass on the way out.
				SocialPlus_Update()
			end)
		end
		SocialPlus_UpdateFriends()
		return
	end
	SOCIALPLUS_LAST_DATA_FRAME=nowDataFrame

	-- Not during a fight.
	--
	-- The derivation is the single most expensive thing this addon does, and
	-- combat is when a dropped frame actually costs something. Nothing it
	-- produces is worth a stutter mid-pull: a friend who came online during a
	-- boss is news that keeps. The rows still repaint, so what is already on
	-- screen stays live and correct-looking; only the re-derivation waits.
	--
	-- Deferred, not dropped -- PLAYER_REGEN_ENABLED flushes it the moment the
	-- fight ends, and the dirty flag is set so the settle path knows a real
	-- pass is still owed. Forced calls are exempt for the same reason they are
	-- exempt from coalescing: those are somebody clicking something, and a
	-- click has to answer even in combat.
	-- Same exception as the coalescing path above, and this is the one that
	-- was reported: a fight lasts long enough for several friends to log on
	-- and off, and holding the old index-to-friend mapping across that put
	-- the wrong names under the group headers for the rest of the fight. A
	-- friend coming online mid-pull now costs one derivation -- rare, and
	-- the alternative is a list that is quietly wrong.
	if not forceUpdate and InCombatLockdown and InCombatLockdown()
		and SocialPlus_ListShape()==SOCIALPLUS_LIST_SHAPE then
		SOCIALPLUS_DATA_DIRTY=true
		SOCIALPLUS_COMBAT_DEFERRED=true
		SocialPlus_UpdateFriends()
		return
	end

	-- The EXPENSIVE pass, counted separately from the render.
	--
	-- SOCIALPLUS_REBUILD_COUNT in SocialPlus_UpdateFriends counts renders, and
	-- the scroll handler calls that directly without any of the per-friend work
	-- below -- so a render is far cheaper than one of these, and the two must
	-- not be added together or multiplied by the same per-rebuild figure.
	-- /spsim bench times THIS function, so this is the count that figure
	-- applies to.
	--
	-- After the guards on purpose: a call that bails because the panel is
	-- hidden costs nothing and must not be counted as work.
	--
	if forceUpdate then
		SOCIALPLUS_SKIP_FORCED=(SOCIALPLUS_SKIP_FORCED or 0)+1
		-- Attribution, off unless /spsim rate turns it on. Knowing how many
		-- passes were forced without knowing WHICH call site forced them sent
		-- two fixes at the wrong target; naming them found the two settle
		-- timers in one run. debugstack is not cheap, hence the flag -- but
		-- forced passes run about once a second, so while it is on the cost is
		-- irrelevant next to the 32ms it is measuring.
		if SOCIALPLUS_TRACE_FORCED and debugstack then
			local where=debugstack(2,1,0)
			where=where and where:match("([%w_%-%.]+%.lua:%d+)") or "?"
			SOCIALPLUS_FORCED_CALLERS=SOCIALPLUS_FORCED_CALLERS or {}
			SOCIALPLUS_FORCED_CALLERS[where]=(SOCIALPLUS_FORCED_CALLERS[where] or 0)+1
		end
	end

	-- Cleared once the derivation below is about to run, so the two settle
	-- timers can tell whether anything actually changed while they waited.
	-- Set by any registered event (see the OnEvent handler).
	--
	-- There is deliberately no "skip the pass while scrolling" check here any
	-- more. One was tried, and measured: it fired 0, 1 and 0 times across three
	-- runs, because the passes it aimed at were never Blizzard's scroll-driven
	-- FriendsList_Update -- they were this addon's own settle timers, which the
	-- attribution above identified. The flag stays because those timers read
	-- it; the skip went because it did nothing.
	SOCIALPLUS_DATA_DIRTY=false

	SOCIALPLUS_DATA_PASS_COUNT=(SOCIALPLUS_DATA_PASS_COUNT or 0)+1

	local numBNetTotal,numBNetOnline=FG_BNGetNumFriends()
	numBNetTotal=numBNetTotal or 0
	numBNetOnline=numBNetOnline or 0
	local numWoWTotal=FG_GetNumFriends()
	local numWoWOnline=FG_GetNumOnlineFriends()
	local numWoWOffline=numWoWTotal-numWoWOnline
	-- The mapping the rows below are about to be built against. Every render
	-- that skips this derivation checks it before trusting them.
	SOCIALPLUS_LIST_SHAPE=SocialPlus_ListShape()
	if QuickJoinToastButton then
		QuickJoinToastButton:UpdateDisplayedFriendCount()
	end

	-- AddButtonInfo shared by both search and normal mode
	local addButtonIndex=0
	local totalButtonHeight=0

	-- Which BNet friends actually reach the screen this pass.
	--
	-- Recorded here rather than at the three call sites that add a BNet row,
	-- because this is the one place all of them go through -- favourites,
	-- recently-added and ordinary groups alike, in search mode as well as out
	-- of it. A friend whose every group is collapsed never gets here, which is
	-- exactly the fact the derivation below wants.
	local BNetShown={}

	-- The stable identity of the friend a row was built for.
	--
	-- A row's .id is a LIST INDEX, and indices renumber on their own when
	-- somebody logs on or off (see SocialPlus_ListShape). Every render that
	-- skips the derivation is drawing from indices an older pass recorded, so
	-- the row has to carry something that CANNOT drift for the render to
	-- check itself against: presenceID for a Battle.net friend, the character
	-- name for a WoW one.
	--
	-- Filled by the two bucketing loops below as they read each friend, so in
	-- normal mode this costs no calls at all -- the lookup is only ever made
	-- for a row the loops have not reached, which means search mode, where
	-- AddButtonInfo builds the layout on its own and there are few rows.
	--
	-- Discarded with the pass, never a memo that outlives it -- same rule the
	-- per-friend derivation states further down, and for the same reason.
	local BNetKey={}
	local WoWKey={}
	local function RowKey(buttonType,id)
		if buttonType==FRIENDS_BUTTON_TYPE_BNET then
			local key=BNetKey[id]
			if key==nil then
				key=FG_BNGetFriendInfo(id) or false
				BNetKey[id]=key
			end
			return key or nil
		elseif buttonType==FRIENDS_BUTTON_TYPE_WOW then
			local key=WoWKey[id]
			if key==nil then
				local info=FG_GetFriendInfoByIndex(id)
				key=(info and info.name) or false
				WoWKey[id]=key
			end
			return key or nil
		end
		return nil
	end

	local function AddButtonInfo(buttonType,id)
		if buttonType==FRIENDS_BUTTON_TYPE_BNET then BNetShown[id]=true end
		addButtonIndex=addButtonIndex+1
		if not FriendButtons[addButtonIndex] then
			FriendButtons[addButtonIndex]={}
		end
		FriendButtons[addButtonIndex].buttonType=buttonType
		FriendButtons[addButtonIndex].id=id
		FriendButtons[addButtonIndex].key=RowKey(buttonType,id)
		FriendButtons.count=addButtonIndex
		totalButtonHeight=totalButtonHeight+FRIENDS_BUTTON_HEIGHTS[buttonType]
	end

	-- If the search text exactly matches an existing custom group name,
	-- show that group's real header (cogwheel, collapse/expand) with only
	-- its members instead of the flat name-only list below -- on request.
	-- Falls through to the normal grouped-mode path further down instead
	-- of the simple search path, with every OTHER group treated as
	-- collapsed for DISPLAY ONLY (SocialPlus_SavedVars.collapsed itself is
	-- never touched, so this doesn't disturb the user's real collapse
	-- state).
	SocialPlus_SearchFocusGroup=nil
	if SocialPlus_SearchTerm and SocialPlus_SavedVars and SocialPlus_SavedVars.groupOrder then
		for _,g in ipairs(SocialPlus_SavedVars.groupOrder) do
			if SocialPlus_NormalizeText(g)==SocialPlus_SearchTerm then
				SocialPlus_SearchFocusGroup=g
				break
			end
		end
	end
	local function SocialPlus_IsCollapsedForDisplay(group)
		if SocialPlus_SearchFocusGroup then
			return group~=SocialPlus_SearchFocusGroup
		end
		return SocialPlus_SavedVars.collapsed[group]
	end

	-- >>> SIMPLE NAME-ONLY SEARCH MODE (no groups) <<<
	if SocialPlus_SearchTerm and not SocialPlus_SearchFocusGroup then
		wipe(FriendButtons)
		-- wipe() erases the count field too -- re-set it explicitly, since
		-- AddButtonInfo only re-sets it when at least one row matches (a
		-- zero-match search left it nil, confirmed live as a hard error
		-- in SocialPlus_GetTopButton).
		FriendButtons.count=0
		wipe(GroupTotal)
		wipe(GroupOnline)
		GroupCount=0
		addButtonIndex=0
		totalButtonHeight=0

		local term=SocialPlus_SearchTerm

		-- Friends who show up BOTH as a Battle.net friend (their BattleTag)
		-- and as a plain WoW/character friend (added separately) are the
		-- same real person -- collected below while walking BNet friends
		-- so the WoW-friend pass further down can skip them, otherwise a
		-- search matched both rows and showed that person twice (reported
		-- live: class-name search). Keyed by name+realm rather than just
		-- name -- a WoW-friend name for a connected-but-different realm has
		-- that realm baked in as a "-Realm" suffix (e.g. "Bukowsky-Pagle"),
		-- while the Battle.net API returns characterName/realmName as
		-- separate fields, so both sides normalize through the same
		-- name|realm key below.
		local bnetActiveWowChars={}
		local function SocialPlus_DedupeRealmKey(realm)
			if not realm or realm=="" then
				realm=(GetRealmName and GetRealmName()) or ""
			end
			return SocialPlus_NormalizeText((realm:gsub("[%s%-]","")))
		end

		-- BNet friends: try BattleTag first, then accountName, then character name
		for i=1,numBNetTotal do
			local accountName,characterName,class,_,_,isOnline,_,client,_,wowProjectID,_,_,_,_,_,_,_,_,realmName,friendRegionID,_,infoBattleTag=
				GetFriendInfoById(i)

			if isOnline and client==BNET_CLIENT_WOW and wowProjectID==WOW_PROJECT_ID
				and characterName and characterName~="" then
				local key=SocialPlus_NormalizeText(characterName).."|"..SocialPlus_DedupeRealmKey(realmName)
				bnetActiveWowChars[key]=true
			end

			if not(SocialPlus_SavedVars and SocialPlus_SavedVars.hide_offline and not isOnline) then
				-- BattleTag and region both came back from the
				-- GetFriendInfoById above (positions 22 and 20).
				--
				-- This used to make a SECOND C_BattleNet.GetFriendAccountInfo
				-- for the same friend purely to read those two fields -- and
				-- GetFriendInfoById's own first act is that exact call, so
				-- every friend was paying for the single most expensive lookup
				-- in this file twice. This is the live search path, walked in
				-- full on every keystroke, so on a 460-friend list that was 460
				-- duplicated account lookups per typed character.
				--
				-- The old `or acct.accountName` fallback is preserved and is
				-- the same value either way: GetFriendInfoById reads
				-- accountName off that very account record, so `accountName`
				-- here and `acct.accountName` there were always identical.
				local battleTag=infoBattleTag or accountName

				local primaryName=battleTag
					or accountName
					or characterName
					or ""

				-- Normalize first word for search (ignores accents and symbols)
				local normalized=SocialPlus_NormalizeText(firstWord(primaryName))
				local classNormalized=SocialPlus_NormalizeText(SocialPlus_BuildClassSearchBlob(class))
				local noteText=select(13,FG_BNGetFriendInfo(i))
				local noteNormalized=SocialPlus_NormalizeText(SocialPlus_BuildNoteSearchBlob(FRIENDS_BUTTON_TYPE_BNET,i,noteText))

				-- accountName is the Real ID display name when Battle.net
				-- shares one for this friend (e.g. an actual first+last
				-- name), distinct from their BattleTag -- but battleTag
				-- takes priority above for primaryName, so a friend's real
				-- name was never actually searched at all when they also
				-- had a BattleTag. Search it as a substring, not anchored to
				-- the first word, since a real name has multiple words that
				-- might each be searched.
				--
				-- Both GetFriendInfoById's accountName AND the raw
				-- BNGetFriendInfo tuple's can transiently be a masked
				-- "|K...|k" placeholder before the name finishes resolving
				-- -- confirmed live neither source is safe at an arbitrary
				-- point in time (this looked fixed once already, using the
				-- raw tuple, but that was coincidence: it just hadn't hit
				-- the masked case in that particular test). Detect and
				-- reject the masked shape outright instead of trusting
				-- either source; a masked name just means "no match this
				-- refresh" rather than matching on garbage.
				local rawAccountName=select(2,FG_BNGetFriendInfo(i))
				local realNameNormalized=""
				if rawAccountName and not SocialPlus_IsMaskedPlaceholder(rawAccountName) then
					realNameNormalized=SocialPlus_NormalizeText(rawAccountName)
				end

				-- Class-name search only matches friends online on the exact
				-- same WoW version as this client -- typing "sham" on TBC
				-- shouldn't surface a Retail friend's Shaman just because
				-- Blizzard still reports their class while offline/elsewhere.
				-- Same-region required too (reported live: a same-version
				-- friend in a different region -- EU vs NA -- still isn't
				-- someone this player could actually play/group with, so
				-- shouldn't surface on a class search either).
				-- Call the accessor, not the bare module-local cache
				-- variable of the same name (which may still be nil/
				-- uncomputed the first time this runs) -- same pattern
				-- every other region check in this file uses.
				local myRegionID=SocialPlus_GetClientRegionID()
				local sameRegion=(not friendRegionID) or (not myRegionID) or friendRegionID==myRegionID
				local classMatches=isOnline and wowProjectID==WOW_PROJECT_ID and sameRegion and containsPlain(classNormalized,term)

				if startsWith(normalized,term) or classMatches
					or containsPlain(noteNormalized,term) or containsPlain(realNameNormalized,term) then
					AddButtonInfo(FRIENDS_BUTTON_TYPE_BNET,i)
				end
			end
		end

		-- WoW friends: character name
		for i=1,numWoWTotal do
			local fi=FG_GetFriendInfoByIndex(i)
			local name=fi and fi.name or nil
			local connected=fi and fi.connected or false

			local dedupeKey=nil
			if name and name~="" then
				local baseName,suffixRealm=name:match("^(.-)%-([^%-]+)$")
				if baseName and suffixRealm then
					dedupeKey=SocialPlus_NormalizeText(baseName).."|"..SocialPlus_DedupeRealmKey(suffixRealm)
				else
					dedupeKey=SocialPlus_NormalizeText(name).."|"..SocialPlus_DedupeRealmKey(nil)
				end
			end

			if SocialPlus_SavedVars and SocialPlus_SavedVars.hide_offline and not connected then
				-- skip offline if setting says so
			elseif dedupeKey and bnetActiveWowChars[dedupeKey] then
				-- Same person already surfaced above via their Battle.net
				-- friend row -- skip the redundant WoW-friend duplicate.
			elseif name and name~="" then
				local searchName=SocialPlus_NormalizeText(firstWord(name))
				local classNormalized=SocialPlus_NormalizeText(SocialPlus_BuildClassSearchBlob(fi and fi.className))
				local noteNormalized=SocialPlus_NormalizeText(SocialPlus_BuildNoteSearchBlob(FRIENDS_BUTTON_TYPE_WOW,i,(fi and fi.notes) or ""))
				-- Native WoW friends are always on this exact client already
				-- (Classic's WoW-friend system is same-realm only), so class
				-- search here just needs an online check to match the BNet
				-- branch's "online + same version" rule above.
				local classMatches=connected and containsPlain(classNormalized,term)
				if startsWith(searchName,term) or classMatches or containsPlain(noteNormalized,term) then
					AddButtonInfo(FRIENDS_BUTTON_TYPE_WOW,i)
				end
			end
		end

		FriendsScrollFrame.totalFriendListEntriesHeight=totalButtonHeight
		FriendsScrollFrame.numFriendListEntries=addButtonIndex

		SocialPlus_UpdateFriends()
		return
	end

	-- <<< END SEARCH MODE >>>

	-- normal grouped mode below
	wipe(FriendButtons)
	wipe(GroupTotal)
	wipe(GroupOnline)
	wipe(GroupSorted)
	GroupCount=0

	local BnetSocialPlus={}
	local WowSocialPlus={}
	local FriendReqGroup={}
	local BNetOnlineStatus={}
	-- Favourite/recent key per friend, captured from the BNGetFriendInfo call
	-- the bucketing pass already makes and handed to the per-friend pass below
	-- so it doesn't call BNGetFriendInfo a second time for the same BattleTag.
	-- Same discipline as BNetOnlineStatus beside it: filled in one tight pass,
	-- read in the next, discarded with the rebuild -- never a memo that
	-- outlives it, which is what previously rendered one friend under another's
	-- row (see the note above the per-friend pass).
	local BNetFavKey={}

	local buttonCount=0

	FriendButtons.count=0
	addButtonIndex=0
	totalButtonHeight=0

	-- Invites
	local numInvites=FG_BNGetNumFriendInvites()
	if numInvites>0 then
		for i=1,numInvites do
			if not FriendReqGroup[i] then
				FriendReqGroup[i]={}
			end
			IncrementGroup(FriendRequestString,true)
			NoteAndGroups(nil,FriendReqGroup[i])
			if not SocialPlus_IsCollapsedForDisplay(FriendRequestString) then
				buttonCount=buttonCount+1
				AddButtonInfo(FRIENDS_BUTTON_TYPE_INVITE,i)
			end
		end
	end

	-- BNet friends (all)
	for i=1,numBNetTotal do
		-- Positional destructure instead of a {tuple} wrapper -- same
		-- per-friend-per-rebuild allocation savings as
		-- SocialPlus_GetBNetSortName (positions 1=presenceID, 3=battleTag,
		-- 8=isOnline, 13=note).
		local presenceID,_,battleTag,_,_,_,_,isOnline,_,_,_,_,noteText=FG_BNGetFriendInfo(i)
		isOnline=isOnline and true or false

		BNetOnlineStatus[i]=isOnline
		-- Handed to RowKey above rather than looked up again: position 1 of
		-- the tuple this loop already destructured.
		BNetKey[i]=presenceID or false
		-- The favourite key is just "BNET:"..battleTag (see
		-- SocialPlus_GetFavoriteKey), and the tag is already in hand here.
		-- Deriving it now saves the per-friend pass a whole BNGetFriendInfo
		-- call each for the favourite and recent tests. false, not nil, so an
		-- unresolved tag is a cached "no key" rather than a gap that reads as
		-- "not looked up yet".
		BNetFavKey[i]=(battleTag and battleTag~="" and ("BNET:"..battleTag)) or false
		-- Note/group membership is parsed and kept as-is regardless of
		-- favorite status -- favoriting only changes where the friend
		-- renders below, never their stored group assignment. Reuse the
		-- cached parse when this friend's raw note hasn't changed since
		-- last time (see SocialPlus_BNetNoteCache above) instead of
		-- re-parsing every single rebuild.
		-- The note we are writing, if one is still in flight for this friend.
		--
		-- Substituted before anything parses it, so every consumer below -- the
		-- cache, the bucketing, the group counts -- sees the finished state.
		-- See SocialPlus_BulkNoteFor.
		local pendingNote=SocialPlus_BulkNoteFor(presenceID)
		if pendingNote then noteText=pendingNote end

		local cached=presenceID and SocialPlus_BNetNoteCache[presenceID]
		if cached and cached.rawNote==noteText then
			BnetSocialPlus[i]=cached.groups
		else
			BnetSocialPlus[i]={}
			NoteAndGroups(noteText,BnetSocialPlus[i])
			if presenceID then
				SocialPlus_BNetNoteCache[presenceID]={rawNote=noteText,groups=BnetSocialPlus[i]}
			end
		end

		-- A favorited friend renders ONLY under the virtual Favorites
		-- group, not also under their real group(s) -- move semantics,
		-- not a copy.
		if SocialPlus_IsFavorite(FRIENDS_BUTTON_TYPE_BNET,i) then
			IncrementGroup(SP_FAVORITES_GROUP,isOnline)
			if not SocialPlus_IsCollapsedForDisplay(SP_FAVORITES_GROUP) then
				if isOnline or not(SocialPlus_SavedVars.hide_offline) then
					buttonCount=buttonCount+1
					AddButtonInfo(FRIENDS_BUTTON_TYPE_BNET,i)
				end
			end
		elseif SocialPlus_IsRecent(FRIENDS_BUTTON_TYPE_BNET,i,BnetSocialPlus[i]) then
			-- Move semantics, exactly as Favorites has: somebody added this
			-- session shows here and not also under General, or the point of a
			-- "look at these" group is lost to a duplicate.
			IncrementGroup(SocialPlus_RECENT_GROUP,isOnline)
			if not SocialPlus_IsCollapsedForDisplay(SocialPlus_RECENT_GROUP) then
				if isOnline or not(SocialPlus_SavedVars.hide_offline) then
					buttonCount=buttonCount+1
					AddButtonInfo(FRIENDS_BUTTON_TYPE_BNET,i)
				end
			end
		else
			for group in pairs(BnetSocialPlus[i]) do
				IncrementGroup(group,isOnline)
				if not SocialPlus_IsCollapsedForDisplay(group) then
					if isOnline or not(SocialPlus_SavedVars.hide_offline) then
						buttonCount=buttonCount+1
						AddButtonInfo(FRIENDS_BUTTON_TYPE_BNET,i)
					end
				end
			end
		end
	end

	-- WoW friends online
	for i=1,numWoWOnline do
		local fi=FG_GetFriendInfoByIndex(i)
		local note=fi and fi.notes
		local wowName=fi and fi.name
		WoWKey[i]=wowName or false
		-- Same cache-by-stable-identity approach as the BNet loop above --
		-- character name, not list index.
		local cached=wowName and SocialPlus_WoWNoteCache[wowName]
		if cached and cached.rawNote==note then
			WowSocialPlus[i]=cached.groups
		else
			WowSocialPlus[i]={}
			NoteAndGroups(note,WowSocialPlus[i])
			-- Ungrouped native friends live in the In-game Friends bucket,
			-- not General ("" is the ungrouped sentinel NoteAndGroups sets).
			if WowSocialPlus[i][""] then
				WowSocialPlus[i][""]=nil
				WowSocialPlus[i][SP_INGAME_GROUP]=true
			end
			if wowName then
				SocialPlus_WoWNoteCache[wowName]={rawNote=note,groups=WowSocialPlus[i]}
			end
		end
		if SocialPlus_IsFavorite(FRIENDS_BUTTON_TYPE_WOW,i) then
			IncrementGroup(SP_FAVORITES_GROUP,true)
			if not SocialPlus_IsCollapsedForDisplay(SP_FAVORITES_GROUP) then
				buttonCount=buttonCount+1
				AddButtonInfo(FRIENDS_BUTTON_TYPE_WOW,i)
			end
		elseif SocialPlus_IsRecent(FRIENDS_BUTTON_TYPE_WOW,i,WowSocialPlus[i]) then
			IncrementGroup(SocialPlus_RECENT_GROUP,true)
			if not SocialPlus_IsCollapsedForDisplay(SocialPlus_RECENT_GROUP) then
				buttonCount=buttonCount+1
				AddButtonInfo(FRIENDS_BUTTON_TYPE_WOW,i)
			end
		else
			for group in pairs(WowSocialPlus[i]) do
				IncrementGroup(group,true)
				if not SocialPlus_IsCollapsedForDisplay(group) then
					buttonCount=buttonCount+1
					AddButtonInfo(FRIENDS_BUTTON_TYPE_WOW,i)
				end
			end
		end
	end

	-- WoW friends offline
	for i=1,numWoWOffline do
		local j=i+numWoWOnline
		local fj=FG_GetFriendInfoByIndex(j)
		local note=fj and fj.notes
		local wowName=fj and fj.name
		WoWKey[j]=wowName or false
		local cached=wowName and SocialPlus_WoWNoteCache[wowName]
		if cached and cached.rawNote==note then
			WowSocialPlus[j]=cached.groups
		else
			WowSocialPlus[j]={}
			NoteAndGroups(note,WowSocialPlus[j])
			-- Same In-game Friends re-bucketing as the online loop above
			if WowSocialPlus[j][""] then
				WowSocialPlus[j][""]=nil
				WowSocialPlus[j][SP_INGAME_GROUP]=true
			end
			if wowName then
				SocialPlus_WoWNoteCache[wowName]={rawNote=note,groups=WowSocialPlus[j]}
			end
		end
		if SocialPlus_IsFavorite(FRIENDS_BUTTON_TYPE_WOW,j) then
			IncrementGroup(SP_FAVORITES_GROUP)
			if not SocialPlus_IsCollapsedForDisplay(SP_FAVORITES_GROUP) and not SocialPlus_SavedVars.hide_offline then
				buttonCount=buttonCount+1
				AddButtonInfo(FRIENDS_BUTTON_TYPE_WOW,j)
			end
		else
			for group in pairs(WowSocialPlus[j]) do
				IncrementGroup(group)
				if not SocialPlus_IsCollapsedForDisplay(group) and not SocialPlus_SavedVars.hide_offline then
					buttonCount=buttonCount+1
					AddButtonInfo(FRIENDS_BUTTON_TYPE_WOW,j)
				end
			end
		end
	end

	-- Finally, add one button per group divider
	buttonCount=buttonCount+GroupCount

	if buttonCount>#FriendButtons then
		for i=#FriendButtons+1,buttonCount do
			FriendButtons[i]={}
		end
	end

	for group in pairs(GroupTotal) do
    table.insert(GroupSorted,group)
end

SocialPlus_NoteNewFriends()
SocialPlus_ApplyGroupOrder()

    ----------------------------------------------------------------------
    -- Per-friend data, computed ONCE per rebuild.
    --
    -- Every field below depends only on the friend, never on the group --
    -- but it used to sit INSIDE the per-group loop, so a friend in N groups
    -- paid for it N times and each group rescanned the whole friend list
    -- (measured: ~1.75 C_BattleNet.GetFriendAccountInfo calls per friend per
    -- rebuild, 448 calls for 64 friends).
    --
    -- Deliberately NOT a cache that outlives the rebuild. Blizzard's
    -- friend-list index-to-friend mapping can shift between updates, so
    -- anything keyed on the list index that survives longer than a single
    -- pass eventually renders one friend's data under another's row --
    -- exactly what a same-frame memo did when tried here. Gathered in one
    -- tight pass, used immediately, discarded.
    ----------------------------------------------------------------------
    local usePrioritize=SocialPlus_SavedVars and SocialPlus_SavedVars.prioritize_current_client
    if usePrioritize and not playerFaction then FG_InitFactionIcon() end
    -- Offline rows are only ever built when they're shown, so don't pay for
    -- their sort names when they're hidden.
    local needOffline=not SocialPlus_SavedVars.hide_offline

    local BNetPre={}
    for i=1,numBNetTotal do
        local online=BNetOnlineStatus[i]
        -- Key handed in from the bucketing pass, so neither of these makes its
        -- own BNGetFriendInfo call for a BattleTag already read once.
        local favKey=BNetFavKey[i]
        local pre={fav=SocialPlus_IsFavorite(FRIENDS_BUTTON_TYPE_BNET,i,favKey) and true or false,
            recent=SocialPlus_IsRecent(FRIENDS_BUTTON_TYPE_BNET,i,BnetSocialPlus[i],favKey) and true or false}
        -- Everything below this point exists to sort and place a row. A friend
        -- whose every group is collapsed has no row, so none of it is ever
        -- read for them -- and GetFriendInfoById is the most expensive call in
        -- this file, three to five C calls deep (GetFriendAccountInfo, then
        -- BNGetFriendInfo, then BNGetGameAccountInfo, plus the linked-account
        -- scan). Paying that for somebody who cannot be seen was most of the
        -- derivation on a large list, where nearly everything is collapsed.
        --
        -- Defaults rather than nothing, deliberately. The comparator guards
        -- sortKey but does arithmetic on statusRank and clusterRank, so a nil
        -- reaching a sorted list would be a hard error rather than a wrong
        -- order. Ranks below every real value keep it total and keep any
        -- unforeseen path harmless.
        if online and not BNetShown[i] then
            pre.promoted=false
            pre.factionRank=1
            pre.statusRank=4
            pre.clusterRank=3
            pre.groupKey=""

        elseif online then
            local accountName,_,_,_,_,_,_,client,_,wowProjectID,_,
                isAFK,isGameAFK,isDND,isGameBusy,_,_,_,_,_,friendFaction=GetFriendInfoById(i)
            -- Reuse the name from the call we just made instead of making a
            -- second one inside the sort-key helper.
            pre.sortKey=SocialPlus_GetBNetSortName(i,accountName or false)
            pre.statusRank=SocialPlus_GetStatusRank(isAFK,isGameAFK,isDND,isGameBusy)
            pre.promoted=false
            pre.factionRank=1
            local isKnownAppCode=(not client) or client==(BNET_CLIENT_APP or "App") or client=="BSAp"
            if client==BNET_CLIENT_WOW then
                pre.groupKey="WoW:"..tostring(wowProjectID or "?")
                pre.clusterRank=0
                if usePrioritize and wowProjectID==WOW_PROJECT_ID then
                    pre.promoted=true
                    -- friendFaction comes from the GetFriendInfoById call
                    -- above. This used to re-fetch the whole account with a
                    -- second C_BattleNet.GetFriendAccountInfo just to read
                    -- factionName off it -- the same account that call had
                    -- already loaded.
                    pre.factionRank=(friendFaction and playerFaction and friendFaction==playerFaction) and 0 or 1
                end
            elseif isKnownAppCode then
                pre.groupKey="AppOnly"
                pre.clusterRank=2
            else
                -- A different game, not WoW. groupKey used to be all this
                -- needed -- "Client:x" against "WoW:y" -- but that was a
                -- plain string compare, and 'C' sorts before 'W'. It read as
                -- Overwatch friends bubbling above every WoW friend on a big
                -- Battle.net list, which is backwards for an addon that is
                -- specifically about WoW's friends list. clusterRank is the
                -- explicit ordering; groupKey goes back to only ever
                -- clustering rows that are already in the same tier.
                pre.groupKey="Client:"..client
                pre.clusterRank=1
            end
        elseif needOffline then
            pre.sortKey=SocialPlus_GetBNetSortName(i)
        end
        BNetPre[i]=pre
    end

    local WoWPre={}
    local wowScanTo=needOffline and numWoWTotal or numWoWOnline
    for i=1,wowScanTo do
        local info=FG_GetFriendInfoByIndex(i)
        -- Built from the info already in hand -- SocialPlus_GetFavoriteKey
        -- would call FG_GetFriendInfoByIndex again for the very same row, once
        -- for the favourite test and once more for the recent one.
        local favKey=(info and info.name and info.name~="" and ("WOW:"..info.name)) or false
        WoWPre[i]={
            fav=SocialPlus_IsFavorite(FRIENDS_BUTTON_TYPE_WOW,i,favKey) and true or false,
            recent=SocialPlus_IsRecent(FRIENDS_BUTTON_TYPE_WOW,i,WowSocialPlus[i],favKey) and true or false,
            sortKey=info and info.name,
            statusRank=SocialPlus_GetStatusRank(info and info.afk,false,info and info.dnd,false),
        }
    end

    ----------------------------------------------------------------------
    -- Group -> members index, built ONCE per rebuild.
    --
    -- The per-group loop below used to find each group's members by
    -- rescanning the WHOLE friend list once per group -- four scans per
    -- group (BNet online, WoW online, BNet offline, WoW offline), i.e.
    -- O(G*N) for G groups and N friends. That is the dominant rebuild cost
    -- for a 300+ friend list, and it is pure re-derivation: BnetSocialPlus
    -- and WowSocialPlus already hold every friend's group memberships, just
    -- indexed friend -> groups. Invert them here, in one pass over each
    -- list, so the loop below reads its own bucket instead of rescanning.
    --
    -- Bucket ORDER is load-bearing and matches the old scan order exactly:
    -- all BNet rows in friend-index order, then all WoW rows in
    -- friend-index order. table.sort is not stable, so identical output
    -- ordering depends on feeding the identical comparator an identically
    -- ordered input -- rows that tie must stay in the order they used to
    -- be appended in.
    ----------------------------------------------------------------------
    local OnlineRowsByGroup={}
    local OfflineRowsByGroup={}
    -- Shared stand-in for a group with no rows. Never written to: sorting
    -- and iterating it are both no-ops, which is exactly what the empty
    -- per-group table used to do.
    local EMPTY_ROWS={}

    -- A group the loop below never renders needs no bucket. This is the
    -- same short-circuit as before -- rows for a collapsed group were never
    -- built -- so collapsing still costs nothing. Covers the search-focus
    -- case too: SocialPlus_IsCollapsedForDisplay already reports every
    -- non-focused group as collapsed while a focus is active.
    local groupWantsRows={}
    local function GroupWantsRows(group)
        local want=groupWantsRows[group]
        if want==nil then
            want=not SocialPlus_IsCollapsedForDisplay(group)
            groupWantsRows[group]=want
        end
        return want
    end

    local function BucketRow(byGroup,group,row)
        if not GroupWantsRows(group) then return end
        local bucket=byGroup[group]
        if not bucket then
            bucket={}
            byGroup[group]=bucket
        end
        bucket[#bucket+1]=row
    end

    -- One row table per friend, shared by every bucket that friend lands in.
    -- Safe because rows are read-only once built (the comparators and the
    -- push loop only read them, table.sort only reorders the array), and it
    -- replaces the old one-allocation-per-friend-per-group churn.
    local function BucketFriend(byGroup,groups,fav,row,recent)
        if fav then
            -- Membership in the virtual Favorites group comes from the
            -- favorite flag, never from the friend's note tags, and it is a
            -- MOVE, not a copy: a favorited friend renders under Favorites
            -- ONLY, never also under their real group(s), which `groups`
            -- still lists because favoriting deliberately doesn't rewrite
            -- the note. Rendering them twice would overrun the row count
            -- pre-sized in the first pass (which correctly skips them) and
            -- index past the end of FriendButtons -- confirmed live.
            BucketRow(byGroup,SP_FAVORITES_GROUP,row)
        elseif recent then
            -- The same move, for the same reason, and it was missing here
            -- while the counting pass above already did it: a recent friend
            -- was counted once under Recently Added and then rendered under
            -- every group their note carries. A friend in two groups is one
            -- row more than was pre-sized, which indexes past the end of
            -- FriendButtons -- the very overrun the note above describes.
            BucketRow(byGroup,SocialPlus_RECENT_GROUP,row)
        elseif groups then
            for group in pairs(groups) do
                -- The converse of that move: a NON-favorited friend whose
                -- note literally carries the Favorites sentinel still does
                -- not render there, because the old membership test for
                -- that group was the favorite flag alone and ignored the
                -- parsed tags entirely.
                if group~=SP_FAVORITES_GROUP then
                    BucketRow(byGroup,group,row)
                end
            end
        end
    end

    -- BNet first, in friend-index order (see the bucket-order note above).
    for i=1,numBNetTotal do
        local pre=BNetPre[i]
        local online=BNetOnlineStatus[i]
        if online then
            BucketFriend(OnlineRowsByGroup,BnetSocialPlus[i],pre.fav,
                {buttonType=FRIENDS_BUTTON_TYPE_BNET,id=i,
                sortKey=pre.sortKey,statusRank=pre.statusRank,
                promoted=pre.promoted,factionRank=pre.factionRank,
                groupKey=pre.groupKey,clusterRank=pre.clusterRank},pre.recent)
        elseif needOffline and online==false then
            BucketFriend(OfflineRowsByGroup,BnetSocialPlus[i],pre.fav,
                {buttonType=FRIENDS_BUTTON_TYPE_BNET,id=i,sortKey=pre.sortKey},pre.recent)
        end
    end

    -- WoW second, so each bucket keeps the old "BNet rows, then WoW rows"
    -- pre-sort order.
    for i=1,numWoWOnline do
        local wpre=WoWPre[i]
        if wpre then
            BucketFriend(OnlineRowsByGroup,WowSocialPlus[i],wpre.fav,
                {buttonType=FRIENDS_BUTTON_TYPE_WOW,id=i,
                sortKey=wpre.sortKey,statusRank=wpre.statusRank,
                groupKey="WoW:"..tostring(WOW_PROJECT_ID or "?"),
                clusterRank=0,promoted=usePrioritize and true or false,
                factionRank=0},wpre.recent)
        end
    end

    if needOffline then
        for i=numWoWOnline+1,numWoWTotal do
            local wopre=WoWPre[i]
            if wopre then
                BucketFriend(OfflineRowsByGroup,WowSocialPlus[i],wopre.fav,
                    {buttonType=FRIENDS_BUTTON_TYPE_WOW,id=i,sortKey=wopre.sortKey},wopre.recent)
            end
        end
    end

    local index=0
    -- The rendering pass must never write past what the counting pass reserved.
    --
    -- The two passes have to agree about every group with "move" semantics --
    -- one where a friend renders under that group INSTEAD of their own. Recently
    -- Added was counted as a move and rendered as a copy, so a friend in two
    -- groups produced one row more than was booked and the write ran off the end
    -- of FriendButtons. Favorites had the same bug before it.
    --
    -- Nothing enforces that agreement, so this says which group was being
    -- rendered when the count ran out, once per rebuild rather than every row.
    -- The slot is created so the list still draws: a friends list that is one
    -- row wrong beats one that stops rendering.
    local overranAt
    local function TakeButton(at,group)
        local button=FriendButtons[at]
        if not button then
            if not overranAt then
                overranAt=group
                DEFAULT_CHAT_FRAME:AddMessage(("|cff4da6ff[SocialPlus]|r more rows than counted, "
                    .."from group '%s' -- please report this")
                    :format((group==nil or group=="") and "General" or tostring(group)))
            end
            button={}
            FriendButtons[at]=button
        end
        return button
    end

    for _,group in ipairs(GroupSorted) do
        -- During a group-name search focus, skip the header ROW entirely
        -- for every other group instead of just collapsing it -- on
        -- request, so only the matched group shows at all.
        local showGroup=not (SocialPlus_SearchFocusGroup and group~=SocialPlus_SearchFocusGroup)
        if showGroup then
        index=index+1
        local divider=TakeButton(index,group)
        divider.buttonType=FRIENDS_BUTTON_TYPE_DIVIDER
        divider.text=group
        -- Rows are reused across passes and across types; a divider landing on
        -- a slot that last held a friend must not inherit that friend's key.
        divider.key=nil

        if not SocialPlus_IsCollapsedForDisplay(group) then
            -- 1) Friend invites bucket (always same behavior)
            if group==FriendRequestString then
                for i=1,#FriendReqGroup do
                    index=index+1
                    local invite=TakeButton(index,group)
                    invite.buttonType=FRIENDS_BUTTON_TYPE_INVITE
                    invite.id=i
                    invite.key=nil
                end
            end

            ----------------------------------------------------------------
            -- Base order, always applied: WoW friends before friends playing
            -- something else before app-idle, same game/client clustered
            -- together within that, then status (online > DND > away) and
            -- alphabetical within each cluster.
            --
            -- "Prioritize <version> friends" adds one thing on top: friends
            -- on this exact WoW version bubble to the very top, ordered by
            -- status, then same faction first, then alphabetical. Everyone
            -- else still follows the base order below them.
            ----------------------------------------------------------------
            local onlineRows=OnlineRowsByGroup[group] or EMPTY_ROWS

            if SocialPlus_RowDebug then
                for _,row in ipairs(onlineRows) do
                    if row.buttonType==FRIENDS_BUTTON_TYPE_BNET then
                        print(string.format(
                            "|cff33ff99[ROWDEBUG]|r group=%q sortKey=%q promoted=%s statusRank=%s clusterRank=%s groupKey=%q factionRank=%s id=%s",
                            tostring(group),tostring(row.sortKey),tostring(row.promoted),
                            tostring(row.statusRank),tostring(row.clusterRank),tostring(row.groupKey),
                            tostring(row.factionRank),tostring(row.id)
                        ))
                    end
                end
            end

            table.sort(onlineRows,function(a,b)
                -- Favorites is now its own dedicated group (rendered
                -- separately above, never mixed with non-favorites in the
                -- same onlineRows set), so it uses the exact same rule as
                -- any other group: game cluster -> status -> alphabetical,
                -- with the "Prioritize" promoted block on top when enabled.
                --
                -- Game cluster outranks status on purpose: an Away WoW friend
                -- belongs beside an Online WoW friend, not off in an "Away"
                -- clump next to somebody Away in a different game entirely.
                -- Status used to be checked first, which split every game's
                -- friends across each status instead of keeping them together.
                if a.promoted~=b.promoted then return a.promoted end
                if a.clusterRank~=b.clusterRank then return a.clusterRank<b.clusterRank end
                if a.groupKey~=b.groupKey then return a.groupKey<b.groupKey end
                if a.statusRank~=b.statusRank then return a.statusRank<b.statusRank end
                if a.promoted and a.factionRank~=b.factionRank then return a.factionRank<b.factionRank end
                if a.buttonType~=b.buttonType then
                    return a.buttonType==FRIENDS_BUTTON_TYPE_BNET
                end
                if a.sortKey and b.sortKey then
                    local an,bn=SocialPlus_AsciiLower(a.sortKey),SocialPlus_AsciiLower(b.sortKey)
                    if an~=bn then return an<bn end
                end
                return (a.id or 0)<(b.id or 0)
            end)

            -- Push sorted online rows
            for _,row in ipairs(onlineRows) do
                index=index+1
                local slot=TakeButton(index,group)
                slot.buttonType=row.buttonType
                slot.id=row.id
                slot.key=RowKey(row.buttonType,row.id)
            end

            -- Offline at the bottom, unaffected by any of the above --
            -- but still alphabetized among themselves, same as online rows.
            -- These used to just get pushed in raw friend-index order
            -- (whatever order Blizzard's own friend list happens to store
            -- them in), not sorted at all -- reported live as offline
            -- friends not appearing A-Z.
            if not SocialPlus_SavedVars.hide_offline then
                local offlineRows=OfflineRowsByGroup[group] or EMPTY_ROWS

                table.sort(offlineRows,function(a,b)
                    if a.sortKey and b.sortKey then
                        local an,bn=SocialPlus_AsciiLower(a.sortKey),SocialPlus_AsciiLower(b.sortKey)
                        if an~=bn then return an<bn end
                    end
                    if a.buttonType~=b.buttonType then
                        return a.buttonType==FRIENDS_BUTTON_TYPE_BNET
                    end
                    return (a.id or 0)<(b.id or 0)
                end)

                for _,row in ipairs(offlineRows) do
                    index=index+1
                    local slot=TakeButton(index,group)
                    slot.buttonType=row.buttonType
                    slot.id=row.id
                    slot.key=RowKey(row.buttonType,row.id)
                end
            end
        end
        end
    end
    FriendButtons.count=index

	    -- Recompute total height and entry count based on the final, rebuilt list
    local finalHeight=0
    for i=1,FriendButtons.count do
        local bt=FriendButtons[i].buttonType or FRIENDS_BUTTON_TYPE_DIVIDER
        finalHeight=finalHeight+(FRIENDS_BUTTON_HEIGHTS[bt] or 0)
    end

    FriendsScrollFrame.totalFriendListEntriesHeight=finalHeight
    FriendsScrollFrame.numFriendListEntries=FriendButtons.count

	-- Driven entirely by SocialPlus_SelectedRow (see declaration above),
	-- not Blizzard's own FriendsFrame.selectedFriend/GetSelectedFriend() --
	-- those reflect client-side state that isn't limited to real clicks in
	-- this session, and every attempt to force-select or gate on Blizzard's
	-- own selection machinery still ended up highlighting (or later
	-- jumping between) friends nobody clicked (reported live, repeatedly).
	if SocialPlus_SelectedRow then
		-- Re-resolve the CURRENT raw index by identity before using it --
		-- the selected friend may be scrolled off-screen (so the per-row
		-- highlight loop's own identity check never runs for them this
		-- pass), and their stored raw id can go stale if Blizzard reindexed
		-- its list in the meantime.
		local resolvedType,resolvedID=nil,nil
		if SocialPlus_SelectedRow.identityKey then
			for i=1,FriendButtons.count do
				local bt=FriendButtons[i].buttonType
				if (bt==FRIENDS_BUTTON_TYPE_WOW or bt==FRIENDS_BUTTON_TYPE_BNET)
					and SocialPlus_GetRowIdentityKey(bt,FriendButtons[i].id)==SocialPlus_SelectedRow.identityKey then
					resolvedType,resolvedID=bt,FriendButtons[i].id
					break
				end
			end
		else
			resolvedType,resolvedID=SocialPlus_SelectedRow.buttonType,SocialPlus_SelectedRow.id
		end

		if not resolvedType then
			-- The selected friend is GONE, not just reindexed -- they were
			-- removed from the friends list entirely, so no row anywhere
			-- matches their identity. Falling back to the stale stored
			-- id/type here handed Blizzard's own FriendsList_CanWhisperFriend
			-- a dangling index it couldn't resolve, hard-crashing it
			-- (reported live: "attempt to index local 'info' (a nil value)"
			-- right after removing a friend who'd been selected). Clear the
			-- selection outright instead.
			SocialPlus_SelectedRow=nil
			FriendsFrameSendMessageButton:Disable()
		else
			-- Self-heal our own stored index so it doesn't keep drifting
			-- from a stale base on the next pass.
			SocialPlus_SelectedRow.buttonType=resolvedType
			SocialPlus_SelectedRow.id=resolvedID
			-- CRITICAL: Send Message's actual click still runs Blizzard's own
			-- FriendsFrameSendMessageButton_OnClick, which reads THESE fields,
			-- not ours -- leaving them stale after the initial click meant the
			-- button looked right (correct enabled state, correct highlighted
			-- row) but fired on whoever the stale raw index now belonged to
			-- after a reindex, not the friend actually highlighted (reported
			-- live: highlighted "aymixe", message went to "breakdownx").
			FriendsFrame.selectedFriendType=resolvedType
			FriendsFrame.selectedFriend=resolvedID
			FriendsFrameSendMessageButton:SetEnabled(FriendsList_CanWhisperFriend(resolvedType,resolvedID))
		end
	else
		FriendsFrameSendMessageButton:Disable()
	end

	local showRIDWarning=false
	local numInvites2=FG_BNGetNumFriendInvites()
	if numInvites2>0 and not GetCVarBool("pendingInviteInfoShown") then
		local _,_,_,_,_,_,isRIDEnabled=FG_BNGetInfo()
		if isRIDEnabled then
			for i=1,numInvites2 do
				local inviteID,accountName,isBattleTag=FG_BNGetFriendInviteInfo(i)
				if not isBattleTag then
					showRIDWarning=true
					break
				end
			end
		end
	end
	if FriendsListFrame and FriendsListFrame.RIDWarning then
		if showRIDWarning then
			FriendsListFrame.RIDWarning:Show()
			FriendsScrollFrame.scrollBar:Disable()
			FriendsScrollFrame.scrollUp:Disable()
			FriendsScrollFrame.scrollDown:Disable()
		else
			FriendsListFrame.RIDWarning:Hide()
		end
	end
	SocialPlus_UpdateFriends()
end

-- [[ Group rename / create popups ]]

local function SocialPlus_Rename(self,old)
	local eb=self.editBox or self.EditBox
	if not eb then return end

	local input=eb:GetText()
	if input=="" or not old or input==old then
		return
	end

	local groups={}

	-- Remembered as they are written, so the burst can be watched to completion
	-- and any note the server drops can be sent again. Battle.net friends only:
	-- the character-friend notes below are local and land at once.
	local pending={}

	for i=1,FG_BNGetNumFriends() do
		local presenceID,_,_,_,_,_,_,_,_,_,_,_,noteText=FG_BNGetFriendInfo(i)
		local note=NoteAndGroups(noteText,groups)
		if groups[old] then
			groups[old]=nil
			groups[input]=true
			note=CreateNote(note,groups)
			FG_SetBNetFriendNote(i,note)
			if presenceID then
				pending[#pending+1]={ presenceID=presenceID, note=note }
			end
		end
	end

	for i=1,FG_GetNumFriends() do
		local fi=FG_GetFriendInfoByIndex(i)
		local note=fi and fi.notes
		note=NoteAndGroups(note,groups)
		if groups[old] then
			groups[old]=nil
			groups[input]=true
			note=CreateNote(note,groups)
			FG_SetFriendNotes(i,note)
		end
	end

	-- Carry the mute setting over to the new group name
	if SocialPlus_SavedVars and SocialPlus_SavedVars.notifications then
		local muted=SocialPlus_SavedVars.notifications.mutedGroups
		if muted[old] then
			muted[old]=nil
			muted[input]=true
		end
	end

	SocialPlus_Update()

	-- Rewrote one note per member, and each lands separately. Above two members
	-- that is a bulk write: the list is already correct here, so the per-write
	-- rebuilds are suppressed until they stop. See SocialPlus_BeginBulkNotes.
	if not SocialPlus_BeginBulkNotes(pending) then
		if SocialPlus_RefreshAfterNoteWrite then
			SocialPlus_RefreshAfterNoteWrite()
		end
	end
end

local function SocialPlus_Create(self,data)
	local eb=self.editBox or self.EditBox
	if not eb then return end

	local input=eb:GetText()
	if input=="" then
		return
	end

	-- Moves them, rather than adding a second tag.
	--
	-- This addon puts a friend in one group at a time -- the same rule the Add
	-- submenu enforces by wiping every tag before applying the new one (see
	-- SocialPlus_ModifyGroupFromDropdown's ADD mode). Creating a group from a
	-- friend who is already in one therefore takes them out of it; AddGroup on
	-- the raw note would have left them tagged into both.
	local groups={}
	local baseNote=NoteAndGroups(data.note,groups)
	local note=AddGroup(baseNote,input)

	data.set(data.id,note)

	-- Clear search so full list comes back
	if SocialPlus_ClearSearch then
		SocialPlus_ClearSearch()
	end

	-- Rebuild list. The immediate pass can still be reading the pre-write note
	-- for a BattleTag friend, so schedule a redraw for once it lands too.
	pcall(SocialPlus_Update)
	if SocialPlus_RefreshAfterNoteWrite then
		SocialPlus_RefreshAfterNoteWrite(data.kind,data.id,note,data.set)
	end

	-- Explicitly close the popup (works for both Accept click and Enter)
	if self and self.Hide then
		self:Hide()
	end
end

-- [[ Friend-note popup ]]
StaticPopupDialogs["SocialPlus_RENAME"]={
	text=L.POPUP_RENAME_TITLE,
	button1=ACCEPT,
	button2=CANCEL,
	hasEditBox=1,
	OnShow=function(self)
		local eb=self.editBox or _G[self:GetName().."EditBox"]
		if eb and self.data then
			eb:SetText(self.data)
			eb:SetCursorPosition(#self.data)
			eb:HighlightText()
		end
	end,
	OnAccept=SocialPlus_Rename,
	EditBoxOnEnterPressed=function(self)
		local parent=self:GetParent()
		SocialPlus_Rename(parent,parent.data)
		parent:Hide()
	end,
	timeout=0,
	whileDead=1,
	hideOnEscape=1,
	preferredIndex=5 -- avoid sharing low-numbered StaticPopup frame slots with Blizzard's own dialogs
}

-- [[ Friend-group create popup ]]
StaticPopupDialogs["SocialPlus_CREATE"]={
	text=L.POPUP_CREATE_TITLE,
	button1=ACCEPT,
	button2=CANCEL,
	hasEditBox=1,
	OnAccept=SocialPlus_Create,
	EditBoxOnEnterPressed=function(self)
		local parent=self:GetParent()
		SocialPlus_Create(parent,parent.data)
	end,
	timeout=0,
	whileDead=1,
	hideOnEscape=1,
	preferredIndex=6
}

-- [[ Friend-note popup ]]	
StaticPopupDialogs["FRIEND_SET_NOTE"]={
	text=L.POPUP_NOTE_TITLE,
	button1=ACCEPT,
	button2=CANCEL,
	hasEditBox=1,
	preferredIndex=7,
	OnShow=function(self,data)
		local eb=self.editBox or self.EditBox
		if eb and data and data.note then
			eb:SetText(data.note)
		end
	end,
	OnAccept=function(self,data)
		local eb=self.editBox or self.EditBox
		if not eb then return end
		if data and data.set then
			-- "#" is reserved for group-tag syntax -- strip any the user
			-- typed here so this free-text box can't be used to hand-craft
			-- a fake "#groupname" that then renders as real group
			-- membership once CreateNote appends the friend's actual tags
			-- below.
			local newBase=eb:GetText():gsub("#","")
			local finalNote=newBase
			if data.groups then
				data.groups[""]=nil
				finalNote=CreateNote(newBase,data.groups)
			end
			pcall(data.set,data.id,finalNote)
			pcall(SocialPlus_Update)
			-- BNet notes aren't readable back immediately; redraw once it lands.
			if SocialPlus_RefreshAfterNoteWrite then
				SocialPlus_RefreshAfterNoteWrite(data.kind,data.id,finalNote,data.set,data.presenceID)
			end
		end
	end,
	timeout=0,
	whileDead=1,
	hideOnEscape=1
}

-- [[ Character-name helper for menu actions ]]

-- Global: the friend row dropdown lives in its own file now.
function SocialPlus_GetFullCharacterName(cf)
	if not cf then return nil end

	local function AttachPlayerRealm(name)
		if not name or name=="" then return nil end
		if name:find("%-") then
			return name
		end
		local realm=GetRealmName and GetRealmName() or nil
		if not realm or realm=="" then
			return name
		end
		realm=realm:gsub("[%s%-]","")
		return name.."-"..realm
	end

	if cf.buttonType==FRIENDS_BUTTON_TYPE_WOW then
		if cf.rawName and cf.rawName~="" then
			return AttachPlayerRealm(cf.rawName)
		end
		if cf.characterName and cf.characterName~="" then
			if cf.realmName and cf.realmName~="" then
				return cf.characterName.."-"..cf.realmName
			else
				return AttachPlayerRealm(cf.characterName)
			end
		end
	end

	if cf.buttonType==FRIENDS_BUTTON_TYPE_BNET then
		if cf.characterName and cf.characterName~="" then
			if cf.realmName and cf.realmName~="" then
				return cf.characterName.."-"..cf.realmName
			else
				return cf.characterName
			end
		end
	end

	return nil
end

-- [[ Friend-menu title helper ]]

-- Global: the friend row dropdown lives in its own file now.
function SocialPlus_GetMenuTitle()
	local kind,id=SocialPlus_GetDropdownFriend()
	if not kind or not id then
		return UNKNOWN
	end

	local name,note
	local buttonType=(kind=="BNET") and FRIENDS_BUTTON_TYPE_BNET or FRIENDS_BUTTON_TYPE_WOW

	if kind=="WOW" then
		local fi=FG_GetFriendInfoByIndex(id)
		if fi and fi.name and fi.name~="" then
			name=fi.name
			note=fi.notes
		end
	elseif kind=="BNET" then
		local accountName,characterName,class,level,isFavoriteFriend,isOnline,
		      bnetAccountId,client,canCoop,wowProjectID,lastOnline,
		      isAFK,isGameAFK,isDND,isGameBusy,mobile,zoneName,gameText,realmName=
		      GetFriendInfoById(id)

		if accountName and accountName~="" then
			name=accountName
		elseif characterName and characterName~="" then
			name=(realmName and realmName~="") and (characterName.."-"..realmName) or characterName
		end
		note=select(13,FG_BNGetFriendInfo(id))
	end

	if not name then return UNKNOWN end

	-- Favorite star on the left, real group tag(s) on the right -- same
	-- "[GroupName]" gold styling already used by "Remove from [Group]"
	-- below in this same menu.
	local prefix=""
	if SocialPlus_IsFavorite(buttonType,id) then
		prefix="|TInterface\\Common\\FavoritesIcon:20:20:0:-3|t"
	end

	local suffix=""
	local groups={}
	NoteAndGroups(note,groups)
	local names={}
	for group in pairs(groups) do
		if group~="" then table.insert(names,group) end
	end
	if #names>0 then
		table.sort(names)
		local c=NORMAL_FONT_COLOR
		local hex=string.format("|cff%02x%02x%02x",c.r*255,c.g*255,c.b*255)
		suffix=" ["..hex..table.concat(names,", ").."|r]"
	end

	return prefix..name..suffix
end

-- [[ Generic dropdown separator helper ]]

-- Global, not local: the who-list menu in SocialPlus_Who.lua needs it too.
function SocialPlus_AddSeparator(level)
	local info=LibDD:UIDropDownMenu_CreateInfo()
	info.disabled=true
	info.notCheckable=true
	info.icon="Interface\\Common\\UI-TooltipDivider-Transparent"
	info.iconOnly=true
	info.iconInfo={
		tCoordLeft=0,tCoordRight=1,tCoordTop=0,tCoordBottom=1,
		tSizeX=0,tSizeY=8,tFitDropDownSizeX=true
	}
	LibDD:UIDropDownMenu_AddButton(info,level)
end

-- [[ Copy-character-name popup ]]

StaticPopupDialogs["SocialPlus_COPY_NAME"]={
    text=L.POPUP_COPY_TITLE,
    button1=OKAY,
    button2=CANCEL,
    hasEditBox=1,
    preferredIndex=8,

    OnShow=function(self,data)
        local eb=self.editBox or self.EditBox
        if eb then
            eb:SetMaxLetters(100)
        end
        if eb and data and data.name then
            eb:SetText(data.name)
            eb:HighlightText()
            eb:SetFocus()
        end
        -- Auto-close on Ctrl+C: hook OnKeyUp (not OnKeyDown) so the native
        -- clipboard copy fires first on KeyDown in clean context, then our
        -- tainted handler closes the dialog on key release.
        if eb and not eb.SocialPlusCtrlCHooked then
            eb.SocialPlusCtrlCHooked=true
            eb:HookScript("OnKeyUp",function(editbox,key)
                if key=="C" and IsControlKeyDown() then
                    editbox:GetParent():Hide()
                end
            end)
        end
    end,

    EditBoxOnEnterPressed=function(self)
        self:GetParent():Hide()
    end,
    EditBoxOnEscapePressed=function(self)
        self:GetParent():Hide()
    end,

    timeout=0,
    whileDead=1,
    hideOnEscape=1,
}

-- [[ Group-wide invite / remove helpers ]]

local function InviteOrGroup(clickedgroup,invite)
	-- Extra safety: never run bulk ops on the implicit [no group] bucket
	-- or the synthetic In-game Friends bucket (its menu never opens, but
	-- guard anyway -- deleting it would try to rewrite notes that hold no
	-- such tag)
	if not clickedgroup or clickedgroup=="" or clickedgroup==SP_INGAME_GROUP then
		return
	end

	-- Favorites membership comes from the favorite flag, not note tags --
	-- same reasoning as the row-building membership checks. "Remove" is
	-- excluded from the menu for Favorites entirely, so the delete path
	-- below never actually runs for it, but is guarded anyway for safety.
	local isFavorites=(clickedgroup==SP_FAVORITES_GROUP)
	local groups={}

	-- Remembered as they are written, exactly as the rename path does.
	-- Deleting a group rewrites one note per member and each lands
	-- separately, so without this the members crossed out of the group one
	-- at a time over the following minute, and a note the server dropped
	-- left somebody in a group that no longer exists.
	-- Battle.net friends only: the character-friend notes below are local
	-- and land at once.
	local pending={}

	-- BNet friends
	for i=1,FG_BNGetNumFriends() do
		local t={FG_BNGetFriendInfo(i)}
		local presenceID=t[1]
		local isOnline=t[8]
		local noteText=t[13] or t[12] or nil
		local note=NoteAndGroups(noteText,groups)

		local isMember
		if isFavorites then
			isMember=SocialPlus_IsFavorite(FRIENDS_BUTTON_TYPE_BNET,i)
		else
			isMember=groups[clickedgroup]
		end

		if isMember then
			if invite then
				local allowed=SocialPlus_GetInviteStatus("BNET",i)
				if allowed and presenceID and isOnline then
					if BNInviteFriend then
						pcall(BNInviteFriend,presenceID)
					end
				end
			elseif not isFavorites then
				groups[clickedgroup]=nil
				local newNote=CreateNote(note,groups)
				FG_SetBNetFriendNote(i,newNote)
				if presenceID then
					pending[#pending+1]={ presenceID=presenceID, note=newNote }
				end
			end
		end
	end

	-- Normal WoW friends
	for i=1,FG_GetNumFriends() do
		local friend_info=FG_GetFriendInfoByIndex(i)
		local name=friend_info and friend_info.name
		local connected=friend_info and friend_info.connected
		local noteText=friend_info and friend_info.notes
		local note=NoteAndGroups(noteText,groups)

		local isMember
		if isFavorites then
			isMember=SocialPlus_IsFavorite(FRIENDS_BUTTON_TYPE_WOW,i)
		else
			isMember=groups[clickedgroup]
		end

		if isMember then
			if invite and connected and name and name~="" then
				local allowed=SocialPlus_GetInviteStatus("WOW",i)
				if allowed then
					if C_PartyInfo and C_PartyInfo.InviteUnit then
					C_PartyInfo.InviteUnit(name)
				end
				end
			elseif not invite and not isFavorites then
				groups[clickedgroup]=nil
				local newNote=CreateNote(note,groups)
				FG_SetFriendNotes(i,newNote)
			end
		end
	end

	-- Deleting a group also clears any mute setting for it, and its entry
	-- in the persisted custom order -- otherwise a stale name lingered
	-- there forever, and a NEW group later created with the exact same
	-- name would silently inherit that old position/collapse-search match
	-- instead of behaving like the fresh group it actually is.
	if not invite and not isFavorites and SocialPlus_SavedVars then
		if SocialPlus_SavedVars.notifications then
			SocialPlus_SavedVars.notifications.mutedGroups[clickedgroup]=nil
		end
		if SocialPlus_SavedVars.groupOrder then
			for i,name in ipairs(SocialPlus_SavedVars.groupOrder) do
				if name==clickedgroup then
					table.remove(SocialPlus_SavedVars.groupOrder,i)
					break
				end
			end
		end
	end

	-- Deleting the group rewrote notes across every BattleTag friend that was in
	-- it. Those writes are server-side and land after any immediate render, so
	-- the list would otherwise still show the deleted group until something else
	-- redrew it. See SocialPlus_RefreshAfterNoteWrite.
	if not invite then
		-- Above one member this is a bulk write: the list is already correct
		-- here, so the per-write rebuilds are suppressed until the writes stop
		-- and each dropped note is re-sent. One member falls through to the
		-- single-write path, which BeginBulkNotes declines to take.
		if not SocialPlus_BeginBulkNotes(pending) then
			if SocialPlus_RefreshAfterNoteWrite then
				SocialPlus_RefreshAfterNoteWrite()
			end
		end
	end
end

-- [[ Friend-group delete confirmation ]]
StaticPopupDialogs["SocialPlus_CONFIRM_DELETE_GROUP"]={
	text=L.CONFIRM_DELETE_GROUP_TEXT,
	button1=OKAY,
	button2=CANCEL,
	OnAccept=function(self,clickedgroup)
		InviteOrGroup(clickedgroup,false)
	end,
	timeout=0,
	whileDead=1,
	hideOnEscape=1,
	preferredIndex=9
}

-- [[ Group context menu (right-click group header) ]]

local SocialPlus_Menu=LibDD:Create_UIDropDownMenu("SocialPlus_Menu",UIParent)
SocialPlus_Menu.displayMode="MENU"

local menu_items={
	[1]={
		{text="",notCheckable=true,isTitle=true},
		{text=L.GROUP_INVITE_ALL,notCheckable=true,func=function(self,menu,clickedgroup) InviteOrGroup(clickedgroup,true) end},
		{text=L.GROUP_RENAME,notCheckable=true,func=function(self,menu,clickedgroup) StaticPopup_Show("SocialPlus_RENAME",nil,nil,clickedgroup) end},
		{text=L.GROUP_REMOVE,notCheckable=true,func=function(self,menu,clickedgroup) StaticPopup_Show("SocialPlus_CONFIRM_DELETE_GROUP",clickedgroup,nil,clickedgroup) end},
		{text=L.GROUP_MUTE_NOTIFICATIONS,isMuteToggle=true},
	},
	-- Settings are now in the left-side panel. This submenu is intentionally removed.
}

SocialPlus_Menu.initialize=function(self,level)
	if not menu_items[level] then return end

	-- Actual group key ("" means [no group])
	local groupKey=L_UIDROPDOWNMENU_MENU_VALUE
	local isNoGroup=(groupKey==nil or groupKey=="")
	local isFavorites=(groupKey==SP_FAVORITES_GROUP)
	-- Real notifications.mutedGroups key: ungrouped friends are muted via the
	-- localized "General" pseudo-group, same as SocialPlus_ShouldNotifyForNote.
	-- Favorites mutes under its own reserved sentinel key (SP_FAVORITES_GROUP
	-- itself), which falls out of this same expression since it's non-empty
	-- and can never collide with a user-typed group name.
	local muteKey=(groupKey~="" and groupKey) or L.GROUP_UNGROUPED
	local displayLabel=isFavorites and SocialPlus_GetFavoritesLabel() or (groupKey~="" and groupKey or L.GROUP_UNGROUPED)

		for _,items in ipairs(menu_items[level]) do
		local info=LibDD:UIDropDownMenu_CreateInfo()

		for prop,value in pairs(items) do
			if prop~="isMuteToggle" then
				-- Replace empty text with the current group label
				info[prop]=value~="" and value or displayLabel
			end
		end
		-- Keep menu text static; slider popup shows the value

		info.arg1=groupKey
		info.arg2=groupKey

		if items.isMuteToggle then
			info.notCheckable=false
			info.isNotRadio=true
			info.keepShownOnClick=false
			info.checked=function()
				return SocialPlus_SavedVars and SocialPlus_SavedVars.notifications
					and SocialPlus_SavedVars.notifications.mutedGroups[muteKey]
			end
			info.func=function()
				local muted=SocialPlus_SavedVars.notifications.mutedGroups
				muted[muteKey]=not muted[muteKey] or nil
			end
		end

		-- When right-clicking [no group], only "Settings" should be usable
		-- (mute toggle stays enabled: ungrouped friends are muted via the
		-- "General" pseudo-group, so this must work here too)
		if level==1 and isNoGroup then
			if info.text==L.GROUP_INVITE_ALL
				or info.text==L.GROUP_RENAME
				or info.text==L.GROUP_REMOVE then
				info.disabled=true
			end
		end

		-- Favorites isn't a user-managed group, so it can't be renamed or
		-- deleted -- but the rows are shown GREYED rather than omitted, so the
		-- menu keeps the same shape and height as every other group's. They
		-- used to be left out entirely, which made this one menu two rows
		-- shorter and the items jump position.
		--
		-- Invite All and Mute stay live: favorites are real friends, and
		-- Favorites mutes under its own reserved key.
		if level==1 and isFavorites then
			if info.text==L.GROUP_RENAME or info.text==L.GROUP_REMOVE then
				info.disabled=true
			end
		end

		LibDD:UIDropDownMenu_AddButton(info,level)
	end
end


-- [[ Friend (row) right-click menu state ]]

-- Global: the friend row dropdown lives in its own file now.
SocialPlus_CurrentFriend=nil

-- Global: the friend row dropdown lives in its own file now.
SocialPlus_FriendMenu=LibDD:Create_UIDropDownMenu("SocialPlus_FriendMenu",UIParent)
SocialPlus_FriendMenu.displayMode="MENU"

-- [[ Click-catcher: closes our menus and unfocuses search when clicking outside ]]
-- Sits at DIALOG strata (above most UI, below TOOLTIP where DropDownLists live) so it
-- captures clicks that miss both the dropdown and the FriendsFrame buttons.
local SocialPlus_ClickCatcher=CreateFrame("Frame","SocialPlusClickCatcher",UIParent)
SocialPlus_ClickCatcher:SetAllPoints(UIParent)
SocialPlus_ClickCatcher:SetFrameStrata("DIALOG")
SocialPlus_ClickCatcher:EnableMouse(true)
SocialPlus_ClickCatcher:Hide()

local function SocialPlus_IsAnyDropDownOpen()
    for i=1,(L_UIDROPDOWNMENU_MAXLEVELS or 2) do
        local list=_G["L_DropDownList"..i]
        if list and list:IsShown() then return true end
    end
    return false
end

local function SocialPlus_ClearSearchFromOutsideClick()
    -- SocialPlus_UpdateSearchGlow is local to SocialPlus_CreateSearchBox
    -- and not reachable here, so hide the glow frames directly (both are
    -- real globals).
    SocialPlus_ClearSearch()
    if SocialPlus_SearchGlow then SocialPlus_SearchGlow:Hide() end
    if SocialPlus_SearchGlowOuter then SocialPlus_SearchGlowOuter:Hide() end
    FriendsList_Update()
end

SocialPlus_ClickCatcher:SetScript("OnMouseDown",function(self,button)
    -- Ignore clicks still actually over the search box itself (typing,
    -- repositioning the cursor) -- let it behave normally.
    if SocialPlus_Searchbox and SocialPlus_Searchbox:IsMouseOver() then
        -- A right-click friend menu is open and THIS full-screen frame is
        -- what's sitting over the search box. Returning early (as the normal
        -- typing/cursor case below does) left the menu up and the click
        -- swallowed, so reaching the search box from an open menu took two
        -- clicks. Dismiss the menu and put the caret in the box in one.
        --
        -- Hiding the catcher does not close a LibDD menu on its own -- every
        -- other dismiss branch here calls CloseDropDownMenus explicitly, and
        -- the same order is used: close the menu, then hide, so OnHide sees
        -- the for-menu flag and plays the close sound exactly once.
        if SocialPlus_ClickCatcherIsForMenu then
            LibDD:CloseDropDownMenus()
            self:Hide()
            SocialPlus_Searchbox:SetFocus()
            return
        end

        -- The clear "X" button is a child sitting on the box's own edge,
        -- same overlap problem as the friend-row case below: this
        -- full-screen frame is on top while shown (search box focused or a
        -- search term active), so a click on the X never actually reaches
        -- it -- self:Hide() alone doesn't un-swallow an already-dispatched
        -- click. Forward it explicitly via :Click(), same fix as the row
        -- case (confirmed live there).
        local clearBtn=SocialPlus_Searchbox.clearButton or SocialPlus_Searchbox.ClearButton
        if clearBtn and clearBtn:IsShown() and clearBtn:IsMouseOver() then
            self:Hide()
            clearBtn:Click()
        end
        return
    end

    -- This full-screen frame sits above everything (including friend
    -- rows) while shown, so it swallows the click that was meant for
    -- whatever's underneath -- self:Hide() alone doesn't un-swallow an
    -- already-dispatched event, only affects the NEXT one, which is why
    -- a friend row previously needed two clicks (confirmed live). Forward
    -- it explicitly via :Click() so one click is enough.
    local clickedFriendRow=nil
    local clickedGear=nil
    local clickedGearGroupKey=nil
    local clickedTravelPass=nil
    if FriendsScrollFrame and FriendsScrollFrame.buttons then
        for _,rowButton in ipairs(FriendsScrollFrame.buttons) do
            if rowButton:IsShown() and rowButton:IsMouseOver() then
                -- The group cogwheel is a child sitting on top of its row,
                -- so the row itself still reads as "moused over" even when
                -- the cursor is actually on the gear. Without this check, a
                -- double-click on the gear (whose first click is what
                -- opened this catcher) has its second click land here, get
                -- misread as "a friend row was clicked", and get forwarded
                -- to the row -- for a group header, that toggles its
                -- collapse state (confirmed live).
                local gear=rowButton.SocialPlusGroupGearButton
                local overGear=gear and gear:IsShown() and gear:IsMouseOver()
                -- Same problem for the travel-pass/invite button -- also a
                -- child sitting on the row, also read as "moused over the
                -- row" -- without this, a click on it got misforwarded to
                -- the ROW instead (confirmed live: looked like nothing
                -- happened except the row highlighting).
                local travel=rowButton.travelPassButton
                local overTravel=travel and travel:IsShown() and travel:IsMouseOver()
                if overGear then
                    clickedGear=gear
                    clickedGearGroupKey=rowButton.SocialPlusGroupName or ""
                elseif overTravel then
                    clickedTravelPass=travel
                else
                    clickedFriendRow=rowButton
                end
                break
            end
        end
    end

    if clickedFriendRow then
        -- Close any menu left open from an earlier right-click before
        -- forwarding this click -- otherwise clicking a friend row (even
        -- the same one) while a context menu is open leaves that menu
        -- orphaned: the catcher hides itself here, so nothing is left
        -- watching for the "click elsewhere" that would normally close it.
        -- A right-click forwarded below still opens its own fresh menu
        -- immediately after.
        LibDD:CloseDropDownMenus()
        -- Clicking a row control means you're done typing: drop keyboard
        -- focus, but deliberately NOT the search term -- clicking a result
        -- must not cancel the search that found it (see below). Focus and
        -- term were previously cleared together, so preserving the term also
        -- left the caret stuck in the search box.
        if SocialPlus_Searchbox and SocialPlus_Searchbox:HasFocus() then
            SocialPlus_Searchbox:ClearFocus()
        end
        self:Hide()
        clickedFriendRow:Click(button)
        -- Stay armed for a later click that's genuinely outside the
        -- Friends List to still clear the search, even though this click
        -- (on a real result) didn't -- otherwise, once focus moves off
        -- the search box from interacting with a row, nothing was left
        -- watching for that later click at all (confirmed live).
        if SocialPlus_SearchTerm then
            SocialPlus_ShowClickCatcher()
        end
        return
    end

    if clickedTravelPass then
        -- Same forwarding as a friend row, and the same reasoning for
        -- staying armed afterward -- an invite click shouldn't cancel an
        -- active search either.
        -- Clicking a row control means you're done typing: drop keyboard
        -- focus, but deliberately NOT the search term -- clicking a result
        -- must not cancel the search that found it (see below). Focus and
        -- term were previously cleared together, so preserving the term also
        -- left the caret stuck in the search box.
        if SocialPlus_Searchbox and SocialPlus_Searchbox:HasFocus() then
            SocialPlus_Searchbox:ClearFocus()
        end
        self:Hide()
        clickedTravelPass:Click(button)
        if SocialPlus_SearchTerm then
            SocialPlus_ShowClickCatcher()
        end
        return
    end

    if clickedGear then
        -- The gear's own OnClick already opens its dropdown -- just get out
        -- of its way without touching the search, on request (clicking the
        -- cogwheel to manage a group you just searched for used to cancel
        -- the search entirely).
        --
        -- If THIS SAME gear's menu is the one currently open (re-clicking
        -- it, e.g. right at its edge where this catcher intercepts instead
        -- of the gear itself), a real toggle-close is wanted -- just close
        -- it and stop, don't forward the click. Forwarding it here used to
        -- run the gear's OnClick again unconditionally, which re-armed the
        -- catcher (SocialPlus_ClickCatcherIsForMenu=true) even when
        -- ToggleDropDownMenu closed rather than opened, so the SAME edge
        -- click both closed the menu and immediately reopened it -- it
        -- never actually stayed closed (reported live).
        local sameMenuAlreadyOpen=clickedGearGroupKey
            and L_UIDROPDOWNMENU_MENU_VALUE==clickedGearGroupKey
            and L_DropDownList1 and L_DropDownList1:IsShown()

        -- Close the REAL dropdown list first (not just our own overlay) --
        -- without this, when a DIFFERENT gear's click needs forwarding
        -- below, the actual LibDD list frame was still open when
        -- clickedGear:Click() ran that gear's own OnClick, so its
        -- ToggleDropDownMenu saw an already-open menu and closed it instead
        -- of opening the new one -- but that OnClick still re-armed the
        -- catcher for a menu that was no longer actually showing, and the
        -- next click anywhere then hid this orphaned, still-armed catcher,
        -- playing a second close sound (reported live).
        LibDD:CloseDropDownMenus()
        -- Clicking a row control means you're done typing: drop keyboard
        -- focus, but deliberately NOT the search term -- clicking a result
        -- must not cancel the search that found it (see below). Focus and
        -- term were previously cleared together, so preserving the term also
        -- left the caret stuck in the search box.
        if SocialPlus_Searchbox and SocialPlus_Searchbox:HasFocus() then
            SocialPlus_Searchbox:ClearFocus()
        end
        self:Hide()
        if not sameMenuAlreadyOpen then
            clickedGear:Click()
        end
        return
    end

    -- Anything else -- a group header itself, blank panel space, or truly
    -- outside the Friends List entirely -- clears an active search and
    -- drops focus, matching Escape. Only a friend row/travel-pass/gear
    -- click (above) is exempt.
    LibDD:CloseDropDownMenus()
    if SocialPlus_SearchTerm then
        SocialPlus_ClearSearchFromOutsideClick()
    end
    if SocialPlus_Searchbox and SocialPlus_Searchbox:HasFocus() then
        SocialPlus_Searchbox:ClearFocus()
    end
    self:Hide()
end)

-- Hover-forward target is kept as a field on the frame itself, and the
-- setter below is nested inside this one OnUpdate closure (not a
-- top-level local) -- this file is already right at Lua's 200-local
-- per-chunk ceiling for its main chunk.
SocialPlus_ClickCatcher:SetScript("OnUpdate",function(self)
    local function SetHover(target)
        if target==self.hoverButton then return end
        if self.hoverButton then
            local onLeave=self.hoverButton:GetScript("OnLeave")
            if onLeave then onLeave(self.hoverButton) end
        end
        if target then
            local onEnter=target:GetScript("OnEnter")
            if onEnter then onEnter(target) end
        end
        self.hoverButton=target
    end

    local dropOpen=SocialPlus_IsAnyDropDownOpen()
    local searchFocused=SocialPlus_Searchbox and SocialPlus_Searchbox:HasFocus()
    -- Also stay shown while a search term is still active (even without
    -- focus, e.g. after interacting with a friend row), so a later click
    -- that's genuinely outside the Friends List can still clear it --
    -- otherwise this immediately re-hid the catcher we just explicitly
    -- re-showed for exactly that purpose (confirmed live).
    local searchActive=SocialPlus_SearchTerm~=nil
    if not dropOpen and not searchFocused and not searchActive then
        SetHover(nil)
        self:Hide()
        return
    end

    -- While a menu is open, the mouse can easily be hovering a menu entry
    -- that visually sits on top of a row/gear/travel-pass button
    -- underneath -- forwarding hover in that case popped up that button's
    -- tooltip (e.g. "not on your WoW version") floating behind/alongside
    -- the open menu, on request. Only forward hover for a plain search
    -- interaction, never while a menu is up.
    if dropOpen then
        SetHover(nil)
        return
    end

    -- Being a full-screen frame sitting above everything else while shown,
    -- this catcher also blocks normal OnEnter/OnLeave hover events from
    -- ever reaching the row/gear/travel-pass button underneath -- so
    -- tooltips silently stopped showing during an active search (confirmed
    -- live: invite button tooltip). Manually detect and forward hover, the
    -- same way OnMouseDown above already forwards clicks.
    local hoverTarget=nil
    if FriendsScrollFrame and FriendsScrollFrame.buttons then
        for _,rowButton in ipairs(FriendsScrollFrame.buttons) do
            if rowButton:IsShown() and rowButton:IsMouseOver() then
                local gear=rowButton.SocialPlusGroupGearButton
                local travel=rowButton.travelPassButton
                if gear and gear:IsShown() and gear:IsMouseOver() then
                    hoverTarget=gear
                elseif travel and travel:IsShown() and travel:IsMouseOver() then
                    hoverTarget=travel
                else
                    hoverTarget=rowButton
                end
                break
            end
        end
    end
    SetHover(hoverTarget)
end)

-- Escape should close an open menu first, not the whole Friends panel --
-- only let Escape propagate through to Blizzard's normal panel-close
-- handling when no menu is actually open. The catcher is only ever shown while
-- a menu or search interaction is active, so it naturally only sees Escape when
-- relevant.
--
-- Propagate first, keyboard only if granted, and asked again on show -- see
-- the drag ghost. This one runs at load rather than in combat, so it is the
-- safe member of the three; it follows the same order so that the next person
-- to copy this block copies the right one.
SocialPlus_ClickCatcher:EnableKeyboard(true)
if not SocialPlus_SetPropagate(SocialPlus_ClickCatcher,true) then
	SocialPlus_ClickCatcher:EnableKeyboard(false)
end
SocialPlus_ClickCatcher:HookScript("OnShow",function(self)
	self:EnableKeyboard(true)
	if not SocialPlus_SetPropagate(self,true) then self:EnableKeyboard(false) end
end)
SocialPlus_ClickCatcher:SetScript("OnKeyDown",function(self,key)
    if key=="ESCAPE" and SocialPlus_IsAnyDropDownOpen() then
        SocialPlus_SetPropagate(self,false)
        LibDD:CloseDropDownMenus()
    else
        SocialPlus_SetPropagate(self,true)
    end
end)

function SocialPlus_ShowClickCatcher()
    SocialPlus_ClickCatcher:Show()
end

SocialPlus_ClickCatcher:HookScript("OnHide",function(self)
    if SocialPlus_ClickCatcherIsForMenu then
        SocialPlus_PlayMenuCloseSound()
    end
    SocialPlus_ClickCatcherIsForMenu=false
    -- The click branches above hide the catcher directly (not just via
    -- OnUpdate), which would otherwise skip the OnUpdate closure's hover
    -- setter and leave a stale tooltip on screen with nothing left to
    -- clear it -- so clear it directly here too.
    if self.hoverButton then
        local onLeave=self.hoverButton:GetScript("OnLeave")
        if onLeave then onLeave(self.hoverButton) end
        self.hoverButton=nil
    end
end)

local function SocialPlus_SetCurrentFriend(button)
	SocialPlus_CurrentFriend={
		buttonType=button.buttonType,
		id=button.id,
		name=button.name and button.name:GetText() or "",
		rawName=button.rawName,
		accountName=button.accountName,
		characterName=button.characterName,
		realmName=button.realmName,
	}

	local title

	if button.name and button.name:GetText() and button.name:GetText()~="" then
		title=button.name:GetText()
	end

	if (not title or title=="") and button.rawName and button.rawName~="" then
		title=button.rawName
	end

	if (not title or title=="") and button.characterName and button.characterName~="" then
		if button.realmName and button.realmName~="" then
			title=button.characterName.."-"..button.realmName
		else
			title=button.characterName
		end
	end

	if (not title or title=="") and button.accountName and button.accountName~="" then
		title=button.accountName
	end

	if not title or title=="" then
		title=UNKNOWN
	end

	SocialPlus_CurrentFriend.title=title

	if button.buttonType==FRIENDS_BUTTON_TYPE_BNET and button.id then
		local info={FG_BNGetFriendInfo(button.id)}
		SocialPlus_CurrentFriend.bnetIndex=button.id
		SocialPlus_CurrentFriend.presenceID=info[1]
		-- accountID must be the BNet account/presence ID (info[1]), NOT the
		-- game-account ID (info[6]) or the account name string (info[2]).
		-- It was previously set to info[6]/info[2], which silently broke
		-- whisper and "Remove Battle.net Friend" since both need the real
		-- presence ID, not a game-account ID or a name string.
		SocialPlus_CurrentFriend.accountID=info[1]
	end
end

-- [[ Capability checks for menu actions ]]
function SocialPlus_CanCopyCharName()
	local kind,id=SocialPlus_GetDropdownFriend()
	if not kind or not id then
		return false
	end

	if kind=="WOW" then
		local info=FG_GetFriendInfoByIndex(id)
		return info and info.connected
	elseif kind=="BNET" then
		local accountName,characterName,class,level,isFavoriteFriend,
		      isOnline,bnetAccountId,client,canCoop,wowProjectID,lastOnline,
		      isAFK,isGameAFK,isDND,isGameBusy,mobile,zoneName,gameText,realmName=
		      GetFriendInfoById(id)

		if not isOnline then return false end
		if client~=BNET_CLIENT_WOW then return false end
		if WOW_PROJECT_ID and wowProjectID and wowProjectID~=WOW_PROJECT_ID then
			return false
		end
		if not characterName or characterName=="" then return false end
		-- realmName is allowed to be empty: that just means the friend is on
		-- our own realm. SocialPlus_GetFullCharacterName already falls back
		-- to the player's own realm in that case. Requiring it here wrongly
		-- disabled Copy Name for same-realm BNet friends who are otherwise
		-- perfectly valid (online, playing MoP, real character name).

		return true
	end

	return false
end

function SocialPlus_CanInviteMenuTarget()
	local kind,id=SocialPlus_GetDropdownFriend()
	if not kind or not id then
		return false
	end
	local allowed,reason = SocialPlus_GetInviteStatus(kind,id)
	return allowed and true or false
end

-- Normalize a realm name for comparison: strip spaces/hyphens (matches the
-- same normalization SocialPlus_GetFullCharacterName already applies when
-- building "Name-Realm" strings elsewhere in this file), and fall back to
-- the player's own realm for a nil/empty value, since that's what an absent
-- realm means everywhere this is called from (same-realm friend/unit).
local function SocialPlus_NormalizeRealmForCompare(realm)
	if not realm or realm=="" then
		realm=(GetRealmName and GetRealmName()) or ""
	end
	return realm:gsub("[%s%-]","")
end

-- Is a character (by name/realm) currently in the player's own party or raid?
-- Used to grey out inviting a friend who's already grouped with you.
local function SocialPlus_IsFriendInMyGroup(name,realm)
	if not name or name=="" then return false end
	if not IsInGroup or not IsInGroup() then return false end

	-- A WoW friend on a different (but connected) realm than the player has
	-- that realm baked directly into the name as "Name-Realm" (e.g.
	-- "Bukowsky-Pagle"), unlike UnitName() which always returns just the
	-- bare character name plus a SEPARATE realm string -- comparing them
	-- directly always failed for exactly the friends most likely to need
	-- this check (reported live: an already-grouped WoW friend still showed
	-- an enabled Invite button).
	if not realm or realm=="" then
		local base,suffixRealm=name:match("^(.-)%-([^%-]+)$")
		if base and suffixRealm then
			name,realm=base,suffixRealm
		end
	end

	local normRealm=SocialPlus_NormalizeRealmForCompare(realm)
	local isRaid=IsInRaid and IsInRaid()
	local unitPrefix=isRaid and "raid" or "party"
	local numMembers=(GetNumGroupMembers and GetNumGroupMembers()) or 0
	-- GetNumGroupMembers includes the player for a raid, but party1..partyN
	-- unit tokens never include "player" -- only go up to numMembers-1 there.
	local maxIndex=isRaid and numMembers or math.max(numMembers-1,0)

	for i=1,maxIndex do
		local unitName,unitRealm=UnitName(unitPrefix..i)
		if unitName and unitName==name and SocialPlus_NormalizeRealmForCompare(unitRealm)==normRealm then
			return true
		end
	end
	return false
end

-- Returns true/false, reason string, and optional invite restriction code
-- Helper: SocialPlus_GetInviteStatus is declared at top scope

SocialPlus_GetInviteStatus=function(kind,id)
	if not kind or not id then return false,L.INVITE_GENERIC_FAIL,INVITE_RESTRICTION_INFO end

	-- Ensure player faction is initialized
	if not playerFaction then FG_InitFactionIcon() end

	if kind=="WOW" then
	local info=FG_GetFriendInfoByIndex(id)
	if not info then
		return false,L.INVITE_GENERIC_FAIL,INVITE_RESTRICTION_INFO
	end

	-- Treat explicit false as offline; nil = "unknown", don't block on that
	if info.connected==false then
		return false,L.INVITE_REASON_NOT_WOW,INVITE_RESTRICTION_INFO
	end

	-- Already grouped with this friend -- nothing to invite them to
	if SocialPlus_IsFriendInMyGroup(info.name,nil) then
		return false,L.INVITE_REASON_ALREADY_GROUPED,INVITE_RESTRICTION_ALREADY_GROUPED
	end

	-- Some WoW friend info may include factionName or faction; check if present
	local friendFaction=info.factionName or info.faction
	if friendFaction and playerFaction and friendFaction~=playerFaction then
		return false,L.INVITE_REASON_OPPOSITE_FACTION,INVITE_RESTRICTION_FACTION
	end

	-- ✅ Passed all checks: same project, same faction (or unknown), not explicitly offline
	return true,nil,INVITE_RESTRICTION_NONE

	elseif kind=="BNET" then
	local accountName,characterName,class,level,isFavoriteFriend,
	      isOnline,bnetAccountId,client,canCoop,wowProjectID,lastOnline,
	      isAFK,isGameAFK,isDND,isGameBusy,mobile,zoneName,gameText,realmName=
	      GetFriendInfoById(id)

	-- Must be online and actually in WoW
	if not isOnline then
		return false,L.INVITE_REASON_NOT_WOW,INVITE_RESTRICTION_INFO
	end
	if client~=BNET_CLIENT_WOW then
		return false,L.INVITE_REASON_NOT_WOW,INVITE_RESTRICTION_NO_GAME_ACCOUNTS
	end

	-- Already grouped with this friend -- nothing to invite them to
	if SocialPlus_IsFriendInMyGroup(characterName,realmName) then
		return false,L.INVITE_REASON_ALREADY_GROUPED,INVITE_RESTRICTION_ALREADY_GROUPED
	end

	-- BNGetFriendInfo position 16 is canSummon (boolean), not wowProjectID in MoP Classic;
	-- only compare when we actually got a numeric project ID.
	if WOW_PROJECT_ID and type(wowProjectID)=="number" and wowProjectID~=WOW_PROJECT_ID then
		return false,L.INVITE_REASON_WRONG_PROJECT,INVITE_RESTRICTION_WOW_PROJECT_ID
	end

	-- Extra faction/region compatibility -- matched to the SPECIFIC account
	-- this row/button is actually displaying (characterName, resolved above
	-- via GetFriendInfoById), not just whichever account C_BattleNet.
	-- GetFriendAccountInfo(id).gameAccountInfo considers "the" one. For a
	-- friend with multiple WoW licenses online at once those two APIs can
	-- resolve to DIFFERENT accounts, so the invite button showed "opposite
	-- faction" even when the character actually being shown/invited was
	-- the SAME faction (reported live) -- same root cause as the row icon
	-- mismatch fixed earlier.
	local ga=nil
	local friendFaction,friendRegionID=nil,nil
	for _,acct in ipairs(SocialPlus_GetOnlineWoWGameAccounts(id)) do
		if acct.characterName==characterName
			and (not realmName or realmName=="" or acct.realmName==realmName) then
			ga={factionName=acct.factionName,regionID=acct.regionID}
			break
		end
	end
	if not ga and C_BattleNet and C_BattleNet.GetFriendAccountInfo and type(C_BattleNet.GetFriendAccountInfo)=="function" then
		local acct=C_BattleNet.GetFriendAccountInfo(id)
		ga=acct and acct.gameAccountInfo or nil
	end
	friendFaction=ga and ga.factionName or nil
	friendRegionID=ga and ga.regionID or nil

	-- If we know faction, block obvious opposite-faction cases first
	if friendFaction and playerFaction and friendFaction~=playerFaction then
		return false,L.INVITE_REASON_OPPOSITE_FACTION,INVITE_RESTRICTION_FACTION
	end

	-- Hard cross-region block: compare BNet regionID with client portal
	local playerRegionID=SocialPlus_GetClientRegionID()
	if friendRegionID and playerRegionID and friendRegionID~=playerRegionID then
		return false,L.INVITE_REASON_NO_REALM,INVITE_RESTRICTION_REALM
	end

	-- Trust Blizzard's canCoop flag for "this can never group" leftovers
	if canCoop==false then
		-- If we *didn't* already classify it as a region issue, fall back to generic
		if friendRegionID and not playerRegionID then
			return false,L.INVITE_REASON_NO_REALM,INVITE_RESTRICTION_REALM
		end
		return false,L.INVITE_GENERIC_FAIL,INVITE_RESTRICTION_INFO
	end

	-- At this point:
	-- - Online
	-- - In WoW
	-- - Same project
	-- - Not obviously opposite faction
	-- - Not obviously other region
	return true,nil,INVITE_RESTRICTION_NONE
end
	-- Unknown kind
	return false,L.INVITE_GENERIC_FAIL,INVITE_RESTRICTION_INFO
end

-- Expose global alias so third-party callers that expect a global will find it
_G.SocialPlus_GetInviteStatus = SocialPlus_GetInviteStatus

-- Global: the friend row dropdown lives in its own file now.
function SocialPlus_DropdownFriendHasGroup()
	local _,_,note=SocialPlus_GetDropdownFriendNote()
	if not note or note=="" then
		return false
	end

	local groups={}
	NoteAndGroups(note,groups)

	for group,present in pairs(groups) do
		if present and group~="" then
			return true
		end
	end

	return false
end

-- Ensure the friend dropdown is never narrower than our longest label
local SocialPlus_MenuMeasureFS

local function SocialPlus_GetStringWidth(str)
    if not str or str=="" then return 0 end
    if not SocialPlus_MenuMeasureFS then
        SocialPlus_MenuMeasureFS=UIParent:CreateFontString(nil,"OVERLAY","GameFontNormal")
        SocialPlus_MenuMeasureFS:Hide()
    end
    SocialPlus_MenuMeasureFS:SetText(str)
    return SocialPlus_MenuMeasureFS:GetStringWidth() or 0
end

-- Global: the friend row dropdown lives in its own file now.
function SocialPlus_ApplyMenuMinWidth(level)
    level=level or 1
    local listFrame=_G["DropDownList"..level]
    if not listFrame then return end

    -- Longest top-level label (EN/FR safe via L)
    local baseText=L.MENU_MOVE_TO_GROUP
    local textWidth=SocialPlus_GetStringWidth(baseText)
    if textWidth<=0 then return end

    -- Padding for left margin + icon + arrow
    local padding=60
    local targetWidth=textWidth+padding

    local currentWidth=listFrame:GetWidth() or 0
    if currentWidth<targetWidth then
        listFrame:SetWidth(targetWidth)

        -- Stretch buttons so the highlight reaches the new width
        local num=listFrame.numButtons or 0
        for i=1,num do
            local btn=_G[listFrame:GetName().."Button"..i]
            if btn then
                btn:SetWidth(targetWidth-5)
            end
        end
    end
end

-- [[ FriendsFrame button hooks (click / tooltip / invite tooltip) ]]
local frame=CreateFrame("Frame")
frame:RegisterEvent("PLAYER_LOGIN")
-- Tells a login apart from a /reload, which is the whole basis of the
-- recently-added group: only a login starts a new session and clears it.
frame:RegisterEvent("PLAYER_ENTERING_WORLD")
frame:RegisterEvent("BN_FRIEND_ACCOUNT_ONLINE")
frame:RegisterEvent("BN_FRIEND_ACCOUNT_OFFLINE")
frame:RegisterEvent("FRIENDLIST_UPDATE")
-- Fires when a friend's game info changes (entering/leaving WoW, character
-- login) WITHOUT a Battle.net connect/disconnect -- the case the 5s poll
-- ticker existed for. With this event feeding the same coalesced scan,
-- detection is near-instant and the ticker is just a safety net.
frame:RegisterEvent("BN_FRIEND_INFO_CHANGED")
-- Out-of-date version alert (see the version-check block further down)
frame:RegisterEvent("CHAT_MSG_ADDON")
frame:RegisterEvent("BN_CHAT_MSG_ADDON")
frame:RegisterEvent("GROUP_ROSTER_UPDATE")
-- Flushes the derivation the combat guard in SocialPlus_Update deferred.
frame:RegisterEvent("PLAYER_REGEN_ENABLED")

-- Forces the tooltip's background fully opaque before it's shown.
--
-- Blizzard's tooltip backdrop is translucent, so anything bright underneath --
-- raid frames especially -- shows straight through and makes every line hard to
-- read (reported live). Applied per show rather than once at load: Blizzard
-- re-applies its own backdrop colour whenever the tooltip is set up again, so a
-- one-time change gets undone.
-- Global, not a file-local: this chunk is at Lua's 200-locals ceiling.
function SocialPlus_MakeTooltipOpaque()
	-- Modern templates use NineSlice; older ones a plain backdrop. Handle both.
	-- Not called "ns": that is the addon namespace, and shadowing it here would
	-- hand any later edit in this function a tooltip widget instead.
	local nine=GameTooltip.NineSlice
	if nine and nine.SetCenterColor then
		nine:SetCenterColor(0,0,0,1)
	end
	if GameTooltip.SetBackdropColor then
		GameTooltip:SetBackdropColor(0,0,0,1)
	end

	-- Those two weren't enough on their own: the tooltip's own background art is
	-- semi-transparent, so setting its colour to opaque black still let raid
	-- frames show through. Lay a solid texture of our own behind the text.
	--
	-- BORDER sits above the tooltip's BACKGROUND art but below the font strings,
	-- so it hides what's behind without covering the text.
	local bg=GameTooltip.SocialPlusOpaqueBG
	if not bg then
		bg=GameTooltip:CreateTexture(nil,"BORDER")
		bg:SetPoint("TOPLEFT",GameTooltip,"TOPLEFT",2,-2)
		bg:SetPoint("BOTTOMRIGHT",GameTooltip,"BOTTOMRIGHT",-2,2)
		if bg.SetColorTexture then
			bg:SetColorTexture(0,0,0,1)
		else
			bg:SetTexture(0,0,0,1)
		end
		GameTooltip.SocialPlusOpaqueBG=bg

		-- Parented to GameTooltip, so without this it would darken EVERY
		-- tooltip in the game, not just ours. Hidden again whenever the
		-- tooltip closes; our show path re-shows it.
		GameTooltip:HookScript("OnHide",function()
			if GameTooltip.SocialPlusOpaqueBG then
				GameTooltip.SocialPlusOpaqueBG:Hide()
			end
		end)
	end
	bg:Show()
end

local function SocialPlus_OnClick(self,button)
	if self.buttonType==FRIENDS_BUTTON_TYPE_DIVIDER then
		-- Use the raw group key; for General this is "" (ungrouped)
		local groupKey=self.SocialPlusGroupName or ""

		if button=="RightButton" then
			-- Friend Requests and In-game Friends are pseudo-groups: none
			-- of the group menu's actions apply, so no context menu (their
			-- cogwheels are likewise hidden at render time).
			if groupKey==FriendRequestString or groupKey==SP_INGAME_GROUP then
				return
			end
			-- Still allow the header context menu everywhere else. No menu
			-- sound here -- that's reserved for the cogwheel buttons, not
			-- right-click context menus.
			LibDD:ToggleDropDownMenu(1,groupKey,SocialPlus_Menu,"cursor",0,0)
			SocialPlus_ShowClickCatcher()
		else
			SocialPlus_SavedVars.collapsed[groupKey]=not SocialPlus_SavedVars.collapsed[groupKey]

			SocialPlus_HardResetScrollRows()
			SocialPlus_Update(true)
			SocialPlus_ScheduleCollapseSettle()
		end
		return
	end


	if button~="RightButton" then
		-- Our own record of "the player picked this row" -- see
		-- SocialPlus_SelectedRow above.
		local isFriendRow=self.buttonType==FRIENDS_BUTTON_TYPE_WOW or self.buttonType==FRIENDS_BUTTON_TYPE_BNET
		if isFriendRow then
			SocialPlus_SelectedRow={buttonType=self.buttonType,id=self.id,identityKey=SocialPlus_GetRowIdentityKey(self.buttonType,self.id)}
		end

		local origResult
		if self.SocialPlus_OrigOnClick then
			origResult=self.SocialPlus_OrigOnClick(self,button)
		end

		if isFriendRow then
			-- We know EXACTLY which widget was actually clicked (self,
			-- right here, unambiguous -- you can't click a button without
			-- hovering it), so force a fresh, correct show for it directly.
			-- Our own tooltip builds its content straight from self,
			-- independent of any Blizzard internal selection state, so
			-- there's no ordering dependency on Blizzard's click handler
			-- above (unlike the old FriendsFrameTooltip_Show-based version).
			SocialPlus_ShowRowTooltip(self)
		end

		return origResult
	end

	-- Only open our context menu for recognised friend row types.
	-- For unrecognised rows (e.g. /who entries that share the scroll frame's button
	-- pool) the Blizzard_Menu unit popup is already shown by OnMouseDown — our
	-- OnClick fires afterwards and must not call anything from our tainted closure,
	-- because even forwarding to self.SocialPlus_OrigOnClick would propagate taint
	-- into Blizzard's menu state and block the subsequent CopyToClipboard call.
	if self.buttonType~=FRIENDS_BUTTON_TYPE_WOW and self.buttonType~=FRIENDS_BUTTON_TYPE_BNET then
		return
	end

	-- Buttons are recycled across tabs.  A /who row can retain a stale buttonType
	-- from when it was last a friends-list row.  Opening ToggleDropDownMenu from
	-- our tainted closure on any non-Friends tab taints the global dropdown state
	-- and blocks CopyToClipboard in the unit popup.
	if FriendsFrame then
		local tabID=PanelTemplates_GetSelectedTab(FriendsFrame) or FriendsFrame.selectedTab
		if tabID~=1 then return end
	end

	-- Open/close sounds matching Blizzard's own unit popup: open sound
	-- here, close sound via the click catcher's for-menu flag.
	SocialPlus_SetCurrentFriend(self)
	SocialPlus_PlayMenuOpenSound()
	LibDD:ToggleDropDownMenu(1,nil,SocialPlus_FriendMenu,"cursor",0,0)
	SocialPlus_ClickCatcherIsForMenu=true
	SocialPlus_ShowClickCatcher()
end

-- [[ Fully custom row tooltip ]]
-- Built and shown entirely under our own control via GameTooltip -- a
-- completely separate frame from Blizzard's "FriendsTooltip"/
-- FriendsFrameTooltip_Show, which this addon used to hook and react to.
-- Confirmed live via diagnostic that something in Blizzard's own update
-- path calls FriendsFrameTooltip_Show repeatedly for rows the mouse isn't
-- even over, for reasons never fully identified despite several targeted
-- fixes (resync-by-identity, mouse-focus gating, hide-after-the-fact).
-- Owning the whole pipeline ourselves -- Blizzard's FriendsFrame code never
-- touches GameTooltip -- sidesteps that entire class of bug instead of
-- continuing to patch around it.
-- Which of a Battle.net friend's characters the PvP block is describing.
--
-- One BattleTag can have several WoW sessions online at once -- the "Also
-- online" line already lists them -- and each is a different character with a
-- different rating. Showing one set of numbers without saying whose they were
-- made the block quietly wrong for anyone playing two accounts.
--
-- A global on purpose: this file has already tripped Lua's 200-local ceiling
-- once, and its own comments say so.
SocialPlus_PvPCycle = SocialPlus_PvPCycle or { key=nil, index=1, count=1, button=nil }

function SocialPlus_ShowRowTooltip(button)
	-- Small helpers local to this function only (not top-level locals) --
	-- Lua caps the main chunk at 200 locals total, and this file was
	-- already close to that ceiling (confirmed live: adding these as
	-- separate top-level locals tripped "main function has more than 200
	-- local variables" again).
	-- Strips our own "#Group" tags from a raw note (e.g. "test#Friends" ->
	-- "test"), same convention as everywhere else notes get displayed.
	local function StripNoteTags(note)
		if not note then return nil end
		return strtrim(note:match("^([^#]*)") or "")
	end
	-- Matches Blizzard's own note styling in the (now-suppressed) native
	-- tooltip: a small note icon inline with the text, in gold rather than
	-- plain white -- requested on request after the custom tooltip's first
	-- pass looked visually plainer.
	local function AddNoteLine(rawNote)
		local note=StripNoteTags(rawNote)
		if note and note~="" then
			GameTooltip:AddLine("|TInterface\\Buttons\\UI-GuildButton-PublicNote-Up:14:14:0:0|t "..note,1,0.82,0,true)
		end
	end

	-- Battle.net "Broadcast" status message (BNGetFriendInfo position 12 --
	-- separate from the note at position 13).
	--
	-- The icon is read live from Blizzard's own tooltip broadcast texture. It
	-- used to come from FriendsFrameBattlenetFrame.BroadcastButton, which is
	-- the button you click to set YOUR OWN broadcast -- different art from the
	-- icon Blizzard shows against a FRIEND's broadcast line, so this line never
	-- matched the default tooltip (reported live). Guessed string paths came
	-- out blank/black before that, which is why this reads a real widget
	-- rather than naming a texture.
	local function AddBroadcastLine(messageText)
		if messageText and messageText~="" then
			-- Falls back to what that widget resolves to today, so a renamed
			-- frame degrades to the right art instead of losing the icon.
			local icon=(FriendsTooltipBroadcastIcon and FriendsTooltipBroadcastIcon:GetTexture()) or 374213
			GameTooltip:AddLine("|T"..icon..":14:14:0:0|t "..messageText,0.6,0.8,1,true)
		end
	end
	-- Same faction crest, same size, as the multi-invite submenu
	-- (SocialPlus_BuildInviteAccountSubmenu) -- prepended to a character
	-- name line, on request, including each additional simultaneous
	-- session line for a friend with more than one WoW license online.
	-- The three marks that follow a name, in one place so both branches below
	-- cannot drift apart on their order.
	--
	-- Order is name, spec, region, faction -- deliberately, and it used to be
	-- faction, spec, name with the region trailing as text at the end. The spec
	-- is the thing being looked for, so it sits against the name; the flag says
	-- which ladder that spec was read from, so it comes next; and the faction
	-- crest, which almost never changes anything, goes last.
	local function FactionIconSuffix(factionName)
		if factionName=="Horde" then
			return " |TInterface\\FriendsFrame\\plusmanz-horde:14:14:0:0|t"
		elseif factionName=="Alliance" then
			return " |TInterface\\FriendsFrame\\plusmanz-alliance:14:14:0:0|t"
		end
		return ""
	end

	-- The flag, or the letters when the flag is switched off. Either way this
	-- carries its own leading space, so a friend whose region is unknown adds
	-- nothing rather than a gap.
	-- No flag in the tooltip. It is a picture where there is room for words,
	-- and the row already carries one -- pointing at a friend to be told the
	-- same thing a second way is not worth a line's width.
	--
	-- The flag setting governs the list, not this: hovering a row must say the
	-- region whether or not the row is drawing it.

	-- The spec icon for one character, for the name line at the top.
	--
	-- Separate from the Ladder Standing block below because that block runs
	-- last, and this is needed while the identity line is still being written.
	-- Cheap to ask twice: the lookup is an indexed hash, not a scan.
	local function SpecIconFor(charName,charRealm,regionID,projectID)
		if not (SocialPlus_SavedVars and SocialPlus_SavedVars.pvp_spec_icon) then return "" end
		if not (charName and charName~="") then return "" end

		local api=_G.ArenaPlusAPI
		if not (api and api.GetLadder and api.GetSpecIcon) then return "" end

		local full=charName
		if charRealm and charRealm~="" then full=charName.."-"..charRealm end

		local region
		if api.RegionFromID then region=api.RegionFromID(regionID) end

		-- Same reason the ratings block asks: the icon has to come off the row
		-- for the game they are actually in, or a name that exists on both
		-- ladders is drawn wearing the wrong spec.
		local version
		if api.VersionFromProjectID then version=api.VersionFromProjectID(projectID) end

		local ok,found=pcall(api.GetLadder,full,region,version)
		if not (ok and found) then return "" end

		-- Any bracket will do: the site stores one spec per character, measured
		-- across 888 players in more than one bracket with no disagreement.
		for bracket=1,4 do
			if found[bracket] then
				local okIcon,path=pcall(api.GetSpecIcon,found[bracket])
				if okIcon and path then
					return (" |T%s:14:14:0:0:64:64:5:59:5:59|t"):format(path)
				end
				break
			end
		end

		return ""
	end

	-- Below FactionIconSuffix on purpose: that helper is a local, and a call
	-- to it from above this line resolves to a global nil rather than to the
	-- function -- which is how the faction crest broke this block outright.
	-- A friend's rated PvP, when ArenaPlus is installed and has them.
	--
	-- Local to this function for the 200-local reason above.
	--
	-- ArenaPlus is optional and absent for most people, so every step is
	-- guarded: a tooltip that errors because a PvP addon is missing is a worse
	-- failure than one that quietly says nothing. Nothing here reaches into
	-- ArenaPlus itself -- only the ArenaPlusAPI table it publishes, which is
	-- the part it promises not to change under us.
	--
	-- Most friends produce nothing: the ladder stops at the Rival cutoff, so
	-- anybody below it is simply absent and the section is skipped entirely.
	-- `who` is a list of {name=,realm=}; one entry for a plain WoW friend, and
	-- one per online session for a BattleTag playing several at once.
	local function AddPvPLines(who,key)
		if not (SocialPlus_SavedVars and SocialPlus_SavedVars.pvp_ratings) then return end
		if not (who and #who>0) then return end

		local api=_G.ArenaPlusAPI
		if not (api and api.GetLadder) then return end

		-- Looked up first, drawn second.
		--
		-- Only characters actually on a ladder are kept, and with none of them
		-- ranked nothing is drawn at all -- no header, no name, no "not on the
		-- ladder". A section that exists only to say it has nothing to say is
		-- worse than no section.
		--
		-- Filtering here rather than at the point of drawing also keeps the
		-- cycle honest: Tab moves between characters that have something to
		-- show, instead of stepping through blanks.
		local ranked={}
		for _,person in ipairs(who) do
			local full=person.name
			if person.realm and person.realm~="" then full=person.name.."-"..person.realm end

			-- Their region, not ours. A friend playing EU is on the EU ladder,
			-- and looking them up in ours finds nothing, which is a different
			-- thing from being unranked.
			local region=person.region
			if not region and api.RegionFromID then region=api.RegionFromID(person.regionID) end

			-- Their game as well as their region. A friend on the Anniversary realms
			-- is on a different ladder, and looking them up in the Classic one finds
			-- either nothing or -- worse -- a stranger who happens to share the name.
			--
			-- nil means the Classic ladder, which is what every caller wanted before
			-- this existed and what a plain WoW friend still wants.
			local version=person.version

			-- Regions we never scraped cannot answer either way.
			local usable=not (region and api.HasRegion and not api.HasRegion(region,version))

			if usable then
				local ok,found=pcall(api.GetLadder,full,region,version)

				-- Filtered here, not at drawing time, so a friend ranked only
				-- in brackets you have switched off counts as having nothing to
				-- show -- no header, and no place in the Tab cycle.
				if ok and found then
					local wanted=SocialPlus_SavedVars.pvp_brackets or {}
					local kept,any=nil,false

					for bracket=1,4 do
						if found[bracket] and wanted[bracket] then
							kept=kept or {}
							kept[bracket]=found[bracket]
							any=true
						end
					end

					if any then
						person.ladder=kept
						ranked[#ranked+1]=person
					end
				end
			end
		end

		if #ranked==0 then return end

		-- The cycle belongs to one friend. Hovering somebody else starts again
		-- at their first character rather than carrying an index across.
		local cycle=SocialPlus_PvPCycle
		if cycle.key~=key then
			cycle.key,cycle.index=key,1
		end
		cycle.count=#ranked
		cycle.index=((cycle.index-1)%#ranked)+1

		local pick=ranked[cycle.index]

		-- The spec once, on the heading, rather than against every bracket.
		--
		-- Measured before deciding: of 888 players appearing in more than one
		-- bracket across both regions, *none* carried a different spec between
		-- them. One spec is stored per character, whichever the profile showed
		-- so a per-bracket icon was the same picture repeated down the column
		-- while implying it meant something per line.
		--
		-- Any entry will do, since they all carry that one spec.
		local icon=""
		if api.GetSpecIcon then
			for bracket=1,4 do
				local entry=pick.ladder[bracket]
				if entry then
					local okIcon,path=pcall(api.GetSpecIcon,entry)
					if okIcon and path then
						icon=("|T%s:14:14:0:0:64:64:5:59:5:59|t"):format(path)
					end
					break
				end
			end
		end

		GameTooltip:AddLine(" ")

		-- The spec icon rides with the name where there is a name line, and
		-- falls back to the heading where there is not.
		--
		-- On the name line it sits between the faction crest and the name, so
		-- the three read as one identity: who, what, where. The heading only
		-- carries it in the single-character case, where there is no name line
		-- to put it on and it would otherwise have nowhere to go.
		local named=#ranked>1

		GameTooltip:AddLine(L.TOOLTIP_PVP_HEADER,1,0.82,0)

		-- Named only when there is a choice to be confused about.
		--
		-- With one ranked character the tooltip has already said who this is,
		-- three lines up -- repeating it under the header is the same name
		-- twice for no reason. It earns its place only when Tab can change
		-- which character the ratings below belong to.
		if named then
			GameTooltip:AddLine(
				ClassColourCode(pick.className)..pick.name.."|r"
				.." "..icon
				..FactionIconSuffix(pick.factionName),1,1,1)

			GameTooltip:AddLine(L.TOOLTIP_PVP_CYCLE:format(cycle.index,#ranked),0.5,0.5,0.5)
		end

		for bracket=1,4 do
			local entry=pick.ladder[bracket]
			if entry then
				-- Coloured by the title the rating is worth, which only
				-- ArenaPlus can work out -- it holds the cutoffs.
				local hex
				if api.GetRankColour then
					local okColour,result=pcall(api.GetRankColour,bracket,entry)
					if okColour then hex=result end
				end

				local rating=tostring(entry.rating or 0)
				if hex then rating=("|cff%s%s|r"):format(hex,rating) end

				GameTooltip:AddLine(L.TOOLTIP_PVP_LINE:format(
					(api.BRACKETS and api.BRACKETS[bracket]) or "?",
					rating,entry.rank or 0),0.8,0.8,0.8)
			end
		end
	end

	-- "Zone:" / "Realm:" labels come from Blizzard's own globals so they stay
	-- localized: this tooltip is shown on every client language, and a
	-- hardcoded English label would ship to all of them. Which global carries
	-- the string varies between builds, so several are tried in order. Some
	-- already include the colon (and in some locales a space before it), so
	-- one is only appended when absent. A miss returns "" rather than an
	-- English fallback -- an unlabelled value reads fine in any language,
	-- a wrong-language label does not.
	local function Label(...)
		for i=1,select("#",...) do
			local s=select(i,...)
			if type(s)=="string" and s~="" then
				if s:find(":",1,true) then
					return (s:gsub("%s+$","")).." "
				end
				return s..": "
			end
		end
		return ""
	end
	-- Resolved once per session, not per tooltip: these globals never change
	-- while logged in, and this runs on every mouseover. Cached on a GLOBAL
	-- rather than a top-level local for the 200-local reason noted above --
	-- globals don't count towards that ceiling. "" is truthy in Lua, so a
	-- locale where none of the globals exist still caches instead of retrying.
	if not SOCIALPLUS_ZONE_LABEL then
		SOCIALPLUS_ZONE_LABEL =Label(ZONE,LOCATION_COLON)
		SOCIALPLUS_REALM_LABEL=Label(FRIENDS_LIST_REALM,REALM)
	end
	local ZONE_LABEL =SOCIALPLUS_ZONE_LABEL
	local REALM_LABEL=SOCIALPLUS_REALM_LABEL

	if not (button and GameTooltip) then return end
	if button.buttonType~=FRIENDS_BUTTON_TYPE_WOW and button.buttonType~=FRIENDS_BUTTON_TYPE_BNET then
		GameTooltip:Hide()
		return
	end

	-- Cleared before anything is drawn, and re-set by AddPvPLines only if it
	-- actually draws a block. Every one of that function's early exits -- the
	-- setting off, ArenaPlus absent, nobody ranked -- used to leave the
	-- PREVIOUS friend's count in place, and the OnEnter handler reads it to
	-- decide whether to capture Tab. So hovering someone with several ranked
	-- characters and then hovering anyone else armed the capture on a row with
	-- nothing to cycle, and Tab -- the targeting key -- was swallowed there.
	SocialPlus_PvPCycle.count=0

	-- ANCHOR_RIGHT on a pooled HybridScrollFrame row anchored the tooltip
	-- near the top of the screen instead of next to the actual row
	-- (reported live) -- these buttons don't always report reliable
	-- coordinates for Blizzard's built-in anchor math right after being
	-- repositioned. Explicit SetPoint against the row's own corner sidesteps
	-- that entirely.
	GameTooltip:SetOwner(button,"ANCHOR_NONE")
	GameTooltip:ClearAllPoints()
	-- Nudged further right than a plain flush anchor -- otherwise it sat
	-- close enough to overlap the list's own scrollbar (reported live).
	GameTooltip:SetPoint("TOPLEFT",button,"TOPRIGHT",28,0)
	GameTooltip.SocialPlusShownKey=SocialPlus_GetRowIdentityKey(button.buttonType,button.id)

	if button.buttonType==FRIENDS_BUTTON_TYPE_WOW then
		local info=FG_GetFriendInfoByIndex(button.id)
		if not info then GameTooltip:Hide() return end
		local classColor=ClassColourCode(info.className)
		-- These friends carry no realm field at all (see FG_GetFriendInfoByIndex),
		-- so the realm has to be worked out rather than read. Two cases: on a
		-- CONNECTED realm Blizzard appends it to the name, and otherwise the
		-- friend is on your own realm by definition -- a non-Battle.net friend
		-- list cannot contain anyone else. Taking the suffix first matters:
		-- assuming the player's realm outright would print the wrong realm for
		-- every connected-realm friend.
		--
		-- Character names cannot contain a hyphen, so splitting on one is
		-- unambiguous.
		local wowName,wowRealm=info.name or UNKNOWN,nil
		local baseName,realmSuffix=wowName:match("^([^%-]+)%-(.+)$")
		if baseName then
			wowName,wowRealm=baseName,realmSuffix
		else
			wowRealm=GetRealmName and GetRealmName() or nil
		end
		GameTooltip:SetText(classColor..wowName.."|r",1,1,1)
		if info.connected then
			if info.level and info.level~=0 then
				GameTooltip:AddLine(format(FRIENDS_LEVEL_TEMPLATE,info.level,info.className or ""),0.8,0.8,0.8)
			end
			if info.area and info.area~="" then
				GameTooltip:AddLine(ZONE_LABEL..info.area,0.6,0.6,0.6)
			end
			if wowRealm and wowRealm~="" then
				GameTooltip:AddLine(REALM_LABEL..wowRealm,0.6,0.6,0.6)
			end
		else
			GameTooltip:AddLine(FRIENDS_LIST_OFFLINE,0.6,0.6,0.6)
		end
		AddNoteLine(info.notes)
		AddPvPLines({ {
			name=wowName, realm=wowRealm, className=info.className,
			regionID=GetCurrentRegion and GetCurrentRegion() or nil,

			-- Whatever game THIS client is: a friends-list friend is on your own
			-- realm, so they are necessarily in it. Left unset this defaulted to
			-- the Classic ladder whichever client was running, which was right
			-- only by accident -- on Anniversary every one of these friends was
			-- looked up in the wrong game's ladder, finding nothing or, where a
			-- name existed on both, somebody else entirely.
			version=(_G.ArenaPlusAPI and _G.ArenaPlusAPI.VersionFromProjectID
				and _G.ArenaPlusAPI.VersionFromProjectID(WOW_PROJECT_ID)) or nil,
			-- A friends-list friend is on your realm and so your faction; the
			-- game does not report one for them because there is nothing to
			-- report.
			factionName=UnitFactionGroup and UnitFactionGroup("player") or nil,
		} },"wow:"..tostring(button.id))
	else
		local accountName,characterName,class,level,_,isOnline,_,client,canCoop,wowProjectID,lastOnline,
			isAFK,isGameAFK,isDND,isGameBusy,mobile,zoneName,gameText,realmName=GetFriendInfoById(button.id)
		local messageText,noteText=select(12,FG_BNGetFriendInfo(button.id))
		-- Inlined rather than calling SocialPlus_GetFriendGameAccountInfo --
		-- that helper is declared further down the file (local, out of
		-- lexical scope here), so referencing it from this earlier function
		-- would silently resolve to a global nil instead of the helper.
		local acctInfo=C_BattleNet and C_BattleNet.GetFriendAccountInfo and C_BattleNet.GetFriendAccountInfo(button.id)
		local ga=acctInfo and acctInfo.gameAccountInfo
		local regionID=ga and ga.regionID

		local friendFaction=ga and ga.factionName

		-- Title (BattleTag) in the same blue as the "L90" level prefix
		-- (FRIENDS_BNET_NAME_COLOR) rather than the class color -- on
		-- request, to match that existing element instead of the
		-- class-colored character line below it.
		GameTooltip:SetText(accountName or UNKNOWN,FRIENDS_BNET_NAME_COLOR.r,FRIENDS_BNET_NAME_COLOR.g,FRIENDS_BNET_NAME_COLOR.b)
		if isOnline then
			if client==BNET_CLIENT_WOW and characterName and characterName~="" then
				local classColor=ClassColourCode(class)
				-- Realm deliberately NOT appended to the character name: it
				-- gets its own labelled line below, matching Blizzard's own
				-- tooltip. Carrying it here as well showed it twice.
				local charLabel=characterName
				local hasRealm=realmName and realmName~=""
				if wowProjectID==WOW_PROJECT_ID then
					-- No region here. The row already carries a region flag
					-- beside the name, so repeating it as "(NA)" text put the
					-- same fact on screen twice -- and squeezed it between the
					-- spec icon and the faction crest, where it read as clutter
					-- between two pictures rather than as information.
					GameTooltip:AddLine(classColor..charLabel.."|r"
						..SpecIconFor(characterName,realmName,regionID,wowProjectID)
						..FactionIconSuffix(friendFaction),1,1,1)
					if level and level~=0 then
						GameTooltip:AddLine(format(FRIENDS_LEVEL_TEMPLATE,level,class or ""),0.8,0.8,0.8)
					end
					-- zoneName arrives pre-composed as "<zone> - <realm>":
					-- GetFriendInfoById builds that for the ROW's location
					-- line, and substitutes the realm outright when there is
					-- no zone at all. The tooltip puts the realm on its own
					-- line below, so undo both here -- otherwise the realm
					-- shows twice (reported live).
					local zoneOnly=zoneName
					if hasRealm and zoneOnly and zoneOnly~="" then
						if zoneOnly==realmName then
							-- Realm standing in for a missing zone: there is
							-- no location to report, so no zone line.
							zoneOnly=nil
						else
							local suffix=" - "..realmName
							if zoneOnly:sub(-#suffix)==suffix then
								zoneOnly=zoneOnly:sub(1,#zoneOnly-#suffix)
							end
						end
					end

					-- Mobile is checked before the zone rather than inside it:
					-- "Mobile App" replaces the location entirely, and it must
					-- still show for a friend whose zone was the realm
					-- stand-in above. It stays unlabelled too -- "Zone: Mobile
					-- App" would claim a location it doesn't describe.
					if mobile then
						GameTooltip:AddLine(LOCATION_MOBILE_APP,0.6,0.6,0.6)
					elseif zoneOnly and zoneOnly~="" then
						-- No separate "In Arena" line: the zone name already says
						-- it ("Blade's Edge Arena"), so colouring that line is
						-- enough. It also avoids translating a status string --
						-- the zone name arrives already localized by Blizzard.
						local zr,zg,zb=0.6,0.6,0.6
						if SocialPlus_IsArenaZone(zoneOnly) then zr,zg,zb=1,0.4,0.4 end
						GameTooltip:AddLine(ZONE_LABEL..zoneOnly,zr,zg,zb)
					end
					if hasRealm then
						GameTooltip:AddLine(REALM_LABEL..realmName,0.6,0.6,0.6)
					end
				else
					-- Region goes on the version line here instead (e.g.
					-- "Retail (EU)") -- putting it on the name line too gave
					-- a duplicate "(NA) ... (NA)" (reported live).
					GameTooltip:AddLine(classColor..charLabel.."|r"
						..SpecIconFor(characterName,realmName,regionID,wowProjectID)
						..FactionIconSuffix(friendFaction),1,1,1)
					-- Version only. The region moved out to the row's flag --
					-- see the name line above.
					GameTooltip:AddLine(SocialPlus_GetVersionLabelText(wowProjectID),0.6,0.6,0.6)
					-- Same labelled realm line as the branch above, so the two
					-- kinds of friend don't disagree about where the realm goes.
					if hasRealm then
						GameTooltip:AddLine(REALM_LABEL..realmName,0.6,0.6,0.6)
					end
				end

				-- A single BattleTag can have more than one WoW client online at
				-- once (e.g. NA + EU simultaneously). GetFriendInfoById/
				-- C_BattleNet.GetFriendAccountInfo only ever surface Blizzard's
				-- own single pick above, so a friend logged into two regions at
				-- once silently only ever showed one of them (reported live).
				-- List any OTHER currently-online WoW sessions here using the
				-- same multi-account enumeration already relied on for invites.
				local otherAccounts=SocialPlus_GetOnlineWoWGameAccounts(button.id)
				for _,acct in ipairs(otherAccounts) do
					if not (acct.characterName==characterName and (acct.realmName or "")==(realmName or "")) then
						local otherLabel=ClassColourCode(acct.className)..(acct.characterName or UNKNOWN).."|r"
						if acct.realmName and acct.realmName~="" then
							otherLabel=otherLabel.."-"..acct.realmName
						end
						otherLabel=otherLabel..FactionIconSuffix(acct.factionName)
						if acct.wowProjectID and acct.wowProjectID~=WOW_PROJECT_ID then
							otherLabel=otherLabel.." - "..SocialPlus_GetVersionLabelText(acct.wowProjectID)
						end
						GameTooltip:AddLine(format(L.TOOLTIP_ALSO_ONLINE,otherLabel),0.6,0.8,0.6,true)
					end
				end
			elseif client==BNET_CLIENT_WOW then
				-- Same reasoning as the row's info line above: an empty
				-- character payload cannot tell character-select apart from
				-- withheld data, so don't claim either.
				GameTooltip:AddLine((gameText and gameText~="" and gameText) or L.WOW_ONLINE_NO_DETAILS,0.8,0.8,0.8)
			else
				GameTooltip:AddLine(gameText or "",0.8,0.8,0.8)
			end
		else
			GameTooltip:AddLine(FRIENDS_LIST_OFFLINE,0.6,0.6,0.6)
		end

		AddNoteLine(noteText)
		AddBroadcastLine(messageText)

		-- Only for a character on this same game. A Battle.net friend may be
		-- playing retail, another classic version, or not WoW at all, and our
		-- ladder describes none of those -- a name that happened to collide
		-- would otherwise be given somebody else's rating.
		-- Every WoW session this BattleTag has online, not merely the one
		-- Blizzard picked to report. Same enumeration the "Also online" line
		-- uses, filtered to this game version -- our ladder describes no other.
		local characters={}

		local function Consider(name,realm,regionID,projectID,className,factionName)
			if not (name and name~="") then return end

			-- Kept if ArenaPlus ships a ladder for the game they are in, rather than
			-- only for our own. It was our project id or nothing, because the ladder
			-- described no other game -- the data addon now carries the Anniversary
			-- one too, so a friend on TBC has a rating worth showing while we sit
			-- in Classic.
			--
			-- Asked of ArenaPlus rather than by listing project ids here: which
			-- ladders shipped is its business, and a version it cannot answer for is
			-- dropped exactly as before.
			local ladderAPI=_G.ArenaPlusAPI
			local version
			if ladderAPI and ladderAPI.VersionFromProjectID then
				version=ladderAPI.VersionFromProjectID(projectID)
				if projectID and not version then return end
			elseif projectID and projectID~=WOW_PROJECT_ID then
				-- ArenaPlus absent, or an older one that cannot be asked. Same rule
				-- it had before: our own game only.
				return
			end

			for _,had in ipairs(characters) do
				if had.name==name and (had.realm or "")==(realm or "") then return end
			end

			characters[#characters+1]={
				name=name, realm=realm, regionID=regionID,
				className=className, factionName=factionName,
				version=version,
			}
		end

		if client==BNET_CLIENT_WOW then
			Consider(characterName,realmName,regionID,wowProjectID,class,friendFaction)
		end

		for _,acct in ipairs(SocialPlus_GetOnlineWoWGameAccounts(button.id)) do
			Consider(acct.characterName,acct.realmName,acct.regionID,acct.wowProjectID,
				acct.className,acct.factionName)
		end

		AddPvPLines(characters,"bnet:"..tostring(button.id))
	end

	SocialPlus_MakeTooltipOpaque()
	GameTooltip:Show()
end

function SocialPlus_HideRowTooltip()
	if GameTooltip then
		GameTooltip:Hide()
		GameTooltip.SocialPlusShownKey=nil
	end

	-- Tab belongs to the game again the moment the tooltip is gone.
	local cycle=SocialPlus_PvPCycle
	if cycle and cycle.button then
		local row=cycle.button
		cycle.button=nil
		row:SetScript("OnKeyDown",nil)
		SocialPlus_SetPropagate(row,true)
		row:EnableKeyboard(false)
	end
end

-- Blizzard's own FriendsTooltip can still get shown from somewhere in its
-- own update path independent of any row's OnEnter (confirmed live: it
-- kept appearing even after taking over every row's OnEnter/OnLeave
-- directly). Rather than chase whatever internal call triggers it,
-- suppress it unconditionally at the frame level -- hook its own OnShow to
-- immediately hide it again, so nothing can make it appear regardless of
-- what's calling in.
if FriendsTooltip then
	FriendsTooltip:HookScript("OnShow",function(self) self:Hide() end)
end

local function SocialPlus_OnEnter(self)
	-- Do nothing when not on the Friends tab; touching Blizzard frames here
	-- from tainted code would propagate taint to the /who popup’s CopyToClipboard.
	if FriendsFrame then
		local tabID=PanelTemplates_GetSelectedTab(FriendsFrame) or FriendsFrame.selectedTab
		if tabID and tabID~=1 then return end
	end

	-- Don’t show a tooltip on group headers -- or on any row while a
	-- group-header drag is active (confirmed live: the tooltip was still
	-- popping up over friend rows mid-drag, cluttering the drag feedback).
	if self.buttonType==FRIENDS_BUTTON_TYPE_DIVIDER or SocialPlus_DragSourceGroup then
		SocialPlus_HideRowTooltip()
	else
		SocialPlus_ShowRowTooltip(self)

		-- Tab cycles the PvP block through a friend's online characters.
		--
		-- Only while the cursor is on a row, and only while that friend has
		-- more than one: Tab is the targeting key, and taking it for a tooltip
		-- any longer than that would be indefensible. Everything else is passed
		-- straight through, so typing is unaffected.
		-- Without SetPropagateKeyboardInput there is no way to let every other
		-- key through, and a row that eats the whole keyboard while hovered is
		-- far worse than one that does not cycle. So on a client without it,
		-- this simply does not happen -- the tooltip still names the character.
		--
		-- In combat it does not happen either, and for the same reason rather
		-- than a different one: the call is protected there, so EnableKeyboard
		-- would arm a row that swallows every key with no way to hand them
		-- back.
		local cycle=SocialPlus_PvPCycle
		if cycle and (cycle.count or 1)>1 then
			-- Armed BEFORE the request, and disarmed again if it is refused.
			--
			-- Asking first reads safer and does not work: SetPropagateKeyboardInput
			-- does nothing on a frame whose keyboard is still off, so the propagate
			-- never sticks and the row comes up armed and deaf anyway. That is what
			-- shipped as 1.15b and took the search box with it.
			self:EnableKeyboard(true)
			if not SocialPlus_SetPropagate(self,true) then self:EnableKeyboard(false) end
		end
		if cycle and (cycle.count or 1)>1 and self:IsKeyboardEnabled() then
			cycle.button=self

			self:SetScript("OnKeyDown",function(row,key)
				if key~="TAB" or not SocialPlus_PvPCycle or (SocialPlus_PvPCycle.count or 1)<=1 then
					SocialPlus_SetPropagate(row,true)
					return
				end

				-- Combat since the row was armed: the keys cannot be taken, so
				-- Tab goes to the game and the tooltip stays as it is. One lost
				-- cycle beats a swallowed Tab in an arena.
				if not SocialPlus_SetPropagate(row,false) then return end

				SocialPlus_PvPCycle.index=SocialPlus_PvPCycle.index+1
				SocialPlus_ShowRowTooltip(row)
			end)
		end
	end

	-- While a group-header drag is active, track which group the cursor is over
	if SocialPlus_DragSourceGroup then
		local groupKey
		if self.buttonType==FRIENDS_BUTTON_TYPE_DIVIDER then
			groupKey=self.SocialPlusGroupName
		else
			groupKey=SocialPlus_GetGroupKeyFromRow(self)
			-- nil means this row belongs to the general (no-group) section
			if groupKey==nil or groupKey=="" then
				groupKey=SP_GENERAL_GROUP
			end
		end
		SocialPlus_DragHoverGroup=groupKey
		SocialPlus_DragHoverEverSet=true
		SocialPlus_UpdateDragInsertionLine(groupKey)
	end
end

-- Called from the OnMouseUp handler on regular friend rows when a group-header
-- drag is in progress.  SocialPlus_OnGroupDragStop already has a fallback that
-- infers the drop target via SocialPlus_GetGroupKeyFromRow for non-divider buttons,
-- so we simply delegate.  If OnDragStop fires first (clearing DragSourceGroup), the
-- early-return inside SocialPlus_OnGroupDragStop makes the second call a no-op.
SocialPlus_OnRowMouseUp=function(self,button)
	if SocialPlus_DragSourceGroup then
		SocialPlus_OnGroupDragStop(self)
	end
end

local function HookButtons()
	local scrollFrame=FriendsScrollFrame
	if not scrollFrame or not scrollFrame.buttons then return end

	local buttons=scrollFrame.buttons
	local numButtons=#buttons

	for i=1,numButtons do
		local btn=buttons[i]
		if btn then
			if not btn.SocialPlus_OrigOnClick then
				btn.SocialPlus_OrigOnClick=btn:GetScript("OnClick")
			end

			-- Group-header cogwheel: same texture as the main settings button,
			-- opens the group's context menu (mute notifications, rename,
			-- delete, invite all) without needing to right-click.
			if not btn.SocialPlusGroupGearButton then
				local gear=CreateFrame("Button",nil,btn)
				gear:SetSize(16,16)
				gear:SetPoint("RIGHT",btn,"RIGHT",-4,0)
				gear:SetFrameLevel(btn:GetFrameLevel()+2)

				local tex=gear:CreateTexture(nil,"ARTWORK")
				tex:SetAllPoints(gear)
				tex:SetTexture("Interface\\Buttons\\UI-OptionsButton")
				gear.icon=tex

				local highlight=gear:CreateTexture(nil,"HIGHLIGHT")
				highlight:SetAllPoints(gear)
				highlight:SetTexture("Interface\\Buttons\\UI-OptionsButton")
				highlight:SetBlendMode("ADD")
				highlight:SetVertexColor(1,1,1,0.5)

				gear:SetScript("OnClick",function()
					SocialPlus_PlayMenuClickSound()
					local groupKey=btn.SocialPlusGroupName or ""
					LibDD:ToggleDropDownMenu(1,groupKey,SocialPlus_Menu,"cursor",0,0)
					SocialPlus_ClickCatcherIsForMenu=true
					SocialPlus_ShowClickCatcher()
				end)

				gear:Hide()
				btn.SocialPlusGroupGearButton=gear
			end

			btn:SetScript("OnClick",SocialPlus_OnClick)
			-- SetScript (replacing), not HookScript (adding on top of) --
			-- Blizzard's own native OnEnter is what called
			-- FriendsFrameTooltip_Show in the first place; fully taking
			-- over here means that path (and its live-reported bugs) never
			-- runs at all anymore, not just reacting to it afterward.
			if not btn.SocialPlus_OrigOnEnter then
				btn.SocialPlus_OrigOnEnter=btn:GetScript("OnEnter")
			end
			btn:SetScript("OnEnter",SocialPlus_OnEnter)
			btn:SetScript("OnLeave",SocialPlus_HideRowTooltip)

			if not btn.SocialPlus_OrigOnMouseUp then
				btn.SocialPlus_OrigOnMouseUp=btn:GetScript("OnMouseUp")
			end
			btn:SetScript("OnMouseUp",function(self,button)
                -- Do nothing when not on the Friends tab to avoid propagating
                -- taint into the /who unit popup's CopyToClipboard path.
                if FriendsFrame then
                    local tabID=PanelTemplates_GetSelectedTab(FriendsFrame) or FriendsFrame.selectedTab
                    if tabID and tabID~=1 then return end
                end
                if SocialPlus_DragSourceGroup then
                    SocialPlus_OnRowMouseUp(self,button)
                    return
                end
                if self.SocialPlus_OrigOnMouseUp then
                    self.SocialPlus_OrigOnMouseUp(self,button)
                end
            end)

			-- Invite tooltip for travel pass button
			local travel=btn.travelPassButton
			if travel and not travel.FG_TooltipHooked then
				travel.FG_TooltipHooked=true

travel:HookScript("OnEnter",function(self)
	if not GameTooltip then return end
	GameTooltip:SetOwner(self,"ANCHOR_RIGHT")

	local title
	if SocialPlus_ShouldSuggestInvite and SocialPlus_ShouldSuggestInvite() then
		title=L.MENU_SUGGEST or L.MENU_INVITE
	else
		title=L.MENU_INVITE
	end

	if self.fgInviteAllowed or self:IsEnabled() then
		GameTooltip:SetText(title,1,1,1)
	else
		GameTooltip:SetText(title,1,0.1,0.1)
		local reason=self.fgInviteReason or L.INVITE_GENERIC_FAIL
		GameTooltip:AddLine(reason,1,0.3,0.3,true)
	end

	SocialPlus_MakeTooltipOpaque()
	GameTooltip:Show()
end)

travel:HookScript("OnLeave",function()
					if GameTooltip then GameTooltip:Hide() end
				end)
			end
		end
	end
end

-- [[ Friends dropdown integration ]]
-- Global, not local: SocialPlus_Version.lua needs it.
function SocialPlus_FindBNetIndexByPresenceID(presenceID)
	for i=1,FG_BNGetNumFriends() do
		local pid=select(1,FG_BNGetFriendInfo(i))
		if pid==presenceID then return i end
	end
end

local function SocialPlus_FindWoWIndexByName(name)
	for i=1,FG_GetNumFriends() do
		local info=FG_GetFriendInfoByIndex(i)
		if info and info.name==name then return i end
	end
end

function SocialPlus_GetDropdownFriend()
	if SocialPlus_CurrentFriend and SocialPlus_CurrentFriend.buttonType then
		if SocialPlus_CurrentFriend.buttonType==FRIENDS_BUTTON_TYPE_BNET then
			-- presenceID is stable across list updates; re-resolve to current index
			local pid=SocialPlus_CurrentFriend.presenceID
			if pid then
				local idx=SocialPlus_FindBNetIndexByPresenceID(pid)
				if idx then return "BNET",idx end
			end
		elseif SocialPlus_CurrentFriend.buttonType==FRIENDS_BUTTON_TYPE_WOW then
			-- character name is stable; re-resolve to current index
			local name=SocialPlus_CurrentFriend.rawName or SocialPlus_CurrentFriend.name
			if name and name~="" then
				local idx=SocialPlus_FindWoWIndexByName(name)
				if idx then return "WOW",idx end
			end
		end
	end

	local dropdown=FriendsFrameDropDown or L_UIDROPDOWNMENU_INIT_MENU or UIDROPDOWNMENU_INIT_MENU
	if not dropdown then return nil end

	if dropdown.bnetIDAccount then
		return "BNET",dropdown.bnetIDAccount
	end

	if dropdown.id then
		return "WOW",dropdown.id
	end

	if dropdown.name then
		for i=1,FG_GetNumFriends() do
			local info=FG_GetFriendInfoByIndex(i)
			if info and info.name==dropdown.name then
				return "WOW",i
			end
		end
	end
end

function SocialPlus_GetDropdownFriendNote()
	local kind,id=SocialPlus_GetDropdownFriend()
	if not kind or not id then return nil end

	if kind=="BNET" then
		local t={FG_BNGetFriendInfo(id)}
		if not t or #t==0 then
			return nil
		end

		local note=t[13] or t[12] or t[14] or nil
		FG_Debug("GetDropdownFriendNote -> BNET","index="..tostring(id),"note="..tostring(note))

		-- Written by presence id, never by the list index it was found at.
		--
		-- id is a position in Battle.net's friend list, and that list reorders
		-- itself whenever anybody logs on or off. Between opening the note popup
		-- and pressing Accept the position can belong to a different person --
		-- and the write went to whoever was standing there, carrying the groups
		-- read from the friend actually clicked. Reported live: a note meant for
		-- one friend landed on another and moved them into the first one's group.
		--
		-- The presence id is stable, so it is captured here and the index is
		-- resolved again at the moment of writing.
		local presenceID=t[1]
		local setter=function(_,newNote)
			local idx=presenceID and SocialPlus_FindBNetIndexByPresenceID(presenceID)
			if idx then FG_SetBNetFriendNote(idx,newNote) end
		end

		return kind,id,note,setter,presenceID
	else
		local info=FG_GetFriendInfoByIndex(id)
		if info then
			return kind,id,info.notes,function(index,note) FG_SetFriendNotes(index,note) end
		end
	end
end

function SocialPlus_CreateGroupFromDropdown()
	local kind,id,note,setter=SocialPlus_GetDropdownFriendNote()
	if not kind or not id or not setter then return end

	StaticPopup_Show("SocialPlus_CREATE",nil,nil,{kind=kind,id=id,note=note,set=setter})

	-- Close the dropdown after clicking "Create new group"
	LibDD:CloseDropDownMenus()
end

-- Redraw the list once a note write has actually landed.
--
-- BNet notes go through BNSetFriendNote, which is a SERVER round-trip: the value
-- is NOT readable back on the next line. Re-rendering immediately therefore
-- shows the OLD note and the change looks like it did nothing -- which is why
-- moving a friend to a group appeared to need two attempts (reported live).
-- Character-friend notes are written locally and need none of this.
--
-- Given `expectedNote` we poll until exactly that value reads back, so the
-- redraw happens the moment it lands and no later. Without it -- bulk writes
-- spanning many friends, where there's no single value to wait on -- we just
-- redraw a couple of times across the next second.
--
-- Deliberately NOT driven off BN_FRIEND_INFO_CHANGED: that fires constantly for
-- zone/status/level changes, so rebuilding on it would add per-friend work all
-- session long, which is the opposite of what a large friend list needs.
-- A group rename or a group-wide move rewrites one note per member, and the
-- server confirms each one separately as its own BN_FRIEND_INFO_CHANGED. Each of
-- those rebuilds the whole friends list, so renaming a fourteen-person group
-- meant fourteen full rebuilds spread over a minute -- which is what made the
-- members appear to march across one at a time (reported live).
--
-- The writes themselves cannot be hurried: Battle.net throttles them server-side
-- and there is no bulk note API. What can go is the thrash. The list is redrawn
-- once up front, where it already knows the answer, and the per-write rebuilds
-- are suppressed until the writes stop.
--
-- Watched, not timed.
--
-- Two guesses failed before this. A window computed from the member count ended
-- with three writes outstanding; a quiet period after the last confirmation
-- ended during a stall. Measured on a fourteen-member rename, four notes landed
-- promptly and the rest took about two more minutes -- so the writes are not
-- paced, they arrive in bursts with long gaps, and no timer can tell a gap from
-- the end.
--
-- What is knowable is what was written. Each note is remembered with the friend
-- it belongs to, and the burst is over when every one of them reads back. That
-- is the same thing SocialPlus_RefreshAfterNoteWrite already does for a single
-- move, including re-issuing the write: BNSetFriendNote is silently dropped
-- often enough that the single-friend path retries three times, and the bulk
-- path never retried at all -- which is the likelier cause of the two minutes
-- than any server pacing.
--
-- The hard stop remains, for the note that never lands however often it is sent.
SocialPlus_BulkPending=nil
SocialPlus_BulkNotesHardStop=0

SocialPlus_BulkPendingByID=nil
function SocialPlus_BulkNotesActive()
	return SocialPlus_BulkPending~=nil
end

-- The note we wrote for this friend, while their write is still outstanding.
--
-- The list is built from notes, so until a write lands a rebuild honestly shows
-- the friend in their old group -- which is why suppressing redraws only hid the
-- marching instead of stopping it. This hands the rebuild the note we are trying
-- to write, so the finished state is on screen from the first redraw and never
-- goes backwards. When the write lands the two agree; if it never lands, the
-- override lapses with the burst and the friend honestly reverts.
--
-- Keyed rather than searched: this is asked once per Battle.net friend per
-- rebuild, and a linear scan of the pending list would be a few thousand
-- comparisons on a large list.
function SocialPlus_BulkNoteFor(presenceID)
	if not (presenceID and SocialPlus_BulkPendingByID) then return nil end
	local item=SocialPlus_BulkPendingByID[presenceID]
	if item and not item.done then return item.note end
	return nil
end

-- Kept only so the event handler has something harmless to call; the burst now
-- ends on the notes reading back, not on confirmations arriving.
function SocialPlus_BulkNotesSaw()
end

function SocialPlus_BeginBulkNotes(pending)
	if not (pending and #pending>1) then return false end
	if not (C_Timer and C_Timer.After) then return false end

	SocialPlus_BulkPending=pending
	SocialPlus_BulkPendingByID={}
	for _,item in ipairs(pending) do
		SocialPlus_BulkPendingByID[item.presenceID]=item
	end
	SocialPlus_BulkNotesHardStop=(GetTime and GetTime() or 0)
		+math.min(600,30+#pending*15)

	SocialPlus_Update(true)

	if L and L.GROUP_BULK_WRITING then
		DEFAULT_CHAT_FRAME:AddMessage("|cff4da6ff[SocialPlus]|r "..
			string.format(L.GROUP_BULK_WRITING,#pending))
	end

	local function finish()
		local done=0
		for _,item in ipairs(SocialPlus_BulkPending or {}) do
			if item.done then done=done+1 end
		end

		SocialPlus_BulkPending=nil
		SocialPlus_BulkPendingByID=nil
		SocialPlus_BulkNotesHardStop=0
		SocialPlus_Update(true)

		-- Said at the end rather than as it goes: the list is already correct
		-- throughout, so a running count would be noise. It still reports the
		-- total, so a write that never landed shows up as a shortfall instead of
		-- silently reverting a friend to their old group.
		if L and L.GROUP_BULK_DONE then
			DEFAULT_CHAT_FRAME:AddMessage("|cff4da6ff[SocialPlus]|r "..
				string.format(L.GROUP_BULK_DONE,done,#pending))
		end
	end

	local function poll()
		if not SocialPlus_BulkPending then return end

		local outstanding=0
		for _,item in ipairs(SocialPlus_BulkPending) do
			if not item.done then
				local idx=SocialPlus_FindBNetIndexByPresenceID(item.presenceID)
				local current=idx and select(13,FG_BNGetFriendInfo(idx)) or nil
				if current==item.note then
					item.done=true
				else
					outstanding=outstanding+1
					item.tries=(item.tries or 0)+1

					-- Re-sent periodically rather than every pass: the server
					-- does accept these eventually, and hammering one note every
					-- two seconds would be its own kind of rude.
					if idx and item.tries%3==0 then
						FG_SetBNetFriendNote(idx,item.note)
					end
				end
			end
		end

		if outstanding==0 or (GetTime and GetTime() or 0)>=SocialPlus_BulkNotesHardStop then
			finish()
			return
		end
		C_Timer.After(2,poll)
	end

	C_Timer.After(2,poll)
	return true
end

function SocialPlus_RefreshAfterNoteWrite(kind,id,expectedNote,setter,presenceID)
	if not (C_Timer and C_Timer.After) then
		SocialPlus_Update(true)
		return
	end

	if kind=="BNET" and id and expectedNote~=nil then
		-- Given one where the caller has it. Deriving it from the index has the
		-- same staleness the note write itself had: the list can have reordered
		-- since, and then this polls the wrong friend's note and gives up.
		presenceID=presenceID or FG_BNGetFriendInfo(id)
		if presenceID then
			local tries=0
			local function pollForWrite()
				tries=tries+1
				local idx=SocialPlus_FindBNetIndexByPresenceID(presenceID)
				local current=idx and select(13,FG_BNGetFriendInfo(idx)) or nil
				if current==expectedNote then
					SocialPlus_GroupDebug("landed after",tries.." poll(s)")
					SocialPlus_Update(true)
					return
				end
				-- Give up after ~2s and redraw anyway, so the list can never sit
				-- stale on a write that silently failed.
				if tries>=8 then
					SocialPlus_GroupDebug("gave up; note never landed")
					SocialPlus_Update(true)
					return
				end
				-- RE-ISSUE the write, don't just wait for it.
				--
				-- BNSetFriendNote on a freshly added BattleTag friend is simply
				-- dropped -- confirmed live, the note read back empty straight
				-- after the call and stayed empty, which is why moving them to a
				-- group appeared to need two attempts. The server accepts it once
				-- the friend entry has finished syncing, so retry a couple of
				-- times rather than only redrawing.
				if setter and idx and (tries==2 or tries==4 or tries==6) then
					SocialPlus_GroupDebug("re-issuing write, attempt",tries)
					setter(idx,expectedNote)
				end
				C_Timer.After(0.25,pollForWrite)
			end
			C_Timer.After(0.25,pollForWrite)
			return
		end
	end

	C_Timer.After(0.3,function() SocialPlus_Update(true) end)
	C_Timer.After(1.0,function() SocialPlus_Update(true) end)
end

-- Turn on with: /run SocialPlusGroupDebug=true
-- Reports what the group move actually resolved and wrote. The symptom -- having
-- to pick the group twice -- can come from resolving the wrong friend, reading a
-- stale note, or the write not landing, and those look identical from outside.
function SocialPlus_GroupDebug(...)
	if not SocialPlusGroupDebug then return end
	local parts={}
	for i=1,select('#',...) do parts[#parts+1]=tostring((select(i,...))) end
	if DEFAULT_CHAT_FRAME and DEFAULT_CHAT_FRAME.AddMessage then
		DEFAULT_CHAT_FRAME:AddMessage("|cff4da6ff[SP group]|r "..table.concat(parts," | "))
	end
end

function SocialPlus_ModifyGroupFromDropdown(group,mode)
	if not group or group=="" then return end
	local kind,id,note,setter=SocialPlus_GetDropdownFriendNote()
	SocialPlus_GroupDebug("resolve",mode,group,"kind="..tostring(kind),"id="..tostring(id),
		"note="..tostring(note),"setter="..tostring(setter~=nil))
	if not kind or not id or not setter then
		SocialPlus_GroupDebug("ABORT: nothing resolved")
		return
	end

	local groups={}
	local baseNote=NoteAndGroups(note,groups)
	local newNote

	if mode=="ADD" then
		-- Single-group / "move to group" semantics:
		-- wipe all existing #Group tags, then apply the new one.
		-- Favorite status is untouched -- it takes priority over real
		-- group assignment (rendered under Favorites regardless of which
		-- real group they're tagged into) and only changes when the user
		-- explicitly removes them from Favorites.
		for k in pairs(groups) do
			groups[k]=nil
		end
		newNote=AddGroup(baseNote,group)
	else
		-- Pure remove: strip just the selected tag, keep any others.
		-- RemoveGroup(baseNote,group) looked right but wasn't -- baseNote
		-- has ALREADY had every tag stripped out of it by the
		-- NoteAndGroups call above, so RemoveGroup's own internal
		-- re-parse of baseNote never finds ANY tags (including the one
		-- being "removed"), making the whole call a no-op -- or, for a
		-- friend in multiple groups, silently dropping every other tag
		-- too, since none of them survive being fed through baseNote in
		-- the first place (reported live: removing a friend from one
		-- group left them stuck in it). `groups` above is already the
		-- correctly-parsed table with every current tag -- just remove
		-- the target one from THAT instead of re-parsing a stripped string.
		groups[""]=nil
		groups[group]=nil
		newNote=CreateNote(baseNote,groups)
	end

	SocialPlus_GroupDebug("writing",'"'..tostring(newNote)..'"')
	setter(id,newNote)
	if kind=="BNET" then
		local pid=FG_BNGetFriendInfo(id)
		local backIdx=pid and SocialPlus_FindBNetIndexByPresenceID(pid) or nil
		local readBack=backIdx and select(13,FG_BNGetFriendInfo(backIdx)) or nil
		SocialPlus_GroupDebug("after write","presenceID="..tostring(pid),
			"idx="..tostring(backIdx),"readback="..tostring(readBack))
	end

	-- Clear search so full list is shown after adding/removing
	if SocialPlus_ClearSearch then
		SocialPlus_ClearSearch()
	end

	-- Rebuild and close menus
	SocialPlus_Update()
	LibDD:CloseDropDownMenus()

	-- See SocialPlus_RefreshAfterNoteWrite: the write above is not readable back
	-- immediately, so the render has to wait for it.
	SocialPlus_RefreshAfterNoteWrite(kind,id,newNote,setter)
end

-- [[ BNet remove friend flow ]]	
if not StaticPopupDialogs then
    StaticPopupDialogs={}
end

-- [[ BNet remove flows ]]
local function SocialPlus_DoRemoveBNetFriend(data)
	if not data then return end

	local bnIndex=data.bnIndex
	local presenceID=data.presenceID
	local accountID=data.accountID
	local battleTag=data.battleTag

	FG_Debug(
		"BNET confirm remove",
		"bnIndex="..tostring(bnIndex),
		"presenceID="..tostring(presenceID),
		"accountID="..tostring(accountID)
	)

	local ok=false

	if C_BattleNet and C_BattleNet.RemoveFriend and accountID then
		ok=pcall(C_BattleNet.RemoveFriend,accountID)
	end

	if not ok and BNRemoveFriend then
		if presenceID then
			ok=pcall(BNRemoveFriend,presenceID)
			FG_Debug("BNET remove via presenceID (confirm)",tostring(ok))
		end
		if not ok and bnIndex then
			ok=pcall(BNRemoveFriend,bnIndex)
			FG_Debug("BNET remove via index (confirm)",tostring(ok))
		end
	end

	FG_Debug("BNET final remove result (confirm)",tostring(ok))

	-- Same cleanup as the WOW-friend remove path -- favorite status is
	-- stored independently of Blizzard's own friend record, keyed by
	-- BattleTag, so it silently persisted across remove/re-add otherwise
	-- (reported live).
	if ok and battleTag and battleTag~="" and SocialPlus_SavedVars and SocialPlus_SavedVars.favorites then
		SocialPlus_SavedVars.favorites["BNET:"..battleTag]=nil
	end

	pcall(SocialPlus_Update)
end

StaticPopupDialogs["SOCIALPLUS_CONFIRM_REMOVE_BNET"]={
	text=L.CONFIRM_REMOVE_BNET_TEXT,
	button1=OKAY,
	button2=CANCEL,
	hasEditBox=true,
	timeout=0,
	hideOnEscape=1,
	whileDead=1,
	preferredIndex=3,

	OnShow=function(self,data)
		self.data=data
		local eb=self.editBox or self.EditBox
		if eb then
			eb:SetText("")
			eb:SetFocus()
			-- Sized to the active locale's confirm word, not hardcoded --
			-- was 4 for "YES.", now variable now that the trailing period
			-- is gone (and locales aren't all the same length: "OUI" is 3,
			-- "SÍ" is 2).
			eb:SetMaxLetters(#L.CONFIRM_REMOVE_BNET_WORD)
		end

		local ok=_G[self:GetName().."Button1"]
		if ok then
			ok:Disable()
		end
	end,

	EditBoxOnTextChanged=function(eb)
		local parent=eb:GetParent()
		local ok=_G[parent:GetName().."Button1"]
		if not ok then return end

		-- Accent- and case-insensitive: "si" should confirm just as well
		-- as "SÍ" for the Spanish locale, same normalization already used
		-- for search.
		if SocialPlus_NormalizeText(eb:GetText())==SocialPlus_NormalizeText(L.CONFIRM_REMOVE_BNET_WORD) then
			ok:Enable()
		else
			ok:Disable()
		end
	end,

	EditBoxOnEnterPressed=function(eb)
		local parent=eb:GetParent()
		local ok=_G[parent:GetName().."Button1"]
		if ok and ok:IsEnabled() then
			ok:Click()
		end
	end,

	OnAccept=function(self,data)
		SocialPlus_DoRemoveBNetFriend(data)
	end,
}

function SocialPlus_RemoveCurrentFriend()
	-- Removing a friend renumbers every friend after them, so an index the
	-- memo answered a moment ago now names somebody else. Cleared before the
	-- removal and again after it, because this function reads by index on the
	-- way through.
	if SocialPlus_InvalidateFriendInfo then SocialPlus_InvalidateFriendInfo() end

	local cf=SocialPlus_CurrentFriend
	if not cf or not cf.buttonType or not cf.id then
		FG_Debug("RemoveCurrentFriend: aborted (no current friend)")
		return
	end

	FG_Debug("RemoveCurrentFriend","type="..tostring(cf.buttonType),"id="..tostring(cf.id))

	local kind,dropdownId=SocialPlus_GetDropdownFriend()
	FG_Debug("RemoveCurrentFriend dropdown","kind="..tostring(kind),"dropdownId="..tostring(dropdownId))

	if cf.buttonType==FRIENDS_BUTTON_TYPE_WOW then
		local idx=cf.id
		if kind=="WOW" and dropdownId then
			idx=dropdownId
		end

		local fi=FG_GetFriendInfoByIndex(idx)
		local name=fi and fi.name
		FG_Debug("WOW remove","idx="..tostring(idx),"name="..tostring(name))

		local ok=false

		if C_FriendList and C_FriendList.RemoveFriend then
			if name and name~="" then
				ok=pcall(C_FriendList.RemoveFriend,name)
			else
				ok=pcall(C_FriendList.RemoveFriend,idx)
			end
		end

		if not ok and RemoveFriend then
			if name and name~="" then
				ok=pcall(RemoveFriend,name)
			else
				ok=pcall(RemoveFriend,idx)
			end
		end

		FG_Debug("WOW remove result",tostring(ok))

		if ok then
			local full=SocialPlus_GetFullCharacterName(cf) or name or "Unknown"
			if DEFAULT_CHAT_FRAME and DEFAULT_CHAT_FRAME.AddMessage then
				DEFAULT_CHAT_FRAME:AddMessage("|cffffff00"..string.format(L.MSG_REMOVE_FRIEND_SUCCESS,full).."|r")
			end
			-- Favorite status is stored independently of Blizzard's own
			-- friend record (SocialPlus_GetFavoriteKey, keyed by name, not
			-- tied to their friend-list entry), so removing the friend
			-- never cleared it on its own -- re-adding them later silently
			-- brought the old favorite flag back (reported live).
			if name and name~="" and SocialPlus_SavedVars and SocialPlus_SavedVars.favorites then
				SocialPlus_SavedVars.favorites["WOW:"..name]=nil
			end
		end

	elseif cf.buttonType==FRIENDS_BUTTON_TYPE_BNET then
		local bnIndex=cf.bnetIndex or cf.id
		if kind=="BNET" and dropdownId then
			bnIndex=dropdownId
		end

		local t={FG_BNGetFriendInfo(bnIndex)}
		local presenceID=t[1]
		local accountID=cf.accountID or t[1]
		local bnetName=t[2] or cf.accountName or cf.rawName or UNKNOWN
		local battleTag=t[3]

		FG_Debug(
			"BNET remove (prompt)",
			"bnIndex="..tostring(bnIndex),
			"presenceID="..tostring(presenceID),
			"accountID="..tostring(accountID),
			"name="..tostring(bnetName)
		)

		local dialogData={
			bnIndex=bnIndex,
			presenceID=presenceID,
			accountID=accountID,
			battleTag=battleTag,
		}

		StaticPopup_Show("SOCIALPLUS_CONFIRM_REMOVE_BNET",bnetName,nil,dialogData)
		return
	end

	pcall(SocialPlus_Update)
end

-- [[ Group submenu builder for "Add"/"Remove from group" ]]
function SocialPlus_BuildGroupSubmenu(mode,level)
	local dropdown=FriendsFrameDropDown or L_UIDROPDOWNMENU_INIT_MENU or UIDROPDOWNMENU_INIT_MENU
	if not dropdown then return end

	local _,_,note=SocialPlus_GetDropdownFriendNote()
	local groups={}
	NoteAndGroups(note,groups)

	local choices={}

	if mode=="ADD" then
		for _,group in ipairs(GroupSorted or {}) do
			-- Favorites and In-game Friends aren't real groups a friend can
			-- be tagged into via their note -- both are display-time
			-- buckets (favorite flag / ungrouped native friends).
			if group~="" and group~=SP_FAVORITES_GROUP and group~=SP_INGAME_GROUP
				and group~=FriendRequestString and not groups[group] then
				table.insert(choices,group)
			end
		end
		-- Already in the same order the groups actually appear in the
		-- list (GroupSorted) -- don't alphabetize on top of that (confirmed
		-- live: "Move to another Group" should read rdru -> Godcomp -> RBG,
		-- matching the visible order, not A-Z).
	else
		for group,present in pairs(groups) do
			if present and group~="" then
				table.insert(choices,group)
			end
		end
		table.sort(choices)
	end

	local info=LibDD:UIDropDownMenu_CreateInfo()
		if #choices==0 then
		info.text=(mode=="ADD") and L.GROUP_NO_GROUPS or L.GROUP_NO_GROUPS_REMOVE
		info.notCheckable=true
		info.disabled=true
		LibDD:UIDropDownMenu_AddButton(info,level)
		return
	end


	local c=NORMAL_FONT_COLOR
	local hex=string.format("|cff%02x%02x%02x",c.r*255,c.g*255,c.b*255)
	for _,group in ipairs(choices) do
		info=LibDD:UIDropDownMenu_CreateInfo()
		info.text="["..hex..group.."|r]"
		info.notCheckable=true
		info.func=function() SocialPlus_ModifyGroupFromDropdown(group,mode) end
		LibDD:UIDropDownMenu_AddButton(info,level)
	end
end

-- [[ Invite submenu: choose which character, for a friend with multiple
-- WoW licenses online at once (matches Retail) ]]
function SocialPlus_BuildInviteAccountSubmenu(level)
	local kind,id=SocialPlus_GetDropdownFriend()
	if kind~="BNET" or not id then return end

	local accounts=SocialPlus_GetOnlineWoWGameAccounts(id)
	if #accounts==0 then
		local info=LibDD:UIDropDownMenu_CreateInfo()
		info.text=L.INVITE_GENERIC_FAIL
		info.notCheckable=true
		info.disabled=true
		LibDD:UIDropDownMenu_AddButton(info,level)
		return
	end

	if not playerFaction then FG_InitFactionIcon() end
	local playerRegionID=SocialPlus_GetClientRegionID()

	-- Group by WoW version with a header per group ("TBC", "MoP", ...) --
	-- with several linked accounts online at once, nothing on the row
	-- itself said which client each one was actually on (reported live:
	-- couldn't tell a TBC character from a MoP one at a glance). Stable
	-- sort keeps each version's accounts in their original relative order.
	local sorted={}
	for i,acct in ipairs(accounts) do sorted[i]=acct end
	table.sort(sorted,function(a,b) return (a.wowProjectID or 0)<(b.wowProjectID or 0) end)

	local c=NORMAL_FONT_COLOR
	local hex=string.format("|cff%02x%02x%02x",c.r*255,c.g*255,c.b*255)
	local lastProjectID
	for _,acct in ipairs(sorted) do
		if acct.wowProjectID~=lastProjectID then
			lastProjectID=acct.wowProjectID
			local header=LibDD:UIDropDownMenu_CreateInfo()
			header.text="["..SocialPlus_GetVersionLabelText(acct.wowProjectID).."]"
			header.isTitle=true
			header.notCheckable=true
			header.disabled=true
			header.justifyH="CENTER"
			LibDD:UIDropDownMenu_AddButton(header,level)
		end

		local target=acct.characterName
		if acct.realmName and acct.realmName~="" then
			target=target.."-"..acct.realmName
		end

		-- Class-colored, same as every other level/class detail string in
		-- this addon (SocialPlus_BuildFriendDetailBlock etc.) -- this was
		-- the one place still using plain text (reported live).
		local details={}
		if acct.level and acct.level~=0 then table.insert(details,tostring(acct.level)) end
		if acct.className and acct.className~="" then
			table.insert(details,ClassColourCode(acct.className)..acct.className.."|r")
		end
		local detailText=(#details>0) and (" ("..table.concat(details,", ")..")") or ""

		-- Same eligibility signals used elsewhere (faction, project,
		-- region, canCoop) -- simplified to this one candidate rather than
		-- the full SocialPlus_GetInviteStatus chain, since that resolves
		-- against whichever account GetFriendInfoById currently prefers,
		-- not necessarily the specific one being listed here. Region was
		-- missing entirely (SocialPlus_GetOnlineWoWGameAccounts never
		-- captured it) -- reported live: an EU account showed as
		-- inviteable to an NA player. canCoop was also missing -- same
		-- "this account can never group with you" catch-all the button
		-- restriction trusts (SocialPlus_GetInviteStatus, "Trust
		-- Blizzard's canCoop flag" below): explicitly false, not nil/
		-- unknown, blocks.
		local factionMismatch=acct.factionName and playerFaction and acct.factionName~=playerFaction
		local projectMismatch=WOW_PROJECT_ID and acct.wowProjectID and acct.wowProjectID~=WOW_PROJECT_ID
		local regionMismatch=acct.regionID and playerRegionID and acct.regionID~=playerRegionID
		local coopBlocked=acct.gameAccountID and CanCooperateWithGameAccount
			and CanCooperateWithGameAccount(acct.gameAccountID)==false
		local ineligible=factionMismatch or projectMismatch or regionMismatch or coopBlocked

		-- Faction crest on the right of each entry, same icon paths as the
		-- main friends-list row (reported live: no way to tell which
		-- account was which faction at a glance in this menu).
		local factionIcon=""
		if acct.factionName=="Horde" then
			factionIcon=" |TInterface\\FriendsFrame\\plusmanz-horde:14:14:0:0|t"
		elseif acct.factionName=="Alliance" then
			factionIcon=" |TInterface\\FriendsFrame\\plusmanz-alliance:14:14:0:0|t"
		end

		-- Opposite-faction entries specifically render fully gray, not just
		-- the library's own (subtle) disabled dimming -- reported live as
		-- not obvious enough at a glance.
		local nameHex=factionMismatch and "|cff808080" or hex

		-- Region tag on the far left of the line -- with several linked
		-- accounts online at once (e.g. one NA, one EU), nothing distinguished
		-- them by region at a glance the way the version header already does.
		local regionPrefix=""
		if acct.regionID==1 then
			regionPrefix="|cff808080["..L.REGION_NA.."]|r "
		elseif acct.regionID==3 then
			regionPrefix="|cff808080["..L.REGION_EU.."]|r "
		end

		local info=LibDD:UIDropDownMenu_CreateInfo()
		info.text=regionPrefix.."["..nameHex..target.."|r]"..detailText..factionIcon
		info.notCheckable=true
		info.disabled=ineligible
		if ineligible then
			info.tooltipTitle=target
			info.tooltipText=factionMismatch and L.INVITE_REASON_OPPOSITE_FACTION
				or regionMismatch and L.INVITE_REASON_NO_REALM
				or projectMismatch and L.INVITE_REASON_WRONG_PROJECT
				or L.INVITE_GENERIC_FAIL
		end
		info.func=function()
			if C_PartyInfo and C_PartyInfo.InviteUnit then
				pcall(C_PartyInfo.InviteUnit,target)
			end
			LibDD:CloseDropDownMenus()
		end
		LibDD:UIDropDownMenu_AddButton(info,level)
	end
end


-- [[ Friend online/offline notifications ]]

-- How long a friend's state must stay unchanged before we commit to a
-- notification. Restarted on every relevant signal for that friend (BNet
-- online/offline events, or the polling scan below noticing a difference),
-- so a burst of changes -- e.g. a character switch, which can briefly
-- report no active character mid-loading-screen before the new one appears
-- -- resolves to exactly one notification once things actually settle,
-- instead of reacting separately to each intermediate state (confirmed
-- live: that's exactly what produced the old "logged out" immediately
-- followed by "came online" spam on a character switch).
-- Trimmed from 3s to 1s for snappier notifications: the blips this bridges
-- are sub-second, and the window restarts on every new signal anyway, so a
-- genuinely unsettled friend still resolves only once. If switch-spam ever
-- returns, raise this first.
local SOCIALPLUS_NOTIFY_DEBOUNCE_WINDOW=1

-- Last CONFIRMED (settled) state per bnetIDAccount. Diffed against a fresh
-- query when a friend's debounce timer fires to decide exactly one
-- transition to announce, then overwritten with the fresh state. Also
-- doubles as the "last known info" source for offline/left-WoW messages,
-- whose real game-account data Blizzard has often already cleared by the
-- time we notice.
local SocialPlus_FriendSnapshot={}
local SocialPlus_NotifyDebounceTimer={}

-- Right after login/reload, friends' game-account data (character name,
-- level, etc.) streams in gradually rather than arriving all at once, so a
-- snapshot taken too early can read as a false transition once things
-- settle. During warmup, only establish baselines -- never announce.
--
-- Declared with the other friend-list state near the top of the file, not here:
-- a reader ~5,000 lines above this point had it out of scope, so that guard was
-- reading a nil global and its "or 0" turned the whole warmup check into a
-- no-op that nothing reported.

-- Find the friend-LIST INDEX for a given presence ID (bnetIDAccount).
local function SocialPlus_FindFriendIndexByPresenceID(bnetIDAccount)
	for i=1,FG_BNGetNumFriends() do
		local presenceID=FG_BNGetFriendInfo(i)
		if presenceID==bnetIDAccount then
			return i
		end
	end
	return nil
end

-- Inline faction icon (Horde/Alliance) for a friend at the given friend-LIST
-- INDEX, or "" if unknown. Uses the same icon textures and faction-lookup
-- path (C_BattleNet.GetFriendAccountInfo) already used by FG_InitFactionIcon
-- and SocialPlus_GetInviteStatus elsewhere in this file.
local function SocialPlus_FormatFactionIconText(faction)
	local iconPath
	if faction=="Horde" then
		iconPath="Interface\\FriendsFrame\\plusmanz-horde"
	elseif faction=="Alliance" then
		iconPath="Interface\\FriendsFrame\\plusmanz-alliance"
	end
	if not iconPath then return "" end
	return " |T"..iconPath..":14:14:0:0|t"
end

-- "" for Korea/Taiwan/China or when unknown (not requested). Placeholder
-- until real flag icon art is added. Global (not local) -- called from
-- SocialPlus_UpdateFriendButton, which is defined earlier in this file, so
-- a local here wouldn't be visible there as an upvalue (same class of
-- forward-reference issue as SocialPlus_NormalizeRealmForCompare earlier).
-- The region as a little flag, or as letters.
--
-- Its own copy of the art rather than ArenaPlus's, even though that addon has
-- the same two files: SocialPlus already treats ArenaPlus as optional -- the
-- spec icons simply do not appear without it -- and a friends list quietly
-- losing its flags because a different addon was disabled would be a puzzle
-- nobody could solve from the outside.
--
-- Both flags are drawn at one shape, 1.67 wide to 1 tall, which is neither's
-- true proportion: the American flag is 19:10 and the European 3:2, and side by
-- side at the same height that difference reads as a mistake rather than as a
-- fact about flags.
-- One table, and a global rather than two more locals.
--
-- This file's main chunk sits exactly on Lua's limit of 200 locals, and adding
-- two went over it: "main function has more than 200 local variables". Anything
-- declared at file scope here has to earn its slot, and constants do not need
-- one.
SocialPlus_RegionFlagArt={
	aspect=1.67,
	[1]={ texture="Interface\\AddOns\\SocialPlus\\Media\\region-us", texels={ 23,105,10,54 } },
	[3]={ texture="Interface\\AddOns\\SocialPlus\\Media\\region-eu", texels={ 23,105,4,59 } },
}

function SocialPlus_FormatRegionFlag(regionID,height)
	if not (SocialPlus_SavedVars and SocialPlus_SavedVars.region_flag) then return nil end

	local art=SocialPlus_RegionFlagArt
	local flag=regionID and art and art[regionID]
	if not flag then return nil end

	height=height or 12

	return ("|T%s:%d:%d:0:0:128:64:%d:%d:%d:%d|t"):format(
		flag.texture,height,math.floor(height*art.aspect+0.5),
		flag.texels[1],flag.texels[2],flag.texels[3],flag.texels[4])
end

-- What the row draws beside a name: the flag, and the spec icon.
--
-- Both answer nil rather than something blank, so the row can tell "nothing to
-- show" from "something to show" and lay its chain out accordingly.

function SocialPlus_RowRegionFlag(button)
	if not (SocialPlus_SavedVars and SocialPlus_SavedVars.region_flag) then return nil end
	if not button then return nil end

	local art=SocialPlus_RegionFlagArt
	return art and button.SocialPlusRegionID and art[button.SocialPlusRegionID] or nil
end

function SocialPlus_FormatRegionText(regionID)
	if regionID==1 then
		return " ("..L.REGION_NA..")"
	elseif regionID==3 then
		return " ("..L.REGION_EU..")"
	end
	return ""
end

local function SocialPlus_GetFriendGameAccountInfo(index)
	if not (index and C_BattleNet and C_BattleNet.GetFriendAccountInfo) then return nil end
	local acct=C_BattleNet.GetFriendAccountInfo(index)
	return acct and acct.gameAccountInfo
end

-- Shared by all four notification types below so they show identical
-- detail: faction icon, region, level, class, version. Built directly in
-- code rather than via a Locales.lua %s-shaped template: that format
-- string has repeatedly been served stale (a leftover shape from an
-- earlier edit) despite reloads and full client restarts, silently
-- misaligning arguments. Each known detail is included individually so an
-- unresolved class/level doesn't show as a literal "Unknown"/"?".
local function SocialPlus_BuildFriendDetailBlock(level,class,wowProjectID,faction,regionID)
	local factionIcon=SocialPlus_FormatFactionIconText(faction)
	local regionText=SocialPlus_FormatRegionText(regionID)
	local versionText=SocialPlus_GetVersionLabelText(wowProjectID)

	local details={}
	if level and level~=0 then table.insert(details,tostring(level)) end
	if class and class~="" then table.insert(details,ClassColourCode(class)..class.."|r") end
	if versionText and versionText~="?" then table.insert(details,versionText) end
	local detailText=(#details>0) and (" ("..table.concat(details,", ")..")") or ""

	return factionIcon..regionText..detailText
end

-- True if the friend is in at least one non-muted group. Ungrouped friends
-- (no group tags in their note) are controlled by muting the "General" /
-- L.GROUP_UNGROUPED pseudo-group, matching the group-header dropdown.
-- A favorited friend is a special case, by explicit request: their real
-- group's mute setting is ignored entirely -- only the Favorites group's
-- own "Mute Notifications" toggle decides, muted or not, regardless of
-- what their real group (even General) is set to.
local function SocialPlus_ShouldNotifyForNote(note,battleTag)
	local muted=SocialPlus_SavedVars and SocialPlus_SavedVars.notifications and SocialPlus_SavedVars.notifications.mutedGroups
	if not muted then return true end

	if battleTag and battleTag~="" and SocialPlus_SavedVars.favorites and SocialPlus_SavedVars.favorites["BNET:"..battleTag] then
		return not muted[SP_FAVORITES_GROUP]
	end

	local groups={}
	NoteAndGroups(note,groups)

	for group in pairs(groups) do
		local muteKey=(group~="" and group) or L.GROUP_UNGROUPED
		if not muted[muteKey] then
			return true
		end
	end
	return false
end

-- Group name color for the notification prefix, styled like a clickable
-- hyperlink so it reads as interactive (see the SetItemRef hook below).
local SOCIALPLUS_GROUP_LINK_COLOR="|cff4da6ff"

-- Comma-separated, alphabetised list of the friend's groups (via the note-tag
-- system), formatted as "[GroupA, GroupB] " (trailing space, meant to lead
-- the message right after "[SocialPlus] "). Each group name is a clickable
-- hyperlink (see the SetItemRef hook below) that opens the Friends panel
-- and searches for that group. Empty string if ungrouped. If the friend is
-- favorited, their real group(s) are ignored entirely and this shows
-- "[<star> Favorites] " instead, matching how favoriting already overrides
-- their real group's mute setting elsewhere.
local function SocialPlus_BuildGroupPrefix(note,battleTag)
	if battleTag and battleTag~="" and SocialPlus_SavedVars.favorites and SocialPlus_SavedVars.favorites["BNET:"..battleTag] then
		-- Clickable like regular group links: opens the panel with the
		-- Favorites label in the search box (search already matches
		-- favorited friends by that label).
		local favLabel=SocialPlus_GetFavoritesLabel()
		return "["..SOCIALPLUS_GROUP_LINK_COLOR.."|Hsocialplus_group:"..favLabel.."|h|TInterface\\Common\\FavoritesIcon:14:14:0:-1|t"..favLabel.."|h|r] "
	end

	local groups={}
	NoteAndGroups(note,groups)

	local names={}
	for group in pairs(groups) do
		if group~="" then
			table.insert(names,group)
		end
	end
	if #names==0 then
		return ""
	end
	table.sort(names)

	local links={}
	for _,name in ipairs(names) do
		links[#links+1]=SOCIALPLUS_GROUP_LINK_COLOR.."|Hsocialplus_group:"..name.."|h"..name.."|h|r"
	end
	return "["..table.concat(links,", ").."] "
end

-- Clicking a group-name link (built above) opens the Friends panel and
-- searches for that group.
local function SocialPlus_OnGroupLinkClick(link)
	local groupName=link and link:match("^socialplus_group:(.*)$")
	if not groupName then return end
	-- ShowFriendsFrame doesn't exist as a global on this client
	-- (confirmed live -- the panel silently failed to open while the
	-- search-text part still worked). ShowUIPanel + PanelTemplates_SetTab
	-- are the same primitives this file already relies on elsewhere for
	-- FriendsFrame.
	if ShowUIPanel then
		ShowUIPanel(FriendsFrame)
	end
	if PanelTemplates_SetTab then
		PanelTemplates_SetTab(FriendsFrame,1)
	end
	if SocialPlus_Searchbox then
		SocialPlus_Searchbox:SetText(groupName)
	end
end

-- Wired through the client's official LinkUtil handler registry, NOT by
-- replacing the global SetItemRef. The old global replacement put EVERY
-- chat hyperlink click -- including right-clicking a player name, whose
-- unit popup menu gets built inside that same SetItemRef call -- under
-- insecure execution, so the menu's protected actions were blocked
-- (confirmed live: "Copy Character Name" threw ADDON_ACTION_FORBIDDEN
-- for CopyToClipboard, blaming SocialPlus). With a registered handler,
-- Blizzard's own SetItemRef stays fully secure, dispatches our link type
-- to us, and returns Handled before ever reaching its erroring
-- ItemRefTooltip fallback; clicks on every other link type never touch
-- addon code at all.
if LinkUtil and LinkUtil.RegisterLinkHandler then
	LinkUtil.RegisterLinkHandler("socialplus_group",SocialPlus_OnGroupLinkClick)
else
	-- Fallback for any client variant without the registry: the old
	-- override, taint downsides and all -- better than group links doing
	-- nothing (Blizzard's SetItemRef hard-errors on unknown link types,
	-- so a plain posthook can't work).
	local SocialPlus_OrigSetItemRef=SetItemRef
	SetItemRef=function(link,text,button,chatFrame)
		if link and link:match("^socialplus_group:") then
			SocialPlus_OnGroupLinkClick(link)
			return
		end
		return SocialPlus_OrigSetItemRef(link,text,button,chatFrame)
	end
end

-- Class-colored, clickable friend link. Uses a real Battle.net "BNplayer" link
-- (accountName+presenceID) rather than a plain character |Hplayer:Name-Realm|h
-- link: a plain player link opens an ordinary /w, which WoW blocks for
-- opposite-faction targets — but BNet friends must be reachable regardless of
-- faction, exactly like the existing MENU_WHISPER menu item already handles
-- via FriendsFrameSendMessageButton_OnClick. Falls back to a plain player
-- link only if we somehow don't have BNet identity info.
-- Realm names must have spaces stripped for the Name-Realm token to work as
-- a whisper target (e.g. "Emerald Dream" -> "EmeraldDream").
local function SocialPlus_BuildFriendLink(characterName,realmName,class,accountName,presenceID)
	local fullName=characterName
	if fullName and realmName and realmName~="" then
		fullName=characterName.."-"..realmName:gsub("%s+","")
	end
	local classColourCode=ClassColourCode(class)

	-- Match the existing Friends List row style: BNet name in
	-- FRIENDS_BNET_NAME_COLOR, followed by the class-coloured
	-- "(CharacterName-Realm)" -- see SocialPlus_GetBNetButtonNameText.
	-- characterName can be nil (offline/BNet-only friend with no cached
	-- character on record), in which case just show the account name alone
	-- rather than crash on concatenating a nil into "(...)" (confirmed live).
	if accountName and accountName~="" and presenceID then
		local bnetColourCode=string.format("|cFF%02x%02x%02x",
			FRIENDS_BNET_NAME_COLOR.r*255,FRIENDS_BNET_NAME_COLOR.g*255,FRIENDS_BNET_NAME_COLOR.b*255)
		local displayText=bnetColourCode.."["..accountName.."]|r"
		if fullName then
			displayText=displayText.." "..classColourCode.."("..fullName..")|r"
		end
		return "|HBNplayer:"..accountName..":"..presenceID.."|h"..displayText.."|h"
	end

	fullName=fullName or accountName or ""
	return classColourCode.."|Hplayer:"..fullName.."|h"..fullName.."|h|r"
end

-- Minimum gap between friend-online chimes, in seconds. Logging in, or a
-- guild group all coming online together, used to fire one chime per friend
-- back to back.
SOCIALPLUS_ONLINE_SOUND_GAP=5

-- Deliberately a global rather than a file-scope local: this chunk sits at
-- Lua's 200-locals-per-chunk ceiling (see SP_Rebuild), so there is no local
-- slot left to spend on a timestamp.
SocialPlus_SoundThrottle=SocialPlus_SoundThrottle or {}

-- withSound is opt-in per caller: only a friend coming ONLINE chimes. Going
-- offline prints its message silently -- a friend leaving isn't something you
-- need to be pulled away from what you're doing for.
local function SocialPlus_PrintNotification(text,withSound)
	if DEFAULT_CHAT_FRAME and DEFAULT_CHAT_FRAME.AddMessage then
		DEFAULT_CHAT_FRAME:AddMessage(text)
	end
	if not withSound then return end
	-- Blizzard's own friend online/offline chime -- SOUNDKIT.UI_BNET_TOAST
	-- (sound kit 18019, same ID across Vanilla/TBC/Wrath's FrameXML source,
	-- so it's not version-specific). Not gated behind the toast CVars this
	-- addon already flips off (SocialPlus_ApplyToastCVars) -- those only
	-- suppress Blizzard's visual toast, not this sound, so playing it here
	-- reproduces what the default chat message is normally paired with,
	-- independent of the (disabled) toast popup.
	if SocialPlus_SavedVars and SocialPlus_SavedVars.notifications and SocialPlus_SavedVars.notifications.sound then
		-- Leading edge: the first friend in a burst is heard immediately, the
		-- rest of the burst is silent. The chat messages are all still printed,
		-- so nothing is lost -- only the repeated chime is dropped.
		local now=(GetTime and GetTime()) or 0
		local last=SocialPlus_SoundThrottle.lastOnline or 0
		if now-last<SOCIALPLUS_ONLINE_SOUND_GAP then return end
		SocialPlus_SoundThrottle.lastOnline=now

		if SOUNDKIT and SOUNDKIT.UI_BNET_TOAST then
			PlaySound(SOUNDKIT.UI_BNET_TOAST)
		else
			PlaySound(18019)
		end
	end
end

-- Query a friend's CURRENT state fresh (never trust cached/event-supplied
-- data -- that's exactly what let the old code commit to a message before
-- a character switch had actually finished). Returns a plain table so it
-- can be stored directly as a snapshot and reused as the "cached info"
-- source for offline/left-WoW messages, whose real game-account data
-- Blizzard has often already cleared by the time we notice.
local function SocialPlus_CaptureFriendState(bnetIDAccount)
	local index=SocialPlus_FindFriendIndexByPresenceID(bnetIDAccount)
	if not index then
		return {online=false}
	end

	local accountName,characterName,class,level,_,isOnline,_,_,_,wowProjectID,_,_,_,_,_,_,_,_,realmName=
		GetFriendInfoById(index)
	local ga=SocialPlus_GetFriendGameAccountInfo(index)
	local _,_,battleTag,_,_,_,_,_,_,_,_,_,noteText=FG_BNGetFriendInfo(index)

	return {
		online=isOnline and true or false,
		inWoW=(isOnline and characterName and characterName~="") and true or false,
		characterName=characterName,realmName=realmName,class=class,level=level,
		wowProjectID=wowProjectID,accountName=accountName,presenceID=bnetIDAccount,battleTag=battleTag,
		faction=ga and ga.factionName,regionID=ga and ga.regionID,noteText=noteText,
	}
end

local function SocialPlus_NotifyOnline(state)
	local link=SocialPlus_BuildFriendLink(state.characterName,state.realmName,state.class,state.accountName,state.presenceID)
	local detailBlock=SocialPlus_BuildFriendDetailBlock(state.level,state.class,state.wowProjectID,state.faction,state.regionID)
	local groupPrefix=SocialPlus_BuildGroupPrefix(state.noteText,state.battleTag)
	local msg=string.format(L.NOTIFY_ONLINE_MSG,link..detailBlock)
	SocialPlus_PrintNotification(groupPrefix..msg..".",true)
end

local function SocialPlus_NotifyOffline(state)
	local link=SocialPlus_BuildFriendLink(state.characterName,state.realmName,state.class,state.accountName,state.presenceID)
	local groupPrefix=SocialPlus_BuildGroupPrefix(state.noteText,state.battleTag)
	local msg=string.format(L.NOTIFY_OFFLINE_MSG,link)
	SocialPlus_PrintNotification(groupPrefix..msg..".")
end

-- The core deferred-comparison logic: called once a friend's per-friend
-- debounce timer settles (see SocialPlus_QueueNotifyCheck below). Queries
-- current state fresh, diffs against the last CONFIRMED snapshot, and
-- emits at most one notification for the net transition, no matter how
-- many intermediate blips (offline, no active character, etc.) happened
-- while the debounce timer was running.
local function SocialPlus_ResolveNotifyTransition(bnetIDAccount)
	local current=SocialPlus_CaptureFriendState(bnetIDAccount)
	local prev=SocialPlus_FriendSnapshot[bnetIDAccount]

	-- Still settling in after login/reload, or first time ever seeing this
	-- friend this session: just establish the baseline, don't announce.
	if not prev or GetTime()<SocialPlus_ScanWarmupUntil then
		SocialPlus_FriendSnapshot[bnetIDAccount]=current
		return
	end

	local n=SocialPlus_SavedVars and SocialPlus_SavedVars.notifications
	local onlineEnabled=n and n.enabled
	local offlineEnabled=onlineEnabled and n.offline_too

	if onlineEnabled and not SocialPlus_ShouldNotifyForNote(current.noteText or prev.noteText,current.battleTag or prev.battleTag) then
		onlineEnabled=false
		offlineEnabled=false
	end

	-- "Only notify [current client] friends" -- opt-in filter, off by
	-- default. current.wowProjectID is nil once they've gone offline, so
	-- fall back to prev's (the last time we actually saw them in WoW).
	if onlineEnabled and n.same_version_only then
		local wowProjectID=current.wowProjectID or prev.wowProjectID
		if wowProjectID and WOW_PROJECT_ID and wowProjectID~=WOW_PROJECT_ID then
			onlineEnabled=false
			offlineEnabled=false
		end
	end

	if not prev.online and current.online then
		if onlineEnabled then SocialPlus_NotifyOnline(current) end
	elseif prev.online and not current.online then
		if offlineEnabled then SocialPlus_NotifyOffline(prev) end
	elseif prev.inWoW and current.online and not current.inWoW then
		-- Still on Battle.net, just no longer active in WoW -- from the
		-- player's perspective this reads the same as going offline, so it
		-- shares the same message instead of a separate "left WoW" one.
		if offlineEnabled then SocialPlus_NotifyOffline(prev) end
	elseif not prev.inWoW and current.online and current.inWoW then
		-- Was already Battle.net-online but not actively in WoW (idling in
		-- the app, playing another game, or just never resolved), and is
		-- now in WoW -- the mirror of the "left WoW" case above. Missing
		-- this branch meant a friend bouncing between two linked WoW
		-- licenses (dual-boxed characters) could show repeated "left WoW"
		-- messages with no matching "came online" in between (confirmed
		-- live). Reuses the online message/toggle, same as a true BNet
		-- connect -- from the player's perspective it's the same thing:
		-- the friend just became visible as active in WoW.
		if onlineEnabled then SocialPlus_NotifyOnline(current) end
	end
	-- Any other case (same character, a character swap while staying in
	-- WoW, or an already-offline friend staying offline) is a flap/no-op:
	-- nothing to announce. Character-switch notifications were tried and
	-- removed -- never actually observed firing in practice, only the
	-- plain online/left-WoW messages.

	SocialPlus_FriendSnapshot[bnetIDAccount]=current
end

-- Restarts (rather than merely starts) the debounce timer on every call, so
-- a burst of signals for the same friend -- BNet online/offline events, or
-- the polling scan below noticing a difference -- keeps pushing the
-- decision back until the friend's state has actually stopped changing.
local function SocialPlus_QueueNotifyCheck(bnetIDAccount)
	if not bnetIDAccount then return end
	local existing=SocialPlus_NotifyDebounceTimer[bnetIDAccount]
	if existing then
		existing:Cancel()
	end
	SocialPlus_NotifyDebounceTimer[bnetIDAccount]=C_Timer.NewTimer(SOCIALPLUS_NOTIFY_DEBOUNCE_WINDOW,function()
		SocialPlus_NotifyDebounceTimer[bnetIDAccount]=nil
		SocialPlus_ResolveNotifyTransition(bnetIDAccount)
	end)
end

-- [[ "Left/entered WoW while staying connected" + character-switch detection ]]
-- BN_FRIEND_ACCOUNT_ONLINE/OFFLINE only fire on a true Battle.net connect/
-- disconnect -- a friend switching characters (or quitting/launching WoW
-- while staying connected to the app, or playing a different Blizzard
-- game) never fires them. So this also polls the friends list (triggered
-- by BN_FRIEND_ACCOUNT_ONLINE/OFFLINE plus FRIENDLIST_UPDATE, with a
-- periodic fallback since neither reliably fires for a passive AFK
-- disconnect either) and feeds ANY detected difference into the same
-- debounced resolver above, rather than deciding anything here directly.
local SocialPlus_ScanPending=false

local function SocialPlus_ScanFriendsForWoWStateChanges()
	SocialPlus_ScanPending=false

	-- Nothing this scan does can ever produce a notification if the master
	-- toggle is off -- skip it entirely rather than pay for a full pass
	-- over every friend for nothing (confirmed live: this was the main
	-- memory/CPU cost of the addon on a very large friends list, since it
	-- ran unconditionally regardless of settings).
	if not (SocialPlus_SavedVars and SocialPlus_SavedVars.notifications and SocialPlus_SavedVars.notifications.enabled) then
		return
	end

	for i=1,FG_BNGetNumFriends() do
		-- Cheap raw-tuple read first (same lightweight BNGetFriendInfo call
		-- used elsewhere in this file) so a friend whose every group is
		-- muted can be skipped before paying for the much heavier
		-- GetFriendInfoById (C_BattleNet + BNGetGameAccountInfo) lookup --
		-- a muted friend can never produce a notification either direction.
		-- (Unlike before, a friend already known to be in WoW can no longer
		-- be skipped just because offline_too is off -- character-switch
		-- detection needs their characterName re-checked regardless, since
		-- it's gated by the online toggle instead.)
		-- Positional destructure, not a {tuple} wrapper.
		--
		-- The wrapper allocated a fresh 13-slot table per friend per scan --
		-- ~460 of them every time this ran on the list this was reported from,
		-- and this scan runs on a 0.2s coalesce off BN_FRIEND_INFO_CHANGED
		-- whether or not the friends panel is even open. That is churn the
		-- collector then has to walk, which is felt as stutter rather than as
		-- a slow frame. SocialPlus_Update's own BNet loop was already fixed
		-- this way (see the note on positions there); this one was missed.
		local presenceID,_,battleTag,_,_,_,_,_,_,_,_,_,noteText=FG_BNGetFriendInfo(i)

		if presenceID and SocialPlus_ShouldNotifyForNote(noteText,battleTag) then
			local _,characterName,_,_,_,isOnline,_,_,_,_,_,_,_,_,_,_,_,_,realmName=GetFriendInfoById(i)

			local prev=SocialPlus_FriendSnapshot[presenceID]
			local nowOnline=isOnline and true or false
			local changed=(not prev) or (prev.online~=nowOnline) or (prev.characterName~=characterName) or (prev.realmName~=realmName)

			if changed then
				SocialPlus_QueueNotifyCheck(presenceID)
			end
		end
	end
end

-- FRIENDLIST_UPDATE can fire repeatedly in a burst; coalesce into one scan.
-- Short delay: this only batches near-simultaneous events, it isn't a
-- flap-protection window (that's the notify debounce above), so it can be
-- trimmed aggressively.
local function SocialPlus_QueueFriendScan()
	if SocialPlus_ScanPending then return end
	SocialPlus_ScanPending=true
	C_Timer.After(0.2,SocialPlus_ScanFriendsForWoWStateChanges)
end

-- [[ Suppress Blizzard's own friend online/offline notification ]]
-- Blizzard's "friend came online/offline" line turned out to be an inline
-- toast overlay, not a real chat message (confirmed live: it never appears
-- in CHAT_MSG_SYSTEM, and third-party chat-copy addons can't see it either),
-- so a ChatFrame message filter can never catch it no matter how the pattern
-- is built. Instead, directly control the two CVars that the Blizzard
-- Options -> Social "online/offline friends" checkboxes themselves set
-- (confirmed live via a SetCVar hook): showToastOnline / showToastOffline.
-- This takes over both toasts whenever our own notification is on, and hands
-- them back the moment it's off.
--
-- Hands back what the player had, not what Blizzard ships with. Turning our
-- notifications off used to write "1" into both, so anybody who had deliberately
-- switched Blizzard's online/offline toasts off got them switched back on by an
-- addon they had just told to stop doing things.
--
-- The original is captured once, on the way in, while the CVars are still
-- theirs; capturing on any later call would record our own "0" as their
-- preference. Cleared again on the way out, so the next time we take over we
-- read a fresh value rather than a stale one.
function SocialPlus_ApplyToastCVars()
	if not SocialPlus_SavedVars then return end

	local enabled=SocialPlus_SavedVars.notifications and SocialPlus_SavedVars.notifications.enabled
	local saved=SocialPlus_SavedVars.toastCVars

	if enabled then
		if not saved then
			SocialPlus_SavedVars.toastCVars={
				online=(GetCVar and GetCVar("showToastOnline")) or "1",
				offline=(GetCVar and GetCVar("showToastOffline")) or "1",
			}
		end
		SetCVar("showToastOnline","0")
		SetCVar("showToastOffline","0")
	else
		SetCVar("showToastOnline",(saved and saved.online) or "1")
		SetCVar("showToastOffline",(saved and saved.offline) or "1")
		SocialPlus_SavedVars.toastCVars=nil
	end
end

-- Everything SocialPlus_Init.lua needs from this file.
--
-- Exported rather than promoted to globals: most of these are forward-declared
-- near the top and assigned much later, so dropping "local" would mean editing
-- that block and changing how every reference in between resolves. An export at
-- the end touches nothing else.
--
-- Safe as a snapshot because every one is read-only from the other side and all
-- are assigned during load. A name the other file WRITES cannot be exported this
-- way -- see SocialPlus_ScanWarmupUntil above.

ns.GetFriendInfoById = GetFriendInfoById
ns.SCROLL_BASE = SCROLL_BASE
ns.NoteAndGroups = NoteAndGroups
ns.RemoveGroup = RemoveGroup
ns.frame = frame
ns.Hook = Hook
ns.HookButtons = HookButtons
ns.FriendsScrollFrame = FriendsScrollFrame
ns.FriendButtonTemplate = FriendButtonTemplate
ns.FG_InitFactionIcon = FG_InitFactionIcon
ns.SocialPlus_EnsureSavedVars = SocialPlus_EnsureSavedVars
ns.SocialPlus_GetTopButton = SocialPlus_GetTopButton
ns.SocialPlus_HardResetScrollRows = SocialPlus_HardResetScrollRows
ns.SocialPlus_HideRowTooltip = SocialPlus_HideRowTooltip
ns.SocialPlus_QueueFriendScan = SocialPlus_QueueFriendScan
ns.SocialPlus_QueueNotifyCheck = SocialPlus_QueueNotifyCheck
ns.SocialPlus_ScheduleCollapseSettle = SocialPlus_ScheduleCollapseSettle
ns.SocialPlus_UpdateFriends = SocialPlus_UpdateFriends
