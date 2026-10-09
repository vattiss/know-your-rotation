local wow = require("wow")
local H = require("helpers")

-- An action button the way Glow.lua reads it.
local function button(w, name, slot, action)
	local b = w.env.CreateFrame("CheckButton", name)
	if slot then
		b.action = slot
	end
	if action then
		w.state.actions[slot] = action
	end
	return b
end

local function boot(class, setup)
	local w = wow.new()
	w:player(class or "WARRIOR")
	w.spell(1, { name = "Strike", harmful = true, icon = 101 })
	w.spell(2, { name = "Shout", helpful = true, icon = 102 })
	w.spell(3, { name = "Heal Me", helpful = true, icon = 103 })
	if setup then
		setup(w)
	end
	w:load()
	w:fire("PLAYER_LOGIN")
	return w, w.ns
end

local function overlayOf(b, key)
	return b.KYROverlays and b.KYROverlays[key]
end

describe("Glow bar scan", function()
	it("maps action slots, spells, macros and icons to buttons", function()
		local w, ns = boot("WARRIOR", function(w)
			button(w, "ActionButton1", 1, { type = "spell", id = 1, icon = 101 })
			button(w, "ActionButton2", 2, { type = "macro", id = 7 })
			button(w, "ActionButton3", 3, { type = "macro", id = 8 })
			button(w, "ActionButton4", 4, { type = "item", id = 9, icon = 104 })
			button(w, "ActionButton5")
			w.state.macros[7] = { spell = 2 }
			w.state.macros[8] = {
				body = "#showtooltip Heal Me\n/cast [@player] Heal Me(Rank 1); !Strike\n/say hi\nno slash",
			}
		end)
		ns.GlowFetch(true)
		H.eq(ns.SpellBarSlot(1), 1)
		H.eq(ns.SpellBarSlot(2), 2, "macro spell")
		H.eq(ns.SpellBarSlot(3), 3, "macro body")
		H.eq(ns.SpellBarSlot(99), nil)
		H.eq(ns.SpellBarSlot(nil), nil)
		local _ = w
	end)

	it("reads slots from attributes, paged IDs and calculated actions", function()
		local w, ns = boot("WARRIOR", function(w)
			local a = button(w, "ActionButton1")
			a:SetAttribute("action", 5)
			w.state.actions[5] = { type = "spell", id = 1 }
			local b = button(w, "ActionButton2")
			b.GetPagedID = function()
				return 6
			end
			w.state.actions[6] = { type = "spell", id = 2 }
			local c = button(w, "ActionButton3")
			c.GetPagedID = function()
				error("boom")
			end
			c.CalculateAction = function()
				return 7
			end
			w.state.actions[7] = { type = "spell", id = 3 }
			local d = button(w, "ActionButton4")
			d:SetAttribute("type", "spell")
			d:SetAttribute("spell", 1)
			local e = button(w, "ActionButton5")
			e:SetAttribute("type", "macro")
			e:SetAttribute("macro", 9)
			w.state.macros[9] = { spell = 3 }
			local f = button(w, "ActionButton6")
			f.GetAttribute = function()
				error("boom")
			end
		end)
		ns.GlowFetch(true)
		H.eq(ns.SpellBarSlot(1), 5)
		H.eq(ns.SpellBarSlot(2), 6)
		H.eq(ns.SpellBarSlot(3), 7)
		local _ = w
	end)

	it("scans stance bars and supported bar addons, in steps", function()
		local w, ns = boot("DRUID", function(w)
			w.spell(768, { name = "Cat Form" })
			w.state.forms = { { spellID = 768 }, { spellID = 5487 } }
			button(w, "StanceButton1")
			w.state.addons = { Dominos = true, Bartender4 = true, ElvUI = true }
			button(w, "DominosActionButton1", 13, { type = "spell", id = 1 })
			button(w, "BT4Button1", 14, { type = "spell", id = 2 })
			button(w, "ElvUI_Bar1Button1", 15, { type = "spell", id = 3 })
		end)
		ns.GlowFetch(true)
		w:advance(0)
		H.eq(ns.SpellBarSlot(1), 13)
		H.eq(ns.SpellBarSlot(2), 14)
		H.eq(ns.SpellBarSlot(3), 15)
		ns.GlowFetch()
		w.env.GetShapeshiftFormInfo = nil
		w.env.GetNumShapeshiftForms = function()
			error("boom")
		end
		ns.GlowFetch(true)
		ns.GlowFetch(true)
		w:advance(0)
	end)

	it("scans the shaman's totem bar", function()
		local w, ns = boot("SHAMAN", function(w)
			w.spell(8071, { name = "Stoneskin Totem", icon = 136098 })
			button(w, "MultiCastActionButton2", 133, { type = "spell", id = 8071 })
		end)
		ns.GlowFetch(true)
		H.eq(ns.SpellBarSlot(8071), 133, "found on the totem bar")
		ns.GlowSpell(8071)
		H.eq(overlayOf(w.env.MultiCastActionButton2, "next"):IsShown(), true)
	end)

	it("scans without timers and finds icons on the button frame", function()
		local w, ns = boot("WARRIOR", function(w)
			w.env.C_Timer.After = nil
			local b = button(w, "ActionButton1", 1, { type = "item", id = 5, icon = "Interface\\Icons\\X" })
			b.icon = b:CreateTexture()
			b.icon:SetTexture(101)
			local c = button(w, "ActionButton2", 2, { type = "item", id = 6 })
			local tex = w.env.CreateFrame("Frame", "ActionButton2Icon")
			tex:SetTexture(102)
			local _ = c
			w.state.addons = { Dominos = true }
		end)
		ns.GlowFetch(true)
		H.eq(ns.SpellBarSlot(1), 1, "same icon as the spell")
		H.eq(ns.SpellBarSlot(2), 2, "icon from the named texture")
		w.env.C_AddOns = nil
		ns.GlowFetch(true)
	end)

	it("ignores odd values from the client", function()
		local w, ns = boot("WARRIOR", function(w)
			button(w, "ActionButton1", 1, { type = "spell", id = wow.SECRET, spellID = 0 })
			button(w, "ActionButton2", 2, { type = wow.SECRET_STRING, id = 1 })
			button(w, "ActionButton3", 3, { type = "spell", id = "abc", icon = wow.SECRET })
			button(w, "ActionButton4", 4, { type = "macro", id = 5 })
			w.state.macros[5] = { body = "/cast Unknown Spell" }
			w.env.GetMacroSpell = function()
				error("boom")
			end
		end)
		w.env.canaccessvalue = function(v)
			return v ~= "abc"
		end
		ns.GlowFetch(true)
		H.eq(ns.SpellBarSlot(1), nil)
	end)
end)

