local wow = require("wow")
local H = require("helpers")

-- A warrior with a hostile target in melee, a few spells, and a list the
-- test controls through ns.GetAPL.
local function setup(extra)
	local w = wow.new()
	w:player("WARRIOR", { power = { [0] = 100, [1] = 100 }, powerMax = { [0] = 100, [1] = 100 } })
	w.spell(1, { name = "Filler", harmful = true, inRange = true })
	w.spell(2, { name = "Smash", harmful = true, inRange = true, baseCooldown = 6000 })
	w.spell(3, { name = "Far", harmful = true })
	w.spell(4, { name = "Rend", harmful = true, inRange = true })
	w.spell(5, { name = "Mend", helpful = true, desc = "Heal yourself for 40 to 40." })
	w.spell(6, { name = "Shout", helpful = true })
	if extra then
		extra(w)
	end
	w:target({ distance = 3 })
	w:load()
	w:fire("PLAYER_LOGIN")
	local ns = w.ns
	return w, ns
end

local function step(key, id, opt, on)
	return { key = key, id = id, opt = opt or {}, on = on ~= false }
end

local function useList(ns, list)
	ns.GetAPL = function()
		return list
	end
end

describe("Priest and a party member", function()
	it("offers the Shield and then the Renew for a selected friend whose health is hidden", function()
		local w = wow.new()
		w:player("PRIEST", { power = { [0] = 100 }, powerMax = { [0] = 100 } })
		w.spell(17, { name = "Power Word: Shield", helpful = true })
		w.spell(139, { name = "Renew", helpful = true })
		w.state.secret.health = true
		w.state.secret.healthPercent = true
		w:target({ hostile = false, reaction = 5, distance = 10, inParty = true })
		w:load()
		w:fire("PLAYER_LOGIN")
		local q = w.ns.BuildQueue()
		H.same({ q[1], q[2] }, { 17, 139 }, "Shield first, then Renew")
	end)
end)

describe("Rogue leveling", function()
	local function rogue(level, mobLevel)
		local w = wow.new()
		w:player("ROGUE", { power = { [3] = 100 }, powerMax = { [3] = 100 } })
		w.state.level = level
		local R = { SinisterStrike = 1752, Eviscerate = 2098 }
		w.spell(R.SinisterStrike, { name = "Sinister Strike", harmful = true, inRange = true })
		w.spell(R.Eviscerate, { name = "Eviscerate", harmful = true, inRange = true })
		w:target({ distance = 3, level = mobLevel })
		w:load()
		w:fire("PLAYER_LOGIN")
		w.state.combo = 2
		return w.ns, R, w
	end

	it("finishes a weak mob with Eviscerate from 2 combo points while leveling", function()
		local ns, R = rogue(5, 3)
		H.eq(ns.BuildQueue()[1], R.Eviscerate)
	end)

	it("waits for 3 points on a mob of your level, and 3 is enough", function()
		local ns, R, w = rogue(5, 5)
		H.eq(ns.BuildQueue()[1], R.SinisterStrike)
		w.state.combo = 3
		H.eq(ns.BuildQueue()[1], R.Eviscerate)
	end)

	it("keeps building points at 2 once past the leveling range", function()
		local ns, R = rogue(25, 20)
		H.eq(ns.BuildQueue()[1], R.SinisterStrike)
	end)
end)

describe("Rotation pull opener", function()
	it("opens with a cast-time attack at range out of combat, instants first in melee or in combat", function()
		local w, ns = setup(function(w)
			w.spell(10, { name = "Bolt", harmful = true, inRange = true, castTime = 2000 })
			w.spell(11, { name = "Shock", harmful = true, inRange = true })
		end)
		useList(ns, {
			step("Shock", 11, { hostile = true, nodebuff = true }),
			step("Bolt", 10, { filler = true, hostile = true }),
		})
		w.state.units.target.distance = 25
		H.eq(ns.API.CastTimeMs(10), 2000)
		H.eq(ns.API.CastTimeMs(11), 0)
		H.eq(ns.BuildQueue()[1], 10, "the pull: the cast while the mob runs in")
		w.state.units.player.combat = true
		H.eq(ns.BuildQueue()[1], 11, "in combat the list order")
		w.state.units.player.combat = false
		w.state.units.target.distance = 3
		H.eq(ns.BuildQueue()[1], 11, "in melee the instants")
		w.state.units.target.distance = 25
		ns.API.CastRemain = function()
			return 1.5
		end
		H.eq(ns.BuildQueue()[1] ~= 10, true, "while casting: what comes next")
	end)
end)

