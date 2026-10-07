local addonName, ns = ...
local I = ns.API.I

-- Cooldown tracking and holds after a cast.
local readable, safe = I.readable, I.safe

local cdUntil = {}
local cdKnown = {}
local holdUntil = {}

function I.cdKey(spellID)
	local name = ns.API.SpellName(spellID)
	if type(name) == "string" and name ~= "" then
		local n = strlower(name)
		n = n:gsub("%s*%([^%)]*%)", "")
		if strtrim then
			n = strtrim(n)
		end
		if n ~= "" then
			return n
		end
	end
	return "id:" .. tostring(spellID)
end

local function parseBaseCooldown(cd, gcd)
	cd = tonumber(safe(cd, nil))
	gcd = tonumber(safe(gcd, nil))
	if not cd or cd <= 0 then
		return 0
	end
	if cd < 500 then
		local gcdSec = gcd and gcd < 500 and gcd or 1.5
		if cd <= gcdSec + 0.05 or cd <= 1.5 then
			return 0
		end
		return cd
	end
	local gcdMs = gcd or 1500
	if cd <= gcdMs + 50 then
		return 0
	end
	return cd / 1000
end

local function baseCooldownSec(spellID)
	if GetSpellBaseCooldown then
		local ok, cd, gcd = pcall(GetSpellBaseCooldown, spellID)
		if ok then
			local sec = parseBaseCooldown(cd, gcd)
			if sec > 0 then
				return sec
			end
		end
	end
	if C_Spell and C_Spell.GetSpellBaseCooldown then
		local ok, cd, gcd = pcall(C_Spell.GetSpellBaseCooldown, spellID)
		if ok then
			local sec
			if type(cd) == "table" then
				sec = parseBaseCooldown(cd.duration or cd.cooldown, cd.gcd)
			else
				sec = parseBaseCooldown(cd, gcd)
			end
			if sec > 0 then
				return sec
			end
		end
	end
	return 0
end

function I.groupOf(spellID)
	local groups = ns.COOLDOWN_GROUPS
	if not groups then
		return nil
	end
	local castName = ns.API.SpellName(spellID)
	for _, group in ipairs(groups) do
		for _, id in ipairs(group.ids) do
			if id == spellID or (castName and ns.API.SpellName(id) == castName) then
				return group
			end
		end
	end
end

local function fallbackSeconds(spellID)
	local map = ns.COOLDOWNS
	if map and map[spellID] then
		return map[spellID]
	end
	local group = I.groupOf(spellID)
	if group and group.seconds then
		return group.seconds
	end
	local name = ns.API.SpellName(spellID)
	if map and name then
		for id, seconds in pairs(map) do
			if ns.API.SpellName(id) == name then
				return seconds
			end
		end
	end
	return 0
end

function ns.API.SpellCooldownSec(spellID)
	spellID = ns.API.Resolve(spellID) or spellID
	if not spellID then
		return 0
	end
	local sec = baseCooldownSec(spellID)
	if sec and sec > 0.2 then
		return sec
	end
	return fallbackSeconds(spellID) or 0
end

function ns.API.IsFallback(opt)
	opt = opt or {}
	return opt.filler == true or opt.swing == true
end

-- A filler listed first must yield to these when they are pressable.
-- Nukes without a cooldown (Starfire, Ice Lance, Swipe) stay list-order.
-- Auto-appended racials never steal a filler higher in the list.
function ns.API.IsRotationAction(spellID, opt, isRacial)
	if isRacial then
		return false
	end
	opt = opt or {}
	if ns.API.IsFallback(opt) or opt.autoRepeat then
		return false
	end
	if opt.heal or opt.nodebuff or opt.nobuff or opt.needbuff or opt.needdebuff then
		return true
	end
	if opt.proc or opt.usable or opt.comboMin then
		return true
	end
	if opt.nopet or opt.pet or opt.nocombat then
		return true
	end
	if opt.hp or opt.manaMax or opt.hpMin then
		return true
	end
	if opt.anybuff or opt.anydebuff then
		return true
	end
	local sec = ns.API.SpellCooldownSec(spellID)
	return sec and sec > 0.2
end