describe("Glow highlights", function()
	local function bars()
		local w, ns = boot("WARRIOR", function(w)
			button(w, "ActionButton1", 1, { type = "spell", id = 1 })
			button(w, "ActionButton2", 2, { type = "spell", id = 2 })
			button(w, "ActionButton3", 3, { type = "spell", id = 3 })
		end)
		ns.GlowFetch(true)
		return w, ns, w.env.ActionButton1, w.env.ActionButton2, w.env.ActionButton3
	end

	it("glows the next spell, a heal in its colour, and clears", function()
		local _, ns, b1, _, b3 = bars()
		ns.GlowSpell(1)
		H.eq(overlayOf(b1, "next"):IsShown(), true)
		ns.GlowSpell(1)
		ns.queueHeal = { [3] = true }
		ns.GlowSpell(3)
		H.eq(overlayOf(b3, "heal"):IsShown(), true)
		H.eq(overlayOf(b1, "next"):IsShown(), false)
		ns.GlowSpell(1)
		H.eq(overlayOf(b3, "heal"):IsShown(), false)
		ns.GlowSpell(nil)
		H.eq(overlayOf(b1, "next"):IsShown(), false)
		ns.db.showRotation = false
		ns.GlowSpell(1)
		H.eq(overlayOf(b1, "next"):IsShown(), false)
		ns.GlowInvalidate()
	end)

	it("glows defense, interrupt, purge, cleanse and weapon cues", function()
		local _, ns, b1, b2, b3 = bars()
		ns.GlowDef(2)
		H.eq(overlayOf(b2, "def"):IsShown(), true)
		ns.GlowDef(2)
		ns.queueHeal = { [3] = true }
		ns.GlowDef(3)
		H.eq(overlayOf(b3, "def"):IsShown(), true)
		ns.GlowDef(nil)
		H.eq(overlayOf(b3, "def"):IsShown(), false)
		ns.db.showDefense = false
		ns.GlowDef(2)
		ns.GlowInterrupt(1)
		ns.GlowInterrupt(1)
		H.eq(overlayOf(b1, "kick"):IsShown(), true)
		ns.GlowInterrupt(nil)
		H.eq(overlayOf(b1, "kick"):IsShown(), false)
		ns.GlowPurge(1)
		H.eq(overlayOf(b1, "purge"):IsShown(), true)
		ns.GlowPurge(nil)
		ns.GlowCleanse(2)
		H.eq(overlayOf(b2, "cleanse"):IsShown(), true)
		ns.GlowCleanse(nil)
		ns.GlowWeapon(3)
		H.eq(overlayOf(b3, "weapon"):IsShown(), true)
		ns.GlowWeapon(nil)
		H.eq(overlayOf(b3, "weapon"):IsShown(), false)
		ns.GlowTotem({ 3, 1 })
		ns.GlowTotem({ 3, 1 })
		H.eq(overlayOf(b3, "totem"):IsShown(), true)
		H.eq(overlayOf(b1, "totem"):IsShown(), true, "every due totem glows at once")
		ns.GlowTotem({ 3 })
		H.eq(overlayOf(b1, "totem"):IsShown(), false)
		ns.GlowTotem(nil)
		H.eq(overlayOf(b3, "totem"):IsShown(), false)
		ns.GlowClearKick()
		ns.GlowClearPurge()
		ns.GlowClearCleanse()
		ns.GlowClearWeapon()
	end)

	it("falls back to a plain texture without the alert template", function()
		local w, ns, b1 = bars()
		local create = w.env.CreateFrame
		w.env.CreateFrame = function(kind, name, parent, template)
			if template then
				error("no template")
			end
			return create(kind, name, parent)
		end
		b1.GetWidth = function()
			return 4
		end
		b1.GetHeight = function()
			return 4
		end
		ns.GlowSpell(1)
		local o = overlayOf(b1, "next")
		H.eq(o.isAlert, nil)
		H.eq(o.texture:GetTexture(), "Interface\\Cooldown\\star4")
		H.eq(o._width, 36 * 1.45, "tiny button: default size")
		o:Fire("OnShow")
	end)

	it("plays the alert animation when shown", function()
		local _, ns, b1 = bars()
		ns.GlowSpell(1)
		local o = overlayOf(b1, "next")
		H.eq(o.isAlert, true)
		o:Hide()
		o:Show()
		H.eq(o.ProcStartAnim:IsPlaying(), true)
		o:Hide()
		H.eq(o.ProcStartAnim:IsPlaying(), false)
	end)
end)

