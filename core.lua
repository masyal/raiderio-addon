local addonName, ns = ...
local uiHooks = {}
local profileCache = {}
local configFrame
local dataProviderQueue = {}
local dataProvider

-- micro-optimization for more speed
local unpack = unpack
local sort = table.sort
local wipe = table.wipe
local floor = math.floor
local lshift = bit.lshift
local rshift = bit.rshift
local band = bit.band
local PAYLOAD_BITS = 13
local PAYLOAD_MASK = lshift(1, PAYLOAD_BITS) - 1
local LOOKUP_MAX_SIZE = floor(2^18-1)

-- default config
local addonConfig = {
	enableUnitTooltips = true,
	enableLFGTooltips = true,
	enableFriendsTooltips = true,
	enableLFGDropdown = true,
	enableWhoTooltips = true,
	enableWhoMessages = true,
	enableGuildTooltips = true,
	enableKeystoneTooltips = true,
	showMainsScore = true,
	showDropDownCopyURL = true,
	showSimpleScoreColors = false,
	showScoreInCombat = true,
	disableScoreColors = false,
	alwaysExtendTooltip = false,
}

-- constants
local L = ns.L
local SCORE_TIERS = ns.scoreTiers
local SCORE_TIERS_SIMPLE = ns.scoreTiersSimple

local DUNGEONS = ns.dungeons
for i = 1, #DUNGEONS, 1 do
	local dgn = DUNGEONS[i]
	dgn.shortName = L["DUNGEON_SHORT_NAME_" .. dgn.shortName] or dgn.shortName
end

local MAX_LEVEL = MAX_PLAYER_LEVEL_TABLE[LE_EXPANSION_LEGION]
local OUTDATED_SECONDS = 86400 * 3 -- number of seconds before we start warning about outdated data
local NUM_FIELDS_PER_CHARACTER = 3 -- number of fields in the database lookup table for each character
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
local LFD_ACTIVITYID_TO_ZONEID = {
	-- Mythic Keystone
	[462] = 1, -- NL    -- 1|7546
	[461] = 2, -- HOV   -- 2|7672
	[460] = 3, -- DHT   -- 3|7673
	[464] = 4, -- VOTW  -- 4|7787
	[463] = 5, -- BRH   -- 5|7805
	[465] = 6, -- MOS   -- 6|7812
	[467] = 7, -- ARC   -- 7|7855
	[459] = 8, -- EOA   -- 8|8040
	[466] = 9, -- COS   -- 9|8079
	[476] = 10, -- CATH  -- 10|8527
	[486] = 11, -- SEAT  -- 11|8910
	[471] = 12, -- LOWER -- 12|999998
	[473] = 13, -- UPPER -- 13|999999
	-- TODO: do we need all this, or is adding the "hotfix" line for SEAT enough? on the other hand wrongly categorized queues will with this trick still function to lookup scores for
	-- Mythic
	[448] = 1, -- NL
	[447] = 2, -- HOV
	[446] = 3, -- DHT
	[451] = 4, -- VOTW
	[450] = 5, -- BRH
	[452] = 6, -- MOS
	[454] = 7, -- ARC
	[445] = 8, -- EOA
	[453] = 9, -- COS
	[475] = 10, -- CATH
	[485] = 11, -- SEAT
	-- [455] = 12, -- LOWER
	-- [455] = 13, -- UPPER
	-- Heroic
	[438] = 1, -- NL
	[437] = 2, -- HOV
	[436] = 3, -- DHT
	[441] = 4, -- VOTW
	[440] = 5, -- BRH
	[442] = 6, -- MOS
	[444] = 7, -- ARC
	[435] = 8, -- EOA
	[443] = 9, -- COS
	[474] = 10, -- CATH
	[484] = 11, -- SEAT
	[470] = 12, -- LOWER
	[472] = 13, -- UPPER
	-- [439] = 0, -- AOVH
	-- Normal
	[428] = 1, -- NL
	[427] = 2, -- HOV
	[426] = 3, -- DHT
	[431] = 4, -- VOTW
	[430] = 5, -- BRH
	[432] = 6, -- MOS
	[434] = 7, -- ARC
	[425] = 8, -- EOA
	[433] = 9, -- COS
	-- [0] = 10, -- CATH
	-- [0] = 11, -- SEAT
	-- [0] = 12, -- LOWER
	-- [0] = 13, -- UPPER
	-- [429] = 0, -- AOVH
}
local DUNGEON_INSTANCEMAPID_TO_ZONEID = {
	[1458] = 1, -- NL
	[1477] = 2, -- HOV
	[1466] = 3, -- DHT
	[1493] = 4, -- VOTW
	[1501] = 5, -- BRH
	[1492] = 6, -- MOS
	[1516] = 7, -- ARC
	[1456] = 8, -- EOA
	[1571] = 9, -- COS
	[1677] = 10, -- CATH
	[1753] = 11, -- SEAT
	[1651] = 12, -- LOWER
	-- [1651] = 13, -- UPPER -- has separate logic to handle this (we just pick best score out of these two)
}
local KEYSTONE_INST_TO_ZONEID = {
	["206"] = 1, -- NL
	["200"] = 2, -- HOV
	["198"] = 3, -- DHT
	["207"] = 4, -- VOTW
	["199"] = 5, -- BRH
	["208"] = 6, -- MOS
	["209"] = 7, -- ARC
	["197"] = 8, -- EOA
	["210"] = 9, -- COS
	["233"] = 10, -- CATH
	["239"] = 11, -- SEAT
	["227"] = 12, -- LOWER
	["234"] = 13, -- UPPER
}
local KEYSTONE_LEVEL_TO_BASE_SCORE = {
	["2"] = 20,
	["3"] = 30,
	["4"] = 40,
	["5"] = 50,
	["6"] = 60,
	["7"] = 70,
	["8"] = 80,
	["9"] = 90,
	["10"] = 100,
	["11"] = 110,
	["12"] = 121,
	["13"] = 133,
	["14"] = 146,
	["15"] = 161,
	["16"] = 177,
	["17"] = 195,
	["18"] = 214,
	["19"] = 236,
	["20"] = 259,
	["21"] = 285,
	["22"] = 314,
	["23"] = 345,
	["24"] = 380,
	["25"] = 418,
	["26"] = 459,
	["27"] = 505,
	["28"] = 556,
	["29"] = 612,
	["30"] = 673,
}

