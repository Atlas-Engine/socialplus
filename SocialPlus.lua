local hooks = {}
local SocialPlus_OriginalDropdownInit
local PLAYER_FACTION = UnitFactionGroup("player")  -- "Alliance" or "Horde"

-----------------------------------------------------------------------
-- Localization: English + French (auto-detected via GetLocale())
-----------------------------------------------------------------------
local L = {}
do
    local locale = GetLocale()

    if locale == "frFR" then
        -- General
        L.ADDON_NAME              = "SocialPlus"

        ----------------------------------------------------------------
        -- Interaction Menu (right-click friend)
        ----------------------------------------------------------------
        L.MENU_INTERACT           = "Interagir"
        L.MENU_WHISPER            = "Chuchoter"
		L.MENU_INVITE             = "Inviter"
        L.MENU_SUGGEST            = "Suggérer une invitation"
        L.MENU_COPY_NAME          = "Copier le nom du personnage"
		L.MENU_VIEW_FRIENDS       = "Voir ses amis"

		L.MENU_GROUPS             = "Gestion des groupes"
        L.MENU_CREATE_GROUP       = "Créer un groupe"
        L.MENU_ADD_TO_GROUP       = "Ajouter au groupe"
        L.MENU_MOVE_TO_GROUP      = "Déplacer vers un autre groupe"
        L.MENU_REMOVE_FROM_GROUP  = "Retirer du groupe"

        L.MENU_OTHER_OPTIONS      = "Options supplémentaires"
        L.MENU_SET_NOTE           = "Définir une note"
        L.MENU_REMOVE_BNET        = "Retirer l’ami Battle.net"

        ----------------------------------------------------------------
        -- Search & grouping
        ----------------------------------------------------------------
        L.SEARCH_PLACEHOLDER      = "Rechercher un ami..."
        L.GROUP_UNGROUPED         = "Général"

        ----------------------------------------------------------------
        -- Group menu (header right-click)
        ----------------------------------------------------------------
        L.GROUP_INVITE_ALL        = "Inviter tout le groupe"
        L.GROUP_RENAME            = "Renommer le groupe"
        L.GROUP_REMOVE            = "Supprimer le groupe"
        L.GROUP_SETTINGS          = "Paramètres du groupe"
        L.GROUP_NO_GROUPS         = "Aucun groupe disponible"
        L.GROUP_NO_GROUPS_REMOVE  = "Aucun groupe à retirer"
        L.GROUP_REORDER_AZ        = "Réorganiser les groupes (A–Z)"

        ----------------------------------------------------------------
        -- Settings toggles (group submenu)
        ----------------------------------------------------------------
        L.SETTING_HIDE_OFFLINE       = "Masquer les amis hors ligne"
        L.SETTING_HIDE_MAX_LEVEL     = "Masquer les personnages de niveau maximal"
        L.SETTING_COLOR_NAMES        = "Colorer les noms selon la classe"
        L.SETTING_PRIORITIZE_CURRENT = "Prioriser les amis sur Mists of Pandaria"
        L.SETTING_SCROLL_SPEED       = "Vitesse de défilement"
        L.SETTING_SCROLL_SPEED_DESC  = "Ajuste la vitesse de défilement de la liste d’amis."

        ----------------------------------------------------------------
        -- Popup titles
        ----------------------------------------------------------------
        L.POPUP_RENAME_TITLE        = "Renommer le groupe"
        L.POPUP_CREATE_TITLE        = "Nom du nouveau groupe"
        L.POPUP_NOTE_TITLE          = "Ajouter ou modifier une note"
        L.POPUP_COPY_TITLE          = "Nom du personnage (Ctrl+C pour copier) :"

        ----------------------------------------------------------------
        -- Extra messages
        ----------------------------------------------------------------
        L.MSG_INVITE_FAILED         = "Impossible d’inviter cet ami."
        L.MSG_INVITE_CROSSREALM     = "Invitation impossible : cet ami est sur un autre royaume."
        L.INVITE_REASON_NOT_WOW     = "Cet ami n’est pas actuellement dans World of Warcraft."
        L.INVITE_REASON_WRONG_PROJECT = "Cet ami n’utilise pas la même version de WoW que vous."
        L.INVITE_REASON_NO_REALM      = "Cet ami se trouve dans une autre région."
        L.INVITE_REASON_OPPOSITE_FACTION = "Cet ami appartient à la faction adverse."

        L.CONFIRM_REMOVE_BNET_TEXT  = 'Voulez-vous vraiment retirer "%s" ?\n\nTapez "OUI." pour confirmer.'
        L.CONFIRM_REMOVE_BNET_WORD  = "OUI."
        L.MSG_REMOVE_FRIEND_SUCCESS = 'Vous avez retiré %s avec succès.'
        L.INVITE_GENERIC_FAIL       = "Vous ne pouvez pas inviter cet ami."

    else
        ----------------------------------------------------------------
        -- Default: English
        ----------------------------------------------------------------
        L.ADDON_NAME              = "SocialPlus"

        ----------------------------------------------------------------
        -- Interaction Menu
        ----------------------------------------------------------------
        L.MENU_INTERACT           = "Interact"
        L.MENU_WHISPER            = "Whisper"
		L.MENU_INVITE             = "Invite"
        L.MENU_SUGGEST            = "Suggest Invite"
        L.MENU_COPY_NAME          = "Copy Character Name"
        L.MENU_VIEW_FRIENDS       = "View friends list"

		L.MENU_GROUPS             = "Group Management"
        L.MENU_CREATE_GROUP       = "Create Group"
        L.MENU_ADD_TO_GROUP       = "Add to Group"
        L.MENU_MOVE_TO_GROUP      = "Move to another Group"
        L.MENU_REMOVE_FROM_GROUP  = "Remove from Group"

        L.MENU_OTHER_OPTIONS      = "Additional Options"
        L.MENU_SET_NOTE           = "Set Note"
        L.MENU_REMOVE_BNET        = "Remove Battle.net Friend"

        ----------------------------------------------------------------
        -- Search & grouping
        ----------------------------------------------------------------
        L.SEARCH_PLACEHOLDER      = "Search friends..."
        L.GROUP_UNGROUPED         = "General"

        ----------------------------------------------------------------
        -- Group menu (header right-click)
        ----------------------------------------------------------------
        L.GROUP_INVITE_ALL        = "Invite Entire Group"
        L.GROUP_RENAME            = "Rename Group"
        L.GROUP_REMOVE            = "Delete Group"
        L.GROUP_SETTINGS          = "Group Settings"
        L.GROUP_NO_GROUPS         = "No groups available"
        L.GROUP_NO_GROUPS_REMOVE  = "No groups to remove"
        L.GROUP_REORDER_AZ        = "Reorder Groups (A–Z)"

        ----------------------------------------------------------------
        -- Settings toggles
        ----------------------------------------------------------------
        L.SETTING_HIDE_OFFLINE       = "Hide offline friends"
        L.SETTING_HIDE_MAX_LEVEL     = "Hide max-level characters"
        L.SETTING_COLOR_NAMES        = "Color names by class"
        L.SETTING_PRIORITIZE_CURRENT = "Prioritize MoP friends"
        L.SETTING_SCROLL_SPEED       = "Scroll speed"
        L.SETTING_SCROLL_SPEED_DESC  = "Adjust the scroll speed for the friends list."

        ----------------------------------------------------------------
        -- Popup titles
        ----------------------------------------------------------------
        L.POPUP_RENAME_TITLE        = "Group Name"
        L.POPUP_CREATE_TITLE        = "New Group Name"
        L.POPUP_NOTE_TITLE          = "Enter a note for this friend"
        L.POPUP_COPY_TITLE          = "Character Name (Ctrl+C to copy):"

        ----------------------------------------------------------------
        -- Extra messages
        ----------------------------------------------------------------
        L.MSG_INVITE_FAILED         = "Unable to invite this friend."
        L.MSG_INVITE_CROSSREALM     = "This friend is on a different realm and cannot be invited."
        L.INVITE_REASON_NOT_WOW     = "This friend is not currently in World of Warcraft."
        L.INVITE_REASON_WRONG_PROJECT = "This friend is not on your WoW version."
        L.INVITE_REASON_NO_REALM      = "This friend is in a different region."
        L.INVITE_REASON_OPPOSITE_FACTION = "This friend is on the opposite faction."

        L.CONFIRM_REMOVE_BNET_TEXT  = 'Are you sure you want to remove "%s"?\n\nType "YES." to confirm.'
        L.CONFIRM_REMOVE_BNET_WORD  = "YES."
        L.MSG_REMOVE_FRIEND_SUCCESS = 'Successfully removed %s.'
        L.INVITE_GENERIC_FAIL       = "You cannot invite this friend."
    end
end


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

-- Ensure savedvars exist and set reasonable defaults
function SocialPlus_EnsureSavedVars()
    SocialPlus_SavedVars=SocialPlus_SavedVars or {}
    if SocialPlus_SavedVars.hide_offline==nil then SocialPlus_SavedVars.hide_offline=false end
    if SocialPlus_SavedVars.hide_high_level==nil then SocialPlus_SavedVars.hide_high_level=false end
    if SocialPlus_SavedVars.colour_classes==nil then SocialPlus_SavedVars.colour_classes=true end
    if SocialPlus_SavedVars.scrollSpeed==nil then SocialPlus_SavedVars.scrollSpeed=SCROLL_BASE end
    -- Default ON for “Prioritize MoP friends”
    if SocialPlus_SavedVars.prioritize_current_client==nil then
   	   SocialPlus_SavedVars.prioritize_current_client=true
    end
   	   SocialPlus_SavedVars.collapsed=SocialPlus_SavedVars.collapsed or {}
       SocialPlus_SavedVars.groupOrder=SocialPlus_SavedVars.groupOrder or {}
    -- Never persist collapse state for the ungrouped "General" bucket
	if SocialPlus_SavedVars.collapsed[""] then
	   SocialPlus_SavedVars.collapsed[""] = nil
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

local INVITE_RESTRICTION_NO_GAME_ACCOUNTS=0
local INVITE_RESTRICTION_CLIENT=1
local INVITE_RESTRICTION_LEADER=2
local INVITE_RESTRICTION_FACTION=3
local INVITE_RESTRICTION_REALM=4
local INVITE_RESTRICTION_INFO=5
local INVITE_RESTRICTION_WOW_PROJECT_ID=6
local INVITE_RESTRICTION_WOW_PROJECT_MAINLINE=7
local INVITE_RESTRICTION_WOW_PROJECT_CLASSIC=8
local INVITE_RESTRICTION_NONE=9
local INVITE_RESTRICTION_MOBILE=10

-- Classic and retail use different values for restrictions
if WOW_PROJECT_ID==WOW_PROJECT_CLASSIC then
	INVITE_RESTRICTION_NO_GAME_ACCOUNTS=0
	INVITE_RESTRICTION_CLIENT=1
	INVITE_RESTRICTION_LEADER=2
	INVITE_RESTRICTION_FACTION=3
	INVITE_RESTRICTION_REALM=nil
	INVITE_RESTRICTION_INFO=4
	INVITE_RESTRICTION_WOW_PROJECT_ID=5
	INVITE_RESTRICTION_WOW_PROJECT_MAINLINE=6
	INVITE_RESTRICTION_WOW_PROJECT_CLASSIC=7
	INVITE_RESTRICTION_NONE=8
	INVITE_RESTRICTION_MOBILE=9
end