describe("Glow hidden-value cues", function()
	local function bars()
		local w, ns = boot("WARRIOR", function(w)
			button(w, "ActionButton1", 1, { type = "spell", id = 1 })
			button(w, "ActionButton2", 2, { type = "spell", id = 3 })
		end)
		ns.GlowFetch(true)
		return w, ns, w.env.ActionButton1, w.env.ActionButton2
	end

	it("sets the heal glow alpha from the health curve", function()
		local w, ns, _, b2 = bars()
		w.state.units.player.health = 30
		ns.GlowHiddenHeal(3, 50)
		H.eq(overlayOf(b2, "hphide"):GetAlpha(), 1, "below the threshold")
		w.state.units.player.health = 90
		ns.GlowHiddenHeal(3, 50)
		H.eq(overlayOf(b2, "hphide"):GetAlpha(), 0)
		ns.GlowHiddenHeal(1, nil)
		H.eq(overlayOf(b2, "hphide"):IsShown(), false, "moved to another button")
		ns.GlowHiddenHeal(nil)
		ns.GlowHiddenMana(3, 20)
		ns.GlowHiddenPet(3, 40)
		ns.GlowHiddenDefense(3, 30)
		ns.GlowHiddenExecute(3, 20)
	end)

	it("warns once when the client cannot drive the glow", function()
		local w, ns = bars()
		w.env.UnitHealthPercent = nil
		ns.GlowHiddenHeal(3, 50)
		ns.GlowHiddenHeal(3, 50)
		H.eq(#w.messages, 1)
		w.env.UnitHealthPercent = function()
			error("boom")
		end
		ns.GlowHiddenDefense(3, 50)
		H.eq(#w.messages, 2)
		w.env.C_CurveUtil = nil
		ns.GlowHiddenExecute(3, 33)
		H.eq(#w.messages, 3, "no curves")
	end)

	it("fades the rotation glow where a finisher takes over", function()
		local w, ns, b1 = bars()
		ns.GlowSpell(1)
		local o = overlayOf(b1, "next")
		w.state.units.target = nil
		w:target({ health = 10 })
		ns.GlowFadeForFinisher(1, 20)
		H.eq(o:GetAlpha(), 0, "target below 20 %")
		ns.GlowFadeForFinisher(1, 20)
		ns.GlowFadeForFinisher(2, 20)
		H.eq(o:GetAlpha(), o.kyrAlpha, "restored for another spell")
		ns.GlowFadeForFinisher(1, 20)
		ns.GlowFadeForFinisher(nil)
		H.eq(o:GetAlpha(), o.kyrAlpha)
		w.env.UnitHealthPercent = function()
			error("boom")
		end
		ns.GlowFadeForFinisher(1, 20)
		w.env.C_CurveUtil = nil
		ns.GlowFadeForFinisher(1, 31)
	end)
end)

describe("Glow range", function()
	it("reads the action slot, then the spell on the right unit", function()
		local w, ns = boot("WARRIOR")
		w.state.actions[1] = { type = "spell", id = 1, inRange = true }
		H.eq(ns.SpellInRange(1, 1), true, "action slot")
		w.state.actions[1].inRange = 0
		H.eq(ns.SpellInRange(1, 1), false)
		w.state.actions[1].inRange = nil
		H.eq(ns.SpellInRange(nil, 1), nil)
		w.state.spells[1].inRange = false
		H.eq(ns.SpellInRange(1), false, "harmful: target")
		w.state.spells[2].inRange = 1
		H.eq(ns.SpellInRange(2), true, "helpful: heal unit")
		ns.queueHeal = { [3] = true }
		w.state.spells[3].inRange = nil
		H.eq(ns.SpellInRange(3, 1), nil)
		w.state.spells[3].inRange = wow.SECRET_BOOL
		H.eq(ns.SpellInRange(3), nil, "secret flag")
		w.env.C_Spell.IsSpellInRange = function(_, unit)
			if unit == "target" then
				return true
			end
		end
		H.eq(ns.SpellInRange(3), true, "falls back to the target")
		w.env.C_Spell.IsSpellInRange = function()
			error("boom")
		end
		w.env.IsActionInRange = function()
			return wow.SECRET_BOOL
		end
		H.eq(ns.SpellInRange(3, 1), nil)
		w.env.IsActionInRange = function()
			error("boom")
		end
		H.eq(ns.SpellInRange(3, 1), nil)
	end)
end)

describe("Glow edge cases", function()
	it("handles actions without a type, unknown spells and secret names", function()
		local w, ns = boot("WARRIOR", function(w)
			button(w, "ActionButton1", 1, { id = 1 })
			button(w, "ActionButton2", 2, { type = "spell", id = 999 })
			button(w, "ActionButton3", 3, { type = "spell", id = 1, icon = true })
			button(w, "ActionButton4", 4, { type = "macro", id = 5 })
			w.state.macros[5] = { body = "/cast Hidden\n/cast Blank" }
			w.state.forms = { {}, { spellID = 1 } }
			button(w, "StanceButton1")
		end)
		w.env.C_Spell.GetSpellInfo = function(id)
			if id == "Hidden" then
				return { name = wow.SECRET_STRING, spellID = 2 }
			end
			if id == "Blank" then
				return { name = "", spellID = 3 }
			end
			local s = w.state.spells[id]
			return s and { name = s.name, spellID = id, iconID = s.icon }
		end
		w.env.canaccessvalue = function(v)
			return v ~= "abc"
		end
		w.state.actions[3].icon = "abc"
		ns.GlowFetch(true)
		H.eq(ns.SpellBarSlot(999), 2, "known slot even without a spell name")
		H.eq(ns.SpellBarSlot(2), 4, "secret name: the macro token")
		H.eq(ns.SpellBarSlot(3), 4, "empty name: the macro token")
		H.eq(ns.SpellBarSlot("abc"), nil)
		w.state.secret.spellName = true
		H.eq(ns.SpellBarSlot(1), 3)
	end)

	it("swaps the next and heal glow on one button", function()
		local w, ns = boot("WARRIOR", function(w)
			button(w, "ActionButton1", 1, { type = "spell", id = 1 })
		end)
		ns.GlowFetch(true)
		local b = w.env.ActionButton1
		ns.GlowSpell(1)
		ns.queueHeal = { [1] = true }
		ns.GlowSpell(1)
		H.eq(overlayOf(b, "next"):IsShown(), false)
		H.eq(overlayOf(b, "heal"):IsShown(), true)
		ns.queueHeal = {}
		ns.GlowSpell(1)
		H.eq(overlayOf(b, "heal"):IsShown(), false)
	end)

	it("finds a renamed spell, a same-named spell and scans on first use", function()
		local w = wow.new()
		w:player("WARRIOR")
		w.spell(10, { name = "Old", override = 11 })
		w.spell(11, { name = "New" })
		w.spell(12, { name = "Twin" })
		w.spell(13, { name = "Twin" })
		local ns = w:load()
		button(w, "ActionButton1", 1, { type = "spell", id = 11 })
		button(w, "ActionButton2", 2, { type = "spell", id = 12 })
		H.eq(ns.SpellBarSlot(10), 1, "first use scans the bars")
	end)

	it("scans many buttons in steps and drops an outdated scan", function()
		local w, ns = boot("WARRIOR", function(w)
			for i = 1, 12 do
				button(w, "ActionButton" .. i, i, { type = "spell", id = 1 })
				button(w, "MultiBarBottomLeftButton" .. i, 12 + i, { type = "spell", id = 2 })
			end
		end)
		ns.GlowFetch(true)
		ns.GlowFetch(true)
		w:advance(0)
		H.eq(ns.SpellBarSlot(2), 13)
		w.env.C_Timer.After = nil
		ns.GlowFetch(true)
		H.eq(ns.SpellBarSlot(2), 13, "no timers: all at once")
	end)
end)
