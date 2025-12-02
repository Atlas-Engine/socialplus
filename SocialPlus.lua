local hooks = {}
local SocialPlus_OriginalDropdownInit

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
        L.MENU_COPY_NAME          = "Copier le nom du personnage"

        L.MENU_GROUPS             = "Groupes"
        L.MENU_CREATE_GROUP       = "Créer un groupe"
        L.MENU_ADD_TO_GROUP       = "Ajouter au groupe"
        L.MENU_REMOVE_FROM_GROUP  = "Retirer du groupe"

        L.MENU_OTHER_OPTIONS      = "Autres options"
        L.MENU_SET_NOTE           = "Définir une note"
        L.MENU_REMOVE_BNET        = "Retirer l’ami Bnet"

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
        L.GROUP_SETTINGS          = "Paramètres"
        L.GROUP_NO_GROUPS         = "Aucun groupe"
        L.GROUP_NO_GROUPS_REMOVE  = "Aucun groupe à retirer"

        ----------------------------------------------------------------
        -- Settings toggles (group submenu)
        ----------------------------------------------------------------
        L.SETTING_HIDE_OFFLINE      = "Masquer les hors ligne"
        L.SETTING_HIDE_MAX_LEVEL    = "Masquer les niveaux max"
        L.SETTING_COLOR_NAMES       = "Colorer les classes"

        ----------------------------------------------------------------
        -- Popup titles
        ----------------------------------------------------------------
        L.POPUP_RENAME_TITLE        = "Nom du groupe"
        L.POPUP_CREATE_TITLE        = "Nom du groupe"
        L.POPUP_NOTE_TITLE          = "Entrez une note pour cet ami"
        L.POPUP_COPY_TITLE          = "Nom du personnage (Ctrl+C pour copier) :"

        ----------------------------------------------------------------
        -- Extra messages
        ----------------------------------------------------------------
        L.MSG_INVITE_FAILED       = "Invitation impossible pour ce contact."
        L.MSG_INVITE_CROSSREALM   = "Invitation inter-royaume non disponible."
        L.INVITE_REASON_NOT_WOW       = "Cet ami n’est pas actuellement dans World of Warcraft."
        L.INVITE_REASON_WRONG_PROJECT = "Cet ami n’est pas sur votre version de WoW."
        L.INVITE_REASON_NO_REALM      = "Vous ne pouvez pas inviter cet ami car son royaume n’est pas disponible (probablement une autre région)."
        L.CONFIRM_REMOVE_BNET_TEXT = 'Êtes-vous sûr de vouloir retirer "%s" ?\n\nTapez "OUI." pour confirmer.'
		L.CONFIRM_REMOVE_BNET_WORD = "OUI."
        L.MSG_REMOVE_FRIEND_SUCCESS = 'Suppression de %s réussie.'
        L.INVITE_GENERIC_FAIL = "Vous ne pouvez pas inviter cet ami."
	else
		-- Default: English
        L.ADDON_NAME              = "SocialPlus"

        ----------------------------------------------------------------
        -- Interaction Menu
        ----------------------------------------------------------------
        L.MENU_INTERACT           = "Interact"
        L.MENU_WHISPER            = "Whisper"
        L.MENU_INVITE             = "Invite"
        L.MENU_COPY_NAME          = "Copy character name"

        L.MENU_GROUPS             = "Groups"
        L.MENU_CREATE_GROUP       = "Create group"
        L.MENU_ADD_TO_GROUP       = "Add to group"
        L.MENU_REMOVE_FROM_GROUP  = "Remove from group"

        L.MENU_OTHER_OPTIONS      = "Other Options"
        L.MENU_SET_NOTE           = "Set note"
        L.MENU_REMOVE_BNET        = "Remove Bnet friend"

        ----------------------------------------------------------------
        -- Search & grouping
        ----------------------------------------------------------------
        L.SEARCH_PLACEHOLDER      = "Search friends..."
        L.GROUP_UNGROUPED         = "General"

        ----------------------------------------------------------------
        -- Group menu (header right-click)
        ----------------------------------------------------------------
        L.GROUP_INVITE_ALL        = "Invite all to party"
        L.GROUP_RENAME            = "Rename group"
        L.GROUP_REMOVE            = "Remove group"
        L.GROUP_SETTINGS          = "Settings"
        L.GROUP_NO_GROUPS         = "No groups"
        L.GROUP_NO_GROUPS_REMOVE  = "No groups to remove"

        ----------------------------------------------------------------
        -- Settings toggles (group submenu)
        ----------------------------------------------------------------
        L.SETTING_HIDE_OFFLINE      = "Hide offline"
        L.SETTING_HIDE_MAX_LEVEL    = "Hide max-level"
        L.SETTING_COLOR_NAMES       = "Color class names"

        ----------------------------------------------------------------
        -- Popup titles
        ----------------------------------------------------------------
        L.POPUP_RENAME_TITLE        = "Group name"
        L.POPUP_CREATE_TITLE        = "Group name"
        L.POPUP_NOTE_TITLE          = "Enter a note for this friend"
        L.POPUP_COPY_TITLE          = "Character name (Ctrl+C to copy):"

        ----------------------------------------------------------------
        -- Extra messages
        ----------------------------------------------------------------
        L.MSG_INVITE_FAILED       = "Unable to invite this contact."
        L.MSG_INVITE_CROSSREALM   = "Cross-realm invite is not available."
        L.INVITE_REASON_NOT_WOW       = "This friend is not currently in World of Warcraft."
        L.INVITE_REASON_WRONG_PROJECT = "This friend is not on your WoW version."
        L.INVITE_REASON_NO_REALM      = "You cannot invite this friend because their realm is not available (likely another region)."
 		L.CONFIRM_REMOVE_BNET_TEXT = 'Are you sure you want to remove "%s"?\n\nType "YES." to confirm.'
		L.CONFIRM_REMOVE_BNET_WORD = "YES."
        L.MSG_REMOVE_FRIEND_SUCCESS = 'Successfully deleted %s.'
        L.INVITE_GENERIC_FAIL = "You cannot invite this friend."
	end
