--[[--------------------------------------------------------------------------
SocialPlusSim.lua -- synthetic friend-list simulator (debug / performance tool)

Populates the friends list with N fake friends so the grouped rebuild path can
be exercised at a scale that is impractical to reach with a real friend list.
Built for testing the group->members indexing work, where the whole point is
behaviour at 200-400+ friends across many groups.

    /spsim 400            400 fake friends (~70% BNet, ~30% native WoW)
    /spsim 400 groups=20  ...spread across 20 groups instead of the default 12
    /spsim off            tear it all down
    /spsim status         what is currently faked
    /spsim help           full option list

HOW IT WORKS, AND WHAT IT DOES NOT TOUCH

Friend data does not reach SocialPlus through a single chokepoint: some reads
go through this addon's own FG_* wrappers, but roughly a dozen call sites --
including the per-row render path that draws zone, faction, class and level --
call C_BattleNet / C_FriendList / BNGet* directly. So the simulator installs
itself one level lower, swapping in its own versions of Blizzard's READ
functions while it is active.

Two properties keep that from being reckless:

  * It is purely ADDITIVE. Real friends keep their real list indices and their
    real, unmodified data -- every shim passes those straight through to the
    original function. Fake friends are appended after them. Nothing real is
    masked, rewritten, or hidden, so anything you do to a real friend while the
    simulator is running behaves exactly as it normally would.

  * It only ever shims READS. Note setters, invites, whispers, and every other
    write path are left completely alone. The simulator cannot modify a real
    friend's note or send anything to anyone.

The unavoidable trade-off of shimming at this level: while the simulator is
active, other addons and Blizzard's own friends UI also see the fake friends,
because they read the same functions. That is why this is off by default, must
be turned on explicitly, announces itself loudly, and does not survive a
/reload.

Fake friends are inert. Clicking, whispering or inviting one will not work --
there is no such character on the server. That is expected; this is a rendering
and performance harness, not a mock server.
----------------------------------------------------------------------------]]

local SIM = {
	active = false,
	bnetOnline = {},   -- ordered: fake BNet friends that are "online"
	bnetOffline = {},
	wowOnline = {},    -- ordered: fake native WoW friends that are "online"
	wowOffline = {},
	opts = nil,
}

-- Exposed deliberately: makes the generated data pokeable from /dump while
-- chasing down a rendering oddity.
_G.SocialPlusSim = SIM

local SIM_PRESENCE_BASE = 900000000
local SIM_GAMEACCT_BASE = 950000000

local PREFIX = "|cff33ff99SocialPlusSim|r: "
local function Say(fmt, ...)
	local msg = select("#", ...) > 0 and string.format(fmt, ...) or fmt
	print(PREFIX .. msg)
end

--[[------------------------------------------------------------------------
Data pools. Deliberately varied along every axis the row renderer and the
grouped rebuild actually branch on: faction (drives the faction icon and the
"prioritize this version" faction ordering), client (drives game-icon and the
app-idle sort cluster), wowProjectID (drives the version label and the
promoted block), status (drives statusRank), zone/realm/class/level (drive the
row text), and note tags (drive group membership, i.e. G in the O(G*N) work
this tool exists to measure).
--------------------------------------------------------------------------]]

local ZONES = {
	"Valley of the Four Winds","Kun-Lai Summit","Townlong Steppes","Dread Wastes",
	"The Jade Forest","Krasarang Wilds","Vale of Eternal Blossoms","Timeless Isle",
	"Isle of Thunder","Orgrimmar","Stormwind City","Shrine of Two Moons",
	"Shrine of Seven Stars","Mogu'shan Vaults","Heart of Fear","Throne of Thunder",
	"Terrace of Endless Spring","Siege of Orgrimmar","Ironforge","Darnassus",
	"Undercity","Thunder Bluff","Silvermoon City","The Exodar","Dalaran",
	"Tanaris","Un'Goro Crater","Winterspring","Nagrand","Hellfire Peninsula",
}

local REALMS = {
	"Whitemane","Faerlina","Benediction","Grobbulus","Mankrik","Pagle","Atiesh",
	"Sulfuras","Westfall","Bloodsail Buccaneers","Old Blanchy","Eranikus",
}

