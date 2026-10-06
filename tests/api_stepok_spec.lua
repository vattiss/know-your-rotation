local wow = require("wow")
local H = require("helpers")

local CORE = { "Locale.lua", "API.lua", "Data.lua" }

-- A level-10 warrior with a hostile target and a few spells.
local function setup(extra)
	local w = wow.new()
	w:player("WARRIOR", { power = { [0] = 100, [1] = 100 }, powerMax = { [0] = 100, [1] = 100 } })
	w.spell(1, { name = "Strike", harmful = true })
	w.spell(2, { name = "Buff", helpful = true })
	w.spell(3, { name = "Debuff", harmful = true })
	w.spell(4, { name = "Other" })
	w.spell(5, { name = "Unlearned", known = false, inBook = false })
	w.spell(6, { name = "Heal", helpful = true, desc = "Heals for 30 to 40." })
	if extra then
		extra(w)
	end
	w:target()
	local ns = w:load(CORE)
	return w, ns, ns.API
end

-- StepOk and its reason in one call.
local function check(A, id, opt, wantOk, wantReason)
	local ok = A.StepOk(id, opt)
	H.eq(ok, wantOk, wantReason or "StepOk")
	local why = A.WhyNot(id, opt)
	if wantOk then
		H.eq(why, nil)
	elseif wantReason then
		H.truthy(why and why:find(wantReason, 1, true), ("reason %q, got %q"):format(wantReason, tostring(why)))
	end
end