-- Invite tier helper for sorting:
-- 1 = fully inviteable (same region+version)
-- 2 = different region/realm
-- 3 = different WoW project/version
-- 4 = other online games / BNet app (non-WoW)
-- 5 = everything else (generic/info/misc)
local function SocialPlus_GetInviteTier(kind,id)
    local allowed,_,restriction=SocialPlus_GetInviteStatus(kind,id)

    -- Fully inviteable → very top
    if allowed and restriction==INVITE_RESTRICTION_NONE then
        return 1
    end

    -- Different region/realm
    if restriction==INVITE_RESTRICTION_REALM
       or (type(INVITE_RESTRICTION_REGION)~="nil" and restriction==INVITE_RESTRICTION_REGION) then
        return 2
    end

    -- Different game version / project
    if restriction==INVITE_RESTRICTION_WOW_PROJECT_ID
       or restriction==INVITE_RESTRICTION_WOW_PROJECT_MAINLINE
       or restriction==INVITE_RESTRICTION_WOW_PROJECT_CLASSIC then
        return 3
    end

    -- Online but not in WoW (BNet app, other game, etc.)
    if restriction==INVITE_RESTRICTION_CLIENT
       or restriction==INVITE_RESTRICTION_NO_GAME_ACCOUNTS then
        return 4
    end

    -- Generic / info / mobile / weird leftovers → lowest online tier
    return 5
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
local SCROLL_BASE = 2.2
-- Apply a tuning factor < 1.0 to slow speeds globally as requested
local SCROLL_TUNE_FACTOR = 0.85

-- Friend list state	
local FriendButtons={count=0}
local GroupCount=0
local GroupTotal={}
local GroupOnline={}
local GroupSorted={}
local FriendRequestString=string.sub(FRIEND_REQUESTS,1,-6)

-- [[ Custom group ordering + drag state ]]
local SocialPlus_DragSourceGroup=nil
local SocialPlus_DragHoverGroup=nil
local SocialPlus_DragSourceButton=nil
local SocialPlus_DragGhostFrame=nil

-- Global collapse/expand button state
local SocialPlus_CollapseAllButton

-- Returns anyCollapsed, anyExpanded for *custom* groups only (ignores General and Friend Requests)
local function SocialPlus_GetAnyGroupCollapsed()
	local anyCollapsed=false
	local anyExpanded=false

	if not GroupSorted or not SocialPlus_SavedVars or not SocialPlus_SavedVars.collapsed then
		return false,false
	end

	for _,groupName in ipairs(GroupSorted) do
		-- Ignore ungrouped bucket ("") and Friend Requests header
		if groupName~="" and groupName~=FriendRequestString then
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

		-- up to 5 sample friend names (left aligned under header)
		f.friend1=f:CreateFontString(nil,"OVERLAY","GameFontHighlightSmall")
		f.friend1:ClearAllPoints()
		f.friend1:SetPoint("TOPLEFT",f,"TOPLEFT",8,-22)  -- fixed left margin
		f.friend1:SetJustifyH("LEFT")


		f.friend2=f:CreateFontString(nil,"OVERLAY","GameFontHighlightSmall")
		f.friend2:SetPoint("TOPLEFT",f.friend1,"BOTTOMLEFT",0,-1)
		f.friend2:SetJustifyH("LEFT")

		f.friend3=f:CreateFontString(nil,"OVERLAY","GameFontHighlightSmall")
		f.friend3:SetPoint("TOPLEFT",f.friend2,"BOTTOMLEFT",0,-1)
		f.friend3:SetJustifyH("LEFT")

		f.friend4=f:CreateFontString(nil,"OVERLAY","GameFontHighlightSmall")
		f.friend4:SetPoint("TOPLEFT",f.friend3,"BOTTOMLEFT",0,-1)
		f.friend4:SetJustifyH("LEFT")

		f.friend5=f:CreateFontString(nil,"OVERLAY","GameFontHighlightSmall")
		f.friend5:SetPoint("TOPLEFT",f.friend4,"BOTTOMLEFT",0,-1)
		f.friend5:SetJustifyH("LEFT")

		f:SetAlpha(0.80)
		f:Hide()

		SocialPlus_DragGhostFrame=f
	end
	return SocialPlus_DragGhostFrame
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
	local others={}

	for groupName in pairs(GroupTotal) do
		if groupName==FriendRequestString then
			hasFriendReq=true
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

-- Drop any custom order and rebuild in pure A–Z.
function SocialPlus_SortGroupsAlphabetically()
	SocialPlus_EnsureSavedVars()
	SocialPlus_SavedVars.groupOrder=nil
	SocialPlus_ApplyGroupOrder()
	SocialPlus_Update(true)
	if FriendsList_Update then
		pcall(FriendsList_Update)
	end
end

-- Move source group based on current visible order (GroupSorted),
-- with direction-aware behavior (drag up = above target, drag down = below).
SocialPlus_SetCustomGroupOrderFromMove=function(source,target)
	if not source or not target or source==target then return end
	-- don’t drag Friend Requests or the implicit General bucket
	if source==FriendRequestString or source=="" then return end
	if target==FriendRequestString or target=="" then return end

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
	-- - dragging down (originalSourceIndex < originalTargetIndex): insert AFTER target
	-- - dragging up   (originalSourceIndex > originalTargetIndex): insert BEFORE target
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
	if not group or group==FriendRequestString or group=="" then
		return
	end

	SocialPlus_DragSourceGroup=group
	SocialPlus_DragSourceButton=self

	-- Immediately refresh so the entire group fades visually
    if FriendsList_Update then
        pcall(FriendsList_Update)
    end

	-- ghost frame
	local ghost=SocialPlus_GetDragGhost()

	-- sample friends from this group
	local headerIndex=self.index
	local samples=SocialPlus_SampleGroupFriends(headerIndex,5) -- soft cap at 5

	-- set header text
	if ghost.text then
	ghost.text:SetText(group)
	end

	-- set sample friend names
	local lineCount=0
	if ghost.friend1 then
		local name1=samples[1]
		if name1 then
			ghost.friend1:SetText(name1)
			ghost.friend1:Show()
			lineCount=lineCount+1
		else
			ghost.friend1:SetText("")
			ghost.friend1:Hide()
		end
	end
	if ghost.friend2 then
		local name2=samples[2]
		if name2 then
			ghost.friend2:SetText(name2)
			ghost.friend2:Show()
			lineCount=lineCount+1
		else
			ghost.friend2:SetText("")
			ghost.friend2:Hide()
		end
	end
	if ghost.friend3 then
    local name3=samples[3]
    if name3 then
        ghost.friend3:SetText(name3)
        ghost.friend3:Show()
        lineCount=lineCount+1
    else
        ghost.friend3:SetText("")
        ghost.friend3:Hide()
    end
	end
	if ghost.friend4 then
    local name4=samples[4]
    if name4 then
        ghost.friend4:SetText(name4)
        ghost.friend4:Show()
        lineCount=lineCount+1
    else
        ghost.friend4:SetText("")
        ghost.friend4:Hide()
    end
	end
	if ghost.friend5 then
    local name5=samples[5]
    if name5 then
        ghost.friend5:SetText(name5)
        ghost.friend5:Show()
        lineCount=lineCount+1
    else
        ghost.friend5:SetText("")
        ghost.friend5:Hide()
    end
