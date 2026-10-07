local addonName, ns = ...
local I = ns.API.I

-- Units: health, range, enemies, roles, casts and creature types.
local readable, safe, unitExists = I.readable, I.safe, I.unitExists

local enemyCountAt, enemyCountVal, enemyCountValKey = 0, 0, nil

function ns.API.EnemyCount(maxYards)
	local now = GetTime()
	maxYards = tonumber(maxYards)
	local cacheKey = maxYards or 0
	if enemyCountAt > 0 and (now - enemyCountAt) < 0.3 and enemyCountValKey == cacheKey then
		return enemyCountVal
	end
	local count = 0
	local function hostile(unit)
		local okEx, exists = pcall(UnitExists, unit)
		if not okEx or not exists then
			return false
		end
		local okDead, dead = pcall(UnitIsDead, unit)
		if okDead and dead then
			return false
		end
		local okAtk, atk = pcall(UnitCanAttack, "player", unit)
		if okAtk and atk then
			return true
		end
		local okR, react = pcall(UnitReaction, "player", unit)
		return okR and type(react) == "number" and react <= 4
	end
	local function plain(value)
		return not (issecretvalue and issecretvalue(value))
	end
	-- In combat, count only enemies fighting you: on your threat table, or
	-- targeting you or your pet. A mob fighting someone else nearby does not
	-- count. Out of combat every hostile nameplate counts.
	local function inFight(unit)
		local okP, pcombat = pcall(UnitAffectingCombat, "player")
		if not (okP and pcombat) then
			return true
		end
		-- A readable threat answer is decisive for you; nil means the mob is
		-- not on your threat table, but it may still be fighting your pet.
		local threatKnown = false
		if UnitThreatSituation then
			local ok, status = pcall(UnitThreatSituation, "player", unit)
			if ok and plain(status) then
				if status ~= nil then
					return true
				end
				threatKnown = true
			end
		end
		local targetUnit = unit .. "target"
		for _, who in ipairs({ "player", "pet" }) do
			local ok, same = pcall(UnitIsUnit, targetUnit, who)
			if ok and plain(same) and same == true then
				return true
			end
		end
		if threatKnown then
			return false
		end
		local okC, combat = pcall(UnitAffectingCombat, unit)
		return okC and plain(combat) and combat == true or false
	end
	local function inYards(unit)
		if not maxYards or maxYards <= 0 then
			return true
		end
		local minY, maxY = ns.API.TargetRangeBand(unit)
		if minY and minY > maxYards then
			return false
		end
		if maxY and maxY <= maxYards then
			return true
		end
		-- ~10 yd band via duel interact when yards <= 10.
		if maxYards <= 10 then
			local close
			if CheckInteractDistance then
				local ok, result = pcall(CheckInteractDistance, unit, 3)
				if ok then
					close = safe(result, nil)
				end
				if close == nil then
					ok, result = pcall(CheckInteractDistance, unit, 2)
					if ok then
						close = safe(result, nil)
					end
				end
			end
			return close == true or close == 1
		end
		if maxYards <= 28 then
			if CheckInteractDistance then
				local ok, result = pcall(CheckInteractDistance, unit, 1)
				if ok then
					result = safe(result, nil)
					return result == true or result == 1
				end
			end
			return true
		end
		return true
	end
	for i = 1, 40 do
		local unit = "nameplate" .. i
		if hostile(unit) and inFight(unit) and inYards(unit) then
			count = count + 1
		end
	end
	if count < 1 and hostile("target") and inYards("target") then
		count = 1
	end
	enemyCountAt = now
	enemyCountVal = count
	enemyCountValKey = cacheKey
	return count
end

local function unitFriendly(unit)
	if not unitExists(unit) then
		return false
	end
	local okDead, dead = pcall(UnitIsDead, unit)
	if okDead and dead then
		return false
	end
	local okAtk, atk = pcall(UnitCanAttack, "player", unit)
	if okAtk and readable(atk) and atk then
		return false
	end
	if okAtk and not readable(atk) then
		return false
	end
	local okR, react = pcall(UnitReaction, "player", unit)
	if okR and readable(react) and type(react) == "number" then
		return react > 4
	end
	if okAtk and readable(atk) and not atk then
		return true
	end
	return false
