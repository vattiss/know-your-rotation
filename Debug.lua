local addonName, ns = ...
local I = ns.API.I
local readable = I.readable

-- Debug mode: samples what the client really answers (secret, nil, value,
-- error) once a second and counts the events it really sends, so questions
-- like "is UnitCreatureType secret on mobs?" are answered by data from the
-- game instead of guessing. Nothing is printed: the numbers live in
-- ns.db.debug (SavedVariables) and ns.Debug.Report() turns them into text
-- (Profiles page, "Debug report").
ns.Debug = ns.Debug or {}
local D = ns.Debug

local MAX_KEYS = 700
local MAX_TEXTS = 150
local SAMPLE_SECONDS = 1

local ticker
local frame

local function store()
	ns.db.debug = ns.db.debug or { counts = {}, texts = {}, keys = 0, textKeys = 0, dropped = 0, samples = 0 }
	return ns.db.debug
end

-- "number", "SECRET number", "nil", "boolean=true" ...: what kind of value
-- came back. Never reads a secret value.
local function classify(value)
	if value == nil then
		return "nil"
	end
	local kind = type(value)
	if issecretvalue(value) then
		return "SECRET " .. kind
	end
	if kind == "boolean" then
		return "boolean=" .. tostring(value)
	end
	return kind
end

-- All return values of a pcall, classified and joined.
local function summarize(ok, ...)
	if not ok then
		return "ERROR " .. tostring((...)):sub(1, 70)
	end
	local count = select("#", ...)
	if count == 0 then
		return "no return"
	end
	local parts = {}
	for i = 1, count do
		parts[i] = classify((select(i, ...)))
	end
	return table.concat(parts, ",")
end

local function count(probe, context, result)
	local d = store()
	local key = probe .. "\t" .. context .. "\t" .. result
	if d.counts[key] == nil then
		if d.keys >= MAX_KEYS then
			d.dropped = d.dropped + 1
			return
		end
		d.keys = d.keys + 1
		d.counts[key] = 0
	end
	d.counts[key] = d.counts[key] + 1
end

-- Short texts the client sends (error messages): the exact wording matters.
local function text(label, message)
	local d = store()
	if type(message) ~= "string" or not readable(message) then
		return
	end
	local key = label .. ": " .. message:sub(1, 80)
	if d.texts[key] == nil then
		if d.textKeys >= MAX_TEXTS then
			return
		end
		d.textKeys = d.textKeys + 1
		d.texts[key] = 0
	end
	d.texts[key] = d.texts[key] + 1
end

local function context()
	local target = "no target"
	if UnitExists("target") then
		target = ns.API.Hostile() and "enemy" or "friend"
	end
	return (ns.API.InCombat() and "combat" or "idle") .. ", " .. target
end

local function probe(name, ctx, fn)
	count(name, ctx, summarize(pcall(fn)))
end

