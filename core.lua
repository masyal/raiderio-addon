local addonName, ns = ...

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

-- session
local uiHooks = {}
local profileCache = {}
local configFrame
local dataProviderQueue = {}
local dataProvider

-- tooltip related hooks and storage
local tooltipArgs = {}
local tooltipHooks = {
	Wipe = function()
		wipe(tooltipArgs)
	end
}

-- player
local PLAYER_FACTION
local PLAYER_REGION
local IS_DB_OUTDATED
local OUTDATED_DAYS

-- constants
local CONST_REALM_SLUGS = ns.realmSlugs
local CONST_REGION_IDS = ns.regionIDs
local CONST_SCORE_TIER = ns.scoreTiers
local CONST_SCORE_TIER_SIMPLE = ns.scoreTiersSimple
local CONST_DUNGEONS = ns.dungeons
local L = ns.L

-- enum dungeons
-- the for-loop serves two purposes: populate the enum, and localize the shortName
local ENUM_DUNGEONS = {}
for i = 1, #CONST_DUNGEONS do
	local dungeon = CONST_DUNGEONS[i]
	ENUM_DUNGEONS[dungeon.shortName] = i
	dungeon.shortNameLocale = L["DUNGEON_SHORT_NAME_" .. dungeon.shortName] or dungeon.shortName
end

