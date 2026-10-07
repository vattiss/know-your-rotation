local wow = require("wow")
local H = require("helpers")

local CORE = wow.API_FILES

local function api(setup)
	local w = wow.new()
	w:player("WARRIOR")
	if setup then
		setup(w)
	end
	local ns = w:load(CORE)
	return w, ns, ns.API
end

local function plate(w, i, data)
	data.hostile = data.hostile ~= false
	return w.unit("nameplate" .. i, data)
end

describe("API.EnemyCount", function()
	it("counts every hostile plate out of combat, cached for a moment", function()
		local w, _, A = api()
		plate(w, 1, {})
		plate(w, 2, { dead = true })
		plate(w, 3, { hostile = false, reaction = 3 })
		plate(w, 4, { hostile = false, reaction = 5 })
		H.eq(A.EnemyCount(), 2)
		plate(w, 5, {})
		H.eq(A.EnemyCount(), 2, "cached")
		w:advance(1)
		H.eq(A.EnemyCount(), 3)
	end)

	it("in combat counts only enemies fighting you or your pet", function()
		local w, _, A = api()
		w.state.units.player.combat = true
		w.unit("pet", { health = 1, maxHealth = 1 })
		plate(w, 1, { threat = 0 })
		plate(w, 2, {})
		w.state.units.nameplate2target = w.state.units.pet
		plate(w, 3, { combat = true })
		plate(w, 4, {})
		H.eq(A.EnemyCount(), 2, "on your threat table, or on your pet")
		w:advance(1)
		w.state.secret.threat = true
		H.eq(A.EnemyCount(), 2, "threat hidden: on your pet, or in combat")
		w:advance(1)
		w.state.secret.compare = true
		H.eq(A.EnemyCount(), 1, "only the plate in combat")
	end)

	it("filters by yards with distance, interact checks and the target fallback", function()
		local w, _, A = api()
		plate(w, 1, { distance = 5 })
		plate(w, 2, { distance = 20 })
		plate(w, 3, { distance = 40 })
		H.eq(A.EnemyCount(10), 1)
		w:advance(1)
		H.eq(A.EnemyCount(25), 2)
		w:advance(1)
		H.eq(A.EnemyCount(40), 3)
		w:advance(1)
		for i = 1, 3 do
			w.state.units["nameplate" .. i] = nil
		end
		w:target({ distance = 3 })
		H.eq(A.EnemyCount(8), 1, "no plates: the target")
	end)

	it("uses interact distances when the client cannot measure", function()
		local w, _, A = api()
		plate(w, 1, {})
		local answers = {}
		w.env.CheckInteractDistance = function(_, index)
			return answers[index]
		end
		answers = { [3] = wow.SECRET_BOOL, [2] = 1 }
		H.eq(A.EnemyCount(10), 1, "trade range")
		w:advance(1)
		answers = { [1] = true }
		H.eq(A.EnemyCount(20), 1, "inspect range")
		w:advance(1)
		answers = { [1] = 0 }
		H.eq(A.EnemyCount(20), 0)
		w:advance(1)
		w.env.CheckInteractDistance = function()
			error("boom")
		end
		H.eq(A.EnemyCount(20), 1, "check failed: counted")
		w:advance(1)
		H.eq(A.EnemyCount(50), 1, "beyond 28 yd: not filtered")
		w:advance(1)
		w.env.CheckInteractDistance = nil
		H.eq(A.EnemyCount(20), 1, "no check: counted")
		w:advance(1)
		H.eq(A.EnemyCount(10), 0)
	end)

	it("survives failing unit calls", function()
		local w, _, A = api()
		plate(w, 1, {})
		w.env.UnitCanAttack = function()
			error("boom")
		end
		w.env.UnitReaction = function()
			error("boom")
		end
		H.eq(A.EnemyCount(), 0)
	end)
end)

describe("API helpful and harmful spells", function()
	it("knows heals by flag, ID, name and the client", function()
		local w, ns, A = api(function(w)
			w.spell(2050, { name = "Lesser Heal" })
			w.spell(90010, { name = "Lesser Heal" })
			w.spell(90011, { name = "Blessing", helpful = true })
			w.spell(90012, { name = "Bolt", harmful = true })
		end)
		ns.HEAL_SPELL_IDS[2050] = true
		H.eq(A.IsHelpful(1, { heal = true }), true)
		H.eq(A.IsHelpful(2050), true)
		H.eq(A.IsHelpful(90010), true, "same name as a heal")
		H.eq(A.IsHelpful(90011), true, "client says helpful")
		H.eq(A.IsHelpful(90012), false)
		H.eq(A.IsHealSpell(1, { heal = true }), true)
		H.eq(A.IsHealSpell(nil), false)
		H.eq(A.IsHealSpell(2050), true)
		H.eq(A.IsHealSpell(90010), true)
		H.eq(A.IsHealSpell(90011), false, "buffs are no heals")
		H.eq(A.IsHealSpell(ns.Spell.Warrior.BattleShout), false, "maintenance buff")
		ns.IsMaintenanceBuff = function(id)
			return id == 90010
		end
		H.eq(A.IsHealSpell(90010), false, "maintenance buff")
		ns.IsWeaponBuff = function()
			return true
		end
		H.eq(A.IsHealSpell(2050), false, "weapon buff")
		H.eq(A.IsHarmful(90012), true)
		H.eq(A.IsHarmful(90011), false)
		w.env.C_Spell.IsSpellHelpful = nil
		w.env.C_Spell.IsSpellHarmful = nil
		H.eq(A.IsHelpful(90011), false)
		H.eq(A.IsHarmful(90012), false)
		ns.HEAL_SPELL_IDS = nil
		A.InvalidateSpells(false)
		H.eq(A.IsHealSpell(90010), false)
	end)
end)

