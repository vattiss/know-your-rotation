local wow = require("wow")
local H = require("helpers")

local function boot(setup)
	local w = wow.new()
	w:player("HUNTER")
	if setup then
		setup(w)
	end
	w:load()
	w:fire("PLAYER_LOGIN")
	return w, w.ns, w.ns.Physics
end

describe("Physics option", function()
	it("is off before the saved variables load, on by default after", function()
		local w = wow.new()
		w:player("HUNTER")
		local ns = w:load()
		ns.db = nil
		H.eq(ns.Physics.Enabled(), false)
		local _, ns2 = boot()
		H.eq(ns2.Physics.Enabled(), true)
		ns2.db.showPhysics = false
		H.eq(ns2.Physics.Enabled(), false)
	end)
end)

describe("Physics.IsClip", function()
	it("knows Aimed Shot, Multi-Shot and Volley, also by their resolved ID", function()
		local _, ns, P = boot()
		local Hu = ns.Spell.Hunter
		H.eq(P.IsClip(nil), false)
		H.eq(P.IsClip(Hu.AimedShot), true)
		H.eq(P.IsClip(Hu.ArcaneShot), false)
		ns.API.Resolve = function()
			return Hu.MultiShot
		end
		H.eq(P.IsClip(99999), true)
	end)
end)

describe("Physics Auto Shot timer", function()
	it("clips only in the last 0.4 s before the next shot", function()
		local w, _, P = boot(function(w)
			w.state.rangedSpeed = 2.8
		end)
		H.eq(P.WouldClip(), false, "no shot yet")
		w:fire("UNIT_SPELLCAST_SUCCEEDED", "player", "guid", 75)
		H.eq(P.WouldClip(), false, "just fired")
		w:advance(2.5)
		H.eq(P.WouldClip(), true, "0.3 s left")
		w:advance(0.25)
		H.eq(P.WouldClip(), false, "0.05 s left")
		w:advance(1)
		H.eq(P.WouldClip(), false, "timer expired")
	end)

	it("resets when combat ends and ignores other units and spells", function()
		local w, _, P = boot(function(w)
			w.state.rangedSpeed = 2
		end)
		w:fire("UNIT_SPELLCAST_SUCCEEDED", "player", "guid", 75)
		w:fire("UNIT_SPELLCAST_SUCCEEDED", "target", "guid", 75)
		w:fire("UNIT_SPELLCAST_SUCCEEDED", "player", "guid", 1234)
		w:advance(1.8)
		H.eq(P.WouldClip(), true)
		w:fire("PLAYER_REGEN_ENABLED")
		H.eq(P.WouldClip(), false)
	end)

	it("takes the speed from the tooltip when the stat is hidden", function()
		local w, _, P = boot(function(w)
			w.state.secret.stats = true
			w.state.tooltips = {
				[18] = {
					"junk",
					{ leftText = "Damage", rightText = "Fast" },
					{ leftText = "Damage", rightText = "Speed 0.10" },
					{ leftText = "Damage", rightText = "Speed 2.00" },
				},
			}
		end)
		P.NoteShot()
		w:advance(1.7)
		H.eq(P.WouldClip(), true, "2 s shot")
		-- The cached speed is reused for the next shot.
		w.state.tooltips = nil
		P.NoteShot()
		w:advance(1.7)
		H.eq(P.WouldClip(), true, "cached 2 s")
	end)

	it("falls back to 3 s without any speed", function()
		local w, _, P = boot(function(w)
			w.env.UnitRangedDamage = nil
			w.state.tooltips = {}
		end)
		P.NoteShot()
		w:advance(2.7)
		H.eq(P.WouldClip(), true, "3 s default")
		local w2, _, P2 = boot(function(w2)
			w2.state.secret.stats = true
			w2.state.tooltips = { [18] = { { leftText = "Damage", rightText = "Fast" } } }
		end)
		P2.NoteShot()
		w2:advance(2.7)
		H.eq(P2.WouldClip(), true, "no speed line")
	end)

	it("copes with a missing or failing tooltip API", function()
		local w, _, P = boot(function(w)
			w.state.secret.stats = true
			w.env.C_TooltipInfo = nil
		end)
		P.NoteShot()
		w:advance(2.7)
		H.eq(P.WouldClip(), true)
		local w2, _, P2 = boot(function(w2)
			w2.state.secret.stats = true
			w2.env.C_TooltipInfo = {
				GetInventoryItem = function()
					error("no tooltip")
				end,
			}
		end)
		P2.NoteShot()
		w2:advance(2.7)
		H.eq(P2.WouldClip(), true)
	end)
end)