-- defined constants
local MAX_LEVEL = MAX_PLAYER_LEVEL_TABLE[LE_EXPANSION_LEGION]
local OUTDATED_SECONDS = 86400 * 3 -- number of seconds before we start warning about outdated data
local NUM_FIELDS_PER_CHARACTER = 3 -- number of fields in the database lookup table for each character
local FACTION
local REGIONS
local KEYSTONE_LEVEL_TO_BASE_SCORE
local LFD_ACTIVITYID_TO_DUNGEONID
local DUNGEON_INSTANCEMAPID_TO_DUNGEONID
local KEYSTONE_INST_TO_DUNGEONID
do
	FACTION = {
		["Alliance"] = 1,
		["Horde"] = 2,
	}

	REGIONS = {
		"us",
		"kr",
		"eu",
		"tw",
		"cn"
	}

	KEYSTONE_LEVEL_TO_BASE_SCORE = {
		[2] = 20,
		[3] = 30,
		[4] = 40,
		[5] = 50,
		[6] = 60,
		[7] = 70,
		[8] = 80,
		[9] = 90,
		[10] = 100,
		[11] = 110,
		[12] = 121,
		[13] = 133,
		[14] = 146,
		[15] = 161,
		[16] = 177,
		[17] = 195,
		[18] = 214,
		[19] = 236,
		[20] = 259,
		[21] = 285,
		[22] = 314,
		[23] = 345,
		[24] = 380,
		[25] = 418,
		[26] = 459,
		[27] = 505,
		[28] = 556,
		[29] = 612,
		[30] = 673,
	}

	LFD_ACTIVITYID_TO_DUNGEONID = {
		-- Mythic Keystone
		[462] = ENUM_DUNGEONS.NL,
		[461] = ENUM_DUNGEONS.HOV,
		[460] = ENUM_DUNGEONS.DHT,
		[464] = ENUM_DUNGEONS.VOTW,
		[463] = ENUM_DUNGEONS.BRH,
		[465] = ENUM_DUNGEONS.MOS,
		[467] = ENUM_DUNGEONS.ARC,
		[459] = ENUM_DUNGEONS.EOA,
		[466] = ENUM_DUNGEONS.COS,
		[476] = ENUM_DUNGEONS.CATH,
		[486] = ENUM_DUNGEONS.SEAT,
		[471] = ENUM_DUNGEONS.LOWER,
		[473] = ENUM_DUNGEONS.UPPER,
		-- Mythic
		[448] = ENUM_DUNGEONS.NL,
		[447] = ENUM_DUNGEONS.HOV,
		[446] = ENUM_DUNGEONS.DHT,
		[451] = ENUM_DUNGEONS.VOTW,
		[450] = ENUM_DUNGEONS.BRH,
		[452] = ENUM_DUNGEONS.MOS,
		[454] = ENUM_DUNGEONS.ARC,
		[445] = ENUM_DUNGEONS.EOA,
		[453] = ENUM_DUNGEONS.COS,
		[475] = ENUM_DUNGEONS.CATH,
		[485] = ENUM_DUNGEONS.SEAT,
		-- [455] = ENUM_DUNGEONS.LOWER,
		-- [455] = ENUM_DUNGEONS.UPPER,
		-- Heroic
		[438] = ENUM_DUNGEONS.NL,
		[437] = ENUM_DUNGEONS.HOV,
		[436] = ENUM_DUNGEONS.DHT,
		[441] = ENUM_DUNGEONS.VOTW,
		[440] = ENUM_DUNGEONS.BRH,
		[442] = ENUM_DUNGEONS.MOS,
		[444] = ENUM_DUNGEONS.ARC,
		[435] = ENUM_DUNGEONS.EOA,
		[443] = ENUM_DUNGEONS.COS,
		[474] = ENUM_DUNGEONS.CATH,
		[484] = ENUM_DUNGEONS.SEAT,
		[470] = ENUM_DUNGEONS.LOWER,
		[472] = ENUM_DUNGEONS.UPPER,
		-- [439] = ENUM_DUNGEONS.AOVH,
		-- Normal
		[428] = ENUM_DUNGEONS.NL,
		[427] = ENUM_DUNGEONS.HOV,
		[426] = ENUM_DUNGEONS.DHT,
		[431] = ENUM_DUNGEONS.VOTW,
		[430] = ENUM_DUNGEONS.BRH,
		[432] = ENUM_DUNGEONS.MOS,
		[434] = ENUM_DUNGEONS.ARC,
		[425] = ENUM_DUNGEONS.EOA,
		[433] = ENUM_DUNGEONS.COS,
		-- [0] = ENUM_DUNGEONS.CATH,
		-- [0] = ENUM_DUNGEONS.SEAT,
		-- [0] = ENUM_DUNGEONS.LOWER,
		-- [0] = ENUM_DUNGEONS.UPPER,
		-- [429] = ENUM_DUNGEONS.AOVH,
	}

	DUNGEON_INSTANCEMAPID_TO_DUNGEONID = {
		[1458] = ENUM_DUNGEONS.NL,
		[1477] = ENUM_DUNGEONS.HOV,
		[1466] = ENUM_DUNGEONS.DHT,
		[1493] = ENUM_DUNGEONS.VOTW,
		[1501] = ENUM_DUNGEONS.BRH,
		[1492] = ENUM_DUNGEONS.MOS,
		[1516] = ENUM_DUNGEONS.ARC,
		[1456] = ENUM_DUNGEONS.EOA,
		[1571] = ENUM_DUNGEONS.COS,
		[1677] = ENUM_DUNGEONS.CATH,
		[1753] = ENUM_DUNGEONS.SEAT,
		[1651] = ENUM_DUNGEONS.LOWER,
		-- [1651] = ENUM_DUNGEONS.UPPER, -- has separate logic to handle this (we just pick best score out of these two)
	}

	KEYSTONE_INST_TO_DUNGEONID = {
		[206] = ENUM_DUNGEONS.NL,
		[200] = ENUM_DUNGEONS.HOV,
		[198] = ENUM_DUNGEONS.DHT,
		[207] = ENUM_DUNGEONS.VOTW,
		[199] = ENUM_DUNGEONS.BRH,
		[208] = ENUM_DUNGEONS.MOS,
		[209] = ENUM_DUNGEONS.ARC,
		[197] = ENUM_DUNGEONS.EOA,
		[210] = ENUM_DUNGEONS.COS,
		[233] = ENUM_DUNGEONS.CATH,
		[239] = ENUM_DUNGEONS.SEAT,
		[227] = ENUM_DUNGEONS.LOWER,
		[234] = ENUM_DUNGEONS.UPPER,
	}
end

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

-- create the addon core frame
local addon = CreateFrame("Frame")

