-- A controllable stand-in for the WoW API, enough to load and drive the addon
-- outside the game. Each wow.new() builds a fresh global environment; the
-- addon files run inside it with the usual (addonName, ns) arguments.
--
-- Secret values (Forever / Midnight) are modelled by typed sentinels:
-- wow.SECRET (a number), wow.SECRET_STRING and wow.SECRET_BOOL. Inside the
-- addon's environment type() reports their kind, like the game does, and any
-- arithmetic, concatenation or indexing on them raises an error, so a test
-- fails where the game would.

local wow = {}

local secretKind = {}

local secretMeta = {
	__tostring = function()
		return "<secret>"
	end,
	__eq = function()
		error("compared a secret value", 2)
	end,
	__lt = function()
		error("compared a secret value", 2)
	end,
	__le = function()
		error("compared a secret value", 2)
	end,
	__add = function()
		error("arithmetic on a secret value", 2)
	end,
	__sub = function()
		error("arithmetic on a secret value", 2)
	end,
	__mul = function()
		error("arithmetic on a secret value", 2)
	end,
	__div = function()
		error("arithmetic on a secret value", 2)
	end,
	__concat = function()
		error("concatenated a secret value", 2)
	end,
	__index = function()
		error("indexed a secret value", 2)
	end,
	__len = function()
		error("length of a secret value", 2)
	end,
}

local function makeSecret(kind)
	local v = setmetatable({}, secretMeta)
	secretKind[v] = kind
	return v
end

local SECRET = makeSecret("number")
local SECRET_STRING = makeSecret("string")
local SECRET_BOOL = makeSecret("boolean")
wow.SECRET = SECRET
wow.SECRET_STRING = SECRET_STRING
wow.SECRET_BOOL = SECRET_BOOL

-- The secret stand-in for a value of this Lua type.
local function secretFor(value)
	local t = type(value)
	if t == "string" then
		return SECRET_STRING
	end
	if t == "boolean" then
		return SECRET_BOOL
	end
	return SECRET
end
wow.secretFor = secretFor

local ROOT = "."
function wow.setRoot(root)
	ROOT = root
end

wow.ADDON_FILES = {
	"Locale.lua",
	"API.lua",
	"Data.lua",
	"Physics.lua",
	"Lists.lua",
	"APL.lua",
	"Share.lua",
	"UI.lua",
	"Options.lua",
	"Glow.lua",
	"Rotations.lua",
	"Core.lua",
}

---------------------------------------------------------------------------
-- Generic UI object (frames, textures, font strings, animation groups)
---------------------------------------------------------------------------

local Obj = {}
local objMeta

local function noop() end