end

	-- size ghost: header height + a bit per line
	local baseW=self:GetWidth()
	local baseH=self:GetHeight()
	local extraH=(lineCount>0) and (lineCount*14+4) or 0


	ghost:SetSize(baseW,baseH+extraH)
	ghost:Show()

	-- follow cursor
	ghost:SetScript("OnUpdate",function(frame)
		if not SocialPlus_DragSourceGroup then
			frame:Hide()
			frame:SetScript("OnUpdate",nil)
			return
		end
		local x,y=GetCursorPosition()
		local scale=UIParent:GetEffectiveScale()
		frame:ClearAllPoints()
		frame:SetPoint("CENTER",UIParent,"BOTTOMLEFT",x/scale,y/scale)
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

	local source=SocialPlus_DragSourceGroup
	local target=SocialPlus_DragHoverGroup  -- usually set by OnEnter while dragging

	-- Fallback: if hover target is invalid, infer it from the button we released on
	if (not target or target==source or target==FriendRequestString or target=="") and self then
		local fallback
		if self.buttonType==FRIENDS_BUTTON_TYPE_DIVIDER then
			fallback=self.SocialPlusGroupName
		else
			fallback=SocialPlus_GetGroupKeyFromRow(self)
		end

		if fallback and fallback~=source and fallback~=FriendRequestString and fallback~="" then
			target=fallback
		end
	end

    SocialPlus_DragSourceButton=nil
    SocialPlus_DragSourceGroup=nil
    SocialPlus_DragHoverGroup=nil

    -- Refresh rows so drag fade is immediately removed even on cancel
    if FriendsList_Update then
        pcall(FriendsList_Update)
    end

    -- still no valid target? Cancel.
    if not target or target==source or target==FriendRequestString or target=="" then
        return
    end
	-- Perform the move	
	SocialPlus_SetCustomGroupOrderFromMove(source,target)
end

-- Clear SocialPlus search box if it has content/focus and the click is outside it
local function SocialPlus_ClearSearchOnClickOutside()
    if not SocialPlus_Searchbox then return end
    if not MouseIsOver then return end

    -- If mouse is over the search box, do nothing
    if MouseIsOver(SocialPlus_Searchbox) then
        return
    end

    local txt = SocialPlus_Searchbox:GetText() or ""
    local hasText = txt:match("%S") ~= nil
    local hasTerm = SocialPlus_SearchTerm ~= nil

    if not hasText and not hasTerm then
        return -- nothing to clear
    end

    SocialPlus_Searchbox:SetText("")
    SocialPlus_Searchbox:ClearFocus()
    SocialPlus_SearchTerm = nil

    if SocialPlus_SearchGlow then
        SocialPlus_SearchGlow:Hide()
    end
    if SocialPlus_SearchGlowOuter then
        SocialPlus_SearchGlowOuter:Hide()
    end

    if FriendsList_Update then
        FriendsList_Update()
    end
end

-- Close open dropdowns (including SocialPlus menus) when left-clicking anywhere else
local function SocialPlus_GlobalDropdownClickCloser(self,button)
    if button~="LeftButton" then return end

    -- Check if any dropdown list is actually open
    local anyOpen=false
    local maxLevels=UIDROPDOWNMENU_MAXLEVELS or 2
    for i=1,maxLevels do
        local list=_G["DropDownList"..i]
        if list and list:IsShown() then
            anyOpen=true
            break
        end
    end
    if not anyOpen then return end

    -- If the mouse is over any open dropdown, do nothing (let it handle the click)
    if MouseIsOver then
        for i=1,maxLevels do
            local list=_G["DropDownList"..i]
            if list and list:IsShown() and MouseIsOver(list) then
                return
            end
        end
    end

    -- Mouse is outside all dropdowns: close them
    if CloseDropDownMenus then
        CloseDropDownMenus()
    end
end

-- Hook WorldFrame once so every left click gets checked
if WorldFrame and not WorldFrame.SocialPlusDropHooked then
    WorldFrame.SocialPlusDropHooked=true
    WorldFrame:HookScript("OnMouseDown",SocialPlus_GlobalDropdownClickCloser)
end

local OPEN_DROPDOWNMENUS_SAVE=nil
local friend_popup_menus={"FRIEND","FRIEND_OFFLINE","BN_FRIEND","BN_FRIEND_OFFLINE"}

-- Determine the current max player level for the active expansion	
local currentExpansionMaxLevel=90 -- MoP Classic cap
if type(GetMaxPlayerLevel)=="function" then
	currentExpansionMaxLevel=GetMaxPlayerLevel()
end

-------------------------------------------------
-- SocialPlus simple search (accent/symbol-insensitive)
-------------------------------------------------
local SocialPlus_Searchbox
local SocialPlus_SearchTerm=nil  -- always normalized or nil

-- Normalize text: lowercase, strip accents, remove non-alphanumerics
local function SocialPlus_NormalizeText(str)
    if not str then return "" end
    str=str:lower()

    local accents={
        ["à"]="a",["á"]="a",["â"]="a",["ä"]="a",["ã"]="a",["å"]="a",["ā"]="a",
        ["ç"]="c",
        ["è"]="e",["é"]="e",["ê"]="e",["ë"]="e",["ē"]="e",
        ["ì"]="i",["í"]="i",["î"]="i",["ï"]="i",["ī"]="i",
        ["ñ"]="n",
        ["ò"]="o",["ó"]="o",["ô"]="o",["ö"]="o",["õ"]="o",["ō"]="o",
        ["ù"]="u",["ú"]="u",["û"]="u",["ü"]="u",["ū"]="u",
        ["ý"]="y",["ÿ"]="y",
    }

    -- UTF-8–safe: walk characters and map accents
    str=str:gsub("[%z\1-\127\194-\244][\128-\191]*",function(c)
        return accents[c] or c
    end)

    -- Strip everything that is not a–z or 0–9
    str=str:gsub("[^a-z0-9]","")

    return str
end

local function SocialPlus_CreateSearchBox()
	if SocialPlus_Searchbox or not FriendsFrame then return end

	SocialPlus_Searchbox=CreateFrame("EditBox","SocialPlusSearchBox",FriendsFrame,"SearchBoxTemplate")
	SocialPlus_Searchbox:SetAutoFocus(false)

		-- Subtle neon glow around the search box
	local glow=CreateFrame("Frame",nil,SocialPlus_Searchbox,"BackdropTemplate")
	glow:SetFrameLevel(SocialPlus_Searchbox:GetFrameLevel()+2)
	glow:SetPoint("TOPLEFT",SocialPlus_Searchbox,-4,-1)
	glow:SetPoint("BOTTOMRIGHT",SocialPlus_Searchbox,-1,1)
	glow:SetBackdrop({
	edgeFile="Interface\\Buttons\\WHITE8x8",
	edgeSize=1.5, -- thinner neon line
	})
	glow:SetBackdropBorderColor(0,0.65,1,0.7) -- softer, muted neon
	glow:Hide()

	-- Soft bloom (very subtle)
	local outer=CreateFrame("Frame",nil,glow,"BackdropTemplate")
	outer:SetFrameLevel(glow:GetFrameLevel()-1)
	outer:SetPoint("TOPLEFT",glow,-1,1)
	outer:SetPoint("BOTTOMRIGHT",glow,1,-1)
	outer:SetBackdrop({
	edgeFile="Interface\\Buttons\\WHITE8x8",
	edgeSize=5, -- small bloom
})
outer:SetBackdropBorderColor(0,0.5,1,0.15) -- light glow, barely there
outer:Hide()

SocialPlus_SearchGlow=glow
SocialPlus_SearchGlowOuter=outer

	-- Fixed, visible position near top-right
	local sbWidth = 139
	local locale = GetLocale and GetLocale() or nil
	if locale == "frFR" then sbWidth = 139 end
	SocialPlus_Searchbox:SetSize(sbWidth,20)
	SocialPlus_Searchbox:SetPoint("TOPRIGHT",FriendsFrame,"TOPRIGHT",-35,-63)
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

	-- When there is at least one expanded custom group, we "collapse all custom groups".
	-- When all custom groups are collapsed, we "expand all custom groups".
	if anyExpanded then
		-- Collapse all custom groups
		if GroupSorted then
			for _,groupName in ipairs(GroupSorted) do
				if groupName~="" and groupName~=FriendRequestString then
					SocialPlus_SavedVars.collapsed[groupName]=true
				end
			end
		end
	else
		-- Expand all custom groups
		if GroupSorted then
			for _,groupName in ipairs(GroupSorted) do
				if groupName~="" and groupName~=FriendRequestString then
					SocialPlus_SavedVars.collapsed[groupName]=nil
				end
			end
		end
	end

	SocialPlus_Update(true)
	SocialPlus_UpdateCollapseAllButtonVisual()
end)


		SocialPlus_CollapseAllButton:Hide()
	end

	-- Configure search box appearance and behavior
	SocialPlus_Searchbox.Instructions:SetText(L.SEARCH_PLACEHOLDER)
	local font,size,flags=SocialPlus_Searchbox:GetFont()
	SocialPlus_Searchbox:SetFont(font,size,flags)
	SocialPlus_Searchbox:SetTextColor(1,1,1)
	SocialPlus_Searchbox.Instructions:SetTextColor(0.8,0.8,0.8)
	SocialPlus_Searchbox:SetScript("OnTextChanged",function(self)
    SearchBoxTemplate_OnTextChanged(self)
    local txt=self:GetText() or ""
    txt=txt:match("^%s*(.-)%s*$") or ""

    local norm=SocialPlus_NormalizeText(txt)
    if norm=="" then
        SocialPlus_SearchTerm=nil
    else
        SocialPlus_SearchTerm=norm  -- already normalized (lowercase, no accents, no symbols)
    end	
        if SocialPlus_SearchGlow then
	if SocialPlus_SearchTerm then
		SocialPlus_SearchGlow:Show()
		if SocialPlus_SearchGlowOuter then SocialPlus_SearchGlowOuter:Show() end
	else
		SocialPlus_SearchGlow:Hide()
		if SocialPlus_SearchGlowOuter then SocialPlus_SearchGlowOuter:Hide() end
	end
	end


    FriendsList_Update()
	end)

	SocialPlus_Searchbox:SetScript("OnEscapePressed",function(self)
    self:SetText("")
    self:ClearFocus()
    SocialPlus_SearchTerm=nil
    if SocialPlus_SearchGlow then
        SocialPlus_SearchGlow:Hide()
    end
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
		FACTION_ICON_PATH="Interface\\TargetingFrame\\UI-PVP-Horde"
	elseif playerFaction=="Alliance" then
		FACTION_ICON_PATH="Interface\\TargetingFrame\\UI-PVP-Alliance"
	else
		FACTION_ICON_PATH=nil
	end
end

-- Detect default icon schema based on client portal/locale
local function SocialPlus_DetectDefaultIconSchema()
    local schema

    -- 1) Prefer launcher portal (last WoW opened wins: "us"/"eu")
    if GetCVar then
        local portal=GetCVar("portal")
        if portal and portal~="" then
            portal=portal:lower()
            if portal:find("eu") then
                schema="EU"
            elseif portal:find("us") then
                schema="NA"
            end
        end
    end

    -- 2) Fallback to locale if portal was useless
    if not schema and GetLocale then
        local loc=GetLocale()
        if loc=="enUS" or loc=="esMX" or loc=="ptBR" then
            schema="NA"
        else
            schema="EU"
        end
    end

    return schema or "NA"
end


-- Decide which icon fileIDs to use based purely on the client portal
local function SocialPlus_GetIconSchema()
    -- Default if everything fails
    local schema="NA"

    if GetCVar then
        local portal=GetCVar("portal")
        if portal and portal~="" then
            portal=portal:lower()
            if portal:find("eu") then
                schema="EU"
            elseif portal:find("us") then
                schema="NA"
            end
        end
    end

    return schema
end

-- Decide which icon fileIDs to use based purely on the client portal
local function SocialPlus_GetIconSchema()
    local schema="NA" -- default

    if GetCVar then
        local portal=GetCVar("portal")
        if portal and portal~="" then
            portal=portal:lower()
            if portal:find("eu") then
                schema="EU"
            elseif portal:find("us") then
                schema="NA"
            end
        end
    end

    return schema
end

-- Decide which icon fileIDs to use based purely on the client portal
local SOCIALPLUS_REGION=SocialPlus_GetIconSchema()

-- Region-specific icon fileIDs
local SOCIALPLUS_ICON_IDS_NA={
    BNET=-6,
    APP =-6,
    WoW =-21,
    SC2 =-16,
    D2  =-8,
    D3  =-14,
    D4  =-17,
    HS  =-11,
    HOTS=-13,
    OW  =-5,
    COD =-12,
    WC3 =-20,
}

local SOCIALPLUS_ICON_IDS_EU={
    BNET=-14,
    APP =-14,
    WoW =-35,
    SC2 =-28,
    D2  =-17,
    D3  =-10,
    D4  =-30,
    HS  =-16,
    HOTS=-25,
    OW  =-13,
    COD =-21,
    WC3 =-33,
}

local SOCIALPLUS_ICON_IDS=(SOCIALPLUS_REGION=="EU") and SOCIALPLUS_ICON_IDS_EU or SOCIALPLUS_ICON_IDS_NA

-- Map BNet client programs to clean in-game icons (file IDs)
local SOCIALPLUS_GAME_ICONS={}
local SOCIALPLUS_DEFAULT_BNET_ICON=SOCIALPLUS_ICON_IDS.BNET or -6
local SOCIALPLUS_UNKNOWN_CLIENTS={}

local function SocialPlus_RegisterIcon(clientConst,fileID)
    if clientConst and fileID then
        SOCIALPLUS_GAME_ICONS[clientConst]=fileID
    end
end

local function SocialPlus_PickIcon(key,defaultID)
    local id=SOCIALPLUS_ICON_IDS[key]
    return id or defaultID or SOCIALPLUS_DEFAULT_BNET_ICON
end

-- Use region-picked IDs
SocialPlus_RegisterIcon(BNET_CLIENT_WOW    or "WoW" ,SocialPlus_PickIcon("WoW" ))
SocialPlus_RegisterIcon(BNET_CLIENT_SC2    or "S2"  ,SocialPlus_PickIcon("SC2" ))
SocialPlus_RegisterIcon(BNET_CLIENT_D2     or "OSI" ,SocialPlus_PickIcon("D2"  ))
SocialPlus_RegisterIcon(BNET_CLIENT_D3     or "D3"  ,SocialPlus_PickIcon("D3"  ))
SocialPlus_RegisterIcon(BNET_CLIENT_D4     or "D4"  ,SocialPlus_PickIcon("D4"  ))
SocialPlus_RegisterIcon(BNET_CLIENT_WTCG   or "WTCG",SocialPlus_PickIcon("HS"  ))
SocialPlus_RegisterIcon(BNET_CLIENT_HEROES or "Hero",SocialPlus_PickIcon("HOTS"))
SocialPlus_RegisterIcon(BNET_CLIENT_OVERWATCH or "Pro",SocialPlus_PickIcon("OW"))
SocialPlus_RegisterIcon(BNET_CLIENT_CLNT   or "CLNT",SocialPlus_PickIcon("BNET"))
SocialPlus_RegisterIcon(BNET_CLIENT_COD    or "COD" ,SocialPlus_PickIcon("COD"))
SocialPlus_RegisterIcon(BNET_CLIENT_WC3    or "W3"  ,SocialPlus_PickIcon("WC3"))

-- Battle.net app / launcher / Remix
SocialPlus_RegisterIcon(BNET_CLIENT_APP or "App",SocialPlus_PickIcon("APP"))
SocialPlus_RegisterIcon("BSAp",                     SocialPlus_PickIcon("APP"))

-- Auto-sizing helper so icons follow row height (including faction crests)
local function SocialPlus_GetAutoIconSize(button,isFaction)
    local h

    if button and button.GetHeight then
        h=button:GetHeight()
    end
    if (not h or h<=0) and button and button.buttonType and FRIENDS_BUTTON_HEIGHTS then
        h=FRIENDS_BUTTON_HEIGHTS[button.buttonType]
    end
    if not h or h<=0 then
        h=34 -- fallback
    end

    -- On a ~34px row:
    --  crest ≈ 30–31px, game icons ≈ 26–27px
    if isFaction then
        return math.floor(h*0.92+0.5)
    end

    return math.floor(h*0.78+0.5)
end

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

	icon:SetPoint(point,button,relPoint,offX,offY)
	icon:SetSize(size,size)
	icon:SetTexCoord(0,1,0,1)
	icon:SetTexture(iconPath)
	icon:Show()
end

