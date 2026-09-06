local ADDON_NAME, ns = ...
local L = ns.L

local LibDD = LibStub("LibUIDropDownMenu-4.0")

-- The who-list right-click menu, lifted out of SocialPlus.lua unchanged.
--
-- First slice of the split. Chosen because it is the least entangled thing in
-- the file: 140 lines at the very end, reaching outside itself for exactly five
-- names. Two of those are the locale table and the dropdown library, which any
-- file can take for itself from the two lines above; the other three were file
-- locals and are now globals, so not one call site had to change.

-- [[ Who-list right-click menu ]]
-- Blizzard's own who-row context menu cannot work correctly alongside this
-- addon: our renderer writes row-state fields (buttonType/id) on the SHARED
-- friends-list buttons, and Blizzard's secure panel-show update reads them
-- (FriendsFrame_ShouldShowSummonButton), tainting the execution that then
-- populates the who list -- from there every who context menu is born
-- tainted and its "Copy Character Name" (CopyToClipboard is blocked for
-- addon-tainted calls) throws ADDON_ACTION_FORBIDDEN blaming us (confirmed
-- via a full taintLog 11 trace: the who buttons' whoIndex fields are
-- written by a SocialPlus-tainted WhoList_Update run). Rather than rename
-- every shared field (a large refactor that would break the stock tooltip
-- helpers we reuse), own the who menu like we already own the friends-list
-- menus: our items need no protected calls -- Copy uses the same
-- Ctrl+C popup as the friend menu, which exists precisely because addons
-- can't call CopyToClipboard.
local SocialPlus_WhoMenu=LibDD:Create_UIDropDownMenu("SocialPlus_WhoMenu",UIParent)
SocialPlus_WhoMenu.displayMode="MENU"
local SocialPlus_WhoMenuName=nil
local SocialPlus_WhoMenuIndex=nil

-- Mirrors the stock who menu's layout: name title, Interact
-- (Invite/Whisper), Other Options (Ignore/Report Player/Copy Character
-- Name). IGNORE and REPORT_PLAYER are Blizzard's own globals, localized by
-- the client. Report uses the same PlayerLocation/ReportInfo primitives as
-- Blizzard's who menu (CreateFromWhoIndex + Enum.ReportType.InWorld).
SocialPlus_WhoMenu.initialize=function(self,level)
	if level~=1 then return end
	local name=SocialPlus_WhoMenuName
	local whoIndex=SocialPlus_WhoMenuIndex
	if not name then return end

	local info=LibDD:UIDropDownMenu_CreateInfo()
	info.text=name
	info.isTitle=true
	info.notCheckable=true
	LibDD:UIDropDownMenu_AddButton(info,level)

	-- Divider lines + Blizzard's own section-title globals, so the layout
	-- and wording match the stock who menu exactly in every locale.
	SocialPlus_AddSeparator(level)

	info=LibDD:UIDropDownMenu_CreateInfo()
	info.text=UNIT_FRAME_DROPDOWN_SUBSECTION_TITLE_INTERACT or L.MENU_INTERACT
	info.isTitle=true
	info.notCheckable=true
	LibDD:UIDropDownMenu_AddButton(info,level)

	info=LibDD:UIDropDownMenu_CreateInfo()
	info.text=L.MENU_INVITE
	info.notCheckable=true
	info.func=function()
		if C_PartyInfo and C_PartyInfo.InviteUnit then
			C_PartyInfo.InviteUnit(name)
		end
	end
	LibDD:UIDropDownMenu_AddButton(info,level)

	info=LibDD:UIDropDownMenu_CreateInfo()
	info.text=L.MENU_WHISPER
	info.notCheckable=true
	info.func=function()
		if ChatFrame_OpenChat then
			ChatFrame_OpenChat("/w "..name.." ")
		end
	end
	LibDD:UIDropDownMenu_AddButton(info,level)

	SocialPlus_AddSeparator(level)

	info=LibDD:UIDropDownMenu_CreateInfo()
	info.text=UNIT_FRAME_DROPDOWN_SUBSECTION_TITLE_OTHER or L.MENU_OTHER_OPTIONS
	info.isTitle=true
	info.notCheckable=true
	LibDD:UIDropDownMenu_AddButton(info,level)

	info=LibDD:UIDropDownMenu_CreateInfo()
	info.text=IGNORE
	info.notCheckable=true
	info.func=function()
		if C_FriendList and C_FriendList.AddIgnore then
			C_FriendList.AddIgnore(name)
		end
	end
	LibDD:UIDropDownMenu_AddButton(info,level)

	info=LibDD:UIDropDownMenu_CreateInfo()
	info.text=REPORT_PLAYER
	info.notCheckable=true
	info.disabled=not (whoIndex and PlayerLocation and ReportFrame and ReportInfo and Enum and Enum.ReportType)
	info.func=function()
		if not whoIndex then return end
		local ok,playerLocation=pcall(PlayerLocation.CreateFromWhoIndex,PlayerLocation,whoIndex)
		if not ok or not playerLocation then return end
		local ok2,reportInfo=pcall(ReportInfo.CreateReportInfoFromType,ReportInfo,Enum.ReportType.InWorld)
		if not ok2 or not reportInfo then return end
		pcall(ReportFrame.InitiateReport,ReportFrame,reportInfo,name,playerLocation,false)
	end
	LibDD:UIDropDownMenu_AddButton(info,level)

	info=LibDD:UIDropDownMenu_CreateInfo()
	info.text=L.MENU_COPY_NAME
	info.notCheckable=true
	info.func=function()
		StaticPopup_Show("SocialPlus_COPY_NAME",nil,nil,{name=name})
	end
	LibDD:UIDropDownMenu_AddButton(info,level)
end

-- Global, not local: SocialPlus.lua calls this from its PLAYER_LOGIN handler.
--
-- It was a file local, and moving it here made it invisible to that caller --
-- an unguarded call to a nil global, which threw at login and took the rest of
-- the handler with it. The who menu falling back to Blizzard's was the visible
-- half of that.
function SocialPlus_HookWhoButtons()
	local i=1
	while _G["WhoFrameButton"..i] do
		local whoBtn=_G["WhoFrameButton"..i]
		if not whoBtn.SocialPlusWhoHooked then
			whoBtn.SocialPlusWhoHooked=true
			local orig=whoBtn:GetScript("OnClick")
			whoBtn:SetScript("OnClick",function(btn,button)
				if button=="RightButton" then
					local info=btn.whoIndex and C_FriendList and C_FriendList.GetWhoInfo
						and C_FriendList.GetWhoInfo(btn.whoIndex)
					local nameFS=_G["WhoFrameButton"..btn:GetID().."Name"]
					local name=(info and info.fullName) or (nameFS and nameFS:GetText())
					if name and name~="" then
						SocialPlus_WhoMenuName=name
						SocialPlus_WhoMenuIndex=btn.whoIndex
						SocialPlus_PlayMenuOpenSound()
						LibDD:ToggleDropDownMenu(1,nil,SocialPlus_WhoMenu,"cursor",0,0)
						SocialPlus_ClickCatcherIsForMenu=true
						SocialPlus_ShowClickCatcher()
					end
					return
				end
				if orig then
					orig(btn,button)
				end
			end)
		end
		i=i+1
	end
end
