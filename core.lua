local addonName, ns = ...
local dataProviders = {}
local uiHooks = {}
local profileCache = {}

-- default config
local addonConfig = {
	enableUnitTooltips = true,
	enableLFGTooltips = true,
	enableWhoTooltips = true,
	enableWhoMessages = true,
	enableGuildTooltips = true,
	enableKeystoneTooltips = true,
	showTooltipSpacing = true,
}

-- constants
local MAX_LEVEL = MAX_PLAYER_LEVEL_TABLE[LE_EXPANSION_LEGION]
local FACTION = {
	["Alliance"] = 1,
	["Horde"] = 2,
}
local SCORES = {
}
local ROLE_MASK = {
	TANK = 1,
	HEALER = 2,
	DPS = 4
}
local ROLE_COMBOS = {
	TANK_HEALER = bit.bor(ROLE_MASK.TANK, ROLE_MASK.HEALER),
	TANK_DPS = bit.bor(ROLE_MASK.TANK, ROLE_MASK.DPS),
	TANK_HEALER_DPS = bit.bor(ROLE_MASK.TANK, ROLE_MASK.HEALER, ROLE_MASK.DPS),
	HEALER_DPS = bit.bor(ROLE_MASK.HEALER, ROLE_MASK.DPS),
}
local REGIONS = {
	"us",
	"kr",
	"eu",
	"tw",
	"cn"
}

-- session constants
local PLAYER_FACTION

-- create the addon core frame
local addon = CreateFrame("Frame")

-- runs the hook process, trying to hook LOD addons
local function ApplyHooks()
	-- iterate backwards, removing hooks as they complete
	for i = #uiHooks, 1, -1 do
		local func = uiHooks[i]

		-- if the function returns true our hook succeeded, we then remove it from the table
		if func() then
			table.remove(uiHooks, i)
		end
	end
end