-- easter
local EGG = {
	["eu"] = {
		["Ravencrest"] = {
			["Voidzone"] = "Raider.IO AddOn Author",
		},
	},
	["us"] = {
		["Skullcrusher"] = {
			["Aspyrform"] = "Raider.IO Creator",
			["Ulsoga"] = "Immeasurable Greatness",
			["Pepsiblue"] = "#millennialthings",
		},
	},
}

-- session constants
local PLAYER_FACTION
local PLAYER_REGION
local IS_DB_OUTDATED
local OUTDATED_DAYS

-- tooltip related hooks and storage
local tooltipArgs = {}
local tooltipHooks = {}

function tooltipHooks.Wipe()
	wipe(tooltipArgs)
end

-- create the addon core frame
local addon = CreateFrame("Frame")

-- get timezone offset between local and UTC+0 time
local function GetTimezoneOffset(ts)
	local u = date("!*t", ts)
	local l = date("*t", ts)
	l.isdst = false
	return difftime(time(l), time(u))
end

-- gets the current region name and index
local function GetRegion()
	-- use the player GUID to find the serverID and check the map for the region we are playing on
	local guid = UnitGUID("player")
	local server
	if guid then
		server = tonumber(strmatch(guid, "^Player%-(%d+)") or 0) or 0
		local i = ns.regionIDs[server]
		if i then
			return REGIONS[i], i
		end
	end
	-- alert the user to report this to the devs
	DEFAULT_CHAT_FRAME:AddMessage(format(L.UNKNOWN_SERVER_FOUND, addonName, guid or "N/A", GetNormalizedRealmName() or "N/A"), 1, 1, 0)
	-- fallback logic that might be wrong, but better than nothing...
	local i = GetCurrentRegion()
	return REGIONS[i], i
