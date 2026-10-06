local wow = require("wow")
local H = require("helpers")

local CORE = { "Locale.lua", "API.lua", "Data.lua" }

local function api(class, setup)
	local w = wow.new()
	w:player(class or "PALADIN")
	if setup then
		setup(w)
	end
	w:target()
	local ns = w:load(CORE)
	return w, ns, ns.API
end

describe("API.FindAura", function()
	it("finds by spell ID, name, scan, resolved ID and family", function()
		local w, _, A = api("PALADIN", function(w)
			w.spell(10, { name = "Seal of Righteousness" })
			w.spell(11, { name = "Seal of Command" })
			w.spell(12, { name = "Blessing of Might" })
			w.spell(13, { name = "Renamed", override = 14 })
			w.spell(14, { name = "Renamed Two" })
		end)
		H.same({ A.FindAura(nil) }, { false, 0, false, nil, 0 })
		w.aura("player", { name = "Seal of Righteousness", spellId = 10, expirationTime = w.state.time + 20 })
		local found, remain, unreadable, _, stacks = A.FindAura(10, "player", "HELPFUL")
		H.same({ found, remain, unreadable, stacks }, { true, 20, false, 1 })
		H.eq((A.FindAura(11)), true, "same seal family")
		w.aura("target", { name = "Blessing of Might", spellId = 12, applications = 3 })
		local f2, r2, _, _, s2 = A.FindAura(12, "target", "HELPFUL")
		H.same({ f2, r2, s2 }, { true, 9999, 3 }, "by name, permanent")
		w.aura("target", { name = "Renamed Two", spellId = 14 })
		w.env.C_UnitAuras.GetAuraDataBySpellName = nil
		H.eq((A.FindAura(13, "target")), true, "scan by resolved ID")
		w.state.units.target.secretGuid = true
		w.aura("target", { name = "Other", spellId = 99 })
		A.WipeAuraScans()
		H.eq((A.FindAura(99, "target")), true, "scan by ID")
	end)

	it("reads stacks from any field and handles odd timers", function()
		local w, _, A = api("PALADIN", function(w)
			w.spell(20, { name = "Stacky" })
		end)
		local data = {
			name = "Stacky",
			spellId = 20,
			stacks = 4,
			expirationTime = w.state.time - 5,
		}
		w.env.C_UnitAuras.GetPlayerAuraBySpellID = function()
			return data
		end
		local _, remain, _, _, stacks = A.FindAura(20)
		H.eq(stacks, 4)
		H.eq(remain, 0, "expired")
		data.stacks, data.count = nil, 2
		H.eq(select(5, A.FindAura(20)), 2)
		data.count = 0
		H.eq(select(5, A.FindAura(20)), 1, "no count: 1")
	end)

	it("marks hidden auras as unreadable", function()
		local w, _, A = api("PALADIN", function(w)
			w.spell(21, { name = "Hidden" })
		end)
		w.aura("player", { name = "Hidden", spellId = 21 })
		w.state.secret.auras = true
		local found, _, unreadable = A.FindAura(21)
		H.same({ found, unreadable }, { false, true })
		w.state.secret.auras = false
		w.env.C_UnitAuras.GetAuraDataByIndex = function(_, i)
			if i == 1 then
				return { name = "Hidden", spellId = wow.SECRET }
			end
		end
		w.env.C_UnitAuras.GetAuraDataBySpellName = function()
			return { name = wow.SECRET_STRING }
		end
		w.env.C_UnitAuras.GetPlayerAuraBySpellID = nil
		A.WipeAuraScans()
		local f2, _, u2 = A.FindAura(21)
		H.same({ f2, u2 }, { false, true }, "half-hidden identity")
		w.env.C_UnitAuras.GetAuraDataByIndex = function()
			return {}
		end
		A.WipeAuraScans()
		local _, _, u3 = A.FindAura(21)
		H.eq(u3, true, "no name, no ID")
		w.env.C_UnitAuras.GetAuraDataByIndex = function()
			error("boom")
		end
		A.WipeAuraScans()
		H.eq(select(3, A.FindAura(21)), true)
		w.env.C_UnitAuras = nil
		A.WipeAuraScans()
		H.eq(select(3, A.FindAura(21)), true, "no aura API")
	end)

	it("uses AuraUtil when the name API is missing", function()
		local w, _, A = api("PALADIN", function(w)
			w.spell(22, { name = "Util" })
		end)
		w.env.C_UnitAuras.GetAuraDataBySpellName = nil
		w.env.C_UnitAuras.GetPlayerAuraBySpellID = nil
		w.env.C_UnitAuras.GetAuraDataByIndex = function() end
		w.env.AuraUtil = {
			FindAuraByName = function(name)
				if name == "Util" then
					return "Util", nil, 0, nil, 0, 0, nil, nil, nil, 22
				end
			end,
		}
		H.eq((A.FindAura(22)), true)
		w.env.AuraUtil.FindAuraByName = function()
			error("boom")
		end
		H.eq((A.FindAura(22)), false)
	end)

	it("counts only your own debuffs on an enemy, except shared ones", function()
		local w, ns, A = api("WARLOCK", function(w)
			w.spell(172, { name = "Corruption", harmful = true })
			w.spell(7386, { name = "Sunder Armor", harmful = true })
		end)
		w.aura("target", { name = "Corruption", spellId = 172, harmful = true, mine = false })
		H.eq((A.FindAura(172, "target", "HARMFUL")), false, "another warlock's")
		w.spell(ns.Spell.Warrior.SunderArmor, { name = "Sunder Armor" })
		w.aura(
			"target",
			{ name = "Sunder Armor", spellId = ns.Spell.Warrior.SunderArmor, harmful = true, mine = false }
		)
		H.eq((A.FindAura(ns.Spell.Warrior.SunderArmor, "target", "HARMFUL")), true, "shared by ID")
		H.eq((A.FindAura(7386, "target", "HARMFUL")), true, "shared by name")
		ns.SHARED_DEBUFF_IDS = nil
		H.eq((A.FindAura(7386, "target", "HARMFUL")), false)
	end)
end)