describe("Rotation queue", function()
	it("returns an empty queue without a list function", function()
		local _, ns = setup()
		ns.GetAPL = nil
		H.same(ns.BuildQueue(), {})
	end)

	it("lets a filler yield slot 1 to a ready action listed lower", function()
		local _, ns = setup()
		useList(ns, { step("Filler", 1, { filler = true }), step("Smash", 2) })
		local q = ns.BuildQueue()
		H.same(q, { 2, 1 })
		H.eq(ns.queueGlowOk, true)
	end)

	it("puts a confirmed in-range spell before one of unknown range", function()
		local _, ns = setup()
		useList(ns, { step("Far", 3), step("Rend", 4) })
		H.same(ns.BuildQueue(), { 4, 3 })
	end)

	it("falls back to unknown range, then to any range", function()
		local _, ns = setup()
		useList(ns, { step("Far", 3) })
		H.same(ns.BuildQueue(), { 3 }, "unknown range")
		ns.API.RangeState = function()
			return "out"
		end
		H.same(ns.BuildQueue(), { 3 }, "out of range still fills a slot")
		H.eq(ns.queueGlowOk, false, "but does not glow")
	end)

	it("skips disabled, weapon and maintenance spells", function()
		local _, ns = setup()
		useList(ns, {
			step("Off", 4, nil, false),
			step("Weapon", next(ns.WEAPON_BUFF_IDS)),
			step("Maint", ns.Spell.Warrior.BattleShout),
			step("NoId", nil),
			step("Filler", 1, { filler = true }),
		})
		H.same(ns.BuildQueue(), { 1 })
	end)

	it("shows a spell once, next-swing attacks included", function()
		local _, ns = setup()
		useList(ns, { step("Rend", 4), step("Rend2", 4), step("Swing", 1, { swing = true }) })
		local q = ns.BuildQueue()
		H.same(q, { 4, 1 })
	end)

	it("takes one spell per exclusive group", function()
		local _, ns = setup()
		local group = { 4, 1 }
		useList(ns, { step("A", 4, { anydebuff = group }), step("B", 1, { anydebuff = group }), step("C", 2) })
		H.same(ns.BuildQueue(), { 4, 2 })
	end)

	it("walks the list after a cast and wraps when it runs out", function()
		local _, ns = setup()
		useList(ns, { step("Rend", 4), step("Filler", 1, { filler = true }) })
		H.same(ns.BuildQueue(), { 4, 1 })
		ns.NoteRotationCast(4)
		H.same(ns.BuildQueue(), { 1, 4 }, "Rend spent: Filler first")
		ns.NoteRotationCast(1)
		H.same(ns.BuildQueue(), { 4, 1 }, "all spent: start over")
		ns.ClearRotationSpent()
		useList(ns, { step("NoId", nil), step("Rend", 4) })
		ns.NoteRotationCast(4)
		ns.NoteRotationCast(nil)
		ns.NoteRotationCast(999)
		ns.NoteRotationCast(4)
		ns.GetAPL = nil
		ns.NoteRotationCast(4)
	end)

	it("matches a cast to a step by resolved ID", function()
		local w, ns = setup(function(w)
			w.spell(7, { name = "Old", harmful = true, inRange = true, override = 8 })
			w.spell(8, { name = "New", harmful = true, inRange = true })
		end)
		useList(ns, { step("Old", 7), step("Filler", 1, { filler = true }) })
		ns.NoteRotationCast(8)
		H.same(ns.BuildQueue(), { 1, 8 })
		local _ = w
	end)

	it("never glows the spell being cast and looks past it", function()
		local w, ns = setup()
		useList(ns, { step("Rend", 4), step("Smash", 2), step("Swing", 1, { swing = true }) })
		w.state.units.player.casting = { name = "Rend", endTime = (w.state.time + 1.5) * 1000 }
		local q = ns.BuildQueue()
		H.eq(q[1], 2, "next after the cast")
		w.state.units.player.casting = { name = "Filler", endTime = (w.state.time + 1.5) * 1000 }
		H.eq(ns.BuildQueue()[1], 4)
	end)

	it("moves a needed heal to slot 1", function()
		local w, ns = setup()
		ns.db.autoHeal = false
		useList(ns, { step("Rend", 4), step("Smash", 2), step("Mend", 5, { heal = true, hp = 80 }) })
		H.same(ns.BuildQueue(), { 4, 2 }, "full health: no heal")
		w.state.units.player.health = 50
		local q = ns.BuildQueue()
		H.eq(q[1], 5, "heal first")
		H.truthy(ns.queueHeal[5])
		useList(ns, { step("Mend", 5, { heal = true, hp = 80 }), step("Rend", 4) })
		H.eq(ns.BuildQueue()[1], 5, "already first")
		w.state.units.player.casting = { name = "Mend", endTime = (w.state.time + 2) * 1000 }
		useList(ns, { step("Rend", 4), step("Mend", 5, { heal = true, hp = 80 }) })
		H.eq(ns.BuildQueue()[1], 4, "the heal being cast is not pushed again")
	end)

	it("keeps the heal it moves within three slots", function()
		local w, ns = setup()
		ns.db.autoHeal = false
		w.spell(9, { name = "Strike", harmful = true, inRange = true, baseCooldown = 4000 })
		useList(ns, {
			step("Rend", 4),
			step("Smash", 2),
			step("Strike", 9),
			step("Mend", 5, { heal = true, hp = 80 }),
		})
		w.state.units.player.health = 50
		local q = ns.BuildQueue()
		H.eq(#q, 3)
		H.eq(q[1], 5)
	end)

	it("survives an error while filling the slots", function()
		local _, ns = setup()
		useList(ns, { step("Rend", 4) })
		ns.API.StepOk = function()
			error("boom")
		end
		H.same(ns.BuildQueue(), {})
		H.eq(ns.queueGlowOk, false)
	end)

	it("does not glow slot 1 when the spell is not ready", function()
		local w, ns = setup()
		useList(ns, { step("Rend", 4) })
		w.state.spells[4].usable = false
		ns.API.StepOk = function()
			return true
		end
		H.same(ns.BuildQueue(), { 4 })
		H.eq(ns.queueGlowOk, false)
	end)

	it("respects a role-bound step", function()
		local _, ns = setup()
		ns.db.role = "damage"
		ns.GetDef = function()
			return { step("Tank", 6, { role = "tank" }), step("Shout", 6) }
		end
		H.eq(ns.BuildDefense(), 6)
		ns.db.role = nil
		ns.GetDef = function()
			return { step("Tank", 6, { role = "tank" }) }
		end
		H.eq(ns.BuildDefense(), nil)
	end)
end)

describe("Maintenance and weapon buff names", function()
	it("recognises buffs by ID and by name, with caches", function()
		local w, ns = setup(function(w)
			w.spell(90001, { name = "Battle Shout" })
			w.spell(90002, { name = "Rockbiter Weapon" })
		end)
		w.spell(ns.Spell.Warrior.BattleShout, { name = "Battle Shout" })
		w.spell(8017, { name = "Rockbiter Weapon" })
		H.eq(ns.IsMaintenanceBuff(nil), false)
		H.eq(ns.IsMaintenanceBuff(ns.Spell.Warrior.BattleShout), true)
		ns.InvalidateBuffCaches()
		H.eq(ns.IsMaintenanceBuff(90001), true, "same name")
		H.eq(ns.IsMaintenanceBuff(90001), true, "cached names")
		H.eq(ns.IsMaintenanceBuff(424242), false)
		H.eq(ns.IsWeaponBuff(nil), false)
		H.eq(ns.IsWeaponBuff(wow.SECRET), false)
		H.eq(ns.IsWeaponBuff(8017), true)
		H.eq(ns.IsWeaponBuff(90002), true, "same name")
		H.eq(ns.IsWeaponBuff(90002), true, "cached")
		H.eq(ns.IsWeaponBuff(424242), false)
		ns.API.WipeAuraScans = nil
		ns.InvalidateBuffCaches()
	end)
end)

describe("Hidden-value cues", function()
	it("picks a heal or own-health step while health is hidden", function()
		local w, ns = setup()
		ns.db.autoHeal = false
		useList(ns, {
			step("Rend", 4),
			step("Weapon", next(ns.WEAPON_BUFF_IDS), { heal = true }),
			step("Mend", 5, { heal = true, hp = 60 }),
		})
		H.eq(ns.BuildHiddenHeal(), nil, "health readable")
		w.state.secret.health = true
		w.state.secret.healthPercent = true
		H.same({ ns.BuildHiddenHeal() }, { 5, 60 })
		useList(ns, { step("Drain", 4, { hp = 40 }) })
		H.same({ ns.BuildHiddenHeal() }, { 4, 40 })
		useList(ns, { step("Mend", 5, { heal = true }) })
		H.same({ ns.BuildHiddenHeal() }, { 5, 80 })
		w.state.units.player.casting = { name = "Mend", endTime = (w.state.time + 1) * 1000 }
		H.eq(ns.BuildHiddenHeal(), nil, "already casting it")
		ns.GetAPL = nil
		H.eq(ns.BuildHiddenHeal(), nil)
	end)

	it("picks a finisher while target health is hidden", function()
		local w, ns = setup()
		useList(ns, {
			step("Rend", 4),
			step("Exec", 4, { hp = 20, unit = "target" }),
			step("Evis", 2, { hpPerCombo = 8, unit = "target" }),
		})
		H.eq(ns.BuildHiddenExecute(), nil, "readable")
		w.state.secret.healthPercent = true
		w.state.secret.health = true
		H.same({ ns.BuildHiddenExecute() }, { 4, 20 })
		useList(ns, { step("Evis", 2, { hpPerCombo = 8, unit = "target" }) })
		H.eq(ns.BuildHiddenExecute(), nil, "0 combo points: no threshold")
		w.state.combo = 3
		H.same({ ns.BuildHiddenExecute() }, { 2, 24 })
		useList(ns, { step("Exec", 4, { hp = "x", unit = "target" }) })
		H.same({ ns.BuildHiddenExecute() }, { 4, 20 }, "default 20 %")
		w.state.units.target = nil
		H.eq(ns.BuildHiddenExecute(), nil, "no enemy")
	end)

	it("picks Mend Pet while pet health is hidden", function()
		local w, ns = setup()
		useList(ns, { step("Rend", 4), step("MendPet", 6, { unit = "pet", hp = 40 }) })
		H.eq(ns.BuildHiddenPet(), nil, "no pet")
		w.unit("pet", { health = 50, maxHealth = 100 })
		H.eq(ns.BuildHiddenPet(), nil, "readable")
		w.state.secret.health = true
		w.state.secret.healthPercent = true
		H.same({ ns.BuildHiddenPet() }, { 6, 40 })
		useList(ns, { step("MendPet", 6, { unit = "pet", hp = "x" }) })
		H.same({ ns.BuildHiddenPet() }, { 6, 40 })
		w.state.units.player.casting = { name = "Shout", endTime = (w.state.time + 1) * 1000 }
		H.eq(ns.BuildHiddenPet(), nil, "already casting it")
	end)

	it("picks Life Tap while mana is hidden", function()
		local w, ns = setup()
		useList(ns, { step("Rend", 4), step("Tap", 6, { manaMax = 20 }) })
		H.eq(ns.BuildHiddenMana(), nil, "readable")
		w.state.secret.power = true
		H.same({ ns.BuildHiddenMana() }, { 6, 20 })
		ns.API.StepOk = function()
			return false
		end
		H.eq(ns.BuildHiddenMana(), nil)
	end)

	it("picks a health defensive while health is hidden", function()
		local w, ns = setup()
		ns.db.autoHeal = false
		ns.GetDef = function()
			return {
				step("Shout", 6),
				step("Wall", 2, { hp = 25 }),
				step("Shield", 5, { hp = 70, heal = true }),
			}
		end
		H.eq(ns.BuildHiddenDefense(), nil, "readable")
		w.state.secret.health = true
		w.state.secret.healthPercent = true
		H.same({ ns.BuildHiddenDefense() }, { 2, 25 })
		ns.GetDef = function()
			return { step("Wall", 2, { hp = "x" }), step("Shield", 5, { hp = 70, heal = true }) }
		end
		H.same({ ns.BuildHiddenDefense() }, { 2, 50 })
		w.state.spells[2].cooldown = { w.state.time, 60 }
		H.same({ ns.BuildHiddenDefense() }, { 5, 70 }, "heal threshold")
		w.state.spells[5].cooldown = { w.state.time, 60 }
		H.eq(ns.BuildHiddenDefense(), nil, "nothing ready")
		ns.GetDef = nil
		H.eq(ns.BuildHiddenDefense(), nil)
	end)
end)

describe("Defense, interrupt, purge and cleanse cues", function()
	it("puts health defensives before buffs", function()
		local w, ns = setup()
		ns.GetDef = function()
			return { step("Shout", 6, { nobuff = true }), step("Wall", 2, { combat = true, hp = 30 }) }
		end
		H.eq(ns.BuildDefense(), 6, "buff when nothing is urgent")
		w.state.units.player.combat = true
		w.state.units.player.health = 20
		H.eq(ns.BuildDefense(), 2)
		ns.GetDef = nil
		H.eq(ns.BuildDefense(), nil)
	end)

	it("skips a defense step whose spell is on no action button", function()
		local w, ns = setup()
		ns.GetDef = function()
			return { step("Shout", 6, { nobuff = true }), step("Mend", 5, { nobuff = true }) }
		end
		H.eq(ns.BuildDefense(), 6, "no bars scanned: the first step stays")
		local b = w.env.CreateFrame("CheckButton", "ActionButton1")
		b.action = 1
		w.state.actions[1] = { type = "spell", id = 5 }
		ns.GlowFetch(true)
		H.eq(ns.BuildDefense(), 5, "the one on the bar glows")
	end)

	it("interrupts an interruptible cast in reach", function()
		local w, ns = setup(function(w)
			w.spell(6552, { name = "Pummel", harmful = true, inRange = true })
		end)
		H.eq(ns.BuildInterrupt(), nil, "not casting")
		w.state.units.target.casting = { name = "Fireball" }
		H.eq(ns.BuildInterrupt(), 6552)
		w.state.spells[6552].inRange = false
		w.state.units.target.distance = 30
		H.eq(ns.BuildInterrupt(), nil, "out of range")
		w.state.class = "MAGE"
		H.eq(ns.BuildInterrupt(), nil, "no interrupt known")
	end)

	it("purges a magic buff in reach", function()
		local w, ns = setup(function(w)
			w.spell(370, { name = "Purge", harmful = true, inRange = true })
		end)
		w.state.class = "SHAMAN"
		H.eq(ns.BuildPurge(), nil, "nothing to purge")
		w.aura("target", { name = "Shield", spellId = 1, dispelName = "Magic" })
		H.eq(ns.BuildPurge(), 370)
		w.state.spells[370].inRange = false
		w.state.units.target.distance = 40
		H.eq(ns.BuildPurge(), nil, "out of range")
		w.state.units.target = nil
		H.eq(ns.BuildPurge(), nil, "no enemy")
		w.state.class = "WARRIOR"
		H.eq(ns.BuildPurge(), nil)
	end)

	it("cleanses you and, if allowed, the group", function()
		local w, ns = setup(function(w)
			w.spell(4987, { name = "Cleanse", helpful = true })
		end)
		w.state.class = "PALADIN"
		H.eq(ns.BuildCleanse(), nil)
		w.unit("party1", { health = 1, maxHealth = 1, reaction = 5 })
		w.aura("party1", { name = "Poison", spellId = 1, harmful = true, dispelName = "Poison" })
		H.eq(ns.BuildCleanse(), 4987, "party member")
		ns.db.cleanseGroup = false
		H.eq(ns.BuildCleanse(), nil, "only yourself")
		w.aura("player", { name = "Poison", spellId = 1, harmful = true, dispelName = "Poison" })
		H.eq(ns.BuildCleanse(), 4987)
		w.state.class = "WARRIOR"
		H.eq(ns.BuildCleanse(), nil)
	end)
end)
