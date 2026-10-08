local addonName, ns = ...
local API = ns.API

local maintNames
local weaponNames
local tokenCache = {}
-- Spells already cast in the current rotation pass. Skipped until the list
-- has been walked through; then wiped so the queue restarts from the top.
local rotSpent = {}

function ns.ClearRotationSpent()
	wipe(rotSpent)
end

local function sameRotSpell(a, b)
	if not a then
		return false
	end
	return a == b or (API.Resolve(a) or a) == b
end

-- Mark an APL spell as used for this pass (cast from the bar or suggested).
-- Next suggestions start after it; when nothing left is usable, we wrap to 1.
function ns.NoteRotationCast(spellID)
	if not spellID or not ns.GetAPL then
		return
	end
	local resolved = API.Resolve(spellID) or spellID
	for _, step in ipairs(ns.GetAPL() or {}) do
		if step.key and sameRotSpell(step.id, resolved) then
			rotSpent[step.key] = true
			rotSpent["id:" .. tostring(resolved)] = true
			return
		end
	end
end

local function isRotSpent(step)
	if step.key and rotSpent[step.key] then
		return true
	end
	local id = API.Resolve(step.id) or step.id
	return id ~= nil and rotSpent["id:" .. tostring(id)] == true
end

function ns.InvalidateBuffCaches()
	maintNames = nil
	weaponNames = nil
	tokenCache = {}
	if ns.API and ns.API.WipeAuraScans then
		ns.API.WipeAuraScans()
	end
end

local function maintNameSet()
	if maintNames and next(maintNames) then
		return maintNames
	end
	maintNames = {}
	for id in pairs(ns.MAINTENANCE_BUFF_IDS or {}) do
		local name = API.SpellName(id)
		if name then
			maintNames[name] = true
		end
	end
	return maintNames
end

local function weaponNameSet()
	if weaponNames and next(weaponNames) then
		return weaponNames
	end
	weaponNames = {}
	for _, list in pairs(ns.WEAPON_BUFFS or {}) do
		for _, entry in ipairs(list) do
			local name = API.SpellName(entry.id)
			if name then
				weaponNames[name] = true
			end
		end
	end
	return weaponNames
end

local function stepReady(id, opt)
	if opt and opt.role and (ns.db.role or "damage") ~= opt.role then
		return false
	end
	return API.StepOk(id, opt)
end

function ns.IsMaintenanceBuff(spellID)
	if not spellID then
		return false
	end
	if ns.MAINTENANCE_BUFF_IDS and ns.MAINTENANCE_BUFF_IDS[spellID] then
		return true
	end
	local name = API.SpellName(spellID)
	return name and maintNameSet()[name] or false
end

-- Totems are a cue of their own (BuildTotem), never a step of the rotation.
function ns.IsTotemCue(spellID)
	return spellID ~= nil and not (issecretvalue and issecretvalue(spellID)) and API.TotemWhen(spellID) ~= nil
end

function ns.IsWeaponBuff(spellID)
	if not spellID or (issecretvalue and issecretvalue(spellID)) then
		return false
	end
	if ns.WEAPON_BUFF_IDS and ns.WEAPON_BUFF_IDS[spellID] then
		return true
	end
	local name = API.SpellName(spellID)
	return name and weaponNameSet()[name] or false
end

