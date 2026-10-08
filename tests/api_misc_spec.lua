local wow = require("wow")
local H = require("helpers")

local CORE = wow.API_FILES

local function api(class, setup)
	local w = wow.new()
	w:player(class or "WARRIOR")
	if setup then
		setup(w)
	end
	local ns = w:load(CORE)
	ns.ClassToken = function()
		return w.state.class
	end
	return w, ns, ns.API
end

describe("API health", function()
	it("reads plain values, the percentage, or reports hidden", function()
		local w, ns, A = api()
		w.state.units.player.health = 40
		H.eq(A.Health(), 40)
		H.eq(A.HealthHidden(), false)
		H.eq(A.HealthHiddenFor("player"), false)
		w.state.secret.health = true
		H.eq(A.Health("player"), 40, "from UnitHealthPercent")
		H.eq(A.HealthHiddenFor("player"), false)
		w.state.secret.healthPercent = true
		H.eq(A.Health("player"), 100, "hidden: 100")
		H.eq(A.HealthHidden(), true)
		H.eq(A.HealthHiddenFor("player"), true)
		w:target({ health = 20 })
		H.eq(A.Health("target"), 100)
		w.state.secret.healthPercent = false
		H.eq(A.Health("target"), 20, "target percentage")
		w.env.UnitHealthPercent = nil
		H.eq(A.Health("target"), 100)
		H.eq(A.HealthHiddenFor("target"), true)
		local _ = ns
	end)

	it("remembers the player's max health and parses heal sizes", function()
		local w, ns, A = api("PRIEST", function(w)
			w.spell(1, { name = "Lesser Heal", desc = "Heal your target for 46 to 56." })
			w.spell(2, { name = "Renew", desc = "Heals the target of 45 damage over 15 sec." })
			w.spell(3, { name = "Smite", desc = "Smite an enemy for 13 to 17 Holy damage." })
			w.spell(4, { name = "Empty", desc = "" })
			w.spell(5, { name = "Big Heal", desc = "Heals for 1,234 to 1,300." })
		end)
		w.state.units.player.maxHealth = 200
		H.eq(A.MaxHealth(), 200)
		w.state.secret.health = true
		H.eq(A.MaxHealth("player"), 200, "remembered")
		H.eq(A.MaxHealth("target"), nil)
		w.state.secret.health = false
		H.eq(A.HealAmount(1), 51)
		H.eq(A.HealAmount(1), 51, "cached")
		H.eq(A.HealAmount(2), 45)
		H.eq(A.HealAmount(3), nil)
		H.eq(A.HealAmount(3), nil, "cached miss")
		H.eq(A.HealAmount(4), nil, "text not loaded")
		H.eq(A.HealAmount(5), 1267)
		w.env.C_Spell.GetSpellDescription = nil
		A.InvalidateSpells(false)
		H.eq(A.HealAmount(1), nil)
		local _ = ns
	end)

	it("derives the smart heal threshold", function()
		local w, ns, A = api("PRIEST", function(w)
			w.spell(1, { name = "Lesser Heal", desc = "Heal your target for 50 to 50." })
			w.spell(2, { name = "Greater Heal", desc = "Heal your target for 900 to 900." })
			w.spell(3, { name = "Tiny", desc = "Heal your target for 1 to 1." })
		end)
		w.state.units.player.maxHealth = 1000
		H.eq(A.AutoHealThreshold(1, "player", 80), 92, "capped at 92")
		H.eq(A.AutoHealThreshold(2, "player", 80), 30, "floored at 30")
		w.state.units.player.maxHealth = 200
		H.eq(A.AutoHealThreshold(1, "player", 80), 75)
		H.eq(A.AutoHealThreshold(1, "player", 40), 40, "emergency keeps its own")
		H.eq(A.AutoHealThreshold(99, "player", 80), 80, "no heal size")
		H.eq(A.AutoHealThreshold(1, nil, 80), 75)
		ns.db = { autoHeal = false }
		H.eq(A.AutoHealThreshold(1, "player", 80), 80)
		local _ = w
	end)

	it("knows when mana is hidden", function()
		local w, _, A = api()
		H.eq(A.ManaHidden(), false)
		w.state.secret.power = true
		H.eq(A.ManaHidden(), true)
	end)
end)

