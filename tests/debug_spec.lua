local wow = require("wow")
local H = require("helpers")

local function boot(class, setup)
	local w = wow.new()
	w:player(class or "WARRIOR", { power = { [0] = 50, [4] = 2 }, powerMax = { [0] = 100 } })
	w.spell(1, { name = "Strike", harmful = true, inRange = true })
	w.spell(2, { name = "Buff", helpful = true })
	if setup then
		setup(w)
	end
	w:load()
	w:fire("PLAYER_LOGIN")
	return w, w.ns
end

-- The rotation the spell probes read: the two spells of the mock.
local function useSteps(ns)
	ns.GetAPL = function()
		return {
			{ key = "Strike", id = 1, opt = { hostile = true }, on = true },
			{ key = "Buff", id = 2, opt = {}, on = true },
			{ key = "Off", id = 2, opt = {}, on = false },
		}
	end
end

local function counts(ns)
	local out = {}
	for key, n in pairs(ns.db.debug.counts) do
		out[key:gsub("\t", " | ")] = n
	end
	return out
end

describe("Debug sampling", function()
	it("classifies what the client answers: values, secrets, nil and errors", function()
		local w, ns = boot()
		useSteps(ns)
		w:target({ health = 40 })
		w.state.units.target.creatureType = "Beast"
		ns.Debug.Sample()
		local c = counts(ns)
		H.eq(c["UnitHealth(player) | idle, enemy | number"], 1)
		H.eq(c["UnitCreatureType(target) | idle, enemy | string,nil"], 1)
		H.eq(c["UnitCanAttack(player, target) | idle, enemy | boolean=true"], 1)
		w.state.units.player.combat = true
		w.state.secret.health = true
		w.state.secret.creature = true
		w.state.secret.guid = true
		ns.Debug.Sample()
		c = counts(ns)
		H.eq(c["UnitHealth(player) | combat, enemy | SECRET number"], 1)
		H.eq(c["UnitCreatureType(target) | combat, enemy | SECRET string,SECRET number"], 1)
		H.eq(c["UnitGUID(target) | combat, enemy | SECRET string"], 1)
		w.env.UnitPower = function()
			error("boom in the client")
		end
		w.env.UnitAttackSpeed = function() end
		ns.Debug.Sample()
		c = counts(ns)
		H.eq(c["UnitPower(player, mana) | combat, enemy | ERROR boom in the client"] ~= nil, false)
		local found
		for key in pairs(c) do
			if key:find("UnitPower(player, mana)", 1, true) and key:find("ERROR", 1, true) then
				found = true
			end
		end
		H.truthy(found, "an error is recorded, not thrown")
		H.eq(c["UnitAttackSpeed(player) | combat, enemy | no return"], 1)
		H.eq(ns.db.debug.samples, 3)
	end)

	it("covers friends, no target, pets, totems and the rotation's spells", function()
		local w, ns = boot("SHAMAN", function(w)
			w.state.spells[1].cooldown = { 1000, 8 }
			w.unit("pet", { health = 10, maxHealth = 10 })
		end)
		useSteps(ns)
		w.state.totems[1] = { name = "Searing Totem", start = 1000, duration = 30 }
		ns.Debug.Sample()
		w.unit("target", { health = 5, maxHealth = 10, reaction = 5, guid = "Player-1-2" })
		ns.Debug.Sample()
		local c = counts(ns)
		H.truthy(c["GetTotemInfo(1) have,name,start,duration | idle, no target | boolean=true,string,number,number"])
		H.truthy(c["UnitHealth(pet) | idle, no target | number"])
		H.truthy(c["UnitGUID(target) | idle, friend | string"])
		local usable
		for key in pairs(c) do
			if key:find("usable vs range vs addon", 1, true) then
				usable = key
			end
		end
		H.truthy(usable, "the usable / range question is recorded")
		H.truthy(usable:find("usable=boolean=true", 1, true))
		local why
		for key in pairs(c) do
			if key:find("addon says | ", 1, true) then
				why = key
			end
		end
		H.truthy(why)
	end)

	it("keeps the key count bounded", function()
		local w, ns = boot()
		ns.Debug.Sample()
		local d = ns.db.debug
		d.keys = 700
		w:target()
		ns.Debug.Sample()
		H.truthy(d.dropped > 0, "new keys are dropped once the limit is reached")
		H.eq(d.keys, 700)
	end)
end)

describe("Debug totem bar and glow buttons", function()
	it("records what the totem bar buttons hold and where a spell would glow", function()
		local w, ns = boot("SHAMAN", function(w)
			w.spell(8071, { name = "Stoneskin Totem" })
		end)
		useSteps(ns)
		ns.GetAPL = function()
			return { { key = "Stoneskin", id = 8071, opt = {}, on = true } }
		end
		local b = w.env.CreateFrame("CheckButton", "MultiCastActionButton2")
		b.action = 133
		w.state.actions[133] = { type = "spell", id = 8071 }
		ns.GlowFetch(true)
		local broken = w.env.CreateFrame("CheckButton", "MultiCastActionButton3")
		broken.GetAttribute = function()
			error("no attribute")
		end
		local hidden = w.env.CreateFrame("CheckButton", "MultiCastActionButton4")
		hidden.action = wow.SECRET
		ns.Debug.Sample()
		local c = counts(ns)
		H.truthy(c["MultiCastActionButton2 | idle, no target | slot=133 type=spell id=8071 shown=true"])
		local found
		for key in pairs(c) do
			if key:find("MultiCastActionButton3 | idle, no target | ERROR", 1, true) then
				found = true
			end
		end
		H.truthy(found, "a failing button is recorded, not thrown")
		H.truthy(c["glows on buttons | Stoneskin Totem | idle, no target | MultiCastActionButton2"])
		H.truthy(c["UnitAffectingCombat(player) | idle, no target | boolean=false"])
		H.truthy(c["UnitExists(target) | idle, no target | boolean=false"])
	end)
end)

