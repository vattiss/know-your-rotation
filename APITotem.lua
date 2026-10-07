local addonName, ns = ...
local I = ns.API.I

-- Shaman totems, kept through combat when the client hides them.
local normName, readable, safe = I.normName, I.readable, I.safe

-- Totems. GetTotemInfo is secret in combat (SecretWhenTotemSlotSecret), so
-- readable reads teach each totem's slot and duration and our own casts
-- stand in during combat (one totem per slot: a new one replaces the old).
-- A totem you walked away from (UnitPosition, more than TOTEM_RANGE yards)
-- counts as gone, so a new pull gets a new one.
local TOTEM_RANGE = 20
local totemSlotOf, totemSecondsOf = {}, {}
local totemOut = {}
local totemInfoByName

local function totemFamily(key)
	return (key:gsub("%s+totem$", ""):gsub("^totem%s+", ""))
end

local function totemMatches(key, wantKey, wantFamily)
	if key == wantKey then
		return true
	end
	local family = totemFamily(key)
	return family == wantFamily or key:find(wantFamily, 1, true) ~= nil
end

local function totemInfo(spellID, key)
	local map = ns.TOTEM_INFO
	if not map then
		return nil
	end
	local resolved = ns.API.Resolve(spellID) or spellID
	if map[resolved] or map[spellID] then
		return map[resolved] or map[spellID]
	end
	if not totemInfoByName or not next(totemInfoByName) then
		totemInfoByName = {}
		for id, row in pairs(map) do
			local name = ns.API.SpellName(id)
			if type(name) == "string" and name ~= "" then
				totemInfoByName[normName(name)] = row
			end
		end
	end
	return key and totemInfoByName[key] or nil
end

local function playerSpot()
	local ok, x, y, _, map = pcall(UnitPosition, "player")
	if not ok then
		return nil
	end
	x, y, map = safe(x, nil), safe(y, nil), safe(map, nil)
	if type(x) ~= "number" or type(y) ~= "number" then
		return nil
	end
	return x, y, map
end

local function walkedAway(entry)
	if not entry or not entry.x then
		return false
	end
	local x, y, map = playerSpot()
	if not x then
		return false
	end
	if map ~= entry.map then
		return true
	end
	local dx, dy = x - entry.x, y - entry.y
	return dx * dx + dy * dy > TOTEM_RANGE * TOTEM_RANGE
end

local function readTotemSlot(slot)
	local ok, haveTotem, totemName, startTime, duration = pcall(GetTotemInfo, slot)
	if not ok or not readable(haveTotem) then
		return nil
	end
	if not haveTotem then
		return false
	end
	if
		not readable(totemName)
		or not readable(startTime)
		or not readable(duration)
		or type(totemName) ~= "string"
		or totemName == ""
	then
		return nil
	end
	return normName(totemName), tonumber(startTime) or 0, tonumber(duration) or 0
end

-- A readable slot: learn the totem's slot and duration, keep our cast
-- record (with its position) when it is the same totem.
local function syncTotemSlot(slot, key, startTime, duration)
	totemSlotOf[key] = slot
	if duration > 0 then
		totemSecondsOf[key] = duration
	end
	local entry = totemOut[slot]
	if not (entry and entry.key == key and math.abs(entry.at - startTime) < 2) then
		totemOut[slot] = { key = key, at = startTime, seconds = duration }
	else
		entry.at, entry.seconds = startTime, duration
	end
end

function ns.API.NoteTotemCast(spellID)
	if spellID == nil or (issecretvalue and issecretvalue(spellID)) then
		return
	end
	local name = ns.API.SpellName(spellID)
	if type(name) ~= "string" or name == "" then
		return
	end
	local key = normName(name)
	local row = totemInfo(spellID, key)
	local slot = totemSlotOf[key] or (row and row.slot)
	if not slot then
		return
	end
	local x, y, map = playerSpot()
	totemOut[slot] = {
		key = key,
		at = GetTime(),
		seconds = totemSecondsOf[key] or (row and row.seconds) or 60,
		x = x,
		y = y,
		map = map,
	}
end

function ns.API.NoteTotemSlot(slot)
	slot = tonumber(slot)
	if not slot then
		return
	end
	local key, startTime, duration = readTotemSlot(slot)
	if key == false then
		totemOut[slot] = nil
	elseif key then
		syncTotemSlot(slot, key, startTime, duration)
	end
end

function ns.API.ClearTotems()
	wipe(totemOut)
end

-- The totem is gone or far away, but its effect may still be on you
-- (Stoneskin, Strength of Earth, ...): then it is not worth another totem.
local function effectRemain(wantName)
	for _, name in ipairs({ wantName:gsub("%s+[Tt]otem$", ""), wantName }) do
		local found, remain = ns.API.FindAuraByName(name, "player", "HELPFUL")
		if found then
			return remain
		end
	end
	return 0
end

---Seconds left on this totem; 0 when it is not down or you walked away.
---@param spellID integer
---@return number
function ns.API.TotemRemain(spellID)
	if not spellID or not GetTotemInfo then
		return 0
	end
	local wantName = ns.API.SpellName(ns.API.Resolve(spellID) or spellID) or ns.API.SpellName(spellID)
	if type(wantName) ~= "string" or wantName == "" then
		return 0
	end
	local wantKey = normName(wantName)
	local wantFamily = totemFamily(wantKey)
	local row = totemInfo(ns.API.Resolve(spellID) or spellID, wantKey)
	local wantedSlot = totemSlotOf[wantKey] or (row and row.slot)
	local now = GetTime()
	for slot = 1, 4 do
		local key, startTime, duration = readTotemSlot(slot)
		if key == false then
			totemOut[slot] = nil
		elseif key then
			syncTotemSlot(slot, key, startTime, duration)
		end
		local entry = totemOut[slot]
		if entry then
			local remain = entry.at + entry.seconds - now
			local alive = remain > 0 and not walkedAway(entry)
			if totemMatches(entry.key, wantKey, wantFamily) then
				return alive and remain or effectRemain(wantName)
			elseif slot == wantedSlot and alive then
				-- The slot holds another totem you dropped (Earthbind in the
				-- earth slot): do not replace it with this one while it lasts.
				return remain
			end
		end
	end
	return effectRemain(wantName)
end