-- adds data provider to RaiderIO (only to be used by the other database modules)
local function AddProvider(_, data)
	-- make sure the object is what we expect it to be like
	assert(type(data.region) == "string" and type(data.faction) == "number" and type(data.db) == "table", "RaiderIO has been requested to load a database that isn't supported.")
	-- append provider to the table
	dataProviders[#dataProviders + 1] = data
end

-- the addon has just loaded, setup the config table, run or wait for the login event and register events
local function Init()
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

-- retrieves the url slug for a given realm name
local function GetRealmSlug(realm)
	return ns.realmSlugs[realm] or realm
end

-- returns the name, realm and possibly unit
local function GetNameAndRealm(arg1, arg2)
	local name, realm, unit
	if UnitExists(arg1) then
		unit = arg1
		if UnitIsPlayer(arg1) then
			name, realm = UnitName(arg1)
			realm = realm and realm ~= "" and realm or GetNormalizedRealmName()
		end
	elseif type(arg1) == "string" and arg1 ~= "" then
		if arg1:find("-", nil, true) then
			name, realm = ("-"):split(arg1)
		else
			name = arg1 -- assume this is the name
		end
		if not realm or realm == "" then
			if type(arg2) == "string" and arg2 ~= "" then
				realm = arg2
			else
				realm = GetNormalizedRealmName() -- assume they are on our realm
			end
		end
	end
	return name, realm, unit
end

-- returns 1 or 2 if the unit is Alliance or Horde, nil if neutral
local function GetFaction(unit)
	if UnitExists(unit) and UnitIsPlayer(unit) then
		local faction = UnitFactionGroup(unit)
		if faction then
			return FACTION[faction]
		end
	end
end

-- caches the profile table and returns one using keys
local function CacheProviderData(provider, name, realm, profile)
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
		roleMask = profile[1],
		allScore = profile[2],
		prevAllScore = profile[3]
	}
	-- extract the scores per role combination (very ugly, but if-else is probably most efficient... given the amount of valid role combinations)
	local tankScore, healScore, dpsScore = 0, 0, 0
	if cache.roleMask == ROLE_MASK.TANK then
		tankScore = profile[1]
	elseif cache.roleMask == ROLE_MASK.HEALER then
		healScore = profile[1]
	elseif cache.roleMask == ROLE_MASK.DPS then
		dpsScore = profile[1]
	elseif cache.roleMask == ROLE_COMBOS.TANK_HEALER then
		tankScore, healScore = profile[4], profile[5]
	elseif cache.roleMask == ROLE_COMBOS.TANK_DPS then
		tankScore, dpsScore = profile[4], profile[5]
	elseif cache.roleMask == ROLE_COMBOS.HEALER_DPS then
		healScore, dpsScore = profile[4], profile[5]
	elseif cache.roleMask == ROLE_COMBOS.TANK_HEALER_DPS then
		tankScore, healScore, dpsScore = profile[4], profile[5], profile[6]
	end
	-- append per role scores
	cache.tankScore, cache.healScore, cache.dpsScore = tankScore, healScore, dpsScore
	-- append additional role information
	cache.isTank, cache.isHealer, cache.isDPS = tankScore > 0, healScore > 0, dpsScore > 0
	cache.numRoles = (tankScore > 0 and 1 or 0) + (healScore > 0 and 1 or 0) + (dpsScore > 0 and 1 or 0)
	cache.isMultiRole = cache.numRoles > 1
	-- try find the players best role (assume it's their primary role)
	cache.primaryRole = ROLE_MASK.DPS
	local maxScore = max(tankScore, healScore, dpsScore)
	if tankScore == maxScore then
		cache.primaryRole = ROLE_MASK.TANK
	elseif healScore == maxScore then
		cache.primaryRole = ROLE_MASK.HEALER
	end
	-- store it in the profile cache
	profileCache[profile] = cache
	-- return the freshly generated table
	return cache
end

-- returns the profile of a given character, faction is optional but recommended for quicker lookups
local function GetProviderData(name, realm, faction)
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
					return CacheProviderData(p, name, realm, d)
				end
			end
		end
	end
end

-- retrieves the profile of a given unit, or name+realm query
local function GetScore(arg1, arg2, forceFaction)
	local name, realm, unit = GetNameAndRealm(arg1, arg2)
	if name and realm then
		-- no need to lookup lowbies for a score
		if unit and (UnitLevel(unit) or 0) < MAX_LEVEL then
			return
		end
		return GetProviderData(name, realm, type(forceFaction) == "number" and forceFaction or GetFaction(unit))
	end
end

-- returns score color using item colors
local function GetScoreColor(score)
	local r, g, b = 1, .5, .5
	if type(score) == "number" then
		if SCORES then
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
			else -- if score >= SCORES[6] then
				r, g, b = GetItemQualityColor(0)
			end
		else
			r, g, b = 1, 1, 1
		end
	end
	return r, g, b
end

-- appends score data to a given tooltip
local function AppendGameTooltip(tooltip, arg1, forceNoPadding, forceAddName)
	local profile = GetScore(arg1)
	if profile then
		-- assume players primary role
		local primaryRole = "DPS "
		if profile.primaryRole == ROLE_MASK.TANK then
			primaryRole = "Tank "
		elseif profile.primaryRole == ROLE_MASK.HEALER then
			primaryRole = "Healer "
		end
		-- add padding line if it looks nicer on the tooltip, also respect users preference
		if not forceNoPadding and addonConfig.showTooltipSpacing then
			tooltip:AddLine(" ")
		end
		tooltip:AddLine("Raider.IO", 1, 0.85, 0, false)
		-- show the players name if required by the calling function
		if forceAddName then
			tooltip:AddLine(profile.name .. " (" .. profile.realm .. ")", 1, 1, 1, false)
		end
		-- draw differently if the player has multiple roles or not
		if profile.isMultiRole then
			-- show the last season score if our current season score is too low relative to our last score, otherwise just show the real score
			if profile.prevAllScore > 0 and profile.prevAllScore/2 > profile.allScore then
				tooltip:AddDoubleLine("Mythic+ Score", profile.prevAllScore or "N/A", 1, 1, 1, GetScoreColor(profile.prevAllScore))
			elseif profile.allScore > 0 or profile.isMultiRole then
				tooltip:AddDoubleLine("Mythic+ Score", profile.allScore or "N/A", 1, 1, 1, GetScoreColor(profile.allScore))
			end
			-- show tank, healer and dps scores
			if profile.tankScore > 0 then
				tooltip:AddDoubleLine("Tank", profile.tankScore or "N/A", 1, 1, 1, GetScoreColor(profile.tankScore))
			end
			if profile.healScore > 0 then
				tooltip:AddDoubleLine("Healer", profile.healScore or "N/A", 1, 1, 1, GetScoreColor(profile.healScore))
			end
			if profile.dpsScore > 0 then
				tooltip:AddDoubleLine("DPS", profile.dpsScore or "N/A", 1, 1, 1, GetScoreColor(profile.dpsScore))
			end
		else
			-- show the last season score if our current season score is too low relative to our last score, otherwise just show the real score
			if profile.prevAllScore > 0 and profile.prevAllScore/2 > profile.allScore then
				tooltip:AddDoubleLine("Mythic+ " .. primaryRole .. "Score", profile.prevAllScore or "N/A", 1, 1, 1, GetScoreColor(profile.prevAllScore))
			elseif profile.allScore > 0 or profile.isMultiRole then
				tooltip:AddDoubleLine("Mythic+ " .. primaryRole .. "Score", profile.allScore or "N/A", 1, 1, 1, GetScoreColor(profile.allScore))
			end
		end
		tooltip:Show()
		return 1
	end
end

-- publicly exposed API
_G.RaiderIO = {
	-- Calling GetScore requires either a unit, or you to provide a name and realm, preferably also a faction, but it's optional.
	-- RaiderIO.GetScore(unit)
	-- RaiderIO.GetScore("Name-Realm")
	-- RaiderIO.GetScore("Name", "Realm")
	-- RaiderIO.GetScore("Name-Realm", nil, 1|2) -- 1 = alliance, 2 = horde
	-- RaiderIO.GetScore("Name", "Realm", 1|2) -- 1 = alliance, 2 = horde
	GetScore = GetScore,
	-- Please do not use the AddProvider method as it's only for internal RaiderIO use (loading the databases selected by the user)
	AddProvider = AddProvider,
}

-- an addon has loaded, is it ours? is it some LOD addon we can hook?
function addon:ADDON_LOADED(event, name)
	-- the addon savedvariables are loaded and we can initialize the addon
	if name == addonName then
		Init()
	end

	-- apply hooks to interface elements
	ApplyHooks()
end

-- we have logged in and character data is available
function addon:PLAYER_LOGIN()
	-- store our faction for later use
	PLAYER_FACTION = GetFaction("player")
	-- get the regions score table
	SCORES = ns.regionScoreStats[REGIONS[GetCurrentRegion()]:upper()]
end

-- we enter the world (after a loading screen, int/out of instances)
function addon:PLAYER_ENTERING_WORLD()
	-- we wipe the cached profiles in between loading screens, this seems like a good way get rid of memory use over time
	table.wipe(profileCache)
end

-- define our UI hooks
do
	-- GameTooltip
	uiHooks[#uiHooks + 1] = function()
		GameTooltip:HookScript("OnTooltipSetUnit", function(self)
			if addonConfig.enableUnitTooltips == false then
				return
			end
			AppendGameTooltip(self, (select(2, self:GetUnit())))
		end)
		return 1
	end

	-- LFG
	uiHooks[#uiHooks + 1] = function()
		if _G.LFGListApplicationViewerScrollFrameButton1 then
			_G.StaticPopupDialogs["RAIDERIO_COPY_URL"] = {
				text = "URL : %s",
				button2 = CLOSE,
				hasEditBox = true,
				hasWideEditBox = true,
				editBoxWidth = 350,
				preferredIndex = 3,
				timeout = 0,
				whileDead = true,
				hideOnEscape = true,
				OnShow = function(self)
					self:SetWidth(420)
					local editBox = _G[self:GetName() .. "WideEditBox"] or _G[self:GetName() .. "EditBox"]
					editBox:SetText(self.text.text_arg1)
					editBox:SetFocus()
					editBox:HighlightText(false)
					local button = _G[self:GetName() .. "Button2"]
					button:ClearAllPoints()
					button:SetWidth(200)
					button:SetPoint("CENTER", editBox, "CENTER", 0, -30)
				end,
				EditBoxOnEscapePressed = function(self)
					self:GetParent():Hide()
				end,
				OnHide = function() end,
				OnAccept = function() end,
				OnCancel = function() end
			}
			local hooked = {}
			local OnEnter, OnLeave, OnDoubleClick
			-- application queue
			function OnEnter(self)
				if addonConfig.enableLFGTooltips == false then
					return
				end
				if self.applicantID and self.Members then
					for i = 1, #self.Members do
						local b = self.Members[i]
						if not hooked[b] then
							hooked[b] = 1
							b:HookScript("OnEnter", OnEnter)
							b:HookScript("OnLeave", OnLeave)
							b:HookScript("OnDoubleClick", OnDoubleClick)
							b:RegisterForClicks("LeftButtonUp", "RightButtonUp")
						end
					end
				elseif self.memberIdx then
					local fullName = C_LFGList.GetApplicantMemberInfo(self:GetParent().applicantID, self.memberIdx)
					if fullName then
						local hasOwner = GameTooltip:GetOwner()
						if not hasOwner then
							GameTooltip:SetOwner(self, "ANCHOR_TOPLEFT", 0, 0)
						end
						AppendGameTooltip(GameTooltip, fullName, not hasOwner, true)
					end
				end
			end
			function OnLeave(self)
				if self.applicantID or self.memberIdx then
					GameTooltip:Hide()
				end
			end
			function OnDoubleClick(self, button)
				if button == "LeftButton" then
					local _, fullName
					if self.resultID then
						_, _, _, _, _, _, _, _, _, _, _, _, fullName = C_LFGList.GetSearchResultInfo(self.resultID)
					elseif self.memberIdx then
						fullName = C_LFGList.GetApplicantMemberInfo(self:GetParent().applicantID, self.memberIdx)
					end
					if fullName then
						local name, realm = GetNameAndRealm(fullName)
						realm = GetRealmSlug(realm)
						local region = REGIONS[GetCurrentRegion()]
						local url = format("https://raider.io/characters/%s/%s/%s", region, realm, name)
						if IsModifiedClick("CHATLINK") then
							local editBox = ChatFrame_OpenChat(url, DEFAULT_CHAT_FRAME)
							editBox:HighlightText()
						else
							StaticPopup_Show("RAIDERIO_COPY_URL", url)
						end
						CloseDropDownMenus()
					end
				end
			end
			for i = 1, 14 do
				local b = _G["LFGListApplicationViewerScrollFrameButton" .. i]
				b:HookScript("OnEnter", OnEnter)
				b:HookScript("OnLeave", OnLeave)
				b:HookScript("OnDoubleClick", OnDoubleClick)
				b:RegisterForClicks("LeftButtonUp", "RightButtonUp")
			end
			-- search results
			local function SetSearchEntryTooltip(tooltip, resultID, autoAcceptOption)
				local _, _, _, _, _, _, _, _, _, _, _, _, leaderName = C_LFGList.GetSearchResultInfo(resultID)
				if leaderName then
					AppendGameTooltip(tooltip, leaderName, false, true)
				end
			end
			hooksecurefunc("LFGListUtil_SetSearchEntryTooltip", SetSearchEntryTooltip)
			for i = 1, 10 do
				local b = _G["LFGListSearchPanelScrollFrameButton" .. i]
				b:HookScript("OnDoubleClick", OnDoubleClick)
				b:RegisterForClicks("LeftButtonUp", "RightButtonUp")
			end
			-- UnempoweredCover blocking removal
			do
				local f = LFGListFrame.ApplicationViewer.UnempoweredCover
				f:EnableMouse(false)
				f:EnableMouseWheel(false)
				f:SetToplevel(false)
			end
			return 1
		end
	end

	-- WhoFrame
	uiHooks[#uiHooks + 1] = function()
		local function OnEnter(self)
			if addonConfig.enableWhoTooltips == false then
				return
			end
			if self.whoIndex then
				local name, guild, level, race, class, zone, classFileName = GetWhoInfo(self.whoIndex)
				if name then
					local hasOwner = GameTooltip:GetOwner()
					if not hasOwner then
						GameTooltip:SetOwner(self, "ANCHOR_TOPLEFT", 0, 0)
					end
					if not AppendGameTooltip(GameTooltip, name, not hasOwner, true) and not hasOwner then
						GameTooltip:Hide()
					end
				end
			end
		end
		local function OnLeave(self)
			if self.whoIndex then
				GameTooltip:Hide()
			end
		end
		for i = 1, 17 do
			local b = _G["WhoFrameButton" .. i]
			b:HookScript("OnEnter", OnEnter)
			b:HookScript("OnLeave", OnLeave)
		end
		return 1
	end

	-- Blizzard_GuildUI
	uiHooks[#uiHooks + 1] = function()
		if _G.GuildFrame then
			local function OnEnter(self)
				if addonConfig.enableGuildTooltips == false then
					return
				end
				if self.guildIndex then
					local fullName = GetGuildRosterInfo(self.guildIndex)
					if fullName then
						GameTooltip:SetOwner(self, "ANCHOR_TOPLEFT", 0, 0)
						if not AppendGameTooltip(GameTooltip, fullName, true, true) then
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

	-- ChatFrame (Who Results)
	uiHooks[#uiHooks + 1] = function()
		local function pattern(pattern)
			pattern = pattern:gsub("%%", "%%%%")
			pattern = pattern:gsub("%.", "%%%.")
			pattern = pattern:gsub("%?", "%%%?")
			pattern = pattern:gsub("%+", "%%%+")
			pattern = pattern:gsub("%-", "%%%-")
			pattern = pattern:gsub("%(", "%%%(")
			pattern = pattern:gsub("%)", "%%%)")
			pattern = pattern:gsub("%[", "%%%[")
			pattern = pattern:gsub("%]", "%%%]")
			pattern = pattern:gsub("%%%%s", "(.-)")
			pattern = pattern:gsub("%%%%d", "(%%d+)")
			pattern = pattern:gsub("%%%%%%[%d%.%,]+f", "([%%d%%.%%,]+)")
			return pattern
		end
		local FORMAT_GUILD = "^" .. pattern(WHO_LIST_GUILD_FORMAT) .. "$"
		local FORMAT = "^" .. pattern(WHO_LIST_FORMAT) .. "$"
		local nameLink, name, level, race, class, guild, zone
		local repl, text, profile
		local function score(profile)
			text = ""
			-- assume players primary role
			local primaryRole = "DPS "
			if profile.primaryRole == ROLE_MASK.TANK then
				primaryRole = "Tank "
			elseif profile.primaryRole == ROLE_MASK.HEALER then
				primaryRole = "Healer "
			end
			-- draw differently if the player has multiple roles or not
			if profile.isMultiRole then
				-- show the last season score if our current season score is too low relative to our last score, otherwise just show the real score
				if profile.prevAllScore > 0 and profile.prevAllScore/2 > profile.allScore then
					text = text .. "Mythic+ Score " .. profile.prevAllScore .. " "
				elseif profile.allScore > 0 or profile.isMultiRole then
					text = text .. "Mythic+ Score " .. profile.allScore .. " "
				end
				-- show tank, healer and dps scores
				if profile.tankScore > 0 then
					text = text .. "Tank " .. profile.tankScore .. " "
				end
				if profile.healScore > 0 then
					text = text .. "Healer " .. profile.healScore .. " "
				end
				if profile.dpsScore > 0 then
					text = text .. "DPS " .. profile.dpsScore .. " "
				end
			else
				-- show the last season score if our current season score is too low relative to our last score, otherwise just show the real score
				if profile.prevAllScore > 0 and profile.prevAllScore/2 > profile.allScore then
					text = text .. "Mythic+ " .. primaryRole .. "Score " .. profile.prevAllScore .. " "
				elseif profile.allScore > 0 or profile.isMultiRole then
					text = text .. "Mythic+ " .. primaryRole .. "Score " .. profile.allScore .. " "
				end
			end
			return text
		end
		local function filter(self, event, text, ...)
			if addonConfig.enableWhoMessages ~= false and event == "CHAT_MSG_SYSTEM" then
				nameLink, name, level, race, class, guild, zone = text:match(FORMAT_GUILD)
				if not zone then
					guild = nil
					nameLink, name, level, race, class, zone = text:match(FORMAT)
				end
				if level then
					level = tonumber(level) or 0
					if level >= MAX_LEVEL then
						if guild then
							repl = format(WHO_LIST_GUILD_FORMAT, nameLink, name, level, race, class, guild, zone)
						else
							repl = format(WHO_LIST_FORMAT, nameLink, name, level, race, class, zone)
						end
						profile = GetScore(nameLink)
						if profile then
							repl = repl .. " - RaiderIO " .. score(profile)
						end
						return false, repl, ...
					end
				end
			end
			return false
		end
		ChatFrame_AddMessageEventFilter("CHAT_MSG_SYSTEM", filter)
		return 1
	end

	-- Keystone GameTooltip + ItemRefTooltip
	--[=[
	uiHooks[#uiHooks + 1] = function()
		local function OnSetItem(tooltip)
			if addonConfig.enableKeystoneTooltips == false then
				return
			end
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
	--]=]
end

-- register events and wait for the addon load event to fire
addon:SetScript("OnEvent", function(_, event, ...) addon[event](addon, event, ...) end)
addon:RegisterEvent("ADDON_LOADED")