end

local function healNameSet()
	if I.healNames and next(I.healNames) then
		return I.healNames
	end
	I.healNames = {}
	for id in pairs(ns.HEAL_SPELL_IDS or {}) do
		local name = ns.API.SpellName(id)
		if name then
			I.healNames[name] = true
		end
	end
	return I.healNames
end

function ns.API.IsHelpful(spellID, opt)
	if opt and opt.heal then
		return true
	end
	local id = ns.API.Resolve(spellID) or spellID
	if ns.HEAL_SPELL_IDS and ((id and ns.HEAL_SPELL_IDS[id]) or (spellID and ns.HEAL_SPELL_IDS[spellID])) then
		return true
	end
	local name = ns.API.SpellName(id) or ns.API.SpellName(spellID)
	if name and healNameSet()[name] then
		return true
	end
	if C_Spell and C_Spell.IsSpellHelpful then
		local ok, helpful = pcall(C_Spell.IsSpellHelpful, id)
		if ok and helpful == true then
			return true
		end
	end
	return false
end

function ns.API.IsHealSpell(spellID, opt)
	if opt and opt.heal then
		return true
	end
	if not spellID then
		return false
	end
	if ns.IsMaintenanceBuff and ns.IsMaintenanceBuff(spellID) then
		return false
	end
	if ns.IsWeaponBuff and ns.IsWeaponBuff(spellID) then
		return false
	end
	local id = ns.API.Resolve(spellID) or spellID
	if ns.HEAL_SPELL_IDS and ((id and ns.HEAL_SPELL_IDS[id]) or ns.HEAL_SPELL_IDS[spellID]) then
		return true
	end
	local name = ns.API.SpellName(id) or ns.API.SpellName(spellID)
	if name and healNameSet()[name] then
		return true
	end
	return false
end

function ns.API.IsHarmful(spellID)
	local id = ns.API.Resolve(spellID) or spellID
	if C_Spell and C_Spell.IsSpellHarmful then
		local ok, harmful = pcall(C_Spell.IsSpellHarmful, id)
		if ok and harmful == true then
			return true
		end
	end
	return false
end

local function numberOrNil(value)
	value = safe(value, nil)
	if type(value) == "number" and value == value then
		return value
	end
	return nil
end

function ns.API.SpellMaxRange(spellID)
	local info = ns.API.SpellInfo(ns.API.Resolve(spellID) or spellID)
	return info and numberOrNil(info.maxRange) or nil
end

local function interactInRange(unit, index)
	if not CheckInteractDistance then
		return nil
	end
	local ok, result = pcall(CheckInteractDistance, unit, index)
	if not ok then
		return nil
	end
	result = safe(result, nil)
	if result == true or result == 1 then
		return true
	end
	if result == false or result == 0 then
		return false
	end
	return nil
end

function ns.API.TargetRangeBand(unit)
	unit = unit or "target"
	if not unitExists(unit) then
		return nil, nil
	end
	if UnitDistanceSquared then
		-- Only valid when the client says it measured (group members); for an
		-- enemy it returns 0 with checked = false, which read as "in melee".
		local ok, distSq, checked = pcall(UnitDistanceSquared, unit)
		if ok and not (issecretvalue and (issecretvalue(checked) or issecretvalue(distSq))) and checked == true then
			distSq = numberOrNil(distSq)
			if distSq and distSq >= 0 then
				local yards = math.sqrt(distSq)
				return yards, yards
			end
		end
	end
	-- Classic: 3 ~10 yd (duel), 2 ~11 yd (trade), 1 ~28 yd (inspect).
	local close = interactInRange(unit, 3)
	if close == nil then
		close = interactInRange(unit, 2)
	end
	local inspect = interactInRange(unit, 1)
	if close == true then
		return 0, 11
	end
	if inspect == true then
		return 11, 28
	end
	if inspect == false then
		return 28, 100
	end
	return nil, nil
end

local function rangeUnitFor(spellID, opt)
	opt = opt or {}
	if opt.heal or (ns.API.IsHelpful(spellID, opt) and not ns.API.IsHarmful(spellID)) then
		return ns.API.HealRangeUnit(opt)
	end
	return "target"
