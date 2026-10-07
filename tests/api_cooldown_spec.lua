local wow = require("wow")
local H = require("helpers")

local CORE = wow.API_FILES

local function api(setup)
	local w = wow.new()
	w:player("SHAMAN")
	if setup then
		setup(w)
	end
	local ns = w:load(CORE)
	return w, ns, ns.API
end

describe("API base cooldowns", function()
	it("reads seconds or milliseconds and ignores GCD-only spells", function()
		local w, ns, A = api(function(w)
			w.spell(1, { name = "Seconds", baseCooldown = 8 })
			w.spell(2, { name = "Millis", baseCooldown = 10000 })
			w.spell(3, { name = "Gcd", baseCooldown = 1500 })
			w.spell(4, { name = "GcdSec", baseCooldown = 1.5 })
			w.spell(5, { name = "Nothing" })
		end)
		H.eq(A.SpellCooldownSec(1), 8)
		H.eq(A.SpellCooldownSec(2), 10)
		H.eq(A.SpellCooldownSec(3), 0)
		H.eq(A.SpellCooldownSec(4), 0)
		H.eq(A.SpellCooldownSec(5), 0)
		H.eq(A.SpellCooldownSec(nil), 0)
		H.eq(A.SpellCooldownSec(ns.Spell.Paladin.Judgement), 8, "table fallback")
		-- Only the C_Spell form, as a table and as numbers.
		w.env.GetSpellBaseCooldown = nil
		w.env.C_Spell.GetSpellBaseCooldown = function(id)
			if id == 1 then
				return { duration = 12000, gcd = 1500 }
			end
			if id == 2 then
				return { cooldown = 1000 }
			end
			if id == 6 then
				return wow.SECRET, 1500
			end
			return 7, 1
		end
		H.eq(A.SpellCooldownSec(1), 12)
		H.eq(A.SpellCooldownSec(2), 0, "below the GCD")
		w.spell(6, { name = "Hidden" })
		w.spell(7, { name = "Short", known = true })
		H.eq(A.SpellCooldownSec(6), 0, "secret base cooldown")
		H.eq(A.SpellCooldownSec(7), 7)
		w.env.C_Spell.GetSpellBaseCooldown = function()
			return 0.5, 1
		end
		H.eq(A.SpellCooldownSec(7), 0)
		w.env.C_Spell.GetSpellBaseCooldown = function()
			error("boom")
		end
		H.eq(A.SpellCooldownSec(7), 0)
		w.env.C_Spell.GetSpellBaseCooldown = function()
			return { duration = 0 }
		end
		H.eq(A.SpellCooldownSec(7), 0)
	end)

	it("finds fallback cooldowns by ID, shock group and name", function()
		local w, ns, A = api(function(w)
			w.spell(8042, { name = "Earth Shock" })
			w.spell(8050, { name = "Flame Shock" })
			w.spell(90001, { name = "Flame Shock" })
			w.spell(90002, { name = "Judgement" })
		end)
		w.spell(ns.Spell.Paladin.Judgement, { name = "Judgement" })
		H.eq(A.SpellCooldownSec(90001), 6, "shock group by name")
		H.eq(A.SpellCooldownSec(90002), 8, "table by name")
		ns.COOLDOWN_GROUPS = nil
		ns.COOLDOWNS = nil
		H.eq(A.SpellCooldownSec(90002), 0)
	end)
end)

describe("API rotation actions", function()
	it("treats fillers, auto-repeat and racials as no action", function()
		local _, _, A = api(function(w)
			w.spell(1, { name = "Cooldown", baseCooldown = 8 })
			w.spell(2, { name = "Spam" })
		end)
		H.eq(A.IsFallback(nil), false)
		H.eq(A.IsFallback({ swing = true }), true)
		H.eq(A.IsRotationAction(1, nil, true), false)
		H.eq(A.IsRotationAction(1, { filler = true }), false)
		H.eq(A.IsRotationAction(1, { autoRepeat = true }), false)
		for _, opt in ipairs({
			{ heal = true },
			{ nodebuff = true },
			{ proc = true },
			{ nopet = true },
			{ hp = 50 },
			{ anybuff = {} },
		}) do
			H.eq(A.IsRotationAction(2, opt), true)
		end
		H.eq(A.IsRotationAction(1, nil), true, "own cooldown")
		H.eq(A.IsRotationAction(2, {}), false)
	end)
end)