describe("API range", function()
	it("reads a spell's max range", function()
		local _, _, A = api(function(w)
			w.spell(1, { name = "Shot", maxRange = 35 })
			w.spell(2, { name = "Hidden", maxRange = wow.SECRET })
		end)
		H.eq(A.SpellMaxRange(1), 35)
		H.eq(A.SpellMaxRange(2), nil)
		H.eq(A.SpellMaxRange(3), nil)
	end)

	it("bands the target distance", function()
		local w, _, A = api()
		H.same({ A.TargetRangeBand() }, { nil, nil }, "no target")
		w:target({ distance = 7 })
		H.same({ A.TargetRangeBand() }, { 7, 7 }, "measured")
		w.env.UnitDistanceSquared = function()
			return 0, false
		end
		H.same({ A.TargetRangeBand() }, { 0, 11 }, "within 10 yd")
		w.state.units.target.distance = 20
		H.same({ A.TargetRangeBand() }, { 11, 28 })
		w.state.units.target.distance = 50
		H.same({ A.TargetRangeBand() }, { 28, 100 })
		w.env.UnitDistanceSquared = function()
			return wow.SECRET, wow.SECRET_BOOL
		end
		w.env.CheckInteractDistance = nil
		H.same({ A.TargetRangeBand() }, { nil, nil })
		w.env.UnitDistanceSquared = function()
			return -1, true
		end
		H.same({ A.TargetRangeBand() }, { nil, nil }, "negative distance ignored")
		w.env.UnitDistanceSquared = nil
		H.same({ A.TargetRangeBand("target") }, { nil, nil })
	end)

	it("decides when a spell needs range", function()
		local w, _, A = api(function(w)
			w.spell(1, { name = "Strike", harmful = true })
			w.spell(2, { name = "Heal", helpful = true })
			w.spell(3, { name = "Shout" })
		end)
		H.eq(A.NeedsRange(1, { nopet = true }), false)
		H.eq(A.NeedsRange(1, { nocombat = true }), false)
		H.eq(A.NeedsRange(2, { heal = true }), false, "self heal")
		w.unit("target", { health = 50, maxHealth = 100, reaction = 5 })
		H.eq(A.NeedsRange(2, { heal = true }), true, "friendly target")
		H.eq(A.NeedsRange(3, { hostile = true }), true)
		H.eq(A.NeedsRange(1), true, "harmful")
		H.eq(A.NeedsRange(3), false)
	end)

	it("states the range of a spell from bands, flags and the action bar", function()
		local w, ns, A = api(function(w)
			w.spell(1, { name = "Strike", harmful = true, maxRange = 0 })
			w.spell(2, { name = "Shot", harmful = true, maxRange = 35 })
			w.spell(3, { name = "Heal", helpful = true })
			w.spell(4, { name = "Shout" })
		end)
		H.eq(A.RangeState(4), "none")
		H.eq(A.RangeState(3, { hostile = true }), "in", "helpful spell cast on yourself")
		H.eq(A.RangeState(3, { heal = true }), "none", "self heal needs no range")
		H.eq(A.RangeState(1), "out", "no target")
		w:target({ distance = 20 })
		H.eq(A.RangeState(1), "out", "melee spell, far target")
		w.state.units.target.distance = 40
		H.eq(A.RangeState(2), "out", "beyond max range")
		w.state.units.target.distance = 4
		H.eq(A.RangeState(1), "in", "band within reach")
		w.env.UnitDistanceSquared = function()
			return 0, false
		end
		w.env.CheckInteractDistance = nil
		local flag
		ns.SpellBarSlot = function()
			return 7
		end
		ns.SpellInRange = function()
			return flag
		end
		flag = true
		H.eq(A.RangeState(2), "in")
		flag = false
		H.eq(A.RangeState(2), "out")
		flag = nil
		H.eq(A.RangeState(2), "unknown")
		w.env.UnitDistanceSquared = nil
		w.env.CheckInteractDistance = function(_, index)
			return index == 1
		end
		flag = false
		H.eq(A.RangeState(2), "in", "band inside a long range wins over a false flag")
		ns.SpellInRange = nil
		H.eq(A.RangeState(2), "in", "band only")
		w.unit("target", { health = 50, maxHealth = 100, reaction = 5 })
		H.eq(A.RangeState(3, { heal = true }), "unknown", "friendly target, nothing known")
	end)

	it("answers InSpellRange per mode", function()
		local _, ns, A = api()
		local state
		A.RangeState = function()
			return state
		end
		state = "none"
		H.eq(A.InSpellRange(1), true)
		state = "out"
		H.eq(A.InSpellRange(1, nil, "any"), true)
		H.eq(A.InSpellRange(1, nil, "in"), false)
		state = "unknown"
		H.eq(A.InSpellRange(1, nil, "notOut"), true)
		H.eq(A.InSpellRange(1), false)
		local _ = ns
	end)
end)

