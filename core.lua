local addonName = ...
local addonConfig = {}
local dataProviders = {}
local uiHooks = {}
local profileCache = {}

-- default config
addonConfig.showTooltipSpacing = true

-- constants
local MAX_LEVEL = MAX_PLAYER_LEVEL_TABLE[LE_EXPANSION_LEGION]
local FACTION = {
	["Alliance"] = 1,
	["Horde"] = 2,
	[1] = "Alliance",
	[2] = "Horde",
}
local SCORES = {
	[1] = 3000,
	[2] = 2400,
	[3] = 1800,
	[4] = 1400,
	[5] = 1000
}

-- session constants
local PLAYER_FACTION

-- create the addon core frame
local addon = CreateFrame("Frame")

-- define our UI hooks
do
	-- GameTooltip
	uiHooks[#uiHooks + 1] = function()
		GameTooltip:HookScript("OnTooltipSetUnit", function(self)
			addon:AppendGameTooltip(self, select(2, self:GetUnit()), nil)
		end)
		return 1
	end

	-- Keystone GameTooltip + ItemRefTooltip
	uiHooks[#uiHooks + 1] = function()
		local function OnSetItem(tooltip)
			local _, link = tooltip:GetItem()
			if type(link) == "string" and link:find("keystone:", nil, true) then
				local inst, lvl, a1, a2, a3 = link:match("keystone:(%d+):(%d+):(%d+):(%d+):(%d+)")
				if inst then
					-- TODO: evaluate the instance, level and affixes compared to our score, can we make it?
					tooltip:AddLine(" ")
					tooltip:AddLine("Raider.IO", 1, 0.85, 0, false)
					tooltip:AddLine((lvl * 50) .. " score is recommended for this dungeon.", 1, 1, 1, false)
					tooltip:Show()
				end
			end
		end
		GameTooltip:HookScript("OnTooltipSetItem", OnSetItem)
		ItemRefTooltip:HookScript("OnTooltipSetItem", OnSetItem)
		return 1
	end

	-- LFG
	uiHooks[#uiHooks + 1] = function()
		if _G.LFGListApplicationViewerScrollFrameButton1 then
			local hooked = {}
			local OnEnter, OnLeave
			function OnEnter(self)
				if self.applicantID and self.Members then
					for i = 1, #self.Members do
						local b = self.Members[i]
						if not hooked[b] then
							hooked[b] = 1
							b:HookScript("OnEnter", OnEnter)
							b:HookScript("OnLeave", OnLeave)
						end
					end
				elseif self.memberIdx then
					local fullName = C_LFGList.GetApplicantMemberInfo(self:GetParent().applicantID, self.memberIdx)
					if fullName then
						local hasOwner = GameTooltip:GetOwner()
						if not hasOwner then
							GameTooltip:SetOwner(self, "ANCHOR_TOPLEFT", 0, 0)
						end
						addon:AppendGameTooltip(GameTooltip, fullName, not hasOwner, true)
					end
				end
			end
			function OnLeave(self)
				if self.applicantID or self.memberIdx then
					GameTooltip:Hide()
				end
			end
			for i = 1, 14 do
				local b = _G["LFGListApplicationViewerScrollFrameButton" .. i]
				b:HookScript("OnEnter", OnEnter)
				b:HookScript("OnLeave", OnLeave)
			end
			return 1
		end
	end

	-- WhoFrame
	uiHooks[#uiHooks + 1] = function()
		-- TODO: NYI
		return 1
	end

	-- Blizzard_GuildUI
	uiHooks[#uiHooks + 1] = function()
		if _G.GuildFrame then
			local function OnEnter(self)
				if self.guildIndex then
					local fullName = GetGuildRosterInfo(self.guildIndex)
					if fullName then
						GameTooltip:SetOwner(self, "ANCHOR_TOPLEFT", 0, 0)
						if not addon:AppendGameTooltip(GameTooltip, fullName, true, true) then
							GameTooltip:Hide()
						end
					end
				end
			end
			local function OnLeave(self)
				if self.guildIndex then
					GameTooltip:Hide()
				end
			end
			for i = 1, 16 do
				local b = _G["GuildRosterContainerButton" .. i]
				b:HookScript("OnEnter", OnEnter)
				b:HookScript("OnLeave", OnLeave)
			end
			return 1
		end
	end

	-- Blizzard_PVPUI
	uiHooks[#uiHooks + 1] = function()
		if _G.PVPQueueFrame then
			-- TODO: NYI
			return 1
		end
	end
end

-- an addon has loaded, is it ours? is it some LOD addon we can hook?
function addon:ADDON_LOADED(event, name)
	-- the addon savedvariables are loaded and we can initialize the addon
	if name == addonName then
		addon:Init()
	end

	-- apply hooks to interface elements
	addon:ApplyHooks()
end

-- we have logged in and character data is available
function addon:PLAYER_LOGIN()
	-- store our faction for later use
	PLAYER_FACTION = addon:GetFaction("player")
end

-- we enter the world (after a loading screen, int/out of instances)
function addon:PLAYER_ENTERING_WORLD()
	-- we wipe the cached profiles in between loading screens, this seems like a good way get rid of memory use over time
	table.wipe(profileCache)
end

-- the addon has just loaded, setup the config table, run or wait for the login event and register events
function addon:Init()
	-- update local reference to the correct savedvariable table
	if type(_G.RaiderIO_Config) ~= "table" then
		_G.RaiderIO_Config = addonConfig
	else
		addonConfig = _G.RaiderIO_Config
	end

	-- wait for the login event, or run the associated code right away
	if not IsLoggedIn() then
		addon:RegisterEvent("PLAYER_LOGIN")
	else
		addon:PLAYER_LOGIN()
	end

	-- purge cache after zoning
	addon:RegisterEvent("PLAYER_ENTERING_WORLD")
end

-- adds data provider to RaiderIO (only to be used by the other database modules)
function addon:AddProvider(data)
	-- make sure the object is what we expect it to be like
	assert(type(data.region) == "string" and type(data.faction) == "number" and type(data.db) == "table", "RaiderIO has been requested to load a database that isn't supported.")
	-- append provider to the table
	dataProviders[#dataProviders + 1] = data
end

-- returns the profile of a given character, faction is optional but recommended for quicker lookups
function addon:GetProviderData(name, realm, faction)
	local c = #dataProviders
	local p, r, d

	-- iterate each provider
	for i = 1, c do
		p = dataProviders[i]

		-- only scan the db if the provider contains data for the requested faction
		if not faction or faction == p.faction then
			r = p.db[realm]

			-- does the realm exist?
			if r then
				d = r[name]

				-- does the profile exist?
				if d then
					return addon:CacheProviderData(p, name, realm, d)
				end
			end
		end
	end
end

-- round scores up to the closest 100
function addon:RoundScore(score)
	return floor(score/100+0.5)*100
end

-- caches the profile table and returns one using keys
function addon:CacheProviderData(provider, name, realm, profile)
	local cache = profileCache[profile]
	-- prefer to re-use cached profiles
	if cache then
		return cache
	end
	-- TODO: can we make this table read-only? raw methods will buypass metatable restrictions we try to enforce
	-- build this custom table in order to avoid users tainting the provider database
	cache = {
		region = provider.region,
		faction = provider.faction,
		date = provider.date,
		name = name,
		realm = realm,
		-- data from Raider.IO
		allScore = addon:RoundScore(profile[1]),
		tankScore = addon:RoundScore(profile[2]),
		dpsScore = addon:RoundScore(profile[3]),
		healScore = addon:RoundScore(profile[4]),
		prevAllScore = addon:RoundScore(profile[5])
	}
	-- store it in the profile cache
	profileCache[profile] = cache
	-- return the freshly generated table
	return cache
end

-- returns the name, realm and possibly unit
function addon:GetNameAndRealm(arg1, arg2)
	local name, realm, unit
	if UnitExists(arg1) then
		unit = arg1
		if UnitIsPlayer(arg1) then
			name, realm = UnitName(arg1)
			realm = realm and realm ~= "" and realm or GetRealmName()
		end
	elseif type(arg1) == "string" then
		if arg1:find("-", nil, true) then
			name, realm = ("-"):split(arg1)
		else
			name = arg1 -- assume this is the name
		end
		if (not realm or realm == "") and type(arg2) == "string" then
			realm = arg2
		else
			realm = GetRealmName() -- assume they are on our realm
		end
	end
	return name, realm, unit
end

-- returns 1 or 2 if the unit is Alliance or Horde, nil if neutral
function addon:GetFaction(unit)
	if UnitExists(unit) and UnitIsPlayer(unit) then
		local faction = UnitFactionGroup(unit)
		if faction then
			return FACTION[faction]
		end
	end
end

-- retrieves the profile of a given unit, or name+realm query
function addon:GetScore(arg1, arg2, forceFaction)
	local name, realm, unit = addon:GetNameAndRealm(arg1, arg2)
	if name and realm then
		-- no need to lookup lowbies for a score
		if unit and (UnitLevel(unit) or 0) < MAX_LEVEL then
			return
		end
		realm = realm:lower():gsub("[%s%.%,%-%_%'%\"]", "") -- DEBUG: DB needs to use real realm names instead of wanna-be-slugs
		return addon:GetProviderData(name, realm, type(forceFaction) == "number" and forceFaction or addon:GetFaction(unit))
	end
end

-- returns score color using item colors
function addon:GetScoreColor(score)
	local r, g, b = 1, .5, .5
	if type(score) == "number" then
		if score >= SCORES[1] then
			r, g, b = GetItemQualityColor(5)
		elseif score >= SCORES[2] then
			r, g, b = GetItemQualityColor(4)
		elseif score >= SCORES[3] then
			r, g, b = GetItemQualityColor(3)
		elseif score >= SCORES[4] then
			r, g, b = GetItemQualityColor(2)
		elseif score >= SCORES[5] then
			r, g, b = GetItemQualityColor(1)
		else
			r, g, b = GetItemQualityColor(0)
		end
	end
	return r, g, b
end

-- runs the hook process, trying to hook LOD addons
function addon:ApplyHooks()
	-- iterate backwards, removing hooks as they complete
	for i = #uiHooks, 1, -1 do
		local func = uiHooks[i]

		-- if the function returns true our hook succeeded, we then remove it from the table
		if func() then
			table.remove(uiHooks, i)
		end
	end
end

-- appends score data to a given tooltip
function addon:AppendGameTooltip(tooltip, arg1, forceNoPadding, forceAddName)
	local profile = addon:GetScore(arg1)
	if profile then
		-- show data origin before we list scores
		if not forceNoPadding and addonConfig.showTooltipSpacing then
			tooltip:AddLine(" ")
		end
		tooltip:AddLine("Raider.IO", 1, 0.85, 0, false)
		-- show the players name if required
		if forceAddName then
			tooltip:AddLine(profile.name .. " (" .. profile.realm .. ")", 1, 1, 1, false)
		end
		-- show the last season score if our current season score is too low relative to our last score, otherwise just show the real score
		if profile.prevAllScore > 0 and profile.prevAllScore/2 > profile.allScore then
			tooltip:AddDoubleLine("M+ Score", profile.prevAllScore or "N/A", 1, 1, 1, addon:GetScoreColor(profile.prevAllScore))
		elseif profile.allScore > 0 then
			tooltip:AddDoubleLine("M+ Score", profile.allScore or "N/A", 1, 1, 1, addon:GetScoreColor(profile.allScore))
		end
		-- show tank, healer and dps scores
		if profile.tankScore > 0 then
			tooltip:AddDoubleLine("M+ Tank Score", profile.tankScore or "N/A", 1, 1, 1, addon:GetScoreColor(profile.tankScore))
		end
		if profile.healScore > 0 then
			tooltip:AddDoubleLine("M+ Healer Score", profile.healScore or "N/A", 1, 1, 1, addon:GetScoreColor(profile.healScore))
		end
		if profile.dpsScore > 0 then
			tooltip:AddDoubleLine("M+ DPS Score", profile.dpsScore or "N/A", 1, 1, 1, addon:GetScoreColor(profile.dpsScore))
		end
		tooltip:Show()
		return 1
	end
end

-- publicly exposed API
_G.RaiderIO = {
	-- RaiderIO:GetScore(unit)
	-- RaiderIO:GetScore("Name-Realm")
	-- RaiderIO:GetScore("Name", "Realm")
	GetScore = addon.GetScore,
	-- Please do not use the AddProvider method as it's only for internal RaiderIO use (loading the databases selected by the user)
	AddProvider = addon.AddProvider,
}

-- register events and wait for the addon load event to fire
addon:SetScript("OnEvent", function(_, event, ...) addon[event](addon, event, ...) end)
addon:RegisterEvent("ADDON_LOADED")