end

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

local ONE_MINUTE=60
local ONE_HOUR=60*ONE_MINUTE
local ONE_DAY=24*ONE_HOUR
local ONE_MONTH=30*ONE_DAY
local ONE_YEAR=12*ONE_MONTH

local FriendButtons={count=0}
local GroupCount=0
local GroupTotal={}
local GroupOnline={}
local GroupSorted={}

local FriendRequestString=string.sub(FRIEND_REQUESTS,1,-6)

local OPEN_DROPDOWNMENUS_SAVE=nil
local friend_popup_menus={"FRIEND","FRIEND_OFFLINE","BN_FRIEND","BN_FRIEND_OFFLINE"}

-- Dropdown integration disabled on MoP Classic to avoid tainting secure menus.
--[[
if type(UnitPopupButtons)=="table" and type(UnitPopupMenus)=="table" then
    UnitPopupButtons["SocialPlus_NEW"]={text="Create new group"}
    UnitPopupButtons["SocialPlus_ADD"]={text="Add to group",nested=1}
    UnitPopupButtons["SocialPlus_DEL"]={text="Remove from group",nested=1}
    UnitPopupMenus["SocialPlus_ADD"]={}
    UnitPopupMenus["SocialPlus_DEL"]={}
end
]]


local currentExpansionMaxLevel=90 -- MoP Classic cap
if type(GetMaxPlayerLevel)=="function" then
	currentExpansionMaxLevel=GetMaxPlayerLevel()
end

-------------------------------------------------
-- SocialPlus simple search (accent/symbol-insensitive)
-------------------------------------------------
local SP_SearchBox
local SP_SearchTerm=nil  -- always normalized or nil

