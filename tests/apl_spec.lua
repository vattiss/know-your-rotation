local wow = require("wow")
local H = require("helpers")

local function boot(class, setup)
	local w = wow.new()
	w:player(class or "ROGUE")
	if setup then
		setup(w)
	end
	w:load()
	w:fire("PLAYER_LOGIN")
	return w, w.ns
end

local function keys(list)
	local out = {}
	for i, s in ipairs(list) do
		out[i] = s.key
	end
	return out
end

local function indexOf(list, key)
	for i, s in ipairs(list) do
		if s.key == key then
			return i
		end
	end
end

describe("APL helpers", function()
	it("reads step on/off and checkbox values", function()
		local _, ns = boot()
		H.eq(ns.IsStepEnabled(nil), false)
		H.eq(ns.IsStepEnabled({ on = false }), false)
		H.eq(ns.IsStepEnabled({ on = 0 }), false)
		H.eq(ns.IsStepEnabled({ on = "0" }), false)
		H.eq(ns.IsStepEnabled({ on = 1 }), true)
		H.eq(ns.IsStepEnabled({}), true)
		H.eq(ns.CoerceChecked(true), true)
		H.eq(ns.CoerceChecked(1), true)
		H.eq(ns.CoerceChecked("1"), true)
		H.eq(ns.CoerceChecked(0), false)
	end)
end)

describe("APL race and faction", function()
	local function race(name, file, id, faction)
		local w = wow.new()
		w:player("ROGUE")
		w.env.UnitRace = function()
			return name, file, id
		end
		w.env.UnitFactionGroup = function()
			return faction
		end
		local ns = w:load()
		return ns
	end

	it("uses the numeric race id when readable", function()
		H.eq(race("Human", "Human", 1).RaceId(), 1)
	end)

	it("maps the race file when the id is hidden", function()
		H.eq(race("x", "Orc", wow.SECRET).RaceId(), 2)
		H.eq(race("x", "Windborne", "nope").RaceId(), 96)
	end)

	it("maps English race names last", function()
		local cases = {
			{ "Human", 1 },
			{ "Orc", 2 },
			{ "Dwarf", 3 },
			{ "Night Elf", 4 },
			{ "Undead", 5 },
			{ "Forsaken", 5 },
			{ "Tauren", 6 },
			{ "Gnome", 7 },
			{ "Troll", 8 },
		}
		for _, c in ipairs(cases) do
			H.eq(race(c[1], "Unknown", nil).RaceId(), c[2], c[1])
		end
		H.eq(race("Aeolid", "", nil, "Horde").RaceId(), 96)
		H.eq(race("Skyborne", "", nil, "Alliance").RaceId(), 95)
		H.eq(race("Murloc", wow.SECRET, nil).RaceId(), nil)
		H.eq(race(wow.SECRET_STRING, wow.SECRET_STRING, nil).RaceId(), nil)
	end)

	it("treats an inaccessible id or name as missing", function()
		local w = wow.new()
		w:player("ROGUE")
		w.env.UnitRace = function()
			return "Human", "Human", 1
		end
		w.env.issecretvalue = function()
			return false
		end
		w.env.canaccessvalue = function()
			return false
		end
		local ns = w:load()
		H.eq(ns.RaceId(), nil)
	end)

	it("returns nil when the client call fails", function()
		local w = wow.new()
		w:player("ROGUE")
		w.env.UnitRace = function()
			error("no")
		end
		w.env.UnitFactionGroup = function()
			error("no")
		end
		local ns = w:load()
		H.eq(ns.RaceId(), nil)
		H.eq(ns.Faction(), nil)
	end)
end)