-- --------------------------------------------------------------------
-- SocialPlus icon styles
-- Central place to tweak size/position of every icon type
-- --------------------------------------------------------------------
local SocialPlus_IconStyles={
	game={
		size=24,
		point="RIGHT",
		relPoint="RIGHT",
		offX=-24,
		offY=0,
	},
	crest={
		size=52,
		point="RIGHT",
		relPoint="RIGHT",
		offX=-1,
		offY=-10,
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

		if not info or not info.connected or not name or name=="" then
			return false,L.INVITE_GENERIC_FAIL
		end

		if InviteUnit then
			pcall(InviteUnit,name)
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
				if InviteUnit then
					pcall(InviteUnit,target)
					return true
				end
			end
		end

		-- Fallback to BNet invite APIs if for some reason we couldn't build a unit name
		if BNInviteFriend then
			pcall(BNInviteFriend,id)
			return true
		elseif BNSendGameInvite then
			pcall(BNSendGameInvite,id)
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

-- [[ Smooth scroll inertia (eased, fixed speed per wheel notch) ]]
local SocialPlus_ScrollAnim=nil

function SocialPlus_ScrollOnUpdate(self,elapsed)
	local anim=SocialPlus_ScrollAnim
	if not anim then
		self:SetScript("OnUpdate",nil)
		return
	end

	anim.t=anim.t+elapsed
	local p=anim.t/anim.duration
	if p>=1 then p=1 end

	-- Smooth easing: accelerate then decelerate (S-curve)
	local ease=p*p*(3-2*p)

	local newValue=anim.from+(anim.to-anim.from)*ease
	anim.scrollBar:SetValue(newValue)

	if p>=1 then
		SocialPlus_ScrollAnim=nil
		self:SetScript("OnUpdate",nil)
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

		-- Interpret both tiny nudges and big spins
		local dir,mag
		if delta>0 then
			dir=1
			mag=delta
		elseif delta<0 then
			dir=-1
			mag=-delta
		else
			return
		end

		-- Clamp raw magnitude from the wheel
		if mag<0.25 then mag=0.25 end
		if mag>3 then mag=3 end

		-- Boost small flicks a bit without touching full spins:
		-- mag=3 stays 3, mag small gets proportionally more.
		local boost=0.80
		mag=mag+boost*(1-mag/3)

		-- Safety re-clamp
		if mag>3 then mag=3 end
		if mag<0.25 then mag=0.25 end

		-- Base step: baseline distance per "normal" tick
		local baseStep=45

		-- Slider 1..5 → 0.4..1.8 multiplier
		local displayValue=(SocialPlus_SavedVars and SocialPlus_SavedVars.scrollSpeed) or 2.2
		displayValue=tonumber(displayValue) or 3.0
		if displayValue<1.0 then displayValue=1.0 end
		if displayValue>5.0 then displayValue=5.0 end

		local t=(displayValue-1.0)/4.0
		if t<0 then t=0 end
		if t>1 then t=1 end

		-- 1.0 → 0.4x, 5.0 → 1.8x
		local finalMultiplier=0.4+1.4*t

		-- Step now scales with both the slider and how hard you spin the wheel
		local step=baseStep*finalMultiplier*mag

		local target=current-dir*step
		if target<min then target=min end
		if target>max then target=max end
		if target==current then return end

		-- Same smooth animation duration as before (scaled only by slider)
		local duration=0.06+0.05*t

		SocialPlus_ScrollAnim={
			scrollBar=sb,
			from=current,
			to=target,
			t=0,
			duration=duration,
		}

		self:SetScript("OnUpdate",SocialPlus_ScrollOnUpdate)
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
			afk=false,
			dnd=false,
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
						return table.unpack(tt)
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

-- [[ Friends-of-Friends frame helper ]]	
local function SocialPlus_ShowFriendsOfFriend(accountID)
	if not accountID then return end

	-- 1) Try Blizzard helper if present
	if type(FriendsFriendsFrame_Show)=="function" then
		FriendsFriendsFrame_Show(accountID)
	else
		-- 2) Brutal fallback: just show the frame manually
		if FriendsFriendsFrame then
			if ShowUIPanel and FriendsFriendsFrame:IsObjectType("Frame") then
				ShowUIPanel(FriendsFriendsFrame)
			else
				FriendsFriendsFrame:Show()
			end
		elseif FriendsFrame and ShowUIPanel then
			-- Worst case: open main Friends frame
			ShowUIPanel(FriendsFrame)
		end
	end

	-- 3) Make sure the FoF data is actually requested (older clients need this)
	if BNRequestFOFInfo then
		BNRequestFOFInfo(accountID)
	end
end

-- [[ Class colour helper ]]
local function ClassColourCode(class,returnTable)
	if not class then
		return returnTable and FRIENDS_GRAY_COLOR or string.format("|cFF%02x%02x%02x",FRIENDS_GRAY_COLOR.r*255,FRIENDS_GRAY_COLOR.g*255,FRIENDS_GRAY_COLOR.b*255)
	end

	local initialClass=class
	for k,v in pairs(LOCALIZED_CLASS_NAMES_FEMALE) do
		if class==v then
			class=k
			break
		end
	end
	if class==initialClass then
		for k,v in pairs(LOCALIZED_CLASS_NAMES_MALE) do
			if class==v then
				class=k
				break
			end
		end
	end
	local colour=class~="" and RAID_CLASS_COLORS[class] or FRIENDS_GRAY_COLOR
	-- Shaman color is shared with pally in the table in classic
	if WOW_PROJECT_ID==WOW_PROJECT_CLASSIC and class=="SHAMAN" then
		colour.r=0
		colour.g=0.44
		colour.b=0.87
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

-- [[ Online info text helper ]]
local function GetOnlineInfoText(client,isMobile,rafLinkType,locationText)
	if not locationText or locationText=="" then
		return UNKNOWN
	end
	if isMobile then
		return LOCATION_MOBILE_APP
	end
	local hasRAF=Enum and Enum.RafLinkType
	if hasRAF and (client==BNET_CLIENT_WOW) and rafLinkType and (rafLinkType~=Enum.RafLinkType.None) and not isMobile then
		if rafLinkType==Enum.RafLinkType.Recruit then
			return RAF_RECRUIT_FRIEND:format(locationText)
		else
			return RAF_RECRUITER_FRIEND:format(locationText)
		end
	end
	return locationText
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
			mobile=accountInfo.isWowMobile
			zoneName=accountInfo.areaName
			lastOnline=accountInfo.lastOnlineTime

			local gameAccountInfo=accountInfo.gameAccountInfo
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

function SocialPlus_IsCurrentClientFriend(buttonType,id)
	-- If the setting is off, never prioritize anyone
	if not (SocialPlus_SavedVars and SocialPlus_SavedVars.prioritize_current_client) then
		return false
	end

	-- Non-BNet WoW friend → use the same rules as the invite helper
	if buttonType==FRIENDS_BUTTON_TYPE_WOW then
		local allowed = false
		if SocialPlus_GetInviteStatus then
			allowed = select(1,SocialPlus_GetInviteStatus("WOW",id))
		end
		return allowed and true or false
	end

	-- BNet friend → must pass full invite checks (project, faction, REGION, canCoop, etc.)
	if buttonType==FRIENDS_BUTTON_TYPE_BNET then
		local allowed = false
		if SocialPlus_GetInviteStatus then
			allowed = select(1,SocialPlus_GetInviteStatus("BNET",id))
		end
		return allowed and true or false
	end

	return false
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

