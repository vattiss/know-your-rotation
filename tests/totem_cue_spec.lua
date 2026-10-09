local wow = require("wow")
local H = require("helpers")

local function boot(setup)
	local w = wow.new()
	w:player("SHAMAN")
	w.spell(8071, { name = "Stoneskin Totem" })
	w.spell(2484, { name = "Earthbind Totem" })
	w.spell(3599, { name = "Searing Totem" })
	if setup then
		setup(w)
	end
	w:load()
	w:fire("PLAYER_LOGIN")
	return w, w.ns
end

-- A button of the totem bar holding an action.
local function totemButton(w, index, action)
	local b = w.env.CreateFrame("CheckButton", "MultiCastActionButton" .. index)
	b.action = 130 + index
	w.state.actions[b.action] = action
	return b
end

describe("Auto Shot cue", function()
	local function hunter(class)
		local w = wow.new()
		w:player(class or "HUNTER")
		w.spell(75, { name = "Auto Shot", harmful = true, inRange = true })
		w:target({ distance = 20 })
		w:load()
		w:fire("PLAYER_LOGIN")
		return w, w.ns
	end

	it("is offered while Auto Shot is off, and is not a step of the rotation", function()
		local _, ns = hunter()
		H.eq(ns.BuildAutoShot(), 75)
		H.eq(ns.IsCueSpell(75), true)
		H.eq(ns.AddAPL(75, "HUNTER"), false)
		local function walk(node)
			for _, child in pairs(node) do
				if type(child) == "table" then
					if child.key and child.opt then
						H.truthy(child.id ~= ns.Spell.Hunter.AutoShot, "no Auto Shot step in " .. child.key)
					else
						walk(child)
					end
				end
			end
		end
		walk(ns.APLDefaults.HUNTER)
		walk(ns.APLModes.HUNTER or {})
	end)

	it("is quiet in melee range, where a hunter cannot shoot", function()
		local _, ns = hunter()
		ns.API.TargetInMelee = function()
			return true
		end
		H.eq(ns.BuildAutoShot(), nil)
		ns.API.TargetInMelee = function()
			return false
		end
		H.eq(ns.BuildAutoShot(), 75)
	end)

	it("is quiet while it runs, and for other classes", function()
		local w, ns = hunter()
		w.state.spells[75].repeating = true
		H.eq(ns.BuildAutoShot(), nil)
		local _, mage = hunter("MAGE")
		H.eq(mage.BuildAutoShot(), nil)
	end)
end)

describe("Totem cue", function()
	it("knows when each totem is worth dropping", function()
		local w, ns = boot()
		local A, Sh = ns.API, ns.Spell.Shaman
		H.eq(A.TotemWhen(8071), "pull")
		H.eq(A.TotemWhen(2484), "melee")
		H.eq(A.TotemWhen(3599), "hostile")
		H.eq(A.TotemWhen(Sh.TremorTotem), nil, "situational: no cue")
		H.eq(A.TotemWhen(424242), nil, "not a totem")
		H.eq(ns.IsCueSpell(8071), true)
		H.eq(ns.IsCueSpell(424242), false)
		H.eq(ns.IsCueSpell(nil), false)
		H.eq(ns.IsCueSpell(wow.SECRET), false)
		H.eq(w ~= nil, true)
	end)

	it("reads the totems the player put in the totem bar", function()
		local w, ns = boot(function(w)
			w.spell(8143, { name = "Tremor Totem" })
		end)
		totemButton(w, 1, { type = "spell", id = 8071 })
		totemButton(w, 2, { type = "spell", id = 2484 })
		totemButton(w, 3, { type = "spell", id = 8143 })
		totemButton(w, 4, { type = "macro", id = 5 })
		H.same(ns.API.TotemBar(), {
			{ id = 8071, when = "pull" },
			{ id = 2484, when = "melee" },
		})
		local empty = w.env.MultiCastActionButton4
		empty.action = nil
		empty.GetAttribute = function()
			return nil
		end
		H.eq(#ns.API.TotemBar(), 2, "a button without an action is skipped")
	end)

	it("offers the missing totems of the bar, by what each one needs", function()
		local w, ns = boot()
		totemButton(w, 1, { type = "spell", id = 8071 })
		totemButton(w, 2, { type = "spell", id = 2484 })
		local seen = {}
		local ready
		ns.API.StepOk = function(id, opt)
			seen[id] = opt
			return id == ready
		end
		ready = 2484
		H.same(ns.BuildTotem(), { 2484 }, "the buff totem is not due, the slow is")
		H.eq(seen[8071].engaged, true, "a buff totem is due at the start of the fight")
		H.eq(seen[2484].inMelee, true, "a slow only helps in melee")
		ready = nil
		H.same(ns.BuildTotem(), {})
		seen = {}
		w.state.actions[131] = { type = "spell", id = 3599 }
		ready = 3599
		H.same(ns.BuildTotem(), { 3599 })
		H.eq(seen[3599].hostile, true, "an attack totem needs an enemy")
		ns.API.StepOk = function()
			return true
		end
		H.same(ns.BuildTotem(), { 3599, 2484 }, "totems of different slots are due together")
	end)

	it("keeps totems out of the rotation lists", function()
		local _, ns = boot()
		H.eq(ns.AddAPL(8071, "SHAMAN"), false)
		local count = 0
		local function walk(node)
			for _, child in pairs(node) do
				if type(child) == "table" then
					if child.key and child.opt then
						count = count + 1
						H.eq(child.opt.totem, nil, child.key)
					else
						walk(child)
					end
				end
			end
		end
		walk(ns.APLDefaults.SHAMAN)
		walk(ns.APLModes.SHAMAN or {})
		H.truthy(count > 5, "the defaults were walked")
	end)
end)