local function markCooldown(spellID, seconds)
	if not seconds or seconds <= 0.2 then
		return
	end
	local exp = GetTime() + seconds
	cdUntil[I.cdKey(spellID)] = exp
	cdUntil["id:" .. tostring(spellID)] = exp
	local group = I.groupOf(spellID)
	if not group then
		return
	end
	local groupExp = GetTime() + math.max(seconds, group.seconds or 0)
	for _, id in ipairs(group.ids) do
		cdUntil[I.cdKey(id)] = groupExp
		cdUntil["id:" .. tostring(id)] = groupExp
	end
end

function ns.API.NoteSpellCast(spellID)
	ns.API.lastCastAt = GetTime()
	if spellID == nil or (issecretvalue and issecretvalue(spellID)) then
		return
	end
	ns.API.NoteComboCast(spellID)
	local key = I.cdKey(spellID)
	local seconds = baseCooldownSec(spellID)
	if seconds <= 0 and cdKnown[key] and cdKnown[key] > 1.5 then
		seconds = cdKnown[key]
	end
	if seconds <= 0 then
		seconds = fallbackSeconds(spellID)
	end
	markCooldown(spellID, seconds)
	local hold = ns.API.HoldSeconds(spellID)
	if hold and hold > 0 then
		ns.API.NoteSpellHold(spellID, hold)
	end
end

-- Re-suggest delay after cast (DoT / HoT / snare). Independent from real CD.
function ns.API.HoldSeconds(spellID)
	local resolved = ns.API.Resolve(spellID) or spellID
	if not resolved then
		return 0
	end
	local function fromStep(step)
		if not step or not step.id then
			return nil
		end
		local sid = ns.API.Resolve(step.id) or step.id
		if sid ~= resolved and step.id ~= spellID and step.id ~= resolved then
			return nil
		end
		if step.opt and step.opt.hold ~= nil then
			return tonumber(step.opt.hold) or 0
		end
		return nil
	end
	if ns.GetAPL then
		local apl = ns.GetAPL()
		for i = 1, #(apl or {}) do
			local hit = fromStep(apl[i])
			if hit ~= nil then
				return math.max(0, hit)
			end
		end
	end
	if ns.GetDef then
		local def = ns.GetDef()
		for i = 1, #(def or {}) do
			local hit = fromStep(def[i])
			if hit ~= nil then
				return math.max(0, hit)
			end
		end
	end
	if ns.SPELL_HOLD then
		local h = ns.SPELL_HOLD[resolved] or ns.SPELL_HOLD[spellID]
		if type(h) == "number" then
			return math.max(0, h)
		end
	end
	return 0
end

-- Target DoT / snare / mark holds bind to the mob GUID so a new target
-- (or a dead one) can be marked again. Self HoTs / Slice and Dice stay global.
-- Bumped on every target change (ClearTargetDebuffs).
I.holdTargetSerial = 0

local function holdTargetGuid()
	local okE, exists = pcall(UnitExists, "target")
	if not okE or not exists then
		return nil
	end
	local ok, guid = pcall(UnitGUID, "target")
	if ok and readable(guid) and type(guid) == "string" then
		return guid
	end
	-- An NPC's GUID is secret (SecretWhenUnitIdentityRestricted): bind the
	-- hold to the current target instead; a target change clears it.
	return "target#" .. I.holdTargetSerial
end

local function holdBindsToTarget(spellID)
	return ns.API.IsHarmful(spellID) == true
end

local function unitIsDead(unit)
	if UnitIsDeadOrGhost then
		local ok, dead = pcall(UnitIsDeadOrGhost, unit)
		if ok and dead == true then
			return true
		end
		if ok and dead == false then
			return false
		end
	end
	if UnitIsDead then
		local ok, dead = pcall(UnitIsDead, unit)
		if ok and dead == true then
			return true
		end
	end
	return false
end

local function writeHold(spellID, exp, guid)
	local entry = { exp = exp, guid = guid }
	holdUntil[I.cdKey(spellID)] = entry
	holdUntil["id:" .. tostring(spellID)] = entry
	local resolved = ns.API.Resolve(spellID)
	if resolved and resolved ~= spellID then
		holdUntil[I.cdKey(resolved)] = entry
		holdUntil["id:" .. tostring(resolved)] = entry
	end
end

function I.clearHoldKeys(spellID)
	holdUntil[I.cdKey(spellID)] = nil
	holdUntil["id:" .. tostring(spellID)] = nil
	local resolved = ns.API.Resolve(spellID)
	if resolved and resolved ~= spellID then
		holdUntil[I.cdKey(resolved)] = nil
		holdUntil["id:" .. tostring(resolved)] = nil
	end
