local ADDON_NAME, ns = ...
local L = ns.L

local LibDD = LibStub("LibUIDropDownMenu-4.0")

local hooks = {}

-- Shared click sound for the settings/group cogwheels and reorder arrows
-- (the same "open a menu" sound as clicking Options from the Escape menu).
-- Guarded since SOUNDKIT entries can vary slightly by client version.
local function SocialPlus_PlayMenuClickSound()
	if SOUNDKIT and SOUNDKIT.IG_MAINMENU_OPTION then
		PlaySound(SOUNDKIT.IG_MAINMENU_OPTION)
	end
end

-- Companion "menu closed" sound, played only when a dropdown menu we opened
-- actually closes (not when the search box merely loses focus).
local function SocialPlus_PlayMenuCloseSound()
	if SOUNDKIT and SOUNDKIT.IG_MAINMENU_CLOSE then
		PlaySound(SOUNDKIT.IG_MAINMENU_CLOSE)
	end
end

-- Set true right before showing the click catcher for a cogwheel-opened
-- dropdown menu ONLY (settings button, group-header gear); left false for
-- right-click context menus and the search-box focus case, so neither
-- plays a menu-close sound.
local SocialPlus_ClickCatcherIsForMenu = false


-- Also expose to global to allow calls from any scope

-- NOTE: _G.SocialPlus_GetInviteStatus will be set after the function is defined below

-- Debug helper to trace id resolution and menu actions (set FG_DEBUG = true to enable)
local FG_DEBUG = false

local function FG_Debug(...)
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
local SocialPlus_GetInviteStatus
local SocialPlus_GetGroupKeyFromRow
local SocialPlus_EnsureSavedVars
local SocialPlus_SetCustomGroupOrderFromMove
local SocialPlus_IsRowInDraggedGroup
local SocialPlus_CancelGroupDrag
local SocialPlus_HardResetScrollRows

local CURRENT_DB_VERSION = 2

-- Ensure savedvars exist and set reasonable defaults
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
    if type(SocialPlus_SavedVars.scrollSpeed)~="number" then
        SocialPlus_SavedVars.scrollSpeed=SCROLL_BASE
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
        SocialPlus_SavedVars.notifications.offline_too=false
    end
    if SocialPlus_SavedVars.notifications.same_version_only==nil then
        SocialPlus_SavedVars.notifications.same_version_only=false
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
local function SocialPlus_AsciiLower(s)
    return (s:gsub("[A-Z]",function(c) return c:lower() end))
end

-- Determine the player's region ID based on the "portal" CVar
local playerRegionID=nil

local function SocialPlus_GetClientRegionID()
	if playerRegionID~=nil then
		return playerRegionID
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

-- Scroll speed base: slider value will be divided by this value to get the internal multiplier
local SCROLL_BASE = 2.5

-- Friend list state	
local FriendButtons={count=0}
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
local SocialPlus_CollapseAllButton

-- Returns anyCollapsed, anyExpanded for *custom* groups plus the General
-- bucket (ignores only the Friend Requests header)
local function SocialPlus_GetAnyGroupCollapsed()
	local anyCollapsed=false
	local anyExpanded=false

	if not GroupSorted or not SocialPlus_SavedVars or not SocialPlus_SavedVars.collapsed then
		return false,false
	end

	for _,groupName in ipairs(GroupSorted) do
		-- Ignore only the Friend Requests header
		if groupName~=FriendRequestString then
			if SocialPlus_SavedVars.collapsed[groupName] then
				anyCollapsed=true
			else
				anyExpanded=true
			end
		end
	end

	return anyCollapsed,anyExpanded
end

-- Update icon (+/-), visibility, and mode
local function SocialPlus_UpdateCollapseAllButtonVisual()
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

		-- Escape cancels an active drag. EnableKeyboard(true) + a default
		-- SetPropagateKeyboardInput(true) is the same pattern already
		-- proven working elsewhere in this file (the old scroll-speed
		-- popup, since removed) -- confirmed legal on this client. Only
		-- swallows the key (stops propagation) when a drag is actually in
		-- progress; otherwise every key passes through untouched.
		f:EnableKeyboard(true)
		f:SetPropagateKeyboardInput(true)
		f:SetScript("OnKeyDown",function(self,key)
			if key=="ESCAPE" and SocialPlus_DragSourceGroup then
				self:SetPropagateKeyboardInput(false)
				SocialPlus_CancelGroupDrag()
			else
				self:SetPropagateKeyboardInput(true)
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
		or groupKey==FriendRequestString or groupKey==SP_FAVORITES_GROUP then
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
	local others={}

	for groupName in pairs(GroupTotal) do
		if groupName==FriendRequestString then
			hasFriendReq=true
		elseif groupName==SP_FAVORITES_GROUP then
			hasFavorites=true
		elseif groupName=="" then
			hasGeneral=true
		else
			table.insert(others,groupName)
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

	-- Favorites is always index 0 -- pinned above everything, including
	-- Friend Requests -- and never enters the user-reorderable "others"
	-- list, so it can't be dragged or persisted into groupOrder.
	if hasFavorites then
		table.insert(GroupSorted,SP_FAVORITES_GROUP)
	end
	if hasFriendReq then
		table.insert(GroupSorted,FriendRequestString)
	end
	for _,name in ipairs(others) do
		table.insert(GroupSorted,name)
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
	-- Favorites is synthetic and always index 0 -- never a drag source or
	-- target, and never persisted into groupOrder.
	if source==SP_FAVORITES_GROUP or target==SP_FAVORITES_GROUP then return end

	SocialPlus_EnsureSavedVars()

	-- Build base from current visible order (excluding pinned buckets)
	local base={}
	local sourceIndex,targetIndex

	for _,name in ipairs(GroupSorted or {}) do
		if name~=FriendRequestString and name~="" then
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
	if not group or group==FriendRequestString or group=="" or group==SP_FAVORITES_GROUP then
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
		and (not target or target==source or target==FriendRequestString or target=="" or target==SP_FAVORITES_GROUP)
		and self then
		local fallback
		if self.buttonType==FRIENDS_BUTTON_TYPE_DIVIDER then
			fallback=self.SocialPlusGroupName
		else
			fallback=SocialPlus_GetGroupKeyFromRow(self)
		end

		if fallback and fallback~=source and fallback~=FriendRequestString and fallback~="" and fallback~=SP_FAVORITES_GROUP then
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
		or target==FriendRequestString or target=="" or target==SP_FAVORITES_GROUP then
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
local SocialPlus_Searchbox
local SocialPlus_SearchTerm=nil  -- always normalized or nil

local function SocialPlus_ClearSearch()
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

	-- Fixed, visible position near top-right. 24 tall (was 20) so the text
	-- isn't cramped vertically; 170 wide, nudged up 1px.
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

	-- When there is at least one expanded group (including General), we
	-- "collapse all". When everything is collapsed, we "expand all".
	if anyExpanded then
		-- Collapse all groups, including General
		if GroupSorted then
			for _,groupName in ipairs(GroupSorted) do
				if groupName~=FriendRequestString then
					SocialPlus_SavedVars.collapsed[groupName]=true
				end
			end
		end
	else
		-- Expand all groups, including General
		if GroupSorted then
			for _,groupName in ipairs(GroupSorted) do
				if groupName~=FriendRequestString then
					SocialPlus_SavedVars.collapsed[groupName]=nil
				end
			end
		end
	end

	SocialPlus_HardResetScrollRows()
	SocialPlus_Update(true)
	SocialPlus_Update(true)
	C_Timer.After(0,function()
		SocialPlus_Update(true)
	end)
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
	-- Single-line placeholder: truncates with "..." instead of wrapping to
	-- a second line if a locale string is still too long for the box.
	SocialPlus_Searchbox.Instructions:SetWordWrap(false)

	-- TEMP DIAGNOSTIC: SocialPlus_Searchbox is a file-local upvalue, not a
	-- real global, so /run can't reach it externally -- this slash command
	-- lives inside the addon itself, where it can.
	SLASH_SPSEARCHBOX1="/spsb"
	SlashCmdList["SPSEARCHBOX"]=function()
		local i=SocialPlus_Searchbox.Instructions
		print("region width:",i:GetWidth(),"text width:",i:GetStringWidth(),"text:",i:GetText())
	end
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
		local txt=self:GetText() or ""
		txt=txt:match("^%s*(.-)%s*$") or ""
		local norm=SocialPlus_NormalizeText(txt)
		SocialPlus_SearchTerm=norm~="" and norm or nil
		SocialPlus_UpdateSearchGlow(self)
		FriendsList_Update()
	end)

	SocialPlus_Searchbox:SetScript("OnEditFocusGained",function(self)
		SocialPlus_ShowClickCatcher()
		SocialPlus_UpdateSearchGlow(self)
	end)

	SocialPlus_Searchbox:SetScript("OnEditFocusLost",function(self)
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
	["Interface\\Shop\\CatalogShopProductLogos2x"]={0.26,0.65,0.10,0.90},

	-- Same texture, LEFT logo (used when "different region")
	["Interface\\Shop\\CatalogShopProductLogos2x_LEFT"]={0.00,0.39,0.10,0.90},
}

-- Apply a game/faction icon to a button's gameIcon texture
-- If iconPath is nil or empty, hides the icon
local function FG_ApplyGameIcon(button,iconPath,size,point,relPoint,offX,offY)
	if not iconPath or iconPath=="" or not button or not button.gameIcon then
		if button and button.gameIcon then
			button.gameIcon:Hide()
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

	if iconPath=="Interface\\Shop\\CatalogShopProductLogos2x" then
		size=64
		offX=-8
		offY=-15
	end

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
-- amount. Blizzard's HybridScrollFrame reuses a pool of row buttons keyed
-- to the previous scroll offset/content size, and confirmed live: a big
-- enough single-frame content change can leave that pool out of sync --
-- rows that claim to belong to a still-expanded group not actually drawn,
-- and/or the scrollbar stuck reporting no scrollable range even once
-- content grows back. Force a clean slate before rebuilding: snap the
-- scroll position back to the top and hide every pooled row so nothing
-- carries over stale state from before the collapse toggle.
SocialPlus_HardResetScrollRows=function()
	local sf=FriendsScrollFrame
	if not sf then return end
	if sf.scrollBar then
		sf.scrollBar:SetValue(0)
	end
	if sf.buttons then
		for _,btn in ipairs(sf.buttons) do
			btn.index=nil
			btn:Hide()
		end
	end
end

-- [[ Unified invite helpers (WOW + BNET) ]]
local function SocialPlus_PerformInvite(kind,id)
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
		-- Battle.net friend
		if C_BattleNet and C_BattleNet.GetFriendAccountInfo and type(C_BattleNet.GetFriendAccountInfo)=="function" then
			local accountInfo=C_BattleNet.GetFriendAccountInfo(id)
			local game=accountInfo and accountInfo.gameAccountInfo
			local characterName=game and game.characterName

			if characterName and characterName~="" then
				local target=characterName
				local realmName=game.realmName
				if realmName and realmName~="" then
					target=characterName.."-"..realmName
				end
				if C_PartyInfo and C_PartyInfo.InviteUnit then
					pcall(C_PartyInfo.InviteUnit,target)
					return true
				end
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

-- A single BattleTag can have multiple WoW licenses online at the same
-- time (already established for the faction-preference fix). Returns one
-- entry per currently-online WoW game account linked to this BNet friend
-- (friend-list index), so the invite menu can offer a choice instead of
-- silently inviting whichever one gets picked automatically.
local function SocialPlus_GetOnlineWoWGameAccounts(bnetIndex)
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
				realmName=ga.realmName,
				className=ga.className,
				level=ga.characterLevel,
				wowProjectID=ga.wowProjectID,
				factionName=ga.factionName,
			})
		end
	end
	return accounts
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
	elseif GetNumFriends then
		return GetNumFriends()
	end
	return 0
end

local function FG_GetNumOnlineFriends()
	if C_FriendList and C_FriendList.GetNumOnlineFriends then
		return C_FriendList.GetNumOnlineFriends()
	elseif GetNumFriends and GetFriendInfo then
		local total=GetNumFriends()
		local online=0
		for i=1,total do
			local _,_,_,_,connected=GetFriendInfo(i)
			if connected then
				online=online+1
			end
		end
		return online
	end
	return 0
end