describe("API pet and UI errors", function()
	it("tracks a dead hunter pet from the unit and the errors", function()
		local w, _, A = api("HUNTER")
		H.eq(A.PetDead(), false)
		w.unit("pet", { health = 0, maxHealth = 100, dead = true })
		H.eq(A.PetDead(), true)
		w.state.units.pet = nil
		H.eq(A.PetDead(), true, "remembered after the unit is gone")
		H.eq(A.NoteUIError("You do not have a pet."), true)
		H.eq(A.PetDead(), false)
		H.eq(A.NoteUIError("Your pet is dead."), true)
		H.eq(A.PetDead(), true)
		w.unit("pet", { health = 100, maxHealth = 100 })
		H.eq(A.PetDead(), false, "a live pet clears it")
		H.eq(A.NoteUIError("Out of range."), false)
		H.eq(A.NoteUIError(nil), false)
		H.eq(A.NoteUIError(wow.SECRET_STRING), false)
	end)

	it("remembers 'not behind' for 3 s on that target", function()
		local w, _, A = api()
		H.eq(A.NotBehindRecently(), false)
		w:target()
		H.eq(A.NoteUIError("You must be behind your target."), true)
		H.eq(A.NotBehindRecently(), true)
		w.state.units.target.guid = "Creature-0-77"
		H.eq(A.NotBehindRecently(), false, "other target")
		w.state.units.target.secretGuid = true
		H.eq(A.NotBehindRecently(), true, "target unknown")
		w:advance(4)
		H.eq(A.NotBehindRecently(), false, "expired")
		w.state.units.target.secretGuid = false
		w.env.SPELL_FAILED_NOT_BEHIND = nil
		H.eq(A.NoteUIError("Behind you!"), true, "text match")
	end)
end)

describe("API creature and target class", function()
	it("maps creature types and blocks or matches lists", function()
		local w, _, A = api()
		H.eq(A.CreatureBlocked(nil), false)
		H.eq(A.CreatureMatch(nil), true)
		H.eq(A.CreatureBlocked(true), false, "no target")
		H.eq(A.CreatureMatch({ "undead" }), true, "unknown type lets it through")
		w:target({ creatureType = "Mechanical" })
		H.eq(A.CreatureBlocked(true), true)
		H.eq(A.CreatureBlocked(false), false)
		H.eq(A.CreatureBlocked("machine"), true, "alias")
		H.eq(A.CreatureBlocked({ "undead", 5, "mechanical" }), true)
		H.eq(A.CreatureBlocked({ "undead" }), false)
		H.eq(A.CreatureMatch("mechanical"), true)
		H.eq(A.CreatureBlocked(7), false, "not a list")
		H.eq(A.CreatureBlocked({ "" }), false, "empty name")
		w.state.units.target.creatureType = "Beast"
		H.eq(A.CreatureBlocked(true), false)
		H.eq(A.CreatureMatch({ "beast" }), true, "unknown canon keeps the name")
		w.state.units.target.creatureType = ""
		H.eq(A.CreatureBlocked(true), false)
		w.state.secret.creature = true
		H.eq(A.CreatureBlocked(true), false, "hidden type")
	end)

	it("treats elites, bosses and much higher levels as raid mobs", function()
		local w, _, A = api()
		H.eq(A.IsRaidmob(), false)
		w:target({ classification = "elite" })
		H.eq(A.IsRaidmob(), true)
		w.state.units.target.classification = "normal"
		H.eq(A.IsRaidmob(), false)
		w.state.units.target.level = 13
		H.eq(A.IsRaidmob(), true)
		w.state.units.target.level = -1
		H.eq(A.IsRaidmob(), true, "skull level")
		w.env.UnitClassification = function()
			error("boom")
		end
		w.env.UnitLevel = function()
			error("boom")
		end
		H.eq(A.IsRaidmob(), false)
	end)
end)

