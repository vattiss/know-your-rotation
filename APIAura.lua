local addonName, ns = ...
local I = ns.API.I

-- Auras: reading, remembering, combo points and the look-ahead (predict).
local normName, readable, safe = I.normName, I.readable, I.safe

I.auraScans = {}

local heldHarmful = {}
local heldHarmfulGuid

function ns.API.WipeAuraScans()
	wipe(I.auraScans)
end

function ns.API.WipeAuraScan(unit)
	if not unit then
		wipe(I.auraScans)
		return
	end
	local prefix = unit .. "\0"
	for key in pairs(I.auraScans) do
		if strsub(key, 1, #prefix) == prefix then
			I.auraScans[key] = nil
		end
	end
end

local function auraRemain(aura)
	local exp = safe(aura.expirationTime, nil)
	if exp and exp > 0 then
		local remain = exp - GetTime()
		if remain < 0 then
			remain = 0
		end
		return remain
	end
	return 9999
end

local function auraStacks(aura)
	local n = safe(aura.applications, nil)
	if n == nil then
		n = safe(aura.stacks, nil)
	end
	if n == nil then
		n = safe(aura.count, nil)
	end
	if type(n) == "number" and n > 0 then
		return n
	end
	return 1
end

-- Exclusive buff families. An active seal (whatever its rank ID) counts for
-- all seals: the Forever client often hides the aura ID as soon as a target
-- is selected.
local AURA_FAMILIES = {
	{ key = "seal", tokens = { "seal" } },
	{ key = "blessing", tokens = { "blessing" } },
	{
		key = "palaura",
		tokens = { "devotion aura", "retribution aura", "concentration aura", "sanctity aura", "resistance aura" },
	},
	{ key = "aspect", tokens = { "aspect" } },
	{ key = "magearmor", tokens = { "ice armor", "frost armor", "mage armor" } },
	{ key = "lockarmor", tokens = { "demon skin", "demon armor" } },
}

local heldNames = {}
local heldFamilies = {}
local buffCastAt = {}

local FAMILY_SECONDS = {
	seal = 30,
	blessing = 300,
	palaura = 1800,
	aspect = 1800,
	magearmor = 1800,
	lockarmor = 1800,
}

-- Combo points. The client may hide them in combat (secret values), so a
-- count of builders and finishers since the last target change backs them up.
local comboEstimate = 0
local comboBuilders, comboFinishers

local function comboNameSets()
	if comboBuilders then
		return
	end
	comboBuilders, comboFinishers = {}, {}
	local R, D = ns.Spell.Rogue or {}, ns.Spell.Druid or {}
	local function add(set, id)
		local name = id and ns.API.SpellName(id)
		if name then
			set[name] = true
		end
	end
	-- By key, so a spell missing from ns.Spell does not cut the list short.
	for _, key in ipairs({
		"SinisterStrike",
		"Backstab",
		"Hemorrhage",
		"GhostlyStrike",
		"Ambush",
		"Garrote",
		"Gouge",
		"Mutilate",
	}) do
		add(comboBuilders, R[key])
	end
	for _, key in ipairs({ "Claw", "Shred", "Rake", "Ravage", "Pounce", "MangleCat" }) do
		add(comboBuilders, D[key])
	end
	for _, key in ipairs({ "Eviscerate", "SliceandDice", "Rupture", "KidneyShot", "ExposeArmor", "Venom" }) do
		add(comboFinishers, R[key])
	end
	for _, key in ipairs({ "FerociousBite", "Rip" }) do
		add(comboFinishers, D[key])
	end
	-- Names not loaded yet: try again next time.
	if not next(comboBuilders) then
		comboBuilders, comboFinishers = nil, nil
	end
end

function ns.API.NoteComboCast(spellID)
	local name = spellID and ns.API.SpellName(spellID)
	if not name then
		return
	end
	comboNameSets()
	if not comboBuilders then
		return
	end
	if comboFinishers[name] then
		comboEstimate = 0
	elseif comboBuilders[name] then
		comboEstimate = math.min(5, comboEstimate + 1)
	end
end

function ns.API.ResetComboEstimate()
	comboEstimate = 0
end

-- The highest of: player power 4 (modern), GetComboPoints on the target
-- (Classic), and the cast count. One source may read 0 on this client while
-- another has the real value, so none of them is trusted alone.
local lastComboSource = "count"

local function rawCombo()
	local best, source = comboEstimate, "count"
	local okP, power = pcall(UnitPower, "player", 4)
	if okP and readable(power) and type(power) == "number" and power > best then
		best, source = power, "power"
	end
	if GetComboPoints then
		local ok, points = pcall(GetComboPoints, "player", "target")
		if ok and readable(points) and type(points) == "number" and points > best then
			best, source = points, "target"
		end
	end
	lastComboSource = source
	return best
end

function ns.API.ComboDebug()
	local value = rawCombo()
	return value, lastComboSource
end

function ns.API.PredictBegin()
	I.predict = { debuffs = {}, buffs = {}, cd = {}, usedBuffs = {}, combo = rawCombo(), taken = 0 }
end

function ns.API.PredictEnd()
	I.predict = nil
end

local function predictMarkDebuff(spellID)
	if not spellID then
		return
	end
	I.predict.debuffs[spellID] = true
	local name = ns.API.SpellName(spellID)
	if type(name) == "string" and name ~= "" then
		I.predict.debuffs[normName(name)] = true
	end
end

local function predictMarkBuff(spellID)
	if not spellID then
		return
	end
	I.predict.buffs[spellID] = true
	local name = ns.API.SpellName(spellID)
	if type(name) == "string" and name ~= "" then
		I.predict.buffs[normName(name)] = true
	end
end

local function isComboBuilder(spellID)
	local builders = ns.COMBO_BUILDERS
	if not builders or not spellID then
		return false
	end
	if builders[spellID] then
		return true
	end
	local name = ns.API.SpellName(spellID)
	if type(name) ~= "string" or name == "" then
		return false
	end
	for id in pairs(builders) do
		if ns.API.SpellName(id) == name then
			return true
		end
	end
	return false
end

function ns.API.PredictConsume(spellID, opt)
	if not I.predict then
		return
	end
	spellID = ns.API.Resolve(spellID) or spellID
	opt = opt or {}
	I.predict.taken = (I.predict.taken or 0) + 1
	if opt.nodebuff then
		local debuff = opt.nodebuff == true and spellID or opt.nodebuff
		---@cast debuff integer
		predictMarkDebuff(debuff)
		predictMarkDebuff(spellID)
	end
	if type(opt.anydebuff) == "table" then
		for _, id in ipairs(opt.anydebuff) do
			predictMarkDebuff(id)
		end
	end
	if opt.needdebuff then
		predictMarkDebuff(opt.needdebuff)
	end
	if opt.nobuff then
		predictMarkBuff(spellID)
	end
	if type(opt.anybuff) == "table" then
		for _, id in ipairs(opt.anybuff) do
			predictMarkBuff(id)
		end
	end
	if opt.needbuff then
		I.predict.usedBuffs[opt.needbuff] = true
		local name = ns.API.SpellName(opt.needbuff)
		if type(name) == "string" and name ~= "" then
			I.predict.usedBuffs[normName(name)] = true
		end
	end
	if opt.comboMin then
		I.predict.combo = 0
	elseif isComboBuilder(spellID) then
		I.predict.combo = math.min(5, (I.predict.combo or 0) + 1)
	end
	if opt.filler == true or opt.swing == true then
		return
	end
	local seconds = ns.API.SpellCooldownSec(spellID)
	if not seconds or seconds <= 0.2 then
		return
	end
	local exp = GetTime() + seconds
	I.predict.cd[I.cdKey(spellID)] = exp
	I.predict.cd["id:" .. tostring(spellID)] = exp
	local group = I.groupOf(spellID)
	if not group then
		return
	end
	for _, id in ipairs(group.ids) do
		I.predict.cd[I.cdKey(id)] = exp
		I.predict.cd["id:" .. tostring(id)] = exp
	end
end

local function targetGuid()
	local ok, guid = pcall(UnitGUID, "target")
	if ok and readable(guid) and type(guid) == "string" then
		return guid
	end
	return nil
end

function ns.API.ClearTargetDebuffs()
	wipe(heldHarmful)
	heldHarmfulGuid = nil
	I.holdTargetSerial = I.holdTargetSerial + 1
	I.clearTargetBoundHolds()
end

-- remain: the duration seen on the target, if any. Otherwise the spell's
-- own duration (ns.SPELL_HOLD / step hold), else 18 s.
function ns.API.NoteTargetDebuff(spellID, remain)
	if spellID == nil or (issecretvalue and issecretvalue(spellID)) then
		return
	end
	local okExists, exists = pcall(UnitExists, "target")
	if not okExists or not exists then
		return
	end
	local guid = targetGuid()
	if heldHarmfulGuid and guid and heldHarmfulGuid ~= guid then
		wipe(heldHarmful)
	end
	heldHarmfulGuid = guid
	local name = ns.API.SpellName(spellID)
	local seconds = tonumber(remain)
	if not seconds or seconds <= 0 or seconds >= 9000 then
		seconds = ns.API.HoldSeconds(spellID)
		if not seconds or seconds <= 0 then
			seconds = 18
		end
	end
	local exp = GetTime() + seconds
	if type(name) == "string" and name ~= "" then
		heldHarmful[normName(name)] = exp
	end
	if type(spellID) == "number" then
		heldHarmful["id:" .. tostring(spellID)] = exp
		local resolved = ns.API.Resolve(spellID)
		if resolved and resolved ~= spellID then
			heldHarmful["id:" .. tostring(resolved)] = exp
		end
	end
end

local function heldHarmfulAura(spellID)
	local now = GetTime()
	if type(spellID) == "number" then
		local exp = heldHarmful["id:" .. tostring(spellID)]
		if exp and now < exp then
			return true
		end
	end
	local name = ns.API.SpellName(spellID)
	if type(name) ~= "string" or name == "" then
		return false
	end
	local exp = heldHarmful[normName(name)]
	return exp and now < exp or false
end

local function familyOf(name)
	if type(name) ~= "string" or name == "" then
		return nil
	end
	local n = normName(name)
	for _, family in ipairs(AURA_FAMILIES) do
		for _, token in ipairs(family.tokens) do
			if n:find(token, 1, true) then
				return family.key
			end
		end
	end
end

local function auraIdentity(aura)
	local auraID = safe(aura.spellId, nil)
	local auraName = safe(aura.name, nil)
	local hidden = (aura.spellId ~= nil and auraID == nil) or (aura.name ~= nil and auraName == nil)
	if not hidden and auraID == nil and auraName == nil then
		hidden = true
	end
	return auraID, auraName, hidden
end

-- HoldSeconds reads the current list, and for a druid the current list depends
-- on the form (ActiveSpec -> Form -> HasAura -> rememberAura): asking again
-- inside that chain would never end. The inner call takes the default.
local askingHold = false

local function rememberAura(spellID, auraName, remain, fromCast)
	local name = auraName or ns.API.SpellName(spellID)
	if type(name) ~= "string" or name == "" then
		return
	end
	local key = normName(name)
	local family = familyOf(name)
	local seconds = family and FAMILY_SECONDS[family]
	if not seconds then
		local hold
		if not askingHold then
			askingHold = true
			local ok, value = pcall(ns.API.HoldSeconds, spellID)
			askingHold = false
			hold = ok and value or nil
		end
		seconds = (hold and hold > 0) and hold or 30
	end
	local exp
	if remain and remain > 0 and remain < 9000 then
		exp = GetTime() + remain
	elseif fromCast or remain ~= nil or not heldNames[key] or heldNames[key] <= GetTime() then
		-- A sighting (remain is known, permanent auras give 9999) renews the
		-- memory: an aspect seen every few seconds never runs out in a long play.
		exp = GetTime() + seconds
	end
	if exp then
		heldNames[key] = exp
		if family then
			heldFamilies[family] = exp
		end
	end
	if fromCast then
		buffCastAt[key] = GetTime()
		if family then
			buffCastAt[family] = GetTime()
		end
	end
end

function ns.API.NoteSelfBuff(spellID)
	if spellID == nil or (issecretvalue and issecretvalue(spellID)) then
		return
	end
	-- Attacks are no buff; a heal cast on someone else is not on you.
	if ns.API.IsHarmful(spellID) and not ns.API.IsHelpful(spellID) then
		return
	end
	if ns.API.IsHealSpell(spellID) and ns.API.HealUnit() ~= "player" then
		return
	end
	rememberAura(spellID, nil, nil, true)
end

local function heldAura(spellID, wantName)
	local name = wantName or ns.API.SpellName(spellID)
	if type(name) ~= "string" or name == "" then
		return false
	end
	local now = GetTime()
	local exp = heldNames[normName(name)]
	if exp and now < exp then
		return true
	end
	local family = familyOf(name)
	exp = family and heldFamilies[family]
	return exp and now < exp or false
end

local function releaseAura(spellID, wantName, familiesSeen)
	local name = wantName or ns.API.SpellName(spellID)
	if type(name) ~= "string" or name == "" then
		return
	end
	local key = normName(name)
	local stamped = buffCastAt[key]
	if stamped and (GetTime() - stamped) < 1 then
		return
	end
	heldNames[key] = nil
	local family = familyOf(name)
	if family and not (familiesSeen and familiesSeen[family]) then
		local famStamp = buffCastAt[family]
		if not famStamp or (GetTime() - famStamp) >= 1 then
			heldFamilies[family] = nil
		end
	end
end

local function scanUnitAuras(unit, filter)
	local now = GetTime()
	local key = (unit or "") .. "\0" .. (filter or "")
	local hit = I.auraScans[key]
	if hit and (now - hit.t) < 0.2 then
		return hit
	end
	local scan = {
		t = now,
		unit = unit,
		filter = filter,
		names = {},
		ids = {},
		families = {},
		unreadable = false,
	}
	I.auraScans[key] = scan
	if not C_UnitAuras or not C_UnitAuras.GetAuraDataByIndex then
		scan.unreadable = true
		return scan
	end
	for i = 1, 40 do
		local ok, aura = pcall(C_UnitAuras.GetAuraDataByIndex, unit, i, filter)
		if not ok then
			scan.unreadable = true
			break
		end
		if not aura then
			if i == 1 and (next(heldNames) or next(heldFamilies)) then
				local busy = ns.API.InCombat and ns.API.InCombat()
				if not busy then
					local okE, exists = pcall(UnitExists, "target")
					busy = okE and exists and true or false
				end
				if busy then
					scan.unreadable = true
				end
			end
			break
		end
		local auraID, auraName, hidden = auraIdentity(aura)
		if hidden then
			scan.unreadable = true
		else
			if auraID then
				scan.ids[auraID] = aura
			end
			if auraName then
				scan.names[normName(auraName)] = aura
				local family = familyOf(auraName)
				if family then
					scan.families[family] = aura
				end
			end
		end
	end
	return scan
end

local function auraBySpellName(unit, name, filter)
	if type(name) ~= "string" or name == "" or not C_UnitAuras then
		return nil
	end
	if C_UnitAuras.GetAuraDataBySpellName then
		local ok, aura = pcall(C_UnitAuras.GetAuraDataBySpellName, unit, name, filter)
		if ok and type(aura) == "table" then
			return aura
		end
	end
	if AuraUtil and AuraUtil.FindAuraByName then
		local ok, auraName, _, _, _, _, _, _, _, auraID = pcall(AuraUtil.FindAuraByName, name, unit, filter)
		if ok and (auraName or auraID) then
			return { name = auraName, spellId = auraID }
		end
	end
end

-- An aura by its exact name (the totem effects: "Stoneskin" for Stoneskin
-- Totem). Returns found, seconds left (9999 when it has no end).
function ns.API.FindAuraByName(name, unit, filter)
	local aura = auraBySpellName(unit, name, filter)
	if aura then
		local _, _, hidden = auraIdentity(aura)
		if not hidden then
			return true, auraRemain(aura)
		end
	end
	return false, 0
end

---Aura present, including the remembered state when the client hides auras.
---@param spellID integer
---@param unit? string
---@param filter? string "HELPFUL" or "HARMFUL"
---@return boolean found
---@return number remain 9999 = unknown or permanent
function ns.API.HasAura(spellID, unit, filter)
	unit = unit or "player"
	filter = filter or "HELPFUL"
	if I.predict then
		local resolved = ns.API.Resolve(spellID) or spellID
		local name = ns.API.SpellName(resolved or spellID)
		local key = type(name) == "string" and name ~= "" and normName(name) or nil
		if filter == "HELPFUL" and unit == "player" then
			if
				(resolved and I.predict.usedBuffs[resolved])
				or (spellID and I.predict.usedBuffs[spellID])
				or (key and I.predict.usedBuffs[key])
			then
				return false, 0
			end
		end
		if filter == "HARMFUL" and (unit == "target" or unit == "") then
			if
				(resolved and I.predict.debuffs[resolved])
				or (spellID and I.predict.debuffs[spellID])
				or (key and I.predict.debuffs[key])
			then
				return true, 9999
			end
		end
		if filter == "HELPFUL" and unit == "player" then
			if
				(resolved and I.predict.buffs[resolved])
				or (spellID and I.predict.buffs[spellID])
				or (key and I.predict.buffs[key])
			then
				return true, 9999
			end
		end
	end
	local found, remain, unreadable, familiesSeen = ns.API.FindAura(spellID, unit, filter)
	local selfBuff = unit == "player" and filter == "HELPFUL"
	local targetHarm = unit == "target" and filter == "HARMFUL"
	if targetHarm then
		local guid = targetGuid()
		if heldHarmfulGuid and guid and heldHarmfulGuid ~= guid then
			wipe(heldHarmful)
			heldHarmfulGuid = guid
		end
	end
	if found then
		if selfBuff then
			rememberAura(spellID, nil, remain, false)
		end
		if targetHarm then
			ns.API.NoteTargetDebuff(spellID, remain)
		end
		return true, remain
	end
	if selfBuff and unreadable and heldAura(spellID) then
		return true, 9999
	end
	if targetHarm and unreadable and heldHarmfulAura(spellID) then
		return true, 9999
	end
	if selfBuff and not unreadable then
		-- In combat the client may simply return no auras. A long self-buff we
		-- saw or cast is trusted until it runs out; the "not found" only
		-- counts out of combat.
		if heldAura(spellID) and ns.API.InCombat() then
			return true, 9999
		end
		releaseAura(spellID, nil, familiesSeen)
	end
	return false, 0
end

local sharedNames

local function sharedDebuff(spellID, wantKey)
	local ids = ns.SHARED_DEBUFF_IDS
	if not ids then
		return false
	end
	if ids[spellID] then
		return true
	end
	if not sharedNames or not next(sharedNames) then
		sharedNames = {}
		for id in pairs(ids) do
			local name = ns.API.SpellName(id)
			if type(name) == "string" and name ~= "" then
				sharedNames[normName(name)] = true
			end
		end
	end
	return wantKey and sharedNames[wantKey] or false
end

---Raw aura read: found, remain, unreadable, families seen, stacks.
---@param spellID integer
---@param unit? string
---@param filter? string
---@return boolean found
---@return number remain
---@return boolean unreadable
---@return table? families
---@return integer stacks
function ns.API.FindAura(spellID, unit, filter)
	if not spellID then
		return false, 0, false, nil, 0
	end
	unit = unit or "player"
	filter = filter or "HELPFUL"
	local resolved = ns.API.Resolve(spellID)
	local wantName = ns.API.SpellName(resolved or spellID) or ns.API.SpellName(spellID)
	local wantKey = type(wantName) == "string" and normName(wantName) or nil
	local wantFamily = familyOf(wantName)
	if filter == "HARMFUL" and unit == "target" and not sharedDebuff(spellID, wantKey) and ns.API.Hostile() then
		filter = "HARMFUL|PLAYER"
	end

	if C_UnitAuras and C_UnitAuras.GetPlayerAuraBySpellID and unit == "player" then
		for _, id in ipairs({ resolved, spellID }) do
			if id then
				local ok, aura = pcall(C_UnitAuras.GetPlayerAuraBySpellID, id)
				if ok and type(aura) == "table" then
					return true, auraRemain(aura), false, nil, auraStacks(aura)
				end
			end
		end
	end

	if wantName then
		local named = auraBySpellName(unit, wantName, filter)
		if named then
			local _, _, hidden = auraIdentity(named)
			if not hidden then
				return true, auraRemain(named), false, nil, auraStacks(named)
			end
		end
	end

	local scan = scanUnitAuras(unit, filter)
	if wantKey and scan.names[wantKey] then
		local aura = scan.names[wantKey]
		return true, auraRemain(aura), false, scan.families, auraStacks(aura)
	end
	if resolved and scan.ids[resolved] then
		local aura = scan.ids[resolved]
		return true, auraRemain(aura), false, scan.families, auraStacks(aura)
	end
	if spellID and scan.ids[spellID] then
		local aura = scan.ids[spellID]
		return true, auraRemain(aura), false, scan.families, auraStacks(aura)
	end
	if wantFamily and scan.families[wantFamily] then
		local aura = scan.families[wantFamily]
		return true, auraRemain(aura), false, scan.families, auraStacks(aura)
	end
	return false, 0, scan.unreadable, scan.families, 0
end

function ns.API.HasWeaponBuff(entry)
	if not entry then
		return false, 0
	end
	local ids = { entry.id }
	if entry.ranks then
		for _, id in ipairs(entry.ranks) do
			ids[#ids + 1] = id
		end
	end
	for _, id in ipairs(ids) do
		local found, remain = ns.API.FindAura(id, "player", "HELPFUL")
		if found then
			return true, remain
		end
	end
	return false, 0
end

function ns.API.Form(spellID)
	return ns.API.HasAura(spellID, "player", "HELPFUL")
end

function ns.API.Combo()
	if I.predict and I.predict.combo ~= nil then
		return I.predict.combo
	end
	return rawCombo()
end