function FG_GetFriendInfoByIndex(index)
	if C_FriendList and C_FriendList.GetFriendInfoByIndex then
		return C_FriendList.GetFriendInfoByIndex(index)
	elseif GetFriendInfo then
		-- Classic / MoP: GetFriendInfo(index) returns
		-- name, level, class, area, connected, status, note
		local name,level,class,area,connected,status,note=GetFriendInfo(index)
		return {
			name=name,
			level=level,
			className=class,
			area=area,
			connected=connected,
			notes=note,
			afk=status=="AFK",
			dnd=status=="DND",
			mobile=false,
			richPresence=nil,
		}
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
local function FG_BNGetNumFriends()
	if BNGetNumFriends then
		return BNGetNumFriends()
	end
	return 0
end

local function FG_BNGetFriendInfo(idx)
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

local function FG_BNGetGameAccountInfo(bnetAccountId)
	if BNGetGameAccountInfo then
		return BNGetGameAccountInfo(bnetAccountId)
	end
	return nil
end

-- BNet note setter using BN friend LIST INDEX
local function FG_SetBNetFriendNote(index,note)
	if not BNSetFriendNote then
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

	pcall(BNSetFriendNote,presenceID,note)
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
	for i=1,FriendButtons.count do
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
		isAFK,isGameAFK,isDND,isGameBusy,mobile,zoneName,gameText,realmName

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
			if BNGetFriendInfo then
				local ft={BNGetFriendInfo(id)}
				isAFK=ft[10] or false
				isDND=ft[11] or false
				local gameAcctId=ft[6]
				if gameAcctId and BNGetGameAccountInfo then
					local g={BNGetGameAccountInfo(gameAcctId)}
					isGameAFK=g[18] or false
					isGameBusy=g[19] or false
				end
			end
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
else
		local bnetIDAccount,accountName2,_,_,characterName2,bnetAccountId2,client2,
			isOnline2,lastOnline2,isAFK2,isDND2,_,_,_,_,wowProjectID2,_,_,isFavorite2,mobile2=
			FG_BNGetFriendInfo(id)

		accountName=accountName2
		bnetAccountId=bnetAccountId2
		characterName=characterName2
		client=client2
		isOnline=isOnline2
		lastOnline=lastOnline2
		isAFK=isAFK2
		isDND=isDND2
		wowProjectID=wowProjectID2
		isFavoriteFriend=isFavorite2
		mobile=mobile2

		if isOnline2 and bnetAccountId2 then
			local _,_,_,realmName2,_,_,_,class2,_,zoneName2,level2,
				gameText2,_,_,_,_,_,isGameAFK2,isGameBusy2,_,wowProjectID3,mobile3=
				FG_BNGetGameAccountInfo(bnetAccountId2)

			realmName=realmName2
			class=class2
			zoneName=zoneName2
			level=level2
			gameText=gameText2
			isGameAFK=isGameAFK2
			isGameBusy=isGameBusy2
			wowProjectID=wowProjectID3 or wowProjectID
			mobile=mobile3 or mobile
		end

		if CanCooperateWithGameAccount and bnetAccountId2 then
			canCoop=CanCooperateWithGameAccount(bnetAccountId2)
		else
			canCoop=nil
		end
	end

	if realmName and realmName~="" then
		if zoneName and zoneName~="" then
			zoneName=zoneName.." - "..realmName
		else
			zoneName=realmName
		end
	end

	return accountName,characterName,class,level,isFavoriteFriend,isOnline,
		bnetAccountId,client,canCoop,wowProjectID,lastOnline,
		isAFK,isGameAFK,isDND,isGameBusy,mobile,zoneName,gameText,realmName
end

-- [[ BNet button name text builder ]]

local function SocialPlus_GetBNetButtonNameText(accountName,client,canCoop,characterName,class,level,realmName)
	local nameText

	if accountName and accountName~="" then
		nameText=accountName
	else
		nameText=UNKNOWN
	end

	if characterName and characterName~="" then
		local coopLabel=""
		if not canCoop then
			coopLabel=CANNOT_COOPERATE_LABEL
		end

		local charLabel=characterName
		if realmName and realmName~="" then
			charLabel=charLabel.."-"..realmName
		end
		charLabel=charLabel..coopLabel

		if client==BNET_CLIENT_WOW then
			local nameColor=SocialPlus_SavedVars.colour_classes and ClassColourCode(class)
			if nameColor then
				nameText=nameText.." "..nameColor.."("..charLabel..")"..FONT_COLOR_CODE_CLOSE
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

						if client==BNET_CLIENT_WOW and wowProjectID==WOW_PROJECT_ID and hasRealm then
							if friendFaction=="Horde" then
								iconPath="Interface\\FriendsFrame\\plusmanz-horde"
							elseif friendFaction=="Alliance" then
								iconPath="Interface\\FriendsFrame\\plusmanz-alliance"
							end
							if not iconPath and FACTION_ICON_PATH then
								iconPath=FACTION_ICON_PATH
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

local function SocialPlus_IsFavorite(buttonType,id)
	local key=SocialPlus_GetFavoriteKey(buttonType,id)
	return key and SocialPlus_SavedVars and SocialPlus_SavedVars.favorites and SocialPlus_SavedVars.favorites[key]==true
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

-- [[ Core per-row button update ]]
local function SocialPlus_UpdateFriendButton(button)
	local index=button.index
	button.buttonType=FriendButtons[index].buttonType
	button.id=FriendButtons[index].id
	local height=FRIENDS_BUTTON_HEIGHTS[button.buttonType]
	local nameText,nameColor,infoText,isFavoriteFriend
	local hasTravelPassButton=false
    local searchBlob="" -- text we will search in for this row

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
	button.SocialPlusGroupName=nil -- only used on divider (group header) rows

	if button.SocialPlusGroupGearButton then
		button.SocialPlusGroupGearButton:Hide()
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

			nameText=info.name..", "..format(FRIENDS_LEVEL_TEMPLATE,info.level,info.className)

			local wowAllowed,wowReason=SocialPlus_GetInviteStatus("WOW",FriendButtons[index].id)

			if FACTION_ICON_PATH then
				FG_ApplyGameIcon(button,FACTION_ICON_PATH,30,"RIGHT","RIGHT",-22,0)
				button.SocialPlusIconAlpha=wowAllowed and 1 or 0.4
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

		-- Build a searchable blob for this row
		searchBlob=table.concat({
			info and info.name or "",
			info and info.area or "",
			tostring(nameText or ""),
			tostring(infoText or "")
		}," ")

		-- Store raw identifiers for whisper/invite
		if info then
			button.rawName=info.name
			button.characterName=info.name
			button.realmName=nil
		end
		button.accountName=nil

	elseif button.buttonType==FRIENDS_BUTTON_TYPE_BNET then
		local id=FriendButtons[index].id
		local accountName,characterName,class,level,isFavorite,
			isOnline,bnetAccountId,client,canCoop,wowProjectID,lastOnline,
			isAFK,isGameAFK,isDND,isGameBusy,mobile,zoneName,gameText,realmName=
			GetFriendInfoById(id)

		nameText=SocialPlus_GetBNetButtonNameText(accountName,client,canCoop,characterName,class,level,realmName)

		button.accountName=accountName
		button.characterName=characterName
		button.realmName=realmName
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

			-- Build a searchable blob for this BNet row
     	  	searchBlob=table.concat({
			accountName or "",
			characterName or "",
			realmName or "",
			zoneName or "",
			gameText or "",
			tostring(nameText or ""),
			tostring(infoText or "")
    		}," ")

			if client==BNET_CLIENT_WOW and wowProjectID==WOW_PROJECT_ID then
				if not zoneName or zoneName=="" then
					infoText=UNKNOWN
				else
					infoText=mobile and LOCATION_MOBILE_APP or zoneName
				end
			else
				infoText=gameText
			end

        local iconPath
        local acct,ga
        if C_BattleNet and C_BattleNet.GetFriendAccountInfo then
            acct=C_BattleNet.GetFriendAccountInfo(id)
            ga=acct and acct.gameAccountInfo or nil
        end

        local hasRealm=(realmName and realmName~="")
            or (ga and ga.realmName and ga.realmName~="")

        -- Friend’s faction (if applicable)
        local friendFaction
        if ga and ga.factionName then
            friendFaction=ga.factionName  -- "Alliance" or "Horde"
        end

        -- If same-project WoW with a real realm, prefer a faction crest
        if client==BNET_CLIENT_WOW and wowProjectID==WOW_PROJECT_ID and hasRealm then
            if friendFaction=="Horde" then
                iconPath="Interface\\FriendsFrame\\plusmanz-horde"
            elseif friendFaction=="Alliance" then
                iconPath="Interface\\FriendsFrame\\plusmanz-alliance"
            end
            if not iconPath and FACTION_ICON_PATH then
                iconPath=FACTION_ICON_PATH
            end
        end

        -- Fallback: generic client logo
        if not iconPath then
            iconPath=FG_GetClientTextureSafe(client)
        end

        -- Crest vs game logo?
        local isCrest=false
        if iconPath==FACTION_ICON_PATH then
            isCrest=true
        elseif type(iconPath)=="string" and iconPath:find("UI%-PVP%-") then
            isCrest=true
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

        -- Icon fading: ONLY un-inviteable WoW/faction icons fade
        -- (Never fade non-WoW client icons.)
        local fadeWowIcon=(client==BNET_CLIENT_WOW and not allowed)
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
		title=SocialPlus_GetFavoritesLabel()
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

		if SocialPlus_SavedVars.collapsed[group] then
			button.status:SetTexture("Interface\\Buttons\\UI-PlusButton-UP")
		else
			button.status:SetTexture("Interface\\Buttons\\UI-MinusButton-UP")
		end
		-- Re-anchor to the row's own vertical center (mirrors the gear
		-- button's "RIGHT" anchor on the other side) so it lines up on the
		-- same axis instead of wherever Blizzard's template placed it.
		button.status:ClearAllPoints()
		button.status:SetPoint("LEFT",button,"LEFT",4,0)

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
	if button.SocialPlusGroupGearButton then
		button.SocialPlusGroupGearButton:Show()
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
		local invite=scrollFrame.invitePool:Acquire()
		invite:SetParent(scrollFrame.ScrollChild)
		invite:SetAllPoints(button)
		invite:Show()
		local inviteID,inviteAccountName=FG_BNGetFriendInviteInfo(button.id)
		invite.Name:SetText(inviteAccountName)
		invite.inviteID=inviteID
		invite.inviteIndex=button.id
		nameText=nil
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

    -- Show/hide travel pass button
    if hasTravelPassButton then
        button.travelPassButton:Show()
    else
        button.travelPassButton:Hide()
    end

    if FriendsFrame.selectedFriendType==FriendButtons[index].buttonType
        and FriendsFrame.selectedFriend==FriendButtons[index].id then
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
			-- Favorite star stays on the left, in front of the name. The
			-- note icon is a test placement on the right, after the name.
			local prefix=""
			local suffix=""

			if SocialPlus_IsFavorite(button.buttonType,button.id) then
				prefix=prefix.."|TInterface\\Common\\FavoritesIcon:26:26:0:-3|t"
			end

			-- Small note icon so a friend with an actual note stands out at
			-- a glance, matching Retail. "Has a note" means real free text,
			-- not just the group tags SocialPlus stores in the same note
			-- field ("Sacha#Friends") -- strip everything from the first
			-- "#" onward (NoteAndGroups does the same split, but isn't in
			-- scope yet at this point in the file) before checking.
			local rawNote
			if button.buttonType==FRIENDS_BUTTON_TYPE_BNET then
				rawNote=select(13,FG_BNGetFriendInfo(button.id))
			else
				local info=FG_GetFriendInfoByIndex(button.id)
				rawNote=info and info.notes
			end
			local baseNote=rawNote and strtrim(rawNote:match("^([^#]*)") or "")
			if baseNote and baseNote~="" then
				suffix=suffix.." |TInterface\\Icons\\INV_Misc_Note_06:14:14:0:0|t"
			end

			nameText=prefix..nameText..suffix
		end
		button.name:SetText(nameText)
		button.name:SetTextColor(nameColor.r,nameColor.g,nameColor.b)
		button.info:SetText(infoText)
		button:Show()
		if isFavoriteFriend and button.Favorite then
			button.Favorite:Show()
			button.Favorite:ClearAllPoints()
			button.Favorite:SetPoint("TOPLEFT",button.name,"TOPLEFT",button.name:GetStringWidth(),0)
		elseif button.Favorite then
			button.Favorite:Hide()
		end
	else
		button:Hide()
	end

	-- Tooltip handling	
	if FriendsTooltip.button==button then
		if FriendsFrameTooltip_Show then
			FriendsFrameTooltip_Show(button)
		elseif button.OnEnter then
			button:OnEnter()
		end
	end

	return height
end