describe("StepOk basics", function()
	it("needs a learned spell and an enemy for hostile steps", function()
		local w, _, A = setup()
		check(A, nil, nil, false, "not learned")
		check(A, 5, nil, false, "not learned yet")
		check(A, 1, { hostile = true }, true)
		H.eq(A.StepOk(1, {}, 0.05), true, "a short look-ahead is raised to 0.2 s")
		w.state.units.target.hostile = false
		w.state.units.target.reaction = 5
		check(A, 1, { hostile = true }, false, "needs an enemy target")
		w.state.units.target.reaction = nil
		w.env.UnitReaction = function()
			return wow.SECRET
		end
		check(A, 1, { hostile = true }, true)
		w.state.units.target.dead = true
		check(A, 1, { hostile = true }, false, "needs an enemy target")
		w.state.units.target = nil
		check(A, 1, { hostile = true }, false, "needs an enemy target")
		H.eq(A.WhyNot(1, { ready = false }), nil)
	end)

	it("gates by level", function()
		local w, _, A = setup()
		check(A, 1, { minLevel = 10 }, true)
		check(A, 1, { minLevel = 11 }, false, "from level 11")
		w.state.level = wow.SECRET
		check(A, 1, { minLevel = 11 }, true)
		w.env.UnitLevel = function()
			error("boom")
		end
		check(A, 1, { minLevel = 11 }, true)
	end)

	it("offers auto-repeat only while it is off", function()
		local w, _, A = setup()
		check(A, 1, { autoRepeat = true }, true)
		w.state.spells[1].repeating = true
		check(A, 1, { autoRepeat = true }, false, "already on")
		w.env.C_Spell.IsAutoRepeatSpell = function()
			return false
		end
		check(A, 1, { autoRepeat = true }, false, "already on")
		w.env.IsAutoRepeatSpell = nil
		check(A, 1, { autoRepeat = true }, true)
		w.env.C_Spell.IsAutoRepeatSpell = nil
		check(A, 1, { autoRepeat = true }, true)
	end)

	it("handles engaged, enemy target and needed spells", function()
		local w, _, A = setup()
		check(A, 2, { engaged = true }, true)
		check(A, 2, { enemyTarget = true }, true)
		check(A, 2, { needKnownAny = { 5, 4 } }, true)
		check(A, 2, { needKnownAny = { 5 } }, false, "nothing to use it for yet")
		w.state.units.target = nil
		check(A, 2, { engaged = true }, false, "only in combat")
		check(A, 2, { enemyTarget = true }, false, "only with an enemy targeted")
		w.state.units.player.combat = true
		check(A, 2, { engaged = true }, true)
	end)

	it("checks creature types", function()
		local w, _, A = setup()
		w.state.units.target.creatureType = "Elemental"
		check(A, 1, { nocreature = true }, false, "no effect on this creature type")
		check(A, 1, { creature = { "undead", "demon" } }, false, "only for another creature type")
		w.state.units.target.creatureType = "Undead"
		check(A, 1, { creature = { "undead", "demon" } }, true)
		check(A, 1, { nocreature = true }, true)
	end)

	it("offers a totem when it is not down", function()
		local w, ns, A = setup()
		local remain = 0
		ns.API.TotemRemain = function()
			return remain
		end
		check(A, 2, { totem = true }, true)
		remain = 0.5
		check(A, 2, { totem = true }, true, "within the default 1 s")
		remain = 5
		check(A, 2, { totem = true }, false, "totem already up")
		check(A, 2, { totem = true, refresh = 6 }, true)
		ns.API.TotemRemain = nil
		check(A, 2, { totem = true }, true)
		local _ = w
	end)

	it("needs enough enemies", function()
		local _, ns, A = setup()
		local n = 1
		ns.API.EnemyCount = function()
			return n
		end
		check(A, 1, { enemiesMin = 2 }, false, "not enough enemies")
		n = nil
		check(A, 1, { enemiesMin = 2 }, false, "not enough enemies")
		n = 3
		check(A, 1, { enemiesMin = 2, enemiesYards = 8 }, true)
	end)

	it("skips low targets, more for elites", function()
		local w, _, A = setup()
		w.state.units.target.health = 15
		check(A, 1, { skipLow = true }, false, "target is almost dead")
		w.state.units.target.classification = "elite"
		check(A, 1, { skipLow = true }, true, "elite: only below 5 %")
		w.state.units.target = nil
		check(A, 1, { skipLow = true }, true)
	end)

	it("needs a target with mana", function()
		local w, _, A = setup()
		w.state.units.target.power = { [0] = 0 }
		check(A, 1, { targetMana = true }, false, "target has no mana")
		w.state.units.target.power = { [0] = 50 }
		w.state.units.target.powerMax = { [0] = 0 }
		check(A, 1, { targetMana = true }, false, "target has no mana")
		w.state.units.target.powerMax = { [0] = 100 }
		check(A, 1, { targetMana = true }, true)
		w.state.secret.power = true
		check(A, 1, { targetMana = true }, false, "target has no mana")
	end)

	it("checks who the target attacks, and being behind", function()
		local w, ns, A = setup()
		local attacks
		ns.API.TargetAttacksYou = function()
			return attacks
		end
		attacks = true
		check(A, 1, { ifTargeting = true }, true)
		check(A, 1, { behind = true }, false, "the target is facing you")
		attacks = nil
		check(A, 1, { ifTargeting = true }, false, "only when the target attacks you")
		check(A, 1, { behind = true }, false, "the target is facing you")
		attacks = false
		check(A, 1, { behind = true }, true)
		ns.API.NoteUIError("You must be behind your target.")
		check(A, 1, { behind = true }, false, "you were not behind")
		local _ = w
	end)

	it("checks melee range both ways", function()
		local _, ns, A = setup()
		local melee = true
		ns.API.TargetInMelee = function()
			return melee
		end
		check(A, 1, { notMelee = true }, false, "not in melee range")
		check(A, 1, { inMelee = true }, true)
		melee = false
		check(A, 1, { notMelee = true }, true)
		check(A, 1, { inMelee = true }, false, "only when the target is in melee range")
	end)

	it("checks better spells, talent trees, swimming and groups", function()
		local w, ns, A = setup()
		check(A, 1, { notKnown = 4 }, false, "a better spell is learned")
		check(A, 1, { notKnown = 5 }, true)
		local tree
		ns.API.MainTree = function()
			return tree
		end
		check(A, 1, { notTree = "fire" }, true)
		tree = "fire"
		check(A, 1, { notTree = "fire" }, false, "not for your talent tree")
		tree = "frost"
		check(A, 1, { notTree = "fire" }, true)
		check(A, 1, { swimming = true }, false, "only while swimming")
		w.state.swimming = true
		check(A, 1, { swimming = true }, true)
		w.env.IsSwimming = function()
			error("boom")
		end
		check(A, 1, { swimming = true }, false, "only while swimming")
		check(A, 1, { inGroup = true }, false, "only in a group")
		w.unit("pet", { health = 1, maxHealth = 1 })
		check(A, 1, { inGroup = true, orPet = true }, true)
		check(A, 1, { inGroup = true }, false, "only in a group")
		w.state.group = true
		check(A, 1, { inGroup = true }, true)
		w.env.IsInGroup = function()
			error("boom")
		end
		check(A, 1, { inGroup = true }, false, "only in a group")
	end)

	it("checks the hunter pet state", function()
		local _, ns, A = setup()
		local dead = false
		ns.API.PetDead = function()
			return dead
		end
		check(A, 1, { petDead = true }, false, "your pet is not dead")
		check(A, 1, { notPetDead = true }, true)
		dead = true
		check(A, 1, { petDead = true }, true)
		check(A, 1, { notPetDead = true }, false, "your pet is dead")
	end)
end)