function SocialPlus_SampleGroupFriends(headerIndex,maxCount)
	local names={}
	if not headerIndex or not FriendButtons or not maxCount or maxCount<=0 then
		return names
	end

	local total=FriendButtons.count or 0
	for i=headerIndex+1,total do
		local row=FriendButtons[i]
		if not row or row.buttonType==FRIENDS_BUTTON_TYPE_DIVIDER then
			break -- end of this group
		end

		local display=nil

		if row.buttonType==FRIENDS_BUTTON_TYPE_WOW then
			if FG_GetFriendInfoByIndex then
				local info=FG_GetFriendInfoByIndex(row.id)
				if info then
					display=info.name or info.name_with_realm or info.characterName or info.nameText
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
				end
			end
		end

		if display and display~="" then
			names[#names+1]=display
			if #names>=maxCount then
				break
			end
		end
	end

	return names
end


-- [[ Core per-row button update ]]
local function SocialPlus_UpdateFriendButton(button)
	local index=button.index
	button.buttonType=FriendButtons[index].buttonType
	button.id=FriendButtons[index].id
	local height=FRIENDS_BUTTON_HEIGHTS[button.buttonType]
	local nameText,nameColor,infoText,broadcastText,isFavoriteFriend
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

	-- Update based on button type
	if button.buttonType==FRIENDS_BUTTON_TYPE_WOW then
		local info=FG_GetFriendInfoByIndex(FriendButtons[index].id)
		broadcastText=nil
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

			if SocialPlus_SavedVars.hide_high_level and info.level==currentExpansionMaxLevel then
				nameText=info.name..", "..info.className
			else
				nameText=info.name..", "..format(FRIENDS_LEVEL_TEMPLATE,info.level,info.className)
			end

			if WOW_PROJECT_ID==WOW_PROJECT_MAINLINE then
				infoText=GetOnlineInfoText(BNET_CLIENT_WOW,info.mobile,info.rafLinkType,info.area)
			end

			if FACTION_ICON_PATH then
				FG_ApplyGameIcon(button,FACTION_ICON_PATH,52,"RIGHT","RIGHT",-1,-10)
				button.SocialPlusIconAlpha=1   -- always full for pure WoW friends
			elseif button.gameIcon then
				button.gameIcon:Hide()
				button.SocialPlusIconAlpha=nil
			end

			-- Invite button for online non-BNet WoW friends
			hasTravelPassButton=true
			if button.travelPassButton then
				local allowed, reason = SocialPlus_GetInviteStatus("WOW", FriendButtons[index].id)
				button.travelPassButton.fgInviteAllowed = allowed
				button.travelPassButton.fgInviteReason = reason
				if allowed then
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
                iconPath="Interface\\TargetingFrame\\UI-PVP-Horde"
            elseif friendFaction=="Alliance" then
                iconPath="Interface\\TargetingFrame\\UI-PVP-Alliance"
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

        -- Crest alpha: ONLY opposite faction gets faded
        local crestAlpha
        if isCrest and friendFaction and PLAYER_FACTION then
            crestAlpha=(friendFaction~=PLAYER_FACTION) and 0.4 or 1
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

        -- Fade rules for non-crest game logos
        local fadeIcon=false
        if client==BNET_CLIENT_WOW then
            if WOW_PROJECT_ID and wowProjectID and wowProjectID~=WOW_PROJECT_ID then
                -- Different project (Retail vs Classic) → fade
                fadeIcon=true
            elseif not allowed and (
                restriction==INVITE_RESTRICTION_WOW_PROJECT_ID
                or restriction==INVITE_RESTRICTION_REALM
                or restriction==INVITE_RESTRICTION_REGION   -- 🔥 different REGION → fade
            ) then
                fadeIcon=true
            end
        else
            -- Non-WoW clients: always slightly faded
            fadeIcon=true
        end

		if isCrest then
			-- Crest still fades for opposite faction, but ALSO fades for region/project restrictions
			if fadeIcon then
				button.SocialPlusIconAlpha = 0.4
			else
				button.SocialPlusIconAlpha = crestAlpha or 1
			end
		else
			button.SocialPlusIconAlpha = fadeIcon and 0.4 or 1
		end

        -- Show invite button
        hasTravelPassButton=true
        if allowed then
            button.travelPassButton:Enable()
        else
            button.travelPassButton:Disable()
        end

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

				-- For the General / ungrouped header, do NOT show +/- at all
		if not group or group=="" then
			button.status:SetTexture(nil)
		else
			if SocialPlus_SavedVars.collapsed[group] then
				button.status:SetTexture("Interface\\Buttons\\UI-PlusButton-UP")
			else
				button.status:SetTexture("Interface\\Buttons\\UI-MinusButton-UP")
			end
		end

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

	-- drag-and-drop for group headers
	button.SocialPlusGroupName=group

if not button.SocialPlusHeaderDragHooked then
	button:RegisterForDrag("LeftButton")
	button:SetScript("OnDragStart",SocialPlus_OnGroupDragStart)
	button:SetScript("OnDragStop",SocialPlus_OnGroupDragStop)
	button.SocialPlusHeaderDragHooked=true
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

	    -- Attach unified SocialPlus click handler once per button
    if button.travelPassButton and not button.travelPassButton.SocialPlusClickHooked then
        button.travelPassButton.SocialPlusClickHooked=true

        -- Preserve Blizzard's original handler as a fallback
        button.travelPassButton.SocialPlusOrigOnClick=button.travelPassButton:GetScript("OnClick")

        button.travelPassButton:SetScript("OnClick",function(self,...)
            -- If SocialPlus says this row is inviteable, always use our helper
            if self.fgInviteAllowed then
                SocialPlus_PerformInviteFromButton(button)
                return
            end

            -- Otherwise fall back to Blizzard's behaviour, if it exists
            if self.SocialPlusOrigOnClick then
                self.SocialPlusOrigOnClick(self,...)
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
	-- BEFORE:
	-- local numFriendButtons=FriendButtons.count
	-- AFTER:
	local numFriendButtons=FriendButtons.count or 0
	local usedHeight=0

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
	for i=1,n do
		local v=select(i,...)
		v=strtrim(v)
		groups[v]=true
	end
	if n==0 then
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

local function CreateNote(note,groups)
	local value=""
	if note then
		value=note
	end
	for group in pairs(groups) do
		value=value.."#"..group
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

	local numBNetTotal,numBNetOnline=FG_BNGetNumFriends()
	numBNetTotal=numBNetTotal or 0
	numBNetOnline=numBNetOnline or 0
	local numWoWTotal=FG_GetNumFriends()
	local numWoWOnline=FG_GetNumOnlineFriends()
	local numWoWOffline=numWoWTotal-numWoWOnline

	if QuickJoinToastButton then
		QuickJoinToastButton:UpdateDisplayedFriendCount()
	end
	if (not FriendsListFrame:IsShown() and not forceUpdate) then
		return
	end

		-- >>> SIMPLE NAME-ONLY SEARCH MODE (no groups) <<<
	if SocialPlus_SearchTerm then
		wipe(FriendButtons)
		wipe(GroupTotal)
		wipe(GroupOnline)
		GroupCount=0


		local term=SocialPlus_SearchTerm -- already normalized (lowercase, no accents/symbols)
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

		local function startsWith(haystack,needle)
			if not haystack or haystack=="" or not needle or needle=="" then
				return false
			end
			return haystack:sub(1,#needle)==needle
		end

		local function firstWord(s)
			if not s or s=="" then return "" end
			return (s:match("^(%S+)")) or ""
		end

		-- BNet friends: try BattleTag first, then accountName, then character name
		for i=1,numBNetTotal do
			local accountName,characterName,_,_,_,isOnline=
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

				if startsWith(normalized,term) then
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
				if startsWith(searchName,term) then
					AddButtonInfo(FRIENDS_BUTTON_TYPE_WOW,i)
				end
			end
		end

		FriendsScrollFrame.totalFriendListEntriesHeight=totalButtonHeight
		FriendsScrollFrame.numFriendListEntries=addButtonIndex

		-- Clear SocialPlus search and restore full list
		function SocialPlus_ClearSearch()
			if SocialPlus_Searchbox then
				SocialPlus_Searchbox:SetText("")
				SocialPlus_Searchbox:ClearFocus()
			end
			SocialPlus_SearchTerm=nil
		end



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
	local addButtonIndex=0
	local totalButtonHeight=0
	local function AddButtonInfo(buttonType,id)
		addButtonIndex=addButtonIndex+1
		if not FriendButtons[addButtonIndex] then
			FriendButtons[addButtonIndex]={}
		end
		FriendButtons[addButtonIndex].buttonType=buttonType
		FriendButtons[addButtonIndex].id=id
		FriendButtons.count=FriendButtons.count+1
		totalButtonHeight=totalButtonHeight+FRIENDS_BUTTON_HEIGHTS[buttonType]
	end

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

	-- BNet friends (all) – MoP has no favorites, just online then offline
	for i=1,numBNetTotal do
		if not BnetSocialPlus[i] then
			BnetSocialPlus[i]={}
		end

		local t={FG_BNGetFriendInfo(i)}
		local isOnline=t[8] and true or false
		local noteText=t[13]

		BNetOnlineStatus[i]=isOnline
		NoteAndGroups(noteText,BnetSocialPlus[i])

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

	-- WoW friends online
	for i=1,numWoWOnline do
		if not WowSocialPlus[i] then
			WowSocialPlus[i]={}
		end
		local fi=FG_GetFriendInfoByIndex(i)
		local note=fi and fi.notes
		NoteAndGroups(note,WowSocialPlus[i])
		for group in pairs(WowSocialPlus[i]) do
			IncrementGroup(group,true)
			if not SocialPlus_SavedVars.collapsed[group] then
				buttonCount=buttonCount+1
				AddButtonInfo(FRIENDS_BUTTON_TYPE_WOW,i)
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
		for group in pairs(WowSocialPlus[j]) do
			IncrementGroup(group)
			if not SocialPlus_SavedVars.collapsed[group] and not SocialPlus_SavedVars.hide_offline then
				buttonCount=buttonCount+1
				AddButtonInfo(FRIENDS_BUTTON_TYPE_WOW,j)
			end
		end
	end

	-- Finally, add one button per group divider
	buttonCount=buttonCount+GroupCount
	totalScrollHeight=totalButtonHeight+GroupCount*FRIENDS_BUTTON_HEIGHTS[FRIENDS_BUTTON_TYPE_DIVIDER]

	FriendsScrollFrame.totalFriendListEntriesHeight=totalScrollHeight
	FriendsScrollFrame.numFriendListEntries=addButtonIndex

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

            local usePrioritize=SocialPlus_SavedVars and SocialPlus_SavedVars.prioritize_current_client

            if usePrioritize then
                ----------------------------------------------------------------
                -- “Prioritize MoP friends” ON:
                -- invite-tier sorting (inviteable → region → version → other game)
                ----------------------------------------------------------------
                local onlineRows={}

                -- BNet online
                for i=1,numBNetTotal do
                    if BnetSocialPlus[i] and BnetSocialPlus[i][group] and BNetOnlineStatus[i] then
                        local tier=SocialPlus_GetInviteTier("BNET",i)
                        onlineRows[#onlineRows+1]={
                            tier=tier,
                            buttonType=FRIENDS_BUTTON_TYPE_BNET,
                            id=i
                        }
                    end
                end

                -- WoW online
                for i=1,numWoWOnline do
                    if WowSocialPlus[i] and WowSocialPlus[i][group] then
                        local tier=SocialPlus_GetInviteTier("WOW",i)
                        onlineRows[#onlineRows+1]={
                            tier=tier,
                            buttonType=FRIENDS_BUTTON_TYPE_WOW,
                            id=i
                        }
                    end
                end

					local function SocialPlus_GetRowPriority(row)
					local kind
					if row.buttonType==FRIENDS_BUTTON_TYPE_BNET then
						kind="BNET"
					elseif row.buttonType==FRIENDS_BUTTON_TYPE_WOW then
						kind="WOW"
					else
						return 999 -- just in case
					end

					local allowed,_,restriction=SocialPlus_GetInviteStatus(kind,row.id)

					-- 1 = BNet WoW friend: can group, same project, same faction/region
					if allowed and restriction==INVITE_RESTRICTION_NONE and row.buttonType==FRIENDS_BUTTON_TYPE_BNET then
						return 1
					end

					-- 2 = WoW friend (non-BNet) that is groupable
					if allowed and restriction==INVITE_RESTRICTION_NONE and row.buttonType==FRIENDS_BUTTON_TYPE_WOW then
						return 2
					end

					-- 3 = same project but realm/region/project issues (still online WoW/BNet)
					if restriction==INVITE_RESTRICTION_REALM
					or restriction==INVITE_RESTRICTION_WOW_PROJECT_ID
					or restriction==INVITE_RESTRICTION_WOW_PROJECT_MAINLINE
					or restriction==INVITE_RESTRICTION_WOW_PROJECT_CLASSIC then
						return 3
					end

					-- 4 = everything else online (Battle.net app, other games, etc.)
					return 4
				end

                -- Sort by invite tier, then WoW > BNet, then id
				table.sort(onlineRows,function(a,b)
				local pa=SocialPlus_GetRowPriority(a)
				local pb=SocialPlus_GetRowPriority(b)

				if pa~=pb then
					return pa<pb
				end

				-- stable-ish within same priority
				if a.buttonType~=b.buttonType then
					return a.buttonType==FRIENDS_BUTTON_TYPE_BNET
				end

				return (a.id or 0)<(b.id or 0)
			end)


                -- Push sorted online rows
                for _,row in ipairs(onlineRows) do
                    index=index+1
                    FriendButtons[index].buttonType=row.buttonType
                    FriendButtons[index].id=row.id
                end

                -- Offline at the bottom
                if not SocialPlus_SavedVars.hide_offline then
                    -- BNet offline
                    for i=1,numBNetTotal do
                        if BnetSocialPlus[i] and BnetSocialPlus[i][group] and BNetOnlineStatus[i]==false then
                            index=index+1
                            FriendButtons[index].buttonType=FRIENDS_BUTTON_TYPE_BNET
                            FriendButtons[index].id=i
                        end
                    end

                    -- WoW offline
                    for i=numWoWOnline+1,numWoWTotal do
                        if WowSocialPlus[i] and WowSocialPlus[i][group] then
                            index=index+1
                            FriendButtons[index].buttonType=FRIENDS_BUTTON_TYPE_WOW
                            FriendButtons[index].id=i
                        end
                    end
                end
            else
                ----------------------------------------------------------------
                -- “Prioritize MoP friends” OFF:
                -- keep Blizzard-ish default order inside each group:
                --   1) BNet online (Blizzard index order, including favorites)
                --   2) WoW online
                --   3) BNet offline
                --   4) WoW offline
                ----------------------------------------------------------------

                -- BNet online in raw Blizzard order
                for i=1,numBNetTotal do
                    if BnetSocialPlus[i] and BnetSocialPlus[i][group] and BNetOnlineStatus[i] then
                        index=index+1
                        FriendButtons[index].buttonType=FRIENDS_BUTTON_TYPE_BNET
                        FriendButtons[index].id=i
                    end
                end

                -- WoW online in raw Blizzard order
                for i=1,numWoWOnline do
                    if WowSocialPlus[i] and WowSocialPlus[i][group] then
                        index=index+1
                        FriendButtons[index].buttonType=FRIENDS_BUTTON_TYPE_WOW
                        FriendButtons[index].id=i
                    end
                end

                if not SocialPlus_SavedVars.hide_offline then
                    -- BNet offline
                    for i=1,numBNetTotal do
                        if BnetSocialPlus[i] and BnetSocialPlus[i][group] and BNetOnlineStatus[i]==false then
                            index=index+1
                            FriendButtons[index].buttonType=FRIENDS_BUTTON_TYPE_BNET
                            FriendButtons[index].id=i
                        end
                    end

                    -- WoW offline
                    for i=numWoWOnline+1,numWoWTotal do
                        if WowSocialPlus[i] and WowSocialPlus[i][group] then
                            index=index+1
                            FriendButtons[index].buttonType=FRIENDS_BUTTON_TYPE_WOW
                            FriendButtons[index].id=i
                        end
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

-- [[ Menu: handle click on our new friend-group items ]]