-- Normalize text: lowercase, strip accents, remove non-alphanumerics
local function SP_NormalizeText(str)
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

local function SP_CreateSearchBox()
	if SP_SearchBox or not FriendsFrame then return end

	SP_SearchBox=CreateFrame("EditBox","SocialPlusSearchBox",FriendsFrame,"SearchBoxTemplate")
	SP_SearchBox:SetAutoFocus(false)

		-- Subtle neon glow around the search box
	local glow=CreateFrame("Frame",nil,SP_SearchBox,"BackdropTemplate")
	glow:SetFrameLevel(SP_SearchBox:GetFrameLevel()+2)
	glow:SetPoint("TOPLEFT",SP_SearchBox,-4,-1)
	glow:SetPoint("BOTTOMRIGHT",SP_SearchBox,-1,1)
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

SP_SearchGlow=glow
SP_SearchGlowOuter=outer



	-- Fixed, visible position near top-right
	SP_SearchBox:SetSize(170,20)
	SP_SearchBox:SetPoint("TOPRIGHT",FriendsFrame,"TOPRIGHT",-8,-63)
	SP_SearchBox.Instructions:SetText(L.SEARCH_PLACEHOLDER)
	local font,size,flags=SP_SearchBox:GetFont()
	SP_SearchBox:SetFont(font,size,flags)
	SP_SearchBox:SetTextColor(1,1,1)
	SP_SearchBox.Instructions:SetTextColor(0.8,0.8,0.8)
	SP_SearchBox:SetScript("OnTextChanged",function(self)
    SearchBoxTemplate_OnTextChanged(self)
    local txt=self:GetText() or ""
    txt=txt:match("^%s*(.-)%s*$") or ""

    local norm=SP_NormalizeText(txt)
    if norm=="" then
        SP_SearchTerm=nil
    else
        SP_SearchTerm=norm  -- already normalized (lowercase, no accents, no symbols)
    end	
        if SP_SearchGlow then
	if SP_SearchTerm then
		SP_SearchGlow:Show()
		if SP_SearchGlowOuter then SP_SearchGlowOuter:Show() end
	else
		SP_SearchGlow:Hide()
		if SP_SearchGlowOuter then SP_SearchGlowOuter:Hide() end
	end
	end


    FriendsList_Update()
	end)



	SP_SearchBox:SetScript("OnEscapePressed",function(self)
    self:SetText("")
    self:ClearFocus()
    SP_SearchTerm=nil
    if SP_SearchGlow then
        SP_SearchGlow:Hide()
    end
    FriendsList_Update()
	end)

end