-- [[ Full friends list rebuild ]]
local function SocialPlus_UpdateFriends()
	local scrollFrame=FriendsScrollFrame
	local offset=HybridScrollFrame_GetOffset(scrollFrame)
	local buttons=scrollFrame.buttons
	local numButtons=#buttons
	local numFriendButtons=FriendButtons.count or 0
	local usedHeight=0

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
	scrollFrame.invitePool:ReleaseAll()
	scrollFrame.PendingInvitesHeaderButton:Hide()

	for i=1,numButtons do
		local button=buttons[i]
		local index=offset+i
		if index<=numFriendButtons then
			button.index=index
			local height=SocialPlus_UpdateFriendButton(button)
			button:SetHeight(height)
			usedHeight=usedHeight+height
		else
			button.index=nil
			button:Hide()
		end
	end

	if HybridScrollFrame_Update then
		pcall(HybridScrollFrame_Update,scrollFrame,scrollFrame.totalFriendListEntriesHeight,usedHeight)
	end

	-- Confirmed live: on this client, whatever HybridScrollFrame_Update does
	-- above never produces a usable scrollbar range -- GetMinMaxValues()
	-- comes back (0,-1) regardless of actual content height, which makes
	-- SocialPlus_InitSmoothScroll's OnMouseWheel handler clamp every scroll
	-- attempt to 0 (math.min(-1,target) is always -1, math.max(0,-1) is
	-- always 0), i.e. dead scrolling. Don't depend on Blizzard's call at
	-- all -- set the real range ourselves from our own known-accurate
	-- content height and the frame's actual visible height.
	if scrollFrame.scrollBar then
		local totalHeight=scrollFrame.totalFriendListEntriesHeight or 0
		local frameHeight=scrollFrame:GetHeight() or 0
		local scrollRange=math.max(totalHeight-frameHeight,0)
		local curValue=scrollFrame.scrollBar:GetValue() or 0
		scrollFrame.scrollBar:SetMinMaxValues(0,scrollRange)
		scrollFrame.scrollBar:SetValue(math.min(curValue,scrollRange))
		if scrollRange<=0 then
			scrollFrame.scrollBar:Hide()
		else
			scrollFrame.scrollBar:Show()
		end
	end

	-- Keep global collapse/expand button state in sync
	SocialPlus_UpdateCollapseAllButtonVisual()

	-- Clean up collapsed groups that no longer exist	
	for key,_ in pairs(SocialPlus_SavedVars.collapsed) do
		if not GroupTotal[key] then
			SocialPlus_SavedVars.collapsed[key]=nil
		end
	end
end

-- [[ Group tag helpers ]]
local function FillGroups(groups,note,...)
	wipe(groups)
	local n=select('#',...)
	local added=false
	for i=1,n do
		local v=select(i,...)
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

	local numBNetTotal,numBNetOnline=FG_BNGetNumFriends()
	numBNetTotal=numBNetTotal or 0
	numBNetOnline=numBNetOnline or 0
	local numWoWTotal=FG_GetNumFriends()
	local numWoWOnline=FG_GetNumOnlineFriends()
	local numWoWOffline=numWoWTotal-numWoWOnline

	if QuickJoinToastButton then
		QuickJoinToastButton:UpdateDisplayedFriendCount()
	end

	-- AddButtonInfo shared by both search and normal mode
	local addButtonIndex=0
	local totalButtonHeight=0
	local function AddButtonInfo(buttonType,id)
		addButtonIndex=addButtonIndex+1
		if not FriendButtons[addButtonIndex] then
			FriendButtons[addButtonIndex]={}
		end
		FriendButtons[addButtonIndex].buttonType=buttonType
		FriendButtons[addButtonIndex].id=id
		FriendButtons.count=addButtonIndex
		totalButtonHeight=totalButtonHeight+FRIENDS_BUTTON_HEIGHTS[buttonType]
	end

	-- >>> SIMPLE NAME-ONLY SEARCH MODE (no groups) <<<
	if SocialPlus_SearchTerm then
		wipe(FriendButtons)
		wipe(GroupTotal)
		wipe(GroupOnline)
		GroupCount=0
		addButtonIndex=0
		totalButtonHeight=0

		local term=SocialPlus_SearchTerm

		-- BNet friends: try BattleTag first, then accountName, then character name
		for i=1,numBNetTotal do
			local accountName,characterName,class,_,_,isOnline,_,_,_,wowProjectID=
				GetFriendInfoById(i)

			if not(SocialPlus_SavedVars and SocialPlus_SavedVars.hide_offline and not isOnline) then
				local battleTag=nil

				-- Try to grab the real BattleTag from C_BattleNet if it exists
				if C_BattleNet and C_BattleNet.GetFriendAccountInfo then
					local acct=C_BattleNet.GetFriendAccountInfo(i)
					if acct then
						battleTag=acct.battleTag or acct.accountName
					end
				end

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
				local classMatches=isOnline and wowProjectID==WOW_PROJECT_ID and containsPlain(classNormalized,term)

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

			if SocialPlus_SavedVars and SocialPlus_SavedVars.hide_offline and not connected then
				-- skip offline if setting says so
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
			if not SocialPlus_SavedVars.collapsed[FriendRequestString] then
				buttonCount=buttonCount+1
				AddButtonInfo(FRIENDS_BUTTON_TYPE_INVITE,i)
			end
		end
	end

	-- BNet friends (all)
	for i=1,numBNetTotal do
		if not BnetSocialPlus[i] then
			BnetSocialPlus[i]={}
		end

		local t={FG_BNGetFriendInfo(i)}
		local isOnline=t[8] and true or false
		local noteText=t[13]

		BNetOnlineStatus[i]=isOnline
		-- Note/group membership is parsed and kept as-is regardless of
		-- favorite status -- favoriting only changes where the friend
		-- renders below, never their stored group assignment.
		NoteAndGroups(noteText,BnetSocialPlus[i])

		-- A favorited friend renders ONLY under the virtual Favorites
		-- group, not also under their real group(s) -- move semantics,
		-- not a copy.
		if SocialPlus_IsFavorite(FRIENDS_BUTTON_TYPE_BNET,i) then
			IncrementGroup(SP_FAVORITES_GROUP,isOnline)
			if not SocialPlus_SavedVars.collapsed[SP_FAVORITES_GROUP] then
				if isOnline or not(SocialPlus_SavedVars.hide_offline) then
					buttonCount=buttonCount+1
					AddButtonInfo(FRIENDS_BUTTON_TYPE_BNET,i)
				end
			end
		else
			for group in pairs(BnetSocialPlus[i]) do
				IncrementGroup(group,isOnline)
				if not SocialPlus_SavedVars.collapsed[group] then
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
		if not WowSocialPlus[i] then
			WowSocialPlus[i]={}
		end
		local fi=FG_GetFriendInfoByIndex(i)
		local note=fi and fi.notes
		NoteAndGroups(note,WowSocialPlus[i])
		if SocialPlus_IsFavorite(FRIENDS_BUTTON_TYPE_WOW,i) then
			IncrementGroup(SP_FAVORITES_GROUP,true)
			if not SocialPlus_SavedVars.collapsed[SP_FAVORITES_GROUP] then
				buttonCount=buttonCount+1
				AddButtonInfo(FRIENDS_BUTTON_TYPE_WOW,i)
			end
		else
			for group in pairs(WowSocialPlus[i]) do
				IncrementGroup(group,true)
				if not SocialPlus_SavedVars.collapsed[group] then
					buttonCount=buttonCount+1
					AddButtonInfo(FRIENDS_BUTTON_TYPE_WOW,i)
				end
			end
		end
	end

	-- WoW friends offline
	for i=1,numWoWOffline do
		local j=i+numWoWOnline
		if not WowSocialPlus[j] then
			WowSocialPlus[j]={}
		end
		local fj=FG_GetFriendInfoByIndex(j)
		local note=fj and fj.notes
		NoteAndGroups(note,WowSocialPlus[j])
		if SocialPlus_IsFavorite(FRIENDS_BUTTON_TYPE_WOW,j) then
			IncrementGroup(SP_FAVORITES_GROUP)
			if not SocialPlus_SavedVars.collapsed[SP_FAVORITES_GROUP] and not SocialPlus_SavedVars.hide_offline then
				buttonCount=buttonCount+1
				AddButtonInfo(FRIENDS_BUTTON_TYPE_WOW,j)
			end
		else
			for group in pairs(WowSocialPlus[j]) do
				IncrementGroup(group)
				if not SocialPlus_SavedVars.collapsed[group] and not SocialPlus_SavedVars.hide_offline then
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