local CLASSES = {
	"Warrior","Paladin","Hunter","Rogue","Priest","Death Knight","Shaman",
	"Mage","Warlock","Monk","Druid",
}

local FACTIONS = { "Alliance", "Horde" }

local DEFAULT_GROUPS = {
	"Raid","Mythic","Alts","Guild","PvP","Leveling","IRL","Discord","Bench",
	"Officers","Trial","Socials","Arena","RBG","Farm","Nightcrew","Reroll",
	"Sweats","Casuals","AltRaid","Recruit","Bank","Prio","Standby","Retired",
}

local NAME_A = {
	"Ael","Bor","Cin","Drav","Elo","Fen","Grim","Hal","Ith","Jor","Kael","Lyr",
	"Mor","Nyx","Or","Pyr","Quil","Rur","Sab","Thor","Umb","Vex","Wren","Xan",
	"Yor","Zeph","Bran","Cael","Dorn","Eir","Fal","Gwyn",
}
local NAME_B = {
	"iana","kk","dra","ok","wen","rik","lash","dor","ra","unn","is","a",
	"dak","ith","in","us","ara","el","yn","ok","ir","an","eth","ora",
}

--[[------------------------------------------------------------------------
Deterministic RNG. Lua's own math.random is seeded globally and shared with
every other addon, so seeding it here would perturb unrelated code and make
"same seed, same list" untrue the moment anything else rolled a number. A
private Lehmer generator keeps `seed=` reproducible and side-effect free.
--------------------------------------------------------------------------]]
local function NewRng(seed)
	local state = seed % 2147483647
	if state <= 0 then state = state + 2147483646 end
	return function(n)
		state = (state * 16807) % 2147483647
		if n then return (state % n) + 1 end
		return state
	end
end

