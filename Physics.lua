local addonName, ns = ...
local API = ns.API

-- Classic timing without the combat log: the Auto Shot timer (so Aimed Shot /
-- Multi-Shot do not delay the next Auto Shot) and the 2 s energy tick.
ns.Physics = ns.Physics or {}

local CLIP_WINDOW = 0.4
local ENERGY_TICK = 2
local ENERGY_WAIT = 0.45
local AUTO_SHOT = 75
local ENERGY = 3

local shotAt, shotSpeed = 0, 0
local cachedShot = 0
local energyAt, lastEnergy = 0, -1
local clipIDs

local function plainNumber(value)
	local ok, n = pcall(function()
		local v = tonumber(value)
		if type(v) ~= "number" then
			return nil
		end
		return v + 0
	end)
	if not ok or type(n) ~= "number" then
		return nil
	end
	return n
end

local function clipSet()
	if not clipIDs then
		clipIDs = {}
		local H = ns.Spell.Hunter
		for _, id in ipairs({ H.AimedShot, H.MultiShot, H.Volley }) do
			clipIDs[id] = true
		end
	end
	return clipIDs
end

-- Behavior option "Classic Auto Shot timing" (ns.db.showPhysics).
function ns.Physics.Enabled()
	return ns.db ~= nil and ns.db.showPhysics ~= false
end

function ns.Physics.IsClip(spellID)
	if not spellID then
		return false
	end
	local set = clipSet()
	if set[spellID] then
		return true
	end
	local resolved = API.Resolve(spellID)
	return resolved ~= nil and set[resolved] == true
end

-- Ranged weapon speed: UnitRangedDamage (secret in combat, so the last
-- readable value is kept), else the weapon tooltip's "Speed" line.
local function tooltipSpeed()
	if not C_TooltipInfo or not C_TooltipInfo.GetInventoryItem then
		return nil
	end
	local ok, data = pcall(C_TooltipInfo.GetInventoryItem, "player", 18)
	if not ok or type(data) ~= "table" or type(data.lines) ~= "table" then
		return nil
	end
	for _, line in ipairs(data.lines) do
		local text = type(line) == "table" and line.rightText
		if type(text) == "string" and text:lower():find("speed", 1, true) then
			local speed = plainNumber(text:match("(%d+%.?%d*)"))
			if speed and speed > 0.4 then
				return speed
			end
		end
	end
	return nil
end

local function rangedSpeed()
	if UnitRangedDamage then
		local ok, speed = pcall(UnitRangedDamage, "player")
		speed = ok and plainNumber(speed)
		if speed and speed > 0.4 then
			cachedShot = speed
			return speed
		end
	end
	if cachedShot <= 0.4 then
		cachedShot = tooltipSpeed() or 0
	end
	return cachedShot
end

-- An Auto Shot just fired.
function ns.Physics.NoteShot()
	local speed = rangedSpeed()
	if speed <= 0 then
		speed = 3
	end
	shotSpeed = speed
	shotAt = GetTime()
end

-- Energy rises by about 20 on each 2 s tick (40 with Adrenaline Rush).
function ns.Physics.NoteEnergy(current)
	current = plainNumber(current)
	if energyAt <= 0 then
		energyAt = GetTime()
	end
	if not current then
		return
	end
	if lastEnergy >= 0 then
		local gain = current - lastEnergy
		if (gain >= 18 and gain <= 22) or (gain >= 37 and gain <= 43) then
			energyAt = GetTime()
		end
	end
	lastEnergy = current
end

local function energyTickRemain()
	if energyAt <= 0 then
		return nil
	end
	local elapsed = GetTime() - energyAt
	if elapsed < 0 then
		return ENERGY_TICK
	end
	return ENERGY_TICK - (elapsed % ENERGY_TICK)
end

-- True while the next Auto Shot is about to fire: a cast now would delay it.
function ns.Physics.WouldClip()
	if shotAt <= 0 or shotSpeed <= 0 then
		return false
	end
	local elapsed = GetTime() - shotAt
	if elapsed > shotSpeed + 0.5 then
		return false
	end
	local left = math.max(0, shotSpeed - elapsed)
	return left > 0.08 and left <= CLIP_WINDOW
end

local function spellEnergyCost(spellID)
	local id = API.Resolve(spellID) or spellID
	if not C_Spell or not C_Spell.GetSpellPowerCost then
		return 0
	end
	local ok, costs = pcall(C_Spell.GetSpellPowerCost, id)
	if not ok or type(costs) ~= "table" then
		return 0
	end
	for _, cost in ipairs(costs) do
		if type(cost) == "table" then
			local needed = plainNumber(cost.cost)
			if needed and needed > 0 and plainNumber(cost.type) == ENERGY then
				return needed
			end
		end
	end
	return 0
end

-- The energy for this spell arrives with the next tick, right now.
function ns.Physics.EnergySoon(spellID)
	local cost = spellEnergyCost(spellID)
	if cost <= 0 then
		return false
	end
	local ok, cur = pcall(UnitPower, "player", ENERGY)
	cur = ok and plainNumber(cur)
	if not cur or cur >= cost or cur + 20 < cost then
		return false
	end
	local tick = energyTickRemain()
	return tick ~= nil and tick <= ENERGY_WAIT
end

-- A hunter shot that would clip Auto Shot waits (when the option is on).
function ns.Physics.Blocks(spellID)
	if not spellID or not ns.Physics.Enabled() then
		return false
	end
	return ns.Physics.IsClip(spellID) and ns.Physics.WouldClip()
end

local frame = CreateFrame("Frame")
pcall(frame.RegisterEvent, frame, "PLAYER_REGEN_ENABLED")
pcall(frame.RegisterUnitEvent, frame, "UNIT_POWER_UPDATE", "player")
pcall(frame.RegisterUnitEvent, frame, "UNIT_SPELLCAST_SUCCEEDED", "player")

frame:SetScript("OnEvent", function(_, event, _, _, spellID)
	if event == "PLAYER_REGEN_ENABLED" then
		shotAt = 0
	elseif event == "UNIT_POWER_UPDATE" then
		local ok, cur = pcall(UnitPower, "player", ENERGY)
		if ok then
			ns.Physics.NoteEnergy(cur)
		end
	elseif event == "UNIT_SPELLCAST_SUCCEEDED" and tonumber(spellID) == AUTO_SHOT then
		ns.Physics.NoteShot()
	end
end)