SocialPlus_ApplyGroupOrder()

    local index=0
    for _,group in ipairs(GroupSorted) do
        index=index+1
        FriendButtons[index].buttonType=FRIENDS_BUTTON_TYPE_DIVIDER
        FriendButtons[index].text=group

        if not SocialPlus_SavedVars.collapsed[group] then
            -- 1) Friend invites bucket (always same behavior)
            if group==FriendRequestString then
                for i=1,#FriendReqGroup do
                    index=index+1
                    FriendButtons[index].buttonType=FRIENDS_BUTTON_TYPE_INVITE
                    FriendButtons[index].id=i
                end
            end

            ----------------------------------------------------------------
            -- Base order, always applied: status (online > DND > away),
            -- then same game/client clustered together (app-idle last),
            -- then alphabetical within each cluster.
            --
            -- "Prioritize <version> friends" adds one thing on top: friends
            -- on this exact WoW version bubble to the very top, ordered by
            -- status, then same faction first, then alphabetical. Everyone
            -- else still follows the base order below them.
            ----------------------------------------------------------------
            local usePrioritize=SocialPlus_SavedVars and SocialPlus_SavedVars.prioritize_current_client
            if usePrioritize and not playerFaction then FG_InitFactionIcon() end

            local onlineRows={}

            -- BNet online
            for i=1,numBNetTotal do
                -- Membership for the virtual Favorites group comes from the
                -- favorite flag, not the friend's real note tags (which
                -- BnetSocialPlus[i] reflects and is left untouched by
                -- favoriting) -- this is what actually implements "move,
                -- don't copy" at render time.
                local isMember
                if group==SP_FAVORITES_GROUP then
                    isMember=BNetOnlineStatus[i] and SocialPlus_IsFavorite(FRIENDS_BUTTON_TYPE_BNET,i)
                else
                    -- A favorited friend must never also render under their
                    -- real group -- BnetSocialPlus[i] still reflects their
                    -- true note tags (favoriting doesn't touch them), so
                    -- without this exclusion they'd render twice, mismatching
                    -- the row count already pre-sized in the first pass
                    -- (which does correctly skip them here) and crashing
                    -- with an out-of-range FriendButtons index (confirmed
                    -- live).
                    isMember=BnetSocialPlus[i] and BnetSocialPlus[i][group] and BNetOnlineStatus[i]
                        and not SocialPlus_IsFavorite(FRIENDS_BUTTON_TYPE_BNET,i)
                end
                if isMember then
                    local row={buttonType=FRIENDS_BUTTON_TYPE_BNET,id=i}

                    -- Use GetFriendInfoById (the C_BattleNet-based path),
                    -- not the raw BNGetFriendInfo tuple, for client/status --
                    -- the raw tuple's field positions have already proven
                    -- unreliable on this client family for other fields
                    -- (wowProjectID at position 16), and confirmed live here
                    -- too: using its isAFK/isDND/client positions produced a
                    -- scrambled order (away friends above online, no real
                    -- alphabetical order). This is the same path already
                    -- used, and proven correct, for the status icon and
                    -- invite checks elsewhere in the addon.
                    local _,_,_,_,_,_,_,client,_,wowProjectID,_,
                        isAFK,isGameAFK,isDND,isGameBusy=GetFriendInfoById(i)
                    -- accountName from GetFriendInfoById/C_BattleNet can
                    -- transiently be a masked placeholder token (WoW's
                    -- "|K...|k" escape, silently rendered as the real name
                    -- by the chat frame but not by plain string comparison)
                    -- before the friend's name has finished resolving --
                    -- confirmed live: sorted "|Kj13|k" vs "|Kj53|k" instead
                    -- of the actual names. The raw BNGetFriendInfo tuple's
                    -- accountName (position 2) has been plain text in every
                    -- test so far, so use that for the sort key instead.
                    row.sortKey=select(2,FG_BNGetFriendInfo(i))
                    row.statusRank=SocialPlus_GetStatusRank(isAFK,isGameAFK,isDND,isGameBusy)
                    row.promoted=false
                    row.factionRank=1

                    -- Idling in the Battle.net app isn't reported as a nil
                    -- client, and isn't even always the same code -- confirmed
                    -- live two different app-idle friends read "App" and
                    -- "BSAp" respectively. Treat any client that isn't a real
                    -- game (checked below) and isn't the same as an already-
                    -- known game code as app-idle instead of hardcoding a
                    -- single expected string.
                    local isKnownAppCode=(not client) or client==(BNET_CLIENT_APP or "App") or client=="BSAp"
                    if client==BNET_CLIENT_WOW then
                        row.groupKey="WoW:"..tostring(wowProjectID or "?")
                        row.appOnlyRank=0
                        if usePrioritize and wowProjectID==WOW_PROJECT_ID then
                            row.promoted=true
                            local acct=C_BattleNet and C_BattleNet.GetFriendAccountInfo and C_BattleNet.GetFriendAccountInfo(i)
                            local ga=acct and acct.gameAccountInfo
                            local friendFaction=ga and ga.factionName
                            row.factionRank=(friendFaction and playerFaction and friendFaction==playerFaction) and 0 or 1
                        end
                    elseif isKnownAppCode then
                        row.groupKey="AppOnly"
                        row.appOnlyRank=1
                    else
                        row.groupKey="Client:"..client
                        row.appOnlyRank=0
                    end

                    if SocialPlus_RowDebug then
                        print(string.format(
                            "|cff33ff99[ROWDEBUG]|r group=%q sortKey=%q promoted=%s statusRank=%s appOnlyRank=%s groupKey=%q factionRank=%s id=%s",
                            tostring(group),tostring(row.sortKey),tostring(row.promoted),
                            tostring(row.statusRank),tostring(row.appOnlyRank),tostring(row.groupKey),
                            tostring(row.factionRank),tostring(row.id)
                        ))
                    end

                    onlineRows[#onlineRows+1]=row
                end
            end

            -- WoW online (native friend, always this exact WoW version)
            for i=1,numWoWOnline do
                local isWowMember
                if group==SP_FAVORITES_GROUP then
                    isWowMember=SocialPlus_IsFavorite(FRIENDS_BUTTON_TYPE_WOW,i)
                else
                    isWowMember=WowSocialPlus[i] and WowSocialPlus[i][group]
                        and not SocialPlus_IsFavorite(FRIENDS_BUTTON_TYPE_WOW,i)
                end
                if isWowMember then
                    local row={buttonType=FRIENDS_BUTTON_TYPE_WOW,id=i}
                    local info=FG_GetFriendInfoByIndex(i)
                    row.sortKey=info and info.name
                    row.statusRank=SocialPlus_GetStatusRank(info and info.afk,false,info and info.dnd,false)
                    row.groupKey="WoW:"..tostring(WOW_PROJECT_ID or "?")
                    row.appOnlyRank=0
                    row.promoted=usePrioritize and true or false
                    row.factionRank=0
                    onlineRows[#onlineRows+1]=row
                end
            end

            table.sort(onlineRows,function(a,b)
                -- Favorites is now its own dedicated group (rendered
                -- separately above, never mixed with non-favorites in the
                -- same onlineRows set), so it uses the exact same rule as
                -- any other group: status -> game cluster -> alphabetical,
                -- with the "Prioritize" promoted block on top when enabled.
                if a.promoted~=b.promoted then return a.promoted end
                if a.statusRank~=b.statusRank then return a.statusRank<b.statusRank end
                if a.promoted and a.factionRank~=b.factionRank then return a.factionRank<b.factionRank end
                if a.appOnlyRank~=b.appOnlyRank then return a.appOnlyRank<b.appOnlyRank end
                if a.groupKey~=b.groupKey then return a.groupKey<b.groupKey end
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
                FriendButtons[index].buttonType=row.buttonType
                FriendButtons[index].id=row.id
            end

            -- Offline at the bottom, unaffected by any of the above
            if not SocialPlus_SavedVars.hide_offline then
                -- BNet offline
                for i=1,numBNetTotal do
                    local isOfflineMember
                    if group==SP_FAVORITES_GROUP then
                        isOfflineMember=BNetOnlineStatus[i]==false and SocialPlus_IsFavorite(FRIENDS_BUTTON_TYPE_BNET,i)
                    else
                        isOfflineMember=BnetSocialPlus[i] and BnetSocialPlus[i][group] and BNetOnlineStatus[i]==false
                            and not SocialPlus_IsFavorite(FRIENDS_BUTTON_TYPE_BNET,i)
                    end
                    if isOfflineMember then
                        index=index+1
                        FriendButtons[index].buttonType=FRIENDS_BUTTON_TYPE_BNET
                        FriendButtons[index].id=i
                    end
                end

                -- WoW offline
                for i=numWoWOnline+1,numWoWTotal do
                    local isWowOfflineMember
                    if group==SP_FAVORITES_GROUP then
                        isWowOfflineMember=SocialPlus_IsFavorite(FRIENDS_BUTTON_TYPE_WOW,i)
                    else
                        isWowOfflineMember=WowSocialPlus[i] and WowSocialPlus[i][group]
                            and not SocialPlus_IsFavorite(FRIENDS_BUTTON_TYPE_WOW,i)
                    end
                    if isWowOfflineMember then
                        index=index+1
                        FriendButtons[index].buttonType=FRIENDS_BUTTON_TYPE_WOW
                        FriendButtons[index].id=i
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

	local selectedFriend=0
	if numBNetTotal+numWoWTotal>0 then
		if FriendsFrame.selectedFriendType==FRIENDS_BUTTON_TYPE_WOW then
			selectedFriend=FG_GetSelectedFriend()
		elseif FriendsFrame.selectedFriendType==FRIENDS_BUTTON_TYPE_BNET then
			selectedFriend=FG_BNGetSelectedFriend()
		end
		if not selectedFriend or selectedFriend==0 then
			FriendsFrame_SelectFriend(FriendButtons[1].buttonType,1)
			selectedFriend=1
		end
		FriendsFrameSendMessageButton:SetEnabled(FriendsList_CanWhisperFriend(FriendsFrame.selectedFriendType,selectedFriend))
	else
		FriendsFrameSendMessageButton:Disable()
	end
	FriendsFrame.selectedFriend=selectedFriend

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

	for i=1,FG_BNGetNumFriends() do
		local presenceID,_,_,_,_,_,_,_,_,_,_,_,noteText=FG_BNGetFriendInfo(i)
		local note=NoteAndGroups(noteText,groups)
		if groups[old] then
			groups[old]=nil
			groups[input]=true
			note=CreateNote(note,groups)
			FG_SetBNetFriendNote(i,note)
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
end

local function SocialPlus_Create(self,data)
	local eb=self.editBox or self.EditBox
	if not eb then return end

	local input=eb:GetText()
	if input=="" then
		return
	end

	-- Apply group change
	local note=AddGroup(data.note,input)
	data.set(data.id,note)

	-- Clear search so full list comes back
	if SocialPlus_ClearSearch then
		SocialPlus_ClearSearch()
	end

	-- Rebuild list
	pcall(SocialPlus_Update)

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
			local newBase=eb:GetText()
			local finalNote=newBase
			if data.groups then
				data.groups[""]=nil
				finalNote=CreateNote(newBase,data.groups)
			end
			pcall(data.set,data.id,finalNote)
			pcall(SocialPlus_Update)
		end
	end,
	timeout=0,
	whileDead=1,
	hideOnEscape=1
}

-- [[ Character-name helper for menu actions ]]

local function SocialPlus_GetFullCharacterName(cf)
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

local function SocialPlus_GetMenuTitle()
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

local function SocialPlus_AddSeparator(level)
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
	if not clickedgroup or clickedgroup=="" then
		return
	end

	-- Favorites membership comes from the favorite flag, not note tags --
	-- same reasoning as the row-building membership checks. "Remove" is
	-- excluded from the menu for Favorites entirely, so the delete path
	-- below never actually runs for it, but is guarded anyway for safety.
	local isFavorites=(clickedgroup==SP_FAVORITES_GROUP)
	local groups={}

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

	-- Deleting a group also clears any mute setting for it
	if not invite and not isFavorites and SocialPlus_SavedVars and SocialPlus_SavedVars.notifications then
		SocialPlus_SavedVars.notifications.mutedGroups[clickedgroup]=nil
	end
end

-- [[ Group context menu (right-click group header) ]]

local SocialPlus_Menu=LibDD:Create_UIDropDownMenu("SocialPlus_Menu",UIParent)
SocialPlus_Menu.displayMode="MENU"

local menu_items={
	[1]={
		{text="",notCheckable=true,isTitle=true},
		{text=L.GROUP_INVITE_ALL,notCheckable=true,func=function(self,menu,clickedgroup) InviteOrGroup(clickedgroup,true) end},
		{text=L.GROUP_RENAME,notCheckable=true,func=function(self,menu,clickedgroup) StaticPopup_Show("SocialPlus_RENAME",nil,nil,clickedgroup) end},
		{text=L.GROUP_REMOVE,notCheckable=true,func=function(self,menu,clickedgroup) InviteOrGroup(clickedgroup,false) end},
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
		-- Favorites isn't a real, user-managed group -- Rename and Delete
		-- are excluded from the menu entirely (not just disabled), per spec.
		if not (level==1 and isFavorites and (items.text==L.GROUP_RENAME or items.text==L.GROUP_REMOVE)) then
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
			info.keepShownOnClick=true
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

		LibDD:UIDropDownMenu_AddButton(info,level)
		end
	end
end


-- [[ Preferences Panel (left-side) ]]
function SocialPlus_CreateSettingsButton()
	if SocialPlus_SettingsButton or not FriendsFrame then return end

	-- Confirmed live via /fstack: FriendsFrameBattlenetFrame.BroadcastButton
	-- is the chat-bubble icon at the right end of the blue BattleTag bar.
	-- Parented to the bar itself (not FriendsFrame) so it's positioned
	-- and layered correctly relative to it -- frame level +2 so it draws
	-- above the bar's own texture.
	local barParent=FriendsFrameBattlenetFrame or FriendsFrame
	local btn=CreateFrame("Button","SocialPlus_SettingsButton",barParent)
	btn:SetSize(18,18)
	btn:SetFrameLevel(barParent:GetFrameLevel()+2)
	if FriendsFrameBattlenetFrame and FriendsFrameBattlenetFrame.BroadcastButton then
		btn:SetPoint("RIGHT",FriendsFrameBattlenetFrame.BroadcastButton,"LEFT",-5,0)
	elseif FriendsFrameBattlenetFrame then
		btn:SetPoint("RIGHT",FriendsFrameBattlenetFrame,"RIGHT",-4,0)
	else
		btn:SetPoint("TOPRIGHT",FriendsFrame,"TOPRIGHT",-8,-48)
	end

	-- Backplate (Blizzard-style frame)
	local back=btn:CreateTexture(nil,"BACKGROUND")
	back:SetTexture("Interface\\Buttons\\UI-Quickslot2")
	back:SetTexCoord(0.1,0.9,0.1,0.9)
	back:SetSize(30,30)
	back:SetPoint("CENTER",btn,"CENTER",0,0)
	back:SetVertexColor(0.55,0.55,0.55) -- idle: dim so hover can pop

	-- Inner dark fill behind the cog (removes empty look)
	local fill = btn:CreateTexture(nil, "BACKGROUND", nil, 1)
	fill:SetColorTexture(0,0,0,0.75) -- soft dark fill
	fill:SetPoint("CENTER", btn, "CENTER", 0, 0)
	fill:SetSize(20,20) -- slightly smaller than the 30x30 outer frame

	-- Cogwheel normal/pushed
	btn:SetNormalTexture("Interface\\Buttons\\UI-OptionsButton")
	btn:SetPushedTexture("Interface\\Buttons\\UI-OptionsButton")

	local normal=btn:GetNormalTexture()
	local pushed=btn:GetPushedTexture()

	if normal then
		normal:ClearAllPoints()
		normal:SetPoint("CENTER",btn,"CENTER",0,0)
		normal:SetSize(15,15)
		normal:SetTexCoord(0,1,0,1)
		normal:SetVertexColor(0.9,0.9,0.9) -- idle: slightly dim
	end

	if pushed then
		pushed:ClearAllPoints()
		pushed:SetPoint("CENTER",btn,"CENTER",-1,-1) -- pressed offset
		pushed:SetSize(15,15)
		pushed:SetTexCoord(0,1,0,1)
		pushed:SetVertexColor(0.6,0.6,0.6) -- clearly darker on press
	end

	-- Hover: light up frame + cog
	btn:HookScript("OnEnter",function()
		back:SetVertexColor(1.5,1.5,1.5)   -- strong highlight
		if normal then normal:SetVertexColor(1,1,1) end
	end)

	btn:HookScript("OnLeave",function()
		back:SetVertexColor(0.55,0.55,0.55) -- back to dim frame
		if normal then normal:SetVertexColor(0.9,0.9,0.9) end
	end)

	btn:SetScript("OnClick",function()
		if SocialPlus_SettingsPanel then
			local opening=not SocialPlus_SettingsPanel:IsShown()
			SocialPlus_SettingsPanel:SetShown(opening)
			if opening then
				SocialPlus_PlayMenuClickSound()
			else
				SocialPlus_PlayMenuCloseSound()
			end
		else
			SocialPlus_PlayMenuClickSound()
		end
	end)

	SocialPlus_SettingsButton=btn
end

-- Short label for a friend's WoW version (e.g. "Retail", "TBC"), always shown
-- (including same-version friends, e.g. "MoP" for another MoP Classic friend).
-- Sentinel fallbacks (-1, -2, ...) on each WOW_PROJECT_* global keep this safe
-- on clients where a given constant doesn't exist, rather than colliding with
-- a real project ID. Declared up here (rather than closer to the notification
-- code that also uses it) so SocialPlus_CreateSettingsPanel below can use it
-- too -- Lua locals are only visible after their declaration in the file.
local function SocialPlus_GetVersionLabelText(wowProjectID)
	local labels={
		[WOW_PROJECT_MAINLINE or -1]=L.WOW_VERSION_RETAIL,
		[WOW_PROJECT_CLASSIC or -2]=L.WOW_VERSION_CLASSIC_ERA,
		[WOW_PROJECT_BURNING_CRUSADE_CLASSIC or -3]=L.WOW_VERSION_TBC,
		[WOW_PROJECT_WRATH_CLASSIC or -4]=L.WOW_VERSION_WOTLK,
		[WOW_PROJECT_CATACLYSM_CLASSIC or -5]=L.WOW_VERSION_CATA,
		[WOW_PROJECT_MISTS_CLASSIC or -6]=L.WOW_VERSION_MOP,
	}
	return (wowProjectID and labels[wowProjectID]) or "?"
end

function SocialPlus_CreateSettingsPanel()
	if SocialPlus_SettingsPanel or not FriendsFrame then return end

	-- Parented to UIParent, not FriendsFrame: WoW frame alpha is
	-- multiplicative down the parent chain, and FriendsFrame's own backdrop
	-- isn't fully opaque -- being its child meant inheriting that
	-- translucency no matter what our own backdrop alpha was set to
	-- (confirmed live: the group-header dropdown, parented to UIParent,
	-- looked solid while this panel didn't, despite identical backdrop
	-- settings). Positioning still anchors relative to FriendsFrame below;
	-- SetPoint works across unrelated frames. The auto-hide-with-Friends-
	-- List behavior doesn't rely on parentage either -- see the explicit
	-- FriendsFrame:HookScript("OnHide", ...) further down.
	local f=CreateFrame("Frame","SocialPlus_SettingsPanel",UIParent,"BackdropTemplate")
	-- Slightly larger box to fit icon preset controls
	f:SetSize(350,354)

	-- Right side of Friends frame
	f:SetPoint("TOPLEFT",FriendsFrame,"TOPRIGHT",8,-24)

	-- Same backdrop shape LibUIDropDownMenu uses for its "MENU" display
	-- mode (see Libs\LibUIDropDownMenu\LibUIDropDownMenu.lua's
	-- BACKDROP_TOOLTIP_16_16_5555) -- matching the group-header cogwheel
	-- menu's appearance exactly, since that's the reference look requested.
	f:SetBackdrop({
		bgFile="Interface\\Tooltips\\UI-Tooltip-Background",
		edgeFile="Interface\\Tooltips\\UI-Tooltip-Border",
		tile=true,tileEdge=true,tileSize=16,edgeSize=16,
		insets={left=5,right=5,top=5,bottom=5}
	})

	-- Blizzard's own tooltip colors, set with no alpha argument (defaults
	-- to fully opaque) -- exactly how LibUIDropDownMenu colors its "MENU"
	-- backdrop, which is what looked solid/non-transparent by comparison.
	f:SetBackdropColor(TOOLTIP_DEFAULT_BACKGROUND_COLOR.r,TOOLTIP_DEFAULT_BACKGROUND_COLOR.g,TOOLTIP_DEFAULT_BACKGROUND_COLOR.b)
	f:SetBackdropBorderColor(TOOLTIP_DEFAULT_COLOR.r,TOOLTIP_DEFAULT_COLOR.g,TOOLTIP_DEFAULT_COLOR.b)

	f:EnableMouse(true)
	f:SetToplevel(true)
	-- Match LibUIDropDownMenu's dropdown list frames, which sit at DIALOG
	-- strata -- not just SetToplevel, which only reorders within a strata,
	-- so this also fixes HUD unit frames (target/focus) bleeding through.
	f:SetFrameStrata("DIALOG")

	-- Escape closes just this panel, not the whole Friends panel behind it
	-- -- same EnableKeyboard(true) + SetPropagateKeyboardInput(true) pattern
	-- used for the click-catcher's menu-Escape handling and the drag
	-- ghost's cancel-drag handling elsewhere in this file.
	f:EnableKeyboard(true)
	f:SetPropagateKeyboardInput(true)
	f:SetScript("OnKeyDown",function(self,key)
		if key=="ESCAPE" then
			self:SetPropagateKeyboardInput(false)
			self:Hide()
		else
			self:SetPropagateKeyboardInput(true)
		end
	end)

	-- Title
	f.title=f:CreateFontString(nil,"OVERLAY","GameFontHighlightLarge")
	f.title:SetPoint("TOPLEFT",f,"TOPLEFT",14,-10)
	f.title:SetText(L.GROUP_SETTINGS)

	-- Close button (standard Blizzard X) -- flush with the panel's very
	-- top-right corner, matching FriendsFrame's own close button placement.
	local close=CreateFrame("Button","SocialPlus_SettingsCloseButton",f,"UIPanelCloseButton")
	close:SetPoint("TOPRIGHT",f,"TOPRIGHT",0,0)
	close:SetScript("OnClick",function()
		f:Hide()
	end)

	-- Checkboxes
	local hideOffline=CreateFrame("CheckButton","SocialPlus_HideOfflineCheck",f,"UICheckButtonTemplate")
	hideOffline:SetPoint("TOPLEFT",f,"TOPLEFT",14,-40)
	_G[hideOffline:GetName().."Text"]:SetText(L.SETTING_HIDE_OFFLINE)
	hideOffline:SetChecked(SocialPlus_SavedVars and SocialPlus_SavedVars.hide_offline)
	hideOffline:SetScript("OnClick",function()
		SocialPlus_SavedVars.hide_offline=not SocialPlus_SavedVars.hide_offline
		SocialPlus_Update()
	end)

	local colourNames=CreateFrame("CheckButton","SocialPlus_ColourNamesCheck",f,"UICheckButtonTemplate")
	colourNames:SetPoint("TOPLEFT",hideOffline,"BOTTOMLEFT",0,-6)
	_G[colourNames:GetName().."Text"]:SetText(L.SETTING_COLOR_NAMES)
	colourNames:SetChecked(SocialPlus_SavedVars and SocialPlus_SavedVars.colour_classes)
	colourNames:SetScript("OnClick",function()
		SocialPlus_SavedVars.colour_classes=not SocialPlus_SavedVars.colour_classes
		SocialPlus_Update()
	end)

	-- Prioritize current-client players -- label names whichever WoW version
	-- this client actually is (MoP, TBC, etc.), not hardcoded to one, since
	-- the addon runs on multiple classic clients now.
	local prioritizeCurrent=CreateFrame("CheckButton","SocialPlus_PrioritizeCurrentClientCheck",f,"UICheckButtonTemplate")
	prioritizeCurrent:SetPoint("TOPLEFT",colourNames,"BOTTOMLEFT",0,-6)
	local currentVersionLabel=SocialPlus_GetVersionLabelText(WOW_PROJECT_ID)
	_G[prioritizeCurrent:GetName().."Text"]:SetText(
		L.SETTING_PRIORITIZE_PREFIX..L.SETTING_PRIORITIZE_SUFFIX)
	prioritizeCurrent:SetChecked(SocialPlus_SavedVars and SocialPlus_SavedVars.prioritize_current_client)
	prioritizeCurrent:SetScript("OnClick",function()
		SocialPlus_SavedVars.prioritize_current_client=not SocialPlus_SavedVars.prioritize_current_client
		-- force full rebuild so ordering updates
		SocialPlus_Update(true)
	end)

	-- Separator + section header ahead of the notification checkboxes, same
	-- style as the existing separator below them.
	local preNotifyLine=f:CreateTexture(nil,"ARTWORK")
	preNotifyLine:SetSize(f:GetWidth()-24,1)
	preNotifyLine:SetPoint("TOPLEFT",prioritizeCurrent,"BOTTOMLEFT",0,-10)
	preNotifyLine:SetColorTexture(0.6,0.6,0.6,0.4)

	local notifySectionHeader=f:CreateFontString(nil,"ARTWORK","GameFontNormal")
	notifySectionHeader:SetPoint("TOPLEFT",preNotifyLine,"BOTTOMLEFT",0,-8)
	notifySectionHeader:SetText(L.SETTING_SECTION_NOTIFICATIONS)

	-- Friend online/offline notifications
	local notifyEnable=CreateFrame("CheckButton","SocialPlus_NotifyEnableCheck",f,"UICheckButtonTemplate")
	notifyEnable:SetPoint("TOPLEFT",notifySectionHeader,"BOTTOMLEFT",0,-6)
	_G[notifyEnable:GetName().."Text"]:SetText(L.SETTING_NOTIFY_ENABLE)
	notifyEnable:SetChecked(SocialPlus_SavedVars and SocialPlus_SavedVars.notifications and SocialPlus_SavedVars.notifications.enabled)

	local notifyOffline=CreateFrame("CheckButton","SocialPlus_NotifyOfflineCheck",f,"UICheckButtonTemplate")
	notifyOffline:SetPoint("TOPLEFT",notifyEnable,"BOTTOMLEFT",16,-6)
	_G[notifyOffline:GetName().."Text"]:SetText(L.SETTING_NOTIFY_OFFLINE)
	notifyOffline:SetChecked(SocialPlus_SavedVars and SocialPlus_SavedVars.notifications and SocialPlus_SavedVars.notifications.offline_too)
	notifyOffline:SetScript("OnClick",function()
		SocialPlus_SavedVars.notifications.offline_too=not SocialPlus_SavedVars.notifications.offline_too
	end)

	-- Only notify friends on this exact WoW version -- labelled dynamically
	-- like "Show WoW friends first" above. Off by default: most players
	-- still want notifications for every friend regardless of version,
	-- this is an opt-in filter for people who specifically don't want
	-- cross-version noise.
	local notifySameVersion=CreateFrame("CheckButton","SocialPlus_NotifySameVersionCheck",f,"UICheckButtonTemplate")
	notifySameVersion:SetPoint("TOPLEFT",notifyOffline,"BOTTOMLEFT",0,-6)
	_G[notifySameVersion:GetName().."Text"]:SetText(
		L.SETTING_NOTIFY_SAME_VERSION_PREFIX..currentVersionLabel..L.SETTING_NOTIFY_SAME_VERSION_SUFFIX)
	notifySameVersion:SetChecked(SocialPlus_SavedVars and SocialPlus_SavedVars.notifications and SocialPlus_SavedVars.notifications.same_version_only)
	notifySameVersion:SetScript("OnClick",function()
		SocialPlus_SavedVars.notifications.same_version_only=not SocialPlus_SavedVars.notifications.same_version_only
	end)

	-- Child checkboxes only mean anything while the parent "notify when
	-- friends come online" toggle is on -- gray them out and disable
	-- interaction (but never touch their SavedVars) whenever it's off, so
	-- re-enabling the parent restores exactly what the user had before.
	local function SocialPlus_UpdateNotifyChildState()
		local enabled=SocialPlus_SavedVars and SocialPlus_SavedVars.notifications and SocialPlus_SavedVars.notifications.enabled
		for _,child in ipairs({notifyOffline,notifySameVersion}) do
			if enabled then
				child:Enable()
				_G[child:GetName().."Text"]:SetTextColor(NORMAL_FONT_COLOR:GetRGB())
			else
				child:Disable()
				_G[child:GetName().."Text"]:SetTextColor(GRAY_FONT_COLOR:GetRGB())
			end
		end
	end

	notifyEnable:SetScript("OnClick",function()
		SocialPlus_SavedVars.notifications.enabled=not SocialPlus_SavedVars.notifications.enabled
		SocialPlus_ApplyToastCVars()
		SocialPlus_UpdateNotifyChildState()
	end)
	SocialPlus_UpdateNotifyChildState()

	-- Separator spanning almost full width, now directly below the notification checkboxes
	local line=f:CreateTexture(nil,"ARTWORK")
	line:SetSize(f:GetWidth()-24,1)
	line:SetPoint("TOPLEFT",notifySameVersion,"BOTTOMLEFT",0,-12)
	line:SetColorTexture(0.6,0.6,0.6,0.4)

	-- Slider label + description
	local lbl=f:CreateFontString(nil,"ARTWORK","GameFontHighlightSmall")
	lbl:SetPoint("TOPLEFT",line,"BOTTOMLEFT",0,-10)
	lbl:SetText(L.SETTING_SCROLL_SPEED)

	local desc=f:CreateFontString(nil,"ARTWORK","GameFontNormalSmall")
	desc:SetPoint("TOPLEFT",lbl,"BOTTOMLEFT",0,-6)
	desc:SetText(L.SETTING_SCROLL_SPEED_DESC)

	-- Slider (widened)
	local slider=CreateFrame("Slider","SocialPlus_SettingsScrollSpeedSlider",f,"OptionsSliderTemplate")
	slider:SetPoint("TOPLEFT",desc,"BOTTOMLEFT",0,-5)
	slider:SetSize(f:GetWidth()-40,16)
	slider:SetMinMaxValues(1.0,5.0)
	slider:SetValueStep(0.1)
	slider:SetObeyStepOnDrag(true)
	slider:SetValue(SocialPlus_SavedVars and SocialPlus_SavedVars.scrollSpeed or SCROLL_BASE)

	-- Center numeric value under slider
	slider.text=_G[slider:GetName().."Text"]
	if slider.text then
		slider.text:ClearAllPoints()
		slider.text:SetPoint("TOP",slider,"BOTTOM",0,-2)
		slider.text:SetJustifyH("CENTER")
		slider.text:SetText(string.format("%d%%",slider:GetValue()/SCROLL_BASE*100))
	end

	slider:SetScript("OnValueChanged",function(self,val)
		val=tonumber(val) or SCROLL_BASE
		val=math.floor(val*10+0.5)/10
		self:SetValue(val)
		if self.text then
			self.text:SetText(string.format("%d%%",val/SCROLL_BASE*100))
		end
		if not SocialPlus_SavedVars then SocialPlus_SavedVars={} end
		SocialPlus_SavedVars.scrollSpeed=val
		pcall(SocialPlus_InitSmoothScroll)
	end)

	-- Sync on show (no more icon profile dropdown)
	f:SetScript("OnShow",function()
		hideOffline:SetChecked(SocialPlus_SavedVars and SocialPlus_SavedVars.hide_offline)
		colourNames:SetChecked(SocialPlus_SavedVars and SocialPlus_SavedVars.colour_classes)
		prioritizeCurrent:SetChecked(SocialPlus_SavedVars and SocialPlus_SavedVars.prioritize_current_client)
		notifyEnable:SetChecked(SocialPlus_SavedVars and SocialPlus_SavedVars.notifications and SocialPlus_SavedVars.notifications.enabled)
		notifyOffline:SetChecked(SocialPlus_SavedVars and SocialPlus_SavedVars.notifications and SocialPlus_SavedVars.notifications.offline_too)
		notifySameVersion:SetChecked(SocialPlus_SavedVars and SocialPlus_SavedVars.notifications and SocialPlus_SavedVars.notifications.same_version_only)
		SocialPlus_UpdateNotifyChildState()

		local svSpeed=SocialPlus_SavedVars and SocialPlus_SavedVars.scrollSpeed or SCROLL_BASE
		slider:SetValue(svSpeed)
		if slider.text then
			slider.text:SetText(string.format("%d%%",svSpeed/SCROLL_BASE*100))
		end

		-- Dynamically fit the panel height to its actual content, so it never
		-- clips or leaves dead space as settings are added/removed over time.
		local top=f:GetTop()
		local bottom=(slider.text and slider.text:GetBottom()) or slider:GetBottom()
		if top and bottom then
			f:SetHeight((top-bottom)+20)
		end
	end)

	f:Hide()
	SocialPlus_SettingsPanel=f

	if FriendsFrame then
		FriendsFrame:HookScript("OnHide",function()
			-- Our group/friend dropdown menus aren't parented to FriendsFrame,
			-- so closing the panel (e.g. via Escape) doesn't automatically
			-- close them, leaving an orphaned menu on screen. Close explicitly.
			LibDD:CloseDropDownMenus()

			if SocialPlus_SettingsPanel then
				SocialPlus_SettingsPanel:Hide()
			end
			if SocialPlus_Searchbox then
				SocialPlus_Searchbox:SetText("")
				SocialPlus_Searchbox:ClearFocus()
				SocialPlus_SearchTerm=nil
				if SocialPlus_SearchGlow then SocialPlus_SearchGlow:Hide() end
				if SocialPlus_SearchGlowOuter then SocialPlus_SearchGlowOuter:Hide() end
			end
		end)
	end
end

local function SocialPlus_UpdateFriendsTabVisibility()
	if not FriendsFrame then return end

	local tabID=PanelTemplates_GetSelectedTab(FriendsFrame) or FriendsFrame.selectedTab
	local isFriendsTab=(tabID==1)

	-- Show/hide search box
	if SocialPlus_Searchbox then
		-- When leaving the Friends tab: clear search completely
		if not isFriendsTab then
			SocialPlus_Searchbox:SetText("")
			SocialPlus_Searchbox:ClearFocus()
			SocialPlus_SearchTerm=nil

			if SocialPlus_SearchGlow then
				SocialPlus_SearchGlow:Hide()
			end
			if SocialPlus_SearchGlowOuter then
				SocialPlus_SearchGlowOuter:Hide()
			end

			-- Do NOT call FriendsList_Update here: any function we define is tainted
			-- by SocialPlus, so even a C_Timer-deferred call propagates taint through
			-- our hooksecurefunc on FriendsList_Update and blocks CopyToClipboard in
			-- the /who unit popup.  SearchTerm is already nil and the search box is
			-- cleared, so the list rebuilds unfiltered on the next natural update.
		end

		SocialPlus_Searchbox:SetShown(isFriendsTab)
	end

	-- Show/hide settings button
	if SocialPlus_SettingsButton then
		SocialPlus_SettingsButton:SetShown(isFriendsTab)
	end

    -- keep +/- button in sync with the Friends tab
	if SocialPlus_CollapseAllButton then
		SocialPlus_UpdateCollapseAllButtonVisual()
	end

	-- Auto-close settings when leaving the tab
	if not isFriendsTab and SocialPlus_SettingsPanel and SocialPlus_SettingsPanel:IsShown() then
		SocialPlus_SettingsPanel:Hide()
	end
end

-- Run visibility fix on first load
SocialPlus_UpdateFriendsTabVisibility()

-- Update visibility when switching tabs
FriendsFrame:HookScript("OnShow",SocialPlus_UpdateFriendsTabVisibility)

hooksecurefunc("PanelTemplates_SetTab",function(frame,tabID)
	if frame==FriendsFrame then
		SocialPlus_UpdateFriendsTabVisibility()
	end
end)

-- [[ Friend (row) right-click menu state ]]

local SocialPlus_CurrentFriend=nil

local SocialPlus_FriendMenu=LibDD:Create_UIDropDownMenu("SocialPlus_FriendMenu",UIParent)
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
                if not overGear then
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

    -- Anything else -- a group header, the cogwheel, blank panel space,
    -- or truly outside the Friends List entirely -- clears an active
    -- search and drops focus, matching Escape. Only a friend row (above)
    -- is exempt.
    LibDD:CloseDropDownMenus()
    if SocialPlus_SearchTerm then
        SocialPlus_ClearSearchFromOutsideClick()
    end
    if SocialPlus_Searchbox and SocialPlus_Searchbox:HasFocus() then
        SocialPlus_Searchbox:ClearFocus()
    end
    self:Hide()
end)

SocialPlus_ClickCatcher:SetScript("OnUpdate",function(self)
    local dropOpen=SocialPlus_IsAnyDropDownOpen()
    local searchFocused=SocialPlus_Searchbox and SocialPlus_Searchbox:HasFocus()
    -- Also stay shown while a search term is still active (even without
    -- focus, e.g. after interacting with a friend row), so a later click
    -- that's genuinely outside the Friends List can still clear it --
    -- otherwise this immediately re-hid the catcher we just explicitly
    -- re-showed for exactly that purpose (confirmed live).
    local searchActive=SocialPlus_SearchTerm~=nil
    if not dropOpen and not searchFocused and not searchActive then self:Hide() end
end)

-- Escape should close an open menu first, not the whole Friends panel --
-- only let Escape propagate through to Blizzard's normal panel-close
-- handling when no menu is actually open. Same EnableKeyboard(true) +
-- SetPropagateKeyboardInput(true) pattern already proven working
-- elsewhere in this file (the drag ghost's Escape-to-cancel handler).
-- The catcher is only ever shown while a menu or search interaction is
-- active, so it naturally only sees Escape when relevant.
SocialPlus_ClickCatcher:EnableKeyboard(true)
SocialPlus_ClickCatcher:SetPropagateKeyboardInput(true)
SocialPlus_ClickCatcher:SetScript("OnKeyDown",function(self,key)
    if key=="ESCAPE" and SocialPlus_IsAnyDropDownOpen() then
        self:SetPropagateKeyboardInput(false)
        LibDD:CloseDropDownMenus()
    else
        self:SetPropagateKeyboardInput(true)
    end
end)

function SocialPlus_ShowClickCatcher()
    SocialPlus_ClickCatcher:Show()
end

SocialPlus_ClickCatcher:HookScript("OnHide",function()
    if SocialPlus_ClickCatcherIsForMenu then
        SocialPlus_PlayMenuCloseSound()
    end
    SocialPlus_ClickCatcherIsForMenu=false
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
		return false,L.INVITE_REASON_ALREADY_GROUPED,INVITE_RESTRICTION_INFO
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
		return false,L.INVITE_REASON_ALREADY_GROUPED,INVITE_RESTRICTION_INFO
	end

	-- BNGetFriendInfo position 16 is canSummon (boolean), not wowProjectID in MoP Classic;
	-- only compare when we actually got a numeric project ID.
	if WOW_PROJECT_ID and type(wowProjectID)=="number" and wowProjectID~=WOW_PROJECT_ID then
		return false,L.INVITE_REASON_WRONG_PROJECT,INVITE_RESTRICTION_WOW_PROJECT_ID
	end

	-- Extra faction/region compatibility via C_BattleNet if available
	local acct,ga=nil,nil
	local friendFaction,friendRegionID=nil,nil
	if C_BattleNet and C_BattleNet.GetFriendAccountInfo and type(C_BattleNet.GetFriendAccountInfo)=="function" then
		acct=C_BattleNet.GetFriendAccountInfo(id)
		ga=acct and acct.gameAccountInfo or nil
		friendFaction=ga and ga.factionName or nil
		friendRegionID=ga and ga.regionID or nil
	end

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

local function SocialPlus_DropdownFriendHasGroup()
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

local function SocialPlus_ApplyMenuMinWidth(level)
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

-- [[ Friend row dropdown (per-friend menu) ]]
SocialPlus_FriendMenu.initialize=function(self,level)
	level=level or 1
	if not SocialPlus_CurrentFriend then return end
	local info

	if level==1 then
		local cf=SocialPlus_CurrentFriend

		-- [ Friend Name ] title
		info=LibDD:UIDropDownMenu_CreateInfo()
		info.text=SocialPlus_GetMenuTitle()
		info.isTitle=true
		info.notCheckable=true
		info.disabled=true
		info.justifyH="LEFT"
		LibDD:UIDropDownMenu_AddButton(info,level)

		-- Make the title a bit sharper
		do
			local listFrame=_G["L_DropDownList"..level]
			if listFrame then
				local idx=listFrame.numButtons or 1
				local btn=_G[listFrame:GetName().."Button"..idx]
				if btn then
					local fs=btn:GetFontString()
					if fs then
						fs:SetFont("Fonts\\FRIZQT__.TTF",12,"OUTLINE")
					end
				end
			end
		end

		-- Toggle SocialPlus favorite (independent of Blizzard's own BNet
		-- favorite, which pins a friend to the top on its own with no
		-- addon-level control).
		if cf.buttonType==FRIENDS_BUTTON_TYPE_BNET or cf.buttonType==FRIENDS_BUTTON_TYPE_WOW then
			-- cf.id is the friend-list index captured when the menu opened,
			-- which can go stale if the list reorders while the menu is
			-- still open (confirmed live: toggled favorite on a different
			-- friend than the one actually right-clicked). Re-resolve to
			-- the CURRENT index from the stable presence ID/character name,
			-- the same pattern SocialPlus_GetDropdownFriend already uses
			-- for every other dropdown action.
			local dropdownKind,freshID=SocialPlus_GetDropdownFriend()
			local freshButtonType=(dropdownKind=="BNET") and FRIENDS_BUTTON_TYPE_BNET or FRIENDS_BUTTON_TYPE_WOW
			local isFav=freshID and SocialPlus_IsFavorite(freshButtonType,freshID)
			info=LibDD:UIDropDownMenu_CreateInfo()
			info.text=isFav and L.MENU_REMOVE_FAVORITE or L.MENU_ADD_FAVORITE
			info.notCheckable=true
			info.func=function()
				local k,fid=SocialPlus_GetDropdownFriend()
				if not fid then return end
				local bt=(k=="BNET") and FRIENDS_BUTTON_TYPE_BNET or FRIENDS_BUTTON_TYPE_WOW
				SocialPlus_ToggleFavorite(bt,fid)
			end
			LibDD:UIDropDownMenu_AddButton(info,level)
		end

		-- Set Note
		info=LibDD:UIDropDownMenu_CreateInfo()
		info.text=L.MENU_SET_NOTE
		info.notCheckable=true
		info.func=function()
			local kind,id,note,setter=SocialPlus_GetDropdownFriendNote()
			if not kind or not id or not setter then return end
			local groups={}
			local baseNote=NoteAndGroups(note,groups)
			StaticPopup_Show("FRIEND_SET_NOTE",nil,nil,{id=id,set=setter,note=baseNote,groups=groups})
		end
		LibDD:UIDropDownMenu_AddButton(info,level)

		-- View BNet friend's friends (Blizzard-style "View Friends")
		info=LibDD:UIDropDownMenu_CreateInfo()
		info.text=L.MENU_VIEW_FRIENDS
		info.notCheckable=true
		do
			local cf=SocialPlus_CurrentFriend
			if cf and cf.buttonType==FRIENDS_BUTTON_TYPE_BNET then
				info.disabled=false
			else
				info.disabled=true
			end
		end

		info.func=function()
			local cf=SocialPlus_CurrentFriend
			if not cf or cf.buttonType~=FRIENDS_BUTTON_TYPE_BNET then return end

			local index=cf.bnetIndex or cf.id
			if not index or not BNGetFriendInfo then return end

			-- MoP-style BNGetFriendInfo:
			-- presenceID = t[1], bnetIDAccount = last value
			local t={BNGetFriendInfo(index)}
			local presenceID=t[1]
			local bnetIDAccount=t[#t]

			if not presenceID then return end

			-- 1) Show the Friends-of-Friends frame
			if type(FriendsFriendsFrame_Show)=="function" then
				FriendsFriendsFrame_Show(presenceID)
			elseif FriendsFriendsFrame then
				if ShowUIPanel then
					ShowUIPanel(FriendsFriendsFrame)
				else
					FriendsFriendsFrame:Show()
				end
			end

			-- 2) Actually request the FoF data so it fills
			if BNRequestFOFInfo and bnetIDAccount then
				BNRequestFOFInfo(bnetIDAccount)
			end
		end
		LibDD:UIDropDownMenu_AddButton(info,level)

		-- --- separator before Interact block
		SocialPlus_AddSeparator(level)

		-- Interact header
		info=LibDD:UIDropDownMenu_CreateInfo()
		info.text=L.MENU_INTERACT
		info.isTitle=true
		info.notCheckable=true
		info.disabled=true
		LibDD:UIDropDownMenu_AddButton(info,level)

		-- Invite / Suggest invite
		info=LibDD:UIDropDownMenu_CreateInfo()

		local isSuggest=SocialPlus_ShouldSuggestInvite and SocialPlus_ShouldSuggestInvite()
		local label=isSuggest and (L.MENU_SUGGEST or L.MENU_INVITE) or L.MENU_INVITE

		info.text=label
		info.notCheckable=true

		-- Determine invite eligibility and reason for the dropdown friend
		local kind,id=SocialPlus_GetDropdownFriend()
		local canInvite,reason=false,nil
		if kind and id then
			canInvite,reason=SocialPlus_GetInviteStatus(kind,id)
		else
			canInvite=false
			reason=L.INVITE_GENERIC_FAIL
		end

		-- A BNet friend can have multiple WoW licenses online at the same
		-- time (same case the faction-preference fix handles) -- offer a
		-- submenu to choose which character to invite, matching Retail,
		-- instead of silently inviting whichever one gets auto-picked.
		local onlineAccounts=(kind=="BNET" and id) and SocialPlus_GetOnlineWoWGameAccounts(id) or nil

		if onlineAccounts and #onlineAccounts>1 then
			info.hasArrow=true
			info.value="SocialPlus_INVITE_SUB"
			info.disabled=false
			info.tooltipTitle=nil
			info.tooltipText=nil
			info.func=nil
		else
			info.disabled=not canInvite
			if info.disabled and reason and reason~="" then
				info.tooltipTitle="|cffff4444"..label.."|r"
				info.tooltipText=reason
			else
				info.tooltipTitle=label
				info.tooltipText=nil
			end

			info.func=function()
				if not SocialPlus_CanInviteMenuTarget() then return end

				local kind,id=SocialPlus_GetDropdownFriend()
				if not kind or not id then return end

				-- Use the unified invite helper (same logic as buttons)
				local ok,reason=SocialPlus_PerformInvite(kind,id)
				if not ok and reason and UIErrorsFrame and UIErrorsFrame.AddMessage then
					UIErrorsFrame:AddMessage(reason,1,0.1,0.1,1.0)
				end
			end
		end
		LibDD:UIDropDownMenu_AddButton(info,level)

		-- Whisper
		info=LibDD:UIDropDownMenu_CreateInfo()
		info.text=L.MENU_WHISPER
		info.notCheckable=true
		info.func=function()
			local cf=SocialPlus_CurrentFriend
			if not cf then return end

			local index=cf.bnetIndex or cf.id
			if not index then return end

			-- Don't touch the chat edit box or its attributes ourselves -- that's
			-- what was tainting the shared Menu system and blocking unrelated
			-- "Copy Name" clicks afterward. Instead, just set the same plain
			-- (non-protected) selection fields Blizzard's own Friends UI uses,
			-- then let Blizzard's own button handler do all the actual work.
			-- This is the same handler the default UI calls for both WoW and
			-- BNet friends, so it covers both cases.
			FriendsFrame.selectedFriendType=cf.buttonType
			FriendsFrame.selectedFriend=index

			FG_Debug("Whisper via FriendsFrameSendMessageButton_OnClick","buttonType="..tostring(cf.buttonType),"index="..tostring(index))

			if FriendsFrameSendMessageButton_OnClick then
				pcall(FriendsFrameSendMessageButton_OnClick,FriendsFrameSendMessageButton)
			end
		end
		LibDD:UIDropDownMenu_AddButton(info,level)

		-- Copy character name
		info=LibDD:UIDropDownMenu_CreateInfo()
		info.text=L.MENU_COPY_NAME
		info.notCheckable=true

		local canCopy=SocialPlus_CanCopyCharName()
		info.disabled=not canCopy

		info.func=function()
			if not SocialPlus_CanCopyCharName() then return end
			local cf=SocialPlus_CurrentFriend
			if not cf then return end
			local full=SocialPlus_GetFullCharacterName(cf)
			if full and full~="" then
				StaticPopup_Show("SocialPlus_COPY_NAME",nil,nil,{name=full})
			end
		end
		LibDD:UIDropDownMenu_AddButton(info,level)

		-- --- separator before Groups section
		SocialPlus_AddSeparator(level)

		-- Groups section title
		info=LibDD:UIDropDownMenu_CreateInfo()
		info.text=L.MENU_GROUPS
		info.isTitle=true
		info.notCheckable=true
		info.disabled=true
		LibDD:UIDropDownMenu_AddButton(info,level)

		-- Does this friend already have a #Group tag?
		local hasGroup=SocialPlus_DropdownFriendHasGroup()

		-- Create group from this friend
		info=LibDD:UIDropDownMenu_CreateInfo()
		info.text=L.MENU_CREATE_GROUP
		info.notCheckable=true
		info.disabled=hasGroup -- only for ungrouped friends
		info.func=SocialPlus_CreateGroupFromDropdown
		LibDD:UIDropDownMenu_AddButton(info,level)

		-- Add / Move submenu
		info=LibDD:UIDropDownMenu_CreateInfo()
		info.text=hasGroup and (L.MENU_MOVE_TO_GROUP or L.MENU_ADD_TO_GROUP) or L.MENU_ADD_TO_GROUP
		info.notCheckable=true
		info.hasArrow=true
		info.value="SocialPlus_ADD_SUB"
		info.disabled=false
		LibDD:UIDropDownMenu_AddButton(info,level)

		-- Remove-from-group (direct action — friends can only be in one group)
		local removeLabel=L.MENU_REMOVE_FROM_GROUP
		if hasGroup then
			local _,_,currentNote=SocialPlus_GetDropdownFriendNote()
			local currentGroups={}
			NoteAndGroups(currentNote,currentGroups)
			for g in pairs(currentGroups) do
				local c=NORMAL_FONT_COLOR
				local hex=string.format("|cff%02x%02x%02x",c.r*255,c.g*255,c.b*255)
				removeLabel=string.format(L.MENU_REMOVE_FROM_NAMED,"["..hex..g.."|r]")
				break
			end
		end
		info=LibDD:UIDropDownMenu_CreateInfo()
		info.text=removeLabel
		info.notCheckable=true
		info.hasArrow=false
		info.disabled=not hasGroup
		info.func=function()
			local kind,id,note,setter=SocialPlus_GetDropdownFriendNote()
			if not setter or not id then return end
			local groups={}
			local baseNote=NoteAndGroups(note,groups)
			for g in pairs(groups) do
				baseNote=RemoveGroup(baseNote,g)
			end
			setter(id,baseNote)
			SocialPlus_ClearSearch()
			SocialPlus_Update()
		end
		LibDD:UIDropDownMenu_AddButton(info,level)

        -- Separator before Other Options
        SocialPlus_AddSeparator(level)

        -- Other Options header
        info=LibDD:UIDropDownMenu_CreateInfo()
        info.text=L.MENU_OTHER_OPTIONS
        info.isTitle=true
        info.notCheckable=true
        info.disabled=true
        LibDD:UIDropDownMenu_AddButton(info,level)

        -- Remove Friend / Remove Battle.net Friend
        info=LibDD:UIDropDownMenu_CreateInfo()
        info.notCheckable=true
        info.func=function()
            SocialPlus_RemoveCurrentFriend()
        end
        if cf and cf.buttonType==FRIENDS_BUTTON_TYPE_BNET then
            info.text=L.MENU_REMOVE_BNET
        else
            info.text=REMOVE_FRIEND
        end
        LibDD:UIDropDownMenu_AddButton(info,level)

		-- After all level-1 buttons are added, enforce a minimum width
        SocialPlus_ApplyMenuMinWidth(level)

	elseif level==2 then
		if L_UIDROPDOWNMENU_MENU_VALUE=="SocialPlus_ADD_SUB" then
			SocialPlus_BuildGroupSubmenu("ADD",level)
		elseif L_UIDROPDOWNMENU_MENU_VALUE=="SocialPlus_DEL_SUB" then
			SocialPlus_BuildGroupSubmenu("DEL",level)
		elseif L_UIDROPDOWNMENU_MENU_VALUE=="SocialPlus_INVITE_SUB" then
			SocialPlus_BuildInviteAccountSubmenu(level)
		end
	end
end


-- [[ FriendsFrame button hooks (click / tooltip / invite tooltip) ]]
local frame=CreateFrame("Frame")
frame:RegisterEvent("PLAYER_LOGIN")
frame:RegisterEvent("BN_FRIEND_ACCOUNT_ONLINE")
frame:RegisterEvent("BN_FRIEND_ACCOUNT_OFFLINE")
frame:RegisterEvent("FRIENDLIST_UPDATE")

local function SocialPlus_OnClick(self,button)
	if self.buttonType==FRIENDS_BUTTON_TYPE_DIVIDER then
		-- Use the raw group key; for General this is "" (ungrouped)
		local groupKey=self.SocialPlusGroupName or ""

		if button=="RightButton" then
			-- Still allow the header context menu everywhere. No menu
			-- sound here -- that's reserved for the cogwheel buttons, not
			-- right-click context menus.
			LibDD:ToggleDropDownMenu(1,groupKey,SocialPlus_Menu,"cursor",0,0)
			SocialPlus_ShowClickCatcher()
		else
			SocialPlus_SavedVars.collapsed[groupKey]=not SocialPlus_SavedVars.collapsed[groupKey]

			SocialPlus_HardResetScrollRows()
			SocialPlus_Update(true)
			SocialPlus_Update(true)
			C_Timer.After(0,function()
				SocialPlus_Update(true)
			end)
		end
		return
	end


	if button~="RightButton" then
		if self.SocialPlus_OrigOnClick then
			return self.SocialPlus_OrigOnClick(self,button)
		end
		return
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

	-- No menu sound here -- that's reserved for the cogwheel buttons, not
	-- right-click context menus.
	SocialPlus_SetCurrentFriend(self)
	LibDD:ToggleDropDownMenu(1,nil,SocialPlus_FriendMenu,"cursor",0,0)
	SocialPlus_ShowClickCatcher()
end

-- Blizzard's FriendsFrameTooltip_Show prints the raw note verbatim into a
-- dedicated "FriendsTooltipNoteText" FontString (with a "FriendsTooltipNoteIcon"
-- texture next to it), which includes our "#Group" tags (e.g. "test#Friends").
-- Strip everything from the first "#" onward, and hide both the text and
-- its icon entirely if nothing but tags was there -- leaving the same gap
-- Blizzard already shows for any friend with no note at all, rather than a
-- placeholder line (tried "Right-click to add a note", but it could
-- overflow the tooltip's width for short names, and repositioning it to
-- avoid the icon-width indent broke the layout twice -- not worth it).
local function SocialPlus_StripNoteGroupTagFromTooltip(button)
	if not (button and FriendsTooltip and FriendsTooltip:IsShown() and FriendsTooltip.button==button) then
		return
	end

	local noteFontString=_G.FriendsTooltipNoteText
	if not noteFontString then return end

	local text=noteFontString:GetText()
	if not text or not text:find("#") then return end

	local noteIcon=_G.FriendsTooltipNoteIcon
	local baseNote=strtrim(text:match("^([^#]*)") or "")
	if baseNote=="" then
		if noteIcon then noteIcon:Hide() end
		noteFontString:SetText("—")
		noteFontString:SetTextColor(0.5,0.5,0.5)
		noteFontString:Show()
	else
		noteFontString:SetText(baseNote)
		noteFontString:SetTextColor(1,1,1)
		if noteIcon then noteIcon:Show() end
	end
end

local function SocialPlus_OnEnter(self)
	-- Do nothing when not on the Friends tab; touching Blizzard frames here
	-- from tainted code would propagate taint to the /who popup’s CopyToClipboard.
	if FriendsFrame then
		local tabID=PanelTemplates_GetSelectedTab(FriendsFrame) or FriendsFrame.selectedTab
		if tabID and tabID~=1 then return end
	end

	-- Don’t show standard tooltip on group headers -- or on any row while a
	-- group-header drag is active (confirmed live: the tooltip was still
	-- popping up over friend rows mid-drag, cluttering the drag feedback).
	if self.buttonType==FRIENDS_BUTTON_TYPE_DIVIDER or SocialPlus_DragSourceGroup then
		if FriendsTooltip:IsShown() then
			FriendsTooltip:Hide()
		end
	else
		SocialPlus_StripNoteGroupTagFromTooltip(self)
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
			btn:HookScript("OnEnter",SocialPlus_OnEnter)

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
local function SocialPlus_FindBNetIndexByPresenceID(presenceID)
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
		return kind,id,note,FG_SetBNetFriendNote
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

	StaticPopup_Show("SocialPlus_CREATE",nil,nil,{id=id,note=note,set=setter})

	-- Close the dropdown after clicking "Create new group"
	LibDD:CloseDropDownMenus()
end

function SocialPlus_ModifyGroupFromDropdown(group,mode)
	if not group or group=="" then return end
	local kind,id,note,setter=SocialPlus_GetDropdownFriendNote()
	if not kind or not id or not setter then return end

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
		-- Pure remove: just strip the selected group tag.
		newNote=RemoveGroup(baseNote,group)
	end

	setter(id,newNote)

	-- Clear search so full list is shown after adding/removing
	if SocialPlus_ClearSearch then
		SocialPlus_ClearSearch()
	end

	-- Rebuild and close menus
	SocialPlus_Update()
	LibDD:CloseDropDownMenus()
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
			eb:SetMaxLetters(4)
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

		if eb:GetText()==L.CONFIRM_REMOVE_BNET_WORD then
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
			-- Favorites isn't a real group a friend can be tagged into via
			-- their note -- it's a display-time overlay driven by the
			-- favorite flag, toggled from "Add/Remove Favorites" only.
			if group~="" and group~=SP_FAVORITES_GROUP and not groups[group] then
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

	local c=NORMAL_FONT_COLOR
	local hex=string.format("|cff%02x%02x%02x",c.r*255,c.g*255,c.b*255)
	for _,acct in ipairs(accounts) do
		local target=acct.characterName
		if acct.realmName and acct.realmName~="" then
			target=target.."-"..acct.realmName
		end

		local details={}
		if acct.level and acct.level~=0 then table.insert(details,tostring(acct.level)) end
		if acct.className and acct.className~="" then table.insert(details,acct.className) end
		local detailText=(#details>0) and (" ("..table.concat(details,", ")..")") or ""

		-- Same eligibility signals used elsewhere (faction, project) --
		-- simplified to this one candidate rather than the full
		-- SocialPlus_GetInviteStatus chain, since that resolves against
		-- whichever account GetFriendInfoById currently prefers, not
		-- necessarily the specific one being listed here.
		local factionMismatch=acct.factionName and playerFaction and acct.factionName~=playerFaction
		local projectMismatch=WOW_PROJECT_ID and acct.wowProjectID and acct.wowProjectID~=WOW_PROJECT_ID
		local ineligible=factionMismatch or projectMismatch

		local info=LibDD:UIDropDownMenu_CreateInfo()
		info.text="["..hex..target.."|r]"..detailText
		info.notCheckable=true
		info.disabled=ineligible
		if ineligible then
			info.tooltipTitle=target
			info.tooltipText=factionMismatch and L.INVITE_REASON_OPPOSITE_FACTION or L.INVITE_REASON_WRONG_PROJECT
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
local SOCIALPLUS_NOTIFY_DEBOUNCE_WINDOW=3

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
local SocialPlus_ScanWarmupUntil=0

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
-- until real flag icon art is added.
local function SocialPlus_FormatRegionText(regionID)
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
		return "[|TInterface\\Common\\FavoritesIcon:14:14:0:-1|t"..SocialPlus_GetFavoritesLabel().."] "
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
-- searches for that group. Must be a real override (checked BEFORE calling
-- through), not hooksecurefunc -- Blizzard's own SetItemRef doesn't
-- silently ignore an unrecognized link type, it hard-errors trying to
-- SetHyperlink() it on ItemRefTooltip (confirmed live). Anything that
-- isn't our own link type still falls through to the original unchanged,
-- so other addons' SetItemRef hooks are unaffected.
local SocialPlus_OrigSetItemRef=SetItemRef
SetItemRef=function(link,text,button,chatFrame)
	local groupName=link and link:match("^socialplus_group:(.*)$")
	if groupName then
		-- ShowFriendsFrame doesn't exist as a global on this client
		-- (confirmed live -- the panel silently failed to open while the
		-- search-text part still worked). ShowUIPanel + PanelTemplates_SetTab
		-- are the same primitives this file already relies on elsewhere for
		-- FriendsFrame (see the FriendsFriendsFrame ShowUIPanel call and the
		-- PanelTemplates_SetTab hook above) -- lower-level and confirmed
		-- present on this client.
		if ShowUIPanel then
			ShowUIPanel(FriendsFrame)
		end
		if PanelTemplates_SetTab then
			PanelTemplates_SetTab(FriendsFrame,1)
		end
		if SocialPlus_Searchbox then
			SocialPlus_Searchbox:SetText(groupName)
		end
		return
	end
	return SocialPlus_OrigSetItemRef(link,text,button,chatFrame)
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
		local displayText=bnetColourCode..accountName.."|r"
		if fullName then
			displayText=displayText.." "..classColourCode.."("..fullName..")|r"
		end
		return "|HBNplayer:"..accountName..":"..presenceID.."|h"..displayText.."|h"
	end

	fullName=fullName or accountName or ""
	return classColourCode.."|Hplayer:"..fullName.."|h"..fullName.."|h|r"
end

local function SocialPlus_PrintNotification(text)
	if DEFAULT_CHAT_FRAME and DEFAULT_CHAT_FRAME.AddMessage then
		DEFAULT_CHAT_FRAME:AddMessage("|cff33ff99[SocialPlus]|r "..text)
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
	SocialPlus_PrintNotification(groupPrefix..msg..".")
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
		local t={FG_BNGetFriendInfo(i)}
		local presenceID=t[1]
		local battleTag=t[3]

		if presenceID and SocialPlus_ShouldNotifyForNote(t[13],battleTag) then
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
	C_Timer.After(0.5,SocialPlus_ScanFriendsForWoWStateChanges)
end

-- [[ Suppress Blizzard's own friend online/offline notification ]]
-- Blizzard's "friend came online/offline" line turned out to be an inline
-- toast overlay, not a real chat message (confirmed live: it never appears
-- in CHAT_MSG_SYSTEM, and third-party chat-copy addons can't see it either),
-- so a ChatFrame message filter can never catch it no matter how the pattern
-- is built. Instead, directly control the two CVars that the Blizzard
-- Options -> Social "online/offline friends" checkboxes themselves set
-- (confirmed live via a SetCVar hook): showToastOnline / showToastOffline.
-- This takes over both toasts whenever our own notification is on, and
-- restores Blizzard's default the moment it's off.
function SocialPlus_ApplyToastCVars()
	local enabled=SocialPlus_SavedVars and SocialPlus_SavedVars.notifications and SocialPlus_SavedVars.notifications.enabled
	SetCVar("showToastOnline",enabled and "0" or "1")
	SetCVar("showToastOffline",enabled and "0" or "1")
end

-- [[ Initialization on PLAYER_LOGIN ]]

frame:SetScript("OnEvent",function(self,event,...)
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

		FG_InitFactionIcon()

		Hook("FriendsList_Update",SocialPlus_Update,true)

		if FriendsFrameTooltip_Show then
			Hook("FriendsFrameTooltip_Show",SocialPlus_OnEnter,true)
		end

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
		local SocialPlus_ScrollRecomputeTimer=nil
		FriendsScrollFrame.update=function()
			SocialPlus_UpdateFriends()
			if SocialPlus_ScrollRecomputeTimer then
				SocialPlus_ScrollRecomputeTimer:Cancel()
			end
			SocialPlus_ScrollRecomputeTimer=C_Timer.NewTimer(0.15,function()
				SocialPlus_ScrollRecomputeTimer=nil
				SocialPlus_Update(true)
			end)
		end

		if FriendsScrollFrame and FriendsScrollFrame.buttons and FriendsScrollFrame.buttons[1] and FRIENDS_FRAME_FRIENDS_FRIENDS_HEIGHT then
			pcall(FriendsScrollFrame.buttons[1].SetHeight,FriendsScrollFrame.buttons[1],FRIENDS_FRAME_FRIENDS_FRIENDS_HEIGHT)
		end
		if HybridScrollFrame_CreateButtons then
			pcall(HybridScrollFrame_CreateButtons,FriendsScrollFrame,FriendButtonTemplate)
		end

		HookButtons()
	elseif event=="BN_FRIEND_ACCOUNT_ONLINE" then
		local bnetIDAccount=...
		SocialPlus_QueueNotifyCheck(bnetIDAccount)
		SocialPlus_QueueFriendScan()
	elseif event=="BN_FRIEND_ACCOUNT_OFFLINE" then
		local bnetIDAccount=...
		SocialPlus_QueueNotifyCheck(bnetIDAccount)
		SocialPlus_QueueFriendScan()
	elseif event=="FRIENDLIST_UPDATE" then
		SocialPlus_QueueFriendScan()
	end
end)