-- First few enabled, learned steps of the current rotation.
local function sampleSpells(ctx)
	local shown = 0
	for _, step in ipairs(ns.GetAPL() or {}) do
		local id = ns.IsStepEnabled(step) and step.id and ns.API.Resolve(step.id)
		if id and shown < 16 then
			shown = shown + 1
			local name = ns.API.SpellName(id) or tostring(id)
			probe("C_Spell.IsSpellUsable | " .. name, ctx, function()
				return C_Spell.IsSpellUsable(id)
			end)
			probe("C_Spell.IsSpellInRange(target) | " .. name, ctx, function()
				return C_Spell.IsSpellInRange(id, "target")
			end)
			probe("C_Spell.GetSpellCooldown start,duration | " .. name, ctx, function()
				local info = C_Spell.GetSpellCooldown(id)
				return info and info.startTime, info and info.duration
			end)
			-- The question behind several rules: does "unusable" mean "out of range"?
			local _, usable, noMana = pcall(C_Spell.IsSpellUsable, id)
			local _, inRange = pcall(C_Spell.IsSpellInRange, id, "target")
			count(
				"usable vs range vs addon | " .. name,
				ctx,
				("usable=%s noMana=%s inRange=%s addonRange=%s"):format(
					classify(usable),
					classify(noMana),
					classify(inRange),
					ns.API.RangeState(id, { hostile = true })
				)
			)
			local why = ns.API.WhyNot(id, step.opt)
			count("addon says | " .. name, ctx, why or "offered")
			count(
				"rank on bar | " .. name,
				ctx,
				("bar=%s known=%s"):format(tostring(ns.GlowBarRank(id)), tostring(ns.API.HighestKnownRank(id)))
			)
			local buttons = ns.GlowButtonNames(id)
			count("glows on buttons | " .. name, ctx, #buttons > 0 and table.concat(buttons, ", ") or "none")
		end
	end
end

local function sampleUnit(ctx, unit)
	probe("UnitHealth(" .. unit .. ")", ctx, function()
		return UnitHealth(unit)
	end)
	probe("UnitHealthMax(" .. unit .. ")", ctx, function()
		return UnitHealthMax(unit)
	end)
	probe("UnitHealthPercent(" .. unit .. ", curve)", ctx, function()
		return UnitHealthPercent(unit, true, CurveConstants.ScaleTo100)
	end)
end

local function sampleTarget(ctx)
	sampleUnit(ctx, "target")
	probe("UnitGUID(target)", ctx, function()
		return UnitGUID("target")
	end)
	probe("UnitCreatureType(target)", ctx, function()
		return UnitCreatureType("target")
	end)
	probe("UnitClassification(target)", ctx, function()
		return UnitClassification("target")
	end)
	probe("UnitLevel(target)", ctx, function()
		return UnitLevel("target")
	end)
	probe("UnitReaction(player, target)", ctx, function()
		return UnitReaction("player", "target")
	end)
	probe("UnitCanAttack(player, target)", ctx, function()
		return UnitCanAttack("player", "target")
	end)
	probe("UnitThreatSituation(player, target)", ctx, function()
		return UnitThreatSituation("player", "target")
	end)
	probe("UnitIsUnit(targettarget, player)", ctx, function()
		return UnitIsUnit("targettarget", "player")
	end)
	probe("UnitDistanceSquared(target) distance,checked", ctx, function()
		return UnitDistanceSquared("target")
	end)
	-- The client blocks this call for a friend in combat (ADDON_ACTION_BLOCKED
	-- named it, and it was this probe): only ask for an enemy, or out of combat.
	probe("CheckInteractDistance(target, 3)", ctx, function()
		local okAtk, canAttack = pcall(UnitCanAttack, "player", "target")
		if ns.API.InCombat() and not (okAtk and canAttack == true) then
			return "skipped: not an enemy, in combat"
		end
		return CheckInteractDistance("target", 3)
	end)
	probe("UnitCastingInfo(target) name,notInterruptible", ctx, function()
		local info = { UnitCastingInfo("target") }
		return info[1], info[8]
	end)
	probe("UnitChannelInfo(target) name,notInterruptible", ctx, function()
		local info = { UnitChannelInfo("target") }
		return info[1], info[7]
	end)
	probe("GetComboPoints(player, target)", ctx, function()
		return GetComboPoints("player", "target")
	end)
	probe("C_UnitAuras debuff 1 name,spellId,expirationTime", ctx, function()
		local aura = C_UnitAuras.GetAuraDataByIndex("target", 1, "HARMFUL")
		return aura and aura.name, aura and aura.spellId, aura and aura.expirationTime
	end)
	probe("C_UnitAuras own debuff 1 (HARMFUL|PLAYER)", ctx, function()
		local aura = C_UnitAuras.GetAuraDataByIndex("target", 1, "HARMFUL|PLAYER")
		return aura and aura.name, aura and aura.spellId
	end)
end

-- The value itself (for slot numbers and IDs), unless it is secret.
local function shown(value)
	return issecretvalue(value) and "SECRET" or tostring(value)
end

-- What each totem bar button says about itself: the action slot, what the slot
-- holds and its icon. The addon reads these buttons like action buttons.
-- The spellbook item type (1 = spell, 2 = not learned yet) of a spell, or "?".
local function bookItemType(spellID)
	local ok, slot, bank = pcall(C_SpellBook.FindSpellBookSlotForSpell, spellID)
	if not ok or not slot then
		return "none"
	end
	local okInfo, info = pcall(C_SpellBook.GetSpellBookItemInfo, slot, bank)
	return okInfo and type(info) == "table" and tostring(info.itemType) or "?"
end

-- Why each enabled step of the defense list (aspects, auras, shields) is or is
-- not offered.
local function sampleDefense(ctx)
	local listed = 0
	for _, step in ipairs(ns.GetDef() or {}) do
		local id = ns.IsStepEnabled(step) and step.id and ns.API.Resolve(step.id)
		if id and listed < 12 then
			listed = listed + 1
			local name = ns.API.SpellName(id) or tostring(id)
			count("defense says | " .. name, ctx, ns.API.WhyNot(id, step.opt) or "offered")
			-- Which of the "do I know this spell" answers say yes (an unlearned
			-- spell must say no everywhere).
			local function yes(fn, ...)
				local ok, answer = pcall(fn, ...)
				return ok and answer and "yes" or "no"
			end
			count(
				"known via | " .. name,
				ctx,
				("same id=%s IsPlayerSpell=%s IsSpellKnown=%s IsSpellKnownOrOverridesKnown=%s inBook=%s bookSlot=%s itemType=%s"):format(
					tostring(id == step.id),
					yes(IsPlayerSpell, step.id),
					yes(IsSpellKnown, step.id),
					yes(IsSpellKnownOrOverridesKnown, step.id),
					yes(C_SpellBook.IsSpellInSpellBook, step.id),
					yes(C_SpellBook.FindSpellBookSlotForSpell, step.id),
					bookItemType(step.id)
				)
			)
		end
	end
end

local function sampleShots(ctx)
	local names = {}
	for _, id in ipairs(ns.BuildShot()) do
		names[#names + 1] = ns.API.SpellName(id) or tostring(id)
	end
	count("shot cue offers", ctx, #names > 0 and table.concat(names, ", ") or "nothing")
end

local function sampleTotemBar(ctx)
	for i = 1, 12 do
		local button = _G["MultiCastActionButton" .. i]
		if button then
			local ok, line = pcall(function()
				local slot = button.action or button:GetAttribute("action")
				local kind, id = GetActionInfo(slot)
				return ("slot=%s type=%s id=%s shown=%s"):format(
					shown(slot),
					shown(kind),
					shown(id),
					shown(button:IsShown())
				)
			end)
			count("MultiCastActionButton" .. i, ctx, ok and line or "ERROR " .. tostring(line):sub(1, 70))
		end
	end
end

-- The totems of the totem bar: what the addon thinks of each, and which one the
-- totem cue offers.
local function sampleTotemCue(ctx)
	-- The cue first: asking it reads the slots and brings the memory up to date.
	local names = {}
	for _, id in ipairs(ns.BuildTotem()) do
		names[#names + 1] = ns.API.SpellName(id) or tostring(id)
	end
	count("totem cue offers", ctx, #names > 0 and table.concat(names, ", ") or "nothing")
	for _, totem in ipairs(ns.API.TotemBar()) do
		local name = ns.API.SpellName(totem.id) or tostring(totem.id)
		count("totem state | " .. name, ctx, ns.API.TotemState(totem.id) .. ", when " .. totem.when)
	end
end

-- The real names the client uses (buffs on you, totems in the slots), out of
-- combat only: in combat they are hidden. Names decide what the addon can match.
local function sampleNames()
	if ns.API.InCombat() then
		return
	end
	for i = 1, 20 do
		local ok, aura = pcall(C_UnitAuras.GetAuraDataByIndex, "player", i, "HELPFUL")
		if not ok or not aura then
			break
		end
		text("buff on you", aura.name)
	end
	for slot = 1, 4 do
		local ok, have, name, start, duration = pcall(GetTotemInfo, slot)
		if ok and readable(have) and have == true then
			text("totem in slot " .. slot, name)
			if readable(start) and readable(duration) then
				text("totem timing", ("%s: lasts %s s, down %d s"):format(name, tostring(duration), GetTime() - start))
			end
		end
	end
end

-- One sample of everything worth knowing; runs once a second in debug mode.
function D.Sample()
	local d = store()
	d.samples = d.samples + 1
	local ctx = context()
	sampleUnit(ctx, "player")
	probe("UnitPower(player, mana)", ctx, function()
		return UnitPower("player", 0)
	end)
	probe("UnitPowerMax(player, mana)", ctx, function()
		return UnitPowerMax("player", 0)
	end)
	probe("UnitPowerPercent(player, mana)", ctx, function()
		return UnitPowerPercent("player", 0, false)
	end)
	probe("UnitPower(player, combo points)", ctx, function()
		return UnitPower("player", 4)
	end)
	probe("UnitAttackSpeed(player)", ctx, function()
		return UnitAttackSpeed("player")
	end)
	probe("UnitRangedDamage(player) speed", ctx, function()
		return (UnitRangedDamage("player"))
	end)
	probe("UnitCastingInfo(player) name,endTime", ctx, function()
		local info = { UnitCastingInfo("player") }
		return info[1], info[5]
	end)
	probe("C_UnitAuras buff 1 name,spellId,expirationTime", ctx, function()
		local aura = C_UnitAuras.GetAuraDataByIndex("player", 1, "HELPFUL")
		return aura and aura.name, aura and aura.spellId, aura and aura.expirationTime
	end)
	if ns.ClassToken() == "SHAMAN" then
		probe("UnitPosition(player) x,y,z,map", ctx, function()
			local x, y, z, map = UnitPosition("player")
			return x, y, z, map
		end)
		for slot = 1, 4 do
			probe("GetTotemInfo(" .. slot .. ") have,name,start,duration", ctx, function()
				local have, name, start, duration = GetTotemInfo(slot)
				return have, name, start, duration
			end)
		end
	end
	if ns.ClassToken() == "SHAMAN" then
		sampleTotemBar(ctx)
		sampleTotemCue(ctx)
	end
	if ns.ClassToken() == "HUNTER" then
		sampleShots(ctx)
	end
	sampleNames()
	probe("UnitAffectingCombat(player)", ctx, function()
		return UnitAffectingCombat("player")
	end)
	probe("UnitExists(target)", ctx, function()
		return UnitExists("target")
	end)
	if UnitExists("pet") then
		sampleUnit(ctx, "pet")
	end
	if UnitExists("target") then
		sampleTarget(ctx)
	end
	sampleSpells(ctx)
	sampleDefense(ctx)
	if ns.healFadeNote then
		count("party heal fade", ctx, ns.healFadeNote)
	end
end

local EVENTS = {
	"UNIT_ATTACK",
	"UNIT_COMBAT",
	"UNIT_SPELLCAST_SUCCEEDED",
	"PLAYER_TOTEM_UPDATE",
	"UI_ERROR_MESSAGE",
}

local function onEvent(_, event, ...)
	local ctx = context()
	if event == "UNIT_SPELLCAST_SUCCEEDED" then
		count("event " .. event .. " spellID", ctx, classify((select(3, ...))))
	elseif event == "UI_ERROR_MESSAGE" then
		local message = select(2, ...)
		count("event " .. event .. " message", ctx, classify(message))
		text("UI_ERROR_MESSAGE", message)
	elseif event == "UNIT_COMBAT" then
		local action = select(2, ...)
		count("event " .. event, ctx, "fired")
		text("UNIT_COMBAT action", action)
	else
		count("event " .. event, ctx, "fired")
	end
end

local function info()
	local d = store()
	local ok, version, build, _, interface = pcall(GetBuildInfo)
	d.info = {
		client = ok and ("%s (build %s, interface %s)"):format(tostring(version), tostring(build), tostring(interface))
			or "unknown",
		addon = tostring(C_AddOns.GetAddOnMetadata(addonName, "Version")),
		class = tostring(ns.ClassToken()),
		level = tostring(UnitLevel("player")),
	}
end

-- Starts or stops the collecting, following ns.db.debugMode.
function D.Apply()
	if ns.db.debugMode == true then
		-- A full store drops every new key: start over, the old data is stale.
		if ns.db.debug and ns.db.debug.keys >= MAX_KEYS then
			D.Clear()
		end
		info()
		if not frame then
			frame = CreateFrame("Frame")
			frame:SetScript("OnEvent", onEvent)
		end
		for _, event in ipairs(EVENTS) do
			if event:find("^UNIT_") then
				frame:RegisterUnitEvent(event, "player")
			else
				frame:RegisterEvent(event)
			end
		end
		if not ticker then
			ticker = C_Timer.NewTicker(SAMPLE_SECONDS, function()
				pcall(D.Sample)
			end)
		end
	else
		if frame then
			frame:UnregisterAllEvents()
		end
		if ticker then
			ticker:Cancel()
			ticker = nil
		end
	end
end

function D.Clear()
	ns.db.debug = nil
end

-- The collected data as text, to copy and send along with a bug report.
function D.Report()
	local d = store()
	local lines = { "Know Your Rotation debug report" }
	local i = d.info or {}
	lines[#lines + 1] = ("client: %s | addon: %s | %s level %s"):format(
		i.client or "?",
		i.addon or "?",
		i.class or "?",
		i.level or "?"
	)
	lines[#lines + 1] = ("samples: %d, keys: %d, dropped: %d"):format(d.samples, d.keys, d.dropped)
	if ns.db.blockedAction then
		lines[#lines + 1] = "blocked action: " .. ns.db.blockedAction
	end
	local probes, byProbe = {}, {}
	for key, n in pairs(d.counts) do
		local name, ctx, result = key:match("^(.-)\t(.-)\t(.*)$")
		if not byProbe[name] then
			byProbe[name] = {}
			probes[#probes + 1] = name
		end
		byProbe[name][#byProbe[name] + 1] = ("  %s -> %s  x%d"):format(ctx, result, n)
	end
	table.sort(probes)
	for _, name in ipairs(probes) do
		lines[#lines + 1] = name
		table.sort(byProbe[name])
		for _, line in ipairs(byProbe[name]) do
			lines[#lines + 1] = line
		end
	end
	local texts = {}
	for key, n in pairs(d.texts) do
		texts[#texts + 1] = ("%s  x%d"):format(key, n)
	end
	table.sort(texts)
	if #texts > 0 then
		lines[#lines + 1] = "texts the client sent"
		for _, line in ipairs(texts) do
			lines[#lines + 1] = "  " .. line
		end
	end
	return table.concat(lines, "\n")
end