describe("APL racials", function()
	it("adds the player's racials, defensive ones only on request", function()
		local _, ns = boot("ROGUE")
		local all = keys(ns.RacialSteps())
		H.contains(all, "racial_Perception")
		H.contains(all, "racial_WillToSurvive")
		local def = keys(ns.RacialSteps(true))
		H.same(def, { "racial_WillToSurvive" })
	end)

	it("gates by faction and falls back to Known without a race list", function()
		local w, ns = boot("ROGUE")
		w.state.faction = "Horde"
		ns.RACIALS = {
			{ key = "OnlyHorde", id = 1, factions = { "Horde" }, races = { 1 } },
			{ key = "OnlyAlliance", id = 2, factions = { "Alliance" } },
			{ key = "Anyone", id = 3 },
			{ key = "Learned", id = 4 },
			{ key = "WrongRace", id = 5, races = { 2 } },
		}
		w.spell(4, { name = "Learned Racial" })
		H.same(keys(ns.RacialSteps()), { "racial_OnlyHorde", "racial_Learned" })
		w.env.UnitFactionGroup = function()
			return nil
		end
		w.env.UnitRace = function()
			return nil
		end
		H.same(keys(ns.RacialSteps()), { "racial_Learned" })
	end)
end)

describe("APL druid form", function()
	it("tells a tank out of bear form to shift", function()
		local _, ns = boot("DRUID")
		local first = ns.APLDefaults.DRUID.tank[1]
		H.eq(first.key, "BearForm")
		H.eq(first.opt.noform, ns.Spell.Druid.BearForm)
	end)

	it("reads the cat form without recursing through the hold lookup", function()
		local w, ns = boot("DRUID", function(w)
			w.spell(768, { name = "Cat Form" })
		end)
		w.aura("player", { name = "Cat Form", spellId = 768 })
		-- ActiveSpec -> Form -> HasAura -> rememberAura -> HoldSeconds -> GetAPL -> ActiveSpec
		H.eq(ns.ActiveSpec(), "cat")
		H.eq(ns.ActiveSpec(), "cat", "and again, from the memory")
	end)
end)