describe("API cast tracking and cooldowns", function()
	it("tracks the base cooldown after a cast, also for the shock group", function()
		local w, ns, A = api(function(w)
			w.spell(8042, { name = "Earth Shock", baseCooldown = 6000 })
			w.spell(8050, { name = "Flame Shock" })
			w.spell(10, { name = "Nova", baseCooldown = 25000 })
		end)
		A.NoteSpellCast(nil)
		A.NoteSpellCast(wow.SECRET)
		A.NoteSpellCast(8042)
		H.eq(A.Cooldown(8042), 6)
		H.eq(A.Cooldown(8050), 6, "shared shock cooldown")
		w:advance(7)
		H.eq(A.Cooldown(8042), 0)
		H.eq(A.Cooldown(nil), 0)
		A.NoteSpellCast(10)
		w:advance(1)
		H.eq(A.Cooldown(10), 24)
		H.eq(ns.API.lastCastAt ~= nil, true)
	end)

	it("learns a cooldown from the client and reuses it", function()
		local w, _, A = api(function(w)
			w.spell(11, { name = "Learned", cooldown = { 1000, 30 } })
		end)
		H.eq(A.Cooldown(11), 30, "client cooldown")
		w.state.spells[11].cooldown = nil
		A.NoteSpellCast(11)
		H.eq(A.Cooldown(11), 30, "learned 30 s used for tracking")
	end)

	it("prefers a readable real cooldown over the tracked estimate", function()
		local w, _, A = api(function(w)
			w.spell(12, { name = "Talented", baseCooldown = 8000 })
		end)
		A.NoteSpellCast(12)
		w.state.spells[12].cooldown = { w.state.time, 6.5 }
		H.eq(A.Cooldown(12), 6.5)
		w.state.secret.cooldown = true
		H.eq(A.Cooldown(12), 8, "secret: the estimate")
		w:advance(9)
		H.eq(A.Cooldown(12), 0, "secret and nothing tracked")
	end)

	it("ignores the GCD and odd client answers", function()
		local w, _, A = api(function(w)
			w.spell(13, { name = "Gcd", cooldown = { 1000, 1.5 } })
			w.spell(14, { name = "Old", cooldown = { 900, 10 } })
		end)
		H.eq(A.Cooldown(13), 0)
		H.eq(A.Cooldown(14), 0, "already over")
		w.env.C_Spell.GetSpellCooldown = function()
			return { start = 1000, duration = 20 }
		end
		H.eq(A.Cooldown(14), 20, "start field name")
		w.env.C_Spell.GetSpellCooldown = function()
			return {}
		end
		H.eq(A.Cooldown(14), 0)
		w.env.C_Spell.GetSpellCooldown = function()
			return 5
		end
		H.eq(A.Cooldown(14), 0)
		w.env.C_Spell.GetSpellCooldown = nil
		H.eq(A.Cooldown(14), 0)
	end)

	it("keys spells by name without rank, else by ID", function()
		local w, _, A = api(function(w)
			w.spell(15, { name = "Rend (Rank 2)", baseCooldown = 10000 })
			w.spell(16, { name = "(Rank 1)", baseCooldown = 10000 })
			w.spell(17, { name = "Rend", baseCooldown = 10000 })
		end)
		A.NoteSpellCast(15)
		H.eq(A.Cooldown(17), 10, "same key as Rend")
		A.NoteSpellCast(16)
		H.eq(A.Cooldown(16), 10, "ID key")
		w.env.strtrim = nil
		A.NoteSpellCast(17)
	end)
end)

