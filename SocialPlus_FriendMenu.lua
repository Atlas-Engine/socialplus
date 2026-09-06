local ADDON_NAME, ns = ...
local L = ns.L

local LibDD = LibStub("LibUIDropDownMenu-4.0")

-- NoteAndGroups and RemoveGroup are unprefixed, so they come across on ns
-- rather than joining the global namespace. Everything else this menu needs
-- was already SocialPlus_- or FG_-prefixed and is a global now.
local NoteAndGroups = ns.NoteAndGroups
local RemoveGroup = ns.RemoveGroup

-- The per-friend right-click menu, lifted out of SocialPlus.lua unchanged.
--
-- Fifth slice. 344 lines, nothing reaching back into it, and every one of its
-- sixteen dependencies read-only -- so nothing here needs a global purely to
-- carry a write back across the boundary.

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
			local kind,id,note,setter,presenceID=SocialPlus_GetDropdownFriendNote()
			if not kind or not id or not setter then return end
			local groups={}
			local baseNote=NoteAndGroups(note,groups)

			-- presenceID travels with the popup: the friend is decided when the
			-- menu is opened, not when Accept is pressed, and the list index can
			-- belong to somebody else by then.
			StaticPopup_Show("FRIEND_SET_NOTE",nil,nil,
				{kind=kind,id=id,set=setter,note=baseNote,groups=groups,presenceID=presenceID})
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
			-- Re-resolve by presenceID, same reasoning as every other item
			-- here -- the raw index captured when the menu opened can go
			-- stale if the list reindexes before this item is clicked.
			local kind,index=SocialPlus_GetDropdownFriend()
			if kind~="BNET" or not index or not BNGetFriendInfo then return end

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
			-- Re-resolve by stable identity (BNet presenceID / WoW character
			-- name), same as the Invite item above -- NOT the raw index
			-- captured when the menu was opened. The friends list can
			-- reindex between opening this menu and clicking an item in it
			-- (e.g. a FriendsList_Update from scrolling, or someone else's
			-- online status changing), which silently repoints a stale raw
			-- index at a completely different friend (reported live: right-
			-- clicking one friend and choosing Whisper messaged a different
			-- one entirely).
			local kind,id=SocialPlus_GetDropdownFriend()
			if not kind or not id then return end
			local resolvedType=(kind=="BNET") and FRIENDS_BUTTON_TYPE_BNET or FRIENDS_BUTTON_TYPE_WOW

			-- Don't touch the chat edit box or its attributes ourselves -- that's
			-- what was tainting the shared Menu system and blocking unrelated
			-- "Copy Name" clicks afterward. Instead, just set the same plain
			-- (non-protected) selection fields Blizzard's own Friends UI uses,
			-- then let Blizzard's own button handler do all the actual work.
			-- This is the same handler the default UI calls for both WoW and
			-- BNet friends, so it covers both cases.
			FriendsFrame.selectedFriendType=resolvedType
			FriendsFrame.selectedFriend=id
			SocialPlus_SelectedRow={buttonType=resolvedType,id=id,identityKey=SocialPlus_GetRowIdentityKey(resolvedType,id)}

			FG_Debug("Whisper via FriendsFrameSendMessageButton_OnClick","buttonType="..tostring(resolvedType),"index="..tostring(id))

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

		-- Offered whether or not they are already in a group. It used to be
		-- greyed out for anyone who had one, which meant making a new group
		-- around an existing friend took three steps: create it from somebody
		-- ungrouped, then move the friend you actually wanted, then tidy up.
		-- Creating a group from a grouped friend moves them into it, since a
		-- friend belongs to one group at a time.
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
