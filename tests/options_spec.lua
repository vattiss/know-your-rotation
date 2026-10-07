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

local function control(w, variable)
	for _, c in ipairs(w.controls) do
		if c.setting and c.setting.variable == "KnowYourRotation_" .. variable then
			return c
		end
	end
	error("no control " .. variable)
end

-- Open one canvas page the way the Settings window does.
local function openPage(w, key)
	local panel = w.env["KnowYourRotationPanel" .. key]
	panel:Hide()
	panel:Show()
	return w.ns.UI.options
end

local function radios(w)
	local out = {}
	for _, item in ipairs(w.lastMenu.items) do
		out[#out + 1] = item
	end
	return out
end

describe("Options registration", function()
	it("registers the landing page, sub-pages and controls once", function()
		local w, ns = boot("ROGUE")
		H.truthy(ns.optionsCategory)
		H.eq(w.addonCategory, ns.optionsCategory)
		local count = #w.categories
		ns.RegisterOptions()
		H.eq(#w.categories, count, "only once")
		local names = {}
		for _, c in ipairs(w.categories) do
			names[#names + 1] = c.name
		end
		H.contains(names, ns.T("TAB_HIGHLIGHTS"))
		H.contains(names, ns.T("TAB_ROTATION"))
	end)

	it("skips without the Settings API and without timers", function()
		local w = wow.new()
		w:player("WARRIOR")
		w.env.Settings = nil
		local ns = w:load()
		w:fire("PLAYER_LOGIN")
		H.eq(ns.optionsCategory, nil)
		local w2 = wow.new()
		w2:player("WARRIOR")
		w2.env.C_Timer.After = nil
		w2.env.CreateColorFromHexString = nil
		local ns2 = w2:load()
		w2:fire("PLAYER_LOGIN")
		H.truthy(ns2.optionsCategory)
	end)

	it("adds only the cues the class can use", function()
		local wm = boot("MAGE")
		local function has(w, variable)
			for _, c in ipairs(w.controls) do
				if c.setting.variable == "KnowYourRotation_" .. variable then
					return true
				end
			end
			return false
		end
		H.eq(has(wm, "showInterrupt"), true)
		H.eq(has(wm, "showPurge"), true)
		H.eq(has(wm, "showCleanse"), true, "Remove Lesser Curse")
		H.eq(has(wm, "showWeapon"), false)
		local wr = boot("ROGUE", function(w)
			w.spell(8679, { name = "Instant Poison" })
		end)
		H.eq(has(wr, "weaponBuffOff"), true, "rogue picks per hand")
		local ws = boot("SHAMAN")
		H.eq(has(ws, "weaponBuff"), true)
		H.eq(has(ws, "weaponBuffOff"), false)
		H.eq(has(ws, "showCleanse"), true)
		local wwar = boot("WARRIOR")
		wwar.state.class = nil
		H.eq(has(wwar, "showPurge"), false)
	end)
end)

describe("Options native pages", function()
	it("reads and writes every switch, list and slider", function()
		local w, ns = boot("ROGUE", function(w)
			w.spell(8679, { name = "Instant Poison" })
			w.spell(2823, { name = "Deadly Poison" })
		end)
		for _, c in ipairs(w.controls) do
			local s = c.setting
			local value = s:GetValue()
			if c.kind == "checkbox" then
				s:SetValue(not value)
				s:SetValue(value)
			elseif c.kind == "dropdown" then
				local items = c.options()
				H.truthy(#items >= 1, s.variable)
				s:SetValue(items[#items].value)
				s:SetValue(value)
			elseif c.kind == "slider" then
				s:SetValue(5)
				H.eq(ns.db.autoEnemies, 5)
				H.eq(c.options.formatter(4), "4")
			elseif c.kind == "color" then
				s:SetValue("ff336699")
				H.eq(math.floor(ns.db.colors[s.variable:match("color_(.+)$")][1] * 255 + 0.5), 0x33)
				s:SetValue(value)
			end
		end
		control(w, "weaponBuff").setting:SetValue("DeadlyPoison")
		H.eq(control(w, "weaponBuff").setting:GetValue(), "DeadlyPoison")
		ns.db.weaponBuff = "Nothing"
		H.eq(control(w, "weaponBuff").setting:GetValue(), "auto")
		w.state.spells[8679].known = false
		w.state.spells[2823].known = false
		ns.API.InvalidateSpells(true)
		H.eq(control(w, "weaponBuff").options()[1].label, ns.T("OPT_AUTOMATIC"))
		control(w, "soundKick").setting:SetValue(nil)
		H.eq(control(w, "soundKick").setting:GetValue(), "none")
		ns.ApplyFeatureFlags = nil
		control(w, "muted").setting:SetValue(true)
		H.eq(ns.db.muted, true)
		ns.FlushProfile, ns.InvalidateAPLCache, ns.Tick = nil, nil, nil
		control(w, "muted").setting:SetValue(false)
		control(w, "autoEnemies").setting:SetValue("x")
		H.eq(ns.db.autoEnemies, 3)
		ns.db.autoEnemies = nil
		H.eq(control(w, "autoEnemies").setting:GetValue(), 3)
		local color = control(w, "color_next").setting
		w.env.CreateColorFromHexString = function()
			return nil
		end
		color:SetValue("bad")
		ns.GlowInvalidate = nil
		w.env.CreateColorFromHexString = function()
			return { r = 1, g = 0, b = 0 }
		end
		color:SetValue("ffff0000")
	end)

	it("lists roles for an unknown class", function()
		local w, ns = boot("WARRIOR")
		ns.ClassToken = function()
			return nil
		end
		local items = control(w, "role").options()
		H.eq(items[2].value, "damage")
	end)

	it("works without the slider label mixin", function()
		local w = wow.new()
		w:player("WARRIOR")
		w.env.MinimalSliderWithSteppersMixin = nil
		w:load()
		w:fire("PLAYER_LOGIN")
		H.eq(control(w, "autoEnemies").options.formatter, nil)
	end)
end)

describe("Options landing page", function()
	it("shows the detected state and copies the links", function()
		local w, ns = boot("ROGUE")
		local home = w.env.KnowYourRotationPanelHome
		home:Show()
		ns.db.muted = true
		ns.db.roleAuto = false
		ns.db.combatMode = "aoe"
		ns.db.autoProfile = false
		home:Hide()
		home:Show()
		ns.db.combatMode = "auto"
		ns.ResolveCombatMode = function()
			return "aoe"
		end
		home:Hide()
		home:Show()
		ns.ResolveCombatMode = nil
		home:Hide()
		home:Show()
		-- Link rows: the copy button and the box scripts.
		local copies = {}
		for _, o in ipairs(w.objects) do
			if o._kind == "Button" and o:GetText() == ns.T("INFO_COPY") then
				copies[#copies + 1] = o
			end
			if o._kind == "EditBox" and o:GetScript("OnEditFocusGained") then
				o:Fire("OnEditFocusGained")
				o:Fire("OnEscapePressed")
				o:Fire("OnEnterPressed")
			end
		end
		H.eq(#copies, 2)
		copies[1]:Click()
		H.eq(w.chat, "https://github.com/vattiss/know-your-rotation")
		w.env.DEFAULT_CHAT_FRAME.editBox = w.env.CreateFrame("EditBox")
		copies[1]:Click()
		w.env.ChatFrame_OpenChat = function()
			error("no chat")
		end
		w.env.CopyToClipboard = nil
		copies[2]:Click()
		w.env.ChatEdit_ChooseBoxForSend = function()
			return w.env.CreateFrame("EditBox")
		end
		copies[2]:Click()
		w.env.ChatEdit_ChooseBoxForSend = function()
			error("boom")
		end
		w.env.DEFAULT_CHAT_FRAME.editBox = nil
		copies[2]:Click()
		w.env.ChatFrame_OpenChat = nil
		w.env.ChatEdit_ChooseBoxForSend = nil
		w.env.ChatEdit_ActivateChat = nil
		copies[1]:Click()
		w.env.DEFAULT_CHAT_FRAME = nil
		copies[1]:Click()
	end)
end)

describe("Options list editor", function()
	local function page(class, key, setup)
		local w, ns = boot(class or "ROGUE", function(w)
			w.spell(1784, { name = "Stealth", helpful = true })
			w.spell(1752, { name = "Sinister Strike", harmful = true })
			w.spell(2098, { name = "Eviscerate", harmful = true })
			if setup then
				setup(w)
			end
		end)
		ns.API.InvalidateSpells(true)
		local frame = openPage(w, key or "rotation")
		return w, ns, frame
	end

	it("builds the rotation page with rows for the list", function()
		local _, ns, frame = page()
		H.eq(frame.activeTab, "rotation")
		H.truthy(#frame.aplRows >= 10)
		H.eq(frame.aplRows[1].label:GetText(), "Stealth")
		H.truthy(frame.editLabel:GetText():find(ns.T("EDIT_IN_USE"), 1, true), "list in use")
		H.eq(frame.listHint:GetText(), ns.T("OPT_AUTO_HINT"))
	end)

	it("edits rows: toggle, move, remove, hold, drag and drop", function()
		local w, ns, frame = page()
		local row = frame.aplRows[1]
		row.box:SetChecked(false)
		row.box:Click()
		H.eq(ns.GetAPL(nil, "damage", "auto")[1].on, false)
		frame.aplRows[2].up:Click()
		H.eq(ns.GetAPL(nil, "damage", "auto")[1].key, "Garrote")
		frame.aplRows[1].down:Click()
		frame.aplRows[1].del:Click()
		H.eq(ns.db.aplDrop.ROGUE.damage.auto.Stealth, true)
		frame.holdToggle:SetChecked(true)
		frame.holdToggle:Click()
		local hold = frame.aplRows[1].hold
		hold:SetText("7")
		hold:Fire("OnEnterPressed")
		H.eq(ns.GetAPL(nil, "damage", "auto")[1].opt.hold, 7)
		hold:SetText("")
		hold:Fire("OnEditFocusLost")
		hold:Fire("OnEscapePressed")
		w.state.cursor = { "spell", 1784 }
		frame.aplRows[1]:Fire("OnReceiveDrag")
		H.eq(ns.GetAPL(nil, "damage", "auto")[1].key, "Stealth", "dropped on row 1")
		w.state.cursor = { "spell", 1784 }
		frame.aplRows[2]:Fire("OnMouseUp")
		frame.aplRows[2]:Fire("OnMouseUp")
		w.state.cursor = { "spell", 2098 }
		frame.addSpell:Fire("OnReceiveDrag")
		frame.addSpell:Click()
		w.state.cursor = { "spell", 2098 }
		frame.addSpell:Click()
		for _, b in ipairs({ frame.resetApl, frame.holdToggle, frame.addSpell, frame.aplRows[1].del }) do
			b:Fire("OnEnter")
			b:Fire("OnLeave")
		end
		ns.DropSpellOnList(1)
		w.env.ClearCursor = nil
		w.state.cursor = { "spell", 2098 }
		ns.DropSpellOnList(1)
		frame.resetApl:Click()
		H.eq(ns.db.apl.ROGUE.damage.auto, nil)
		frame.aplRows[1].box.stepKey = nil
		frame.aplRows[1].box:Click()
		frame.aplRows[1].up.index = nil
		frame.aplRows[1].up:Click()
		frame.aplRows[1].down.index = nil
		frame.aplRows[1].down:Click()
		frame.aplRows[1].del.stepKey = nil
		frame.aplRows[1].del:Click()
		hold.stepKey = nil
		hold:Fire("OnEditFocusLost")
	end)

	it("explains each row in its tooltip", function()
		local w, ns, frame = page("ROGUE", "rotation", function(w)
			w.spell(1856, { name = "Vanish" })
		end)
		local tip = w.env.GameTooltip
		local function why(row)
			row:Fire("OnEnter")
			row:Fire("OnLeave")
			return tip._lines[2]
		end
		H.eq(why(frame.aplRows[3]), ns.T("WHY_NOT_KNOWN"), "Ambush not learned")
		ns.SetAPLEnabled("Stealth", false, nil, "damage", "auto")
		ns.RefreshOptions()
		H.eq(why(frame.aplRows[1]), ns.T("WHY_SWITCHED_OFF"))
		ns.SetAPLEnabled("Stealth", true, nil, "damage", "auto")
		ns.RefreshOptions()
		H.truthy(why(frame.aplRows[1]):find("only with an enemy targeted", 1, true))
		ns.API.WhyNot = function()
			return nil
		end
		H.eq(why(frame.aplRows[1]), ns.T("WHY_READY"))
		frame.aplRows[1].stepId = nil
		frame.aplRows[1]:Fire("OnEnter")
		local _ = w
	end)

	it("switches spec and mode from the dropdowns", function()
		local w, ns, frame = page("DRUID", "rotation", function(w)
			w.spell(5176, { name = "Wrath", harmful = true })
		end)
		frame.specDrop:GenerateMenu()
		local specs = radios(w)
		H.eq(specs[1].text, ns.T("SPEC_CASTER"))
		H.eq(specs[2].text, ns.T("SPEC_CAT"))
		H.eq(specs[3].text, ns.T("SPEC_BEAR"))
		specs[2].b("cat")
		H.eq(specs[2].a("cat"), true)
		frame.modeDrop:GenerateMenu()
		local modes = radios(w)
		modes[3].b("aoe")
		H.eq(modes[3].a("aoe"), true)
		H.eq(frame.listHint:GetText(), ns.T("OPT_LIST_HINT"))
		specs[1].b("damage")
		modes[2].b("single")
	end)

	it("edits the defense list on its own page", function()
		local w, ns, frame = page("WARRIOR", "def", function(w)
			w.spell(6673, { name = "Battle Shout", helpful = true })
		end)
		H.eq(frame.activeTab, "def")
		H.eq(frame.modeDrop:IsShown(), false)
		local row = frame.aplRows[1]
		row.box:SetChecked(false)
		row.box:Click()
		frame.aplRows[2].up:Click()
		frame.aplRows[1].down:Click()
		frame.holdToggle:SetChecked(true)
		frame.holdToggle:Click()
		frame.aplRows[1].hold:SetText("4")
		frame.aplRows[1].hold:Fire("OnEnterPressed")
		frame.aplRows[1].del:Click()
		w.state.cursor = { "spell", 6673 }
		frame.addSpell:Fire("OnReceiveDrag")
		frame.resetApl:Click()
		H.eq(ns.db.def.WARRIOR.damage, nil)
	end)

	it("exports and imports on the profiles page", function()
		local w, ns, frame = page("ROGUE", "profiles")
		H.eq(frame.activeTab, "profiles")
		frame.exportBtn:Click()
		H.truthy(frame.shareEdit:GetText():find("^WFR1"))
		frame.shareEdit:Fire("OnEscapePressed")
		frame.importBtn:Click()
		H.contains(w.printed, "|cff66ccffKnow Your Rotation|r: " .. ns.T("OPT_IMPORT_OK"))
		frame.shareEdit:SetText("WFR1\nC=MAGE")
		frame.importBtn:Click()
		frame.shareEdit:SetText(nil)
		frame.importBtn:Click()
		frame.resetAll:Click()
		ns.ImportProfile = nil
		frame.importBtn:Click()
		ns.ExportProfile = nil
		frame.exportBtn:Click()
	end)

	it("keeps rows for longer lists and hides the extra ones later", function()
		local w, ns, frame = page()
		local before = #frame.aplRows
		local full = ns.GetAPL
		ns.GetAPL = function()
			return { full()[1] }
		end
		ns.RefreshOptions()
		H.eq(frame.aplRows[2]:IsShown(), false)
		H.eq(#frame.aplRows, before)
		local _ = w
	end)

	it("labels racials and unknown spells", function()
		local w, ns, frame = page("ROGUE", "rotation", function(w)
			w.state.race = "Orc"
			w.env.UnitRace = function()
				return "Orc", "Orc", 2
			end
		end)
		ns.db.showHoldColumn = true
		ns.SPELL_HOLD[ns.Spell.Rogue.Stealth] = 5
		ns.SaveAPL({ { key = "Stealth", on = 1 } }, nil, "damage", "auto")
		ns.RefreshOptions()
		local found
		for _, row in ipairs(frame.aplRows) do
			if row:IsShown() and row.label:GetText():find(ns.T("RACIAL_PREFIX"):format(""), 1, true) then
				found = true
			end
		end
		H.truthy(found, "racial row")
		local _ = w
	end)
end)

describe("Options page host", function()
	it("is built early out of combat and warmed once", function()
		local w, ns = boot("ROGUE")
		w.state.units.player.combat = true
		ns.PrebuildOptions()
		H.eq(ns.UI.options, nil, "not in combat")
		w.state.units.player.combat = false
		ns.PrebuildOptions()
		H.truthy(ns.UI.options)
		ns.PrebuildOptions()
		w:advance(3)
		H.truthy(#ns.UI.options.aplRows > 0, "rows warmed")
		ns.UI.options:Show()
		ns.WarmOptionsList()
		ns.UI.options:Hide()
		w.state.units.player.combat = true
		ns.WarmOptionsList()
		w.state.units.player.combat = false
		w.env.C_Timer.After = nil
		ns.UI.options = nil
		ns.PrebuildOptions()
		ns.UI.options = nil
		ns.WarmOptionsList()
	end)

	it("refreshes only when visible and reports a failing page", function()
		local w, ns = boot("ROGUE")
		ns.RefreshOptions()
		H.eq(ns.UI.options, nil)
		local frame = openPage(w, "rotation")
		ns.ActiveSpec = function()
			return "nope"
		end
		ns.CombatMode = function()
			return "single"
		end
		openPage(w, "rotation")
		ns.ProfileKey = nil
		ns.ResolveCombatMode = nil
		ns.CombatMode = nil
		frame.ShowTab("rotation")
		ns.RefreshOptions()
		ns.SpecList = function()
			error("broken")
		end
		openPage(w, "rotation")
		H.truthy(w.printed[#w.printed]:find("broken", 1, true))
		frame.shareHint = nil
		frame.resetAll = nil
		frame.resetApl = nil
		frame.exportBtn = nil
		frame.importBtn = nil
		frame.RelocalizeChrome()
		frame.ShowTab("other")
	end)
end)