function ns.BuildQueue()
	local q = {}
	ns.queueHeal = {}
	if not ns.GetAPL then
		return q
	end
	local apl = ns.GetAPL()
	-- Spell IDs already in the queue or being cast: a spell shows at most once,
	-- so the queue walks the list (1 → 2 → 3) instead of repeating a cast.
	local used = {}
	local stepById = {}
	local function markHeal(id, opt)
		if not API.IsHealSpell(id, opt) then
			return
		end
		ns.queueHeal[id] = true
		local resolved = API.Resolve(id)
		if resolved then
			ns.queueHeal[resolved] = true
		end
	end
	-- Only called after pressable(), which already refuses a used ID.
	local function take(step)
		local id = API.Resolve(step.id) or step.id
		q[#q + 1] = id
		stepById[id] = step
		used[id] = true
		markHeal(id, step.opt)
		API.PredictConsume(step.id, step.opt)
		return true
	end
	local function consider(step)
		return ns.IsStepEnabled(step)
			and step.id
			and not ns.IsWeaponBuff(step.id)
			and not ns.IsMaintenanceBuff(step.id)
			and not ns.IsTotemCue(step.id)
	end
	API.PredictBegin()
	-- mode: "in" = confirmed reach (slot 1), "notOut" = unknown reach is
	-- fine, "any" = out of range is fine too (slots 2-3).
	local function pressable(step, shift, mode)
		if not consider(step) or not API.StepOk(step.id, step.opt, shift) then
			return false
		end
		local id = API.Resolve(step.id) or step.id
		return not used[id] and API.InSpellRange(id, step.opt, mode)
	end
	-- A ready action (shock, DoT, cooldown, proc) listed after position "from".
	local function laterAction(from, shift)
		for j = from + 1, #apl do
			local step = apl[j]
			if
				not isRotSpent(step)
				and API.IsRotationAction(step.id, step.opt, step.racial)
				and (pressable(step, shift, "in") or pressable(step, shift, "notOut"))
			then
				return true
			end
		end
		return false
	end
	-- First unspent step that can be taken. Fillers (Lightning Bolt,
	-- Fireball, Heroic Strike, …) yield to a later ready action so that spell
	-- becomes slot 1; Ice Lance / Starfire stay in list order (not actions).
	local function pickOne(shift, mode)
		for i, step in ipairs(apl) do
			if not isRotSpent(step) and pressable(step, shift, mode) then
				if not (API.IsFallback(step.opt) and laterAction(i, shift)) then
					take(step)
					return true
				end
			end
		end
		return false
	end
	-- Continue after a manual cast; when the pass is used up, restart from
	-- the top of the list.
	local function pickNext(shift, mode)
		if pickOne(shift, mode) then
			return true
		end
		if next(rotSpent) then
			wipe(rotSpent)
			return pickOne(shift, mode)
		end
		return false
	end
	local function fillSlots()
		local shift = math.max(0.2, API.CastRemain())
		-- The spell being cast right now is not glowed again: it only counts as
		-- used for the look-ahead, so the glow already shows what comes next.
		for _, step in ipairs(apl) do
			if consider(step) and API.CastingSpell(step.id) then
				if not (step.opt and step.opt.swing) then
					used[API.Resolve(step.id) or step.id] = true
				end
				API.PredictConsume(step.id, step.opt)
				break
			end
		end
		if not pickNext(shift, "in") then
			pickNext(shift, "notOut")
		end
		while #q < 3 do
			if not pickNext(shift, "any") then
				return
			end
		end
	end
	pcall(fillSlots)
	API.PredictEnd()
	-- Only slot 1 glows: a needed heal moves there even when it already sits
	-- in slot 2 or 3.
	if not (q[1] and ns.queueHeal[q[1]]) then
		for _, step in ipairs(apl) do
			if
				consider(step)
				and API.IsHealSpell(step.id, step.opt)
				and not API.CastingSpell(step.id)
				and API.StepOk(step.id, step.opt, 0.2)
			then
				local id = API.Resolve(step.id) or step.id
				for i = #q, 1, -1 do
					if q[i] == id then
						table.remove(q, i)
					end
				end
				table.insert(q, 1, id)
				stepById[id] = step
				q[4] = nil
				markHeal(id, step.opt)
				break
			end
		end
	end
	-- Whether the spell that will be flashed (slot 1) can be pressed right now.
	local function pressableNow(id)
		local step = id and stepById[id]
		return step ~= nil and API.Ready(id, step.opt) and API.RangeState(id, step.opt) ~= "out"
	end
	local okGlow, glowOk = pcall(pressableNow, q[1])
	ns.queueGlowOk = okGlow and glowOk == true
	return q
end

-- Hidden values (health or mana in combat): pick the step the player would
-- press, so Glow.lua can show it with an alpha the client drives from the
-- hidden value (a curve through UnitHealthPercent / UnitPowerPercent): lit
-- only past the step's threshold, with no number ever compared by us.
--
-- spec.wants(opt)         does this step wait for the hidden value?
-- spec.gate               opt flag that switches the step's own value check off
-- spec.clear              opt key dropped from the copy (optional)
-- spec.skipCasting        skip the spell being cast right now (optional)
-- spec.skipBuffs          skip weapon and maintenance buffs (optional)
-- spec.threshold(opt, id) percent where the glow turns on; nil skips the step
local function hiddenPick(steps, spec)
	for _, step in ipairs(steps or {}) do
		local opt = step.opt or {}
		if
			spec.wants(opt)
			and step.id
			and ns.IsStepEnabled(step)
			and not (spec.skipCasting and API.CastingSpell(step.id))
			and not (spec.skipBuffs and (ns.IsWeaponBuff(step.id) or ns.IsMaintenanceBuff(step.id)))
		then
			local copy = {}
			for k, v in pairs(opt) do
				copy[k] = v
			end
			copy[spec.gate] = true
			if spec.clear then
				copy[spec.clear] = nil
			end
			if API.StepOk(step.id, copy, 0.2) then
				local threshold = spec.threshold(opt, step.id)
				if threshold then
					return API.Resolve(step.id) or step.id, threshold
				end
			end
		end
	end
	return nil
end

-- Heal (or a step on your own health, like Drain Life) while your health is hidden.
function ns.BuildHiddenHeal()
	if not ns.GetAPL or not API.HealthHidden() then
		return nil
	end
	return hiddenPick(ns.GetAPL(), {
		wants = function(opt)
			return opt.heal or (opt.hp and not opt.unit)
		end,
		gate = "noHpGate",
		skipCasting = true,
		skipBuffs = true,
		threshold = function(opt, id)
			local threshold = tonumber(opt.hp) or 80
			return opt.heal and API.AutoHealThreshold(id, "player", threshold) or threshold
		end,
	})
end

-- A step waiting for a low target ("hp" with unit "target", or "hpPerCombo")
-- while the target's health is hidden. Returns the spell and the percent.
function ns.BuildHiddenExecute()
	if not ns.GetAPL or not API.Hostile() or not API.HealthHiddenFor("target") then
		return nil
	end
	return hiddenPick(ns.GetAPL(), {
		wants = function(opt)
			return opt.unit == "target" and (opt.hp or opt.hpPerCombo)
		end,
		gate = "noHpGate",
		clear = "hpPerCombo",
		threshold = function(opt)
			local threshold = opt.hpPerCombo and (API.Combo() * opt.hpPerCombo) or tonumber(opt.hp) or 20
			return threshold > 0 and threshold or nil
		end,
	})
end

-- Pet heal (Mend Pet) while the pet's health is hidden.
function ns.BuildHiddenPet()
	if not ns.GetAPL or not UnitExists("pet") or not API.HealthHiddenFor("pet") then
		return nil
	end
	return hiddenPick(ns.GetAPL(), {
		wants = function(opt)
			return opt.unit == "pet" and opt.hp
		end,
		gate = "noHpGate",
		skipCasting = true,
		threshold = function(opt)
			return tonumber(opt.hp) or 40
		end,
	})
end

-- Mana step (Life Tap) while your mana is hidden.
function ns.BuildHiddenMana()
	if not ns.GetAPL or not API.ManaHidden() then
		return nil
	end
	return hiddenPick(ns.GetAPL(), {
		wants = function(opt)
			return opt.manaMax
		end,
		gate = "noManaGate",
		threshold = function(opt)
			return tonumber(opt.manaMax)
		end,
	})
end

-- Defensive step on your own health while it is hidden.
function ns.BuildHiddenDefense()
	if not ns.GetDef or not API.HealthHidden() then
		return nil
	end
	return hiddenPick(ns.GetDef(), {
		wants = function(opt)
			return opt.hp and (not opt.unit or opt.unit == "player")
		end,
		gate = "noHpGate",
		threshold = function(opt, id)
			local threshold = tonumber(opt.hp) or 50
			return opt.heal and API.AutoHealThreshold(id, "player", threshold) or threshold
		end,
	})
end

function ns.BuildDefense()
	if not ns.GetDef then
		return
	end
	-- Health-based defensives first (Shield Wall at 20% beats a lapsed Battle
	-- Shout), then buffs and the rest, each in list order.
	for pass = 1, 2 do
		for _, step in ipairs(ns.GetDef()) do
			local urgent = step.opt and step.opt.hp and true or false
			if urgent == (pass == 1) and ns.IsStepEnabled(step) and stepReady(step.id, step.opt) then
				return (API.Resolve and API.Resolve(step.id)) or step.id
			end
		end
	end
end

function ns.BuildInterrupt()
	local token = ns.ClassToken and ns.ClassToken()
	local id = token and ns.INTERRUPTS[token]
	if not id or not API.Ready(id) then
		return
	end
	if not API.Hostile() or not API.TargetCasting() then
		return
	end
	if API.RangeState and API.RangeState(id, { hostile = true }) == "out" then
		return
	end
	return id
end

-- What a totem needs before it is worth dropping, by its `when`.
local TOTEM_OPT = {
	pull = { totem = true, engaged = true },
	hostile = { totem = true, hostile = true },
	melee = { totem = true, inMelee = true },
}

-- The first totem of the player's totem bar that is missing and worth dropping
-- now. A cue next to the rotation: it never takes a slot of the queue.
function ns.BuildTotem()
	for _, totem in ipairs(API.TotemBar()) do
		if API.StepOk(totem.id, TOTEM_OPT[totem.when]) then
			return totem.id
		end
	end
end

function ns.BuildPurge()
	local token = ns.ClassToken and ns.ClassToken()
	local id = token and ns.PURGES[token]
	if not id or not API.Ready(id) then
		return
	end
	if not API.Hostile() then
		return
	end
	if not API.Purgable(token == "MAGE") then
		return
	end
	if API.RangeState and API.RangeState(id, { hostile = true }) == "out" then
		return
	end
	return id
end

function ns.BuildCleanse()
	local token = ns.ClassToken and ns.ClassToken()
	local list = token and ns.CLEANSE[token]
	if not list then
		return
	end
	local units = { "player" }
	if ns.db.cleanseGroup ~= false then
		for _, unit in ipairs({ "mouseover", "target", "focus", "party1", "party2", "party3", "party4" }) do
			units[#units + 1] = unit
		end
	end
	for _, entry in ipairs(list) do
		if API.Known(entry.id) and API.Ready(entry.id) then
			for _, unit in ipairs(units) do
				if API.HasDebuffType(entry.types, unit) then
					return entry.id
				end
			end
		end
	end
end

function ns.WeaponChoices()
	local token = ns.ClassToken and ns.ClassToken()
	return token and ns.WEAPON_BUFFS[token] or {}
end

-- Highest rank of this weapon buff the character has learned, or nil.
local function learnedWeaponID(entry)
	if not entry then
		return nil
	end
	if entry.ranks then
		for i = #entry.ranks, 1, -1 do
			if API.Known(entry.ranks[i]) then
				return entry.ranks[i]
			end
		end
	end
	if API.Known(entry.id) then
		return entry.id
	end
	return nil
end

function ns.WeaponBuffLearned(entry)
	return learnedWeaponID(entry) ~= nil
end

-- Automatic pick: the best weapon buff already learned, by role where it
-- matters (melee shaman: Windfury first; caster / healer: Flametongue first).
-- At low level this is simply the only one known, e.g. Rockbiter.
local WEAPON_PRIORITY = {
	SHAMAN = {
		melee = { "Windfury", "Flametongue", "Rockbiter", "Frostbrand" },
		default = { "Flametongue", "Rockbiter", "Frostbrand", "Windfury" },
	},
	ROGUE = {
		default = { "InstantPoison", "DeadlyPoison", "WoundPoison", "CripplingPoison", "MindNumbingPoison" },
	},
}

-- Classes that coat both weapons, and what goes on the off-hand by default.
local WEAPON_DUAL = { ROGUE = true }
local OFFHAND_PRIORITY = {
	ROGUE = { "DeadlyPoison", "InstantPoison", "CripplingPoison", "WoundPoison", "MindNumbingPoison" },
}

-- True when the class coats both weapons and an off-hand weapon is equipped.
function ns.WeaponIsDual()
	local token = ns.ClassToken and ns.ClassToken()
	if not token or not WEAPON_DUAL[token] or not GetInventoryItemID then
		return false
	end
	local ok, itemID = pcall(GetInventoryItemID, "player", 17)
	if not ok or type(itemID) ~= "number" then
		return false
	end
	local info = C_Item and C_Item.GetItemInfoInstant
	if not info then
		return true
	end
	local okInfo, _, _, _, _, _, classID = pcall(info, itemID)
	return okInfo and classID == 2
end

function ns.WeaponHasOffhandChoice()
	local token = ns.ClassToken and ns.ClassToken()
	return token and WEAPON_DUAL[token] == true or false
end

function ns.AutoWeaponBuff(offhand)
	local choices = ns.WeaponChoices()
	local token = ns.ClassToken and ns.ClassToken()
	local order
	if offhand then
		order = token and OFFHAND_PRIORITY[token]
	else
		local pack = token and WEAPON_PRIORITY[token]
		order = pack and (pack[ns.db.role] or pack.default)
	end
	if order then
		local byKey = {}
		for _, entry in ipairs(choices) do
			byKey[entry.key] = entry
		end
		for _, key in ipairs(order) do
			local id = learnedWeaponID(byKey[key])
			if id then
				return byKey[key], id
			end
		end
	end
	for _, entry in ipairs(choices) do
		local id = learnedWeaponID(entry)
		if id then
			return entry, id
		end
	end
	return nil
end

-- The player's pick if it is learned, otherwise the automatic one. Returns
-- nothing while no weapon buff is learned yet, so nothing is suggested.
function ns.SelectedWeaponBuff(offhand)
	local choices = ns.WeaponChoices()
	if #choices == 0 then
		return
	end
	local key = offhand and ns.db.weaponBuffOff or ns.db.weaponBuff
	if key and key ~= "auto" then
		for _, entry in ipairs(choices) do
			if entry.key == key then
				local id = learnedWeaponID(entry)
				if id then
					return entry, id
				end
				break
			end
		end
	end
	return ns.AutoWeaponBuff(offhand)
end

local function rememberWeaponApply(entry)
	local now = GetTime()
	ns.weaponGrace = now + 3
	ns.weaponCastAt = now
	ns.weaponSeenUntil = now + (entry.duration or 3600)
	ns.weaponRecheckDrop = nil
end

local function entryMatchesName(entry, name)
	if not entry or type(name) ~= "string" or name == "" then
		return false
	end
	local lower = strlower(name)
	if entry.match then
		for _, token in ipairs(entry.match) do
			if type(token) == "string" and token ~= "" and lower:find(token, 1, true) then
				return true
			end
		end
	end
	local ids = { entry.id }
	if entry.ranks then
		for _, id in ipairs(entry.ranks) do
			ids[#ids + 1] = id
		end
	end
	for _, id in ipairs(ids) do
		local spellName = API.SpellName(id)
		if type(spellName) == "string" and strlower(spellName) == lower then
			return true
		end
	end
	return false
end

function ns.NoteWeaponCast(spellID, spellName)
	local entry
	if spellID and not (issecretvalue and issecretvalue(spellID)) then
		entry = ns.WEAPON_BUFF_IDS and ns.WEAPON_BUFF_IDS[spellID]
		if not entry and ns.IsWeaponBuff(spellID) then
			entry = select(1, ns.SelectedWeaponBuff())
		end
	end
	if not entry and type(spellName) == "string" then
		for _, choice in ipairs(ns.WeaponChoices() or {}) do
			if entryMatchesName(choice, spellName) then
				entry = choice
				break
			end
		end
	end
	if not entry and ns.weaponNeedLast then
		entry = select(1, ns.SelectedWeaponBuff())
	end
	if not entry then
		return
	end
	rememberWeaponApply(entry)
	if ns.API and ns.API.ClearWeaponTooltipCache then
		ns.API.ClearWeaponTooltipCache()
	end
end

function ns.NoteWeaponEnchantChanged()
	local entry = select(1, ns.SelectedWeaponBuff())
	if not entry then
		return
	end
	local now = GetTime()
	if ns.weaponNeedLast then
		rememberWeaponApply(entry)
		return
	end
	if now < (ns.weaponGrace or 0) or ((ns.weaponCastAt or 0) > 0 and (now - ns.weaponCastAt) < 8) then
		return
	end
	ns.weaponRecheckDrop = true
end

function ns.ClearWeaponMemory()
	ns.weaponGrace = 0
	ns.weaponSeenUntil = 0
	ns.weaponCastAt = 0
	ns.weaponRecheckDrop = nil
end

local function handState(entry, offhand)
	local has, remain, enchId = API.WeaponEnchant(offhand)
	if has == true then
		-- An enchant ID we know that belongs to another buff: a different imbue.
		local owner = enchId and ns.WEAPON_ENCHANT_IDS[enchId]
		if owner and owner ~= entry then
			return "other", 0
		end
		return "up", remain
	end
	if has == false then
		return "no", 0
	end
	return "unknown", 0
end

local function weaponMatchTokens(entry)
	if tokenCache[entry] then
		return tokenCache[entry]
	end
	local tokens, seen = {}, {}
	local function add(token)
		if type(token) ~= "string" or token == "" then
			return
		end
		local key = strlower(token)
		if seen[key] then
			return
		end
		seen[key] = true
		tokens[#tokens + 1] = key
	end
	if entry.match then
		for _, token in ipairs(entry.match) do
			add(token)
		end
	end
	local ids = { entry.id }
	if entry.ranks then
		for _, id in ipairs(entry.ranks) do
			ids[#ids + 1] = id
		end
	end
	for _, id in ipairs(ids) do
		add(API.SpellName(id))
		for _, name in ipairs(API.HintNames(id)) do
			add(name)
		end
	end
	tokenCache[entry] = tokens
	return tokens
end

local function detectSelected(entry)
	local auraOn, auraRemain = API.HasWeaponBuff(entry)
	if auraOn then
		return "up", auraRemain
	end
	local main, mainLeft = handState(entry, false)
	local off, offLeft = handState(entry, true)
	if main == "up" or off == "up" then
		return "up", main == "up" and mainLeft or offLeft
	end
	if API.WeaponTooltipHas(weaponMatchTokens(entry)) then
		return "up", 9999
	end
	if main == "no" and (off == "no" or off == "other") then
		return "missing", 0
	end
	if off == "no" and (main == "no" or main == "other") then
		return "missing", 0
	end
	if (main == "other" or off == "other") and main ~= "unknown" and off ~= "unknown" then
		return "missing", 0
	end
	return "unknown", 0
end

-- Two coated weapons (rogue): each hand is read on its own. The first hand
-- whose poison is missing, wrong or about to run out is the one suggested.
local missingSince = {}

local function buildDualWeapon()
	local now = GetTime()
	local function check(offhand)
		local hand = offhand and "off" or "main"
		local entry, spellID = ns.SelectedWeaponBuff(offhand)
		if not entry or not spellID then
			missingSince[hand] = nil
			return nil
		end
		local state, remain = handState(entry, offhand)
		if state == "up" then
			missingSince[hand] = nil
			if remain and remain > 0 and remain < 9000 and remain <= 30 then
				return spellID, remain
			end
			return nil
		end
		if state == "unknown" then
			-- The client did not answer: stay quiet rather than nag.
			missingSince[hand] = nil
			return nil
		end
		-- Missing or another poison. Wait out the few seconds after a cast,
		-- and only believe a reading that holds for a moment.
		missingSince[hand] = missingSince[hand] or now
		if now < (ns.weaponGrace or 0) or now - missingSince[hand] < 1.5 then
			return nil
		end
		return spellID, 0
	end
	local spellID, remain = check(false)
	if not spellID then
		spellID, remain = check(true)
	end
	ns.weaponNeedLast = spellID ~= nil
	if spellID then
		return spellID, remain or 0, true
	end
	local _, mainID = ns.SelectedWeaponBuff(false)
	return mainID, 0, false
end

function ns.BuildWeapon()
	if ns.WeaponIsDual() then
		return buildDualWeapon()
	end
	local entry, spellID = ns.SelectedWeaponBuff()
	if not entry or not spellID then
		ns.weaponNeedLast = nil
		return
	end
	local status, remain = detectSelected(entry)
	if status ~= "missing" then
		ns.weaponMissingSince = nil
	end
	if status == "up" then
		ns.weaponRecheckDrop = nil
		local hold = remain
		if not hold or hold <= 0 or hold >= 9000 then
			hold = entry.duration or 3600
		end
		ns.weaponSeenUntil = GetTime() + hold
		ns.weaponGrace = 0
		local need = remain > 0 and remain < 9000 and remain <= 30
		ns.weaponNeedLast = need
		return spellID, remain, need
	end
	-- A WEAPON_ENCHANT_CHANGED we did not cause: believe the drop at once.
	if ns.weaponRecheckDrop then
		ns.weaponRecheckDrop = nil
		ns.weaponSeenUntil = 0
		ns.weaponGrace = 0
		ns.weaponNeedLast = true
		return spellID, 0, true
	end
	local now = GetTime()
	if status == "missing" then
		-- The client says no imbue is on the weapon. Past the short grace after
		-- a cast, believe it once it has held for a moment, even if we "saw"
		-- the buff recently (it was removed by hand, or replaced).
		ns.weaponMissingSince = ns.weaponMissingSince or now
		if now >= (ns.weaponGrace or 0) and now - ns.weaponMissingSince >= 1.5 then
			ns.weaponSeenUntil = 0
			ns.weaponGrace = 0
			ns.weaponNeedLast = true
			return spellID, 0, true
		end
		if now < (ns.weaponGrace or 0) or now < (ns.weaponSeenUntil or 0) then
			local left = math.max((ns.weaponSeenUntil or 0) - now, 0)
			local need = left > 0 and left <= 30
			ns.weaponNeedLast = need
			return spellID, left, need
		end
		ns.weaponSeenUntil = 0
		ns.weaponGrace = 0
		ns.weaponNeedLast = true
		return spellID, 0, true
	end
	if now < (ns.weaponGrace or 0) then
		ns.weaponNeedLast = false
		return spellID, 0, false
	end
	local seen = ns.weaponSeenUntil or 0
	if now < seen then
		local left = seen - now
		local need = left <= 30
		ns.weaponNeedLast = need
		return spellID, left, need
	end
	ns.weaponNeedLast = true
	return spellID, 0, true
end
