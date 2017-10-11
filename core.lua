local addonName, ns = ...
local uiHooks = {}
local profileCache = {}
local configFrame
local dataProvider

-- micro-optimization for more speed
local lshift = bit.lshift
local rshift = bit.rshift
local band = bit.band
local PAYLOAD_BITS = 13
local PAYLOAD_BITS2 = PAYLOAD_BITS * 2
local PAYLOAD_BITS3 = PAYLOAD_BITS * 3
local PAYLOAD_MASK = lshift(1, PAYLOAD_BITS) - 1

-- default config
local addonConfig = {
	enableUnitTooltips = true,
	enableLFGTooltips = true,
	enableLFGDropdown = true,
	enableWhoTooltips = true,
	enableWhoMessages = true,
	enableGuildTooltips = true,
	enableKeystoneTooltips = true,
	showPrevAllScore = true,
	showDropDownCopyURL = true,
}

-- constants
local L = ns.L

--TEMP TEMP UNTIL LOCALE FIXED
L = {}
L.LOCALE_NAME = "enUS"
L.CHANGES_REQUIRES_UI_RELOAD = "Your changes have been saved, but you must reload your interface for them to take effect.\r\n\r\nDo you wish to do that now?"
L.RELOAD_NOW = "Reload Now"
L.RELOAD_LATER = "I'll Reload Later"
L.RAIDERIO_MYTHIC_OPTIONS = "Raider.IO Mythic+ Options"
L.MYTHIC_PLUS_SCORES = "Mythic Plus Scores"
L.SHOW_ON_PLAYER_UNITS = "Show on Player Units"
L.SHOW_ON_PLAYER_UNITS_DESC = "Show Mythic+ Score when you mouseover player units."
L.SHOW_IN_LFD = "Show in Dungeon Finder"
L.SHOW_IN_LFD_DESC = "Show Mythic+ Score when you mouseover groups or applicants."
L.SHOW_ON_GUILD_ROSTER = "Show on Guild Roster"
L.SHOW_ON_GUILD_ROSTER_DESC = "Show Mythic+ Score when you mouseover guild members in the guild roster."
L.SHOW_IN_WHO_UI = "Show in \"Who\" UI"
L.SHOW_IN_WHO_UI_DESC = "Show Mythic+ Score when you mouseover in the Who results dialog."
L.SHOW_IN_SLASH_WHO_RESULTS = "Show in /who Results"
L.SHOW_IN_SLASH_WHO_RESULTS_DESC = "Show Mythic+ Score when you \"/who\" someone specific."
L.TOOLTIP_CUSTOMIZATION = "Tooltip Customization"
L.SHOW_KEYSTONE_INFO = "Show Keystone Info"
L.SHOW_KEYSTONE_INFO_DESC = "Adds Keystone information to Keystone tooltips. Suggests a Mythic+ Score for the group."
L.SHOW_PREV_SEASON_SCORE = "Show Previous Season Score"
L.SHOW_PREV_SEASON_SCORE_DESC = "Shows the previous season score if the players current score is lower than before."
L.COPY_RAIDERIO_PROFILE_URL = "Copy Raider.IO Profile URL"
L.ALLOW_ON_PLAYER_UNITS = "Allow on Player Units"
L.ALLOW_ON_PLAYER_UNITS_DESC = "Right-click player units to copy Raider.IO profile URL."
L.ALLOW_IN_LFD = "Allow in Dungeon Finder"
L.ALLOW_IN_LFD_DESC = "Right-click groups or applicants in Dungeon Finder to copy Raider.IO profile URL."
L.MYTHIC_PLUS_DB_MODULES = "Mythic Plus Database Modules"
L.OPEN_CONFIG = "Open Config"
L.RAIDERIO_MP_SCORE = "Raider.IO M+ Score"
L.TANK_SCORE = "Tank Score"
L.HEALER_SCORE = "Healer Score"
L.DPS_SCORE = "DPS Score"
L.PREV_SEASON_SCORE = "Previous Season Score"
L.COPY_RAIDERIO_URL = "Copy Raider.IO URL"
L.RAIDERIO_MP_SCORE_COLON = "Raider.IO M+ Score: "
L.PREV_SEASON_COLON = "Prev. Season: "
L.TANK = "Tank"
L.HEALER = "Healer"
L.DPS = "DPS"
--TEMP TEMP UNTIL LOCALE FIXED