describe("API totems", function()
	local function shaman()
		return api("SHAMAN", function(w)
			w.spell(3599, { name = "Searing Totem" })
			w.spell(8075, { name = "Strength of Earth Totem" })
			w.spell(8190, { name = "Magma Totem" })
			w.spell(5675, { name = "Mana Spring Totem" })
			w.spell(9999, { name = "Mystery Totem" })
			w.spell(9998, { name = "Not A Totem" })
		end)
	end

	it("reads readable slots and keeps its own record in combat", function()
		local w, _, A = shaman()
		H.eq(A.TotemRemain(nil), 0)
		H.eq(A.TotemRemain(424242), 0, "no name")
		w.state.totems[1] = { name = "Searing Totem", start = w.state.time, duration = 35 }
		A.NoteTotemCast(3599)
		w:advance(10)
		H.eq(A.TotemRemain(3599), 25)
		w.state.secret.totems = true
		w:advance(5)
		H.eq(A.TotemRemain(3599), 20, "memory with the learned 35 s")
		A.NoteTotemCast(8075)
		H.eq(A.TotemRemain(8075), 120, "table length")
		A.NoteTotemCast(8190)
		H.eq(A.TotemRemain(3599), 20, "the fire slot holds Magma: Searing does not replace it")
		H.eq(A.TotemRemain(5675), 0)
		w.state.position = { 40, 0, 1 }
		H.eq(A.TotemRemain(8075), 0, "walked away")
		w.state.position = { 0, 0, 2 }
		H.eq(A.TotemRemain(8075), 0, "other map")
		w.state.position = nil
		H.eq(A.TotemRemain(8075), 120, "no position: still counted")
		A.ClearTotems()
		H.eq(A.TotemRemain(8075), 0)
		-- A totem first seen by a readable read stands where you are.
		w.state.position = { 0, 0, 1 }
		w.state.secret.totems = false
		w.state.totems[2] = { name = "Strength of Earth Totem", start = w.state.time, duration = 300 }
		H.eq(A.TotemRemain(8075), 300)
		w.state.position = { 40, 0, 1 }
		w.state.secret.totems = true
		H.eq(A.TotemRemain(8075), 0, "fresh read remembered the spot: walked away")
	end)

	it("does not replace another totem you dropped in the same slot", function()
		local w, ns, A = shaman()
		w.spell(8071, { name = "Stoneskin Totem" })
		w.spell(2484, { name = "Earthbind Totem" })
		w.state.secret.totems = true
		A.NoteTotemCast(8071)
		H.eq(A.TotemRemain(8071), 300)
		A.NoteTotemCast(2484)
		H.eq(A.TotemRemain(2484), 45)
		H.eq(A.TotemRemain(8071), 45, "the earth slot is busy with Earthbind")
		w:advance(50)
		H.eq(A.TotemRemain(8071), 0, "Earthbind ran out")
		H.eq(A.TotemRemain(3599), 0, "another slot is not affected")
		local _ = ns
	end)

	it("does not ask for a totem whose effect is still on you", function()
		local w, ns, A = shaman()
		w.spell(8071, { name = "Stoneskin Totem" })
		ns.TOTEM_INFO[8071] = { slot = 2, seconds = 120 }
		A.NoteTotemCast(8071)
		w.state.position = { 60, 0, 1 }
		H.eq(A.TotemRemain(8071), 0, "walked away, no effect on you")
		w.aura("player", { name = "Stoneskin", spellId = 8072, expirationTime = w.state.time + 40 })
		H.eq(A.TotemRemain(8071), 40, "the effect is still on you")
		-- Combat hides the aura: the end seen before is remembered.
		w.state.auras.player = {}
		w.state.units.player.combat = true
		w:advance(10)
		H.eq(A.TotemRemain(8071), 30, "the effect seen before the fight still runs")
		w:advance(40)
		H.eq(A.TotemRemain(8071), 0, "and ends")
		w.state.units.player.combat = false
		w.aura("player", { name = "Windfury Totem", spellId = 8512 })
		w.spell(8512, { name = "Windfury Totem" })
		A.NoteTotemCast(8512)
		w.state.position = { 120, 0, 1 }
		H.eq(A.TotemRemain(8512), 9999, "an effect named like the totem")
		w.state.secret.auras = true
		H.eq(A.TotemRemain(8512), 0, "effect unreadable in combat: nothing to go by")
	end)

	it("learns slots from events and ignores unknown casts", function()
		local w, _, A = shaman()
		A.NoteTotemCast(nil)
		A.NoteTotemCast(wow.SECRET)
		A.NoteTotemCast(424242)
		A.NoteTotemCast(9998)
		A.NoteTotemCast(9999)
		H.eq(A.TotemRemain(9999), 0, "no slot known yet")
		w.state.totems[2] = { name = "Mystery Totem", start = w.state.time, duration = 50 }
		A.NoteTotemSlot(2)
		A.NoteTotemSlot("x")
		w.state.totems[2] = nil
		w.state.totems[3] = { name = "", start = 0, duration = 0 }
		A.NoteTotemSlot(3)
		A.NoteTotemSlot(2)
		w.state.secret.totems = true
		A.NoteTotemSlot(2)
		A.NoteTotemCast(9999)
		H.eq(A.TotemRemain(9999), 50, "learned slot and length")
		w.state.secret.totems = false
		w.state.totems[2] = { name = "Mystery Totem", start = w.state.time, duration = 0 }
		H.eq(A.TotemRemain(9999), 0, "zero length")
		w.env.GetTotemInfo = function()
			error("boom")
		end
		H.eq(A.TotemRemain(9999), 0)
		w.env.GetTotemInfo = nil
		H.eq(A.TotemRemain(9999), 0)
	end)

	it("matches totems by family name and finds the table by name", function()
		local w, ns, A = shaman()
		w.spell(90030, { name = "Searing Totem" })
		w.state.totems[1] = { name = "Searing Totem II", start = w.state.time, duration = 40 }
		H.eq(A.TotemRemain(90030), 40, "family 'searing'")
		w.state.totems[1] = { name = "Totem of Wrath", start = w.state.time, duration = 40 }
		w.spell(90031, { name = "Totem of Wrath" })
		H.eq(A.TotemRemain(90031), 40, "'totem of' prefix")
		w.state.totems = {}
		w.state.secret.totems = true
		A.NoteTotemCast(90030)
		H.eq(A.TotemRemain(90030), 30, "table entry found by name")
		ns.TOTEM_INFO = nil
		A.NoteTotemCast(90031)
		H.eq(A.TotemRemain(90030), 0, "same slot: replaced")
		w.env.UnitPosition = function()
			error("boom")
		end
		H.eq(A.TotemRemain(90031), 40)
		w.env.UnitPosition = function()
			return wow.SECRET, 1, 0, 1
		end
		H.eq(A.TotemRemain(90031), 40)
	end)
end)