describe("StepOk auras", function()
	it("nobuff: readable aura, stacks, refresh and memory", function()
		local w, ns, A = setup()
		check(A, 2, { nobuff = true }, true)
		local aura = w.aura("player", { name = "Buff", spellId = 2, expirationTime = w.state.time + 30 })
		check(A, 2, { nobuff = true }, false, "already active")
		check(A, 2, { nobuff = true, refresh = 40 }, true, "refresh window")
		aura.applications = 2
		check(A, 2, { nobuff = true, stacks = 3 }, true, "needs more stacks")
		ns.SPELL_HOLD[2] = 10
		A.NoteSpellCast(2)
		check(A, 2, { nobuff = true, stacks = 3 }, true, "stacks clear the hold")
		aura.applications = 3
		check(A, 2, { nobuff = true, stacks = 3 }, false, "already active")
		w.state.auras.player = {}
		A.NoteSpellCast(2)
		check(A, 2, { nobuff = true }, true, "readable absence clears the hold")
		check(A, 2, { nobuff = true }, true)
	end)

	it("nobuff: hidden auras and combat trust the remembered buff", function()
		local w, ns, A = setup()
		ns.SPELL_HOLD[2] = 0
		A.NoteSelfBuff(2)
		w.state.secret.auras = true
		check(A, 2, { nobuff = true }, false, "already active")
		w.state.secret.auras = false
		w.state.units.player.combat = true
		check(A, 2, { nobuff = true }, false, "already active")
	end)

	it("nobuff on a heal reads the healed unit", function()
		local w, _, A = setup()
		w.unit("target", { health = 10, maxHealth = 100, reaction = 5 })
		w.state.units.player.health = 10
		w.aura("target", { name = "Heal", spellId = 6, expirationTime = w.state.time + 10 })
		check(A, 6, { heal = true, nobuff = true }, false, "already active")
		check(A, 6, { heal = true, nobuff = true, unit = "player" }, true)
	end)

	it("nodebuff: readable debuffs, stacks, refresh, other IDs", function()
		local w, ns, A = setup()
		check(A, 3, { nodebuff = true }, true)
		local d = w.aura("target", { name = "Debuff", spellId = 3, harmful = true, expirationTime = w.state.time + 20 })
		check(A, 3, { nodebuff = true }, false, "already active")
		d.expirationTime = w.state.time + 5
		check(A, 3, { nodebuff = true }, true, "default 6 s refresh")
		check(A, 3, { nodebuff = true, refresh = 0 }, false, "already active")
		d.applications = 1
		check(A, 3, { nodebuff = true, stacks = 5 }, true, "stacking")
		check(A, 1, { nodebuff = 3, refresh = 0 }, false, "already active")
		w.state.auras.target = {}
		ns.SPELL_HOLD[3] = 10
		A.NoteSpellCast(3)
		check(A, 3, { nodebuff = true }, true, "readable absence clears the hold")
	end)

	it("nodebuff: hidden debuffs trust the cast memory", function()
		local w, _, A = setup()
		A.NoteTargetDebuff(3)
		w.aura("target", { name = "Debuff", spellId = 3, harmful = true })
		w.state.secret.auras = true
		check(A, 3, { nodebuff = true }, false, "already active")
		A.ClearTargetDebuffs()
		check(A, 3, { nodebuff = true }, true)
	end)

	it("waits for a hold", function()
		local w, ns, A = setup()
		ns.SPELL_HOLD[1] = 5
		A.NoteSpellCast(1)
		check(A, 1, {}, false, "waiting after the last cast")
		check(A, 1, { filler = true }, true, "fillers ignore holds")
		local _ = w
	end)
end)