end

function ns.API.NeedsRange(spellID, opt)
	opt = opt or {}
	if opt.nopet or opt.nocombat then
		return false
	end
	local id = ns.API.Resolve(spellID) or spellID
	if opt.heal then
		local unit = rangeUnitFor(id, opt)
		return unit ~= "player"
	end
	if opt.hostile then
		return true
	end
	if ns.API.IsHarmful(id) then
		return true
	end
	return false
end

-- "none" = no check, "in" / "out" / "unknown".
-- Unknown is never treated as in-range for the first HUD slot.
-- Yard band can override a wrong/secret IsSpellInRange so melee spells
-- stay out at distance and long-range spells can still win slot 1 (all classes).
---Range of the spell's target: "in", "out", "unknown" or "none" (no range).
---@param spellID integer
---@param opt? KYR.StepOpt
---@return "in"|"out"|"unknown"|"none"
function ns.API.RangeState(spellID, opt)
	opt = opt or {}
	local id = ns.API.Resolve(spellID) or spellID
	if not id or not ns.API.NeedsRange(id, opt) then
		return "none"
	end
	local unit = rangeUnitFor(id, opt)
	-- A self-cast (heal on yourself) has no distance. The action slot would
	-- report "out of range" while an enemy is targeted, so skip the check.
	if unit == "player" then
		return "in"
	end
	if not unitExists(unit) then
		return "out"
	end
	local maxR = ns.API.SpellMaxRange(id)
	if maxR == 0 and ns.API.IsHarmful(id) then
		maxR = 5
	end
	local minY, maxY = ns.API.TargetRangeBand(unit)
	-- Melee-range spell vs clearly far target: always out (every class).
	if minY and maxR and maxR <= 5 and minY > 8 then
		return "out"
	end
	if minY and maxR and minY >= maxR then
		return "out"
	end
	local slot = ns.SpellBarSlot and ns.SpellBarSlot(id)
	local flag
	if ns.SpellInRange then
		flag = ns.SpellInRange(id, slot)
	end
	if flag == true then
		return "in"
	end
	if flag == false then
		-- Band says the target is inside max range: prefer in when Forever
		-- reports false/secret for long-range shots (Hunter/mage/etc.).
		if maxY and maxR and maxR > 5 and maxY <= maxR then
			return "in"
		end
		return "out"
	end
	if maxY and maxR and maxY <= maxR then
		return "in"
	end
	return "unknown"
end

-- mode: "in" (slot 1), "notOut" (unknown allowed), "any" (lookahead / OOR).
function ns.API.InSpellRange(spellID, opt, mode)
	mode = mode or "in"
	local state = ns.API.RangeState(spellID, opt)
	if state == "none" or state == "in" then
		return true
	end
	if state == "out" then
		return mode == "any"
	end
	return mode ~= "in"
end

