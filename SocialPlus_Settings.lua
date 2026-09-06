local ADDON_NAME, ns = ...
local L = ns.L

local LibDD = LibStub("LibUIDropDownMenu-4.0")

-- SCROLL_BASE is unprefixed, so it stays off the global namespace and comes
-- across on ns instead. Everything else this panel needs was already a
-- SocialPlus_-prefixed name and is now a global, which is what lets the two
-- frames it touches be created at runtime -- an ns snapshot taken at load
-- would have captured nil for both.
local SCROLL_BASE = ns.SCROLL_BASE

-- The same collapse artwork the friends list's own group headers use, so a
-- section here reads as the same kind of thing.
local TEX_PLUS  = "Interface\\Buttons\\UI-PlusButton-Up"
local TEX_MINUS = "Interface\\Buttons\\UI-MinusButton-Up"
local frame = ns.frame

-- The preferences panel, lifted out of SocialPlus.lua unchanged.
--
-- Fourth slice, and the biggest: 919 lines with nothing reaching back into it.
-- Picked by scoring every remaining section on exactly that -- what still needs
-- names declared inside it -- rather than on size or how separate it looks.

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
--
-- Built once, at load. It used to be built inside the function, and the row
-- renderer asks for a label for every cross-version friend on every render --
-- so a six-entry table was allocated and thrown away hundreds of times a
-- second on a large list. Safe to build at file scope because Locales.lua is
-- loaded ahead of this file (the `local L = ns.L` at the top depends on the
-- same thing) and the WOW_PROJECT_* globals exist before any addon runs.
local VERSION_LABELS={
	[WOW_PROJECT_MAINLINE or -1]=L.WOW_VERSION_RETAIL,
	[WOW_PROJECT_CLASSIC or -2]=L.WOW_VERSION_CLASSIC_ERA,
	[WOW_PROJECT_BURNING_CRUSADE_CLASSIC or -3]=L.WOW_VERSION_TBC,
	[WOW_PROJECT_WRATH_CLASSIC or -4]=L.WOW_VERSION_WOTLK,
	[WOW_PROJECT_CATACLYSM_CLASSIC or -5]=L.WOW_VERSION_CATA,
	[WOW_PROJECT_MISTS_CLASSIC or -6]=L.WOW_VERSION_MOP,
}
function SocialPlus_GetVersionLabelText(wowProjectID)
	return (wowProjectID and VERSION_LABELS[wowProjectID]) or "?"
end

-- The expansion phrases Blizzard's own free-text rich presence uses, with the
-- label and the project ID each one stands for.
--
-- wowProjectID can come back broken (0, not a real expansion) for a friend
-- whose structured game-account fields didn't fully resolve -- confirmed live
-- for multiple friends across different expansions. gameText (e.g. "Mists of
-- Pandaria Classic - Pagle") is generated independently of those broken fields
-- and is still correct, so it is what both recoveries below read.
--
-- One list, not two. The label recovery and the project-ID recovery used to
-- carry the same six phrases in the same order in separate tables, so every
-- phrase had to be added twice and the ordering rule had to hold in two
-- places -- and each was rebuilt on every call besides.
--
-- Order matters: longer, more specific phrases first, so "Wrath of the Lich
-- King Classic" is never caught by a broader entry.
local GAMETEXT_VERSIONS={
	-- Anniversary names itself, and never says "Burning Crusade": its rich
	-- presence reads "WoW Classic Anniversary - Spineshatter". Matching
	-- nothing here meant the caller fell through to printing that whole
	-- string as the row's second line, where "TBC (EU)" belongs.
	--
	-- Mapped to TBC because the Anniversary realms are on Burning Crusade;
	-- the client itself reports WOW_PROJECT_BURNING_CRUSADE_CLASSIC. If
	-- that line ever moves on, this is the entry that has to move with it.
	{"Classic Anniversary",L.WOW_VERSION_TBC,WOW_PROJECT_BURNING_CRUSADE_CLASSIC},
	{"Burning Crusade Classic",L.WOW_VERSION_TBC,WOW_PROJECT_BURNING_CRUSADE_CLASSIC},
	{"Wrath of the Lich King Classic",L.WOW_VERSION_WOTLK,WOW_PROJECT_WRATH_CLASSIC},
	{"Cataclysm Classic",L.WOW_VERSION_CATA,WOW_PROJECT_CATACLYSM_CLASSIC},
	{"Mists of Pandaria Classic",L.WOW_VERSION_MOP,WOW_PROJECT_MISTS_CLASSIC},
	{"Classic Era",L.WOW_VERSION_CLASSIC_ERA,WOW_PROJECT_CLASSIC},
	-- No Retail entry on purpose: retail's rich presence carries no "Classic"
	-- marker to match on, so it stays unrecovered rather than guessed at.
}

-- Our own clean label for a friend whose wowProjectID came back broken
-- (region gets appended separately by the caller), instead of a bare "?".
function SocialPlus_GetVersionLabelFromGameText(gameText)
	if not gameText or gameText=="" then return nil end
	for _,entry in ipairs(GAMETEXT_VERSIONS) do
		if gameText:find(entry[1],1,true) then
			return entry[2]
		end
	end
	return nil
end

-- The same recovery yielding the project ID itself rather than a display
-- string, so a broken wowProjectID can be repaired where it is READ instead
-- of every comparison site having to learn about it.
function SocialPlus_GetProjectIDFromGameText(gameText)
	if not gameText or gameText=="" then return nil end
	for _,entry in ipairs(GAMETEXT_VERSIONS) do
		-- Guarded: these constants are absent on some client families, and an
		-- absent one must not match everything via a nil comparison later.
		if entry[3] and gameText:find(entry[1],1,true) then
			return entry[3]
		end
	end
	return nil
end

-- Blizzard reports wowProjectID as 0 -- not a real expansion -- for friends
-- whose structured game-account fields didn't fully resolve (confirmed live:
-- WOW_PROJECT_ID 19 against a friend reporting 0 while playing that very
-- client). Because 0 is TRUTHY in Lua, the usual
-- "wowProjectID and wowProjectID ~= WOW_PROJECT_ID" guards read it as a
-- genuine mismatch rather than as missing data, so one broken field silently
-- cost that friend their faction crest, arena swords, prioritise sorting,
-- class-search matches and invite eligibility all at once.
--
-- Returns the value UNCHANGED when nothing can be recovered, so an
-- unidentifiable friend keeps today's behaviour instead of being optimistically
-- claimed as your own version.
function SocialPlus_RepairProjectID(wowProjectID,gameText)
	if wowProjectID and wowProjectID~=0 then return wowProjectID end
	return SocialPlus_GetProjectIDFromGameText(gameText) or wowProjectID