describe("StepOk health", function()
	it("compares own, target and heal health", function()
		local w, ns, A = setup()
		w.state.units.player.health = 80
		check(A, 1, { hp = 70 }, false, "health is above")
		check(A, 1, { hp = 90 }, true)
		w.state.units.target.health = 30
		check(A, 1, { hp = 20, unit = "target" }, false, "health is above")
		w.state.units.target.health = 10
		check(A, 1, { hp = 20, unit = "target" }, true)
		check(A, 1, { hp = 20, noHpGate = true }, true, "hidden-health glow decides")
		ns.db = { autoHeal = false }
		w.state.units.player.health = 95
		check(A, 6, { heal = true }, true, "implicit 99 % threshold")
		w.state.units.player.health = 100
		check(A, 6, { heal = true }, false, "health is above")
		ns.HEAL_SPELL_IDS[6] = true
		w.state.units.player.health = 70
		check(A, 6, { hp = 80 }, true, "heal by ID")
	end)

	it("scales a finisher threshold by combo points", function()
		local w, ns, A = setup()
		ns.API.Combo = function()
			return 3
		end
		w.state.units.target.health = 30
		check(A, 1, { hpPerCombo = 8, unit = "target" }, false, "health is above")
		w.state.units.target.health = 20
		check(A, 1, { hpPerCombo = 8, unit = "target" }, true)
	end)
end)