describe("API who the target attacks and melee range", function()
	it("reads threat first, then the target's target", function()
		local w, _, A = api()
		H.eq(A.TargetAttacksYou(), false, "no target")
		w:target({ threat = 3 })
		H.eq(A.TargetAttacksYou(), true)
		w.state.units.target.threat = 1
		H.eq(A.TargetAttacksYou(), false)
		w.state.units.target.threat = nil
		H.eq(A.TargetAttacksYou(), false, "no target's target")
		w.state.units.targettarget = w.state.units.player
		H.eq(A.TargetAttacksYou(), true)
		w.state.secret.compare = true
		H.eq(A.TargetAttacksYou(), nil, "unknown")
		w.env.UnitThreatSituation = nil
		H.eq(A.TargetAttacksYou(), nil)
	end)

	it("decides melee range from bands, a class probe and interact", function()
		local w, ns, A = api("ROGUE")
		H.eq(A.TargetInMelee(), false, "no target")
		w:target({ distance = 20 })
		H.eq(A.TargetInMelee(), false, "far")
		w.state.units.target.distance = 3
		H.eq(A.TargetInMelee(), true, "close")
		w.state.units.target.distance = 7
		local state
		A.RangeState = function()
			return state
		end
		for _, class in ipairs({ "HUNTER", "SHAMAN", "WARRIOR", "ROGUE", "DRUID", "PALADIN" }) do
			w.state.class = class
			state = "in"
			H.eq(A.TargetInMelee(), true, class)
			state = "out"
			H.eq(A.TargetInMelee(), false, class)
		end
		state = "unknown"
		H.eq(A.TargetInMelee(), true, "7 yd, unknown probe: duel range counts")
		w.state.class = "MAGE"
		w.env.UnitDistanceSquared = function()
			return 0, false
		end
		w.state.units.target.distance = 2
		H.eq(A.TargetInMelee(), true, "duel range")
		w.env.CheckInteractDistance = function(_, index)
			return index == 3
		end
		H.eq(A.TargetInMelee(), true, "within 11 yd band")
		w.env.CheckInteractDistance = function(_, index)
			if index == 1 then
				return true
			end
			return nil
		end
		H.eq(A.TargetInMelee(), false)
		w.state.units.target.hostile = false
		w.state.units.target.reaction = 5
		H.eq(A.TargetInMelee(), false, "friendly")
		local _ = ns
	end)
end)

