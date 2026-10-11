local addonName, ns = ...
local I = ns.API.I

-- Is this list step offered right now? (StepOk and its checks).
local readable, safe, unitExists = I.readable, I.safe, I.unitExists

local function hasResources(id)
	if C_Spell and C_Spell.GetSpellPowerCost then
		local ok, costs = pcall(C_Spell.GetSpellPowerCost, id)
		if ok and type(costs) == "table" then
			for _, cost in ipairs(costs) do
				if type(cost) == "table" then
					local needed = tonumber(safe(cost.cost, nil))
					local ptype = tonumber(safe(cost.type, nil)) or 0
					-- Negative power types are health costs (Bloodrage, Life Tap): not a resource to wait for.
					if needed and needed > 0 and ptype >= 0 then
						local cur = safe(UnitPower("player", ptype), nil)
						if type(cur) == "number" and cur < needed then
							return false
						end
					end
				end
			end
		end
	end
	return true
end

local function readUsable(fn, id)
	if not fn then
		return nil, nil
	end
	local ok, usable, noMana = pcall(fn, id)
	if not ok then
		return nil, nil
	end
	return safe(usable, nil), safe(noMana, nil)
end

function ns.API.Ready(spellID, opt, ignoreCooldown)
	local id = ns.API.Resolve(spellID)
	if not id then
		return false
	end
	if not ignoreCooldown then
		local remain = ns.API.Cooldown(id)
		if remain > 0.2 then
			return false
		end
	end
	local helpfulOnly = ns.API.IsHelpful(id, opt) and not ns.API.IsHarmful(id)
	local usable, noMana = readUsable(C_Spell and C_Spell.IsSpellUsable, id)
	if noMana == true then
		return false
	end
	if usable == true then
		return true
	end
	if helpfulOnly then
		return hasResources(id)
	end
	-- Camelot marks other spells unusable during a cast or GCD. Fillers
	-- already bypass this; shocks and DoTs must still enter the lookahead.
	if usable == false then
		if ns.API.CastRemain() > 0 then
			return hasResources(id)
		end
		local last = ns.API.lastCastAt
		if last and (GetTime() - last) < 1.55 then
			return hasResources(id)
		end
		return false
	end
	return hasResources(id)
end

-- Why a step is not offered right now (shown on the Rotation / Defense rows).
local rejectReason
local function reject(reason)
	rejectReason = reason
	return false
end

---Why a step is not offered now, or nil when it is.
---@param spellID integer
---@param opt? KYR.StepOpt
---@return string?
function ns.API.WhyNot(spellID, opt)
	rejectReason = nil
	if ns.API.StepOk(spellID, opt, 0.2) then
		return nil
	end
	return rejectReason or "unknown"
end

