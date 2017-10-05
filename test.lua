local provider

local function AddProvider(_, data)
	provider = data
end

RaiderIO = { AddProvider = AddProvider }

require("./db/db_eu_alliance")

local TANK = 1
local HEAL = 2
local DPS = 4
local ROLE_COMB = {
	TANK,
	HEAL,
	DPS,
	TANK + HEAL,
	TANK + DPS,
	TANK + HEAL + DPS,
	HEAL + DPS,
}

local roleMask, allScore, prevAllScore
local tankScore, healScore, dpsScore

for realm, realmData in pairs(provider.db) do
	for name, profile in pairs(realmData) do
		roleMask, allScore, prevAllScore = profile[1], profile[2], profile[3]

		local f
		for i = 1, #ROLE_COMB do
			if ROLE_COMB[i] == roleMask then
				f = 1
				break
			end
		end
		if not f then
			print(roleMask)
			return
		end

		--return
	end
end