local function newObj(w, kind, name, parent, template)
	local o = setmetatable({
		_w = w,
		_kind = kind,
		_name = name,
		_parent = parent,
		_template = template,
		_shown = true,
		_alpha = 1,
		_width = 36,
		_height = 36,
		_scripts = {},
		_events = {},
		_attrs = {},
		_points = {},
		_text = nil,
		_level = 1,
	}, objMeta)
	if name then
		w.env[name] = o
	end
	w.objects[#w.objects + 1] = o
	return o
end

function Obj:GetName()
	return self._name
end
function Obj:GetParent()
	return self._parent
end
function Obj:SetParent(p)
	self._parent = p
end
function Obj:Show()
	local was = self._shown
	self._shown = true
	if not was and self._scripts.OnShow then
		self._scripts.OnShow(self)
	end
end
function Obj:Hide()
	local was = self._shown
	self._shown = false
	if was and self._scripts.OnHide then
		self._scripts.OnHide(self)
	end
end
function Obj:SetShown(v)
	if v then
		self:Show()
	else
		self:Hide()
	end
end
function Obj:IsShown()
	return self._shown
end
function Obj:IsVisible()
	local o = self
	while o do
		if type(o) == "table" and o._shown == false then
			return false
		end
		o = type(o) == "table" and o._parent or nil
	end
	return true
end
function Obj:SetAlpha(a)
	self._alpha = a
end
function Obj:GetAlpha()
	return self._alpha
end
function Obj:SetSize(wd, h)
	self._width, self._height = wd, h
end
function Obj:SetWidth(wd)
	self._width = wd
end
function Obj:SetHeight(h)
	self._height = h
end
function Obj:GetWidth()
	return self._width
end
function Obj:GetHeight()
	return self._height
end
function Obj:SetPoint(...)
	self._points[#self._points + 1] = { ... }
end
function Obj:ClearAllPoints()
	self._points = {}
end
function Obj:SetAllPoints()
	self._points = { { "ALL" } }
end
function Obj:SetScript(event, fn)
	self._scripts[event] = fn
end
function Obj:GetScript(event)
	return self._scripts[event]
end
function Obj:HookScript(event, fn)
	local old = self._scripts[event]
	self._scripts[event] = function(...)
		if old then
			old(...)
		end
		fn(...)
	end
end
function Obj:RegisterEvent(event)
	if self._w.unknownEvents[event] then
		error("unknown event " .. event)
	end
	self._events[event] = true
end
function Obj:RegisterUnitEvent(event, ...)
	self._events[event] = { ... }
end
function Obj:UnregisterEvent(event)
	self._events[event] = nil
end
function Obj:UnregisterAllEvents()
	self._events = {}
end
function Obj:IsEventRegistered(event)
	return self._events[event] ~= nil
end
function Obj:SetText(t)
	self._text = t
end
function Obj:GetText()
	return self._text
end
function Obj:SetFormattedText(fmt, ...)
	self._text = fmt:format(...)
end
function Obj:SetFrameLevel(l)
	self._level = l
end
function Obj:GetFrameLevel()
	return self._level
end
function Obj:SetAttribute(k, v)
	self._attrs[k] = v
end
function Obj:GetAttribute(k)
	return self._attrs[k]
end
function Obj:SetChecked(v)
	self._checked = v and true or false
end
function Obj:GetChecked()
	return self._checked
end
function Obj:SetFocus()
	self._focus = true
end
function Obj:ClearFocus()
	self._focus = false
end
function Obj:HasFocus()
	return self._focus == true
end
function Obj:CreateTexture(name)
	return newObj(self._w, "Texture", name, self)
end
function Obj:CreateFontString(name)
	return newObj(self._w, "FontString", name, self)
end
function Obj:CreateAnimationGroup(name)
	return newObj(self._w, "AnimationGroup", name, self)
end
function Obj:Play()
	self._playing = true
end
function Obj:Stop()
	self._playing = false
end
function Obj:IsPlaying()
	return self._playing == true
end
function Obj:SetVertexColor(r, g, b, a)
	self._color = { r, g, b, a }
end
function Obj:SetTextColor(r, g, b, a)
	self._color = { r, g, b, a }
end
function Obj:SetTexture(t)
	self._texture = t
end
function Obj:GetTexture()
	return self._texture
end
function Obj:SetScrollChild(c)
	self._child = c
end
function Obj:SetupMenu(gen)
	self._menu = gen
end
function Obj:GenerateMenu()
	if self._menu then
		self._w.lastMenu = self._w.newMenuRoot()
		self._menu(self, self._w.lastMenu)
	end
end
function Obj:SetOwner(owner)
	self._owner = owner
	self._lines = {}
end
function Obj:AddLine(text)
	self._lines = self._lines or {}
	self._lines[#self._lines + 1] = text
end
function Obj:AddMessage(text)
	self._w.messages[#self._w.messages + 1] = text
end
function Obj:Click(button)
	if self._scripts.OnClick then
		self._scripts.OnClick(self, button or "LeftButton")
	end
end
-- Run a script the way the client would (tests call it).
function Obj:Fire(script, ...)
	local fn = self._scripts[script]
	if fn then
		return fn(self, ...)
	end
end

objMeta = {
	__index = function(_, key)
		local m = Obj[key]
		if m then
			return m
		end
		-- Any other widget method (SetJustifyH, SetBackdrop, EnableMouse...)
		-- is accepted and does nothing.
		if type(key) == "string" and key:match("^[A-Z]") then
			return noop
		end
		return nil
	end,
}

---------------------------------------------------------------------------
-- Curves (C_CurveUtil) for the hidden-value glows
---------------------------------------------------------------------------

local Curve = {}
Curve.__index = Curve
function Curve:SetType(t)
	self.type = t
end
function Curve:AddPoint(x, y)
	self.points[#self.points + 1] = { x, y }
	table.sort(self.points, function(a, b)
		return a[1] < b[1]
	end)
end
function Curve:Evaluate(x)
	local p = self.points
	if #p == 0 then
		return 0
	end
	if x <= p[1][1] then
		return p[1][2]
	end
	for i = 2, #p do
		if x <= p[i][1] then
			local a, b = p[i - 1], p[i]
			local t = (x - a[1]) / (b[1] - a[1])
			return a[2] + (b[2] - a[2]) * t
		end
	end
	return p[#p][2]
end
local function newCurve()
	return setmetatable({ points = {} }, Curve)
end

---------------------------------------------------------------------------
-- Environment
---------------------------------------------------------------------------

local LUA_GLOBALS = {
	"assert",
	"error",
	"ipairs",
	"next",
	"pairs",
	"pcall",
	"print",
	"rawequal",
	"rawget",
	"rawset",
	"select",
	"setmetatable",
	"getmetatable",
	"tonumber",
	"tostring",
	"type",
	"unpack",
	"xpcall",
	"string",
	"table",
	"math",
	"bit",
	"coroutine",
}

function wow.new()
	local w = {
		objects = {},
		timers = {},
		messages = {},
		printed = {},
		sounds = {},
		unknownEvents = {},
	}
	local state = {
		time = 1000,
		level = 10,
		class = "WARRIOR",
		className = "Warrior",
		race = "Human",
		faction = "Alliance",
		units = {},
		spells = {},
		book = {},
		auras = {},
		totems = {},
		actions = {},
		cvars = {},
		forms = {},
		talents = {},
		enchants = {},
		cursor = nil,
		secret = {},
		swimming = false,
		group = false,
		mounted = false,
		resting = false,
		taxi = false,
		instance = { "Elwynn Forest", "none" },
		position = { 0, 0, 1 },
		addons = {},
		macros = {},
		bindings = {},
	}
	w.state = state
	local env = {}
	w.env = env
	for _, name in ipairs(LUA_GLOBALS) do
		env[name] = _G[name]
	end
	env._G = env
	env.print = function(...)
		local parts = {}
		for i = 1, select("#", ...) do
			parts[i] = tostring((select(i, ...)))
		end
		w.printed[#w.printed + 1] = table.concat(parts, " ")
	end

	-- secret helpers -----------------------------------------------------
	local function hide(kind, value)
		if state.secret[kind] then
			return secretFor(value)
		end
		return value
	end
	w.hide = hide
	env.issecretvalue = function(v)
		return v ~= nil and secretKind[v] ~= nil
	end
	env.canaccessvalue = function(v)
		return v == nil or secretKind[v] == nil
	end
	env.type = function(v)
		local kind = v ~= nil and secretKind[v]
		return kind or type(v)
	end

	-- Lua aliases the client provides ------------------------------------
	env.format = string.format
	env.strlower = string.lower
	env.strupper = string.upper
	env.strsub = string.sub
	env.strfind = string.find
	env.strtrim = function(s)
		return (s:gsub("^%s+", ""):gsub("%s+$", ""))
	end
	env.wipe = function(t)
		for k in pairs(t) do
			t[k] = nil
		end
		return t
	end
	env.GetTime = function()
		return state.time
	end

	-- units ---------------------------------------------------------------
	local function unit(u)
		return u and state.units[u]
	end
	w.unit = function(u, data)
		state.units[u] = data
		if data then
			data.exists = data.exists ~= false
			data.power = data.power or {}
			data.powerMax = data.powerMax or {}
		end
		return data
	end
	env.UnitExists = function(u)
		local d = unit(u)
		return d ~= nil and d.exists == true
	end
	env.UnitIsDead = function(u)
		local d = unit(u)
		return d ~= nil and d.dead == true
	end
	env.UnitIsDeadOrGhost = env.UnitIsDead
	env.UnitHealth = function(u)
		local d = unit(u)
		return hide("health", d and d.health or 0)
	end
	env.UnitHealthMax = function(u)
		local d = unit(u)
		return hide("health", d and d.maxHealth or 0)
	end
	env.UnitHealthPercent = function(u, _, curve)
		local d = unit(u)
		if not d then
			return nil
		end
		local pct = (d.health or 0) / math.max(1, d.maxHealth or 1)
		if state.secret.health or state.secret.healthPercent then
			return SECRET
		end
		if curve then
			return curve:Evaluate(pct)
		end
		return pct * 100
	end
	env.UnitPower = function(u, ptype)
		local d = unit(u)
		return hide("power", d and d.power[ptype or 0] or 0)
	end
	env.UnitPowerMax = function(u, ptype)
		local d = unit(u)
		return hide("power", d and d.powerMax[ptype or 0] or 0)
	end
	env.UnitPowerPercent = function(u, ptype, _, curve)
		local d = unit(u)
		if state.secret.power then
			return SECRET
		end
		local pct = (d and d.power[ptype or 0] or 0) / math.max(1, d and d.powerMax[ptype or 0] or 1)
		return curve and curve:Evaluate(pct) or pct * 100
	end
	env.GetComboPoints = function()
		return hide("power", state.combo or 0)
	end
	env.UnitAffectingCombat = function(u)
		local d = unit(u)
		return d ~= nil and d.combat == true
	end
	env.UnitCanAttack = function(_, u)
		local d = unit(u)
		return d ~= nil and d.hostile == true
	end
	env.UnitReaction = function(_, u)
		local d = unit(u)
		if not d then
			return nil
		end
		return d.reaction or (d.hostile and 2 or 5)
	end
	env.UnitIsPlayer = function(u)
		local d = unit(u)
		return d ~= nil and d.isPlayer == true
	end
	env.UnitIsUnit = function(a, b)
		if state.secret.compare then
			return SECRET_BOOL
		end
		local da, db = unit(a), unit(b)
		return da ~= nil and da == db
	end
	env.UnitGUID = function(u)
		local d = unit(u)
		if not d then
			return nil
		end
		if state.secret.guid or d.secretGuid then
			return SECRET_STRING
		end
		return d.guid
	end
	env.UnitLevel = function(u)
		if u == "player" then
			return state.level
		end
		local d = unit(u)
		return d and d.level or 0
	end
	env.UnitClassification = function(u)
		local d = unit(u)
		return d and d.classification or "normal"
	end
	env.UnitCreatureType = function(u)
		local d = unit(u)
		if state.secret.creature then
			return SECRET_STRING, SECRET
		end
		return d and d.creatureType, d and d.creatureTypeId
	end
	env.UnitClass = function()
		return state.className, state.class, 1
	end
	env.UnitClassBase = function()
		return state.class, 1
	end
	env.UnitRace = function()
		return state.race, state.race, 1
	end
	env.UnitFactionGroup = function()
		return state.faction, state.faction
	end
	env.UnitThreatSituation = function(_, mob)
		local d = unit(mob)
		if state.secret.threat then
			return SECRET
		end
		return d and d.threat
	end
	env.UnitDistanceSquared = function(u)
		local d = unit(u)
		if not d or d.distance == nil then
			return 0, false
		end
		return d.distance * d.distance, true
	end
	env.CheckInteractDistance = function(u, index)
		local d = unit(u)
		if not d or d.distance == nil then
			return nil
		end
		local limits = { 28, 11, 10, 28 }
		return d.distance <= (limits[index] or 10)
	end
	env.UnitPosition = function()
		local p = state.position
		if not p then
			return nil
		end
		return p[1], p[2], 0, p[3]
	end
	env.UnitAttackSpeed = function()
		return hide("stats", state.attackSpeed or 2.6), hide("stats", state.offhandSpeed)
	end
	env.UnitRangedDamage = function()
		return hide("stats", state.rangedSpeed or 0), 0, 0, 0, 0, 0
	end
	env.UnitCastingInfo = function(u)
		local d = unit(u)
		local c = d and d.casting
		if not c then
			return nil
		end
		return c.name, c.name, 0, c.start or 0, c.endTime or 0, false, "cast-guid", c.notInterruptible, c.spellID
	end
	env.UnitChannelInfo = function(u)
		local d = unit(u)
		local c = d and d.channel
		if not c then
			return nil
		end
		return c.name, c.name, 0, c.start or 0, c.endTime or 0, false, c.notInterruptible, c.spellID
	end
	env.UnitOnTaxi = function()
		return state.taxi
	end
	env.IsMounted = function()
		return state.mounted
	end
	env.IsResting = function()
		return state.resting
	end
	env.IsSwimming = function()
		return state.swimming
	end
	env.IsInGroup = function()
		return state.group
	end
	env.GetInstanceInfo = function()
		return state.instance[1], state.instance[2]
	end
	env.InCombatLockdown = function()
		local p = unit("player")
		return p ~= nil and p.combat == true
	end

	-- spells --------------------------------------------------------------
	w.spell = function(id, data)
		data.id = id
		state.spells[id] = data
		if data.known ~= false and data.inBook ~= false then
			state.book[#state.book + 1] = id
		end
		return data
	end
	local function spellByName(name)
		local best
		for id, s in pairs(state.spells) do
			if s.name == name and (not best or (s.known ~= false and state.spells[best].known == false)) then
				best = id
			end
		end
		return best
	end
	local function spellOf(id)
		if type(id) == "string" then
			id = spellByName(id)
		end
		return id and state.spells[id], id
	end
	local function known(id)
		local s = state.spells[id]
		return s ~= nil and s.known ~= false
	end
	env.C_Spell = {
		GetSpellInfo = function(id)
			local s, sid = spellOf(id)
			if not s then
				return nil
			end
			return {
				name = hide("spellName", s.name),
				spellID = sid,
				iconID = s.icon or 136000,
				originalIconID = s.icon,
			}
		end,
		GetOverrideSpell = function(id)
			local s = state.spells[id]
			return s and s.override or id
		end,
		GetSpellCooldown = function(id)
			local s = spellOf(id)
			if state.secret.cooldown then
				return { startTime = SECRET, duration = SECRET }
			end
			local cd = s and s.cooldown
			return { startTime = cd and cd[1] or 0, duration = cd and cd[2] or 0 }
		end,
		GetSpellBaseCooldown = function(id)
			local s = spellOf(id)
			return s and s.baseCooldown or 0, 1500
		end,
		IsSpellUsable = function(id)
			local s = spellOf(id)
			if not s then
				return false, false
			end
			return s.usable ~= false, s.noMana == true
		end,
		IsSpellInRange = function(id)
			local s = spellOf(id)
			return s and s.inRange
		end,
		IsSpellHelpful = function(id)
			local s = spellOf(id)
			return s ~= nil and s.helpful == true
		end,
		IsSpellHarmful = function(id)
			local s = spellOf(id)
			return s ~= nil and s.harmful == true
		end,
		GetSpellDescription = function(id)
			local s = spellOf(id)
			return s and s.desc or ""
		end,
		GetSpellPowerCost = function(id)
			local s = spellOf(id)
			return s and s.cost
		end,
		IsAutoRepeatSpell = function(id)
			local s = spellOf(id)
			return s ~= nil and s.repeating == true
		end,
		GetSpellTexture = function(id)
			local s = spellOf(id)
			return s and (s.icon or 136000)
		end,
	}
	env.GetSpellBaseCooldown = function(id)
		local s = spellOf(id)
		return s and s.baseCooldown or 0, 1500
	end
	env.IsAutoRepeatSpell = function(id)
		local s = spellOf(id)
		return s ~= nil and s.repeating == true
	end
	env.IsPlayerSpell = function(id)
		return known(id)
	end
	env.IsSpellKnown = env.IsPlayerSpell
	env.IsSpellKnownOrOverridesKnown = env.IsPlayerSpell
	env.Enum = {
		SpellBookSpellBank = { Player = 0, Pet = 1 },
		LuaCurveType = { Linear = 0, Step = 1 },
	}
	env.C_SpellBook = {
		GetNumSpellBookSkillLines = function()
			return 1
		end,
		GetSpellBookSkillLineInfo = function()
			return { itemIndexOffset = 0, numSpellBookItems = #state.book }
		end,
		GetSpellBookItemInfo = function(index, bank)
			if bank ~= 0 then
				return nil
			end
			local id = state.book[index]
			local s = id and state.spells[id]
			if not s then
				return nil
			end
			return { name = s.name, spellID = id }
		end,
		GetSpellBookItemName = function(index, bank)
			if bank ~= 0 then
				return nil
			end
			local id = state.book[index]
			return id and state.spells[id] and state.spells[id].name
		end,
		IsSpellInSpellBook = function(id)
			return known(id)
		end,
		FindSpellBookSlotForSpell = function()
			return nil
		end,
	}
	env.GetCursorInfo = function()
		local c = state.cursor
		if not c then
			return nil
		end
		return c[1], c[2], c[3], c[4]
	end
	env.ClearCursor = function()
		state.cursor = nil
	end

	-- auras -----------------------------------------------------------------
	w.aura = function(u, data)
		state.auras[u] = state.auras[u] or {}
		local list = state.auras[u]
		list[#list + 1] = data
		return data
	end
	local function auraMatches(a, filter)
		filter = filter or "HELPFUL"
		local wantHarm = filter:find("HARMFUL", 1, true) ~= nil
		if (a.harmful == true) ~= wantHarm then
			return false
		end
		if filter:find("PLAYER", 1, true) and a.mine == false then
			return false
		end
		return true
	end
	local function auraData(a)
		if state.secret.auras then
			return { name = SECRET_STRING, spellId = SECRET, expirationTime = SECRET, applications = SECRET }
		end
		return {
			name = a.name,
			spellId = a.spellId,
			expirationTime = a.expirationTime or 0,
			duration = a.duration or 0,
			applications = a.applications or 0,
			dispelName = a.dispelName,
			isStealable = a.isStealable,
			sourceUnit = a.mine == false and "party1" or "player",
		}
	end
	local function auraList(u, filter)
		local out = {}
		for _, a in ipairs(state.auras[u] or {}) do
			if auraMatches(a, filter) then
				out[#out + 1] = a
			end
		end
		return out
	end
	env.C_UnitAuras = {
		GetAuraDataByIndex = function(u, index, filter)
			local a = auraList(u, filter)[index]
			return a and auraData(a)
		end,
		GetAuraDataBySpellName = function(u, name, filter)
			if state.secret.auras then
				return nil
			end
			for _, a in ipairs(auraList(u, filter)) do
				if a.name == name then
					return auraData(a)
				end
			end
		end,
		GetPlayerAuraBySpellID = function(id)
			if state.secret.auras then
				return nil
			end
			for _, a in ipairs(auraList("player", "HELPFUL")) do
				if a.spellId == id then
					return auraData(a)
				end
			end
		end,
	}

	-- totems ----------------------------------------------------------------
	env.GetTotemInfo = function(slot)
		if state.secret.totems then
			return SECRET_BOOL, SECRET_STRING, SECRET, SECRET
		end
		local t = state.totems[slot]
		if not t then
			return false, "", 0, 0
		end
		return true, t.name, t.start, t.duration, 0, 1, t.spellID
	end

	-- talents -------------------------------------------------------------
	env.C_SpecializationInfo = {
		GetSpecializationInfo = function(index)
			local t = state.talents[index]
			if not t then
				return nil
			end
			return index, t.name, "", 0, "DAMAGER", 0, t.points
		end,
	}

	-- forms ---------------------------------------------------------------
	env.GetNumShapeshiftForms = function()
		return #state.forms
	end
	env.GetShapeshiftFormInfo = function(i)
		local f = state.forms[i]
		if not f then
			return nil
		end
		return f.icon or 1, f.active == true, true, f.spellID
	end

	-- actions / macros / bindings ---------------------------------------------
	env.HasAction = function(slot)
		return state.actions[slot] ~= nil
	end
	env.GetActionInfo = function(slot)
		local a = state.actions[slot]
		if not a then
			return nil
		end
		return a.type, a.id, a.subType, a.spellID or (a.type == "spell" and a.id or nil)
	end
	env.GetActionTexture = function(slot)
		local a = state.actions[slot]
		return a and a.icon
	end
	env.IsActionInRange = function(slot)
		local a = state.actions[slot]
		return a and a.inRange
	end
	env.GetMacroSpell = function(id)
		local m = state.macros[id]
		return m and m.spell
	end
	env.GetMacroBody = function(id)
		local m = state.macros[id]
		return m and m.body
	end
	env.GetBindingKey = function(command)
		return state.bindings[command]
	end
	env.GetBindingText = function(key)
		return key
	end

	-- items / enchants ----------------------------------------------------
	env.GetInventoryItemID = function(_, slot)
		return state.items and state.items[slot]
	end
	env.C_PaperDollInfo = {
		GetTemporaryEnchantmentInfo = function(slot)
			return state.enchants[slot]
		end,
	}
	env.GetWeaponEnchantInfo = function()
		local m, o = state.enchants[16], state.enchants[17]
		return m ~= nil,
			m and m.remainingTimeMs or 0,
			0,
			m and m.enchantID,
			o ~= nil,
			o and o.remainingTimeMs or 0,
			0,
			o and o.enchantID
	end
	env.C_Item = {
		GetWeaponEnchantInfo = nil,
		GetItemInfoInstant = function(id)
			local item = state.itemInfo and state.itemInfo[id]
			if not item then
				return nil
			end
			return id, "", "", "", 0, item.classID, item.subclassID
		end,
	}
	env.C_TooltipInfo = {
		GetInventoryItem = function(_, slot)
			local lines = state.tooltips and state.tooltips[slot]
			return lines and { lines = lines }
		end,
	}
	env.INVSLOT_MAINHAND = 16
	env.INVSLOT_OFFHAND = 17

	-- cvars / addons / misc -----------------------------------------------
	env.GetCVarBool = function(name)
		return state.cvars[name] == true
	end
	env.C_AddOns = {
		IsAddOnLoaded = function(name)
			return state.addons[name] == true
		end,
	}
	env.C_CurveUtil = {
		CreateCurve = function()
			return newCurve()
		end,
	}
	env.CurveConstants = { ScaleTo100 = setmetatable({ points = { { 0, 0 }, { 1, 100 } } }, Curve) }
	env.PlaySound = function(id)
		w.sounds[#w.sounds + 1] = id
	end
	env.SOUNDKIT = setmetatable({}, {
		__index = function(_, k)
			return k
		end,
	})
	env.CopyToClipboard = function(text)
		w.clipboard = text
	end
	env.CreateColor = function(r, g, b, a)
		return {
			r = r,
			g = g,
			b = b,
			a = a,
			GetRGB = function(self)
				return self.r, self.g, self.b
			end,
			GetRGBA = function(self)
				return self.r, self.g, self.b, self.a
			end,
			GenerateHexColor = function(self)
				return ("ff%02x%02x%02x"):format(self.r * 255, self.g * 255, self.b * 255)
			end,
		}
	end
	env.CreateColorFromHexString = function(hex)
		local r = tonumber(hex:sub(3, 4), 16) / 255
		local g = tonumber(hex:sub(5, 6), 16) / 255
		local b = tonumber(hex:sub(7, 8), 16) / 255
		return env.CreateColor(r, g, b, 1)
	end
	env.RANGE_INDICATOR = "*"
	env.SPELL_FAILED_NOT_BEHIND = "You must be behind your target."
	env.YES, env.NO, env.OKAY, env.CANCEL = "Yes", "No", "Okay", "Cancel"
	env.BOOKTYPE_SPELL, env.BOOKTYPE_PET = "spell", "pet"
	env.StaticPopupDialogs = {}
	env.StaticPopup_Show = function(name, ...)
		w.popup = { name = name, ... }
		return w.popup
	end
	env.ChatEdit_ChooseBoxForSend = function()
		return nil
	end
	env.ChatEdit_ActivateChat = noop
	env.ChatFrame_OpenChat = function(text)
		w.chat = text
	end

	-- frames ---------------------------------------------------------------
	env.CreateFrame = function(kind, name, parent, template)
		local o = newObj(w, kind, name, parent, template)
		if template and template:find("ActionButtonSpellAlertTemplate", 1, true) then
			o.ProcStartAnim = newObj(w, "AnimationGroup", nil, o)
			o.ProcLoop = newObj(w, "AnimationGroup", nil, o)
			o.ProcStartFlipbook = newObj(w, "Texture", nil, o)
			o.ProcLoopFlipbook = newObj(w, "Texture", nil, o)
			o.ProcAltGlow = newObj(w, "Texture", nil, o)
		end
		return o
	end
	env.UIParent = newObj(w, "Frame", "UIParent")
	env.DEFAULT_CHAT_FRAME = newObj(w, "Frame", "DEFAULT_CHAT_FRAME")
	env.DEFAULT_CHAT_FRAME.AddMessage = function(_, text)
		w.printed[#w.printed + 1] = text
	end
	env.UIErrorsFrame = newObj(w, "Frame", "UIErrorsFrame")
	env.GameTooltip = newObj(w, "GameTooltip", "GameTooltip")
	env.MinimalSliderWithSteppersMixin = { Label = { Right = 1 } }

	-- timers ---------------------------------------------------------------
	env.C_Timer = {
		After = function(delay, fn)
			w.timers[#w.timers + 1] = { at = state.time + (delay or 0), fn = fn }
		end,
		NewTicker = function(interval, fn)
			local t = { interval = interval, fn = fn, next = state.time + interval }
			t.Cancel = function(self)
				self.cancelled = true
			end
			t.IsCancelled = function(self)
				return self.cancelled == true
			end
			w.tickers = w.tickers or {}
			w.tickers[#w.tickers + 1] = t
			return t
		end,
	}

	-- settings -------------------------------------------------------------
	local function newSetting(variable, default, getter, setter)
		local s = { variable = variable, default = default, getter = getter, setter = setter }
		function s:GetValue()
			return self.getter and self.getter() or self.value
		end
		function s:SetValue(v)
			self.value = v
			if self.setter then
				self.setter(v)
			end
		end
		function s:GetVariable()
			return self.variable
		end
		return s
	end
	local function newCategory(name, frame)
		local c = { name = name, frame = frame, ID = name }
		function c:GetID()
			return self.ID
		end
		function c:GetName()
			return self.name
		end
		w.categories = w.categories or {}
		w.categories[#w.categories + 1] = c
		return c
	end
	local function newLayout()
		local l = { initializers = {} }
		function l:AddInitializer(i)
			self.initializers[#self.initializers + 1] = i
		end
		return l
	end
	env.Settings = {
		RegisterCanvasLayoutCategory = function(frame, name)
			return newCategory(name, frame), newLayout()
		end,
		RegisterCanvasLayoutSubcategory = function(_, frame, name)
			return newCategory(name, frame), newLayout()
		end,
		RegisterVerticalLayoutCategory = function(name)
			return newCategory(name), newLayout()
		end,
		RegisterVerticalLayoutSubcategory = function(_, name)
			return newCategory(name), newLayout()
		end,
		RegisterAddOnCategory = function(c)
			w.addonCategory = c
		end,
		RegisterProxySetting = function(_, variable, _, _, default, getter, setter)
			local s = newSetting(variable, default, getter, setter)
			w.settings = w.settings or {}
			w.settings[variable] = s
			return s
		end,
		CreateCheckbox = function(_, setting, tooltip)
			return { setting = setting, tooltip = tooltip, kind = "checkbox" }
		end,
		CreateDropdown = function(_, setting, options, tooltip)
			return { setting = setting, options = options, tooltip = tooltip, kind = "dropdown" }
		end,
		CreateSlider = function(_, setting, options, tooltip)
			return { setting = setting, options = options, tooltip = tooltip, kind = "slider" }
		end,
		CreateColorSwatch = function(_, setting, tooltip)
			return { setting = setting, tooltip = tooltip, kind = "color" }
		end,
		CreateSliderOptions = function(min, max, step)
			local o = { min = min, max = max, step = step }
			function o:SetLabelFormatter(where, fn)
				self.formatter = fn
			end
			return o
		end,
		CreateControlTextContainer = function()
			local c = { data = {} }
			function c:Add(value, label, tooltip)
				self.data[#self.data + 1] = { value = value, label = label, tooltip = tooltip }
			end
			function c:GetData()
				return self.data
			end
			return c
		end,
		OpenToCategory = function(id)
			w.openedCategory = id
		end,
		VarType = { Boolean = "boolean", Number = "number", String = "string" },
	}
	env.CreateSettingsListSectionHeaderInitializer = function(text)
		return { kind = "header", text = text }
	end
	w.newMenuRoot = function()
		local root = { items = {} }
		local function add(kind)
			return function(self, text, a, b, c)
				local item = { kind = kind, text = text, a = a, b = b, c = c, items = {} }
				setmetatable(item, { __index = root.__methods })
				self.items[#self.items + 1] = item
				return item
			end
		end
		root.__methods = {
			CreateRadio = add("radio"),
			CreateButton = add("button"),
			CreateCheckbox = add("checkbox"),
			CreateTitle = add("title"),
			CreateDivider = add("divider"),
			SetTooltip = function(self, fn)
				self.tooltip = fn
			end,
		}
		return setmetatable(root, { __index = root.__methods })
	end

	return setmetatable(w, { __index = wow })
end

---------------------------------------------------------------------------
-- Loading and driving
---------------------------------------------------------------------------

-- Load the addon files (all by default) into this environment.
function wow:load(files)
	self.ns = self.ns or {}
	for _, f in ipairs(files or wow.ADDON_FILES) do
		local chunk = assert(loadfile(ROOT .. "/" .. f))
		setfenv(chunk, self.env)
		chunk("KnowYourRotation", self.ns)
	end
	return self.ns
end

-- Fire an event to every frame registered for it.
function wow:fire(event, ...)
	for _, o in ipairs(self.objects) do
		local reg = o._events[event]
		if reg and o._scripts.OnEvent then
			o._scripts.OnEvent(o, event, ...)
		end
	end
end

-- Advance the clock and run due timers and tickers.
function wow:advance(seconds)
	local target = self.state.time + (seconds or 0)
	repeat
		local ran = false
		local due = {}
		for i = #self.timers, 1, -1 do
			local t = self.timers[i]
			if t.at <= target then
				table.remove(self.timers, i)
				table.insert(due, 1, t)
			end
		end
		for _, t in ipairs(due) do
			self.state.time = math.max(self.state.time, t.at)
			t.fn()
			ran = true
		end
	until not ran
	self.state.time = target
	for _, t in ipairs(self.tickers or {}) do
		while not t.cancelled and t.next <= target do
			t.next = t.next + t.interval
			t.fn(t)
		end
	end
end

-- Default player: a level-10 character of the given class.
function wow:player(class, extra)
	self.state.class = class or "WARRIOR"
	self.state.className = (class or "WARRIOR"):sub(1, 1) .. (class or "WARRIOR"):sub(2):lower()
	local data = {
		health = 100,
		maxHealth = 100,
		guid = "Player-1",
		level = self.state.level,
		power = { [0] = 100 },
		powerMax = { [0] = 100 },
	}
	for k, v in pairs(extra or {}) do
		data[k] = v
	end
	return self.unit("player", data)
end

-- An attackable NPC target.
function wow:target(extra)
	local data = {
		health = 100,
		maxHealth = 100,
		hostile = true,
		guid = "Creature-0-1",
		level = self.state.level,
		distance = 5,
	}
	for k, v in pairs(extra or {}) do
		data[k] = v
	end
	return self.unit("target", data)
end

return wow