end

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
	-- queue it for later inspection
	dataProviderQueue[#dataProviderQueue + 1] = data
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
			local checked1 = f.checkButton:GetChecked()
			local checked2 = f.checkButton2:GetChecked()
			local loaded1 = IsAddOnLoaded(f.addon1)
			local loaded2 = IsAddOnLoaded(f.addon2)
			if checked1 then
				if not loaded1 then
					reload = 1
					EnableAddOn(f.addon1)
				end
			elseif loaded1 then
				reload = 1
				DisableAddOn(f.addon1)
			end
			if checked2 then
				if not loaded2 then
					reload = 1
					EnableAddOn(f.addon2)
				end
			elseif loaded2 then
				reload = 1
				DisableAddOn(f.addon2)
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
				f.checkButton:SetChecked(IsAddOnLoaded(f.addon1))
				f.checkButton2:SetChecked(IsAddOnLoaded(f.addon2))
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

			widget.checkButton = CreateFrame("CheckButton", "$parentCheckButton1", widget, "UICheckButtonTemplate")
			widget.checkButton:Hide()
			widget.checkButton:SetPoint("RIGHT", -4, 0)
			widget.checkButton:SetScale(0.7)

			widget.checkButton2 = CreateFrame("CheckButton", "$parentCheckButton2", widget, "UICheckButtonTemplate")
			widget.checkButton2:Hide()
			widget.checkButton2:SetPoint("RIGHT", widget.checkButton, "LEFT", -4, 0)
			widget.checkButton2:SetScale(0.7)

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
		CreatePadding = function(self)
			local frame = self:CreateWidget("Frame")
			local _, lastWidget = frame:GetPoint(1)
			frame:ClearAllPoints()
			frame:SetPoint("TOPLEFT", lastWidget, "BOTTOMLEFT", 0, -14)
			frame:SetPoint("BOTTOMRIGHT", lastWidget, "BOTTOMRIGHT", 0, -4)
			frame.bg:Hide()
			return frame
		end,
		CreateHeadline = function(self, text)
			local frame = self:CreateWidget("Frame")
			frame.bg:Hide()
			frame.text:SetText(text)
			return frame
		end,
		CreateModuleToggle = function(self, name, addon1, addon2)
			local frame = self:CreateWidget("Frame")
			frame.text:SetText(name)
			frame.addon2 = addon1
			frame.addon1 = addon2
			frame.checkButton:Show()
			frame.checkButton2:Show()
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
		configFrame:SetSize(1024, 1024) -- narrowed later in the code
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
		local header = config:CreateHeadline(L.RAIDERIO_MYTHIC_OPTIONS .. "\nVersion: " .. tostring(GetAddOnMetadata(addonName, "Version")))
		header.text:SetFont(header.text:GetFont(), 16, "OUTLINE")

		config:CreatePadding()
		config:CreateHeadline(L.MYTHIC_PLUS_SCORES)
		config:CreateOptionToggle(L.SHOW_ON_PLAYER_UNITS, L.SHOW_ON_PLAYER_UNITS_DESC, "enableUnitTooltips")
		config:CreateOptionToggle(L.SHOW_IN_LFD, L.SHOW_IN_LFD_DESC, "enableLFGTooltips")
		config:CreateOptionToggle(L.SHOW_IN_FRIENDS, L.SHOW_IN_FRIENDS_DESC, "enableFriendsTooltips")
		config:CreateOptionToggle(L.SHOW_ON_GUILD_ROSTER, L.SHOW_ON_GUILD_ROSTER_DESC, "enableGuildTooltips")
		config:CreateOptionToggle(L.SHOW_IN_WHO_UI, L.SHOW_IN_WHO_UI_DESC, "enableWhoTooltips")
		config:CreateOptionToggle(L.SHOW_IN_SLASH_WHO_RESULTS, L.SHOW_IN_SLASH_WHO_RESULTS_DESC, "enableWhoMessages")

		config:CreatePadding()
		config:CreateHeadline(L.TOOLTIP_CUSTOMIZATION)
		config:CreateOptionToggle(L.SHOW_MAINS_SCORE, L.SHOW_MAINS_SCORE_DESC, "showMainsScore")
		config:CreateOptionToggle(L.ENABLE_SIMPLE_SCORE_COLORS, L.ENABLE_SIMPLE_SCORE_COLORS_DESC, "showSimpleScoreColors")
		config:CreateOptionToggle(L.ENABLE_NO_SCORE_COLORS, L.ENABLE_NO_SCORE_COLORS_DESC, "disableScoreColors")
		config:CreateOptionToggle(L.ALWAYS_SHOW_EXTENDED_INFO, L.ALWAYS_SHOW_EXTENDED_INFO_DESC, "alwaysExtendTooltip")
		config:CreateOptionToggle(L.SHOW_SCORE_IN_COMBAT, L.SHOW_SCORE_IN_COMBAT_DESC, "showScoreInCombat")
		config:CreateOptionToggle(L.SHOW_KEYSTONE_INFO, L.SHOW_KEYSTONE_INFO_DESC, "enableKeystoneTooltips")

		config:CreatePadding()
		config:CreateHeadline(L.COPY_RAIDERIO_PROFILE_URL)
		config:CreateOptionToggle(L.ALLOW_ON_PLAYER_UNITS, L.ALLOW_ON_PLAYER_UNITS_DESC, "showDropDownCopyURL")
		config:CreateOptionToggle(L.ALLOW_IN_LFD, L.ALLOW_IN_LFD_DESC, "enableLFGDropdown")

		config:CreatePadding()
		config:CreateHeadline(L.MYTHIC_PLUS_DB_MODULES)
		local module1 = config:CreateModuleToggle(L.MODULE_AMERICAS, "RaiderIO_DB_US_A", "RaiderIO_DB_US_H")
		config:CreateModuleToggle(L.MODULE_EUROPE, "RaiderIO_DB_EU_A", "RaiderIO_DB_EU_H")
		config:CreateModuleToggle(L.MODULE_KOREA, "RaiderIO_DB_KR_A", "RaiderIO_DB_KR_H")
		config:CreateModuleToggle(L.MODULE_TAIWAN, "RaiderIO_DB_TW_A", "RaiderIO_DB_TW_H")

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
		local height = 32 + 4
		for i = 1, #children do
			height = height + children[i]:GetHeight() + 2
		end
		configFrame:SetHeight(height)

		-- adjust frame width dynamically (add padding based on the largest option label string)
		local maxWidth = 0
		for i = 1, #config.options do
			local option = config.options[i]
			if option.text and option.text:GetObjectType() == "FontString" then
				maxWidth = max(maxWidth, option.text:GetStringWidth())
			end
		end
		configFrame:SetWidth(160 + maxWidth)

		-- add faction headers over the first module
		local af = config:CreateHeadline("|TInterface\\Icons\\inv_bannerpvp_02:0:0:0:0:16:16:4:12:4:12|t")
		af:ClearAllPoints()
		af:SetPoint("BOTTOM", module1.checkButton2, "TOP", 2, -5)
		af:SetSize(32, 32)
		local hf = config:CreateHeadline("|TInterface\\Icons\\inv_bannerpvp_01:0:0:0:0:16:16:4:12:4:12|t")
		hf:ClearAllPoints()
		hf:SetPoint("BOTTOM", module1.checkButton, "TOP", 2, -5)
		hf:SetSize(32, 32)
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
		local defaults = addonConfig
		addonConfig = setmetatable(_G.RaiderIO_Config, {
			__index = function(_, key)
				return defaults[key]
			end
		})
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

	-- detect toggling of the modifier keys (additional events to try self-correct if we locked the mod key by using ALT-TAB)
	addon:RegisterEvent("MODIFIER_STATE_CHANGED")
end

-- attempts to extract the keystone level from the provided strings
local function GetKeystoneLevel(raw)
	if type(raw) ~= "string" then return end
	local level = raw:match("%+%s*(%d+)")
	if not level then return end
	return tonumber(level)
end

-- detect LFD queue status
-- returns two objects, first is a table containing queued dungeons and levels, second is a true|false based on if we are hosting ourselves
-- the first table returns the dungeon directly if we are hosting, since we can only host for one dungeon at a time anyway
local function GetLFDStatus()
	local temp = {}
	-- are we hosting our own keystone group?
	local id, activityID, _, _, name, comment = C_LFGList.GetActiveEntryInfo()
	if id then
		if activityID then
			local index = LFD_ACTIVITYID_TO_ZONEID[activityID]
				if index then
				temp.index = index
				temp.dungeon = DUNGEONS[index]
				temp.level = GetKeystoneLevel(name) or GetKeystoneLevel(comment) or 0
				return temp, true
			end
		end
		return nil, true
	end
	-- scan what we have applied to, if we aren't hosting our own keystone
	local applications = C_LFGList.GetApplications()
	for i = 1, #applications do
		local resultID = applications[i]
		local id, activityID, name, comment, _, _, _, _, _, _, _, isDelisted = C_LFGList.GetSearchResultInfo(resultID)
		if activityID then
			local _, appStatus, pendingStatus = C_LFGList.GetApplicationInfo(resultID)
			-- the application needs to be active for us to count as queued up for it
			if not isDelisted and not pendingStatus and (appStatus == "applied" or appStatus == "invited") then
				local index = LFD_ACTIVITYID_TO_ZONEID[activityID]
				if index then
					temp[#temp + 1] = {
						index = index,
						dungeon = DUNGEONS[index],
						level = GetKeystoneLevel(name) or GetKeystoneLevel(comment) or 0
					}
				end
			end
		end
	end
	-- return only if we have valid results
	if temp[1] then
		return temp, false
	end
end

-- detect what instance we are in
local function GetInstanceStatus()
	local _, instanceType, _, _, _, _, _, instanceMapID = GetInstanceInfo()
	if instanceType ~= "party" then return end
	local index = DUNGEON_INSTANCEMAPID_TO_ZONEID[instanceMapID]
	if not index then return end
	local temp = {
		index = index,
		dungeon = DUNGEONS[index],
		level = 0
	}
	return temp, true, true
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

-- search for the index of a name in the given sorted list
local function BinarySearchForName(list, name, startIndex, endIndex)
	local minIndex = startIndex
	local maxIndex = endIndex
	local mid, current

	while minIndex <= maxIndex do
		mid = floor((maxIndex + minIndex) / 2)
		current = list[mid]
		if current == name then
			return mid
		elseif current < name then
			minIndex = mid + 1
		else
			maxIndex = mid - 1
		end
	end
end

local function Split64BitNumber(dword)
	-- 0x100000000 == (1 << 32). Meaning, shift to get the hi-word.
	-- WoW lua bit operators seem to only work on the lo-word (?)
	local lo = band(dword, 0xfffffffff)
	return lo, (dword - lo) / 0x100000000
end

-- read given number of bits from the chosen offset with max of 52 bits
-- assumed that lo contains 32 bits and hi contains 20 bits
local function ReadBits(lo, hi, offset, bits)
	if offset < 32 and (offset + bits) > 32 then
    -- reading across boundary
    local mask = lshift(1, (offset + bits) - 32) - 1
    local p1 = rshift(lo, offset)
    local p2 = lshift(band(hi, mask), 32 - offset)
    return p1 + p2
	else
		local mask = lshift(1, bits) - 1
		if offset < 32 then
			-- standard read from loword
			return band(rshift(lo, offset), mask)
		else
			-- standard read from hiword
			return band(rshift(hi, offset - 32), mask)
		end
	end
end

local function UnpackCharacterData(data1, data2, data3)
	local results = {}
	local lo, hi
	local offset

	--
	-- Field 1
	--
	lo, hi = Split64BitNumber(data1)
	offset = 0

	results.allScore = ReadBits(lo, hi, offset, PAYLOAD_BITS)
	offset = offset + PAYLOAD_BITS

	results.healScore = ReadBits(lo, hi, offset, PAYLOAD_BITS)
	offset = offset + PAYLOAD_BITS

	results.tankScore = ReadBits(lo, hi, offset, PAYLOAD_BITS)
	offset = offset + PAYLOAD_BITS

	results.mainScore = ReadBits(lo, hi, offset, PAYLOAD_BITS)
	offset = offset + PAYLOAD_BITS

	results.isPrevAllScore = not (ReadBits(lo, hi, offset, 1) == 0)
	offset = offset + 1

	--
	-- Field 2
	--
	lo, hi = Split64BitNumber(data2)

	offset = 0
	results.dpsScore = ReadBits(lo, hi, offset, PAYLOAD_BITS)
	offset = offset + PAYLOAD_BITS

	local dungeonIndex = 1
	results.dungeons = {}
	for i = 1, 8 do
		results.dungeons[dungeonIndex] = ReadBits(lo, hi, offset, 5)
		dungeonIndex = dungeonIndex + 1
		offset = offset + 5
	end

	--
	-- Field 3
	--
	lo, hi = Split64BitNumber(data3)

	offset = 0
	while dungeonIndex <= #ns.dungeons do
		results.dungeons[dungeonIndex] = ReadBits(lo, hi, offset, 5)
		dungeonIndex = dungeonIndex + 1
		offset = offset + 5
	end

	local maxDungeonLevel = 0
	local maxDungeonIndex = -1	-- we may not have a max dungeon if user was brought in because of +10/+15 achievement
	for i = 1, #results.dungeons do
		if results.dungeons[i] > maxDungeonLevel then
			maxDungeonLevel = results.dungeons[i]
			maxDungeonIndex = i
		end
	end

	results.maxDungeonLevel = maxDungeonLevel
	results.maxDungeonIndex = maxDungeonIndex

	results.keystoneTenPlus = ReadBits(lo, hi, offset, 8)
	offset = offset + 8

	results.keystoneFifteenPlus = ReadBits(lo, hi, offset, 8)
	offset = offset + 8

	return results
end

-- caches the profile table and returns one using keys
local function CacheProviderData(name, realm, index, data1, data2, data3)
	local cache = profileCache[index]

	-- prefer to re-use cached profiles
	if cache then
		return cache
	end

	-- unpack the payloads into these tables
	payload = UnpackCharacterData(data1, data2, data3)

	-- TODO: can we make this table read-only? raw methods will bypass metatable restrictions we try to enforce
	-- build this custom table in order to avoid users tainting the provider database
	cache = {
		region = dataProvider.region,
		faction = dataProvider.faction,
		date = dataProvider.date,
		season = dataProvider.season,
		prevSeason = dataProvider.prevSeason,
		name = name,
		realm = realm,
		-- current and last season overall score
		allScore = payload.allScore,
		prevAllScore = payload.allScore,		-- DEPRECATED, will be removed in the future
		isPrevAllScore = payload.isPrevAllScore,
		mainScore = payload.mainScore,
		-- extract the scores per role
		dpsScore = payload.dpsScore,
		healScore = payload.healScore,
		tankScore = payload.tankScore,
		-- dungeons they have completed
		dungeons = payload.dungeons,
		maxDungeonLevel = payload.maxDungeonLevel,
		maxDungeonName = DUNGEONS[payload.maxDungeonIndex] and DUNGEONS[payload.maxDungeonIndex].shortName or '',
		keystoneTenPlus = payload.keystoneTenPlus,
		keystoneFifteenPlus = payload.keystoneFifteenPlus,
	}

	-- append additional role information
	cache.isTank, cache.isHealer, cache.isDPS = cache.tankScore > 0, cache.healScore > 0, cache.dpsScore > 0
	cache.numRoles = (cache.tankScore > 0 and 1 or 0) + (cache.healScore > 0 and 1 or 0) + (cache.dpsScore > 0 and 1 or 0)

	-- store it in the profile cache
	profileCache[index] = cache

	-- return the freshly generated table
	return cache
end

-- returns the profile of a given character, faction is optional but recommended for quicker lookups
local function GetProviderData(name, realm, faction)
	-- figure out what faction tables we want to iterate
	local a, b = 1, 2
	if faction == 1 or faction == 2 then
		a, b = faction, faction
	end
	-- iterate through the data
	local db, lu, r, d, base, bucketID, bucket
	for i = a, b do
		db, lu = dataProvider["db" .. i], dataProvider["lookup" .. i]
		-- sanity check that the data exists and is loaded, because it might not be for the requested faction
		if db and lu then
			r = db[realm]
			if r then
				d = BinarySearchForName(r, name, 2, #r)
				if d then
					-- `r[1]` = offset for this realm's characters in lookup table
					-- `d` = index of found character in realm list. note: this is offset by one because of r[1]
					-- `bucketID` is the index in the lookup table that contains that characters data
					base = r[1] + (d - 1) * NUM_FIELDS_PER_CHARACTER - (NUM_FIELDS_PER_CHARACTER - 1)
					bucketID = floor(base / LOOKUP_MAX_SIZE)
					bucket = lu[bucketID + 1]
					base = base - bucketID * LOOKUP_MAX_SIZE
					return CacheProviderData(name, realm, i .. "-" .. bucketID .. "-" .. base, bucket[base], bucket[base + 1], bucket[base + 2])
				end
			end
		end
	end
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
		return GetProviderData(name, realm, type(forceFaction) == "number" and forceFaction or GetFaction(unit))
	end
end

-- returns score color using item colors
local function GetScoreColor(score)
	if score == 0 or addonConfig.disableScoreColors then
		return 1, 1, 1
	end
	local r, g, b = 0.62, 0.62, 0.62
	if type(score) == "number" then
		if not addonConfig.showSimpleScoreColors then
			for i = 1, #SCORE_TIERS do
				local tier = SCORE_TIERS[i]
				if score >= tier.score then
					local color = tier.color
					r, g, b = color[1], color[2], color[3]
					break
				end
			end
		else
			local qualityColor = 0
			for i = 1, #SCORE_TIERS_SIMPLE do
				local tier = SCORE_TIERS_SIMPLE[i]
				if score >= tier.score then
					qualityColor = tier.quality
					break
				end
			end
			r, g, b = GetItemQualityColor(qualityColor)
		end
	end
	return r, g, b
end

-- returns score formatted for current or prev season
local function GetFormattedScore(score, isPrevious)
	if isPrevious then
		return score .. " " .. L.PREV_SEASON_SUFFIX
	end
	return score
end

-- we only use 8 bits for a run, so decide a cap that we won't show beyond
local function GetFormattedRunCount(count)
	if count > 250 then
		return '250+'
	else
		return count
	end
end

-- appends score data to a given tooltip
local function AppendGameTooltip(tooltip, arg1, forceNoPadding, forceAddName, forceFaction, focusOnDungeonIndex)
	local profile = GetScore(arg1, nil, forceFaction)

	-- sanity check that the profile exists
	if profile then

		-- HOTFIX: ALT-TAB stickyness
		addon:MODIFIER_STATE_CHANGED(true)

		-- setup tooltip hook
		if not tooltipHooks[tooltip] then
			tooltipHooks[tooltip] = true
			tooltip:HookScript("OnHide", tooltipHooks.Wipe)
		end

		-- assign the current function args for later use
		tooltipArgs[1], tooltipArgs[2], tooltipArgs[3], tooltipArgs[4], tooltipArgs[5], tooltipArgs[6] = tooltip, arg1, forceNoPadding, forceAddName, forceFaction, focusOnDungeonIndex

		-- should we show the extended version of the data?
		local showExtendedTooltip = addon.modKey or addonConfig.alwaysExtendTooltip

		-- add padding line if it looks nicer on the tooltip, also respect users preference
		if not forceNoPadding then
			tooltip:AddLine(" ")
		end

		-- show the players name if required by the calling function
		if forceAddName then
			tooltip:AddLine(profile.name .. " (" .. profile.realm .. ")", 1, 1, 1, false)
		end

		if profile.allScore > 0 then
			tooltip:AddDoubleLine(L.RAIDERIO_MP_SCORE, GetFormattedScore(profile.allScore, profile.isPrevAllScore), 1, 0.85, 0, GetScoreColor(profile.allScore))
		else
			tooltip:AddDoubleLine(L.RAIDERIO_MP_SCORE, L.UNKNOWN_SCORE, 1, 0.85, 0, 1, 1, 1)
		end

		-- choose the best highlight to show:
		-- if user has a recorded run at higher level than their highest
		-- achievement then show that. otherwise, show their highest achievement.
		local highlightStr
		if profile.keystoneFifteenPlus > 0 then
			if profile.maxDungeonLevel < 15 then
				highlightStr = L.KEYSTONE_COMPLETED_15
			end
		elseif profile.keystoneTenPlus > 0 then
			if profile.maxDungeonLevel < 10 then
				highlightStr = L.KEYSTONE_COMPLETED_10
			end
		end

		if not highlightStr and profile.maxDungeonLevel > 0 then
			highlightStr = "+" .. profile.maxDungeonLevel .. " " .. profile.maxDungeonName
		end

		-- queued/focus highlight variables
		local qHighlightStrSameAsBest, qHighlightStr1, qHighlightStr2

		-- are we focusing on a specific keystone?
		if focusOnDungeonIndex then
			local d = DUNGEONS[focusOnDungeonIndex]
			local l = profile.dungeons[focusOnDungeonIndex]
			if l > 0 then
				qHighlightStrSameAsBest = profile.maxDungeonName == d.shortName
				qHighlightStr1 = d.shortName
				qHighlightStr2 = "+" .. l
			end
		end

		-- if not, then are we queued for, or hosting a group for a keystone run?
		if not focusOnDungeonIndex then
			local queued, isHosting = GetLFDStatus()
			local waitingInsideDungeon
			-- if no LFD, are we inside a dungeon we'd like to show the score for?
			if not queued or isHosting == nil then
				queued, isHosting, waitingInsideDungeon = GetInstanceStatus()
			end
			if queued and isHosting ~= nil then
				if isHosting then
					-- we are inside dungeon waiting on our group
					if waitingInsideDungeon and (queued.index == 12 or queued.index == 13) then -- we don't know what part of karazhan we are doing
						queued.index = profile.dungeons[12] > profile.dungeons[13] and 12 or 13 -- pick best score (lower or upper)
						queued.dungeon = DUNGEONS[queued.index] -- adjust the dungeon data we display
					end
					-- we are hosting, so this is the only keystone we are interested in showing
					if profile.dungeons[queued.index] > 0 then
						qHighlightStrSameAsBest = profile.maxDungeonName == queued.dungeon.shortName
						qHighlightStr1 = queued.dungeon.shortName
						qHighlightStr2 = "+" .. profile.dungeons[queued.index]
					end
				else
					-- at the moment we pick the first queued dungeon and hope the player only queues for one dungeon at a time, not multiple different keys
					if profile.dungeons[queued[1].index] > 0 then
						qHighlightStr1 = queued[1].dungeon.shortName
						qHighlightStr2 = "+" .. profile.dungeons[queued[1].index]
					end
					-- try and see if the player is queued to something we got score for on this character
					for i = 1, #queued do
						local q = queued[i]
						local l = profile.dungeons[q.index]
						if profile.maxDungeonName == q.dungeon.shortName then
							if l > 0 then
								qHighlightStrSameAsBest = true
								qHighlightStr1 = q.dungeon.shortName
								qHighlightStr2 = "+" .. l
							end
							break
						end
					end
				end
			end
		end

		if highlightStr then
			-- if highlight is same as what we are queued for (best key) then show it as green color to make it stand out
			if qHighlightStrSameAsBest then
				tooltip:AddDoubleLine(L.BEST_RUN, highlightStr, 0, 1, 0, GetScoreColor(profile.allScore))
			else
				-- show the default best run line (it's the best piece of info we have for the player)
				tooltip:AddDoubleLine(L.BEST_RUN, highlightStr, 1, 1, 1, GetScoreColor(profile.allScore))
				-- if we have a best dungeon level to show that is different than the best run, then show it to provide context
				if qHighlightStr1 then
					tooltip:AddDoubleLine(L.BEST_FOR_DUNGEON, qHighlightStr2 .. " " .. qHighlightStr1, 1, 1, 1, GetScoreColor(profile.allScore))
				end
			end
		end

		if profile.keystoneFifteenPlus > 0 then
			tooltip:AddDoubleLine(L.TIMED_15_RUNS, GetFormattedRunCount(profile.keystoneFifteenPlus), 1, 1, 1, GetScoreColor(profile.allScore))
		end

		if profile.keystoneTenPlus > 0 and (profile.keystoneFifteenPlus == 0 or showExtendedTooltip) then
			tooltip:AddDoubleLine(L.TIMED_10_RUNS, GetFormattedRunCount(profile.keystoneTenPlus), 1, 1, 1, GetScoreColor(profile.allScore))
		end

		-- show tank, healer and dps scores (only when the tooltip is extended)
		if showExtendedTooltip then
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

			sort(scores, function (a, b) return a[2] > b[2] end)

			for i = 1, #scores do
				if scores[i][2] > 0 then
					tooltip:AddDoubleLine(scores[i][1], scores[i][2], 1, 1, 1, GetScoreColor(scores[i][2]))
				end
			end
		end

		if addonConfig.showMainsScore and profile.mainScore > profile.allScore then
			tooltip:AddDoubleLine(L.MAINS_SCORE, profile.mainScore, 1, 1, 1, GetScoreColor(profile.mainScore))
		end

		if IS_DB_OUTDATED then
			tooltip:AddLine(format(L.OUTDATED_DATABASE, OUTDATED_DAYS), 1, 1, 1, false)
		end

		do
			local t = EGG[profile.region]
			if t then
				t = t[profile.realm]
				if t then
					t = t[profile.name]
					if t then
						tooltip:AddLine(t, 0.9, 0.8, 0.5, false)
					end
				end
			end
		end

		tooltip:Show()

		return 1
	end
end

-- triggers a tooltip update of the current visible tooltip
local function UpdateAppendedGameTooltip()
	-- sanity check that the args exist
	if not tooltipArgs[1] or not tooltipArgs[1]:GetOwner() then return end
	-- unpack the args
	local tooltip, arg1, forceNoPadding, forceAddName, forceFaction, focusOnDungeonIndex = tooltipArgs[1], tooltipArgs[2], tooltipArgs[3], tooltipArgs[4], tooltipArgs[5], tooltipArgs[6]
	-- units only need to SetUnit to re-draw the tooltip properly
	local _, unit = tooltip:GetUnit()
	if unit then
		tooltip:SetUnit(unit)
		return
	end
	-- gather tooltip information
	local o1, o2, o3, o4 = tooltip:GetOwner()
	local p1, p2, p3, p4, p5 = tooltip:GetPoint(1)
	local a1, a2, a3 = tooltip:GetAnchorType()
	-- try to run the OnEnter handler to simulate the user hovering over and triggering the tooltip
	if o1 then
		local oe = o1:GetScript("OnEnter")
		if oe then
			tooltip:Hide()
			oe(o1)
			return
		end
	end
	-- if nothing else worked, attempt to hide, then show the tooltip again in the same place
	tooltip:Hide()
	if o1 then
		o2 = a1
		if p4 then
			o3 = p4
		end
		if p5 then
			o4 = p5
		end
		tooltip:SetOwner(o1, o2, o3, o4)
	end
	if p1 then
		tooltip:SetPoint(p1, p2, p3, p4, p5)
	end
	if not o1 and a1 then
		tooltip:SetAnchorType(a1, a2, a3)
	end
	-- finalize by appending our tooltip on the bottom
	AppendGameTooltip(tooltip, arg1, forceNoPadding, forceAddName, forceFaction, focusOnDungeonIndex)
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
	PLAYER_REGION = GetRegion()
	-- pick the data provider that suits the players region
	for i = #dataProviderQueue, 1, -1 do
		local data = dataProviderQueue[i]
		-- is this provider relevant?
		if data.region == PLAYER_REGION then
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
			wipe(data)
		end
		-- remove reference from the queue
		dataProviderQueue[i] = nil
	end
	-- is the provider up to date?
	if dataProvider then
		local year, month, day, hours, minutes, seconds = dataProvider.date:match("^(%d+)%-(%d+)%-(%d+)T(%d+):(%d+):(%d+).*Z$")
		-- parse the ISO timestamp to unix time
		local ts = time({ year = year, month = month, day = day, hour = hours, min = minutes, sec = seconds })
		-- calculate the timezone offset between the user and UTC+0
		local offset = GetTimezoneOffset(ts)
		-- find elapsed seconds since database update and account for the timezone offset
		local diff = time() - ts - offset
		-- figure out of the DB is outdated or not by comparing to our threshold
		IS_DB_OUTDATED = diff >= OUTDATED_SECONDS
		OUTDATED_DAYS = floor(diff / 86400 + 0.5)
		if IS_DB_OUTDATED then
			DEFAULT_CHAT_FRAME:AddMessage(format(L.OUTDATED_DATABASE_S, addonName, OUTDATED_DAYS), 1, 1, 0)
		end
	end
end

-- we enter the world (after a loading screen, int/out of instances)
function addon:PLAYER_ENTERING_WORLD()
	-- we wipe the cached profiles in between loading screens, this seems like a good way get rid of memory use over time
	wipe(profileCache)
end

-- modifier key is toggled, update the tooltip if needed
function addon:MODIFIER_STATE_CHANGED(skipUpdatingTooltip)
	-- if we always draw the full tooltip then this part of the code shouldn't be running at all
	if addonConfig.alwaysExtendTooltip then
		return
	end
	-- check if the mod state has changed, and only then run the update function
	local m = IsModifierKeyDown()
	local l = addon.modKey
	addon.modKey = m
	if m ~= l and skipUpdatingTooltip ~= true then
		UpdateAppendedGameTooltip()
	end
end

-- define our UI hooks
do
	-- extract character name and realm from BNet friend
	local function GetNameAndRealmForBNetFriend(bnetIDAccount)
		local index = BNGetFriendIndex(bnetIDAccount)
		if index then
			local numGameAccounts = BNGetNumFriendGameAccounts(index)
			for i = 1, numGameAccounts do
				local _, characterName, client, realmName, _, faction = BNGetFriendGameAccountInfo(index, i)
				if client == BNET_CLIENT_WOW then
					if realmName then
						characterName = characterName .. "-" .. realmName:gsub("%s+", "")
					end
					return characterName, FACTION[faction]
				end
			end
		end
	end

	-- copy profile link from dropdown menu
	local function CopyURLForNameAndRealm(...)
		local name, realm = GetNameAndRealm(...)
		local realmSlug = GetRealmSlug(realm)
		local url = format("https://raider.io/characters/%s/%s/%s", PLAYER_REGION, realmSlug, name)
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
			if dropdownFrame.which:find("^BN_") then
				name, realm = GetNameAndRealmForBNetFriend(dropdownFrame.bnetIDAccount), nil
			end
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
			if not addonConfig.enableUnitTooltips then
				return
			end
			if not addonConfig.showScoreInCombat and InCombatLockdown() then
				return
			end
			local _, unit = self:GetUnit()
			AppendGameTooltip(self, unit, nil, nil, GetFaction(unit), nil)
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
				if not addonConfig.enableLFGTooltips then
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
						AppendGameTooltip(GameTooltip, fullName, not hasOwner, true, PLAYER_FACTION, nil)
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
				local _, activityID, _, _, _, _, _, _, _, _, _, _, leaderName = C_LFGList.GetSearchResultInfo(resultID)
				if leaderName then
					AppendGameTooltip(tooltip, leaderName, false, true, PLAYER_FACTION, LFD_ACTIVITYID_TO_ZONEID[activityID])
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
					if not addonConfig.showDropDownCopyURL then
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
			if not addonConfig.enableWhoTooltips then
				return
			end
			if self.whoIndex then
				local name, guild, level, race, class, zone, classFileName = GetWhoInfo(self.whoIndex)
				if name then
					local hasOwner = GameTooltip:GetOwner()
					if not hasOwner then
						GameTooltip:SetOwner(self, "ANCHOR_TOPLEFT", 0, 0)
					end
					if not AppendGameTooltip(GameTooltip, name, not hasOwner, true, PLAYER_FACTION, nil) and not hasOwner then
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

	-- FriendsFrame
	uiHooks[#uiHooks + 1] = function()
		local function OnEnter(self)
			if not addonConfig.enableFriendsTooltips then
				return
			end
			local fullName, faction
			if self.buttonType == FRIENDS_BUTTON_TYPE_BNET then
				local bnetIDAccount = BNGetFriendInfo(self.id)
				fullName, faction = GetNameAndRealmForBNetFriend(bnetIDAccount)
			elseif self.buttonType == FRIENDS_BUTTON_TYPE_WOW then
				fullName = GetFriendInfo(self.id)
				faction = PLAYER_FACTION
			end
			if fullName then
				GameTooltip:SetOwner(FriendsTooltip, "ANCHOR_BOTTOMRIGHT", -FriendsTooltip:GetWidth(), -4)
				if not AppendGameTooltip(GameTooltip, fullName, true, true, faction, nil) then
					GameTooltip:Hide()
				end
			else
				GameTooltip:Hide()
			end
		end
		local buttons = FriendsFrameFriendsScrollFrame.buttons
		for i = 1, #buttons do
			local button = buttons[i]
			button:HookScript("OnEnter", OnEnter)
		end
		hooksecurefunc("FriendsFrameTooltip_Show", OnEnter)
		hooksecurefunc(FriendsTooltip, "Hide", function()
			if not addonConfig.enableFriendsTooltips then
				return
			end
			GameTooltip:Hide()
		end)
		return 1
	end

	-- Blizzard_GuildUI
	uiHooks[#uiHooks + 1] = function()
		if _G.GuildFrame then
			local function OnEnter(self)
				if not addonConfig.enableGuildTooltips then
					return
				end
				if self.guildIndex then
					local fullName = GetGuildRosterInfo(self.guildIndex)
					if fullName then
						GameTooltip:SetOwner(self, "ANCHOR_TOPLEFT", 0, 0)
						if not AppendGameTooltip(GameTooltip, fullName, true, false, PLAYER_FACTION, nil) then
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

			if profile.allScore > 0 then
				text = text .. (L.RAIDERIO_MP_SCORE_COLON):gsub("%.", "|cffFFFFFF|r.") .. GetFormattedScore(profile.allScore, profile.isPrevAllScore) .. ". "
			end

			-- show the mains season score
			if addonConfig.showMainsScore and profile.mainScore > profile.allScore then
				text = text .. "(" .. L.MAINS_SCORE_COLON .. profile.mainScore .. "). "
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

			sort(scores, function (a, b) return a[2] > b[2] end)

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
			if addonConfig.enableWhoMessages and event == "CHAT_MSG_SYSTEM" then
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
						profile = GetScore(nameLink, nil, PLAYER_FACTION)
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
		if addonConfig.showDropDownCopyURL then
			local append = {
				"PLAYER", -- TAINT?
				"FRIEND",
				-- "BN_FRIEND", -- TAINT?
				-- "GUILD", -- TAINT
			}
			for i = 1, #append do
				local key = append[i]
				local options = UnitPopupMenus[key]
				table.insert(options, #options - 1, "RAIDERIO_COPY_URL")
			end
		end
		return 1
	end

	-- Keystone Info
	uiHooks[#uiHooks + 1] = function()
		local function OnSetItem(tooltip)
			if not addonConfig.enableKeystoneTooltips then
				return
			end
			local _, link = tooltip:GetItem()
			if type(link) ~= "string" then return end
			local inst, lvl, a1, a2, a3 = link:match("keystone:(%d+):(%d+):(%d+):(%d+):(%d+)")
			if not lvl then inst, lvl, a1, a2, a3 = link:match("item:138019:.-:.-:.-:.-:.-:.-:.-:.-:.-:.-:.-:.-:(%d+):(%d+):(%d+):(%d+):(%d+)") end
			if not lvl then return end
			local baseScore = KEYSTONE_LEVEL_TO_BASE_SCORE[lvl]
			if not baseScore then return end
			tooltip:AddLine(" ")
			tooltip:AddDoubleLine(L.RAIDERIO_MP_BASE_SCORE, baseScore, 1, 0.85, 0, 1, 1, 1)
			local index = KEYSTONE_INST_TO_ZONEID[inst]
			if index then
				local n = GetNumGroupMembers()
				if n <= 5 then -- let's show score only if we are in a 5 man group/raid
					for i = 0, n, 1 do
						local unit = i == 0 and "player" or "party" .. i
						local profile = GetScore(unit)
						if profile then
							local level = profile.dungeons[index]
							if level > 0 then
								-- TODO: sort these by dungeon level, descending
								local dungeonName = DUNGEONS[index] and " " .. DUNGEONS[index].shortName or ""
								tooltip:AddDoubleLine(UnitName(unit), "+" .. level .. dungeonName, 1, 1, 1, 1, 1, 1)
							end
						end
					end
				end
			end
			tooltip:Show()
		end
		GameTooltip:HookScript("OnTooltipSetItem", OnSetItem)
		ItemRefTooltip:HookScript("OnTooltipSetItem", OnSetItem)
		return 1
	end
end

-- register events and wait for the addon load event to fire
addon:SetScript("OnEvent", function(_, event, ...) addon[event](addon, event, ...) end)
addon:RegisterEvent("ADDON_LOADED")