describe("APL front racials", function()
	it("puts an offensive racial first, also in a save that has it at the end", function()
		local _, ns = boot("ROGUE")
		ns.RACIALS = {
			{
				key = "Offence",
				id = 20572,
				races = { 1 },
				opt = { hostile = true, combat = true },
				on = true,
				front = true,
			},
			{ key = "Calm", id = 20600, races = { 1 }, opt = { combat = true } },
		}
		ns.InvalidateAPLCache()
		local list = ns.GetAPL("ROGUE", "damage", "single")
		H.eq(list[1].key, "racial_Offence", "first in the default list")
		H.eq(list[#list].key, "racial_Calm", "the others close it")
		ns.db.apl = {
			ROGUE = {
				damage = {
					single = {
						{ key = "Eviscerate", on = 1 },
						{ key = "racial_Offence", on = 1 },
					},
				},
			},
		}
		ns.InvalidateAPLCache()
		list = ns.GetAPL("ROGUE", "damage", "single")
		H.eq(list[1].key, "racial_Offence", "an old save is moved to the front")
		H.eq(list[2].key, "Eviscerate")
	end)
end)

describe("APL specs and modes", function()
	it("picks the druid list from the form and role", function()
		local w, ns = boot("DRUID", function(w)
			w.spell(768, { name = "Cat Form" })
			w.spell(5487, { name = "Bear Form" })
		end)
		local form
		ns.API.Form = function(id)
			return id == form
		end
		ns.db.role = "heal"
		H.eq(ns.ActiveSpec(), "heal")
		ns.db.role = "tank"
		H.eq(ns.ActiveSpec(), "tank")
		form = ns.Spell.Druid.BearForm
		H.eq(ns.ActiveSpec(), "bear")
		ns.db.role = "damage"
		H.eq(ns.ActiveSpec(), "bear")
		form = ns.Spell.Druid.CatForm
		H.eq(ns.ActiveSpec(), "cat")
		form = nil
		H.eq(ns.ActiveSpec(), "damage")
		ns.db.role = nil
		H.eq(ns.ActiveSpec(), "damage")
		w.state.class = "ROGUE"
		ns.ClassToken = nil
		ns.db.role = "damage"
		H.eq(ns.ActiveSpec(), "damage")
	end)

	it("lists the specs of a class", function()
		local _, ns = boot("SHAMAN")
		H.same(ns.SpecList("DRUID"), { "damage", "cat", "bear", "heal", "tank" })
		H.same(ns.SpecList(), { "caster", "melee", "heal" })
		H.same(ns.SpecList("NOBODY"), { "damage" })
		ns.APLDefaults.TESTCLASS = { extra = {} }
		H.same(ns.SpecList("TESTCLASS"), { "extra" })
		ns.APLDefaults.EMPTY = {}
		ns.CLASS_ROLES.EMPTY = { "tank" }
		H.same(ns.SpecList("EMPTY"), { "tank" })
	end)

	it("reads the combat mode and switches to AoE on enough enemies", function()
		local w, ns = boot("WARRIOR")
		ns.db.combatMode = "bogus"
		H.eq(ns.CombatMode(), "auto")
		ns.db.combatMode = "single"
		H.eq(ns.ResolveCombatMode(), "single")
		ns.db.combatMode = "auto"
		H.eq(ns.ResolveCombatMode(), "auto", "out of combat")
		w.state.units.player.combat = true
		local count = 1
		ns.API.EnemyCount = function()
			return count
		end
		ns.db.autoEnemies = 1
		H.eq(ns.ResolveCombatMode(), "auto", "need is at least 2")
		count = 2
		H.eq(ns.ResolveCombatMode(), "aoe")
		ns.db.autoEnemies = nil
		H.eq(ns.ResolveCombatMode(), "auto", "default 3")
		local db = ns.db
		ns.db = nil
		H.eq(ns.CombatMode(), "auto")
		ns.db = db
	end)
end)

describe("APL rotation lists", function()
	it("returns the defaults with racials and memoizes for a moment", function()
		local w, ns = boot("ROGUE")
		local list = ns.GetAPL("ROGUE", "damage", "single")
		H.eq(list[1].key, "Stealth")
		H.truthy(indexOf(list, "racial_Perception"), "racial added")
		H.eq(ns.GetAPL("ROGUE", "damage", "single"), list, "memo")
		w:advance(1)
		H.truthy(ns.GetAPL("ROGUE", "damage", "single") ~= list, "memo expired")
		H.eq(ns.GetAPL("ROGUE", "damage", "aoe")[1].key, "BladeFlurry")
		H.truthy(#ns.GetAPL("NOBODY", "damage", "aoe") > 0, "only racials")
	end)

	it("falls back to the damage / caster / range lists", function()
		local _, ns = boot("SHAMAN")
		H.eq(ns.GetAPL("SHAMAN", "nope", "single")[1].key, ns.APLDefaults.SHAMAN.caster[1].key)
		H.eq(ns.GetAPL("SHAMAN", "nope", "aoe")[1].key, ns.APLModes.SHAMAN.caster.aoe[1].key)
		H.eq(ns.GetAPL("ROGUE", "nope", "aoe")[1].key, "BladeFlurry")
		ns.APLModes.ROGUE = nil
		H.eq(ns.GetAPL("ROGUE", "damage", "aoe")[1].key, "Stealth", "no AoE list: single")
	end)

	it("saves, moves, toggles and sets holds", function()
		local _, ns = boot("ROGUE")
		local first = ns.GetAPL("ROGUE", "damage", "single")[1].key
		ns.MoveAPL(1, 1, "ROGUE", "damage", "single")
		H.eq(ns.GetAPL("ROGUE", "damage", "single")[2].key, first)
		ns.MoveAPL(1, -1, "ROGUE", "damage", "single")
		ns.MoveAPL(1, 1, "ROGUE", "damage", "bogus")
		ns.SetAPLEnabled(first, false, "ROGUE", "damage", "single")
		H.eq(ns.GetAPL("ROGUE", "damage", "single")[2].on, false)
		ns.SetAPLEnabled("nope", true, "ROGUE", "damage", "single")
		ns.SetAPLEnabled(first, true, "ROGUE", "damage", "bogus")
		ns.SetAPLHold(first, 4.4, "ROGUE", "damage", "single")
		H.eq(ns.GetAPL("ROGUE", "damage", "single")[2].opt.hold, 4)
		ns.SetAPLHold(first, "x", "ROGUE", "damage", "single")
		H.eq(ns.GetAPL("ROGUE", "damage", "single")[2].opt.hold, 0)
		ns.SetAPLHold("nope", 1, "ROGUE", "damage", "single")
		ns.SetAPLHold(nil, 1, "ROGUE", "damage", "single")
		ns.SetAPLHold(first, 1, "ROGUE", "damage", "bogus")
		local saved = ns.db.apl.ROGUE.damage.single
		H.eq(saved[2].hold, 0)
	end)

	it("removes a default (remembered as dropped) and a custom spell", function()
		local w, ns = boot("ROGUE")
		w.spell(9001, { name = "Custom Strike!", harmful = true })
		H.eq(ns.AddAPL(9001, "ROGUE", "damage", "single"), true)
		local list = ns.GetAPL("ROGUE", "damage", "single")
		local custom = list[#list]
		H.eq(custom.key, "custom_CustomStrike")
		H.same(custom.opt, { hostile = true, hold = 0 })
		ns.RemoveAPL("custom_CustomStrike", "ROGUE", "damage", "single")
		H.falsy(indexOf(ns.GetAPL("ROGUE", "damage", "single"), "custom_CustomStrike"))
		ns.RemoveAPL("Stealth", "ROGUE", "damage", "single")
		H.falsy(indexOf(ns.GetAPL("ROGUE", "damage", "single"), "Stealth"))
		H.eq(ns.db.aplDrop.ROGUE.damage.single.Stealth, true)
		ns.RemoveAPL("Stealth", "ROGUE", "damage", "bogus")
		ns.RemoveAPL("Stealth")
	end)

	it("adds spells: duplicates, buffs, defaults, helpful customs, positions", function()
		local w, ns = boot("ROGUE")
		w.spell(9002, { name = "Bandage Self", helpful = true })
		w.spell(9003, { name = "", harmful = true })
		H.eq(ns.AddAPL(nil), false)
		H.eq(ns.AddAPL(ns.Spell.Mage.ArcaneIntellect), false, "maintenance buff refused")
		H.eq(ns.AddAPL(ns.Spell.Rogue.SinisterStrike, "ROGUE", "damage", "bogus"), false)
		H.eq(ns.AddAPL(ns.Spell.Rogue.SinisterStrike, "ROGUE", "damage", "single"), false, "already listed")
		ns.RemoveAPL("Stealth", "ROGUE", "damage", "single")
		H.eq(ns.AddAPL(ns.Spell.Rogue.Stealth, "ROGUE", "damage", "single", 1), true, "default back")
		H.eq(ns.GetAPL("ROGUE", "damage", "single")[1].key, "Stealth")
		H.eq(ns.db.aplDrop.ROGUE.damage.single.Stealth, nil)
		H.eq(ns.AddAPL(9002, "ROGUE", "damage", "single", 999), true)
		local list = ns.GetAPL("ROGUE", "damage", "single")
		H.eq(list[#list].opt.heal, true, "helpful custom is a heal")
		H.eq(ns.AddAPL(9003), false, "no mode")
		H.eq(ns.AddAPL(9003, nil, nil, "single"), true)
		local single = ns.GetAPL(nil, nil, "single")
		H.eq(single[#single].key, "custom_9003")
		H.eq(single[#single].opt.hostile, true)
		H.eq(ns.AddAPL("Some Spell", "ROGUE", "damage", "aoe"), true)
		local aoe = ns.GetAPL("ROGUE", "damage", "aoe")
		H.eq(aoe[#aoe].key, "custom_spell")
	end)

	it("merges saved rows with new defaults, customs and drops", function()
		local w, ns = boot("ROGUE")
		w.spell(9004, { name = "Mystery", helpful = true })
		ns.db.apl = {
			ROGUE = {
				damage = {
					single = {
						{ key = "SinisterStrike", on = 0, hold = 7 },
						{ key = "custom_Mystery", id = 9004, custom = true, on = 1, hold = -1 },
						{ key = "custom_Weapon", id = next(ns.WEAPON_BUFF_IDS), custom = true, on = 1 },
						{ key = "Gone", on = 1 },
						{ key = "custom_NoId", custom = true, on = 1 },
						"junk",
					},
				},
			},
		}
		ns.db.aplDrop = { ROGUE = { damage = { single = { Stealth = true } } } }
		ns.InvalidateAPLCache()
		local list = ns.GetAPL("ROGUE", "damage", "single")
		H.eq(list[1].key, "SinisterStrike")
		H.eq(list[1].on, false)
		H.eq(list[1].opt.hold, 7)
		H.eq(list[2].key, "custom_Mystery")
		H.eq(list[2].opt.heal, true, "helpful custom marked as heal")
		H.falsy(indexOf(list, "custom_Weapon"), "weapon buffs never in combat lists")
		H.falsy(indexOf(list, "Gone"), "unknown key dropped")
		H.falsy(indexOf(list, "Stealth"), "dropped default")
		H.truthy(indexOf(list, "Eviscerate"), "new default appended")
	end)

	it("merges drops only, skipping duplicates by name", function()
		local w, ns = boot("ROGUE")
		ns.db.apl = nil
		ns.db.aplDrop = { ROGUE = { damage = { single = { Stealth = true } } } }
		local list = ns.GetAPL("ROGUE", "damage", "single")
		H.falsy(indexOf(list, "Stealth"))
		H.truthy(indexOf(list, "Eviscerate5"), "same spell, other key kept")
		ns.InvalidateAPLCache()
		ns.db.aplDrop = { ROGUE = { damage = { aoe = {} } } }
		H.eq(ns.GetAPL("ROGUE", "damage", "single")[1].key, "Stealth", "no drops for this mode")
		ns.InvalidateAPLCache()
		ns.db.aplDrop = { ROGUE = { damage = { single = "bad" } } }
		H.eq(ns.GetAPL("ROGUE", "damage", "single")[1].key, "Stealth")
		w.spell(ns.Spell.Rogue.Eviscerate, { name = "Eviscerate" })
		ns.InvalidateAPLCache()
		ns.db.apl = { ROGUE = { damage = { single = { { key = "Eviscerate", on = 1 } } } } }
		ns.db.aplDrop = nil
		local merged = ns.GetAPL("ROGUE", "damage", "single")
		H.eq(merged[1].key, "Eviscerate")
		H.truthy(indexOf(merged, "Eviscerate5"), "a new default variant reaches an old save")
		-- A spell the player added himself is not doubled by a default.
		ns.InvalidateAPLCache()
		ns.db.apl = {
			ROGUE = {
				damage = {
					single = {
						{ key = "custom_Eviscerate", id = ns.Spell.Rogue.Eviscerate, custom = true, on = 1 },
					},
				},
			},
		}
		merged = ns.GetAPL("ROGUE", "damage", "single")
		H.eq(merged[1].key, "custom_Eviscerate")
		H.falsy(indexOf(merged, "Eviscerate5"), "the player's own copy counts")
	end)

	it("reads legacy flat saves as the single list", function()
		local _, ns = boot("ROGUE")
		ns.db.apl = { ROGUE = { damage = { { key = "Eviscerate", on = 1 } } } }
		H.eq(ns.GetAPL("ROGUE", "damage", "single")[1].key, "Eviscerate")
		H.eq(ns.GetAPL("ROGUE", "damage", "aoe")[1].key, "BladeFlurry", "legacy has no AoE")
		ns.SaveAPL({ { key = "Gouge", on = true } }, "ROGUE", "damage", "aoe")
		H.eq(ns.db.apl.ROGUE.damage.single[1].key, "Eviscerate", "legacy moved into the bucket")
		ns.db.apl.ROGUE.damage = { aoe = "bad" }
		H.eq(ns.GetAPL("ROGUE", "damage", "aoe")[1].key, "BladeFlurry")
		ns.db.apl.ROGUE.damage = "bad"
		ns.SaveAPL({}, "ROGUE", "damage", "single")
		H.same(ns.db.apl.ROGUE.damage, { single = {} })
	end)

	it("ignores bad save calls and falls back to Tick", function()
		local _, ns = boot("ROGUE")
		ns.SaveAPL({}, "ROGUE", "damage", "bogus")
		ns.SaveAPL(nil, "ROGUE", "damage", "single")
		H.eq(ns.db.apl, nil)
		local ticks = 0
		ns.ApplyRotationEdit = nil
		ns.Tick = function()
			ticks = ticks + 1
		end
		ns.SaveAPL({}, "ROGUE", "damage", "single")
		H.eq(ticks, 1)
		ns.Tick = nil
		ns.SaveAPL({}, nil, nil, "single")
	end)

	it("resets one mode, a legacy list, or nothing", function()
		local _, ns = boot("ROGUE")
		local ticks = 0
		ns.Tick = function()
			ticks = ticks + 1
		end
		ns.ResetAPL("ROGUE", "damage", "bogus")
		ns.ResetAPL("ROGUE", "damage", "single")
		H.truthy(ticks >= 1, "nothing saved: just a refresh")
		ns.Tick = nil
		ns.ResetAPL("ROGUE", "damage", "single")
		ns.SaveAPL({ { key = "Gouge", on = 1 } }, "ROGUE", "damage", "single")
		ns.RemoveAPL("Stealth", "ROGUE", "damage", "single")
		ns.ResetAPL("ROGUE", "damage", "single")
		H.eq(ns.db.apl.ROGUE.damage.single, nil)
		H.eq(ns.db.aplDrop.ROGUE.damage.single, nil)
		ns.db.apl.ROGUE.damage = { { key = "Gouge", on = 1 } }
		ns.ResetAPL("ROGUE", "damage", "aoe")
		H.truthy(ns.db.apl.ROGUE.damage, "legacy kept for another mode")
		ns.ResetAPL("ROGUE", "damage", "single")
		H.eq(ns.db.apl.ROGUE.damage, nil)
		ns.ApplyRotationEdit = nil
		ns.db.apl.ROGUE.damage = { single = {} }
		ns.ResetAPL(nil, nil, "single")
	end)
end)

describe("APL defense lists", function()
	it("returns defaults with defensive racials and memoizes", function()
		local w, ns = boot("WARRIOR")
		local list = ns.GetDef("WARRIOR", "damage")
		H.eq(list[1].key, "BattleShout")
		H.truthy(indexOf(list, "racial_WillToSurvive"))
		H.eq(ns.GetDef("WARRIOR", "damage"), list)
		w:advance(1)
		H.eq(ns.GetDef("WARRIOR", "nope")[1].key, "BattleShout", "falls back to damage")
		H.truthy(#ns.GetDef("NOBODY", "damage") >= 1, "racials only")
		H.truthy(ns.GetDef()[1], "current class and spec")
	end)

	it("edits, removes, adds and resets", function()
		local w, ns = boot("WARRIOR")
		w.spell(9100, { name = "Shield Trick" })
		ns.MoveDef(1, 1, "WARRIOR", "damage")
		H.eq(ns.GetDef("WARRIOR", "damage")[2].key, "BattleShout")
		ns.MoveDef(1, -5, "WARRIOR", "damage")
		ns.SetDefEnabled("BattleShout", 0, "WARRIOR", "damage")
		H.eq(ns.GetDef("WARRIOR", "damage")[2].on, false)
		ns.SetDefEnabled("nope", 1, "WARRIOR", "damage")
		ns.SetDefHold("BattleShout", 2.6, "WARRIOR", "damage")
		H.eq(ns.GetDef("WARRIOR", "damage")[2].opt.hold, 3)
		ns.SetDefHold("BattleShout", nil, "WARRIOR", "damage")
		H.eq(ns.GetDef("WARRIOR", "damage")[2].opt.hold, 0)
		ns.SetDefHold("nope", 1, "WARRIOR", "damage")
		ns.SetDefHold(nil, 1)
		H.eq(ns.AddDef(nil), false)
		H.eq(ns.AddDef(ns.Spell.Warrior.BattleShout, "WARRIOR", "damage"), false, "duplicate")
		H.eq(ns.AddDef(9100, "WARRIOR", "damage", 1), true)
		H.eq(ns.GetDef("WARRIOR", "damage")[1].key, "custom_ShieldTrick")
		H.same(ns.GetDef("WARRIOR", "damage")[1].opt, { combat = true, hold = 0 })
		ns.RemoveDef("custom_ShieldTrick", "WARRIOR", "damage")
		ns.RemoveDef("BattleShout", "WARRIOR", "damage")
		H.eq(ns.db.defDrop.WARRIOR.damage.BattleShout, true)
		H.falsy(indexOf(ns.GetDef("WARRIOR", "damage"), "BattleShout"))
		H.eq(ns.AddDef(ns.Spell.Warrior.BattleShout, "WARRIOR", "damage", 99), true, "default back")
		H.eq(ns.db.defDrop.WARRIOR.damage.BattleShout, nil)
		ns.RemoveDef("BattleShout")
		H.eq(ns.AddDef(ns.Spell.Warrior.BattleShout), true)
		ns.ResetDef("WARRIOR", "damage")
		H.eq(ns.db.def.WARRIOR.damage, nil)
		ns.ResetDef("MAGE", "damage")
		ns.ApplyRotationEdit = nil
		ns.ResetDef()
		ns.SaveDef({}, nil, nil)
	end)

	it("merges saved defense rows", function()
		local w, ns = boot("WARRIOR")
		w.spell(9200, { name = "Mend", helpful = true })
		ns.db.def = { WARRIOR = { damage = { { key = "LastStand", on = 1 } } } }
		ns.InvalidateAPLCache()
		local list = ns.GetDef("WARRIOR", "damage")
		H.eq(list[1].key, "LastStand")
		H.truthy(indexOf(list, "BattleShout"), "maintenance buffs stay in defense")
		ns.InvalidateAPLCache()
		ns.db.def = nil
		ns.db.defDrop = { WARRIOR = { damage = { LastStand = true } } }
		H.falsy(indexOf(ns.GetDef("WARRIOR", "damage"), "LastStand"))
		ns.InvalidateAPLCache()
		ns.db.def = { WARRIOR = { damage = { { key = "custom_Mend", id = 9200, custom = true, on = 1 } } } }
		local custom = ns.GetDef("WARRIOR", "damage")[1]
		H.eq(custom.opt.heal, true, "helpful custom in defense")
		H.eq(custom.opt.combat, true)
	end)
end)

describe("APL.ApplyRotationEdit", function()
	it("runs whatever refresh hooks exist", function()
		local _, ns = boot("ROGUE")
		local calls = {}
		ns.FlushProfile = function()
			calls[#calls + 1] = "flush"
		end
		ns.InvalidateTick = function()
			calls[#calls + 1] = "invalidate"
		end
		ns.Tick = function()
			calls[#calls + 1] = "tick"
		end
		ns.ApplyRotationEdit()
		H.same(calls, { "flush", "invalidate", "tick" })
		ns.FlushProfile, ns.InvalidateAPLCache, ns.InvalidateTick, ns.Tick = nil, nil, nil, nil
		ns.ApplyRotationEdit()
	end)
end)