describe("API.HasAura memory", function()
	it("remembers a cast self-buff while auras are hidden", function()
		local w, ns, A = api("PALADIN", function(w)
			w.spell(30, { name = "Seal of Light", helpful = true })
			w.spell(31, { name = "Plain Buff", helpful = true })
		end)
		A.NoteSelfBuff(nil)
		A.NoteSelfBuff(wow.SECRET)
		A.NoteSelfBuff(30)
		w.aura("player", { name = "Something", spellId = 1 })
		w.state.secret.auras = true
		H.same({ A.HasAura(30) }, { true, 9999 }, "remembered (seal family 30 s)")
		w:advance(31)
		H.same({ A.HasAura(30) }, { false, 0 }, "expired")
		ns.SPELL_HOLD[31] = 12
		A.NoteSelfBuff(31)
		w:advance(11)
		H.eq((A.HasAura(31)), true, "own hold length")
		w:advance(2)
		H.eq((A.HasAura(31)), false)
	end)

	it("trusts a remembered buff in combat and releases it out of combat", function()
		local w, _, A = api("PALADIN", function(w)
			w.spell(32, { name = "Blessing of Wisdom", helpful = true })
		end)
		w.aura("player", { name = "Blessing of Wisdom", spellId = 32, expirationTime = w.state.time + 300 })
		H.eq((A.HasAura(32)), true, "seen with its time")
		w.state.units.target = nil
		w.state.auras.player = {}
		w.state.units.player.combat = true
		A.WipeAuraScans()
		H.same({ A.HasAura(32) }, { true, 9999 }, "in combat: trusted")
		w.state.units.player.combat = false
		A.WipeAuraScans()
		H.same({ A.HasAura(32) }, { false, 0 }, "out of combat: released")
		A.NoteSelfBuff(32)
		w:advance(2)
		w.aura("player", { name = "Readable Other", spellId = 77 })
		w.state.units.player.combat = true
		A.WipeAuraScans()
		H.same({ A.HasAura(32) }, { true, 9999 }, "readable list without it, in combat: trusted")
		H.same({ A.HasAura(999) }, { false, 0 }, "unknown spell")
		w.state.secret.auras = true
		A.WipeAuraScans()
		H.same({ A.HasAura(999) }, { false, 0 }, "unknown spell, hidden auras")
	end)

	it("keeps a just-cast buff and its family for a second", function()
		local w, _, A = api("PALADIN", function(w)
			w.spell(33, { name = "Seal of Wisdom", helpful = true })
		end)
		w.state.units.target = nil
		A.NoteSelfBuff(33)
		H.eq((A.HasAura(33)), false, "readable absence")
		w.state.units.player.combat = true
		A.WipeAuraScans()
		H.eq((A.HasAura(33)), true, "cast less than a second ago")
		w.state.units.player.combat = false
		w:advance(2)
		A.WipeAuraScans()
		H.eq((A.HasAura(33)), false)
	end)

	it("does not remember attacks or heals on someone else", function()
		local w, ns, A = api("PALADIN", function(w)
			w.spell(34, { name = "Smite", harmful = true })
			w.spell(35, { name = "Holy Light", helpful = true })
		end)
		ns.HEAL_SPELL_IDS[35] = true
		w.unit("target", { health = 50, maxHealth = 100, reaction = 5 })
		A.NoteSelfBuff(34)
		A.NoteSelfBuff(35)
		w.aura("player", { name = "X", spellId = 1 })
		w.state.secret.auras = true
		H.eq((A.HasAura(34)), false)
		H.eq((A.HasAura(35)), false)
	end)

	it("remembers target debuffs from casts and readable sightings", function()
		local w, ns, A = api("WARLOCK", function(w)
			w.spell(40, { name = "Agony", harmful = true })
			w.spell(41, { name = "Immolate", harmful = true })
		end)
		ns.SPELL_HOLD[41] = 15
		A.NoteTargetDebuff(nil)
		A.NoteTargetDebuff(wow.SECRET)
		local d = w.aura("target", { name = "Agony", spellId = 40, harmful = true, expirationTime = w.state.time + 24 })
		H.eq((A.HasAura(40, "target", "HARMFUL")), true, "seen: remembered for 24 s")
		A.NoteTargetDebuff(41)
		w.state.secret.auras = true
		w:advance(14)
		H.eq((A.HasAura(41, "target", "HARMFUL")), true, "15 s hold length")
		w:advance(2)
		H.eq((A.HasAura(41, "target", "HARMFUL")), false)
		H.eq((A.HasAura(40, "target", "HARMFUL")), true)
		w.state.units.target.guid = "Creature-0-9"
		H.eq((A.HasAura(40, "target", "HARMFUL")), false, "new target")
		A.NoteTargetDebuff(40)
		w.state.units.target.guid = "Creature-0-10"
		A.NoteTargetDebuff(41)
		H.eq((A.HasAura(40, "target", "HARMFUL")), false, "memory moved to the new target")
		w.state.units.target = nil
		A.NoteTargetDebuff(40)
		local _ = d
		w:target({ secretGuid = true })
		w.spell(45, { name = "Old Curse", harmful = true, override = 46 })
		w.spell(46, { name = "New Curse", harmful = true })
		A.NoteTargetDebuff(45)
		H.eq((A.HasAura(46, "target", "HARMFUL")), true, "remembered under the resolved ID too")
	end)

	it("remembers by name only for spells without a number ID", function()
		local w, _, A = api("WARLOCK", function(w)
			w.spell(42, { name = "" })
		end)
		A.NoteTargetDebuff("Agony")
		A.NoteTargetDebuff(42)
		w.aura("target", { name = "Z", spellId = 1, harmful = true })
		w.state.secret.auras = true
		H.eq((A.HasAura(42, "target", "HARMFUL")), true, "remembered by ID")
		H.eq((A.HasAura(43, "target", "HARMFUL")), false, "no name, no memory")
	end)
end)