-- utility functions
local GetTimezoneOffset
local GetRegion
local GetKeystoneLevel
local GetLFDStatus
local GetInstanceStatus
local GetRealmSlug
local GetNameAndRealm
local GetFaction
do
	-- get timezone offset between local and UTC+0 time
	function GetTimezoneOffset(ts)
		local u = date("!*t", ts)
		local l = date("*t", ts)
		l.isdst = false
		return difftime(time(l), time(u))
	end

	-- gets the current region name and index
	function GetRegion()
		-- use the player GUID to find the serverID and check the map for the region we are playing on
		local guid = UnitGUID("player")
		local server
		if guid then
			server = tonumber(strmatch(guid, "^Player%-(%d+)") or 0) or 0
			local i = CONST_REGION_IDS[server]
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

	-- attempts to extract the keystone level from the provided strings
	function GetKeystoneLevel(raw)
		if type(raw) ~= "string" then
			return
		end
		local level = raw:match("%+%s*(%d+)")
		if not level then
			return
		end
		return tonumber(level)
	end

	-- detect LFD queue status
	-- returns two objects, first is a table containing queued dungeons and levels, second is a true|false based on if we are hosting ourselves
	-- the first table returns the dungeon directly if we are hosting, since we can only host for one dungeon at a time anyway
	function GetLFDStatus()
		local temp = {}
		-- are we hosting our own keystone group?
		local id, activityID, _, _, name, comment = C_LFGList.GetActiveEntryInfo()
		if id then
			if activityID then
				local index = LFD_ACTIVITYID_TO_DUNGEONID[activityID]
					if index then
					temp.index = index
					temp.dungeon = CONST_DUNGEONS[index]
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
					local index = LFD_ACTIVITYID_TO_DUNGEONID[activityID]
					if index then
						temp[#temp + 1] = {
							index = index,
							dungeon = CONST_DUNGEONS[index],
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
	function GetInstanceStatus()
		local _, instanceType, _, _, _, _, _, instanceMapID = GetInstanceInfo()
		if instanceType ~= "party" then
			return
		end
		local index = DUNGEON_INSTANCEMAPID_TO_DUNGEONID[instanceMapID]
		if not index then
			return
		end
		local temp = {
			index = index,
			dungeon = CONST_DUNGEONS[index],
			level = 0
		}
		return temp, true, true
	end

	-- retrieves the url slug for a given realm name
	function GetRealmSlug(realm)
		return CONST_REALM_SLUGS[realm] or realm
	end

	-- returns the name, realm and possibly unit
	function GetNameAndRealm(arg1, arg2)
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
	function GetFaction(unit)
		if UnitExists(unit) and UnitIsPlayer(unit) then
			local faction = UnitFactionGroup(unit)
			if faction then
				return FACTION[faction]
			end
		end
	end
end

-- addon functions
local Init
local InitConfig
do
	-- update local reference to the correct savedvariable table
	local function UpdateGlobalConfigVar()
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
	end

	-- addon config is loaded so we update the local reference and register for future events
	function Init()
		-- update local reference to the correct savedvariable table
		UpdateGlobalConfigVar()

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

	-- addon config is loaded so we can build the config frame
	function InitConfig()
		_G.StaticPopupDialogs["RAIDERIO_RELOADUI_CONFIRM"] = {
			text = L.CHANGES_REQUIRES_UI_RELOAD,
			button1 = L.RELOAD_NOW,
			button2 = L.RELOAD_LATER,
			hasEditBox = false,
			preferredIndex = 3,
			timeout = 0,
			whileDead = true,
			hideOnEscape = true,
			OnShow = nil,
			OnHide = nil,
			OnAccept = ReloadUI,
			OnCancel = nil
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
				--[=[ -- TODO: OBSCOLETE?
				local enabled = addonConfig[f.cvar]
				if f.cvar == "showDropDownCopyURL" and ((not enabled and checked) or (enabled and not checked)) then
					reload = 1
				end
				--]=]
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
			}
		}

		function config.Update(self)
			for i = 1, #self.modules do
				local f = self.modules[i]
				f.checkButton:SetChecked(IsAddOnLoaded(f.addon1))
				f.checkButton2:SetChecked(IsAddOnLoaded(f.addon2))
			end
			for i = 1, #self.options do
				local f = self.options[i]
				f.checkButton:SetChecked(addonConfig[f.cvar] ~= false)
			end
		end

		function config.CreateWidget(self, widgetType, height)
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
		end

		function config.CreatePadding(self)
			local frame = self:CreateWidget("Frame")
			local _, lastWidget = frame:GetPoint(1)
			frame:ClearAllPoints()
			frame:SetPoint("TOPLEFT", lastWidget, "BOTTOMLEFT", 0, -14)
			frame:SetPoint("BOTTOMRIGHT", lastWidget, "BOTTOMRIGHT", 0, -4)
			frame.bg:Hide()
			return frame
		end

		function config.CreateHeadline(self, text)
			local frame = self:CreateWidget("Frame")
			frame.bg:Hide()
			frame.text:SetText(text)
			return frame
		end

		function config.CreateModuleToggle(self, name, addon1, addon2)
			local frame = self:CreateWidget("Frame")
			frame.text:SetText(name)
			frame.addon2 = addon1
			frame.addon1 = addon2
			frame.checkButton:Show()
			frame.checkButton2:Show()
			self.modules[#self.modules + 1] = frame
			return frame
		end

		function config.CreateOptionToggle(self, label, description, cvar)
			local frame = self:CreateWidget("Frame")
			frame.text:SetText(label)
			frame.tooltip = description
			frame.cvar = cvar
			frame.help.tooltip = description
			frame.help:Show()
			frame.checkButton:Show()
			self.options[#self.options + 1] = frame
			return frame
		end
	
		-- customize the look and feel
		do
			local function ConfigFrame_OnShow(self)
				if not InCombatLockdown() then
					if InterfaceOptionsFrame:IsShown() then
						InterfaceOptionsFrame_Show()
					end
					HideUIPanel(GameMenuFrame)
				end
				config:Update()
			end

			local function ConfigFrame_OnDragStart(self)
				self:StartMoving()
			end

			local function ConfigFrame_OnDragStop(self)
				self:StopMovingOrSizing()
			end

			local function ConfigFrame_OnEvent(self, event)
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
			end

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
	
			configFrame:SetScript("OnShow", ConfigFrame_OnShow)
			configFrame:SetScript("OnDragStart", ConfigFrame_OnDragStart)
			configFrame:SetScript("OnDragStop", ConfigFrame_OnDragStop)
			configFrame:SetScript("OnEvent", ConfigFrame_OnEvent)

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
			local function Button_OnClick()
				if not InCombatLockdown() then
					configFrame:SetShown(not configFrame:IsShown())
				end
			end

			local panel = CreateFrame("Frame", configFrame:GetName() .. "Panel", InterfaceOptionsFramePanelContainer)
			panel.name = addonName
			panel:Hide()
	
			local button = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
			button:SetText(L.OPEN_CONFIG)
			button:SetWidth(button:GetTextWidth() + 18)
			button:SetPoint("TOPLEFT", 16, -16)
			button:SetScript("OnClick", Button_OnClick)
	
			InterfaceOptions_AddCategory(panel, true)
		end
	
		-- create slash command to toggle the config frame
		do
			_G["SLASH_" .. addonName .. "1"] = "/raiderio"
			_G["SLASH_" .. addonName .. "2"] = "/rio"
	
			local function handler()
				if not InCombatLockdown() then
					configFrame:SetShown(not configFrame:IsShown())
				end
			end

			SlashCmdList[addonName] = handler
		end
	end
end

-- provider
local AddProvider
local GetScore
local GetScoreColor
do
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
			maxDungeonName = CONST_DUNGEONS[payload.maxDungeonIndex] and CONST_DUNGEONS[payload.maxDungeonIndex].shortName or '',
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

	function AddProvider(data)
		-- make sure the object is what we expect it to be like
		assert(type(data) == "table" and type(data.name) == "string" and type(data.region) == "string" and type(data.faction) == "number", "Raider.IO has been requested to load a database that isn't supported.")
		-- queue it for later inspection
		dataProviderQueue[#dataProviderQueue + 1] = data
	end

	-- retrieves the profile of a given unit, or name+realm query
	function GetScore(arg1, arg2, forceFaction)
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
	function GetScoreColor(score)
		if score == 0 or addonConfig.disableScoreColors then
			return 1, 1, 1
		end
		local r, g, b = 0.62, 0.62, 0.62
		if type(score) == "number" then
			if not addonConfig.showSimpleScoreColors then
				for i = 1, #CONST_SCORE_TIER do
					local tier = CONST_SCORE_TIER[i]
					if score >= tier.score then
						local color = tier.color
						r, g, b = color[1], color[2], color[3]
						break
					end
				end
			else
				local qualityColor = 0
				for i = 1, #CONST_SCORE_TIER_SIMPLE do
					local tier = CONST_SCORE_TIER_SIMPLE[i]
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
end

-- tooltips
local GetFormattedScore
local GetFormattedRunCount
local AppendGameTooltip
local UpdateAppendedGameTooltip
do
	local function sortRoleScores(a, b)
		return a[2] > b[2]
	end

	-- returns score formatted for current or prev season
	function GetFormattedScore(score, isPrevious)
		if isPrevious then
			return score .. " " .. L.PREV_SEASON_SUFFIX
		end
		return score
	end

	-- we only use 8 bits for a run, so decide a cap that we won't show beyond
	function GetFormattedRunCount(count)
		if count > 250 then
			return '250+'
		else
			return count
		end
	end

	-- appends score data to a given tooltip
	function AppendGameTooltip(tooltip, arg1, forceNoPadding, forceAddName, forceFaction, focusOnDungeonIndex)
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
				local d = CONST_DUNGEONS[focusOnDungeonIndex]
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
							queued.dungeon = CONST_DUNGEONS[queued.index] -- adjust the dungeon data we display
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

				sort(scores, sortRoleScores)

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

			tooltip:Show()

			return 1
		end
	end

	-- triggers a tooltip update of the current visible tooltip
	function UpdateAppendedGameTooltip()
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
end

-- addon events
do
	-- apply hooks to interface elements
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
					if not dataProvider.db1 then
						dataProvider.db1 = data.db1
					end
					if not dataProvider.db2 then
						dataProvider.db2 = data.db2
					end
					if not dataProvider.lookup1 then
						dataProvider.lookup1 = data.lookup1
					end
					if not dataProvider.lookup2 then
						dataProvider.lookup2 = data.lookup2
					end
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
		-- hide the provider function from the public API
		_G.RaiderIO.AddProvider = nil
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
end

-- ui hooks
do
	-- extract character name and realm from BNet friend
	local function GetNameAndRealmForBNetFriend(bnetIDAccount)
		local index = BNGetFriendIndex(bnetIDAccount)
		if index then
			local numGameAccounts = BNGetNumFriendGameAccounts(index)
			for i = 1, numGameAccounts do
				local _, characterName, client, realmName, _, faction, _, _, _, _, level = BNGetFriendGameAccountInfo(index, i)
				if client == BNET_CLIENT_WOW then
					if realmName then
						characterName = characterName .. "-" .. realmName:gsub("%s+", "")
					end
					return characterName, FACTION[faction], tonumber(level)
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
		OnHide = nil,
		OnAccept = nil,
		OnCancel = nil
	}

	-- GameTooltip
	uiHooks[#uiHooks + 1] = function()
		local function OnTooltipSetUnit(self)
			if not addonConfig.enableUnitTooltips then
				return
			end
			if not addonConfig.showScoreInCombat and InCombatLockdown() then
				return
			end
			local _, unit = self:GetUnit()
			AppendGameTooltip(self, unit, nil, nil, GetFaction(unit), nil)
		end
		GameTooltip:HookScript("OnTooltipSetUnit", OnTooltipSetUnit)
		return 1
	end

	-- LFG
	uiHooks[#uiHooks + 1] = function()
		if _G.LFGListApplicationViewerScrollFrameButton1 then
			local hooked = {}
			local OnEnter, OnLeave
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
					AppendGameTooltip(tooltip, leaderName, false, true, PLAYER_FACTION, LFD_ACTIVITYID_TO_DUNGEONID[activityID])
				end
			end
			hooksecurefunc("LFGListUtil_SetSearchEntryTooltip", SetSearchEntryTooltip)
			-- execute delayed hooks
			for i = 1, 14 do
				local b = _G["LFGListApplicationViewerScrollFrameButton" .. i]
				b:HookScript("OnEnter", OnEnter)
				b:HookScript("OnLeave", OnLeave)
			end
			for i = 1, 10 do
				local b = _G["LFGListSearchPanelScrollFrameButton" .. i]
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
				if name and level and level >= MAX_LEVEL then
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
			local fullName, faction, level
			if self.buttonType == FRIENDS_BUTTON_TYPE_BNET then
				local bnetIDAccount = BNGetFriendInfo(self.id)
				fullName, faction, level = GetNameAndRealmForBNetFriend(bnetIDAccount)
			elseif self.buttonType == FRIENDS_BUTTON_TYPE_WOW then
				fullName, level = GetFriendInfo(self.id)
				faction = PLAYER_FACTION
			end
			if fullName and level and level >= MAX_LEVEL then
				GameTooltip:SetOwner(FriendsTooltip, "ANCHOR_BOTTOMRIGHT", -FriendsTooltip:GetWidth(), -4)
				if not AppendGameTooltip(GameTooltip, fullName, true, true, faction, nil) then
					GameTooltip:Hide()
				end
			else
				GameTooltip:Hide()
			end
		end
		local function FriendTooltip_Hide()
			if not addonConfig.enableFriendsTooltips then
				return
			end
			GameTooltip:Hide()
		end
		local buttons = FriendsFrameFriendsScrollFrame.buttons
		for i = 1, #buttons do
			local button = buttons[i]
			button:HookScript("OnEnter", OnEnter)
		end
		hooksecurefunc("FriendsFrameTooltip_Show", OnEnter)
		hooksecurefunc(FriendsTooltip, "Hide", FriendTooltip_Hide)
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
					local fullName, _, _, level = GetGuildRosterInfo(self.guildIndex)
					if fullName and level >= MAX_LEVEL then
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
		local function sortRoleScores(a, b)
			return a[2] > b[2]
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

			sort(scores, sortRoleScores)

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

	-- DropDownMenu (Units and LFD)
	uiHooks[#uiHooks + 1] = function()
		local function CanCopyURL(which, unit, name, bnetIDAccount)
			if UnitExists(unit) then
				return UnitIsPlayer(unit) and UnitLevel(unit) >= MAX_LEVEL,
					GetUnitName(unit, true) or name,
					"UNIT"
			elseif which and which:find("^BN_") then
				local charName, charFaction, charLevel
				if bnetIDAccount then
					charName, charFaction, charLevel = GetNameAndRealmForBNetFriend(bnetIDAccount)
				end
				return charName and charLevel and charLevel >= MAX_LEVEL,
					bnetIDAccount,
					"BN",
					charName,
					charFaction
			elseif name then
				return true,
					name,
					"NAME"
			end
			return false
		end
		local function ShowCopyURLPopup(kind, query, bnetChar, bnetFaction)
			CopyURLForNameAndRealm(bnetChar or query)
		end
		local supportedTypes = {
			SELF = 1,
			PARTY = 1,
			PLAYER = 1,
			RAID_PLAYER = 1,
			RAID = 1,
			FRIEND = 1,
			BN_FRIEND = 1,
			GUILD = 1,
			GUILD_OFFLINE = 1,
			CHAT_ROSTER = 1,
			TARGET = 1,
			ARENAENEMY = 1,
			FOCUS = 1,
			WORLD_STATE_SCORE = 1,
		}
		local OFFSET_BETWEEN = 6 -- default UI makes this offset look nice
		local reskinDropDownList
		do
			local addons = {
				{
					name = "Aurora",
					func = function(list)
						local F = _G.Aurora[1]
						local menu = _G[list:GetName() .. "MenuBackdrop"]
						local backdrop = _G[list:GetName() .. "Backdrop"]
						if not backdrop.reskinned then
							F.CreateBD(menu)
							F.CreateBD(backdrop)
							backdrop.reskinned = true
						end
						OFFSET_BETWEEN = -0.5 -- need no gaps so the frames align with this addon
						return true
					end
				},
			}
			local skinned = {}
			function reskinDropDownList(list)
				if skinned[list] then
					return
				end
				for i = 1, #addons do
					local addon = addons[i]
					if IsAddOnLoaded(addon.name) then
						skinned[list] = addon.func(list)
						break
					end
				end
			end
		end
		local custom
		do
			local function CopyOnClick()
				ShowCopyURLPopup(custom.kind, custom.query, custom.bnetChar, custom.bnetFaction)
			end
			local function UpdateCopyButton()
				local copy = custom.copy
				local copyName = copy:GetName()
				local text = _G[copyName .. "NormalText"]
				text:SetText(L.COPY_RAIDERIO_PROFILE_URL)
				text:Show()
				copy:SetScript("OnClick", CopyOnClick)
				copy:Show()
			end
			local function CustomOnShow(self) -- UIDropDownMenuTemplates.xml#257
				local p = self:GetParent() or self
				local w = p:GetWidth()
				local h = 32
				for i = 1, #self.buttons do
					local b = self.buttons[i]
					if b:IsShown() then
						b:SetWidth(w - 32) -- anchor offsets for left/right
						h = h + 16
					end
				end
				self:SetHeight(h)
			end
			local function CustomButtonOnEnter(self) -- UIDropDownMenuTemplates.xml#155
				_G[self:GetName() .. "Highlight"]:Show()
			end
			local function CustomButtonOnLeave(self) -- UIDropDownMenuTemplates.xml#178
				_G[self:GetName() .. "Highlight"]:Hide()
			end
			custom = CreateFrame("Button", addonName .. "CustomDropDownList", UIParent, "UIDropDownListTemplate")
			custom:Hide()
			-- attempt to reskin using popular frameworks
			reskinDropDownList(custom)
			-- cleanup and modify the default template
			do
				custom:SetScript("OnClick", nil)
				custom:SetScript("OnEnter", nil)
				custom:SetScript("OnLeave", nil)
				custom:SetScript("OnUpdate", nil)
				custom:SetScript("OnShow", CustomOnShow)
				custom:SetScript("OnHide", nil)
				_G[custom:GetName() .. "Backdrop"]:Hide()
				custom.buttons = {}
				for i = 1, UIDROPDOWNMENU_MAXBUTTONS do
					local b = _G[custom:GetName() .. "Button" .. i]
					if not b then
						break
					end
					custom.buttons[i] = b
					b:Hide()
					b:SetScript("OnClick", nil)
					b:SetScript("OnEnter", CustomButtonOnEnter)
					b:SetScript("OnLeave", CustomButtonOnLeave)
					b:SetScript("OnEnable", nil)
					b:SetScript("OnDisable", nil)
					b:SetPoint("TOPLEFT", custom, "TOPLEFT", 16 * i, -16)
					local t = _G[b:GetName() .. "NormalText"]
					t:ClearAllPoints()
					t:SetPoint("TOPLEFT", b, "TOPLEFT", 0, 0)
					t:SetPoint("BOTTOMRIGHT", b, "BOTTOMRIGHT", 0, 0)
					_G[b:GetName() .. "Check"]:SetAlpha(0)
					_G[b:GetName() .. "UnCheck"]:SetAlpha(0)
					_G[b:GetName() .. "Icon"]:SetAlpha(0)
					_G[b:GetName() .. "ColorSwatch"]:SetAlpha(0)
					_G[b:GetName() .. "ExpandArrow"]:SetAlpha(0)
					_G[b:GetName() .. "InvisibleButton"]:SetAlpha(0)
				end
				custom.copy = custom.buttons[1]
				UpdateCopyButton()
			end
		end
		local function ShowCustomDropDown(list, dropdown, name, unit, which, bnetIDAccount)
			local show, query, kind, bnetChar, bnetFaction = CanCopyURL(which, unit, name, bnetIDAccount)
			if not show then
				return custom:Hide()
			end
			-- assign data for use with the copy function
			custom.query = query
			custom.kind = kind
			custom.bnetChar = bnetChar
			custom.bnetFaction = bnetFaction
			-- set positioning under the active dropdown
			custom:SetParent(list)
			custom:SetFrameStrata(list:GetFrameStrata())
			custom:SetFrameLevel(list:GetFrameLevel() + 2)
			custom:ClearAllPoints()
			custom:SetPoint("TOPLEFT", list, "BOTTOMLEFT", 0, OFFSET_BETWEEN)
			custom:SetPoint("TOPRIGHT", list, "BOTTOMRIGHT", 0, OFFSET_BETWEEN)
			custom:Show()
		end
		local function HideCustomDropDown()
			custom:Hide()
		end
		local function OnShow(self)
			local dropdown = self.dropdown
			if not dropdown then
				return
			end
			if dropdown.Button == _G.LFGListFrameDropDownButton then -- LFD
				if addonConfig.enableLFGDropdown then
					ShowCustomDropDown(self, dropdown, dropdown.menuList[2].arg1)
				end
			elseif dropdown.which and supportedTypes[dropdown.which] then -- UnitPopup
				if addonConfig.showDropDownCopyURL then
					ShowCustomDropDown(self, dropdown, dropdown.chatTarget or dropdown.name, dropdown.unit, dropdown.which, dropdown.bnetIDAccount)
				end
			end
		end
		local function OnHide()
			HideCustomDropDown()
		end
		DropDownList1:HookScript("OnShow", OnShow)
		DropDownList1:HookScript("OnHide", OnHide)
		return 1
	end

	-- Keystone Info
	uiHooks[#uiHooks + 1] = function()
		local function OnSetItem(tooltip)
			if not addonConfig.enableKeystoneTooltips then
				return
			end
			local _, link = tooltip:GetItem()
			if type(link) ~= "string" then
				return
			end
			local inst, lvl, a1, a2, a3 = link:match("keystone:(%d+):(%d+):(%d+):(%d+):(%d+)")
			if not lvl then
				inst, lvl, a1, a2, a3 = link:match("item:138019:.-:.-:.-:.-:.-:.-:.-:.-:.-:.-:.-:.-:(%d+):(%d+):(%d+):(%d+):(%d+)")
			end
			if not lvl then
				return
			end
			lvl = tonumber(lvl) or 0
			local baseScore = KEYSTONE_LEVEL_TO_BASE_SCORE[lvl]
			if not baseScore then
				return
			end
			tooltip:AddLine(" ")
			tooltip:AddDoubleLine(L.RAIDERIO_MP_BASE_SCORE, baseScore, 1, 0.85, 0, 1, 1, 1)
			inst = tonumber(inst)
			if inst then
				local index = KEYSTONE_INST_TO_DUNGEONID[inst]
				if index then
					local n = GetNumGroupMembers()
					if n <= 5 then -- let's show score only if we are in a 5 man group/raid
						for i = 0, n do
							local unit = i == 0 and "player" or "party" .. i
							local profile = GetScore(unit)
							if profile then
								local level = profile.dungeons[index]
								if level > 0 then
									-- TODO: sort these by dungeon level, descending
									local dungeonName = CONST_DUNGEONS[index] and " " .. CONST_DUNGEONS[index].shortName or ""
									tooltip:AddDoubleLine(UnitName(unit), "+" .. level .. dungeonName, 1, 1, 1, 1, 1, 1)
								end
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

-- API
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
}

-- PLEASE DO NOT USE (we need it public for the sake of the database modules)
_G.RaiderIO.AddProvider = AddProvider

-- register events and wait for the addon load event to fire
addon:SetScript("OnEvent", function(_, event, ...) addon[event](addon, event, ...) end)
addon:RegisterEvent("ADDON_LOADED")
