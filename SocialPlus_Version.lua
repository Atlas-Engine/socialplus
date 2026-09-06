local ADDON_NAME, ns = ...
local L = ns.L

-- Taken off ns rather than promoted to a global: the name is unprefixed and
-- the global namespace belongs to everybody. Aliased to a local here so the
-- moved code below reads exactly as it did in SocialPlus.lua.
local GetFriendInfoById = ns.GetFriendInfoById

-- The out-of-date version alert, lifted out of SocialPlus.lua unchanged.
--
-- Second slice of the split. It reaches outside itself for five names and
-- nothing outside reaches back in, so the dependency runs one way only -- which
-- is what makes a seam safe to cut rather than merely convenient.

-- [[ Out-of-date version alert ]]
--
-- Same idea as Bagnon's: broadcast our own version over the addon-message
-- channel, and if another player reports a HIGHER one, tell the user once
-- that theirs might be out of date. Everything here is deliberately
-- best-effort -- a failed/unavailable comm API must never break the addon,
-- so every call is guarded and every unparseable version is ignored rather
-- than guessed at.
--
-- Declared as globals (not top-level locals) on purpose: this file's main
-- chunk is already at Lua's 200-local ceiling (see the tooltip helpers for
-- the same constraint).

-- Addon message prefixes are capped at 16 characters.
SOCIALPLUS_VERSION_PREFIX="SocialPlusVer"

-- Only ever warn once per session, however many people report a newer build.
SocialPlus_VersionAlertShown=false