describe("API holds", function()
	it("takes the hold from the list step, then the table", function()
		local _, ns, A = api(function(w)
			w.spell(20, { name = "Corruption", harmful = true })
			w.spell(21, { name = "Shield", helpful = true })
			w.spell(22, { name = "Plain" })
		end)
		H.eq(A.HoldSeconds(20), 0)
		ns.GetAPL = function()
			return { { id = 99 }, { id = 20, opt = { hold = 4 } }, {} }
		end
		ns.GetDef = function()
			return { { id = 21, opt = { hold = "x" } } }
		end
		H.eq(A.HoldSeconds(20), 4)
		H.eq(A.HoldSeconds(21), 0, "invalid hold is 0")
		ns.SPELL_HOLD[22] = 3
		H.eq(A.HoldSeconds(22), 3)
		ns.GetAPL = function()
			return { { id = 22 } }
		end
		H.eq(A.HoldSeconds(22), 3, "listed without a hold: the table")
		ns.SPELL_HOLD[22] = "bad"
		H.eq(A.HoldSeconds(22), 0)
		ns.GetAPL = function()
			return { { id = 20, opt = { hold = -2 } } }
		end
		H.eq(A.HoldSeconds(20), 0, "negative clamped")
		ns.API.Resolve = function()
			return nil
		end
		H.eq(A.HoldSeconds(nil), 0)
	end)

	it("binds harmful holds to the target and self holds to nothing", function()
		local w, ns, A = api(function(w)
			w.spell(20, { name = "Corruption", harmful = true })
			w.spell(21, { name = "Shield", helpful = true })
		end)
		w:target()
		ns.SPELL_HOLD[20] = 10
		ns.SPELL_HOLD[21] = 10
		A.NoteSpellCast(20)
		A.NoteSpellCast(21)
		H.eq(A.HoldRemain(20), 10)
		H.eq(A.HoldRemain(21), 10)
		H.eq(A.HoldRemain(nil), 0)
		H.eq(A.HoldRemain(99), 0)
		w.state.units.target.guid = "Creature-0-2"
		H.eq(A.HoldRemain(20), 0, "other target")
		H.eq(A.HoldRemain(21), 10, "self hold stays")
		A.NoteSpellCast(20)
		w.state.units.target.dead = true
		H.eq(A.HoldRemain(20), 0, "dead target")
		w.state.units.target.dead = false
		A.NoteSpellCast(20)
		A.ClearTargetDebuffs()
		H.eq(A.HoldRemain(20), 0, "target change")
		H.eq(A.HoldRemain(21), 10)
		w:advance(11)
		H.eq(A.HoldRemain(21), 0, "expired")
		w.state.units.target = nil
		A.NoteSpellHold(20, 5)
		H.eq(A.HoldRemain(20), 0, "cast without a target")
		A.NoteSpellHold(nil, 5)
		A.NoteSpellHold(20, "x")
		A.NoteSpellHold(20, 0)
	end)

	it("binds to the current target when the GUID is secret", function()
		local w, ns, A = api(function(w)
			w.spell(20, { name = "Corruption", harmful = true })
		end)
		w:target({ secretGuid = true })
		ns.SPELL_HOLD[20] = 8
		A.NoteSpellCast(20)
		H.eq(A.HoldRemain(20), 8)
		A.ClearTargetDebuffs()
		H.eq(A.HoldRemain(20), 0)
	end)

	it("finds a hold by the resolved ID and checks death both ways", function()
		local w, ns, A = api(function(w)
			w.spell(30, { name = "Old", harmful = true, override = 31 })
			w.spell(31, { name = "New", harmful = true })
		end)
		w:target()
		A.NoteSpellHold(30, 6)
		H.eq(A.HoldRemain(31), 6, "stored under the resolved ID too")
		A.NoteSpellHold(31, 6)
		H.eq(A.HoldRemain(30), 6, "through Resolve")
		w.env.UnitIsDeadOrGhost = function()
			error("boom")
		end
		w.env.UnitIsDead = function()
			return true
		end
		H.eq(A.HoldRemain(30), 0, "UnitIsDead fallback")
		A.NoteSpellHold(31, 6)
		w.env.UnitIsDead = nil
		w.env.UnitIsDeadOrGhost = nil
		H.eq(A.HoldRemain(31), 6)
		local _ = ns
	end)
end)

describe("API look-ahead (predict)", function()
	it("marks debuffs, buffs, used buffs, combo and cooldowns", function()
		local w, ns, A = api(function(w)
			w.spell(8042, { name = "Earth Shock", baseCooldown = 6000 })
			w.spell(8050, { name = "Flame Shock" })
			w.spell(1752, { name = "Sinister Strike" })
			w.spell(90003, { name = "Sinister Strike" })
			w.spell(40, { name = "Buff" })
			w.spell(41, { name = "Stealth" })
		end)
		ns.COMBO_BUILDERS = { [1752] = true }
		A.PredictConsume(8042, {})
		A.PredictBegin()
		A.PredictConsume(8042, { nodebuff = true, anydebuff = { 8050 }, needdebuff = 8050 })
		H.eq(A.Cooldown(8050), 6, "predicted shock cooldown")
		H.same({ A.HasAura(8042, "target", "HARMFUL") }, { true, 9999 })
		A.PredictConsume(40, { nobuff = true, anybuff = { 40 } })
		H.same({ A.HasAura(40, "player", "HELPFUL") }, { true, 9999 })
		A.PredictConsume(1, { needbuff = 41 })
		H.same({ A.HasAura(41, "player", "HELPFUL") }, { false, 0 })
		A.PredictConsume(90003, {})
		A.PredictConsume(1752, { filler = true })
		H.eq(A.Combo(), 2)
		A.PredictConsume(2098, { comboMin = 1 })
		H.eq(A.Combo(), 0)
		A.PredictConsume(nil, {})
		A.PredictConsume(nil, { nodebuff = true, nobuff = true })
		w.spell(90020, { name = "Earth Shock" })
		H.eq((A.HasAura(90020, "target", "HARMFUL")), true, "same name as a predicted debuff")
		w.spell(90021, { name = "Buff" })
		H.eq((A.HasAura(90021, "player", "HELPFUL")), true, "same name as a predicted buff")
		w.spell(44, { name = "Nova", baseCooldown = 25000 })
		A.PredictConsume(44, {})
		H.eq(A.Cooldown(44), 25, "predicted cooldown outside a group")
		A.PredictConsume(42, nil)
		w.spell(43, { name = "" })
		A.PredictConsume(43, { nodebuff = true, nobuff = true, needbuff = 43 })
		ns.COMBO_BUILDERS = nil
		A.PredictConsume(1752, {})
		A.PredictEnd()
		H.eq(A.Cooldown(8050), 0)
	end)
end)