describe("StepOk state", function()
	it("checks forms, combat, combo points and pets", function()
		local w, ns, A = setup()
		local form = false
		ns.API.Form = function()
			return form
		end
		check(A, 1, { form = 9 }, false, "wrong form")
		check(A, 1, { noform = 9 }, true)
		form = true
		check(A, 1, { form = 9 }, true)
		check(A, 1, { noform = 9 }, false, "not in this form")
		check(A, 1, { combat = true }, false, "only in combat")
		check(A, 1, { nocombat = true }, true)
		w.state.units.player.combat = true
		check(A, 1, { combat = true }, true)
		check(A, 1, { nocombat = true }, false, "only out of combat")
		check(A, 1, { comboMin = 2 }, false, "not enough combo points (0 of 2")
		w.state.combo = 2
		check(A, 1, { comboMin = 2 }, true)
		check(A, 1, { pet = true }, false, "needs your pet")
		check(A, 1, { nopet = true }, true)
		w.unit("pet", { health = 1, maxHealth = 1 })
		check(A, 1, { pet = true }, true)
		check(A, 1, { nopet = true }, false, "pet is already out")
	end)

	it("checks needed buffs and debuffs", function()
		local w, _, A = setup()
		check(A, 1, { needbuff = 2 }, false, "needs a buff")
		check(A, 1, { needanybuff = { 2, 4 } }, false, "needs a buff")
		check(A, 1, { needdebuff = 3 }, false, "needs a debuff")
		w.aura("player", { name = "Other", spellId = 4 })
		w.aura("target", { name = "Debuff", spellId = 3, harmful = true })
		check(A, 1, { needanybuff = { 2, 4 } }, true)
		check(A, 1, { needdebuff = 3 }, true)
		check(A, 1, { anybuff = { 4 } }, false, "a buff from the same group")
		check(A, 1, { anydebuff = { 3 } }, false, "a debuff from the same group")
		check(A, 1, { anybuff = { 2 }, anydebuff = { 5 } }, true)
	end)

	it("waits for procs and usable spells", function()
		local w, ns, A = setup()
		check(A, 1, { proc = true }, true)
		w.state.spells[1].usable = false
		check(A, 1, { proc = true }, false, "waiting for its proc")
		check(A, 1, { usable = true }, false, "not usable right now")
		ns.API.lastCastAt = w.state.time
		check(A, 1, { usable = true }, true, "inside the GCD the client says no to everything")
		w.state.units.player.casting = { name = "X", endTime = (w.state.time + 1) * 1000 }
		H.eq(A.StepOk(1, { usable = true, ready = false }), true, "during a cast")
	end)

	it("checks mana for Life Tap", function()
		local w, _, A = setup()
		check(A, 1, { manaMax = 20 }, false, "mana is still high")
		w.state.units.player.power[0] = 10
		check(A, 1, { manaMax = 20 }, true)
		w.state.units.player.powerMax[0] = 0
		check(A, 1, { manaMax = 20 }, false, "mana is still high")
		w.state.secret.power = true
		check(A, 1, { manaMax = 20 }, false, "mana is hidden")
		check(A, 1, { manaMax = 20, noManaGate = true }, true)
	end)

	it("needs enough own health", function()
		local w, _, A = setup()
		w.state.units.player.health = 30
		check(A, 1, { hpMin = 40 }, false, "health too low")
		check(A, 1, { hpMin = 20, unit = "player" }, true)
	end)
end)

describe("StepOk cooldown and readiness", function()
	it("rejects a cooldown unless it ends with the current cast", function()
		local w, _, A = setup()
		w.state.spells[1].cooldown = { w.state.time, 5 }
		check(A, 1, {}, false, "on cooldown")
		check(A, 1, { swing = true }, true, "next-swing attacks skip it")
		w.state.units.player.casting = { name = "Other", endTime = (w.state.time + 4.8) * 1000 }
		check(A, 1, {}, true, "cooldown ends with the cast")
		w.state.units.player.casting = { name = "Strike", endTime = (w.state.time + 1) * 1000 }
		check(A, 1, {}, true, "casting this spell now")
		check(A, 1, { ready = false }, true)
	end)

	it("holds a shot that would clip Auto Shot", function()
		local _, ns, A = setup()
		ns.Physics = {
			Blocks = function()
				return true
			end,
		}
		check(A, 1, {}, false, "would clip Auto Shot")
	end)

	it("lets fillers and reachable-later spells through", function()
		local w, ns, A = setup()
		w.state.spells[1].usable = false
		check(A, 1, { filler = true }, true)
		w.state.spells[1].noMana = true
		ns.API.RangeState = function()
			return "in"
		end
		check(A, 1, { filler = true }, false, "not usable right now (stance")
		w.state.spells[1].noMana = false
		ns.API.RangeState = function()
			return "out"
		end
		check(A, 1, {}, true, "out of range: still a queue candidate")
		ns.API.RangeState = function()
			return "in"
		end
		ns.Physics = {
			EnergySoon = function()
				return true
			end,
		}
		check(A, 1, {}, true, "energy arrives soon")
		ns.Physics = nil
		check(A, 1, {}, false, "not usable right now (stance")
	end)
end)