describe("API pet reminders", function()
	it("asks hunters and warlocks to summon or send the pet", function()
		local w, ns, A = api("HUNTER")
		H.eq(A.CombatNotice(), nil, "out of combat")
		w.state.units.player.combat = true
		H.eq(A.CombatNotice(), nil, "no Call Pet yet")
		w.spell(ns.Spell.Hunter.CallPet, { name = "Call Pet" })
		A.InvalidateSpells(true)
		H.eq(A.CombatNotice(), "NOTICE_CALL_PET")
		w.unit("pet", { health = 1, maxHealth = 1 })
		H.eq(A.CombatNotice(), nil, "no enemy")
		w:target()
		H.eq(A.CombatNotice(), "NOTICE_PET_ASSIST", "pet has no target")
		w.unit("pettarget", { health = 1, maxHealth = 1 })
		H.eq(A.CombatNotice(), "NOTICE_PET_ASSIST", "pet not fighting")
		w.state.units.pet.combat = true
		H.eq(A.CombatNotice(), nil)
		w.state.class = "WARLOCK"
		w.spell(ns.Spell.Warlock.SummonImp, { name = "Summon Imp" })
		A.InvalidateSpells(true)
		w.state.units.pet = nil
		H.eq(A.CombatNotice(), "NOTICE_SUMMON_DEMON")
		w.state.class = "MAGE"
		H.eq(A.CombatNotice(), nil)
	end)
end)

describe("API combat, eating and idle", function()
	it("reads combat, food and idle states", function()
		local w, _, A = api()
		H.eq(A.InCombat(), false)
		w.env.UnitAffectingCombat = function()
			return wow.SECRET_BOOL
		end
		H.eq(A.InCombat(), true, "secret but set")
		w.env.UnitAffectingCombat = function()
			error("boom")
		end
		H.eq(A.InCombat(), false)
		H.eq(A.IsEating(), false)
		w.aura("player", { name = "Food", spellId = 1 })
		H.eq(A.IsEating(), true)
		w.state.auras.player = { { name = wow.SECRET_STRING } }
		w.env.C_UnitAuras.GetAuraDataByIndex = function(_, i)
			if i == 1 then
				return { name = wow.SECRET_STRING }
			end
		end
		H.eq(A.IsEating(), false)
		w.env.C_UnitAuras = nil
		H.eq(A.IsEating(), false)
	end)

	it("hides the glow when dead, flying, mounted, eating or resting", function()
		local w, ns, A = api()
		ns.db = {}
		H.eq(A.ShouldHideIdle(), false)
		w.state.mounted = true
		H.eq(A.ShouldHideIdle(), true)
		w.state.mounted = false
		w.state.resting = true
		H.eq(A.ShouldHideIdle(), true)
		w.state.units.player.combat = true
		H.eq(A.ShouldHideIdle(), false, "resting in combat")
		w.aura("player", { name = "Drink", spellId = 1 })
		H.eq(A.ShouldHideIdle(), true)
		w.state.auras.player = {}
		w.env.IsMounted = nil
		H.eq(A.ShouldHideIdle(), false, "no mount API")
		ns.db = nil
		H.eq(A.ShouldHideIdle(), false)
	end)
end)