describe("Debug mode switch and events", function()
	it("starts and stops collecting with the setting", function()
		local w, ns = boot()
		ns.db.debugMode = true
		ns.Debug.Apply()
		ns.Debug.Apply()
		w:advance(2.5)
		H.truthy(ns.db.debug.samples >= 2, "the ticker samples every second")
		H.eq(ns.db.debug.info.addon, "1.0.0-test")
		H.eq(ns.db.debug.info.class, "WARRIOR")
		local before = ns.db.debug.samples
		ns.db.debugMode = nil
		ns.Debug.Apply()
		ns.Debug.Apply()
		w:advance(3)
		H.eq(ns.db.debug.samples, before)
		ns.db.debugMode = true
		w.env.GetBuildInfo = function()
			error("no build info")
		end
		ns.Debug.Apply()
		H.eq(ns.db.debug.info.client, "unknown")
	end)

	it("counts events and remembers the client's error texts", function()
		local w, ns = boot()
		ns.db.debugMode = true
		ns.Debug.Apply()
		w:fire("UNIT_ATTACK", "player")
		w:fire("UNIT_ATTACK", "target")
		w:fire("PLAYER_TOTEM_UPDATE", 1)
		w:fire("UNIT_SPELLCAST_SUCCEEDED", "player", "guid", 1)
		w:fire("UNIT_SPELLCAST_SUCCEEDED", "player", "guid", wow.SECRET)
		w:fire("UNIT_COMBAT", "player", "PARRY", "", 0, 1)
		w:fire("UI_ERROR_MESSAGE", 51, "You must be behind your target.")
		w:fire("UI_ERROR_MESSAGE", 51, "You must be behind your target.")
		w:fire("UI_ERROR_MESSAGE", 51, wow.SECRET_STRING)
		local c = counts(ns)
		H.eq(c["event UNIT_ATTACK | idle, no target | fired"], 1, "only the player's")
		H.eq(c["event PLAYER_TOTEM_UPDATE | idle, no target | fired"], 1)
		H.eq(c["event UNIT_SPELLCAST_SUCCEEDED spellID | idle, no target | number"], 1)
		H.eq(c["event UNIT_SPELLCAST_SUCCEEDED spellID | idle, no target | SECRET number"], 1)
		H.eq(ns.db.debug.texts["UI_ERROR_MESSAGE: You must be behind your target."], 2)
		H.eq(ns.db.debug.texts["UNIT_COMBAT action: PARRY"], 1)
		-- The text list is bounded.
		for i = 1, 70 do
			w:fire("UI_ERROR_MESSAGE", 51, "message " .. i)
		end
		H.eq(ns.db.debug.textKeys, 60)
	end)
end)

describe("Debug report", function()
	it("turns the numbers into text, and clears them", function()
		local w, ns = boot()
		ns.db.debugMode = true
		ns.Debug.Apply()
		w:fire("UI_ERROR_MESSAGE", 51, "Out of range.")
		w:target()
		ns.Debug.Sample()
		local report = ns.Debug.Report()
		H.truthy(report:find("^Know Your Rotation debug report\nclient: 1.14.0 %(build 54321, interface 16001%)"))
		H.truthy(report:find("addon: 1.0.0-test | WARRIOR level 10", 1, true))
		H.truthy(report:find("UnitHealth(player)\n  idle, enemy -> number  x1", 1, true))
		H.truthy(report:find("texts the client sent\n  UI_ERROR_MESSAGE: Out of range.  x1", 1, true))
		ns.Debug.Clear()
		local empty = ns.Debug.Report()
		H.truthy(empty:find("samples: 0, keys: 0, dropped: 0", 1, true))
		H.truthy(empty:find("client: ? | addon: ?", 1, true))
		H.falsy(empty:find("texts the client sent", 1, true))
	end)
end)

describe("Debug buttons and switch in the options", function()
	it("shows the report, clears it, and toggles collecting", function()
		local w, ns = boot()
		local checkbox
		for _, c in ipairs(w.controls) do
			if c.setting.variable == "KnowYourRotation_debugMode" then
				checkbox = c
			end
		end
		H.eq(checkbox.setting:GetValue(), false)
		checkbox.setting:SetValue(true)
		H.eq(ns.db.debugMode, true)
		H.eq(checkbox.setting:GetValue(), true)
		checkbox.setting:SetValue(false)
		H.eq(ns.db.debugMode, nil)
		local panel = w.env.KnowYourRotationPanelprofiles
		panel:Hide()
		panel:Show()
		local frame = ns.UI.options
		ns.Debug.Sample()
		frame.debugBtn:Click()
		H.truthy(frame.shareEdit:GetText():find("^Know Your Rotation debug report"))
		frame.clearBtn:Click()
		H.eq(ns.db.debug, nil)
		H.contains(w.printed, "|cff66ccffKnow Your Rotation|r: " .. ns.T("OPT_DEBUG_CLEARED"))
	end)
end)