local function SocialPlus_OnFriendMenuClick(self)
	if not self.value then
		return
	end

	local add=strmatch(self.value,"FGROUPADD_(.+)")
	local del=strmatch(self.value,"FGROUPDEL_(.+)")
	local creating=self.value=="SocialPlus_NEW"

	if add or del or creating then
		local dropdown=UIDROPDOWNMENU_INIT_MENU
		local source=OPEN_DROPDOWNMENUS_SAVE[1] and OPEN_DROPDOWNMENUS_SAVE[1].which or self.owner

		if source=="BN_FRIEND" or source=="BN_FRIEND_OFFLINE" then
			local note=select(13,FG_BNGetFriendInfoByID(dropdown.bnetIDAccount))
			if creating then
				StaticPopup_Show("SocialPlus_CREATE",nil,nil,{id=dropdown.bnetIDAccount,note=note,set=FG_SetBNetFriendNote})
			else
				if add then
					note=AddGroup(note,add)
				else
					note=RemoveGroup(note,del)
				end
				FG_SetBNetFriendNote(dropdown.bnetIDAccount,note)
			end
		elseif source=="FRIEND" or source=="FRIEND_OFFLINE" then
			for i=1,FG_GetNumFriends() do
				local friend_info=FG_GetFriendInfoByIndex(i)
				local name=friend_info.name
				local note=friend_info.notes
				if dropdown.name and name:find(dropdown.name) then
					if creating then
						StaticPopup_Show("SocialPlus_CREATE",nil,nil,{id=i,note=note,set=FG_SetFriendNotes})
					else
						if add then
							note=AddGroup(note,add)
						else
							note=RemoveGroup(note,del)
						end
						FG_SetFriendNotes(i,note)
					end
					break
				end
			end
		end
		SocialPlus_Update()
		SocialPlus_ClearSearch()
	end
	HideDropDownMenu(1)
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
	OnAccept=SocialPlus_Rename,
	EditBoxOnEnterPressed=function(self)
		local parent=self:GetParent()
		SocialPlus_Rename(parent,parent.data)
		parent:Hide()
	end,
	timeout=0,
	whileDead=1,
	hideOnEscape=1
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
	hideOnEscape=1
}