-- The unit a heal lands on when pressed from the action bar: the mouseover
-- (only with the client's mouseover cast on), a friendly target, else you
-- (an enemy target or no target heals yourself).
local function mouseoverCastOn()
	if not GetCVarBool then
		return false
	end
	local ok, on = pcall(GetCVarBool, "enableMouseoverCast")
	return ok and on == true
end

---The unit a press of a heal would land on.
---@param opt? KYR.StepOpt
---@return string
function ns.API.HealUnit(opt)
	opt = opt or {}
	if opt.unit and unitExists(opt.unit) then
		return opt.unit
	end
	if mouseoverCastOn() and unitFriendly("mouseover") then
		return "mouseover"
	end
	if unitFriendly("target") then
		return "target"
	end
	return "player"
end

function ns.API.HealHealth(opt)
	return ns.API.Health(ns.API.HealUnit(opt))
end

function ns.API.HealRangeUnit(opt)
	return ns.API.HealUnit(opt)
end

function ns.API.Hostile()
	if not UnitExists("target") then
		return false
	end
	local dead = UnitIsDead("target")
	if readable(dead) and dead then
		return false
	end
	local reaction = UnitReaction("player", "target")
	if not readable(reaction) then
		return true
	end
	return reaction <= 4
end

---Health percent of the unit; 100 when the client hides it.
---@param unit? string Defaults to "player".
---@return number
function ns.API.Health(unit)
	unit = unit or "player"
	local health = safe(UnitHealth(unit), nil)
	local max = safe(UnitHealthMax(unit), nil)
	if health and max and max > 0 then
		if unit == "player" then
			ns.API.healthHidden = false
		end
		return (health / max) * 100
	end
	-- Plain values are hidden: ask for the percentage instead.
	if UnitHealthPercent and CurveConstants and CurveConstants.ScaleTo100 then
		local ok, pct = pcall(UnitHealthPercent, unit, true, CurveConstants.ScaleTo100)
		pct = ok and safe(pct, nil) or nil
		if type(pct) == "number" then
			if unit == "player" then
				ns.API.healthHidden = false
			end
			return pct
		end
	end
	-- Hidden in combat: callers that need a number get 100; the heal cue
	-- switches to a glow whose alpha the client drives (ns.GlowHiddenHeal).
	if unit == "player" then
		ns.API.healthHidden = true
	end
	return 100
end

-- Smart heal threshold: cast a heal once the missing health roughly equals
-- what the spell restores, so it is not wasted. Needs the heal size (parsed
-- from the spell text) and the maximum health (remembered while readable,
-- because the client hides it in combat).
ns.API.healAmountCache = {}
local playerMaxHealth

function ns.API.MaxHealth(unit)
	unit = unit or "player"
	local max = safe(UnitHealthMax(unit), nil)
	if type(max) == "number" and max > 0 then
		if unit == "player" then
			playerMaxHealth = max
		end
		return max
	end
	if unit == "player" then
		return playerMaxHealth
	end
	return nil
end

function ns.API.HealAmount(spellID)
	local id = ns.API.Resolve(spellID) or spellID
	local cache = ns.API.healAmountCache
	if cache[id] ~= nil then
		return cache[id] or nil
	end
	if not C_Spell or not C_Spell.GetSpellDescription then
		return nil
	end
	local ok, desc = pcall(C_Spell.GetSpellDescription, id)
	desc = ok and safe(desc, nil) or nil
	if type(desc) ~= "string" or desc == "" then
		return nil -- text not loaded yet: ask again next time
	end
	desc = desc:lower():gsub(",", "")
	local lo, hi = desc:match("heal[^%d]*(%d+)%s+to%s+(%d+)")
	local amount
	if lo then
		amount = (tonumber(lo) + tonumber(hi)) / 2
	else
		local single = desc:match("heal[^%d]*(%d+)")
		amount = single and tonumber(single) or nil
	end
	cache[id] = amount or false
	return amount
end

-- Returns the health percent at or below which the heal should be offered.
-- Emergency steps (own threshold under 50) keep their value.
function ns.API.AutoHealThreshold(spellID, unit, fallback)
	if ns.db and ns.db.autoHeal == false then
		return fallback
	end
	if fallback and fallback < 50 then
		return fallback
	end
	local amount = ns.API.HealAmount(spellID)
	local maxHp = ns.API.MaxHealth(unit or "player")
	if not amount or not maxHp or maxHp <= 0 then
		return fallback
	end
	local pct = 100 - (amount / maxHp) * 100
	if pct < 30 then
		pct = 30
	elseif pct > 92 then
		pct = 92
	end
	return pct
end

-- True when the client hides this unit's health (combat), so no number can be compared.
function ns.API.HealthHiddenFor(unit)
	local health = safe(UnitHealth(unit), nil)
	local max = safe(UnitHealthMax(unit), nil)
	if health and max and max > 0 then
		return false
	end
	if UnitHealthPercent and CurveConstants and CurveConstants.ScaleTo100 then
		local ok, pct = pcall(UnitHealthPercent, unit, true, CurveConstants.ScaleTo100)
		if ok and type(safe(pct, nil)) == "number" then
			return false
		end
	end
	return true
end

-- True when the client hides your mana (combat), so manaMax cannot be compared.
function ns.API.ManaHidden()
	local okCur, current = pcall(UnitPower, "player", 0)
	local okMax, maxp = pcall(UnitPowerMax, "player", 0)
	return not (okCur and okMax and readable(current) and readable(maxp))
end

-- "You must be behind your target": remembered for a few seconds on that target.
local notBehindAt, notBehindGUID
local NOT_BEHIND_SECONDS = 3

local function targetGUID()
	local ok, guid = pcall(UnitGUID, "target")
	return ok and safe(guid, nil) or nil
end

-- Dead hunter pet: seen as a dead "pet" unit, or from the "Your pet is
-- dead" error after the unit is gone. Cleared once a live pet is out.
local petDeadFlag = false

function ns.API.PetDead()
	if unitExists("pet") then
		local ok, dead = pcall(UnitIsDead, "pet")
		petDeadFlag = ok and safe(dead, false) == true
	end
	return petDeadFlag
end

function ns.API.NoteUIError(message)
	if type(message) ~= "string" or not readable(message) then
		return false
	end
	local lower = strlower(message)
	if message == SPELL_FAILED_NOT_BEHIND or lower:find("behind", 1, true) then
		notBehindAt = GetTime()
		notBehindGUID = targetGUID()
		return true
	end
	if lower:find("pet is dead", 1, true) then
		petDeadFlag = true
		return true
	end
	if lower:find("have a pet", 1, true) then
		petDeadFlag = false
		return true
	end
	return false
end

function ns.API.NotBehindRecently()
	if not notBehindAt or (GetTime() - notBehindAt) > NOT_BEHIND_SECONDS then
		return false
	end
	local guid = targetGUID()
	return guid == nil or notBehindGUID == nil or guid == notBehindGUID
end

function ns.API.HealthHidden()
	ns.API.Health("player")
	return ns.API.healthHidden == true
end

-- Creature types -> canonical EN keys.
local CREATURE_CANON = {
	mechanical = "mechanical",
	machine = "mechanical",
	elemental = "elemental",
	undead = "undead",
	demon = "demon",
}

local function creatureCanon(ctype)
	if type(ctype) ~= "string" or ctype == "" then
		return nil
	end
	local key = strlower(ctype)
	return CREATURE_CANON[key] or key
end

local function targetCreatureCanon()
	if not unitExists("target") then
		return nil
	end
	-- Secret when the unit is not player-controlled or in your group
	-- (SecretWhenUnitIdentityRestricted): then the type is unknown.
	local ok, ctype = pcall(UnitCreatureType, "target")
	if not ok or not readable(ctype) or type(ctype) ~= "string" or ctype == "" then
		return nil
	end
	return creatureCanon(ctype)
end

local function creatureListHas(list, canon)
	if not canon then
		return false
	end
	if list == true then
		return canon == "mechanical" or canon == "elemental"
	end
	if type(list) == "string" then
		return canon == creatureCanon(list)
	end
	if type(list) == "table" then
		for _, name in ipairs(list) do
			if type(name) == "string" and canon == creatureCanon(name) then
				return true
			end
		end
	end
	return false
end

function ns.API.CreatureBlocked(list)
	if list == nil or list == false then
		return false
	end
	return creatureListHas(list, targetCreatureCanon())
end

function ns.API.CreatureMatch(list)
	if list == nil or list == false then
		return true
	end
	local canon = targetCreatureCanon()
	if not canon then
		-- Unknown type: let the step through; Exorcism's own "usable" check
		-- still refuses a wrong target.
		return true
	end
	return creatureListHas(list, canon)
end

function ns.API.IsRaidmob()
	if not unitExists("target") then
		return false
	end
	local okC, classification = pcall(UnitClassification, "target")
	if okC and type(classification) == "string" then
		if classification == "worldboss" or classification == "rareelite" or classification == "elite" then
			return true
		end
	end
	local okT, tlvl = pcall(UnitLevel, "target")
	local okP, plvl = pcall(UnitLevel, "player")
	if okT and okP and type(tlvl) == "number" and type(plvl) == "number" then
		if tlvl < 0 or tlvl > plvl + 2 then
			return true
		end
	end
	return false
end

-- True when the target attacks you, false when it attacks someone else or
-- no one, nil when unknown. UnitThreatSituation("player", "target") is not
-- secret (SecretWhenUnitThreatStateRestricted: player vs target is allowed);
-- 2 / 3 mean you have aggro. UnitIsUnit("targettarget", ...) is a compound
-- token, always secret on addon-restricted maps, so it is only a fallback.
function ns.API.TargetAttacksYou()
	if not unitExists("target") then
		return false
	end
	if UnitThreatSituation then
		local ok, status = pcall(UnitThreatSituation, "player", "target")
		if ok and readable(status) and type(status) == "number" then
			return status >= 2
		end
	end
	if not unitExists("targettarget") then
		return false
	end
	local ok, onMe = pcall(UnitIsUnit, "targettarget", "player")
	if ok and readable(onMe) then
		return onMe == true
	end
	return nil
end

function ns.API.TargetInMelee()
	if not unitExists("target") or not ns.API.Hostile() then
		return false
	end
	-- Distance band first: never treat a far target as melee (role auto + queue).
	local minY, maxY = ns.API.TargetRangeBand("target")
	if minY and minY > 8 then
		return false
	end
	if maxY and maxY <= 5 then
		return true
	end
	local token = ns.ClassToken and ns.ClassToken()
	local probe
	local S = ns.Spell
	if token == "HUNTER" and S and S.Hunter then
		probe = S.Hunter.RaptorStrike or S.Hunter.WingClip or S.Hunter.MongooseBite
	elseif token == "SHAMAN" and S and S.Shaman then
		probe = S.Shaman.Stormstrike or S.Shaman.LavaLash or S.Shaman.EarthShock
	elseif token == "WARRIOR" and S and S.Warrior then
		probe = S.Warrior.HeroicStrike or S.Warrior.Rend
	elseif token == "ROGUE" and S and S.Rogue then
		probe = S.Rogue.SinisterStrike
	elseif token == "DRUID" and S and S.Druid then
		probe = S.Druid.Claw or S.Druid.Mangle or S.Druid.Maul
	elseif token == "PALADIN" and S and S.Paladin then
		probe = S.Paladin.CrusaderStrike or S.Paladin.Judgement
	end
	if probe then
		local state = ns.API.RangeState(probe, { hostile = true })
		if state == "in" then
			return true
		end
		if state == "out" then
			return false
		end
	end
	if minY and minY <= 5 then
		return true
	end
	local close = interactInRange("target", 3)
	return close == true
end

function ns.API.CombatNotice()
	local token = ns.ClassToken and ns.ClassToken()
	if token ~= "HUNTER" and token ~= "WARLOCK" then
		return nil
	end
	if not ns.API.InCombat() then
		return nil
	end
	-- Only once a pet can be summoned: hunters get Call Pet around level 10,
	-- and a warlock may not have a demon spell yet.
	local summons
	if token == "HUNTER" then
		summons = { "CallPet" }
	else
		summons =
			{ "SummonImp", "SummonVoidwalker", "SummonSuccubus", "SummonFelhunter", "SummonIncubus", "SummonFelguard" }
	end
	local book = token == "HUNTER" and ns.Spell.Hunter or ns.Spell.Warlock
	local canSummon = false
	for _, key in ipairs(summons) do
		local id = book and book[key]
		if id and ns.API.Known(id) then
			canSummon = true
			break
		end
	end
	if not canSummon then
		return nil
	end
	if not unitExists("pet") then
		return token == "WARLOCK" and "NOTICE_SUMMON_DEMON" or "NOTICE_CALL_PET"
	end
	if not ns.API.Hostile() then
		return nil
	end
	local okT, hasPetTarget = pcall(UnitExists, "pettarget")
	if okT and not hasPetTarget then
		return "NOTICE_PET_ASSIST"
	end
	local okC, petCombat = pcall(UnitAffectingCombat, "pet")
	if okC and petCombat == false then
		return "NOTICE_PET_ASSIST"
	end
	return nil
end

-- Role from the talent tree with the most points, judged by the tree's name
-- (not its position or the role the client reports, which can differ on
-- Forever): Protection = tank, Holy / Discipline / Restoration = heal,
-- anything else = damage. Cached for a few seconds; nil = no talent data yet.
local TANK_TREE_WORDS = { "protection" }
local HEAL_TREE_WORDS = { "restoration", "holy", "discipline" }
local specRoleCache, specRoleAt = nil, -10
local treeCache, treeAt = nil, -10

-- Lower-case name of the talent tree with the most points; nil = no points
-- or no talent data yet. Cached for a few seconds.
function ns.API.MainTree()
	local now = GetTime()
	if treeAt > 0 and now - treeAt < 3 then
		return treeCache
	end
	treeAt = now
	treeCache = nil
	local info = C_SpecializationInfo and C_SpecializationInfo.GetSpecializationInfo
	if not info then
		return nil
	end
	local bestPoints = 0
	for index = 1, 4 do
		local ok, specId, name, _, _, _, _, points = pcall(info, index)
		if not ok or not specId or specId == 0 then
			break
		end
		points = tonumber(safe(points, 0)) or 0
		if points > bestPoints and type(name) == "string" and readable(name) then
			bestPoints = points
			treeCache = name:lower()
		end
	end
	return treeCache
end

local function specRole()
	local now = GetTime()
	if specRoleAt > 0 and now - specRoleAt < 3 then
		return specRoleCache
	end
	specRoleAt = now
	specRoleCache = nil
	local bestName = ns.API.MainTree()
	if not bestName then
		return nil
	end
	specRoleCache = "damage"
	for _, word in ipairs(TANK_TREE_WORDS) do
		if bestName:find(word, 1, true) then
			specRoleCache = "tank"
		end
	end
	for _, word in ipairs(HEAL_TREE_WORDS) do
		if bestName:find(word, 1, true) then
			specRoleCache = "heal"
		end
	end
	return specRoleCache
end

-- Picks the playstyle from the character, no clicking needed: talent tree,
-- defensive stance / Righteous Fury, and melee range for hunter / shaman.
function ns.SyncAutoRole()
	if not ns.db or ns.db.roleAuto == false then
		return
	end
	local token = ns.ClassToken and ns.ClassToken()
	local want
	if token == "HUNTER" then
		if not ns.API.Hostile() or not unitExists("target") then
			return
		end
		want = ns.API.TargetInMelee() and "melee" or "range"
	elseif token == "WARRIOR" or token == "PALADIN" or token == "PRIEST" or token == "SHAMAN" or token == "DRUID" then
		local spec = specRole()
		if spec == nil and (token ~= "SHAMAN" or ns.db.role == "heal") then
			-- No talent data yet (low level): keep whatever is set.
			return
		end
		if spec == "tank" or spec == "heal" then
			want = spec
		elseif token == "SHAMAN" then
			-- Damage shaman: caster at range, melee when in reach of the target.
			if not ns.API.Hostile() or not unitExists("target") then
				if ns.db.role == "heal" then
					want = "caster"
				else
					return
				end
			else
				want = ns.API.TargetInMelee() and "melee" or "caster"
			end
		elseif token == "DRUID" then
			want = "hybrid"
		else
			want = "damage"
		end
	else
		return
	end
	want = ns.NormalizeRole and ns.NormalizeRole(want) or want
	if ns.db.role == want then
		return
	end
	-- In-memory only while fighting: FlushProfile mid-combat feels like lag.
	ns.db.role = want
	if ns.InvalidateAPLCache then
		ns.InvalidateAPLCache()
	end
	if ns.UI and ns.UI.RefreshRoles then
		ns.UI.RefreshRoles()
	end
	if ns.InvalidateTick then
		ns.InvalidateTick()
	end
end

function ns.API.InCombat()
	local ok, combat = pcall(UnitAffectingCombat, "player")
	if ok and readable(combat) then
		return combat and true or false
	end
	return ok and combat and true or false
end

local EAT_AURA = {
	food = true,
	drink = true,
}

function ns.API.IsEating()
	if not C_UnitAuras or not C_UnitAuras.GetAuraDataByIndex then
		return false
	end
	for i = 1, 40 do
		local ok, aura = pcall(C_UnitAuras.GetAuraDataByIndex, "player", i, "HELPFUL")
		if not ok or not aura then
			break
		end
		local name = safe(aura.name, nil)
		if name then
			if EAT_AURA[strlower(name)] then
				return true
			end
		end
	end
	return false
end

function ns.API.ShouldHideIdle()
	if not ns.db then
		return false
	end
	local function yes(fn, ...)
		if type(fn) ~= "function" then
			return false
		end
		local ok, value = pcall(fn, ...)
		return ok and value == true
	end
	if yes(UnitIsDeadOrGhost, "player") or yes(UnitOnTaxi, "player") or yes(IsMounted) then
		return true
	end
	if ns.API.IsEating() == true then
		return true
	end
	if not ns.API.InCombat() and yes(IsResting) then
		return true
	end
	return false
end

function ns.API.CastRemain()
	local function remain(fn)
		if not fn then
			return 0
		end
		local ok, name, _, _, _, endTime = pcall(fn, "player")
		if not ok or name == nil then
			return 0
		end
		if issecretvalue and issecretvalue(name) then
			return 0
		end
		endTime = tonumber(safe(endTime, nil))
		if not endTime then
			return 0
		end
		if endTime > 100000 then
			endTime = endTime / 1000
		end
		local left = endTime - GetTime()
		if left < 0 then
			return 0
		end
		return left
	end
	local cast = remain(UnitCastingInfo)
	if cast > 0 then
		return cast
	end
	return remain(UnitChannelInfo)
end

function ns.API.CastingSpell(spellID)
	local name = ns.API.SpellName(spellID)
	if type(name) ~= "string" or name == "" then
		return false
	end
	local function same(fn)
		if not fn then
			return false
		end
		local ok, castName = pcall(fn, "player")
		if not ok or type(castName) ~= "string" or castName == "" then
			return false
		end
		if issecretvalue and issecretvalue(castName) then
			return false
		end
		return castName == name
	end
	return same(UnitCastingInfo) or same(UnitChannelInfo)
end

function ns.API.TargetCasting()
	if not UnitExists("target") then
		return false
	end
	-- notInterruptible is return 8 of UnitCastingInfo (after castID) and
	-- return 7 of UnitChannelInfo.
	local function peek(fn, kickIndex)
		if not fn then
			return false, nil
		end
		local ok, name = pcall(fn, "target")
		if not ok or name == nil then
			return false, nil
		end
		local okKick, notKick = pcall(function()
			return (select(kickIndex, fn("target")))
		end)
		if okKick and readable(notKick) and notKick then
			return false, true
		end
		return true, false
	end
	local casting = peek(UnitCastingInfo, 8)
	if casting then
		return true
	end
	casting = peek(UnitChannelInfo, 7)
	if casting then
		return true
	end
	return ns.API.castTarget == true
end

function ns.API.Purgable(stealableOnly)
	if not UnitExists("target") or not C_UnitAuras or not C_UnitAuras.GetAuraDataByIndex then
		return false
	end
	for i = 1, 40 do
		local ok, aura = pcall(C_UnitAuras.GetAuraDataByIndex, "target", i, "HELPFUL")
		if not ok or not aura then
			break
		end
		if stealableOnly then
			if readable(aura.isStealable) and aura.isStealable then
				return true
			end
		else
			if readable(aura.isStealable) and aura.isStealable then
				return true
			end
			local dispel = safe(aura.dispelName, nil)
			if dispel == "Magic" then
				return true
			end
		end
	end
	return false
end

function ns.API.HasDebuffType(types, unit)
	if not types or not C_UnitAuras or not C_UnitAuras.GetAuraDataByIndex then
		return false
	end
	if unit and unit ~= "player" and not unitFriendly(unit) then
		return false
	end
	unit = unit or "player"
	local want = {}
	for _, name in ipairs(types) do
		want[name] = true
	end
	for i = 1, 40 do
		local ok, aura = pcall(C_UnitAuras.GetAuraDataByIndex, unit, i, "HARMFUL")
		if not ok or not aura then
			break
		end
		local dispel = safe(aura.dispelName, nil)
		if dispel and want[dispel] then
			return true
		end
	end
	return false
end