describe("API casts", function()
	it("reads the player's remaining cast and current spell", function()
		local w, _, A = api(nil, function(w)
			w.spell(1, { name = "Frostbolt" })
		end)
		H.eq(A.CastRemain(), 0)
		H.eq(A.CastingSpell(1), false)
		w.state.units.player.casting = { name = "Frostbolt", endTime = (w.state.time + 2) * 1000 }
		H.eq(A.CastRemain(), 2)
		H.eq(A.CastingSpell(1), true)
		H.eq(A.CastingSpell(999), false, "no name")
		w.state.units.player.casting = { name = "Frostbolt", endTime = w.state.time + 1 }
		H.eq(A.CastRemain(), 1, "seconds")
		w.state.units.player.casting = { name = "Frostbolt", endTime = w.state.time - 1 }
		H.eq(A.CastRemain(), 0, "over")
		w.state.units.player.casting = nil
		w.state.units.player.channel = { name = "Frostbolt", endTime = (w.state.time + 3) * 1000 }
		H.eq(A.CastRemain(), 3, "channel")
		H.eq(A.CastingSpell(1), true)
		w.state.units.player.channel = { name = "Frostbolt", endTime = wow.SECRET }
		H.eq(A.CastRemain(), 0)
		w.env.UnitCastingInfo = function()
			return wow.SECRET_STRING
		end
		w.env.UnitChannelInfo = nil
		H.eq(A.CastRemain(), 0)
		H.eq(A.CastingSpell(1), false)
		w.env.UnitCastingInfo = nil
		H.eq(A.CastRemain(), 0)
	end)

	it("knows when the target casts something interruptible", function()
		local w, ns, A = api()
		H.eq(A.TargetCasting(), false, "no target")
		w:target()
		H.eq(A.TargetCasting(), false)
		w.state.units.target.casting = { name = "Fireball" }
		H.eq(A.TargetCasting(), true)
		w.state.units.target.casting = { name = "Shield", notInterruptible = true }
		H.eq(A.TargetCasting(), false, "uninterruptible cast")
		w.state.units.target.casting = nil
		w.state.units.target.channel = { name = "Drain", notInterruptible = true }
		H.eq(A.TargetCasting(), false, "uninterruptible channel")
		w.state.units.target.channel = { name = "Drain" }
		H.eq(A.TargetCasting(), true)
		w.state.units.target.channel = nil
		ns.API.castTarget = true
		H.eq(A.TargetCasting(), true, "cast seen through events")
		w.env.UnitCastingInfo = nil
		w.env.UnitChannelInfo = function()
			error("boom")
		end
		ns.API.castTarget = false
		H.eq(A.TargetCasting(), false)
	end)
end)

describe("API purge and dispel", function()
	it("finds magic or stealable buffs on the target", function()
		local w, _, A = api()
		H.eq(A.Purgable(), false, "no target")
		w:target()
		H.eq(A.Purgable(), false)
		w.aura("target", { name = "Armor", spellId = 1 })
		H.eq(A.Purgable(), false)
		w.aura("target", { name = "Shield", spellId = 2, dispelName = "Magic" })
		H.eq(A.Purgable(), true)
		H.eq(A.Purgable(true), false, "mage: stealable only")
		w.aura("target", { name = "Steal", spellId = 3, isStealable = true })
		H.eq(A.Purgable(true), true)
		w.state.auras.target = { { name = "Steal", spellId = 3, isStealable = true } }
		H.eq(A.Purgable(), true)
		w.env.C_UnitAuras = nil
		H.eq(A.Purgable(), false)
	end)

	it("finds dispellable debuffs on you and friends", function()
		local w, _, A = api()
		H.eq(A.HasDebuffType(nil), false)
		H.eq(A.HasDebuffType({ "Magic" }), false)
		w.aura("player", { name = "Poison", spellId = 1, harmful = true, dispelName = "Poison" })
		H.eq(A.HasDebuffType({ "Magic" }), false)
		H.eq(A.HasDebuffType({ "Poison" }), true)
		H.eq(A.HasDebuffType({ "Poison" }, "player"), true)
		w:target()
		w.aura("target", { name = "Curse", spellId = 2, harmful = true, dispelName = "Curse" })
		H.eq(A.HasDebuffType({ "Curse" }, "target"), false, "enemy")
		w.unit("party1", { health = 1, maxHealth = 1, reaction = 5 })
		w.aura("party1", { name = "Curse", spellId = 2, harmful = true, dispelName = "Curse" })
		H.eq(A.HasDebuffType({ "Curse" }, "party1"), true)
		w.env.C_UnitAuras = nil
		H.eq(A.HasDebuffType({ "Curse" }, "party1"), false)
	end)
end)