end

function I.clearTargetBoundHolds()
	for key, entry in pairs(holdUntil) do
		if entry.guid ~= "self" then
			holdUntil[key] = nil
		end
	end
end

function ns.API.NoteSpellHold(spellID, seconds)
	seconds = tonumber(seconds)
	if not spellID or not seconds or seconds <= 0 then
		return
	end
	local exp = GetTime() + seconds
	---@type string|false
	local guid = "self"
	if holdBindsToTarget(spellID) then
		guid = holdTargetGuid() or false
	end
	writeHold(spellID, exp, guid)
end

---Seconds left on the spell's hold after its last cast.
---@param spellID integer
---@return number
function ns.API.HoldRemain(spellID)
	if not spellID then
		return 0
	end
	local entry = holdUntil[I.cdKey(spellID)] or holdUntil["id:" .. tostring(spellID)]
	if not entry then
		local resolved = ns.API.Resolve(spellID)
		if resolved then
			entry = holdUntil[I.cdKey(resolved)] or holdUntil["id:" .. tostring(resolved)]
		end
	end
	if not entry then
		return 0
	end
	-- Entries come from writeHold only: { exp = time, guid = "self" | target | false }.
	local guid = entry.guid
	if guid ~= "self" then
		-- Bound to a mob: no target when cast, new target, or a dead one -> re-suggest.
		local cur = holdTargetGuid()
		if not guid or not cur or cur ~= guid or unitIsDead("target") then
			I.clearHoldKeys(spellID)
			return 0
		end
	end
	local remain = entry.exp - GetTime()
	if remain <= 0 then
		I.clearHoldKeys(spellID)
		return 0
	end
	return remain
end

local function trackedRemain(spellID)
	local exp = cdUntil[I.cdKey(spellID)] or cdUntil["id:" .. tostring(spellID)]
	if not exp then
		return 0
	end
	local remain = exp - GetTime()
	if remain <= 0 then
		cdUntil[I.cdKey(spellID)] = nil
		cdUntil["id:" .. tostring(spellID)] = nil
		return 0
	end
	return remain
end

local function readSpellCooldown(spellID)
	if not spellID or not C_Spell or not C_Spell.GetSpellCooldown then
		return 0, 0, true
	end
	local ok, info = pcall(C_Spell.GetSpellCooldown, spellID)
	if not ok or type(info) ~= "table" then
		return 0, 0, true
	end
	local start = info.startTime or info.start
	local duration = info.duration
	if (start ~= nil and not readable(start)) or (duration ~= nil and not readable(duration)) then
		return 0, 0, true
	end
	start = tonumber(start) or 0
	duration = tonumber(duration) or 0
	local remain = duration - (GetTime() - start)
	if remain < 0 then
		remain = 0
	end
	if duration > 0 and duration <= 1.51 then
		return 0, duration, false
	end
	return remain, duration, false
end

---Seconds left on the spell's own cooldown (GCD ignored), and its length.
---@param spellID integer
---@return number remain
---@return number duration
function ns.API.Cooldown(spellID)
	spellID = ns.API.Resolve(spellID) or spellID
	if not spellID then
		return 0, 0
	end
	local apiRemain, apiDuration, secret = readSpellCooldown(spellID)
	local key = I.cdKey(spellID)
	if not secret and apiDuration and apiDuration > 1.51 then
		cdKnown[key] = apiDuration
	end
	local tracked = trackedRemain(spellID)
	if I.predict then
		local pred = I.predict.cd[I.cdKey(spellID)] or I.predict.cd["id:" .. tostring(spellID)]
		if pred then
			local predRemain = pred - GetTime()
			if predRemain > tracked then
				tracked = predRemain
			end
		end
	end
	if tracked > 0.2 then
		-- A readable real cooldown wins over the estimate from the base
		-- cooldown: talents can shorten it (Reverberation, Improved Fire Blast).
		if not secret and apiDuration and apiDuration > 1.51 then
			return apiRemain, apiDuration
		end
		return tracked, apiDuration > 0 and apiDuration or tracked
	end
	if secret then
		return 0, 0
	end
	return apiRemain, apiDuration
end