end

-- realmName goes missing on the same friends whose wowProjectID comes back 0,
-- and the rich presence carries it in the same breath: "Mists of Pandaria
-- Classic - Pagle". Confirmed live -- Blizzard's own tooltip renders that
-- string while the structured realmName reads nil.
--
-- Deliberately refuses to split anything whose leading half isn't a version
-- phrase we already recognise. Rich presence is free text and a friend's
-- status can legitimately contain " - "; without that guard this would
-- happily report the back half of an arbitrary sentence as a realm name.
function SocialPlus_GetRealmFromGameText(gameText)
	if not gameText or gameText=="" then return nil end
	if not SocialPlus_GetProjectIDFromGameText(gameText) then return nil end
	local realm=gameText:match("^.+%s+%-%s+(.+)$")
	if realm and realm~="" then return realm end
	return nil
end

function SocialPlus_RepairRealmName(realmName,gameText)
	if realmName and realmName~="" then return realmName end
	return SocialPlus_GetRealmFromGameText(gameText) or realmName
end

-- Tall enough for whatever is actually in it.
--
-- The height used to be a hand-kept number that every new setting had to
-- remember to bump -- "404, not 380" in the comment that used to sit here,
-- because the BattleTag tick pushed a row down. Settings were added and it was
-- not bumped, so the notifications block and the scroll slider drew outside the
-- panel, over the world, with no backdrop behind them.
--
-- Measured on show rather than at build time: a hidden frame has no reliable
-- rect to read, and the panel is created hidden. Regions are measured as well
-- as children, since the section headers are font strings rather than frames.
--
-- At file scope on purpose. It used to be declared at column 0 in the MIDDLE of
-- SocialPlus_CreateSettingsPanel, left there by an earlier edit -- legal Lua,
-- but it meant the global did not exist until the panel had been built once.
function SocialPlus_FitSettingsPanel(f)
	if not (f and f.GetTop) then return end
	local top=f:GetTop()
	if not top then return end

	local lowest=top
	local function consider(obj)
		if obj and obj.IsShown and obj:IsShown() and obj.GetBottom then
			local bottom=obj:GetBottom()
			if bottom and bottom<lowest then lowest=bottom end
		end
	end

	for _,child in ipairs({f:GetChildren()}) do
		consider(child)
		-- One level deeper as well.
		--
		-- A control's own label can hang BELOW it: the scroll slider carries its
		-- percentage anchored under its bottom edge. Measuring only the child
		-- stops at the slider and cuts that number off, which is what the
		-- hand-written "+20" in the old OnShow handler existed to paper over.
		if child.GetRegions then
			for _,region in ipairs({child:GetRegions()}) do consider(region) end
		end
	end
	for _,region in ipairs({f:GetRegions()}) do consider(region) end

	if lowest<top then f:SetHeight(top-lowest+14) end
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
	-- A starting size only. SocialPlus_FitSettingsPanel replaces the height
	-- with whatever the content needs, the first time the panel is shown.
	f:SetSize(500,404)

	-- Right side of Friends frame
	f:SetPoint("TOPLEFT",FriendsFrame,"TOPRIGHT",8,0)

	-- Reported live: a single tooltip-style backdrop reads as too
	-- transparent even at near-opaque alpha, compared to our own
	-- right-click menus. Traced it to LibUIDropDownMenu's "MENU" display
	-- mode actually layering TWO backdrops (Libs\LibUIDropDownMenu\
	-- LibUIDropDownMenu.lua, creatre_DropDownList): a dark dialog-box
	-- background underneath (BACKDROP_DIALOG_DARK), with the tooltip-tint
	-- backdrop on top of THAT -- not the tooltip backdrop alone. Replicate
	-- both layers, in the same order, for a visually identical result.
	f:SetBackdrop({
		bgFile="Interface\\DialogFrame\\UI-DialogBox-Background-Dark",
		edgeFile="Interface\\DialogFrame\\UI-DialogBox-Border",
		tile=true,tileEdge=true,tileSize=32,edgeSize=32,
		insets={left=11,right=12,top=12,bottom=11}
	})
	f:SetBackdropColor(0,0,0,1)
	f:SetBackdropBorderColor(1,1,1,1)

	-- Solid fill UNDER both backdrop layers.
	--
	-- Setting those layers to opaque black isn't enough on its own: the art
	-- itself (UI-DialogBox-Background-Dark, and the tooltip tint over it) is
	-- semi-transparent, so bright UI behind the panel still bleeds through --
	-- the same problem the friend tooltip had. Sublevel -8 keeps it beneath
	-- both, and the insets match the backdrop so the border art still frames it.
	local fSolid=f:CreateTexture(nil,"BACKGROUND",nil,-8)
	fSolid:SetPoint("TOPLEFT",f,"TOPLEFT",11,-12)
	fSolid:SetPoint("BOTTOMRIGHT",f,"BOTTOMRIGHT",-12,11)
	if fSolid.SetColorTexture then
		fSolid:SetColorTexture(0,0,0,1)
	else
		fSolid:SetTexture(0,0,0,1)
	end

	-- Second layer: the tooltip-tint backdrop this panel had on its own
	-- before, now on top of the dark dialog background instead of replacing
	-- it -- same BACKDROP_TOOLTIP_16_16_5555 shape/insets as the library.
	local fTint=CreateFrame("Frame",nil,f,"BackdropTemplate")
	fTint:SetAllPoints()
	-- CRITICAL: a new child FRAME defaults to one level above its parent,
	-- which put fTint's whole backdrop (even its BACKGROUND-layer texture)
	-- above everything f owns DIRECTLY as FontStrings -- title, version
	-- text, the "Notifications" header, the scroll-speed label/description
	-- -- since those live at f's own level, not a child frame's level.
	-- (The checkboxes were unaffected only because they're separate child
	-- frames created AFTER fTint, so they already sit above it too.)
	-- Pinning fTint to f's own level restores normal same-level draw-layer
	-- ordering (BACKGROUND behind OVERLAY), so it sits behind ALL of f's
	-- content as originally intended (reported live: several labels read
	-- as washed out/barely visible -- this was the actual cause, not their
	-- text color).
	fTint:SetFrameLevel(f:GetFrameLevel())
	fTint:SetBackdrop({
		bgFile="Interface\\Tooltips\\UI-Tooltip-Background",
		edgeFile="Interface\\Tooltips\\UI-Tooltip-Border",
		tile=true,tileEdge=true,tileSize=16,edgeSize=16,
		insets={left=5,right=5,top=5,bottom=5}
	})
	fTint:SetBackdropColor(TOOLTIP_DEFAULT_BACKGROUND_COLOR.r,TOOLTIP_DEFAULT_BACKGROUND_COLOR.g,TOOLTIP_DEFAULT_BACKGROUND_COLOR.b)
	fTint:SetBackdropBorderColor(TOOLTIP_DEFAULT_COLOR.r,TOOLTIP_DEFAULT_COLOR.g,TOOLTIP_DEFAULT_COLOR.b)

	f:EnableMouse(true)
	f:SetToplevel(true)
	-- Match LibUIDropDownMenu's dropdown list frames, which sit at DIALOG
	-- strata -- not just SetToplevel, which only reorders within a strata,
	-- so this also fixes HUD unit frames (target/focus) bleeding through.
	f:SetFrameStrata("DIALOG")

	-- Escape closes just this panel, not the whole Friends panel behind it.
	--
	-- Propagate first, keyboard only if granted, and asked again on show --
	-- see the drag ghost for why. This panel is built the first time it is
	-- opened, which can just as easily be in combat.
	-- Arm, ask, disarm if refused -- see the drag ghost for why this order and
	-- not the other one.
	f:EnableKeyboard(true)
	if not SocialPlus_SetPropagate(f,true) then f:EnableKeyboard(false) end
	f:HookScript("OnShow",function(self)
		self:EnableKeyboard(true)
		if not SocialPlus_SetPropagate(self,true) then self:EnableKeyboard(false) end
	end)
	f:SetScript("OnKeyDown",function(self,key)
		if key=="ESCAPE" then
			SocialPlus_SetPropagate(self,false)
			SocialPlus_PlayMenuCloseSound()
			self:Hide()
		else
			SocialPlus_SetPropagate(self,true)
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
		SocialPlus_PlayMenuCloseSound()
		f:Hide()
	end)

	-- Version, read from the .toc at load time so it always matches
	-- whatever's actually packaged -- never hardcoded, so this can't drift
	-- out of date on a new release. Right-aligned on the same axis as the
	-- title, just left of the close button. SocialPlus_GetAddonVersion
	-- handles both the C_AddOns/global API split and the unpackaged
	-- "1.13c" sentinel (returning nil for a dev build) -- see
	-- it for the full story on why that token can't be written literally.
	local addonVersion=SocialPlus_GetAddonVersion()
	if addonVersion then
		-- GameFontDisableSmall (WoW's "grayed out" style) carries its own
		-- dim alpha baked into the font object itself -- SetTextColor's RGB
		-- was correct but that baked-in alpha kept it faded regardless
		-- (reported live: still washed out even at full gold RGB).
		-- GameFontNormalSmall has no such override, so our color actually
		-- shows at full strength.
		f.versionText=f:CreateFontString(nil,"OVERLAY","GameFontNormalSmall")
		-- Anchored to the panel's own TOPRIGHT (same y as the title, -10)
		-- rather than relative to the close button's center -- that anchor
		-- put it too high and left too much of a gap next to the X
		-- (reported live).
		f.versionText:SetPoint("TOPRIGHT",f,"TOPRIGHT",-30,-10)
		f.versionText:SetJustifyH("RIGHT")
		f.versionText:SetText("v"..addonVersion)
		f.versionText:SetTextColor(1,0.82,0,1)
	end

	-- [[ Sections ]]
	--
	-- Every control used to hang off the one above it in a single unbroken
	-- chain -- fifteen ticks, four bracket boxes and a slider, top to bottom,
	-- with one section header somewhere in the middle. It read as a list rather
	-- than a panel, it grew taller than the frame it hangs beside, and the chain
	-- itself was the fragile part: three separate comments in this file recorded
	-- a row being added and everything below it drawing straight through the
	-- next section, because whatever had been anchored to the old last row
	-- stayed anchored there.
	--
	-- There are four blocks now, and one function anchors all of them. A block
	-- is a separator, a clickable header and an ordered list of controls;
	-- Relayout walks them in order and re-anchors every visible one. Adding a
	-- control is adding an entry to a list, and nothing below it has to be told.
	--
	-- Leaving one out is the same walk with fewer entries, which is what makes
	-- both collapsing and the ArenaPlus case work -- the latter used to be a
	-- hand-written re-anchoring pass inside UpdatePvPRatingsState, and is now
	-- one flag on one block.
	local blocks={}
	local blocksByKey={}

	local function IsCollapsed(key)
		local saved=SocialPlus_SavedVars and SocialPlus_SavedVars.settingsCollapsed
		return (saved and saved[key]) and true or false
	end

	local Relayout

	local function AddBlock(key,label)
		local block={key=key,label=label,widgets={},available=true}

		block.line=f:CreateTexture(nil,"ARTWORK")
		block.line:SetSize(f:GetWidth()-24,1)
		block.line:SetColorTexture(0.6,0.6,0.6,0.4)

		-- The whole header is the hit area, not just the little +/-. A 16px
		-- square is a small target for something meant to be clicked often, and
		-- the label beside it looks clickable whether or not it is.
		block.header=CreateFrame("Button",nil,f)
		block.header:SetSize(f:GetWidth()-28,18)

		block.toggle=block.header:CreateTexture(nil,"ARTWORK")
		block.toggle:SetSize(16,16)
		block.toggle:SetPoint("LEFT",block.header,"LEFT",0,0)

		block.text=block.header:CreateFontString(nil,"ARTWORK","GameFontNormal")
		block.text:SetPoint("LEFT",block.toggle,"RIGHT",2,0)
		block.text:SetText(label)

		block.header:SetScript("OnEnter",function()
			block.text:SetTextColor(1,1,1)
		end)
		block.header:SetScript("OnLeave",function()
			block.text:SetTextColor(NORMAL_FONT_COLOR:GetRGB())
		end)

		block.header:SetScript("OnClick",function()
			if not SocialPlus_SavedVars then return end
			SocialPlus_SavedVars.settingsCollapsed=SocialPlus_SavedVars.settingsCollapsed or {}
			-- nil rather than false when open, so the saved table only ever
			-- holds the sections somebody actually closed.
			SocialPlus_SavedVars.settingsCollapsed[key]=(not IsCollapsed(key)) or nil
			Relayout()
		end)

		blocks[#blocks+1]=block
		blocksByKey[key]=block
		return block
	end

	-- indent and gap are offsets from the PREVIOUS row, which is what the old
	-- hand-written chain used too -- so the bracket ticks step in by 18 once and
	-- the tick after them steps back out by the same 18.
	--
	-- cols forces a run of that many controls onto one row, for the bracket
	-- ticks: four boxes labelled "2v2".."RBG", which cost four full rows in a
	-- single column and carry about forty pixels of text between them.
	--
	-- pair=false keeps a control on a row of its own whatever it measures --
	-- the scroll slider and its description, which are not tick-shaped.
	local function AddControl(block,widget,indent,gap,cols,pair)
		block.widgets[#block.widgets+1]={
			widget=widget,indent=indent,gap=gap,cols=cols,pair=pair,
		}
		return widget
	end

	-- What a control actually needs across, box plus label.
	--
	-- Measured rather than assumed, and this is the whole reason the two-column
	-- layout below is safe to do at all: "Show BattleTags instead of real names"
	-- fits beside another tick in English and does not in Spanish, and nothing
	-- here has to know that. A label too wide for half the panel simply gets the
	-- whole row, in whatever language it is too wide in.
	local function ControlWidth(widget)
		local width=(widget.GetWidth and widget:GetWidth()) or 0
		local name=widget.GetName and widget:GetName()
		local text=(name and _G[name.."Text"]) or widget.label
		if text and text.GetStringWidth then
			width=width+text:GetStringWidth()+4
		end
		return width
	end

	function Relayout()
		local anchor,point=f.title,"BOTTOMLEFT"
		local headerGap=-14
		local inner=f:GetWidth()-28

		for _,block in ipairs(blocks) do
			if block.available then
				block.line:ClearAllPoints()
				block.line:SetPoint("TOPLEFT",anchor,point,0,headerGap)
				block.line:Show()

				block.header:ClearAllPoints()
				block.header:SetPoint("TOPLEFT",block.line,"BOTTOMLEFT",0,-6)
				block.header:Show()

				local collapsed=IsCollapsed(block.key)
				if collapsed then
					block.toggle:SetTexture(TEX_PLUS)
				else
					block.toggle:SetTexture(TEX_MINUS)
				end

				anchor,point=block.header,"BOTTOMLEFT"
				local gap=-2

				local widgets=block.widgets
				local i=1
				while i<=#widgets do
					local entry=widgets[i]

					if collapsed then
						entry.widget:Hide()
						i=i+1
					else
						-- How many controls share this row: what the entry
						-- asked for, or two where two will genuinely fit.
						local cols=entry.cols or 1
						if cols==1 then
							local follower=widgets[i+1]
							if entry.pair~=false and follower and follower.pair~=false
								and ControlWidth(entry.widget)<=inner/2
								and ControlWidth(follower.widget)<=inner/2 then
								cols=2
							end
						end

						local step=inner/cols
						local rowFirst
						for column=1,cols do
							local placed=widgets[i]
							if not placed then break end
							placed.widget:Show()
							placed.widget:ClearAllPoints()
							if column==1 then
								placed.widget:SetPoint("TOPLEFT",anchor,point,
									placed.indent or 0,placed.gap or gap)
								rowFirst=placed.widget
							else
								-- Off the row's first control, at a fixed step,
								-- rather than off the one to its left: label
								-- widths differ, and chaining left-to-right
								-- would leave the second column ragged.
								placed.widget:SetPoint("TOPLEFT",rowFirst,"TOPLEFT",
									(column-1)*step,0)
							end
							i=i+1
						end

						anchor,point=rowFirst,"BOTTOMLEFT"
						gap=-6
					end
				end

				headerGap=-12
			else
				-- A hidden frame keeps its anchors, so a block that is not
				-- available must not stay in the chain: nothing is anchored to
				-- it, and the next block anchors to whatever came before it.
				block.line:Hide()
				block.header:Hide()
				for _,entry in ipairs(block.widgets) do
					entry.widget:Hide()
				end
			end
		end

		SocialPlus_FitSettingsPanel(f)
	end

	----------------------------------------------------------------------
	-- Display
	----------------------------------------------------------------------
	local display=AddBlock("display",L.SETTING_SECTION_DISPLAY)

	local hideOffline=CreateFrame("CheckButton","SocialPlus_HideOfflineCheck",f,"UICheckButtonTemplate")
	_G[hideOffline:GetName().."Text"]:SetText(L.SETTING_HIDE_OFFLINE)
	hideOffline:SetScript("OnClick",function()
		SocialPlus_SavedVars.hide_offline=not SocialPlus_SavedVars.hide_offline
		SocialPlus_Update()
	end)
	AddControl(display,hideOffline)

	local showLevel=CreateFrame("CheckButton","SocialPlus_ShowLevelCheck",f,"UICheckButtonTemplate")
	_G[showLevel:GetName().."Text"]:SetText(L.SETTING_SHOW_LEVEL)
	showLevel:SetScript("OnClick",function()
		SocialPlus_SavedVars.show_level=not SocialPlus_SavedVars.show_level
		SocialPlus_Update()
	end)
	AddControl(display,showLevel)

	local colourNames=CreateFrame("CheckButton","SocialPlus_ColourNamesCheck",f,"UICheckButtonTemplate")
	_G[colourNames:GetName().."Text"]:SetText(L.SETTING_COLOR_NAMES)
	colourNames:SetScript("OnClick",function()
		SocialPlus_SavedVars.colour_classes=not SocialPlus_SavedVars.colour_classes
		SocialPlus_Update()
	end)
	AddControl(display,colourNames)

	-- Label names whichever WoW version this client actually is (MoP, TBC,
	-- etc.), not hardcoded to one, since the addon runs on several now.
	local prioritizeCurrent=CreateFrame("CheckButton","SocialPlus_PrioritizeCurrentClientCheck",f,"UICheckButtonTemplate")
	local currentVersionLabel=SocialPlus_GetVersionLabelText(WOW_PROJECT_ID)
	_G[prioritizeCurrent:GetName().."Text"]:SetText(
		L.SETTING_PRIORITIZE_PREFIX..currentVersionLabel..L.SETTING_PRIORITIZE_SUFFIX)
	prioritizeCurrent:SetScript("OnClick",function()
		SocialPlus_SavedVars.prioritize_current_client=not SocialPlus_SavedVars.prioritize_current_client
		-- force full rebuild so ordering updates
		SocialPlus_Update(true)
	end)
	AddControl(display,prioritizeCurrent)

	-- These two live here rather than under PvP, where they used to sit purely
	-- because that is where they had been added. Neither needs another addon --
	-- the flags ship here -- and both change what the NAME area of a row shows,
	-- which is what this section is. Moving them is also what lets the PvP
	-- block disappear whole: it used to have to stay behind and re-anchor
	-- upward over the hidden rows.
	local regionFlag=CreateFrame("CheckButton","SocialPlus_RegionFlagCheck",f,"UICheckButtonTemplate")
	_G[regionFlag:GetName().."Text"]:SetText(L.SETTING_REGION_FLAG)
	regionFlag:SetScript("OnClick",function()
		SocialPlus_SavedVars.region_flag=not SocialPlus_SavedVars.region_flag

		-- Redraw the list, or nothing changes until the rows happen to be
		-- rebuilt: they are pooled, and a row keeps whatever it was last given
		-- until something recycles it. Without this the tick appeared to do
		-- nothing until you scrolled far enough to reuse every row.
		SocialPlus_Update()
	end)
	AddControl(display,regionFlag)

	local battleTag=CreateFrame("CheckButton","SocialPlus_BattleTagCheck",f,"UICheckButtonTemplate")
	_G[battleTag:GetName().."Text"]:SetText(L.SETTING_BATTLETAG)
	battleTag:SetScript("OnClick",function()
		SocialPlus_SavedVars.show_battletag=not SocialPlus_SavedVars.show_battletag
		-- Same pooled-row reason as the flag above.
		SocialPlus_Update()
	end)
	AddControl(display,battleTag)

	----------------------------------------------------------------------
	-- PvP -- present only while ArenaPlus is there to answer
	----------------------------------------------------------------------
	--
	-- Both declared above everything that reads them.
	--
	-- UpdatePvPRatingsState is referred to by the tick's click handler, and
	-- bracketChecks is read inside UpdatePvPRatingsState -- a local declared
	-- further down is not the same name at all from up here, it is a global
	-- that happens to be nil, and the failure lands at runtime rather than at
	-- load. The same shape as calling a function before its definition, which
	-- is why ordercheck does not see it: nothing is being called.
	local UpdatePvPRatingsState
	local bracketChecks={}

	local pvp=AddBlock("pvp",L.SETTING_SECTION_PVP)

	local pvpRatings=CreateFrame("CheckButton","SocialPlus_PvPRatingsCheck",f,"UICheckButtonTemplate")
	_G[pvpRatings:GetName().."Text"]:SetText(L.SETTING_PVP_RATINGS)
	pvpRatings:SetScript("OnClick",function()
		SocialPlus_SavedVars.pvp_ratings=not SocialPlus_SavedVars.pvp_ratings
		UpdatePvPRatingsState()
		-- Nothing to rebuild: the tooltip reads the setting when it is next
		-- built, and the list itself is unchanged.
	end)
	AddControl(pvp,pvpRatings)

	-- One tick per bracket, indented under the switch they depend on.
	--
	-- Built in a loop rather than written out four times: the labels come from
	-- ArenaPlus's own BRACKETS table where it is installed, so the two cannot
	-- disagree about what bracket 4 is called.
	for bracket=1,4 do
		local check=CreateFrame("CheckButton",nil,f,"UICheckButtonTemplate")
		check:SetSize(20,20)
		check.bracket=bracket

		local names=_G.ArenaPlusAPI and _G.ArenaPlusAPI.BRACKETS
		local label=check:CreateFontString(nil,"OVERLAY","GameFontNormalSmall")
		label:SetPoint("LEFT",check,"RIGHT",2,0)
		label:SetText((names and names[bracket]) or tostring(bracket))
		check.label=label

		check:SetScript("OnClick",function(self)
			SocialPlus_SavedVars.pvp_brackets=type(SocialPlus_SavedVars.pvp_brackets)=="table"
				and SocialPlus_SavedVars.pvp_brackets or {}
			SocialPlus_SavedVars.pvp_brackets[self.bracket]=self:GetChecked() and true or nil
		end)

		bracketChecks[bracket]=check
		-- All four on one row: they are the narrowest controls on the panel and
		-- they used to cost four of its tallest rows.
		AddControl(pvp,check,bracket==1 and 18 or 0,-2,bracket==1 and 4 or nil)
	end

	local specIcon=CreateFrame("CheckButton","SocialPlus_PvPSpecIconCheck",f,"UICheckButtonTemplate")
	_G[specIcon:GetName().."Text"]:SetText(L.SETTING_PVP_SPEC_ICON)
	specIcon:SetScript("OnClick",function()
		SocialPlus_SavedVars.pvp_spec_icon=not SocialPlus_SavedVars.pvp_spec_icon
	end)
	-- Steps back out by the same 18 the bracket ticks stepped in by.
	AddControl(pvp,specIcon,-18,-4)

	----------------------------------------------------------------------
	-- Notifications
	----------------------------------------------------------------------
	local notify=AddBlock("notify",L.SETTING_SECTION_NOTIFICATIONS)

	local notifyEnable=CreateFrame("CheckButton","SocialPlus_NotifyEnableCheck",f,"UICheckButtonTemplate")
	_G[notifyEnable:GetName().."Text"]:SetText(L.SETTING_NOTIFY_ENABLE)
	AddControl(notify,notifyEnable)

	-- Sound sits directly under the "come online" toggle it belongs to, so
	-- the two online options read as a pair and "go offline" follows after.
	--
	-- Reproduces Blizzard's own friend online chime (SOUNDKIT.UI_BNET_TOAST),
	-- which this addon's chat-message notification doesn't otherwise come
	-- with -- the toast CVars this addon flips off only silence Blizzard's
	-- visual popup, not this.
	local notifySound=CreateFrame("CheckButton","SocialPlus_NotifySoundCheck",f,"UICheckButtonTemplate")
	_G[notifySound:GetName().."Text"]:SetText(L.SETTING_NOTIFY_SOUND)
	notifySound:SetScript("OnClick",function()
		SocialPlus_SavedVars.notifications.sound=not SocialPlus_SavedVars.notifications.sound
	end)
	AddControl(notify,notifySound)

	local notifyOffline=CreateFrame("CheckButton","SocialPlus_NotifyOfflineCheck",f,"UICheckButtonTemplate")
	_G[notifyOffline:GetName().."Text"]:SetText(L.SETTING_NOTIFY_OFFLINE)
	notifyOffline:SetScript("OnClick",function()
		SocialPlus_SavedVars.notifications.offline_too=not SocialPlus_SavedVars.notifications.offline_too
	end)
	AddControl(notify,notifyOffline)

	-- Only notify friends on this exact WoW version -- labelled dynamically
	-- like "Show WoW friends first" above. Off by default: most players
	-- still want notifications for every friend regardless of version,
	-- this is an opt-in filter for people who specifically don't want
	-- cross-version noise.
	local notifySameVersion=CreateFrame("CheckButton","SocialPlus_NotifySameVersionCheck",f,"UICheckButtonTemplate")
	_G[notifySameVersion:GetName().."Text"]:SetText(
		L.SETTING_NOTIFY_SAME_VERSION_PREFIX..currentVersionLabel..L.SETTING_NOTIFY_SAME_VERSION_SUFFIX)
	notifySameVersion:SetScript("OnClick",function()
		SocialPlus_SavedVars.notifications.same_version_only=not SocialPlus_SavedVars.notifications.same_version_only
	end)
	AddControl(notify,notifySameVersion)

	-- Child checkboxes only mean anything while the parent "notify when
	-- friends come online" toggle is on -- gray them out and disable
	-- interaction (but never touch their SavedVars) whenever it's off, so
	-- re-enabling the parent restores exactly what the user had before.
	local function SocialPlus_UpdateNotifyChildState()
		local enabled=SocialPlus_SavedVars and SocialPlus_SavedVars.notifications and SocialPlus_SavedVars.notifications.enabled
		for _,child in ipairs({notifyOffline,notifySameVersion,notifySound}) do
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

	----------------------------------------------------------------------
	-- Scrolling
	----------------------------------------------------------------------
	--
	-- The header carries the "Scroll speed" label the section used to repeat on
	-- its own line directly underneath it.
	local scroll=AddBlock("scroll",L.SETTING_SCROLL_SPEED)

	local desc=f:CreateFontString(nil,"ARTWORK","GameFontNormalSmall")
	desc:SetText(L.SETTING_SCROLL_SPEED_DESC)
	AddControl(scroll,desc,nil,nil,nil,false)

	local slider=CreateFrame("Slider","SocialPlus_SettingsScrollSpeedSlider",f,"OptionsSliderTemplate")
	slider:SetSize(f:GetWidth()-40,16)
	slider:SetMinMaxValues(1.0,5.0)
	slider:SetValueStep(0.1)
	slider:SetObeyStepOnDrag(true)
	slider:SetValue(SocialPlus_SavedVars and SocialPlus_SavedVars.scrollSpeed or SCROLL_BASE)
	-- A little more room than a tick row. Nothing sits above the slider -- its
	-- template's own label is moved below it just under this -- but its Low/High
	-- captions and that number all hang BELOW its bottom edge, so the slider
	-- needs to be clear of the description above it to look centred in its own
	-- space. The height those captions need is measured, not guessed: see the
	-- one-level-deeper pass in SocialPlus_FitSettingsPanel.
	AddControl(scroll,slider,0,-10,nil,false)

	-- Center numeric value under slider
	slider.text=_G[slider:GetName().."Text"]
	if slider.text then
		slider.text:ClearAllPoints()
		slider.text:SetPoint("TOP",slider,"BOTTOM",0,-2)
		slider.text:SetJustifyH("CENTER")
		slider.text:SetText(format("%d%%",slider:GetValue()/SCROLL_BASE*100))
	end

	slider:SetScript("OnValueChanged",function(self,val)
		val=tonumber(val) or SCROLL_BASE
		val=math.floor(val*10+0.5)/10
		self:SetValue(val)
		if self.text then
			self.text:SetText(format("%d%%",val/SCROLL_BASE*100))
		end
		if not SocialPlus_SavedVars then SocialPlus_SavedVars={} end
		SocialPlus_SavedVars.scrollSpeed=val
		pcall(SocialPlus_InitSmoothScroll)
	end)

	----------------------------------------------------------------------

	-- No "requires ArenaPlus" hover hint any more: it only ever appeared on the
	-- greyed checkbox, and the checkbox is now hidden outright in exactly that
	-- case, so the script could never run. L.SETTING_PVP_RATINGS_NEEDS is left
	-- in Locales.lua unused rather than deleted across three languages, in case
	-- the hint is wanted somewhere that can actually be seen.

	-- The whole block is absent unless ArenaPlus is there to answer, rather
	-- than greyed. These settings cannot do anything without it -- the tooltip
	-- guards every call into ArenaPlusAPI and simply draws no block -- and a
	-- greyed tick still takes up a line and still asks to be read before it can
	-- be dismissed, on a panel where most people will never install that addon.
	--
	-- Tested on the published table rather than on the addon being loaded: an
	-- ArenaPlus that is installed but disabled never runs its files and never
	-- creates it, which is the same thing as absent from here.
	--
	-- Defined after every widget it touches, deliberately. Three times now a
	-- widget has been added after it and come out nil -- a local declared below
	-- its reader is not that local at all. The forward declaration above is what
	-- lets the tick's own click handler still reach it.
	function UpdatePvPRatingsState()
		local ready=(_G.ArenaPlusAPI and _G.ArenaPlusAPI.GetLadder) and true or false

		-- One flag, and Relayout does the rest -- including re-measuring the
		-- panel, since rows have just appeared or disappeared and the content
		-- is the only thing that knows by how much.
		pvp.available=ready
		Relayout()

		-- With ArenaPlus present the bracket ticks still depend on the block
		-- above them being switched on: a tick that changes nothing is a tick
		-- that lies.
		local live=ready and SocialPlus_SavedVars and SocialPlus_SavedVars.pvp_ratings
		for _,check in ipairs(bracketChecks) do
			local wanted=SocialPlus_SavedVars and SocialPlus_SavedVars.pvp_brackets
			check:SetChecked(wanted and wanted[check.bracket] and true or false)

			if live then check:Enable() else check:Disable() end
			check.label:SetTextColor(live and 0.8 or 0.4,live and 0.8 or 0.4,live and 0.8 or 0.4)
		end
	end

	-- Every tick read back from SavedVars in one place.
	--
	-- They used to be re-read in two -- some here, some inside
	-- UpdatePvPRatingsState -- which is how a tick came to be synced by the
	-- function that hides it.
	local function SyncChecks()
		local sv=SocialPlus_SavedVars
		local notifications=sv and sv.notifications

		hideOffline:SetChecked(sv and sv.hide_offline)
		showLevel:SetChecked(sv and sv.show_level)
		colourNames:SetChecked(sv and sv.colour_classes)
		prioritizeCurrent:SetChecked(sv and sv.prioritize_current_client)
		regionFlag:SetChecked(sv and sv.region_flag)
		battleTag:SetChecked(sv and sv.show_battletag)

		pvpRatings:SetChecked(sv and sv.pvp_ratings)
		specIcon:SetChecked(sv and sv.pvp_spec_icon)

		notifyEnable:SetChecked(notifications and notifications.enabled)
		notifySound:SetChecked(notifications and notifications.sound)
		notifyOffline:SetChecked(notifications and notifications.offline_too)
		notifySameVersion:SetChecked(notifications and notifications.same_version_only)
		SocialPlus_UpdateNotifyChildState()

		local speed=(sv and sv.scrollSpeed) or SCROLL_BASE
		slider:SetValue(speed)
		if slider.text then
			slider.text:SetText(format("%d%%",speed/SCROLL_BASE*100))
		end
	end

	SyncChecks()
	-- Anchors everything for the first time; also re-tests ArenaPlus.
	UpdatePvPRatingsState()

	-- Hooked, not set.
	--
	-- SetScript REPLACES the handler, hooks and all. The keyboard re-arm above
	-- is installed with HookScript before this point, and it is installed onto
	-- nothing -- so it simply becomes the OnShow script, and a SetScript here
	-- threw it away. That is what this line used to be, which is why the panel
	-- never did ask for the keyboard again on a later open: first built during
	-- combat with propagation refused, Escape stopped closing it for the rest
	-- of the session, and nothing else re-armed it (OnKeyDown cannot, because
	-- the keyboard it would re-arm is the thing that is off).
	f:HookScript("OnShow",function()
		SyncChecks()
		-- Re-tested every time the panel opens, in case ArenaPlus was enabled.
		-- Relayout, and with it the height, comes along with it.
		UpdatePvPRatingsState()
	end)
	f:Hide()

	-- Sized on every open, not once: rows appear and disappear with ArenaPlus,
	-- and a frame that is hidden has no rect worth measuring.
	f:HookScript("OnShow",function(self) SocialPlus_FitSettingsPanel(self) end)

	SocialPlus_SettingsPanel=f

	if FriendsFrame then
		FriendsFrame:HookScript("OnHide",function()
			-- Our group/friend dropdown menus aren't parented to FriendsFrame,
			-- so closing the panel (e.g. via Escape) doesn't automatically
			-- close them, leaving an orphaned menu on screen. Close explicitly.
			LibDD:CloseDropDownMenus()

			-- WoW only fires OnEnter on actual mouse movement -- so
			-- reopening the panel with the cursor sitting still leaves the
			-- stale tooltip from whoever was hovered before showing, even
			-- though the row under the cursor may now be a different friend
			-- (list order can change while the panel's closed) (reported
			-- live). Clear it out on close so nothing stale can linger.
			SocialPlus_HideRowTooltip()

			-- Clear the highlighted friend on close too, so reopening the
			-- panel starts fresh with nobody selected instead of whoever
			-- was picked last time.
			SocialPlus_SelectedRow=nil

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

-- The search box shares its row with Blizzard's Friends/Ignore tabs, whose
-- width comes from the GAME client's locale, not ours. At a fixed 170 the box
-- left exactly 1px of clearance on a Spanish client (measured with /spgap:
-- "Amigos"/"Ignorar") and would overlap outright in a wordier locale.
--
-- So the width adapts: keep 170 when there's room, otherwise give the tabs
-- their space and shrink, down to a floor where the box is still usable. Runs
-- whenever the tab strip may have changed, since the tabs are laid out by
-- Blizzard and we only get to react.
function SocialPlus_LayoutSearchBox()
	if not (SocialPlus_Searchbox and FriendsFrame) then return end

	local PREFERRED,MINIMUM,GAP=170,104,8

	local frameRight=FriendsFrame:GetRight()
	if not frameRight then return end

	local rightmostTab=nil
	for i=1,4 do
		local tab=_G["FriendsTabHeaderTab"..i]
		if tab and tab:IsShown() then
			local r=tab:GetRight()
			if r and (not rightmostTab or r>rightmostTab) then rightmostTab=r end
		end
	end

	-- No tabs laid out yet (panel never shown): leave the preferred width.
	if not rightmostTab then
		SocialPlus_Searchbox:SetWidth(PREFERRED)
		return
	end

	-- -9 mirrors the TOPRIGHT inset the box is anchored with.
	local available=(frameRight-9)-(rightmostTab+GAP)
	local width=math.min(PREFERRED,math.max(MINIMUM,available))
	if math.floor(width+0.5)~=math.floor((SocialPlus_Searchbox:GetWidth() or 0)+0.5) then
		SocialPlus_Searchbox:SetWidth(width)
	end
end

local function SocialPlus_UpdateFriendsTabVisibility()
	if not FriendsFrame then return end
	-- Tabs may have just been re-laid out (shown, or switched); re-fit first so
	-- the box is never briefly overlapping them.
	SocialPlus_LayoutSearchBox()

	local tabID=PanelTemplates_GetSelectedTab(FriendsFrame) or FriendsFrame.selectedTab
	local isFriendsTab=(tabID==1)

	-- The Friends/Ignore sub-tabs at the top are a separate tab strip
	-- (FriendsTabHeader), independent of the bottom Friends/Who/Raid tabs.
	-- Search only applies to the friends list, so on the Ignore sub-tab
	-- the box stays visible but empty and disabled (greyed), instead of
	-- filtering a list it doesn't apply to.
	local headerTab=FriendsTabHeader
		and ((PanelTemplates_GetSelectedTab and PanelTemplates_GetSelectedTab(FriendsTabHeader)) or FriendsTabHeader.selectedTab)
	local searchUsable=isFriendsTab and (headerTab==nil or headerTab==1)

	-- Show/hide search box
	if SocialPlus_Searchbox then
		-- Whenever search doesn't apply (other bottom tab, or the Ignore
		-- sub-tab): clear it completely
		if not searchUsable then
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
		if searchUsable then
			SocialPlus_Searchbox:Enable()
			SocialPlus_Searchbox:SetAlpha(1)
		else
			SocialPlus_Searchbox:Disable()
			SocialPlus_Searchbox:SetAlpha(0.4)
		end
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
	if frame==FriendsFrame or (FriendsTabHeader and frame==FriendsTabHeader) then
		SocialPlus_UpdateFriendsTabVisibility()
	end
end)

-- Belt-and-suspenders for the header sub-tabs: FriendsFrame_Update is
-- Blizzard's central updater that runs on every tab switch of either
-- strip, so hooking it covers the Ignore sub-tab even if this client's
-- header tabs don't route through PanelTemplates_SetTab.
if type(FriendsFrame_Update)=="function" then
	hooksecurefunc("FriendsFrame_Update",SocialPlus_UpdateFriendsTabVisibility)
end