describe("API combo points", function()
	it("takes the best of power, target points and the cast count", function()
		local w, ns, A = api("ROGUE", function(w)
			w.spell(1752, { name = "Sinister Strike" })
			w.spell(2098, { name = "Eviscerate" })
		end)
		H.same({ A.ComboDebug() }, { 0, "count" })
		A.NoteComboCast(1752)
		A.NoteComboCast(1752)
		H.same({ A.ComboDebug() }, { 2, "count" })
		w.state.units.player.power[4] = 3
		H.same({ A.ComboDebug() }, { 3, "power" })
		w.state.combo = 4
		H.same({ A.ComboDebug() }, { 4, "target" })
		A.NoteComboCast(2098)
		w.state.units.player.power[4] = 0
		w.state.combo = 0
		H.eq(A.Combo(), 0, "finisher spends the count")
		for _ = 1, 7 do
			A.NoteComboCast(1752)
		end
		H.eq(A.Combo(), 5, "capped at 5")
		A.ResetComboEstimate()
		H.eq(A.Combo(), 0)
		A.NoteComboCast(nil)
		A.NoteComboCast(999)
		w.env.GetComboPoints = nil
		H.eq(A.Combo(), 0)
		local _ = ns
	end)

	it("waits until the spell names are loaded", function()
		local w, _, A = api("ROGUE")
		w.spell(1, { name = "Something" })
		A.NoteComboCast(1)
		H.eq(A.Combo(), 0)
	end)
end)