-- [[ Friend-note popup ]]	
StaticPopupDialogs["FRIEND_SET_NOTE"]={
	text=L.POPUP_NOTE_TITLE,
	button1=ACCEPT,
	button2=CANCEL,
	hasEditBox=1,
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
			pcall(data.set,data.id,eb:GetText())
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

	if kind=="WOW" then
		local fi=FG_GetFriendInfoByIndex(id)
		if fi and fi.name and fi.name~="" then
			return fi.name
		end
		return UNKNOWN
	end

	if kind=="BNET" then
		local accountName,characterName,class,level,isFavoriteFriend,isOnline,
		      bnetAccountId,client,canCoop,wowProjectID,lastOnline,
		      isAFK,isGameAFK,isDND,isGameBusy,mobile,zoneName,gameText,realmName=
		      GetFriendInfoById(id)

		if accountName and accountName~="" then
			return accountName
		end

		if characterName and characterName~="" then
			if realmName and realmName~="" then
				return characterName.."-"..realmName
			else
				return characterName
			end
		end

		return UNKNOWN
	end

	return UNKNOWN
end

-- [[ Generic dropdown separator helper ]]

local function SocialPlus_AddSeparator(level)
	local info=UIDropDownMenu_CreateInfo()
	info.disabled=true
	info.notCheckable=true
	info.icon="Interface\\Common\\UI-TooltipDivider-Transparent"
	info.iconOnly=true
	info.iconInfo={
		tCoordLeft=0,tCoordRight=1,tCoordTop=0,tCoordBottom=1,
		tSizeX=0,tSizeY=8,tFitDropDownSizeX=true
	}
	UIDropDownMenu_AddButton(info,level)
end

-- [[ Copy-character-name popup ]]

StaticPopupDialogs["SocialPlus_COPY_NAME"]={
    text=L.POPUP_COPY_TITLE,
    button1=OKAY,
    button2=CANCEL,
    hasEditBox=1,

    OnShow=function(self,data)
        local eb=self.editBox or self.EditBox
        if eb then
            eb:SetMaxLetters(64) -- allow full Character-Realm
        end
        if eb and data and data.name then
            eb:SetText(data.name)
            eb:HighlightText()
            eb:SetFocus()
        end

        -- NEW: close on Ctrl+C with a small delay to allow the copy to complete
        if eb then
            local prevOnKeyDown=eb:GetScript("OnKeyDown")
            eb:SetScript("OnKeyDown",function(editBox,key)
                if prevOnKeyDown then
                    prevOnKeyDown(editBox,key)
                end

                if IsControlKeyDown() and (key=="C" or key=="c") then
                    local popup=editBox:GetParent()
                    if popup and popup.Hide then
                        C_Timer.After(0.08,function()
                            popup:Hide()
                        end)
                    end
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

	local groups={}

	-- BNet friends
	for i=1,FG_BNGetNumFriends() do
		local t={FG_BNGetFriendInfo(i)}
		local noteText=t[13] or t[12] or nil
		local note=NoteAndGroups(noteText,groups)

			if groups[clickedgroup] then
			if invite then
				local accountInfo=C_BattleNet and C_BattleNet.GetFriendAccountInfo and C_BattleNet.GetFriendAccountInfo(i)
				if accountInfo and accountInfo.gameAccountInfo and accountInfo.gameAccountInfo.isOnline then
					local game=accountInfo.gameAccountInfo
					local characterName=game.characterName
					local realmName=game.realmName

					if characterName and characterName~="" then
						local target=characterName
						if realmName and realmName~="" then
							target=characterName.."-"..realmName
						end
						-- Skip invite if not allowed (opposite faction etc.)
						local allowed,reason = SocialPlus_GetInviteStatus("BNET", i)
						if allowed then
							pcall(InviteUnit,target)
						end
					end
				end
			else
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

			if groups[clickedgroup] then
			if invite and connected and name and name~="" then
				-- Skip invite if not allowed (opposite faction etc.)
				local allowed,reason = SocialPlus_GetInviteStatus("WOW", i)
				if allowed then
					pcall(InviteUnit,name)
				end
			elseif not invite then
				groups[clickedgroup]=nil
				local newNote=CreateNote(note,groups)
				FG_SetFriendNotes(i,newNote)
			end
		end
	end
end

-- [[ Group context menu (right-click group header) ]]

local SocialPlus_Menu=CreateFrame("Frame","SocialPlus_Menu")
SocialPlus_Menu.displayMode="MENU"

local menu_items={
	[1]={
		{text="",notCheckable=true,isTitle=true},
		{text=L.GROUP_INVITE_ALL,notCheckable=true,func=function(self,menu,clickedgroup) InviteOrGroup(clickedgroup,true) end},
		{text=L.GROUP_RENAME,notCheckable=true,func=function(self,menu,clickedgroup) StaticPopup_Show("SocialPlus_RENAME",nil,nil,clickedgroup) end},
		{text=L.GROUP_REMOVE,notCheckable=true,func=function(self,menu,clickedgroup) InviteOrGroup(clickedgroup,false) end},
        {text=L.GROUP_REORDER_AZ,notCheckable=true,func=function(self,menu,clickedgroup) SocialPlus_SortGroupsAlphabetically() end},
	},
	-- Settings are now in the left-side panel. This submenu is intentionally removed.
}

SocialPlus_Menu.initialize=function(self,level)
	if not menu_items[level] then return end

	-- Actual group key ("" means [no group])
	local groupKey=UIDROPDOWNMENU_MENU_VALUE
	local isNoGroup=(groupKey==nil or groupKey=="")

		for _,items in ipairs(menu_items[level]) do
		local info=UIDropDownMenu_CreateInfo()

		for prop,value in pairs(items) do
			-- Replace empty text with the current group label
			info[prop]=value~="" and value or (groupKey~="" and groupKey or L.GROUP_UNGROUPED)
		end
		-- Keep menu text static; slider popup shows the value

		info.arg1=groupKey
		info.arg2=groupKey

		-- When right-clicking [no group], only "Settings" should be usable
		if level==1 and isNoGroup then
			if info.text==L.GROUP_INVITE_ALL
				or info.text==L.GROUP_RENAME
				or info.text==L.GROUP_REMOVE then
				info.disabled=true
			end
		end

		UIDropDownMenu_AddButton(info,level)
	end
end

-- [[ Scroll speed popup UI ]]
local function SocialPlus_CreateScrollSpeedPopup()
	if SocialPlus_ScrollSpeedFrame then return end

	local f=CreateFrame("Frame","SocialPlus_ScrollSpeedFrame",UIParent,"BackdropTemplate")
	f:SetSize(340,110)
	f:SetPoint("CENTER",UIParent,"CENTER",0,0)
	f:SetBackdrop({bgFile="Interface\DialogFrame\UI-DialogBox-Background",edgeFile="Interface\DialogFrame\UI-DialogBox-Border",tile=false,tileSize=0,edgeSize=16,insets={left=8,right=8,top=6,bottom=6}})
	-- Solid dark background overlay to avoid transparency
	local bg = f:CreateTexture(nil, "BACKGROUND")
	bg:SetAllPoints(f)
	bg:SetColorTexture(0.06, 0.06, 0.06, 0.95)
	if type(f.SetBackdropBorderColor)=="function" then
		pcall(f.SetBackdropBorderColor,f,0.75,0.75,0.75,1)
	end
	f:SetMovable(true)
	f:EnableMouse(true)
	f:SetToplevel(true)

	f.title=f:CreateFontString(nil,"OVERLAY","GameFontHighlightLarge")
	f.title:SetPoint("TOP",f,"TOP",0,-8)
	f.title:SetText(L.SETTING_SCROLL_SPEED)

	f.desc=f:CreateFontString(nil,"OVERLAY","GameFontNormalSmall")
	f.desc:SetPoint("TOP",f.title,"BOTTOM",0,-6)
	f.desc:SetText(L.SETTING_SCROLL_SPEED_DESC)

	local slider=CreateFrame("Slider","SocialPlus_ScrollSpeedSlider",f,"OptionsSliderTemplate")
	slider:SetPoint("TOP",f.desc,"BOTTOM",0,-10)
	slider:SetSize(260,16)
	-- 1.0 to 5.0 range (0.1 steps) for smoother control
	slider:SetMinMaxValues(1.0,5.0)
	slider:SetValueStep(0.1)
	slider:SetObeyStepOnDrag(true)
	slider:SetValue(SocialPlus_SavedVars and SocialPlus_SavedVars.scrollSpeed or 2.2)

	slider.text = _G[slider:GetName().."Text"]
	if slider.text then slider.text:SetText(string.format("%.1f", slider:GetValue())) end

	-- low/high labels if template didn't create them
	if not _G[slider:GetName().."Low"] then
		local low = slider:CreateFontString(nil,"ARTWORK","GameFontNormalSmall")
		low:SetPoint("LEFT",slider,"LEFT",0,-18)
		low:SetText("1.0")
	end
	if not _G[slider:GetName().."High"] then
		local high = slider:CreateFontString(nil,"ARTWORK","GameFontNormalSmall")
		high:SetPoint("RIGHT",slider,"RIGHT",0,-18)
		high:SetText("5.0")
	end

	slider:SetScript("OnValueChanged",function(self,val)
		val = tonumber(val) or 1.0
		-- Snap to 0.1 increments
		val = math.floor(val*10+0.5)/10
		self:SetValue(val)
		if self.text then self.text:SetText(string.format("%.1f", val)) end
		-- Store as pending value; will be committed on OK / ENTER
		if f then
			f._pendingScrollSpeed = val
		end
	end)

	local ok=CreateFrame("Button",nil,f,"UIPanelButtonTemplate")
	ok:SetSize(100,22)
	ok:SetPoint("BOTTOMRIGHT",f,-12,12)
	ok:SetText(OKAY)
	ok:SetScript("OnClick",function()
		local val = f._pendingScrollSpeed or (tonumber(slider:GetValue()) or 2.2)
		val = math.floor(val*10+0.5)/10
		SocialPlus_SavedVars.scrollSpeed = val
		f:Hide()
	end)

	local cancel=CreateFrame("Button",nil,f,"UIPanelButtonTemplate")
	cancel:SetSize(100,22)
	cancel:SetPoint("BOTTOMLEFT",f,12,12)
	cancel:SetText(CANCEL)
	cancel:SetScript("OnClick",function()
		if f._pendingScrollSpeed then
			local current = SocialPlus_SavedVars and SocialPlus_SavedVars.scrollSpeed or 2.2
			slider:SetValue(current)
			f._pendingScrollSpeed = nil
		end
		f:Hide()
	end)

	-- Keyboard handling: ESC to cancel, ENTER to accept
	f:EnableKeyboard(true)
	f:SetScript("OnShow",function(self)
		-- try to focus slider for keyboard input; fallback gracefully
		pcall(function() slider:SetFocus() end)
		if type(self.SetPropagateKeyboardInput)=="function" then pcall(self.SetPropagateKeyboardInput,self,false) end
		self:SetScript("OnKeyDown",function(inner,key)
			if key=="ESCAPE" then
				self:Hide()
			elseif key=="ENTER" then
				local val = self._pendingScrollSpeed or (tonumber(slider:GetValue()) or 2.2)
				val = math.floor(val*10+0.5)/10
				SocialPlus_SavedVars.scrollSpeed = val
				self:Hide()
			end
		end)
		self:SetScript("OnHide",function(inner)
			inner:SetScript("OnKeyDown",nil)
			-- Revert slider to saved value if pending exists
			if inner._pendingScrollSpeed and inner._slider then
				local current = SocialPlus_SavedVars and SocialPlus_SavedVars.scrollSpeed or 2.2
				pcall(inner._slider.SetValue,inner._slider,current)
				inner._pendingScrollSpeed = nil
			end
		end)
	end)

	SocialPlus_ScrollSpeedFrame = f
	SocialPlus_ScrollSpeedFrame._slider = slider
	SocialPlus_ScrollSpeedFrame._ok = ok
	SocialPlus_ScrollSpeedFrame._cancel = cancel
end

function SocialPlus_ShowScrollSpeedPopup(group)
	SocialPlus_CreateScrollSpeedPopup()
	if not SocialPlus_ScrollSpeedFrame then return end
	local v = SocialPlus_SavedVars and SocialPlus_SavedVars.scrollSpeed or 1
	if SocialPlus_ScrollSpeedFrame._slider then
		SocialPlus_ScrollSpeedFrame._slider:SetValue(v)
		local txt = SocialPlus_ScrollSpeedFrame._slider.text
		if txt then txt:SetText(tostring(v)) end
	end
	SocialPlus_ScrollSpeedFrame._pendingScrollSpeed = v
	SocialPlus_ScrollSpeedFrame:Show()
end


-- [[ Preferences Panel (left-side) ]]
function SocialPlus_CreateSettingsButton()
	if SocialPlus_SettingsButton or not FriendsFrame then return end

	local btn=CreateFrame("Button","SocialPlus_SettingsButton",FriendsFrame)
	btn:SetSize(23,23)
	btn:SetPoint("TOPRIGHT",FriendsFrame,"TOPRIGHT",-10,-59)

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
			SocialPlus_SettingsPanel:SetShown(not SocialPlus_SettingsPanel:IsShown())
		end
	end)

	SocialPlus_SettingsButton=btn
end

function SocialPlus_CreateSettingsPanel()
	if SocialPlus_SettingsPanel or not FriendsFrame then return end

	local f=CreateFrame("Frame","SocialPlus_SettingsPanel",FriendsFrame,"BackdropTemplate")
	-- Slightly larger box
	f:SetSize(340,280)

	-- Right side of Friends frame
	f:SetPoint("TOPLEFT",FriendsFrame,"TOPRIGHT",8,-24)

	-- Tighter insets so the background fills closer to the border
	f:SetBackdrop({
    bgFile="Interface\\Tooltips\\UI-Tooltip-Background",
    edgeFile="Interface\\Tooltips\\UI-Tooltip-Border",
    tile=true, tileSize=16, edgeSize=16,
    insets={left=4,right=4,top=4,bottom=4}
})

	-- Dark, almost identical to the Friends panel
	f:SetBackdropColor(0.02,0.02,0.02,0.95)    -- inner fill
	f:SetBackdropBorderColor(0.3,0.3,0.3,1)    -- subtle grey border

	f:EnableMouse(true)
	f:SetToplevel(true)

	-- Title
	f.title=f:CreateFontString(nil,"OVERLAY","GameFontHighlightLarge")
	f.title:SetPoint("TOPLEFT",f,"TOPLEFT",14,-10)
	f.title:SetText(L.GROUP_SETTINGS)

	-- Close button (standard Blizzard X)
	local close = CreateFrame("Button","SocialPlus_SettingsCloseButton",f,"UIPanelCloseButton")
	close:SetPoint("TOPRIGHT",f,"TOPRIGHT",-4,-4)
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

	local hideLevel=CreateFrame("CheckButton","SocialPlus_HideMaxLevelCheck",f,"UICheckButtonTemplate")
	hideLevel:SetPoint("TOPLEFT",hideOffline,"BOTTOMLEFT",0,-6)
	_G[hideLevel:GetName().."Text"]:SetText(L.SETTING_HIDE_MAX_LEVEL)
	hideLevel:SetChecked(SocialPlus_SavedVars and SocialPlus_SavedVars.hide_high_level)
	hideLevel:SetScript("OnClick",function()
		SocialPlus_SavedVars.hide_high_level=not SocialPlus_SavedVars.hide_high_level
		SocialPlus_Update()
	end)

	local colourNames=CreateFrame("CheckButton","SocialPlus_ColourNamesCheck",f,"UICheckButtonTemplate")
	colourNames:SetPoint("TOPLEFT",hideLevel,"BOTTOMLEFT",0,-6)
	_G[colourNames:GetName().."Text"]:SetText(L.SETTING_COLOR_NAMES)
	colourNames:SetChecked(SocialPlus_SavedVars and SocialPlus_SavedVars.colour_classes)
	colourNames:SetScript("OnClick",function()
		SocialPlus_SavedVars.colour_classes=not SocialPlus_SavedVars.colour_classes
		SocialPlus_Update()
	end)

	-- NEW: prioritize current-client players (MoP Classic / same project)
	local prioritizeCurrent=CreateFrame("CheckButton","SocialPlus_PrioritizeCurrentClientCheck",f,"UICheckButtonTemplate")
	prioritizeCurrent:SetPoint("TOPLEFT",colourNames,"BOTTOMLEFT",0,-6)
	_G[prioritizeCurrent:GetName().."Text"]:SetText(L.SETTING_PRIORITIZE_CURRENT)
	prioritizeCurrent:SetChecked(SocialPlus_SavedVars and SocialPlus_SavedVars.prioritize_current_client)
	prioritizeCurrent:SetScript("OnClick",function()
		SocialPlus_SavedVars.prioritize_current_client = not SocialPlus_SavedVars.prioritize_current_client
		-- force full rebuild so ordering updates
		SocialPlus_Update(true)
	end)

	-- Separator spanning almost full width, now below the new setting
	local line=f:CreateTexture(nil,"ARTWORK")
	line:SetSize(f:GetWidth()-24,1)
	line:SetPoint("TOPLEFT",prioritizeCurrent,"BOTTOMLEFT",0,-12)

	line:SetColorTexture(0.6,0.6,0.6,0.4)

	-- Slider label + description
	local lbl=f:CreateFontString(nil,"ARTWORK","GameFontHighlightSmall")
	lbl:SetPoint("TOPLEFT",line,"BOTTOMLEFT",0,-10)
	lbl:SetText(L.SETTING_SCROLL_SPEED)

	local desc=f:CreateFontString(nil,"ARTWORK","GameFontNormalSmall")
	desc:SetPoint("TOPLEFT",lbl,"BOTTOMLEFT",0,-6)
	desc:SetText(L.SETTING_SCROLL_SPEED_DESC)

	-- Slider (moved a bit UP and widened)
	local slider=CreateFrame("Slider","SocialPlus_SettingsScrollSpeedSlider",f,"OptionsSliderTemplate")
	slider:SetPoint("TOPLEFT",desc,"BOTTOMLEFT",0,-5)
	slider:SetSize(f:GetWidth()-40,16)
	slider:SetMinMaxValues(1.0,5.0)
	slider:SetValueStep(0.1)
	slider:SetObeyStepOnDrag(true)
	slider:SetValue(SocialPlus_SavedVars and SocialPlus_SavedVars.scrollSpeed or 2.2)

	-- Center numeric value under slider
	slider.text=_G[slider:GetName().."Text"]
	if slider.text then
		slider.text:ClearAllPoints()
		slider.text:SetPoint("TOP",slider,"BOTTOM",0,-2)
		slider.text:SetJustifyH("CENTER")
		slider.text:SetText(string.format("%.1f",slider:GetValue()))
	end

	slider:SetScript("OnValueChanged",function(self,val)
		val=tonumber(val) or 2.2
		val=math.floor(val*10+0.5)/10
		self:SetValue(val)
		if self.text then
			self.text:SetText(string.format("%.1f",val))
		end
		SocialPlus_SavedVars.scrollSpeed=val
		pcall(SocialPlus_InitSmoothScroll)
	end)

	-- Sync on show
	f:SetScript("OnShow",function()
		hideOffline:SetChecked(SocialPlus_SavedVars and SocialPlus_SavedVars.hide_offline)
		hideLevel:SetChecked(SocialPlus_SavedVars and SocialPlus_SavedVars.hide_high_level)
		colourNames:SetChecked(SocialPlus_SavedVars and SocialPlus_SavedVars.colour_classes)
	    prioritizeCurrent:SetChecked(SocialPlus_SavedVars and SocialPlus_SavedVars.prioritize_current_client)
		slider:SetValue(SocialPlus_SavedVars and SocialPlus_SavedVars.scrollSpeed or 3.0)
	end)

	f:Hide()
	SocialPlus_SettingsPanel=f

	if FriendsFrame then
		FriendsFrame:HookScript("OnHide",function()
			if SocialPlus_SettingsPanel then SocialPlus_SettingsPanel:Hide() end
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

			-- Force list back to full view
			FriendsList_Update()
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
FriendsFrame:HookScript("OnShow", SocialPlus_UpdateFriendsTabVisibility)

hooksecurefunc("PanelTemplates_SetTab", function(frame, tabID)
	if frame == FriendsFrame then
		SocialPlus_UpdateFriendsTabVisibility()
	end
end)

-- [[ Friend (row) right-click menu state ]]

local SocialPlus_CurrentFriend=nil

local SocialPlus_FriendMenu=CreateFrame("Frame","SocialPlus_FriendMenu",UIParent,"UIDropDownMenuTemplate")
SocialPlus_FriendMenu.displayMode="MENU"

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
		SocialPlus_CurrentFriend.accountID=info[6] or info[2] or nil
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
		if not realmName or realmName=="" then return false end

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
	if WOW_PROJECT_ID and wowProjectID and wowProjectID~=WOW_PROJECT_ID then
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
    local baseText=L.MENU_MOVE_TO_GROUP or "Move to Another Group"
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
		info=UIDropDownMenu_CreateInfo()
		info.text=SocialPlus_GetMenuTitle()
		info.isTitle=true
		info.notCheckable=true
		info.disabled=true
		info.justifyH="LEFT"
		UIDropDownMenu_AddButton(info,level)

		-- Make the title a bit sharper
		do
			local listFrame=_G["DropDownList"..level]
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

		-- Set Note
		info=UIDropDownMenu_CreateInfo()
		info.text=L.MENU_SET_NOTE
		info.notCheckable=true
		info.func=function()
			local kind,id,note,setter=SocialPlus_GetDropdownFriendNote()
			if not kind or not id or not setter then return end
			StaticPopup_Show("FRIEND_SET_NOTE",nil,nil,{id=id,set=setter,note=note})
		end
		UIDropDownMenu_AddButton(info,level)

		-- View BNet friend's friends (Blizzard-style "View Friends")
		info=UIDropDownMenu_CreateInfo()
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
		UIDropDownMenu_AddButton(info,level)

		-- --- separator before Interact block
		SocialPlus_AddSeparator(level)

		-- Interact header
		info=UIDropDownMenu_CreateInfo()
		info.text=L.MENU_INTERACT
		info.isTitle=true
		info.notCheckable=true
		info.disabled=true
		UIDropDownMenu_AddButton(info,level)

		-- Invite / Suggest invite
		info=UIDropDownMenu_CreateInfo()

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
		UIDropDownMenu_AddButton(info,level)

		-- Whisper
		info=UIDropDownMenu_CreateInfo()
		info.text=L.MENU_WHISPER
		info.notCheckable=true
		info.func=function()
			local cf=SocialPlus_CurrentFriend
			if not cf then return end

			if cf.buttonType==FRIENDS_BUTTON_TYPE_WOW then
				local target=SocialPlus_GetFullCharacterName(cf)
				if target and target~="" then
					pcall(ChatFrame_SendTell,target)
				end
				return
			end

			if cf.buttonType==FRIENDS_BUTTON_TYPE_BNET then
				local index=cf.bnetIndex or cf.id
				local accountName=cf.accountName
				local accountID=cf.accountID

				if ((not accountName or accountName=="") or not accountID) then
					if index and C_BattleNet and C_BattleNet.GetFriendAccountInfo then
						local acc=C_BattleNet.GetFriendAccountInfo(index)
						if acc then
							accountName=accountName or acc.accountName
							accountID=accountID or acc.bnetAccountID
						end
					end
					if (not accountName or accountName=="") and BNGetFriendInfo and index then
						local t={BNGetFriendInfo(index)}
						local givenName=t[2]
						local surName=t[3]
						if givenName and surName and givenName~="" and surName~="" then
							accountName=givenName.." "..surName
						else
							accountName=givenName or surName or accountName
						end
					end
				end

				if accountID and C_ChatInfo and C_ChatInfo.SendBNetTell then
					pcall(C_ChatInfo.SendBNetTell,accountID)
					return
				end
				if accountName and accountName~="" and ChatFrame_SendBNetTell then
					pcall(ChatFrame_SendBNetTell,accountName)
					return
				end
				if accountName and accountName~="" then
					pcall(ChatFrame_SendTell,accountName)
				end
			end
		end
		UIDropDownMenu_AddButton(info,level)

		-- Copy character name
		info=UIDropDownMenu_CreateInfo()
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
		UIDropDownMenu_AddButton(info,level)

		-- --- separator before Groups section
		SocialPlus_AddSeparator(level)

		-- Groups section title
		info=UIDropDownMenu_CreateInfo()
		info.text=L.MENU_GROUPS
		info.isTitle=true
		info.notCheckable=true
		info.disabled=true
		UIDropDownMenu_AddButton(info,level)

		-- Does this friend already have a #Group tag?
		local hasGroup=SocialPlus_DropdownFriendHasGroup()

		-- Create group from this friend
		info=UIDropDownMenu_CreateInfo()
		info.text=L.MENU_CREATE_GROUP
		info.notCheckable=true
		info.disabled=hasGroup -- only for ungrouped friends
		info.func=SocialPlus_CreateGroupFromDropdown
		UIDropDownMenu_AddButton(info,level)

		-- Add / Move submenu
		info=UIDropDownMenu_CreateInfo()
		info.text=hasGroup and (L.MENU_MOVE_TO_GROUP or L.MENU_ADD_TO_GROUP) or L.MENU_ADD_TO_GROUP
		info.notCheckable=true
		info.hasArrow=true
		info.value="SocialPlus_ADD_SUB"
		info.disabled=false
		UIDropDownMenu_AddButton(info,level)

		-- Remove-from-group submenu
		info=UIDropDownMenu_CreateInfo()
		info.text=L.MENU_REMOVE_FROM_GROUP
		info.notCheckable=true
		info.hasArrow=true
		info.value="SocialPlus_DEL_SUB"
		UIDropDownMenu_AddButton(info,level)

        -- Separator before Other Options
        SocialPlus_AddSeparator(level)

        -- Other Options header
        info=UIDropDownMenu_CreateInfo()
        info.text=L.MENU_OTHER_OPTIONS
        info.isTitle=true
        info.notCheckable=true
        info.disabled=true
        UIDropDownMenu_AddButton(info,level)

        -- Remove Friend / Remove Battle.net Friend
        info=UIDropDownMenu_CreateInfo()
        info.notCheckable=true
        info.func=function()
            SocialPlus_RemoveCurrentFriend()
        end
        if cf and cf.buttonType==FRIENDS_BUTTON_TYPE_BNET then
            info.text=L.MENU_REMOVE_BNET
        else
            info.text=REMOVE_FRIEND
        end
        UIDropDownMenu_AddButton(info,level)

		-- After all level-1 buttons are added, enforce a minimum width
        SocialPlus_ApplyMenuMinWidth(level)

	elseif level==2 then
		if UIDROPDOWNMENU_MENU_VALUE=="SocialPlus_ADD_SUB" then
			SocialPlus_BuildGroupSubmenu("ADD",level)
		elseif UIDROPDOWNMENU_MENU_VALUE=="SocialPlus_DEL_SUB" then
			SocialPlus_BuildGroupSubmenu("DEL",level)
		end
	end
end


-- [[ FriendsFrame button hooks (click / tooltip / invite tooltip) ]]
local frame=CreateFrame("Frame")
frame:RegisterEvent("PLAYER_LOGIN")

local function SocialPlus_OnClick(self,button)
	if self.buttonType==FRIENDS_BUTTON_TYPE_DIVIDER then
		-- Use the raw group key; for General this is "" (ungrouped)
		local groupKey=self.SocialPlusGroupName or ""

		if button=="RightButton" then
			-- Still allow the header context menu everywhere
			ToggleDropDownMenu(1,groupKey,SocialPlus_Menu,"cursor",0,0)
		else
			-- General / ungrouped header cannot be collapsed at all
			if groupKey=="" then
				return
			end

			SocialPlus_SavedVars.collapsed[groupKey]=not SocialPlus_SavedVars.collapsed[groupKey]
			SocialPlus_Update()
		end
		return
	end


	if button~="RightButton" then
		if self.SocialPlus_OrigOnClick then
			return self.SocialPlus_OrigOnClick(self,button)
		end
		return
	end

	SocialPlus_SetCurrentFriend(self)
	ToggleDropDownMenu(1,nil,SocialPlus_FriendMenu,"cursor",0,0)
end

local function SocialPlus_OnEnter(self)
	-- Existing behavior: don’t show standard tooltip on group headers
	if self.buttonType==FRIENDS_BUTTON_TYPE_DIVIDER then
		if FriendsTooltip:IsShown() then
			FriendsTooltip:Hide()
		end
	end

	-- New: while dragging a group header, remember which group we’re hovering
	if SocialPlus_DragSourceGroup then
		local groupKey

		if self.buttonType==FRIENDS_BUTTON_TYPE_DIVIDER then
			groupKey=self.SocialPlusGroupName
		else
			groupKey=SocialPlus_GetGroupKeyFromRow(self)
		end

		SocialPlus_DragHoverGroup=groupKey
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


			btn:SetScript("OnClick",SocialPlus_OnClick)
			btn:HookScript("OnEnter",SocialPlus_OnEnter)
          
			if not btn.SocialPlus_OrigOnMouseUp then
                btn.SocialPlus_OrigOnMouseUp=btn:GetScript("OnMouseUp")
            end

            btn:SetScript("OnMouseUp",function(self,button)
                if SocialPlus_DragSourceGroup then
                    -- consume the mouse-up as a drop target
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
function SocialPlus_GetDropdownFriend()
	if SocialPlus_CurrentFriend and SocialPlus_CurrentFriend.id and SocialPlus_CurrentFriend.buttonType then
		if SocialPlus_CurrentFriend.buttonType==FRIENDS_BUTTON_TYPE_BNET then
			return "BNET",SocialPlus_CurrentFriend.id
		elseif SocialPlus_CurrentFriend.buttonType==FRIENDS_BUTTON_TYPE_WOW then
			return "WOW",SocialPlus_CurrentFriend.id
		end
	end

	local dropdown=FriendsFrameDropDown or UIDROPDOWNMENU_INIT_MENU
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

function SocialPlus_GetFriendRowButton(kind,id)
	if not kind or not id then return nil end
	local scrollFrame=FriendsScrollFrame
	if not scrollFrame or not scrollFrame.buttons then return nil end

	for _,button in ipairs(scrollFrame.buttons) do
		if button.buttonType and button.id then
			if kind=="BNET" and button.buttonType==FRIENDS_BUTTON_TYPE_BNET and button.id==id then
				return button
			elseif kind=="WOW" and button.buttonType==FRIENDS_BUTTON_TYPE_WOW and button.id==id then
				return button
			end
		end
	end

	return nil
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
	CloseDropDownMenus()
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
	CloseDropDownMenus()
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
	local dropdown=FriendsFrameDropDown or UIDROPDOWNMENU_INIT_MENU
	if not dropdown then return end

	local _,_,note=SocialPlus_GetDropdownFriendNote()
	local groups={}
	NoteAndGroups(note,groups)

	local choices={}

	if mode=="ADD" then
		for _,group in ipairs(GroupSorted or {}) do
			if group~="" and not groups[group] then
				table.insert(choices,group)
			end
		end
	else
		for group,present in pairs(groups) do
			if present and group~="" then
				table.insert(choices,group)
			end
		end
	end

	table.sort(choices)

	local info=UIDropDownMenu_CreateInfo()
		if #choices==0 then
		info.text=(mode=="ADD") and L.GROUP_NO_GROUPS or L.GROUP_NO_GROUPS_REMOVE
		info.notCheckable=true
		info.disabled=true
		UIDropDownMenu_AddButton(info,level)
		return
	end


	for _,group in ipairs(choices) do
		info=UIDropDownMenu_CreateInfo()
		info.text=group
		info.notCheckable=true
		info.func=function() SocialPlus_ModifyGroupFromDropdown(group,mode) end
		UIDropDownMenu_AddButton(info,level)
	end
end

-- [[ Friends dropdown hook installer ]]

local function SocialPlus_HookFriendsDropdown()
	if type(FriendsFrameDropDown_Initialize)=="function" and not SocialPlus_OriginalDropdownInit then
		SocialPlus_OriginalDropdownInit=FriendsFrameDropDown_Initialize
	end
end

-- [[ Initialization on PLAYER_LOGIN ]]

frame:SetScript("OnEvent",function(self,event,...)
	if event=="PLAYER_LOGIN" then
		FG_InitFactionIcon()

		Hook("FriendsList_Update",SocialPlus_Update,true)

		if FriendsFrameTooltip_Show then
			Hook("FriendsFrameTooltip_Show",SocialPlus_OnEnter,true)
		end

		Hook("FriendsFrame_ShowDropdown",SocialPlus_HookFriendsDropdown,true)
		FriendsScrollFrame.dynamic=SocialPlus_GetTopButton
		FriendsScrollFrame.update=SocialPlus_UpdateFriends

		if FriendsScrollFrame and FriendsScrollFrame.buttons and FriendsScrollFrame.buttons[1] and FRIENDS_FRAME_FRIENDS_FRIENDS_HEIGHT then
			pcall(FriendsScrollFrame.buttons[1].SetHeight,FriendsScrollFrame.buttons[1],FRIENDS_FRAME_FRIENDS_FRIENDS_HEIGHT)
		end
		if HybridScrollFrame_CreateButtons then
			pcall(HybridScrollFrame_CreateButtons,FriendsScrollFrame,FriendButtonTemplate)
		end

		HookButtons()

		-- Extra safety: force a clean repaint shortly after the Friends frame is shown.
		-- This fixes rare cases where the list draws with stale rows until the user scrolls.
		if FriendsFrame and not FriendsFrame.SocialPlusInitialRefreshHooked then
  		FriendsFrame.SocialPlusInitialRefreshHooked=true
 	    FriendsFrame:HookScript("OnShow",function()
        if FriendsList_Update and C_Timer and C_Timer.After then
            -- Use a short delay so Battle.net/WoW friend data has settled.
            C_Timer.After(0.08,function()
                pcall(FriendsList_Update)
            end)
        end
    end)
end

		if not SocialPlus_SavedVars then
    SocialPlus_SavedVars={
        collapsed={},
        hide_offline=false,
        colour_classes=true,
        hide_high_level=false,
        scrollSpeed=2.2,
        prioritize_current_client=true,
        groupOrder={}
 		  }
       end
	end
end)