describe("API heal unit", function()
	it("heals the unit a press would land on", function()
		local w, _, A = api()
		H.eq(A.HealUnit(), "player")
		H.eq(A.HealHealth(), 100)
		w.unit("mouseover", { health = 30, maxHealth = 100, reaction = 5 })
		H.eq(A.HealUnit(), "player", "mouseover cast off")
		w.state.cvars.enableMouseoverCast = true
		H.eq(A.HealUnit(), "mouseover")
		H.eq(A.HealHealth(), 30)
		w.state.units.mouseover = nil
		w.unit("target", { health = 60, maxHealth = 100, reaction = 5 })
		H.eq(A.HealRangeUnit(), "target")
		w.unit("focus", { health = 1, maxHealth = 1 })
		H.eq(A.HealUnit({ unit = "focus" }), "focus")
		H.eq(A.HealUnit({ unit = "party3" }), "target", "missing unit")
		w.env.GetCVarBool = function()
			error("boom")
		end
		H.eq(A.HealUnit(), "target")
		w.env.GetCVarBool = nil
		H.eq(A.HealUnit(), "target")
	end)

	it("never counts dead, attackable or unreadable units as friendly", function()
		local w, _, A = api()
		w.unit("target", { health = 1, maxHealth = 1, dead = true, reaction = 5 })
		H.eq(A.HealUnit(), "player", "dead")
		w.unit("target", { health = 1, maxHealth = 1, hostile = true })
		H.eq(A.HealUnit(), "player", "attackable")
		w.env.UnitCanAttack = function()
			return wow.SECRET_BOOL
		end
		H.eq(A.HealUnit(), "player", "secret")
		w.env.UnitCanAttack = function()
			return false
		end
		w.env.UnitReaction = function()
			return wow.SECRET
		end
		H.eq(A.HealUnit(), "target", "not attackable, reaction hidden")
		w.env.UnitCanAttack = function()
			error("boom")
		end
		w.env.UnitReaction = function()
			error("boom")
		end
		H.eq(A.HealUnit(), "player")
		w.env.UnitExists = function()
			error("boom")
		end
		H.eq(A.HealUnit(), "player")
	end)
end)

describe("API.Ready", function()
	local function ready()
		return api(function(w)
			w.spell(1, { name = "Strike", harmful = true, cost = { "junk", { type = 1, cost = 20 } } })
			w.spell(2, { name = "Heal", helpful = true, usable = false, cost = { { type = 0, cost = 50 } } })
			w.spell(3, { name = "Lay on Hands", helpful = true, usable = false, cost = { { type = -2, cost = 10 } } })
			w.spell(4, { name = "Busy", harmful = true, usable = false })
			w.spell(5, { name = "Broke", noMana = true })
		end)
	end

	it("checks known, cooldown, usability and resources", function()
		local w, _, A = ready()
		w.state.units.player.power[1] = 30
		H.eq(A.Ready(99), false, "unknown")
		H.eq(A.Ready(1), true)
		w.state.spells[1].cooldown = { w.state.time, 10 }
		H.eq(A.Ready(1), false, "on cooldown")
		H.eq(A.Ready(1, nil, true), true, "cooldown ignored")
		H.eq(A.Ready(5), false, "out of mana")
		w.state.units.player.power[0] = 40
		H.eq(A.Ready(2), false, "helpful: needs 50 mana")
		w.state.units.player.power[0] = 60
		H.eq(A.Ready(2), true)
		H.eq(A.Ready(3), true, "health cost is no resource")
		H.eq(A.Ready(4), false, "harmful and unusable")
	end)

	it("lets an unusable spell pass during a cast or right after one", function()
		local w, ns, A = ready()
		w.state.units.player.casting = { name = "Busy", endTime = (w.state.time + 2) * 1000 }
		H.eq(A.Ready(4), true, "during a cast")
		w.state.units.player.casting = nil
		ns.API.lastCastAt = w.state.time
		H.eq(A.Ready(4), true, "inside the GCD")
		w:advance(2)
		H.eq(A.Ready(4), false)
	end)

	it("treats odd usability answers as unknown", function()
		local w, _, A = ready()
		w.state.units.player.power[1] = 30
		w.env.C_Spell.IsSpellUsable = function()
			error("boom")
		end
		H.eq(A.Ready(1), true)
		w.env.C_Spell.IsSpellUsable = nil
		w.env.C_Spell.GetSpellPowerCost = function()
			error("boom")
		end
		H.eq(A.Ready(1), true)
		w.env.C_Spell = nil
		H.eq(A.Ready(1), true)
	end)
end)