local function Pick(rnd, t)
	return t[rnd(#t)]
end

local function MakeName(rnd)
	return Pick(rnd, NAME_A) .. Pick(rnd, NAME_B)
end

--[[------------------------------------------------------------------------
Generation
--------------------------------------------------------------------------]]

-- Builds the "#tag#tag" note that drives group membership. An empty note is
-- left empty on purpose: ungrouped friends are their own case (BNet ones fall
-- into General, native WoW ones into In-game Friends) and the rebuild handles
-- them on a separate path worth exercising.
local function MakeNote(rnd, groups, maxTags)
	local n = rnd(maxTags + 2) - 2   -- weighted towards 0-1 tags
	if n < 1 then return "" end
	local used, parts = {}, {}
	for _ = 1, n do
		local g = Pick(rnd, groups)
		if not used[g] then
			used[g] = true
			parts[#parts + 1] = "#" .. g
		end
	end
	return table.concat(parts)
end

local function BuildGroupPool(count)
	local pool = {}
	for i = 1, count do
		pool[i] = DEFAULT_GROUPS[((i - 1) % #DEFAULT_GROUPS) + 1]
		-- Past the built-in list, keep names unique rather than repeating,
		-- so `groups=40` really does produce 40 distinct groups.
		if i > #DEFAULT_GROUPS then
			pool[i] = pool[i] .. tostring(math.floor((i - 1) / #DEFAULT_GROUPS) + 1)
		end
	end
	return pool
end

local WOW_CLIENT = BNET_CLIENT_WOW or "WoW"
local APP_CLIENT = BNET_CLIENT_APP or "App"
local OTHER_CLIENTS = { "D3", "S2", "Hero", "Pro", "WTCG" }

local function ThisProjectID()
	return WOW_PROJECT_ID or 19
end

local function OtherProjectID()
	local mine = ThisProjectID()
	return mine == 1 and 2 or 1
end

local function MaxLevel()
	return MAX_PLAYER_LEVEL or 90
end

local function GenerateBNet(rnd, index, opts, groups)
	local online = rnd(100) > opts.offlinePct
	local name = MakeName(rnd)
	local rec = {
		index         = index,
		presenceID    = SIM_PRESENCE_BASE + index,
		bnetAccountID = SIM_PRESENCE_BASE + index,
		gameAccountID = SIM_GAMEACCT_BASE + index,
		accountName   = name,
		-- The favourite key is "BNET:<battleTag>", so the tag has to be unique
		-- per fake friend or favouriting one would favourite its twin -- the
		-- name pool intentionally repeats, so the index carries the
		-- uniqueness. A leading-zero discriminator is also never issued by
		-- Battle.net, so a fake tag can't collide with a real friend's key
		-- either.
		battleTag     = name .. "#0" .. tostring(index),
		note          = MakeNote(rnd, groups, opts.maxTags),
		isOnline      = online,
		isFavorite    = false,
		isWowMobile   = false,
		lastOnlineTime = time and (time() - rnd(600000)) or 0,
		isAFK = false, isDND = false, isGameAFK = false, isGameBusy = false,
	}

	if online then
		-- Status mix: mostly available, with enough AFK/DND to make statusRank
		-- ordering visible in the list.
		local roll = rnd(100)
		if roll <= 12 then rec.isAFK = true
		elseif roll <= 20 then rec.isDND = true
		elseif roll <= 28 then rec.isGameAFK = true
		elseif roll <= 34 then rec.isGameBusy = true end

		local kind = rnd(100)
		if kind <= 55 then
			-- On this exact WoW version: the population the "prioritize"
			-- setting promotes, and the only one with a faction to match.
			rec.client = WOW_CLIENT
			rec.wowProjectID = ThisProjectID()
		elseif kind <= 70 then
			rec.client = WOW_CLIENT
			rec.wowProjectID = OtherProjectID()
		elseif kind <= 90 then
			rec.client = APP_CLIENT      -- app-idle: sorts last within a group
		else
			rec.client = Pick(rnd, OTHER_CLIENTS)
		end

		if rec.client == WOW_CLIENT then
			rec.characterName = MakeName(rnd)
			rec.className     = Pick(rnd, CLASSES)
			rec.level         = rnd(MaxLevel())
			rec.areaName      = Pick(rnd, ZONES)
			rec.realmName     = Pick(rnd, REALMS)
			rec.factionName   = Pick(rnd, FACTIONS)
			rec.richPresence  = string.format("Level %d %s - %s",
				rec.level, rec.className, rec.areaName)
		else
			rec.richPresence = "In Menus"
		end
	end

	return rec
end

local function GenerateWoW(rnd, index, opts, groups)
	local online = rnd(100) > opts.offlinePct
	local name = MakeName(rnd) .. tostring(index)   -- WoW names are unique per realm
	return {
		index     = index,
		name      = name,
		guid      = "Player-SIM-" .. tostring(index),
		level     = rnd(MaxLevel()),
		className = Pick(rnd, CLASSES),
		area      = Pick(rnd, ZONES),
		connected = online,
		notes     = MakeNote(rnd, groups, opts.maxTags),
		afk       = online and rnd(100) <= 10 or false,
		dnd       = online and rnd(100) <= 6 or false,
		mobile    = false,
		isOnline  = online,
	}
end

local function Generate(opts)
	local rnd = NewRng(opts.seed)
	local groups = BuildGroupPool(opts.groups)

	SIM.bnetOnline, SIM.bnetOffline = {}, {}
	SIM.wowOnline, SIM.wowOffline = {}, {}

	local numWoW  = opts.wow
	local numBNet = opts.total - numWoW

	for i = 1, numBNet do
		local rec = GenerateBNet(rnd, i, opts, groups)
		local bucket = rec.isOnline and SIM.bnetOnline or SIM.bnetOffline
		bucket[#bucket + 1] = rec
	end
	for i = 1, numWoW do
		local rec = GenerateWoW(rnd, i, opts, groups)
		local bucket = rec.isOnline and SIM.wowOnline or SIM.wowOffline
		bucket[#bucket + 1] = rec
	end

	SIM.opts = opts
	SIM.groupPool = groups
end

--[[------------------------------------------------------------------------
Index mapping

Blizzard orders both friend lists online-first, and the grouped rebuild relies
on that for native WoW friends (it treats 1..numOnline as online and the rest
as offline without re-checking). So fakes cannot simply be appended to the end
of the whole list -- they have to be spliced in per segment:

    [ real online | fake online | real offline | fake offline ]

Returns (fakeRecord, realIndex): exactly one of the two is non-nil, or both
are nil when the index is past the end of everything.
--------------------------------------------------------------------------]]
local function MapIndex(i, realTotal, realOnline, fakeOn, fakeOff)
	if not i or i < 1 then return nil, nil end
	local nFakeOn, nFakeOff = #fakeOn, #fakeOff

	if i <= realOnline then return nil, i end
	if i <= realOnline + nFakeOn then return fakeOn[i - realOnline], nil end

	local realOffline = realTotal - realOnline
	local base = realOnline + nFakeOn
	if i <= base + realOffline then return nil, i - nFakeOn end
	if i <= base + realOffline + nFakeOff then
		return fakeOff[i - base - realOffline], nil
	end
	return nil, nil
end

--[[------------------------------------------------------------------------
Record -> Blizzard shapes
--------------------------------------------------------------------------]]

local function GameAccountInfo(rec)
	if not rec.isOnline then return nil end
	return {
		isOnline        = true,
		gameAccountID   = rec.gameAccountID,
		clientProgram   = rec.client,
		wowProjectID    = rec.wowProjectID,
		characterName   = rec.characterName,
		className       = rec.className,
		characterLevel  = rec.level,
		areaName        = rec.areaName,
		realmName       = rec.realmName,
		factionName     = rec.factionName,
		richPresence    = rec.richPresence,
		isGameAFK       = rec.isGameAFK,
		isGameBusy      = rec.isGameBusy,
		playerGuid      = "Player-SIM-B-" .. tostring(rec.index),
	}
end

local function AccountInfo(rec)
	return {
		bnetAccountID   = rec.bnetAccountID,
		accountName     = rec.accountName,
		battleTag       = rec.battleTag,
		isFriend        = true,
		isFavorite      = rec.isFavorite,
		isAFK           = rec.isAFK,
		isDND           = rec.isDND,
		isGameAFK       = rec.isGameAFK,
		isGameBusy      = rec.isGameBusy,
		isWowMobile     = rec.isWowMobile,
		areaName        = rec.areaName,
		note            = rec.note,
		lastOnlineTime  = rec.lastOnlineTime,
		gameAccountInfo = GameAccountInfo(rec),
	}
end

local function FriendInfo(rec)
	return {
		name        = rec.name,
		guid        = rec.guid,
		level       = rec.level,
		className   = rec.className,
		area        = rec.area,
		connected   = rec.connected,
		notes       = rec.notes,
		afk         = rec.afk,
		dnd         = rec.dnd,
		mobile      = rec.mobile,
		rafLinkType = 0,
	}
end

-- Legacy BNGetFriendInfo tuple. Only the positions this addon actually reads
-- are populated (1 presenceID, 2 accountName, 3 battleTag, 5 characterName,
-- 6 gameAccountID, 7 client, 8 isOnline, 9 lastOnline, 10 isAFK, 11 isDND,
-- 12 broadcast, 13 note, 16 wowProjectID, 19 isFavorite, 20 mobile); the rest
-- are nil, which is what an unpopulated field looks like anyway.
local function LegacyFriendTuple(rec)
	return rec.presenceID, rec.accountName, rec.battleTag, nil,
		rec.characterName, rec.gameAccountID, rec.client, rec.isOnline,
		rec.lastOnlineTime, rec.isAFK, rec.isDND, "", rec.note, nil, nil,
		rec.wowProjectID, nil, nil, rec.isFavorite, rec.isWowMobile
end

-- Legacy BNGetGameAccountInfo tuple: 4 realmName, 8 class, 10 zone, 11 level,
-- 12 gameText, 18 isGameAFK, 19 isGameBusy, 21 wowProjectID, 22 mobile.
local function LegacyGameAccountTuple(rec)
	return nil, nil, nil, rec.realmName, nil, nil, nil, rec.className, nil,
		rec.areaName, rec.level, rec.richPresence, nil, nil, nil, nil, nil,
		rec.isGameAFK, rec.isGameBusy, nil, rec.wowProjectID, rec.isWowMobile
end

--[[------------------------------------------------------------------------
The shim layer
--------------------------------------------------------------------------]]

local orig = {}

local function RealBNetCounts()
	local t, o = 0, 0
	if orig.BNGetNumFriends then t, o = orig.BNGetNumFriends() end
	return t or 0, o or 0
end

local function RealWoWCounts()
	local t = orig.GetNumFriends and orig.GetNumFriends() or 0
	local o = orig.GetNumOnlineFriends and orig.GetNumOnlineFriends() or 0
	return t or 0, o or 0
end

local function MapBNet(i)
	local rt, ro = RealBNetCounts()
	return MapIndex(i, rt, ro, SIM.bnetOnline, SIM.bnetOffline)
end

local function MapWoW(i)
	local rt, ro = RealWoWCounts()
	return MapIndex(i, rt, ro, SIM.wowOnline, SIM.wowOffline)
end

-- Fake game-account IDs are looked up directly (not by list index) by the
-- legacy path, so they need their own reverse lookup.
local function FindByGameAccountID(id)
	if type(id) ~= "number" or id < SIM_GAMEACCT_BASE then return nil end
	for _, list in ipairs({ SIM.bnetOnline, SIM.bnetOffline }) do
		for _, rec in ipairs(list) do
			if rec.gameAccountID == id then return rec end
		end
	end
	return nil
end

local function InstallShims()
	orig.BNGetNumFriends       = BNGetNumFriends
	orig.BNGetFriendInfo       = BNGetFriendInfo
	orig.BNGetGameAccountInfo  = BNGetGameAccountInfo

	_G.BNGetNumFriends = function()
		local rt, ro = RealBNetCounts()
		return rt + #SIM.bnetOnline + #SIM.bnetOffline, ro + #SIM.bnetOnline
	end

	_G.BNGetFriendInfo = function(i)
		local rec, realIdx = MapBNet(i)
		if realIdx then return orig.BNGetFriendInfo(realIdx) end
		if not rec then return nil end
		return LegacyFriendTuple(rec)
	end

	_G.BNGetGameAccountInfo = function(id)
		local rec = FindByGameAccountID(id)
		if rec then return LegacyGameAccountTuple(rec) end
		return orig.BNGetGameAccountInfo and orig.BNGetGameAccountInfo(id)
	end

	if C_BattleNet then
		orig.GetFriendAccountInfo     = C_BattleNet.GetFriendAccountInfo
		orig.GetFriendNumGameAccounts = C_BattleNet.GetFriendNumGameAccounts
		orig.GetFriendGameAccountInfo = C_BattleNet.GetFriendGameAccountInfo

		C_BattleNet.GetFriendAccountInfo = function(i, ...)
			local rec, realIdx = MapBNet(i)
			if realIdx then return orig.GetFriendAccountInfo(realIdx, ...) end
			if not rec then return nil end
			return AccountInfo(rec)
		end

		C_BattleNet.GetFriendNumGameAccounts = function(i, ...)
			local rec, realIdx = MapBNet(i)
			if realIdx then return orig.GetFriendNumGameAccounts(realIdx, ...) end
			if not rec then return 0 end
			return rec.isOnline and 1 or 0
		end

		C_BattleNet.GetFriendGameAccountInfo = function(i, n, ...)
			local rec, realIdx = MapBNet(i)
			if realIdx then return orig.GetFriendGameAccountInfo(realIdx, n, ...) end
			if not rec or n ~= 1 then return nil end
			return GameAccountInfo(rec)
		end
	end

	if C_FriendList then
		orig.GetNumFriends        = C_FriendList.GetNumFriends
		orig.GetNumOnlineFriends  = C_FriendList.GetNumOnlineFriends
		orig.GetFriendInfoByIndex = C_FriendList.GetFriendInfoByIndex

		C_FriendList.GetNumFriends = function()
			local rt = RealWoWCounts()
			return rt + #SIM.wowOnline + #SIM.wowOffline
		end

		C_FriendList.GetNumOnlineFriends = function()
			local _, ro = RealWoWCounts()
			return ro + #SIM.wowOnline
		end

		C_FriendList.GetFriendInfoByIndex = function(i, ...)
			local rec, realIdx = MapWoW(i)
			if realIdx then return orig.GetFriendInfoByIndex(realIdx, ...) end
			if not rec then return nil end
			return FriendInfo(rec)
		end
	end
end

local function RemoveShims()
	if orig.BNGetNumFriends      then _G.BNGetNumFriends = orig.BNGetNumFriends end
	if orig.BNGetFriendInfo      then _G.BNGetFriendInfo = orig.BNGetFriendInfo end
	if orig.BNGetGameAccountInfo then _G.BNGetGameAccountInfo = orig.BNGetGameAccountInfo end

	if C_BattleNet then
		if orig.GetFriendAccountInfo     then C_BattleNet.GetFriendAccountInfo = orig.GetFriendAccountInfo end
		if orig.GetFriendNumGameAccounts then C_BattleNet.GetFriendNumGameAccounts = orig.GetFriendNumGameAccounts end
		if orig.GetFriendGameAccountInfo then C_BattleNet.GetFriendGameAccountInfo = orig.GetFriendGameAccountInfo end
	end
	if C_FriendList then
		if orig.GetNumFriends        then C_FriendList.GetNumFriends = orig.GetNumFriends end
		if orig.GetNumOnlineFriends  then C_FriendList.GetNumOnlineFriends = orig.GetNumOnlineFriends end
		if orig.GetFriendInfoByIndex then C_FriendList.GetFriendInfoByIndex = orig.GetFriendInfoByIndex end
	end

	orig = {}
end

--[[------------------------------------------------------------------------
Favourites

SocialPlus keys favourites by battleTag / character name in SavedVars, so the
only way to have favourited fake friends -- and the Favorites group is exactly
the move-not-copy path worth stress-testing -- is to write those keys in for
real. Every key written is recorded in SavedVars so teardown can remove
precisely what was added, even across a /reload that happened while the
simulator was on. Nothing else in SavedVars is touched.
--------------------------------------------------------------------------]]

local function PurgeSimFavorites()
	local sv = SocialPlus_SavedVars
	if type(sv) ~= "table" then return 0 end
	local keys = sv.simFavoriteKeys
	if type(keys) ~= "table" then return 0 end
	local removed = 0
	if type(sv.favorites) == "table" then
		for _, key in ipairs(keys) do
			if sv.favorites[key] then
				sv.favorites[key] = nil
				removed = removed + 1
			end
		end
	end
	sv.simFavoriteKeys = nil
	return removed
end

local function ApplySimFavorites(pct)
	local sv = SocialPlus_SavedVars
	if type(sv) ~= "table" or pct <= 0 then return 0 end
	sv.favorites = type(sv.favorites) == "table" and sv.favorites or {}

	local rnd = NewRng((SIM.opts.seed * 7919) + 13)
	local keys = {}
	local function maybe(key)
		if rnd(100) <= pct and not sv.favorites[key] then
			sv.favorites[key] = true
			keys[#keys + 1] = key
		end
	end
	for _, list in ipairs({ SIM.bnetOnline, SIM.bnetOffline }) do
		for _, rec in ipairs(list) do maybe("BNET:" .. rec.battleTag) end
	end
	for _, list in ipairs({ SIM.wowOnline, SIM.wowOffline }) do
		for _, rec in ipairs(list) do maybe("WOW:" .. rec.name) end
	end

	sv.simFavoriteKeys = keys
	return #keys
end

--[[------------------------------------------------------------------------
Activation
--------------------------------------------------------------------------]]

local function Refresh()
	if SocialPlus_Update then pcall(SocialPlus_Update, true) end
	if FriendsList_Update then pcall(FriendsList_Update) end
end

local function Stop(quiet)
	if not SIM.active then
		if not quiet then Say("not running.") end
		return
	end
	RemoveShims()
	local removed = PurgeSimFavorites()
	SIM.active = false
	SIM.bnetOnline, SIM.bnetOffline = {}, {}
	SIM.wowOnline, SIM.wowOffline = {}, {}
	SIM.opts = nil
	Refresh()
	if not quiet then
		Say("stopped. Real friend list restored%s.",
			removed > 0 and string.format(" (%d simulated favourites cleared)", removed) or "")
	end
end

local function Start(opts)
	if SIM.active then Stop(true) end

	Generate(opts)
	InstallShims()
	SIM.active = true
	local favs = ApplySimFavorites(opts.fav)
	Refresh()

	Say("|cffffff00%d simulated friends|r added (%d BNet, %d native WoW) across %d groups.",
		opts.total, opts.total - opts.wow, opts.wow, opts.groups)
	Say("  %d online / %d offline, %d favourited, seed=%d",
		#SIM.bnetOnline + #SIM.wowOnline,
		#SIM.bnetOffline + #SIM.wowOffline, favs, opts.seed)
	Say("|cffff8000Heads up:|r other addons and Blizzard's friends UI will see these too. " ..
		"Your real friends are untouched. Use |cffffffff/spsim off|r when done.")
end

--[[------------------------------------------------------------------------
Slash command
--------------------------------------------------------------------------]]

local function DefaultOpts(total)
	return {
		total      = total,
		wow        = math.floor(total * 0.3),
		groups     = 12,
		maxTags    = 3,
		offlinePct = 45,
		fav        = 8,
		seed       = 1,
	}
end

local function Clamp(v, lo, hi)
	if v < lo then return lo end
	if v > hi then return hi end
	return v
end

--[[------------------------------------------------------------------------
Benchmark

Times full SocialPlus_Update(true) rebuilds. Passing forceUpdate=true is
deliberate: it bypasses the visibility guards at the top of that function, so
the rebuild runs even with the friends list closed. The row RENDER half only
does real work while the list is open though, so the report states which of
the two it just measured rather than quietly comparing unlike numbers.

The first pass is reported separately because note parsing is cached between
rebuilds -- the pass right after a note change does measurably more work than
the steady-state ones following it.
--------------------------------------------------------------------------]]

local function Now()
	if debugprofilestop then return debugprofilestop() end
	return (GetTime and GetTime() * 1000) or 0
end

local function TimeOneRebuild()
	local t0 = Now()
	SocialPlus_Update(true)
	return Now() - t0
end

local function Benchmark(iters)
	if type(SocialPlus_Update) ~= "function" then
		Say("|cffff2020SocialPlus_Update unavailable|r -- is SocialPlus itself loaded?")
		return
	end

	local bnet = BNGetNumFriends and (BNGetNumFriends()) or 0
	local wow = (C_FriendList and C_FriendList.GetNumFriends
		and C_FriendList.GetNumFriends()) or 0

	local first = TimeOneRebuild()

	-- Auto-size the run to roughly a two-second budget. A rebuild over a
	-- 5000-friend simulated list is slow enough that a fixed iteration count
	-- would freeze the client for ten seconds.
	if iters then
		iters = math.floor(Clamp(iters, 2, 1000))
	else
		iters = math.floor(Clamp(math.floor(2000 / math.max(first, 0.5)), 5, 200))
	end

	local samples = {}
	for _ = 1, iters - 1 do
		samples[#samples + 1] = TimeOneRebuild()
	end

	local total, min, max = 0, math.huge, 0
	local sorted = {}
	for i, v in ipairs(samples) do
		total = total + v
		if v < min then min = v end
		if v > max then max = v end
		sorted[i] = v
	end
	table.sort(sorted)

	Say("benchmark: %d rebuilds over %d friends (%d BNet + %d native WoW)%s",
		#samples + 1, bnet + wow, bnet, wow,
		SIM.active and string.format(", %d simulated across %d groups",
			SIM.opts.total, SIM.opts.groups) or "")
	Say("  first pass  |cffffffff%.2f ms|r   (includes any note re-parsing)", first)
	if #samples > 0 then
		Say("  steady      |cffffff00%.2f ms|r mean   min %.2f   median %.2f   max %.2f",
			total / #samples, min, sorted[math.ceil(#sorted / 2)], max)
	end

	local open = FriendsListFrame and FriendsListFrame:IsShown()
	Say("  friends list %s -- %s", open and "|cff20ff20OPEN|r" or "|cffff8000CLOSED|r",
		open and "row rendering included" or "rebuild only, rows not drawn")
	if SIM.active then
		Say("  compare: same |cffffffffseed=%d|r on another branch measures the same list.",
			SIM.opts.seed)
	end
end

local function ShowHelp()
	Say("friend-list simulator (debug tool).")
	print("  |cffffffff/spsim <n>|r            simulate n fake friends")
	print("  |cffffffff/spsim off|r            stop and restore the real list")
	print("  |cffffffff/spsim status|r         show what is currently simulated")
	print("  |cffffffff/spsim bench [n]|r     time n full rebuilds (auto-sized if omitted)")
	print("  Options, any order:  |cffffffff/spsim 400 groups=20 wow=150 seed=7|r")
	print("    |cffffffffgroups=|r n   distinct groups to spread across (default 12)")
	print("    |cffffffffwow=|r n      how many are native WoW friends (default 30%)")
	print("    |cfffffffftags=|r n     max group tags per friend (default 3)")
	print("    |cffffffffoffline=|r n  percent offline (default 45)")
	print("    |cfffffffffav=|r n      percent favourited (default 8)")
	print("    |cffffffffseed=|r n     RNG seed; same seed = same list (default 1)")
end

local function ShowStatus()
	if not SIM.active then Say("not running.") return end
	local o = SIM.opts
	Say("active: %d fake friends (%d BNet, %d WoW), %d groups, seed=%d",
		o.total, o.total - o.wow, o.wow, o.groups, o.seed)
	Say("  online %d / offline %d",
		#SIM.bnetOnline + #SIM.wowOnline, #SIM.bnetOffline + #SIM.wowOffline)
end

local function HandleCommand(msg)
	msg = (msg or ""):gsub("^%s+", ""):gsub("%s+$", "")
	local args = {}
	for word in msg:gmatch("%S+") do args[#args + 1] = word end

	local first = args[1] and args[1]:lower() or ""
	if first == "" or first == "help" then return ShowHelp() end
	if first == "status" then return ShowStatus() end
	if first == "bench" then return Benchmark(tonumber(args[2])) end
	if first == "off" or first == "stop" or first == "0" then return Stop() end

	-- Allow a leading "simulate" for people who type it out in full.
	local startAt = 1
	if first == "simulate" or first == "sim" then startAt = 2 end

	local total = tonumber(args[startAt])
	if not total then
		Say("|cffff2020Unrecognised:|r %s", msg)
		return ShowHelp()
	end

	total = math.floor(Clamp(total, 1, 5000))
	local opts = DefaultOpts(total)

	for i = startAt + 1, #args do
		local key, value = args[i]:match("^(%a+)=(%-?%d+)$")
		if key and value then
			key, value = key:lower(), tonumber(value)
			if key == "groups"  then opts.groups     = math.floor(Clamp(value, 1, 200))
			elseif key == "wow"     then opts.wow        = math.floor(Clamp(value, 0, total))
			elseif key == "tags"    then opts.maxTags    = math.floor(Clamp(value, 0, 10))
			elseif key == "offline" then opts.offlinePct = math.floor(Clamp(value, 0, 100))
			elseif key == "fav"     then opts.fav        = math.floor(Clamp(value, 0, 100))
			elseif key == "seed"    then opts.seed       = math.floor(Clamp(value, 1, 2147483646))
			else Say("|cffff8000Ignoring unknown option:|r %s", args[i]) end
		else
			Say("|cffff8000Ignoring unparsable argument:|r %s", args[i])
		end
	end

	Start(opts)
end

SLASH_SOCIALPLUSSIM1 = "/spsim"
SLASH_SOCIALPLUSSIM2 = "/socialplussim"
SlashCmdList["SOCIALPLUSSIM"] = HandleCommand

--[[------------------------------------------------------------------------
Teardown safety net

The simulator itself never survives a reload -- the shims are plain Lua and go
away with the environment. Favourite keys DO persist though, so if the client
was reloaded while it was running, clean them out at login.
--------------------------------------------------------------------------]]
local simFrame = CreateFrame("Frame")
simFrame:RegisterEvent("PLAYER_LOGIN")
simFrame:SetScript("OnEvent", function()
	local removed = PurgeSimFavorites()
	if removed > 0 then
		Say("cleaned up %d simulated favourite(s) left over from a previous session.", removed)
	end
end)