describe("API weapon enchants", function()
	it("reads the temporary enchant per hand", function()
		local w, _, A = api("ROGUE")
		H.same({ A.WeaponEnchant(false) }, { false, 0, 0 })
		w.state.enchants[16] = { enchantID = 323, remainingTimeMs = 600000 }
		H.same({ A.WeaponEnchant(false) }, { true, 600, 323 })
		w.state.enchants[17] = { enchantID = wow.SECRET, remainingTimeMs = wow.SECRET }
		H.same({ A.WeaponEnchant(true) }, { true, 9999, nil })
	end)

	it("falls back to the old weapon enchant APIs", function()
		local w, _, A = api("ROGUE")
		w.env.C_PaperDollInfo = nil
		w.state.enchants[16] = { enchantID = 323, remainingTimeMs = 600000 }
		H.same({ A.WeaponEnchant(false) }, { true, 600, 323 })
		H.same({ A.WeaponEnchant(true) }, { false, 0, 0 })
		w.state.enchants[17] = { remainingTimeMs = 5000 }
		H.same({ A.WeaponEnchant(true) }, { true, 5000 / 1000 * 1000 / 1000 * 1000 > 10000 and 5 or 5000, nil })
		w.env.GetWeaponEnchantInfo = function()
			return {
				hasMainHandEnchant = true,
				mainHandExpiration = 20000,
				hasOffHandEnchant = wow.SECRET_BOOL,
				offHandExpiration = 0,
			}
		end
		H.same({ A.WeaponEnchant(false) }, { true, 20, nil })
		H.same({ A.WeaponEnchant(true) }, { nil, 0, nil }, "unknown")
		w.env.GetWeaponEnchantInfo = function()
			return { [1] = { "odd" } }
		end
		H.same({ A.WeaponEnchant(false) }, { nil, 0, nil })
		w.env.GetWeaponEnchantInfo = function()
			error("boom")
		end
		w.env.C_Item.GetWeaponEnchantInfo = function()
			return false, 0, 0, nil, "x", "y", 0, "1"
		end
		H.same({ A.WeaponEnchant(false) }, { false, 0, 0 })
		H.same({ A.WeaponEnchant(true) }, { true, 9999, 1 }, "text enchant ID")
		w.env.C_Item.GetWeaponEnchantInfo = nil
		w.env.GetWeaponEnchantInfo = nil
		H.same({ A.WeaponEnchant(false) }, { nil, 0, nil })
	end)

	it("copes with failing or odd paper doll answers", function()
		local w, _, A = api("ROGUE")
		w.env.C_PaperDollInfo.GetTemporaryEnchantmentInfo = function()
			error("boom")
		end
		w.env.GetWeaponEnchantInfo = nil
		H.same({ A.WeaponEnchant(false) }, { nil, 0, nil })
		w.env.C_PaperDollInfo.GetTemporaryEnchantmentInfo = function()
			return "odd"
		end
		H.same({ A.WeaponEnchant(false) }, { nil, 0, nil })
	end)

	it("searches the weapon tooltips", function()
		local w, _, A = api("ROGUE")
		H.eq(A.WeaponTooltipHas(nil), false)
		H.eq(A.WeaponTooltipHas({}), false)
		H.eq(A.WeaponTooltipHas({ "poison" }), false, "no tooltip")
		A.ClearWeaponTooltipCache()
		w.state.tooltips = {
			[16] = { { leftText = "Instant Poison (30 min)" }, { leftText = wow.SECRET_STRING } },
		}
		H.eq(A.WeaponTooltipHas({ "", 5, "instant poison" }), true)
		H.eq(A.WeaponTooltipHas({ "deadly" }), false, "cached texts")
		w.env.C_TooltipInfo = nil
		A.ClearWeaponTooltipCache()
		H.eq(A.WeaponTooltipHas({ "instant" }), false)
	end)
end)