local SCORE_TIERS = ns.scoreTiers
local MAX_LEVEL = MAX_PLAYER_LEVEL_TABLE[LE_EXPANSION_LEGION]
local FACTION = {
	["Alliance"] = 1,
	["Horde"] = 2,
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
local function AddProvider(data)
	-- make sure the object is what we expect it to be like
	assert(type(data) == "table" and type(data.name) == "string" and type(data.region) == "string" and type(data.faction) == "number", "Raider.IO has been requested to load a database that isn't supported.")
	-- is this provider relevant?
	if REGIONS[GetCurrentRegion()] == data.region then
		-- append provider to the table
		if dataProvider then
			if not dataProvider.db1 then dataProvider.db1 = data.db1 end
			if not dataProvider.db2 then dataProvider.db2 = data.db2 end
			if not dataProvider.lookup1 then dataProvider.lookup1 = data.lookup1 end
			if not dataProvider.lookup2 then dataProvider.lookup2 = data.lookup2 end
		else
			dataProvider = data
		end
	else
		-- disable the provider addon from loading in the future
		DisableAddOn(data.name)
		-- wipe the table to free up memory
		table.wipe(data)
	end
end

-- creates the config frame
local function InitConfig()
	_G.StaticPopupDialogs["RAIDERIO_RELOADUI_CONFIRM"] = {
		text = L.CHANGES_REQUIRES_UI_RELOAD,
		button1 = L.RELOAD_NOW,
		button2 = L.RELOAD_LATER,
		hasEditBox = false,
		preferredIndex = 3,
		timeout = 0,
		whileDead = true,
		hideOnEscape = true,
		OnShow = function() end,
		OnHide = function() end,
		OnAccept = function() ReloadUI() end,
		OnCancel = function() end
	}

	configFrame = CreateFrame("Frame", addonName .. "ConfigFrame", UIParent)
	configFrame:Hide()

	local config

	local function WidgetHelp_OnEnter(self)
		if self.tooltip then
			GameTooltip:SetOwner(self, "ANCHOR_TOPLEFT", 0, 0)
			GameTooltip:AddLine(self.tooltip, 1, 1, 1, true)
			GameTooltip:Show()
		end
	end

	local function WidgetButton_OnEnter(self)
		self:SetBackdropColor(0.3, 0.3, 0.3, 1)
		self:SetBackdropBorderColor(1, 1, 1, 1)
	end

	local function WidgetButton_OnLeave(self)
		self:SetBackdropColor(0, 0, 0, 1)
		self:SetBackdropBorderColor(1, 1, 1, 0.3)
	end

	local function Close_OnClick()
		configFrame:SetShown(not configFrame:IsShown())
	end

	local function Save_OnClick()
		Close_OnClick()
		local reload
		for i = 1, #config.modules do
			local f = config.modules[i]
			local checked = f.checkButton:GetChecked()
			local loaded = IsAddOnLoaded(f.addon)
			if checked then
				if not loaded then
					reload = 1
					EnableAddOn(f.addon)
				end
			elseif loaded then
				reload = 1
				DisableAddOn(f.addon)
			end
		end
		for i = 1, #config.options do
			local f = config.options[i]
			local checked = f.checkButton:GetChecked()
			local enabled = addonConfig[f.cvar]
			if f.cvar == "showDropDownCopyURL" and ((not enabled and checked) or (enabled and not checked)) then
				reload = 1
			end
			addonConfig[f.cvar] = not not checked
		end
		if reload then
			StaticPopup_Show("RAIDERIO_RELOADUI_CONFIRM")
		end
	end

	config = {
		modules = {},
		options = {},
		backdrop = {
			bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
			edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border", tile = true, tileSize = 16, edgeSize = 16,
			insets = { left = 4, right = 4, top = 4, bottom = 4 }
		},
		Update = function(self)
			for i = 1, #self.modules do
				local f = self.modules[i]
				f.checkButton:SetChecked(IsAddOnLoaded(f.addon))
			end
			for i = 1, #self.options do
				local f = self.options[i]
				f.checkButton:SetChecked(addonConfig[f.cvar] ~= false)
			end
		end,
		CreateWidget = function(self, widgetType, height)
			local widget = CreateFrame(widgetType, nil, configFrame)

			if self.lastWidget then
				widget:SetPoint("TOPLEFT", self.lastWidget, "BOTTOMLEFT", 0, -24)
				widget:SetPoint("BOTTOMRIGHT", self.lastWidget, "BOTTOMRIGHT", 0, -4)
			else
				widget:SetPoint("TOPLEFT", configFrame, "TOPLEFT", 16, -38)
				widget:SetPoint("BOTTOMRIGHT", configFrame, "TOPRIGHT", -16, -16)
			end

			widget.bg = widget:CreateTexture()
			widget.bg:SetAllPoints()
			widget.bg:SetColorTexture(0, 0, 0, 0.5)

			widget.text = widget:CreateFontString(nil, nil, "GameFontNormal")
			widget.text:SetPoint("LEFT", 8, 0)
			widget.text:SetPoint("RIGHT", -8, 0)
			widget.text:SetJustifyH("LEFT")

			widget.checkButton = CreateFrame("CheckButton", "$parentCheckButton", widget, "UICheckButtonTemplate")
			widget.checkButton:Hide()
			widget.checkButton:SetPoint("RIGHT", -4, 0)
			widget.checkButton:SetScale(0.7)

			widget.help = CreateFrame("Frame", nil, widget)
			widget.help:Hide()
			widget.help:SetPoint("LEFT", widget.checkButton, "LEFT", -20, 0)
			widget.help:SetSize(16, 16)
			widget.help:SetScale(0.9)
			widget.help.icon = widget.help:CreateTexture()
			widget.help.icon:SetAllPoints()
			widget.help.icon:SetTexture("Interface\\GossipFrame\\DailyActiveQuestIcon")

			widget.help:SetScript("OnEnter", WidgetHelp_OnEnter)
			widget.help:SetScript("OnLeave", GameTooltip_Hide)

			if widgetType == "Button" then
				widget.bg:Hide()
				widget.text:SetTextColor(1, 1, 1)
				widget:SetBackdrop(self.backdrop)
				widget:SetBackdropColor(0, 0, 0, 1)
				widget:SetBackdropBorderColor(1, 1, 1, 0.3)
				widget:SetScript("OnEnter", WidgetButton_OnEnter)
				widget:SetScript("OnLeave", WidgetButton_OnLeave)
			end

			self.lastWidget = widget
			return widget
		end,
		CreateHeadline = function(self, text)
			local frame = self:CreateWidget("Frame")
			frame.bg:Hide()
			frame.text:SetText(text)
			return frame
		end,
		CreateModuleToggle = function(self, name, addon)
			local frame = self:CreateWidget("Frame")
			frame.text:SetText(name)
			frame.addon = addon
			frame.checkButton:Show()
			self.modules[#self.modules + 1] = frame
			return frame
		end,
		CreateOptionToggle = function(self, label, description, cvar)
			local frame = self:CreateWidget("Frame")
			frame.text:SetText(label)
			frame.tooltip = description
			frame.cvar = cvar
			frame.help.tooltip = description
			frame.help:Show()
			frame.checkButton:Show()
			self.options[#self.options + 1] = frame
			return frame
		end,
	}

	-- customize the look and feel
	do
		configFrame:SetSize(280, 496)
		configFrame:SetPoint("CENTER")
		configFrame:SetFrameStrata("DIALOG")
		configFrame:SetFrameLevel(255)

		configFrame:EnableMouse(true)
		configFrame:SetClampedToScreen(true)
		configFrame:SetDontSavePosition(true)
		configFrame:SetMovable(true)
		configFrame:RegisterForDrag("LeftButton")

		configFrame:SetBackdrop(config.backdrop)
		configFrame:SetBackdropColor(0, 0, 0, 0.8)
		configFrame:SetBackdropBorderColor(0.5, 0.5, 0.5, 0.8)

		configFrame:SetScript("OnShow", function()
			if not InCombatLockdown() then
				if InterfaceOptionsFrame:IsShown() then
					InterfaceOptionsFrame_Show()
				end
				HideUIPanel(GameMenuFrame)
			end
			config:Update()
		end)

		configFrame:SetScript("OnDragStart", function(self)
			self:StartMoving()
		end)

		configFrame:SetScript("OnDragStop", function(self)
			self:StopMovingOrSizing()
		end)

		configFrame:SetScript("OnEvent", function(self, event)
			if event == "PLAYER_REGEN_ENABLED" then
				if self.combatHidden then
					self.combatHidden = nil
					self:Show()
				end
			elseif event == "PLAYER_REGEN_DISABLED" then
				if self:IsShown() then
					self.combatHidden = true
					self:Hide()
				end
			end
		end)

		configFrame:RegisterEvent("PLAYER_REGEN_ENABLED")
		configFrame:RegisterEvent("PLAYER_REGEN_DISABLED")

		-- add widgets
		local header = config:CreateHeadline(L.RAIDERIO_MYTHIC_OPTIONS)
		header.text:SetFont(header.text:GetFont(), 16, "OUTLINE")

		config:CreateHeadline(L.MYTHIC_PLUS_SCORES)
		config:CreateOptionToggle(L.SHOW_ON_PLAYER_UNITS, L.SHOW_ON_PLAYER_UNITS_DESC, "enableUnitTooltips")
		config:CreateOptionToggle(L.SHOW_IN_LFD, L.SHOW_IN_LFD_DESC, "enableLFGTooltips")
		config:CreateOptionToggle(L.SHOW_ON_GUILD_ROSTER, L.SHOW_ON_GUILD_ROSTER_DESC, "enableGuildTooltips")
		config:CreateOptionToggle(L.SHOW_IN_WHO_UI, L.SHOW_IN_WHO_UI_DESC, "enableWhoTooltips")
		config:CreateOptionToggle(L.SHOW_IN_SLASH_WHO_RESULTS, L.SHOW_IN_SLASH_WHO_RESULTS_DESC, "enableWhoMessages")

		config:CreateHeadline(L.TOOLTIP_CUSTOMIZATION)
		-- config:CreateOptionToggle(L.SHOW_KEYSTONE_INFO, L.SHOW_KEYSTONE_INFO_DESC, "enableKeystoneTooltips")
		config:CreateOptionToggle(L.SHOW_PREV_SEASON_SCORE, L.SHOW_PREV_SEASON_SCORE_DESC, "showPrevAllScore")

		config:CreateHeadline(L.COPY_RAIDERIO_PROFILE_URL)
		config:CreateOptionToggle(L.ALLOW_ON_PLAYER_UNITS, L.ALLOW_ON_PLAYER_UNITS_DESC, "showDropDownCopyURL")
		config:CreateOptionToggle(L.ALLOW_IN_LFD, L.ALLOW_IN_LFD_DESC, "enableLFGDropdown")

		config:CreateHeadline(L.MYTHIC_PLUS_DB_MODULES)
		config:CreateModuleToggle("Americas - Alliance", "RaiderIO_DB_US_A")
		config:CreateModuleToggle("Americas - Horde", "RaiderIO_DB_US_H")
		config:CreateModuleToggle("Europe - Alliance", "RaiderIO_DB_EU_A")
		config:CreateModuleToggle("Europe - Horde", "RaiderIO_DB_EU_H")
		config:CreateModuleToggle("Korea - Alliance", "RaiderIO_DB_KR_A")
		config:CreateModuleToggle("Korea - Horde", "RaiderIO_DB_KR_H")
		config:CreateModuleToggle("Taiwan - Alliance", "RaiderIO_DB_TW_A")
		config:CreateModuleToggle("Taiwan - Horde", "RaiderIO_DB_TW_H")

		-- add save button and cancel buttons
		local buttons = config:CreateWidget("Frame", 4)
		buttons:Hide()
		local save = config:CreateWidget("Button", 4)
		local cancel = config:CreateWidget("Button", 4)
		save:ClearAllPoints()
		save:SetPoint("LEFT", buttons, "LEFT", 0, -12)
		save:SetSize(96, 28)
		save.text:SetText(SAVE)
		save.text:SetJustifyH("CENTER")
		save:SetScript("OnClick", Save_OnClick)
		cancel:ClearAllPoints()
		cancel:SetPoint("RIGHT", buttons, "RIGHT", 0, -12)
		cancel:SetSize(96, 28)
		cancel.text:SetText(CANCEL)
		cancel.text:SetJustifyH("CENTER")
		cancel:SetScript("OnClick", Close_OnClick)

		-- adjust frame height dynamically
		local children = {configFrame:GetChildren()}
		local height = 64
		for i = 1, #children do
			height = height + children[i]:GetHeight()
		end
		configFrame:SetHeight(height)
	end

	-- add the category and a shortcut button in the interface panel options
	do
		local panel = CreateFrame("Frame", configFrame:GetName() .. "Panel", InterfaceOptionsFramePanelContainer)
		panel.name = addonName
		panel:Hide()

		local button = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
		button:SetText(L.OPEN_CONFIG)
		button:SetWidth(button:GetTextWidth() + 18)
		button:SetPoint("TOPLEFT", 16, -16)
		button:SetScript("OnClick", function()
			if not InCombatLockdown() then
				configFrame:SetShown(not configFrame:IsShown())
			end
		end)

		InterfaceOptions_AddCategory(panel, true)
	end

	-- create slash command to toggle the config frame
	do
		_G["SLASH_" .. addonName .. "1"] = "/raiderio"
		_G["SLASH_" .. addonName .. "2"] = "/rio"

		SlashCmdList[addonName] = function()
			if not InCombatLockdown() then
				configFrame:SetShown(not configFrame:IsShown())
			end
		end
	end
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

	-- create the config frame
	InitConfig()

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

-- unpack the payload
local function UnpackPayload(data)
	-- 4294967296 == (1 << 32). Meaning, shift to get the hi-word.
	-- WoW lua bit operators seem to only work on the lo-word (?)
	local hiword = data / 4294967296
	return 
		band(data, PAYLOAD_MASK),
		band(rshift(data, PAYLOAD_BITS), PAYLOAD_MASK),
		band(hiword, PAYLOAD_MASK),
		band(rshift(hiword, PAYLOAD_BITS), PAYLOAD_MASK)
end

-- caches the profile table and returns one using keys
local function CacheProviderData(name, realm, index, data1, data2)
	local cache = profileCache[index]

	-- prefer to re-use cached profiles
	if cache then
		return cache
	end

	-- unpack the payloads into these tables
	data1 = {UnpackPayload(data1)}
	data2 = {UnpackPayload(data2)}

	-- TODO: can we make this table read-only? raw methods will bypass metatable restrictions we try to enforce
	-- build this custom table in order to avoid users tainting the provider database
	cache = {
		region = dataProvider.region,
		faction = dataProvider.faction,
		date = dataProvider.date,
		name = name,
		realm = realm,
		-- current and last season overall score
		allScore = data1[1],
		prevAllScore = data1[2],
		-- extract the scores per role
		tankScore = data2[1],
		healScore = data2[2],
		dpsScore = data2[3]
	}

	-- append additional role information
	cache.isTank, cache.isHealer, cache.isDPS = cache.tankScore > 0, cache.healScore > 0, cache.dpsScore > 0
	cache.numRoles = (cache.tankScore > 0 and 1 or 0) + (cache.healScore > 0 and 1 or 0) + (cache.dpsScore > 0 and 1 or 0)

	-- store it in the profile cache
	profileCache[index] = cache

	-- return the freshly generated table
	return cache
end

-- retrieves the profile of a given unit, or name+realm query
local function GetScore(arg1, arg2, forceFaction)
	if not dataProvider then
		return
	end
	local name, realm, unit = GetNameAndRealm(arg1, arg2)
	if name and realm then
		-- no need to lookup lowbies for a score
		if unit and (UnitLevel(unit) or 0) < MAX_LEVEL then
			return
		end
		local faction = type(forceFaction) == "number" and forceFaction or GetFaction(unit)
		if faction then
			local db, lookup = dataProvider["db" .. faction], dataProvider["lookup" .. faction]
			if not db or not lookup then
				return
			end
			local r = db[realm]
			if r then
				local ofs = r[name]
				if ofs then
					return CacheProviderData(name, realm, ofs, lookup[ofs], lookup[ofs + 1])
				end
			end
		else
			-- FIXME: is there a better way we should be doing this if there is no faction?
			for faction = 1, 2 do
				local db, lookup = dataProvider["db" .. faction], dataProvider["lookup" .. faction]
				if not db or not lookup then
					return
				end
				local r = db[realm]
				if r then
					local ofs = r[name]
					if ofs then
						return CacheProviderData(name, realm, ofs, lookup[ofs], lookup[ofs + 1])
					end
				end
			end
		end
	end
end

-- returns score color using item colors
local function GetScoreColor(score)
	local r, g, b = 0.6, 0.6, 0.6 -- default color
	if SCORE_TIERS and type(score) == "number" then
		for i = 1, #SCORE_TIERS do
			local tier = SCORE_TIERS[i]
			if score >= tier.score then
				local color = tier.color
				return color[1], color[2], color[3]
			end
		end
	end
	return r, g, b
end

-- appends score data to a given tooltip
local function AppendGameTooltip(tooltip, arg1, forceNoPadding, forceAddName)
	local profile = GetScore(arg1)
	if profile then
		-- add padding line if it looks nicer on the tooltip, also respect users preference
		if not forceNoPadding then
			tooltip:AddLine(" ")
		end

		-- show the players name if required by the calling function
		if forceAddName then
			tooltip:AddLine(profile.name .. " (" .. profile.realm .. ")", 1, 1, 1, false)
		end

		tooltip:AddDoubleLine(L.RAIDERIO_MP_SCORE, profile.allScore, 1, 0.85, 0, GetScoreColor(profile.allScore))

		-- show tank, healer and dps scores
		local scores = {}

		if profile.tankScore then
			scores[#scores + 1] = { L.TANK_SCORE, profile.tankScore }
		end

		if profile.healScore then
			scores[#scores + 1] = { L.HEALER_SCORE, profile.healScore }
		end

		if profile.dpsScore then
			scores[#scores + 1] = { L.DPS_SCORE, profile.dpsScore }
		end

		table.sort(scores, function (a, b) return a[2] > b[2] end)

		for i = 1, #scores do
			if scores[i][2] > 0 then
				tooltip:AddDoubleLine(scores[i][1], scores[i][2], 1, 1, 1, GetScoreColor(scores[i][2]))
			end
		end

		if addonConfig.showPrevAllScore ~= false and profile.prevAllScore > profile.allScore then
			tooltip:AddDoubleLine(L.PREV_SEASON_SCORE, profile.prevAllScore, 0.8, 0.8, 0.8, GetScoreColor(profile.prevAllScore))
		end

		tooltip:Show()

		return 1
	end
end

-- publicly exposed API
_G.RaiderIO = {
	-- Calling GetScore requires either a unit, or you to provide a name and realm, optionally also a faction. (1 = Alliance, 2 = Horde)
	-- RaiderIO.GetScore(unit)
	-- RaiderIO.GetScore("Name-Realm"[, nil, 1|2])
	-- RaiderIO.GetScore("Name", "Realm"[, 1|2])
	GetScore = GetScore,
	-- Calling GetFaction requires a unit and returns you 1 if it's Alliance, 2 if Horde, otherwise nil.
	-- Calling GetScoreColor requires a Mythic+ score to be passed (a number value) and it returns r, g, b for that score.
	-- RaiderIO.GetScoreColor(1234)
	GetScoreColor = GetScoreColor,
	-- Please do not use the AddProvider method as it's only for internal Raider.IO use (loading the databases selected by the user)
	AddProvider = AddProvider
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
end

-- we enter the world (after a loading screen, int/out of instances)
function addon:PLAYER_ENTERING_WORLD()
	-- we wipe the cached profiles in between loading screens, this seems like a good way get rid of memory use over time
	table.wipe(profileCache)
end

-- define our UI hooks
do
	-- copy profile link from dropdown menu
	local function CopyURLForNameAndRealm(...)
		local name, realm = GetNameAndRealm(...)
		local realmSlug = GetRealmSlug(realm)
		local region = REGIONS[GetCurrentRegion()]
		local url = format("https://raider.io/characters/%s/%s/%s", region, realmSlug, name)
		if IsModifiedClick("CHATLINK") then
			local editBox = ChatFrame_OpenChat(url, DEFAULT_CHAT_FRAME)
			editBox:HighlightText()
		else
			StaticPopup_Show("RAIDERIO_COPY_URL", format("%s (%s)", name, realm), url)
		end
	end

	_G.StaticPopupDialogs["RAIDERIO_COPY_URL"] = {
		text = "%s",
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
			editBox:SetText(self.text.text_arg2)
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

	_G.UnitPopupButtons["RAIDERIO_COPY_URL"] = {
		text = L.COPY_RAIDERIO_URL,
		dist = 0,
		func = function()
			local dropdownFrame = UIDROPDOWNMENU_INIT_MENU
			local name, realm = dropdownFrame.name, dropdownFrame.server
			if name then
				CopyURLForNameAndRealm(name, realm)
			end
		end
	}

	hooksecurefunc("UnitPopup_ShowMenu", function(dropdownMenu, which, unit, name, userData, ...)
		for i = 1, UIDROPDOWNMENU_MAXBUTTONS do
			local button = _G["DropDownList" .. UIDROPDOWNMENU_MENU_LEVEL .. "Button" .. i]
			if button.value == "RAIDERIO_COPY_URL" then
				button.func = _G.UnitPopupButtons["RAIDERIO_COPY_URL"].func
				break
			end
		end
	end)

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
			local hooked = {}
			local OnEnter, OnLeave, OnClick
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
							b:HookScript("OnClick", OnClick)
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
			-- search results
			local function SetSearchEntryTooltip(tooltip, resultID, autoAcceptOption)
				local _, _, _, _, _, _, _, _, _, _, _, _, leaderName = C_LFGList.GetSearchResultInfo(resultID)
				if leaderName then
					AppendGameTooltip(tooltip, leaderName, false, true)
				end
			end
			hooksecurefunc("LFGListUtil_SetSearchEntryTooltip", SetSearchEntryTooltip)
			-- DropDownMenu (a lot of copy-paste of existing code, because there was no easier/cleaner way...)
			local LFG_LIST_SEARCH_ENTRY_MENU do
				LFG_LIST_SEARCH_ENTRY_MENU = {
					{
						text = nil, --Group name goes here
						isTitle = true,
						notCheckable = true,
					},
					{
						text = WHISPER_LEADER,
						func = function(_, name) ChatFrame_SendTell(name); end,
						notCheckable = true,
						arg1 = nil, --Leader name goes here
						disabled = nil, --Disabled if we don't have a leader name yet or you haven't applied
						tooltipWhileDisabled = 1,
						tooltipOnButton = 1,
						tooltipTitle = nil, --The title to display on mouseover
						tooltipText = nil, --The text to display on mouseover
					},
					{
						text = LFG_LIST_REPORT_GROUP_FOR,
						hasArrow = true,
						notCheckable = true,
						menuList = {
							{
								text = LFG_LIST_SPAM,
								func = function(_, id) C_LFGList.ReportSearchResult(id, "lfglistspam"); end,
								arg1 = nil, --Search result ID goes here
								notCheckable = true,
							},
							{
								text = LFG_LIST_BAD_NAME,
								func = function(_, id) C_LFGList.ReportSearchResult(id, "lfglistname"); end,
								arg1 = nil, --Search result ID goes here
								notCheckable = true,
							},
							{
								text = LFG_LIST_BAD_DESCRIPTION,
								func = function(_, id) C_LFGList.ReportSearchResult(id, "lfglistcomment"); end,
								arg1 = nil, --Search reuslt ID goes here
								notCheckable = true,
								disabled = nil, --Disabled if the description is just an empty string
							},
							{
								text = LFG_LIST_BAD_LEADER_NAME,
								func = function(_, id) C_LFGList.ReportSearchResult(id, "badplayername"); end,
								arg1 = nil, --Search reuslt ID goes here
								notCheckable = true,
								disabled = nil, --Disabled if we don't have a name for the leader
							},
						},
					},
					{
						text = CANCEL,
						notCheckable = true,
					},
				}
			end
			local LFG_LIST_APPLICANT_MEMBER_MENU do
				LFG_LIST_APPLICANT_MEMBER_MENU = {
					{
						text = nil, --Player name goes here
						isTitle = true,
						notCheckable = true,
					},
					{
						text = WHISPER,
						func = function(_, name) ChatFrame_SendTell(name); end,
						notCheckable = true,
						arg1 = nil, --Player name goes here
						disabled = nil, --Disabled if we don't have a name yet
					},
					{
						text = LFG_LIST_REPORT_FOR,
						hasArrow = true,
						notCheckable = true,
						menuList = {
							{
								text = LFG_LIST_BAD_PLAYER_NAME,
								notCheckable = true,
								func = function(_, id, memberIdx) C_LFGList.ReportApplicant(id, "badplayername", memberIdx); end,
								arg1 = nil, --Applicant ID goes here
								arg2 = nil, --Applicant Member index goes here
							},
							{
								text = LFG_LIST_BAD_DESCRIPTION,
								notCheckable = true,
								func = function(_, id) C_LFGList.ReportApplicant(id, "lfglistappcomment"); end,
								arg1 = nil, --Applicant ID goes here
							},
						},
					},
					{
						text = IGNORE_PLAYER,
						notCheckable = true,
						func = function(_, name, applicantID) AddIgnore(name); C_LFGList.DeclineApplicant(applicantID); end,
						arg1 = nil, --Player name goes here
						arg2 = nil, --Applicant ID goes here
						disabled = nil, --Disabled if we don't have a name yet
					},
					{
						text = CANCEL,
						notCheckable = true,
					},
				}
			end
			local DROPDOWN_ENTRY = {
				notCheckable = true,
				arg1 = nil, -- full name goes here
				text = "Copy Raider.IO URL",
				dist = 0,
				func = function(self)
					local dropdownFrame = UIDROPDOWNMENU_INIT_MENU
					local name, realm = dropdownFrame.name, dropdownFrame.server
					if name then
						CopyURLForNameAndRealm(name, realm)
					elseif self and self.arg1 then
						CopyURLForNameAndRealm(self.arg1)
					end
				end
			}
			table.insert(LFG_LIST_SEARCH_ENTRY_MENU, #LFG_LIST_SEARCH_ENTRY_MENU, DROPDOWN_ENTRY)
			table.insert(LFG_LIST_APPLICANT_MEMBER_MENU, #LFG_LIST_APPLICANT_MEMBER_MENU, DROPDOWN_ENTRY)
			local function LFGListUtil_GetSearchEntryMenu(resultID)
				local id, activityID, name, comment, voiceChat, iLvl, honorLevel, age, numBNetFriends, numCharFriends, numGuildMates, isDelisted, leaderName = C_LFGList.GetSearchResultInfo(resultID);
				local _, appStatus, pendingStatus, appDuration = C_LFGList.GetApplicationInfo(resultID);
				LFG_LIST_SEARCH_ENTRY_MENU[1].text = name;
				LFG_LIST_SEARCH_ENTRY_MENU[2].arg1 = leaderName;
				local applied = (appStatus == "applied" or appStatus == "invited");
				LFG_LIST_SEARCH_ENTRY_MENU[2].disabled = not leaderName;
				LFG_LIST_SEARCH_ENTRY_MENU[2].tooltipTitle = (not applied) and WHISPER
				LFG_LIST_SEARCH_ENTRY_MENU[2].tooltipText = (not applied) and LFG_LIST_MUST_SIGN_UP_TO_WHISPER;
				LFG_LIST_SEARCH_ENTRY_MENU[3].menuList[1].arg1 = resultID;
				LFG_LIST_SEARCH_ENTRY_MENU[3].menuList[2].arg1 = resultID;
				LFG_LIST_SEARCH_ENTRY_MENU[3].menuList[3].arg1 = resultID;
				LFG_LIST_SEARCH_ENTRY_MENU[3].menuList[3].disabled = (comment == "");
				LFG_LIST_SEARCH_ENTRY_MENU[3].menuList[4].arg1 = resultID;
				LFG_LIST_SEARCH_ENTRY_MENU[3].menuList[4].disabled = not leaderName;
				LFG_LIST_SEARCH_ENTRY_MENU[4].arg1 = leaderName
				return LFG_LIST_SEARCH_ENTRY_MENU;
			end
			local function LFGListUtil_GetApplicantMemberMenu(applicantID, memberIdx)
				local name, class, localizedClass, level, itemLevel, honorLevel, tank, healer, damage, assignedRole = C_LFGList.GetApplicantMemberInfo(applicantID, memberIdx);
				local id, status, pendingStatus, numMembers, isNew, comment = C_LFGList.GetApplicantInfo(applicantID);
				LFG_LIST_APPLICANT_MEMBER_MENU[1].text = name or " ";
				LFG_LIST_APPLICANT_MEMBER_MENU[2].arg1 = name;
				LFG_LIST_APPLICANT_MEMBER_MENU[2].disabled = not name or (status ~= "applied" and status ~= "invited");
				LFG_LIST_APPLICANT_MEMBER_MENU[3].menuList[1].arg1 = applicantID;
				LFG_LIST_APPLICANT_MEMBER_MENU[3].menuList[1].arg2 = memberIdx;
				LFG_LIST_APPLICANT_MEMBER_MENU[3].menuList[2].arg1 = applicantID;
				LFG_LIST_APPLICANT_MEMBER_MENU[3].menuList[2].disabled = (comment == "");
				LFG_LIST_APPLICANT_MEMBER_MENU[4].arg1 = name;
				LFG_LIST_APPLICANT_MEMBER_MENU[4].arg2 = applicantID;
				LFG_LIST_APPLICANT_MEMBER_MENU[4].disabled = not name;
				LFG_LIST_APPLICANT_MEMBER_MENU[5].arg1 = name
				return LFG_LIST_APPLICANT_MEMBER_MENU;
			end
			function OnClick(self, button)
				if button == "RightButton" then
					if addonConfig.showDropDownCopyURL == false then
						return
					end
					if self.resultID then
						CloseDropDownMenus()
						EasyMenu(LFGListUtil_GetSearchEntryMenu(self.resultID), LFGListFrameDropDown, self, 290, -2, "MENU")
					elseif self.memberIdx then
						CloseDropDownMenus()
						EasyMenu(LFGListUtil_GetApplicantMemberMenu(self:GetParent().applicantID, self.memberIdx), LFGListFrameDropDown, self, 60, -5, "MENU")
					end
				end
			end
			-- execute delayed hooks
			for i = 1, 14 do
				local b = _G["LFGListApplicationViewerScrollFrameButton" .. i]
				b:HookScript("OnEnter", OnEnter)
				b:HookScript("OnLeave", OnLeave)
				b:HookScript("OnClick", OnClick)
			end
			for i = 1, 10 do
				local b = _G["LFGListSearchPanelScrollFrameButton" .. i]
				b:HookScript("OnClick", OnClick)
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
						if not AppendGameTooltip(GameTooltip, fullName, true, false) then
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

			-- show the last season score if our current season score is too low relative to our last score, otherwise just show the real score
			if addonConfig.showPrevAllScore ~= false and profile.prevAllScore > profile.allScore then
				text = text .. (L.RAIDERIO_MP_SCORE_COLON):gsub("%.", "|cffFFFFFF|r.") .. profile.allScore .. " (" .. L.PREV_SEASON_COLON .. profile.prevAllScore .. "). "
			elseif profile.allScore > 0 then
				text = text .. (L.RAIDERIO_MP_SCORE_COLON):gsub("%.", "|cffFFFFFF|r.") .. profile.allScore .. ". "
			end

			-- show tank, healer and dps scores
			local scores = {}

			if profile.tankScore then
				scores[#scores + 1] = { L.TANK, profile.tankScore }
			end

			if profile.healScore then
				scores[#scores + 1] = { L.HEALER, profile.healScore }
			end

			if profile.dpsScore then
				scores[#scores + 1] = { L.DPS, profile.dpsScore }
			end

			table.sort(scores, function (a, b) return a[2] > b[2] end)

			for i = 1, #scores do
				if scores[i][2] > 0 then
					if i > 1 then
						text = text .. ", "
					end
					text = text .. scores[i][1] .. ": " .. scores[i][2]
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
							repl = repl .. " - " .. score(profile)
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

	-- DropDownMenu
	uiHooks[#uiHooks + 1] = function()
		if addonConfig.showDropDownCopyURL ~= false then
			local append = {
				"PARTY",
				"PLAYER",
				"RAID_PLAYER",
				"RAID",
				"FRIEND",
				"BN_FRIEND",
				"GUILD",
				"CHAT_ROSTER",
				"ARENAENEMY",
				"WORLD_STATE_SCORE",
			}
			for i = 1, #append do
				local key = append[i]
				local options = UnitPopupMenus[key]
				table.insert(options, #options - 1, "RAIDERIO_COPY_URL")
			end
		end
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