describe("Physics energy tick", function()
	local function rogue(energy, cost)
		local w, ns, P = boot(function(w)
			w:player("ROGUE", { power = { [3] = energy }, powerMax = { [3] = 100 } })
			w.spell(1752, { name = "Sinister Strike", cost = cost })
		end)
		return w, ns, P
	end

	it("lets a spell through when its energy arrives within 0.45 s", function()
		local w, _, P = rogue(25, { "junk", { type = 0, cost = 10 }, { type = 3, cost = 40 } })
		H.eq(P.EnergySoon(1752), false, "no tick seen yet")
		w:fire("UNIT_POWER_UPDATE", "player", "ENERGY")
		w.state.units.player.power[3] = 45
		w:advance(0.1)
		w:fire("UNIT_POWER_UPDATE", "player", "ENERGY")
		w.state.units.player.power[3] = 25
		w:advance(1.0)
		H.eq(P.EnergySoon(1752), false, "1.0 s to the tick")
		w:advance(0.7)
		H.eq(P.EnergySoon(1752), true, "0.3 s to the tick")
	end)

	it("resyncs on a gain of 40 and ignores small gains", function()
		local w, _, P = rogue(20, { { type = 3, cost = 40 } })
		P.NoteEnergy(20)
		w:advance(0.5)
		P.NoteEnergy(60)
		w:advance(0.5)
		P.NoteEnergy(65)
		w:advance(1.2)
		H.eq(P.EnergySoon(1752), true, "tick from the +40 gain")
		P.NoteEnergy("not a number")
		w:fire("UNIT_POWER_UPDATE", "target", "ENERGY")
	end)

	it("says no without a cost, with enough energy or far too little", function()
		local _, _, P = rogue(50, { { type = 3, cost = 40 } })
		H.eq(P.EnergySoon(1752), false, "enough already")
		local _, _, P2 = rogue(10, { { type = 3, cost = 40 } })
		H.eq(P2.EnergySoon(1752), false, "a tick is not enough")
		local _, _, P3 = rogue(10, nil)
		H.eq(P3.EnergySoon(1752), false, "no cost")
		local _, _, P5 = rogue(10, { { type = 0, cost = 30 } })
		H.eq(P5.EnergySoon(1752), false, "mana cost only")
		local w4, _, P4 = rogue(25, { { type = 3, cost = 40 } })
		w4.state.secret.power = true
		H.eq(P4.EnergySoon(1752), false, "hidden energy")
	end)

	it("handles a clock that went backwards", function()
		local w, _, P = rogue(25, { { type = 3, cost = 40 } })
		P.NoteEnergy(25)
		w.state.time = w.state.time - 5
		H.eq(P.EnergySoon(1752), false)
	end)

	it("copes with missing or failing cost and power APIs", function()
		local w, _, P = rogue(25, { { type = 3, cost = 40 } })
		w.env.C_Spell.GetSpellPowerCost = function()
			error("boom")
		end
		H.eq(P.EnergySoon(1752), false)
		w.env.C_Spell.GetSpellPowerCost = nil
		H.eq(P.EnergySoon(1752), false)
		w.env.C_Spell = nil
		H.eq(P.EnergySoon(1752), false)
		local w2 = rogue(25, { { type = 3, cost = 40 } })
		w2.env.UnitPower = function()
			error("boom")
		end
		w2:fire("UNIT_POWER_UPDATE", "player", "ENERGY")
		H.eq(w2.ns.Physics.EnergySoon(1752), false)
	end)
end)

describe("Physics.Blocks", function()
	it("holds a clipping shot only while the option is on", function()
		local w, ns, P = boot(function(w)
			w.state.rangedSpeed = 2
		end)
		local aimed = ns.Spell.Hunter.AimedShot
		H.eq(P.Blocks(nil), false)
		w:fire("UNIT_SPELLCAST_SUCCEEDED", "player", "guid", 75)
		w:advance(1.8)
		H.eq(P.Blocks(aimed), true)
		H.eq(P.Blocks(ns.Spell.Hunter.ArcaneShot), false)
		ns.db.showPhysics = false
		H.eq(P.Blocks(aimed), false)
	end)
end)