-- Step conditions, checked in this order. A check returns the reason the step
-- is refused, or nil. The first entry is the option the check belongs to (the
-- check only runs when the step has it); nil = always runs. c is the context:
-- c.id (resolved spell), c.opt, c.gate (look-ahead seconds), c.helpful and
-- c.auraUnit (the unit a helpful spell would land on).
---@type { [1]: string?, [2]: fun(c: table): string? }[]
local STEP_CHECKS = {
	{
		"hostile",
		function()
			if not ns.API.Hostile() then
				return "needs an enemy target"
			end
		end,
	},
	-- Some spells only pay off later while leveling (longer fights, bigger
	-- mana pool): minLevel = from this character level on.
	{
		"minLevel",
		function(c)
			local ok, level = pcall(UnitLevel, "player")
			level = ok and tonumber(safe(level, nil)) or nil
			if level and level < c.opt.minLevel then
				return ("from level %d"):format(c.opt.minLevel)
			end
		end,
	},
	-- maxLevel = up to this character level (a lower-level stand-in, like
	-- Stoneskin Totem until Strength of Earth Totem is worth its mana).
	{
		"maxLevel",
		function(c)
			local ok, level = pcall(UnitLevel, "player")
			level = ok and tonumber(safe(level, nil)) or nil
			if level and level > c.opt.maxLevel then
				return ("up to level %d"):format(c.opt.maxLevel)
			end
		end,
	},
	-- reach = the target is at most this many yards away (a spell without a
	-- range of its own, like a racial, would otherwise be pressable at any
	-- distance). An unknown distance only counts in combat.
	{
		"reach",
		function(c)
			local _, farthest = ns.API.TargetRangeBand("target")
			if farthest == nil then
				if not ns.API.InCombat() then
					return "the target's distance is unknown"
				end
			elseif farthest > c.opt.reach then
				return ("the target is farther than %d yards"):format(c.opt.reach)
			end
		end,
	},
	-- weakTarget = the target is below your level (an unknown level counts as
	-- not weak).
	{
		"weakTarget",
		function()
			local okT, targetLevel = pcall(UnitLevel, "target")
			local okP, level = pcall(UnitLevel, "player")
			targetLevel, level = okT and tonumber(safe(targetLevel, nil)), okP and tonumber(safe(level, nil))
			if not (targetLevel and level and targetLevel >= 0 and targetLevel < level) then
				return "the target is not below your level"
			end
		end,
	},
	-- Auto-repeat attacks (Auto Shot): suggest turning it on, never while it
	-- is already running (pressing it again would stop it).
	{
		"autoRepeat",
		function(c)
			local repeating = false
			local check = (C_Spell and C_Spell.IsAutoRepeatSpell) or IsAutoRepeatSpell
			if check then
				local ok, on = pcall(check, c.id)
				repeating = ok and on == true
			end
			if not repeating and IsAutoRepeatSpell and check ~= IsAutoRepeatSpell then
				local ok, on = pcall(IsAutoRepeatSpell, ns.API.SpellName(c.id) or c.id)
				repeating = ok and on == true
			end
			if repeating then
				return "already on"
			end
		end,
	},
	-- Fight-only buffs (seals, totems, Tiger's Fury): in combat, or right
	-- before a pull with an enemy targeted. Never while just walking around.
	{
		"engaged",
		function()
			if not ns.API.InCombat() and not ns.API.Hostile() then
				return "only in combat or with an enemy targeted"
			end
		end,
	},
	-- An attackable target is needed, without making the spell range-checked
	-- (Stealth / Prowl are cast on yourself).
	{
		"enemyTarget",
		function()
			if not ns.API.Hostile() then
				return "only with an enemy targeted"
			end
		end,
	},
	-- At least one of these must be learned (e.g. an opener to use from Stealth).
	{
		"needKnownAny",
		function(c)
			for _, other in pairs(c.opt.needKnownAny) do
				if other and ns.API.Known(other) then
					return nil
				end
			end
			return "nothing to use it for yet"
		end,
	},
	{
		"nocreature",
		function(c)
			if ns.API.CreatureBlocked(c.opt.nocreature) then
				return "no effect on this creature type"
			end
		end,
	},
	{
		"creature",
		function(c)
			if not ns.API.CreatureMatch(c.opt.creature) then
				return "only for another creature type"
			end
		end,
	},
	{
		"totem",
		function(c)
			local refreshAt = tonumber(c.opt.refresh)
			if refreshAt == nil then
				refreshAt = 1
			end
			if ns.API.TotemRemain(c.id) > refreshAt then
				return "totem already up"
			end
		end,
	},
	{
		"enemiesMin",
		function(c)
			if (ns.API.EnemyCount(c.opt.enemiesYards) or 0) < c.opt.enemiesMin then
				return "not enough enemies near you"
			end
		end,
	},
	{
		"skipLow",
		function()
			if ns.API.Hostile() then
				local floorHp = ns.API.IsRaidmob() and 5 or 20
				if ns.API.Health("target") < floorHp then
					return "target is almost dead"
				end
			end
		end,
	},
	{
		"targetMana",
		function()
			local okCur, current = pcall(UnitPower, "target", 0)
			local okMax, maxp = pcall(UnitPowerMax, "target", 0)
			if not okCur or not readable(current) or current <= 0 then
				return "target has no mana"
			end
			if okMax and readable(maxp) and maxp <= 0 then
				return "target has no mana"
			end
		end,
	},
	{
		"ifTargeting",
		function()
			if ns.API.TargetAttacksYou() ~= true then
				return "only when the target attacks you"
			end
		end,
	},
	-- Backstab / Shred: only from behind. A mob faces whoever it attacks, so
	-- not while it attacks you; after a "must be behind" error, wait a moment.
	{
		"behind",
		function()
			if ns.API.NotBehindRecently() then
				return "you were not behind the target"
			end
			if ns.API.TargetAttacksYou() ~= false then
				return "the target is facing you"
			end
		end,
	},
	-- Cast-time spells a melee build only uses to pull. A spell ID as the value
	-- limits this to characters who already know that spell (melee shaman:
	-- Stormstrike); before that melee is weak and the shocks leave gaps.
	{
		"notMelee",
		function(c)
			local only = c.opt.notMelee
			if (only == true or ns.API.Known(only)) and ns.API.TargetInMelee() then
				return "not in melee range"
			end
		end,
	},
	-- Point-blank spells (Frost Nova): only once the target has reached you.
	{
		"inMelee",
		function()
			if not ns.API.TargetInMelee() then
				return "only when the target is in melee range"
			end
		end,
	},
	-- Replaced by a better spell once that one is learned (Imp -> Voidwalker).
	{
		"notKnown",
		function(c)
			if ns.API.Known(c.opt.notKnown) then
				return "a better spell is learned"
			end
		end,
	},
	-- Not for this talent tree (word in the name of the tree with the most points).
	{
		"notTree",
		function(c)
			local tree = ns.API.MainTree()
			if tree and tree:find(c.opt.notTree, 1, true) then
				return "not for your talent tree"
			end
		end,
	},
	{
		"swimming",
		function()
			local ok, swimming = pcall(IsSwimming)
			if not ok or safe(swimming, false) ~= true then
				return "only while swimming"
			end
		end,
	},
	-- Threat drops (Fade, Feint, Disengage) do nothing with nobody else around.
	{
		"inGroup",
		function(c)
			local ok, grouped = pcall(IsInGroup)
			grouped = ok and safe(grouped, false) == true
			if not grouped and not (c.opt.orPet and unitExists("pet")) then
				return "only in a group"
			end
		end,
	},
	{
		"petDead",
		function()
			if not ns.API.PetDead() then
				return "your pet is not dead"
			end
		end,
	},
	{
		"notPetDead",
		function()
			if ns.API.PetDead() then
				return "your pet is dead"
			end
		end,
	},
	-- Aura-first (ConROC-style): readable missing aura -> allow; up with remain
	-- above refresh -> block. stacks=N keeps applying until count reaches N.
	-- Hold is only a Forever fallback when auras lie.
	{
		"nobuff",
		function(c)
			local opt = c.opt
			local buffUnit = "player"
			if opt.heal then
				buffUnit = opt.unit or c.auraUnit
			end
			local found, remain, unreadable, _, stacks = ns.API.FindAura(c.id, buffUnit, "HELPFUL")
			if found then
				local needStacks = tonumber(opt.stacks)
				local refreshAt = tonumber(opt.refresh) or 0
				if needStacks and (stacks or 0) < needStacks then
					if ns.API.HoldRemain(c.id) > 0 then
						I.clearHoldKeys(c.id)
					end
				elseif remain >= 9000 or refreshAt <= 0 or remain > refreshAt then
					return "already active"
				end
			elseif not unreadable and ns.API.HoldRemain(c.id) > 0 then
				I.clearHoldKeys(c.id)
			end
			if not found and (unreadable or ns.API.InCombat()) and ns.API.HasAura(c.id, buffUnit, "HELPFUL") then
				return "already active"
			end
		end,
	},
	{
		"nodebuff",
		function(c)
			local opt = c.opt
			local debuff = opt.nodebuff == true and c.id or opt.nodebuff
			---@cast debuff integer
			-- Seals / buffs are "helpful" but judgement/DoT checks always use the enemy.
			local debuffUnit = opt.unit or ((c.helpful and opt.heal) and c.auraUnit or "target")
			local found, remain, unreadable, _, stacks = ns.API.FindAura(debuff, debuffUnit, "HARMFUL")
			if found then
				local needStacks = tonumber(opt.stacks)
				local refreshAt = tonumber(opt.refresh)
				if refreshAt == nil then
					refreshAt = 6
				end
				if needStacks and (stacks or 0) < needStacks then
					I.clearHoldKeys(c.id)
				elseif remain >= 9000 or refreshAt <= 0 or remain > refreshAt then
					return "already active"
				else
					I.clearHoldKeys(c.id)
				end
			elseif not unreadable then
				I.clearHoldKeys(c.id)
			elseif ns.API.HasAura(debuff, debuffUnit, "HARMFUL") then
				return "already active"
			end
		end,
	},
	-- Fillers are spammed by design: a hold (even one saved in a list)
	-- never holds them back.
	{
		nil,
		function(c)
			if c.opt.filler ~= true and ns.API.HoldRemain(c.id) > c.gate then
				return "waiting after the last cast (delay)"
			end
		end,
	},
	-- Health threshold: your own, the healed unit's, or the target's.
	{
		nil,
		function(c)
			local opt = c.opt
			local needHp = opt.hp
			if opt.hpPerCombo then
				needHp = ns.API.Combo() * opt.hpPerCombo
			end
			if opt.noHpGate then
				-- Health is hidden: the caller checks the threshold another way.
				needHp = nil
			elseif opt.heal or ns.API.IsHealSpell(c.id, opt) then
				needHp = ns.API.AutoHealThreshold(c.id, opt.unit or ns.API.HealUnit(opt), needHp or 99)
			end
			if needHp then
				local unit = opt.unit or ((c.helpful or opt.heal) and ns.API.HealUnit(opt)) or "player"
				if ns.API.Health(unit) > needHp then
					-- Health reads as 100 when the game hides it: say so, the
					-- coloured glow (BuildHidden*) follows the real value.
					if ns.API.HealthHiddenFor(unit) then
						return "health is hidden by the game (the coloured glow follows it)"
					end
					return "health is above the heal threshold"
				end
			end
		end,
	},
	{
		"form",
		function(c)
			if not ns.API.Form(c.opt.form) then
				return "wrong form or stance"
			end
		end,
	},
	{
		"noform",
		function(c)
			if ns.API.Form(c.opt.noform) then
				return "not in this form or stance"
			end
		end,
	},
	{
		"combat",
		function()
			if not ns.API.InCombat() then
				return "only in combat"
			end
		end,
	},
	{
		"comboMin",
		function(c)
			if ns.API.Combo() < c.opt.comboMin then
				local have, source = ns.API.ComboDebug()
				return ("not enough combo points (%d of %d, read from %s)"):format(have, c.opt.comboMin, source)
			end
		end,
	},
	{
		"pet",
		function()
			if not unitExists("pet") then
				return "needs your pet"
			end
		end,
	},
	{
		"nopet",
		function()
			if unitExists("pet") then
				return "pet is already out"
			end
		end,
	},
	-- tamedPet = only for a hunter who has a tamed pet (Call Pet is learned at
	-- level 1, before any pet is tamed).
	{
		"tamedPet",
		function()
			if not ns.API.HasTamedPet() then
				return "no tamed pet yet"
			end
		end,
	},
	{
		"nocombat",
		function()
			if ns.API.InCombat() then
				return "only out of combat"
			end
		end,
	},
	{
		"needbuff",
		function(c)
			if not ns.API.HasAura(c.opt.needbuff, "player", "HELPFUL") then
				return "needs a buff you do not have"
			end
		end,
	},
	{
		"needanybuff",
		function(c)
			for _, other in ipairs(c.opt.needanybuff) do
				if ns.API.HasAura(other, "player", "HELPFUL") then
					return nil
				end
			end
			return "needs a buff you do not have"
		end,
	},
	-- require / requireAny are NOT used to hide list spells. List order is
	-- authoritative: if the player put Frostbolt above Fireball, Frostbolt wins
	-- when it is known and ready. School gating lived here before and skipped
	-- fillers the player had explicitly ordered.
	{
		"needdebuff",
		function(c)
			if not ns.API.HasAura(c.opt.needdebuff, c.opt.unit or "target", "HARMFUL") then
				return "needs a debuff on the target first"
			end
		end,
	},
	{
		nil,
		function(c)
			if c.opt.proc or c.opt.usable then
				local usable = readUsable(C_Spell and C_Spell.IsSpellUsable, c.id)
				if usable ~= true then
					if c.opt.proc then
						return "waiting for its proc"
					end
					if ns.API.CastRemain() <= 0 then
						local last = ns.API.lastCastAt
						if not last or (GetTime() - last) >= 1.55 then
							return "not usable right now"
						end
					end
				end
			end
		end,
	},
	{
		"manaMax",
		function(c)
			if c.opt.noManaGate then
				return nil
			end
			local okCur, current = pcall(UnitPower, "player", 0)
			local okMax, maxp = pcall(UnitPowerMax, "player", 0)
			if not okCur or not okMax or not readable(current) or not readable(maxp) then
				-- Hidden in combat: ns.GlowHiddenMana shows it instead.
				return "mana is hidden right now"
			end
			if maxp <= 0 or (current / maxp) * 100 > c.opt.manaMax then
				return "mana is still high"
			end
		end,
	},
	{
		"hpMin",
		function(c)
			if ns.API.Health(c.opt.unit or "player") < c.opt.hpMin then
				return "health too low for it"
			end
		end,
	},
	{
		"anybuff",
		function(c)
			for _, other in ipairs(c.opt.anybuff) do
				if ns.API.HasAura(other, "player", "HELPFUL") then
					return "a buff from the same group is already up"
				end
			end
		end,
	},
	{
		"anydebuff",
		function(c)
			for _, other in ipairs(c.opt.anydebuff) do
				if ns.API.HasAura(other, c.opt.unit or "target", "HARMFUL") then
					return "a debuff from the same group is already on the target"
				end
			end
		end,
	},
	{
		nil,
		function(c)
			local remain = ns.API.Cooldown(c.id)
			if ns.API.CastingSpell(c.id) then
				remain = 0
			else
				local castLeft = ns.API.CastRemain()
				if castLeft > 0 and remain > 0 and remain <= castLeft + 0.45 then
					remain = 0
				end
			end
			if not c.opt.swing and remain > c.gate then
				return "on cooldown"
			end
		end,
	},
}

---Is this list step offered right now? Fills the WhyNot reason when not.
---@param spellID integer
---@param opt? KYR.StepOpt
---@param timeShift? number Look-ahead in seconds (at least 0.2).
---@return boolean
function ns.API.StepOk(spellID, opt, timeShift)
	spellID = ns.API.Resolve(spellID) or spellID
	if not spellID or not ns.API.Known(spellID) then
		return reject("not learned yet")
	end
	opt = opt or {}
	local c = {
		id = spellID,
		opt = opt,
		gate = math.max(tonumber(timeShift) or 0.2, 0.2),
		helpful = ns.API.IsHelpful(spellID, opt),
	}
	c.auraUnit = c.helpful and ns.API.HealUnit(opt) or "player"
	for _, check in ipairs(STEP_CHECKS) do
		local key = check[1]
		if key == nil or opt[key] then
			local why = check[2](c)
			if why then
				return reject(why)
			end
		end
	end
	if opt.ready == false then
		return true
	end
	if ns.Physics and ns.Physics.Blocks and ns.Physics.Blocks(spellID) then
		return reject("would clip Auto Shot")
	end
	if ns.API.Ready(spellID, opt, true) then
		return true
	end
	-- Fillers skip the strict "usable" test (the client says no during a cast
	-- or GCD), but not when it says you are out of mana: then the next step
	-- (the wand) takes over.
	if opt.filler == true or opt.swing == true then
		local _, noMana = readUsable(C_Spell and C_Spell.IsSpellUsable, spellID)
		if noMana ~= true then
			return true
		end
	end
	-- Certainly out of range is still a queue candidate for slots 2-3 (the
	-- client calls it unusable). An unknown range proves nothing: the spell
	-- may be unusable for another reason, such as the wrong stance.
	if hasResources(spellID) and ns.API.RangeState(spellID, opt) == "out" then
		return true
	end
	if ns.Physics and ns.Physics.EnergySoon and ns.Physics.EnergySoon(spellID) then
		return true
	end
	return reject("not usable right now (stance, rage / mana, or the client says no)")
end