-- Our own version, straight from the .toc, or nil when running unpackaged.
--
-- The packager substitutes "1.13c" with the real tag across
-- EVERY packaged file -- so the sentinel we compare against has to be built
-- from pieces, or it gets substituted too and the comparison silently
-- becomes 'version ~= version' (this exact self-defeating bug shipped once
-- already, see the settings panel's version text). Returning nil for the
-- unpackaged case keeps a dev build from ever broadcasting or reacting to
-- the literal token.
function SocialPlus_GetAddonVersion()
	local version
	-- Try the modern C_AddOns namespace first -- this client's version of
	-- the old global may be absent, in which case a bare
	-- "GetAddOnMetadata and GetAddOnMetadata(...)" guard silently skips.
	if C_AddOns and C_AddOns.GetAddOnMetadata then
		version=C_AddOns.GetAddOnMetadata(ADDON_NAME,"Version")
	elseif GetAddOnMetadata then
		version=GetAddOnMetadata(ADDON_NAME,"Version")
	end
	local unpackagedToken="@".."project-version".."@"
	if not version or version=="" or version==unpackagedToken then
		return nil
	end
	return version
end

-- "1.10c" -> 1, 10, "c". Returns nil for anything that isn't our exact
-- release format, so a malformed or foreign version string can never
-- produce a bogus "you're outdated" warning.
function SocialPlus_ParseVersion(version)
	if type(version)~="string" then return nil end
	local major,minor,letter=version:match("^(%d+)%.(%d+)(%a?)$")
	if not major then return nil end
	return tonumber(major),tonumber(minor),letter or ""
end

-- True only when `other` is a well-formed version strictly newer than
-- `mine`. Minor is compared NUMERICALLY (1.10 is newer than 1.9 -- a plain
-- string compare would get that backwards), and the letter suffix compares
-- lexically with "" sorting before "a" (so 1.10 < 1.10a < 1.10b).
function SocialPlus_IsVersionNewer(other,mine)
	local oMajor,oMinor,oLetter=SocialPlus_ParseVersion(other)
	local mMajor,mMinor,mLetter=SocialPlus_ParseVersion(mine)
	if not oMajor or not mMajor then return false end
	if oMajor~=mMajor then return oMajor>mMajor end
	if oMinor~=mMinor then return oMinor>mMinor end
	return oLetter>mLetter
end

function SocialPlus_BroadcastVersion()
	local version=SocialPlus_GetAddonVersion()
	if not version then return end
	local send=(C_ChatInfo and C_ChatInfo.SendAddonMessage) or SendAddonMessage
	if not send then return end

	if IsInGuild and IsInGuild() then
		pcall(send,SOCIALPLUS_VERSION_PREFIX,version,"GUILD")
	end
	-- Dungeon Finder, Raid Finder, scenario and battleground groups route
	-- party chat to INSTANCE_CHAT, and sending to PARTY inside one is NOT
	-- silently dropped, as this comment used to claim. The client answers
	-- with a "You are not in a party." system message that the player sees,
	-- once per roster change, since GROUP_ROSTER_UPDATE is what queues the
	-- rebroadcast. The pcall below does not hide it either: it is a chat
	-- message from the client, not a Lua error.
	--
	-- Both instance tests are kept because they do not agree across every
	-- group type, and INSTANCE_CHAT is accepted whenever either is true.
	local inInstanceGroup=(IsPartyLFG and IsPartyLFG())
		or (IsInGroup and LE_PARTY_CATEGORY_INSTANCE
			and IsInGroup(LE_PARTY_CATEGORY_INSTANCE))
	local channel
	if inInstanceGroup then
		channel="INSTANCE_CHAT"
	elseif IsInRaid and IsInRaid() then
		channel="RAID"
	elseif IsInGroup and IsInGroup() then
		channel="PARTY"
	end
	if channel then
		pcall(send,SOCIALPLUS_VERSION_PREFIX,version,channel)
	end
end

-- Roster events fire in bursts (every member load, every join/leave), so
-- coalesce them into at most one broadcast per settle window instead of
-- spamming the channel -- same debounce shape as the friend-scan queue.
SocialPlus_VersionBroadcastTimer=nil
function SocialPlus_QueueVersionBroadcast()
	if SocialPlus_VersionBroadcastTimer then return end
	SocialPlus_VersionBroadcastTimer=C_Timer.NewTimer(5,function()
		SocialPlus_VersionBroadcastTimer=nil
		SocialPlus_BroadcastVersion()
	end)
end

function SocialPlus_OnVersionMessage(prefix,message,sender)
	if prefix~=SOCIALPLUS_VERSION_PREFIX then return end
	if SocialPlus_VersionAlertShown then return end
	local mine=SocialPlus_GetAddonVersion()
	if not mine then return end
	-- Our own broadcast comes back to us too, but it can never be strictly
	-- newer than itself, so it falls out here with no special-casing.
	if not SocialPlus_IsVersionNewer(message,mine) then return end

	SocialPlus_VersionAlertShown=true
	if DEFAULT_CHAT_FRAME and DEFAULT_CHAT_FRAME.AddMessage then
		DEFAULT_CHAT_FRAME:AddMessage(format(L.MSG_VERSION_OUTDATED,mine,sender or UNKNOWN,message))
	end
end

-- Battle.net friends are the whole point of this addon, and they're far
-- likelier to be running it than a random guildmate -- but they are NOT
-- reachable over the addon-message channels above, which only ever cover
-- guild/group members. BNSendGameData is the Battle.net equivalent, and
-- it targets ONE game account at a time: there's no broadcast, just one
-- send per online friend.
--
-- That makes this the one spot where a big friend list genuinely costs
-- something -- 150 online friends means 150 sends -- and WoW will
-- disconnect a client that bursts addon messages. So sends are queued and
-- drained a couple per second rather than fired in a loop. Nothing is
-- waiting on them, so being slow is free.

-- gameAccountIDs already sent to this session, so a friend relogging (or
-- several roster events in a row) can't queue them repeatedly.
SocialPlus_VersionBNetSent={}
SocialPlus_VersionBNetQueue={}
SocialPlus_VersionBNetTicker=nil

function SocialPlus_QueueBNetVersionSend(gameAccountID)
	if not gameAccountID then return end
	if SocialPlus_VersionBNetSent[gameAccountID] then return end
	if not BNSendGameData then return end
	if not SocialPlus_GetAddonVersion() then return end

	SocialPlus_VersionBNetSent[gameAccountID]=true
	SocialPlus_VersionBNetQueue[#SocialPlus_VersionBNetQueue+1]=gameAccountID
	if SocialPlus_VersionBNetTicker then return end

	SocialPlus_VersionBNetTicker=C_Timer.NewTicker(0.5,function(ticker)
		local gameAccount=table.remove(SocialPlus_VersionBNetQueue,1)
		if not gameAccount then
			ticker:Cancel()
			SocialPlus_VersionBNetTicker=nil
			return
		end
		local version=SocialPlus_GetAddonVersion()
		if version then
			-- pcall'd: a friend can log out between queueing and sending,
			-- and a cross-project target may simply reject the data.
			pcall(BNSendGameData,gameAccount,SOCIALPLUS_VERSION_PREFIX,version)
		end
	end)
end

function SocialPlus_SendVersionToBNetFriends()
	if not BNSendGameData then return end
	if not SocialPlus_GetAddonVersion() then return end
	for i=1,FG_BNGetNumFriends() do
		-- Reuses the same online-WoW-account enumeration the invite menu
		-- and tooltip already rely on, so a friend with two clients open
		-- gets told on whichever ones are actually running WoW.
		for _,acct in ipairs(SocialPlus_GetOnlineWoWGameAccounts(i)) do
			SocialPlus_QueueBNetVersionSend(acct.gameAccountID)
		end
	end
end

-- One specific friend, for when they come online after our opening pass --
-- far cheaper than re-walking the whole friend list on every online event
-- (which matters on a large list, where that walk hits the game-account
-- API once per friend).
function SocialPlus_SendVersionToBNetFriend(presenceID)
	if not BNSendGameData then return end
	if not SocialPlus_GetAddonVersion() then return end
	local index=SocialPlus_FindBNetIndexByPresenceID(presenceID)
	if not index then return end
	for _,acct in ipairs(SocialPlus_GetOnlineWoWGameAccounts(index)) do
		SocialPlus_QueueBNetVersionSend(acct.gameAccountID)
	end
end

-- BN_CHAT_MSG_ADDON identifies the sender by presenceID, not by name --
-- resolve it to the BattleTag so the alert names someone recognisable
-- instead of a bare number.
function SocialPlus_ResolveBNetSenderName(presenceID)
	if not presenceID then return nil end
	local index=SocialPlus_FindBNetIndexByPresenceID(presenceID)
	if not index then return nil end
	return (GetFriendInfoById(index))
end

-- One FriendsList_Update per burst, instead of one per event.
--
-- Only used while SOCIALPLUS_DRIVING_REFRESH is set -- that is, while the two
-- high-frequency events have been taken off Blizzard's frame (see the
-- PLAYER_LOGIN block). Blizzard's function is still what runs; this only
-- decides how often. A whole burst arriving in one frame collapses to a single
-- call on the next, which is the same shape as the derivation coalescing in
-- SocialPlus_Update and for the same reason.
--
-- Global rather than a file-local: this chunk is at Lua's 200-local ceiling.
function SocialPlus_RequestListRefresh()
	if SOCIALPLUS_REFRESH_QUEUED then return end
	SOCIALPLUS_REFRESH_QUEUED=true

	C_Timer.After(0,function()
		SOCIALPLUS_REFRESH_QUEUED=false
		if type(FriendsList_Update)=="function" then FriendsList_Update() end
	end)
end