-- Ensure it’s created when the UI is ready
local SP_SearchFrame=CreateFrame("Frame")
SP_SearchFrame:RegisterEvent("PLAYER_LOGIN")
SP_SearchFrame:RegisterEvent("ADDON_LOADED")
SP_SearchFrame:SetScript("OnEvent",function(_,event,addon)
	if event=="PLAYER_LOGIN" or addon=="Blizzard_FriendsFrame" then
		SP_CreateSearchBox()
		SP_InitSmoothScroll()
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

local function FG_ApplyGameIcon(button,iconPath,size,point,relPoint,offX,offY)
	if not iconPath or iconPath=="" or not button or not button.gameIcon then
		if button and button.gameIcon then
			button.gameIcon:Hide()
		end
		return
	end

	local icon=button.gameIcon
	icon:ClearAllPoints()

	size=size or 20
	point=point or "RIGHT"
	relPoint=relPoint or "RIGHT"
	offX=offX or -4
	offY=offY or 0

	icon:SetPoint(point,button,relPoint,offX,offY)
	icon:SetSize(size,size)
	icon:SetTexCoord(0,1,0,1)
	icon:SetTexture(iconPath)
	icon:Show()
end

-- Safe BNet client texture helper with MoP fallbacks
local function FG_GetClientTextureSafe(client)
	if BNet_GetClientTexture then
		local tex=BNet_GetClientTexture(client)
		if tex and tex~="" then
			return tex
		end
	end

	-- Generic fallbacks (paths exist in MoP)
	if client==BNET_CLIENT_WOW then
		return "Interface\\FriendsFrame\\Battlenet-WoWicon"
	else
		return "Interface\\FriendsFrame\\Battlenet-Battleneticon"
	end
end

local FriendsScrollFrame
local FriendButtonTemplate

if FriendsListFrameScrollFrame then
	FriendsScrollFrame=FriendsListFrameScrollFrame
	FriendButtonTemplate="FriendsListButtonTemplate"
else
	FriendsScrollFrame=FriendsFrameFriendsScrollFrame
	FriendButtonTemplate="FriendsFrameButtonTemplate"
end

-- [[ Smooth scroll inertia (adaptive, fast enough) ]]

local SP_ScrollAnim=nil

local function SP_ScrollOnUpdate(self,elapsed)
	if not SP_ScrollAnim or not SP_ScrollAnim.scrollBar then
		SP_ScrollAnim=nil
		self:SetScript("OnUpdate",nil)
		return
	end

	local a=SP_ScrollAnim
	a.t=a.t+elapsed
	local d=a.duration

	if a.t>=d then
		a.scrollBar:SetValue(a.to)
		SP_ScrollAnim=nil
		self:SetScript("OnUpdate",nil)
		return
	end

	-- Ease-out
	local x=a.t/d
	local alpha=1-(1-x)*(1-x)*(1-x)*(1-x)

	local value=a.from+(a.to-a.from)*alpha
	a.scrollBar:SetValue(value)
end

function SP_InitSmoothScroll()
	local frame=FriendsScrollFrame
	if not frame or not frame.scrollBar then return end

	frame:EnableMouseWheel(true)

	frame:SetScript("OnMouseWheel",function(self,delta)
		local sb=self.scrollBar
		if not sb then return end

		local min,max=sb:GetMinMaxValues()
		local current=sb:GetValue() or 0
		local range=max-min

		-- Adaptive step: about 8–10 wheel ticks from top to bottom
		local baseStep
		if range <= 400 then
  		  baseStep = 50      -- small list → give it a real step
		else
 		 baseStep = range/14
		end


		local target=current-delta*baseStep
		if target<min then target=min end
		if target>max then target=max end
		if target==current then return end

		SP_ScrollAnim={
			scrollBar=sb,
			from=current,
			to=target,
			t=0,
			duration=0.10, -- short, snappy
		}

		self:SetScript("OnUpdate",SP_ScrollOnUpdate)
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

local function FG_GetFriendInfoByIndex(index)
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

-- [[ Core per-row button update ]]
local function SocialPlus_UpdateFriendButton(button)
	local index=button.index
	button.buttonType=FriendButtons[index].buttonType
	button.id=FriendButtons[index].id
	local height=FRIENDS_BUTTON_HEIGHTS[button.buttonType]
	local nameText,nameColor,infoText,broadcastText,isFavoriteFriend
	local hasTravelPassButton=false
    local searchBlob="" -- text we will search in for this row
	-- Clear per-button friend metadata (used by custom menu)
	button.rawName=nil
	button.accountName=nil
	button.characterName=nil
	button.realmName=nil

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

			-- Faction icon when online
			if FACTION_ICON_PATH then
				FG_ApplyGameIcon(button,FACTION_ICON_PATH,50,"CENTER","RIGHT",-27,-9)
			elseif button.gameIcon then
				button.gameIcon:Hide()
			end

			-- Invite button for online non-BNet WoW friends
			hasTravelPassButton=true
			if button.travelPassButton then
				button.travelPassButton.fgInviteAllowed=true
				button.travelPassButton.fgInviteReason=nil
				button.travelPassButton:Enable()
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

			if client==BNET_CLIENT_WOW and wowProjectID==WOW_PROJECT_ID and hasRealm then
				if ga and ga.factionName then
					if ga.factionName=="Horde" then
						iconPath="Interface\\TargetingFrame\\UI-PVP-Horde"
					elseif ga.factionName=="Alliance" then
						iconPath="Interface\\TargetingFrame\\UI-PVP-Alliance"
					end
				end
				if not iconPath and FACTION_ICON_PATH then
					iconPath=FACTION_ICON_PATH
				end
			end

			if not iconPath then
				iconPath=FG_GetClientTextureSafe(client)
			end

			if type(iconPath)=="string" and iconPath:find("UI%-PVP%-") then
				FG_ApplyGameIcon(button,iconPath,50,"CENTER","RIGHT",-27,-9)
			else
				FG_ApplyGameIcon(button,iconPath,32,"RIGHT","RIGHT",-20,0)
			end

			nameColor=FRIENDS_BNET_NAME_COLOR
			local fadeIcon=(client==BNET_CLIENT_WOW) and (wowProjectID~=WOW_PROJECT_ID)
			button.gameIcon:SetAlpha(fadeIcon and 0.6 or 1)

			hasTravelPassButton=true

			local fgAllowed=true
			local fgReason=nil

			if client~=BNET_CLIENT_WOW then
			fgAllowed=false
			fgReason=L.INVITE_REASON_NOT_WOW
			elseif WOW_PROJECT_ID and wowProjectID and wowProjectID~=WOW_PROJECT_ID then
			fgAllowed=false
			fgReason=L.INVITE_REASON_WRONG_PROJECT
			end

			if fgAllowed and (not realmName or realmName=="") then
			fgAllowed=false
			fgReason=L.INVITE_REASON_NO_REALM
			end


			button.travelPassButton.fgInviteAllowed=fgAllowed
			button.travelPassButton.fgInviteReason=fgReason

			if fgAllowed then
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

		if SocialPlus_SavedVars.collapsed[group] then
			button.status:SetTexture("Interface\\Buttons\\UI-PlusButton-UP")
		else
			button.status:SetTexture("Interface\\Buttons\\UI-MinusButton-UP")
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

local function SocialPlus_Update(forceUpdate)
	local numBNetTotal,numBNetOnline,numBNetFavorite,numBNetFavoriteOnline=FG_BNGetNumFriends()
	numBNetFavorite=numBNetFavorite or 0
	numBNetFavoriteOnline=numBNetFavoriteOnline or 0
	local numBNetOffline=numBNetTotal-numBNetOnline
	local numBNetFavoriteOffline=numBNetFavorite-numBNetFavoriteOnline
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
	if SP_SearchTerm then
		wipe(FriendButtons)
		wipe(GroupTotal)
		wipe(GroupOnline)
		GroupCount=0


		local term=SP_SearchTerm -- already normalized (lowercase, no accents/symbols)
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
				local normalized=SP_NormalizeText(firstWord(primaryName))

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
				local searchName=SP_NormalizeText(firstWord(name))
				if startsWith(searchName,term) then
					AddButtonInfo(FRIENDS_BUTTON_TYPE_WOW,i)
				end
			end
		end

		FriendsScrollFrame.totalFriendListEntriesHeight=totalButtonHeight
		FriendsScrollFrame.numFriendListEntries=addButtonIndex

		-- Clear SocialPlus search and restore full list
		function SocialPlus_ClearSearch()
			if SP_SearchBox then
				SP_SearchBox:SetText("")
				SP_SearchBox:ClearFocus()
			end
			SP_SearchTerm=nil
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

	-- Favorite BNet friends online
	for i=1,numBNetFavoriteOnline do
		if not BnetSocialPlus[i] then
			BnetSocialPlus[i]={}
		end
		local noteText=select(13,FG_BNGetFriendInfo(i))
		NoteAndGroups(noteText,BnetSocialPlus[i])
		for group in pairs(BnetSocialPlus[i]) do
			IncrementGroup(group,true)
			if not SocialPlus_SavedVars.collapsed[group] then
				buttonCount=buttonCount+1
				AddButtonInfo(FRIENDS_BUTTON_TYPE_BNET,i)
			end
		end
	end

	-- Favorite BNet friends offline
	for i=1,numBNetFavoriteOffline do
		local j=i+numBNetFavoriteOnline
		if not BnetSocialPlus[j] then
			BnetSocialPlus[j]={}
		end
		local noteText=select(13,FG_BNGetFriendInfo(j))
		NoteAndGroups(noteText,BnetSocialPlus[j])
		for group in pairs(BnetSocialPlus[j]) do
			IncrementGroup(group)
			if not SocialPlus_SavedVars.collapsed[group] and not SocialPlus_SavedVars.hide_offline then
				buttonCount=buttonCount+1
				AddButtonInfo(FRIENDS_BUTTON_TYPE_BNET,j)
			end
		end
	end

	-- Online BNet friends (non-favorite)
	for i=1,numBNetOnline-numBNetFavoriteOnline do
		local j=i+numBNetFavorite
		if not BnetSocialPlus[j] then
			BnetSocialPlus[j]={}
		end
		local noteText=select(13,FG_BNGetFriendInfo(j))
		NoteAndGroups(noteText,BnetSocialPlus[j])
		for group in pairs(BnetSocialPlus[j]) do
			IncrementGroup(group,true)
			if not SocialPlus_SavedVars.collapsed[group] then
				buttonCount=buttonCount+1
				AddButtonInfo(FRIENDS_BUTTON_TYPE_BNET,j)
			end
		end
	end

	-- Online WoW friends
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

	-- Offline BNet friends (non-favorite)
	for i=1,numBNetOffline-numBNetFavoriteOffline do
		local j=i+numBNetFavorite+numBNetOnline-numBNetFavoriteOnline
		if not BnetSocialPlus[j] then
			BnetSocialPlus[j]={}
		end
		local noteText=select(13,FG_BNGetFriendInfo(j))
		NoteAndGroups(noteText,BnetSocialPlus[j])
		for group in pairs(BnetSocialPlus[j]) do
			IncrementGroup(group)
			if not SocialPlus_SavedVars.collapsed[group] and not SocialPlus_SavedVars.hide_offline then
				buttonCount=buttonCount+1
				AddButtonInfo(FRIENDS_BUTTON_TYPE_BNET,j)
			end
		end
	end

	-- Offline WoW friends
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
	table.sort(GroupSorted)

	if GroupSorted[1]=="" then
		table.remove(GroupSorted,1)
		table.insert(GroupSorted,"")
	end

	for key,val in pairs(GroupSorted) do
		if val==FriendRequestString then
			table.remove(GroupSorted,key)
			table.insert(GroupSorted,1,FriendRequestString)
		end
	end

	local index=0
	for _,group in ipairs(GroupSorted) do
		index=index+1
		FriendButtons[index].buttonType=FRIENDS_BUTTON_TYPE_DIVIDER
		FriendButtons[index].text=group
		if not SocialPlus_SavedVars.collapsed[group] then
			for i=1,#FriendReqGroup do
				if group==FriendRequestString then
					index=index+1
					FriendButtons[index].buttonType=FRIENDS_BUTTON_TYPE_INVITE
					FriendButtons[index].id=i
				end
			end
			for i=1,numBNetFavoriteOnline do
				if BnetSocialPlus[i][group] then
					index=index+1
					FriendButtons[index].buttonType=FRIENDS_BUTTON_TYPE_BNET
					FriendButtons[index].id=i
				end
			end
			for i=numBNetFavorite+1,numBNetOnline+numBNetFavoriteOffline do
				if BnetSocialPlus[i][group] then
					index=index+1
					FriendButtons[index].buttonType=FRIENDS_BUTTON_TYPE_BNET
					FriendButtons[index].id=i
				end
			end
			for i=1,numWoWOnline do
				if WowSocialPlus[i][group] then
					index=index+1
					FriendButtons[index].buttonType=FRIENDS_BUTTON_TYPE_WOW
					FriendButtons[index].id=i
				end
			end
			if not SocialPlus_SavedVars.hide_offline then
				for i=numBNetFavoriteOnline+1,numBNetFavorite do
					if BnetSocialPlus[i][group] then
						index=index+1
						FriendButtons[index].buttonType=FRIENDS_BUTTON_TYPE_BNET
						FriendButtons[index].id=i
					end
				end
				for i=numBNetOnline+numBNetFavoriteOffline+1,numBNetTotal do
					if BnetSocialPlus[i][group] then
						index=index+1
						FriendButtons[index].buttonType=FRIENDS_BUTTON_TYPE_BNET
						FriendButtons[index].id=i
					end
				end
				for i=numWoWOnline+1,numWoWTotal do
					if WowSocialPlus[i][group] then
						index=index+1
						FriendButtons[index].buttonType=FRIENDS_BUTTON_TYPE_WOW
						FriendButtons[index].id=i
					end
				end
			end
		end
	end
	FriendButtons.count=index

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
						pcall(InviteUnit,target)
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
				pcall(InviteUnit,name)
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
		{text=L.GROUP_INVITE_ALL
,notCheckable=true,func=function(self,menu,clickedgroup) InviteOrGroup(clickedgroup,true) end},
		{text=L.GROUP_RENAME,notCheckable=true,func=function(self,menu,clickedgroup) StaticPopup_Show("SocialPlus_RENAME",nil,nil,clickedgroup) end},
		{text=L.GROUP_REMOVE,notCheckable=true,func=function(self,menu,clickedgroup) InviteOrGroup(clickedgroup,false) end},
		{text=L.GROUP_SETTINGS,notCheckable=true,hasArrow=true},
	},
	[2]={
		{text=L.SETTING_HIDE_OFFLINE,checked=function() return SocialPlus_SavedVars.hide_offline end,func=function() CloseDropDownMenus() SocialPlus_SavedVars.hide_offline=not SocialPlus_SavedVars.hide_offline SocialPlus_Update() end},
		{text=L.SETTING_HIDE_MAX_LEVEL,checked=function() return SocialPlus_SavedVars.hide_high_level end,func=function() CloseDropDownMenus() SocialPlus_SavedVars.hide_high_level=not SocialPlus_SavedVars.hide_high_level SocialPlus_Update() end},
		{text=L.SETTING_COLOR_NAMES,checked=function() return SocialPlus_SavedVars.colour_classes end,func=function() CloseDropDownMenus() SocialPlus_SavedVars.colour_classes=not SocialPlus_SavedVars.colour_classes SocialPlus_Update() end},
	},
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

-- [[ Friend row dropdown (per-friend menu) ]]

SocialPlus_FriendMenu.initialize=function(self,level)
	level=level or 1
	if not SocialPlus_CurrentFriend then return end
	local info

	if level==1 then
		local cf=SocialPlus_CurrentFriend

		info=UIDropDownMenu_CreateInfo()
		info.text=SocialPlus_GetMenuTitle()
		info.isTitle=true
		info.notCheckable=true
		info.disabled=true
		info.justifyH="CENTER"
		UIDropDownMenu_AddButton(info,level)

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

		SocialPlus_AddSeparator(level)

		info=UIDropDownMenu_CreateInfo()
		info.text=L.MENU_INTERACT
		info.isTitle=true
		info.notCheckable=true
		info.disabled=true
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

		-- Invite
		info=UIDropDownMenu_CreateInfo()
		info.text=L.MENU_INVITE
		info.notCheckable=true

		local canInvite=SocialPlus_CanInviteMenuTarget()
		info.disabled=not canInvite

		info.func=function()
			if not SocialPlus_CanInviteMenuTarget() or not InviteUnit then return end

			local kind,id=SocialPlus_GetDropdownFriend()
			if not kind or not id then return end

			if kind=="WOW" then
				local fi=FG_GetFriendInfoByIndex(id)
				local target=fi and fi.name
				if target and target~="" then
					pcall(InviteUnit,target)
				end
			elseif kind=="BNET" then
				local accountName,characterName,class,level,isFavoriteFriend,
				      isOnline,bnetAccountId,client,canCoop,wowProjectID,_,_,_,_,_,_,_,realmName=
				      GetFriendInfoById(id)

				if characterName and characterName~="" then
					local target=characterName
					if realmName and realmName~="" then
						target=characterName.."-"..realmName
					end
					pcall(InviteUnit,target)
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

		SocialPlus_AddSeparator(level)

		info=UIDropDownMenu_CreateInfo()
		info.text=L.MENU_GROUPS
		info.isTitle=true
		info.notCheckable=true
		info.disabled=true
		UIDropDownMenu_AddButton(info,level)

		local hasGroup=SocialPlus_DropdownFriendHasGroup()
		info=UIDropDownMenu_CreateInfo()
		info.text=L.MENU_CREATE_GROUP
		info.notCheckable=true
		info.disabled=hasGroup
		info.func=SocialPlus_CreateGroupFromDropdown
		UIDropDownMenu_AddButton(info,level)

		info=UIDropDownMenu_CreateInfo()
		info.text=L.MENU_ADD_TO_GROUP
		info.notCheckable=true
		info.hasArrow=true
		info.value="SocialPlus_ADD_SUB"
		info.disabled=hasGroup
		UIDropDownMenu_AddButton(info,level)

		info=UIDropDownMenu_CreateInfo()
		info.text=L.MENU_REMOVE_FROM_GROUP
		info.notCheckable=true
		info.hasArrow=true
		info.value="SocialPlus_DEL_SUB"
		UIDropDownMenu_AddButton(info,level)

		SocialPlus_AddSeparator(level)

		info=UIDropDownMenu_CreateInfo()
		info.text=L.MENU_OTHER_OPTIONS
		info.isTitle=true
		info.notCheckable=true
		info.disabled=true
		UIDropDownMenu_AddButton(info,level)

		info=UIDropDownMenu_CreateInfo()
		info.text=L.MENU_SET_NOTE
		info.notCheckable=true
		info.func=function()
			local kind,id,note,setter=SocialPlus_GetDropdownFriendNote()
			if not kind or not id or not setter then return end
			StaticPopup_Show("FRIEND_SET_NOTE",nil,nil,{id=id,set=setter,note=note})
		end
		UIDropDownMenu_AddButton(info,level)

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
		local group=self.info and self.info:GetText() or ""
		if button=="RightButton" then
			ToggleDropDownMenu(1,group,SocialPlus_Menu,"cursor",0,0)
		else
			SocialPlus_SavedVars.collapsed[group]=not SocialPlus_SavedVars.collapsed[group]
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
	if self.buttonType==FRIENDS_BUTTON_TYPE_DIVIDER then
		if FriendsTooltip:IsShown() then
			FriendsTooltip:Hide()
		end
		return
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

			if not FriendsFrameTooltip_Show then
				btn:HookScript("OnEnter",SocialPlus_OnEnter)
			end

			local travel=btn.travelPassButton
			if travel and not travel.FG_TooltipHooked then
				travel.FG_TooltipHooked=true

				travel:HookScript("OnEnter",function(self)
					if not GameTooltip then return end
					GameTooltip:SetOwner(self,"ANCHOR_RIGHT")
					local title=INVITE or "Invite"

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
		newNote=AddGroup(baseNote,group)
	else
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

		if not SocialPlus_SavedVars then
			SocialPlus_SavedVars={
				collapsed={},
				hide_offline=false,
				colour_classes=true,
				hide_high_level=false
			}
		end
	end
end)