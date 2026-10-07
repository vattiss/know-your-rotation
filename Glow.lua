local addonName, ns = ...
local API = ns.API

-- Built-in client art only: no texture files ship with the addon.
local GLOW_ART = "Interface\\Cooldown\\star4" -- fallback if the spell-alert glow template is missing
local BARS = {
	"Action",
	"MultiBarBottomLeft",
	"MultiBarBottomRight",
	"MultiBarRight",
	"MultiBarLeft",
	"MultiBar5",
	"MultiBar6",
	"MultiBar7",
}

local spells = {}
local spellsByName = {}
local buttonSlots = {}
local damageGlowing = {}
local defenseGlowing = {}
local kickGlowing = {}
local purgeGlowing = {}
local lastSpell
local lastSpellHeal
local lastDef
local lastDefHeal
local lastKick
local lastPurge
local lastFetch = 0
local glowFetchGen = 0
local addonCache = {}

local function addonLoaded(name)
	if addonCache[name] ~= nil then
		return addonCache[name]
	end
	local loaded = false
	if C_AddOns and C_AddOns.IsAddOnLoaded then
		local ok, value = pcall(C_AddOns.IsAddOnLoaded, name)
		if ok then
			loaded = value and true or false
		end
	end
	addonCache[name] = loaded
	return loaded
end

local spellsByNorm = {}
local buttonsByIcon = {}

local function isToken(value, expected)
	if value == nil or expected == nil then
		return false
	end
	if issecretvalue and issecretvalue(value) then
		return false
	end
	local ok, same = pcall(function()
		return value == expected
	end)
	return ok and same == true
end

-- name: a readable, non-empty spell name (the callers check).
local function normKey(name)
	local lower = strtrim(strlower((name:gsub("%s*%([^)]*%)%s*$", ""))))
	if lower ~= "" then
		return lower
	end
end

local function addSpellName(name, button)
	spellsByName[name] = spellsByName[name] or {}
	spellsByName[name][#spellsByName[name] + 1] = button
	local key = normKey(name)
	if key then
		spellsByNorm[key] = spellsByNorm[key] or {}
		spellsByNorm[key][#spellsByNorm[key] + 1] = button
	end
end

local function plainID(value)
	if value == nil or value == 0 or value == "" then
		return nil
	end
	if issecretvalue and issecretvalue(value) then
		return nil
	end
	if canaccessvalue and not canaccessvalue(value) then
		return nil
	end
	local ok, n = pcall(function()
		local v = tonumber(value)
		if type(v) ~= "number" then
			return nil
		end
		return v + 0
	end)
	if ok and type(n) == "number" and n > 0 then
		return n
	end
	return nil
end

local function spellName(spellID)
	spellID = plainID(spellID)
	if not spellID then
		return
	end
	local info = API.SpellInfo(spellID)
	local name = info and info.name
	if type(name) ~= "string" or name == "" then
		return
	end
	return name
end

local function overlay(button, key, texture, r, g, b, scale, alpha)
	scale = scale or 1.25
	alpha = alpha or 0.85
	button.KYROverlays = button.KYROverlays or {}
	local frame = button.KYROverlays[key]
	-- The default highlight uses Blizzard's own spell-alert glow (the retail
	-- "proc" animation). Our own instance, never the one the action-bar manager
	-- drives, so real procs are unaffected. Falls back to a plain texture.
	local wantAlert = texture == GLOW_ART
	if not frame then
		if wantAlert then
			local ok, alert = pcall(CreateFrame, "Frame", nil, button, "ActionButtonSpellAlertTemplate")
			if ok and alert and alert.ProcStartAnim and alert.ProcLoop then
				frame = alert
				frame.isAlert = true
				frame:SetFrameStrata("MEDIUM")
				frame:SetFrameLevel((button.GetFrameLevel and button:GetFrameLevel() or 4) + 6)
				frame:SetPoint("CENTER", button, "CENTER", 0, 0)
				frame:SetScript("OnShow", function(self)
					self.ProcLoop:Stop()
					self.ProcStartAnim:Play()
				end)
				frame:SetScript("OnHide", function(self)
					self.ProcStartAnim:Stop()
					self.ProcLoop:Stop()
				end)
				if frame.ProcAltGlow then
					frame.ProcAltGlow:Hide()
				end
				frame:Hide()
				button.KYROverlays[key] = frame
			end
		end
		if not frame then
			frame = CreateFrame("Frame", nil, button)
			frame:SetFrameStrata("MEDIUM")
			frame:SetFrameLevel((button.GetFrameLevel and button:GetFrameLevel() or 4) + 6)
			frame:SetPoint("CENTER", button, "CENTER", 0, 0)
			local tex = frame:CreateTexture(nil, "OVERLAY")
			tex:SetAllPoints(frame)
			frame.texture = tex
			frame:Hide()
			button.KYROverlays[key] = frame
		end
	end
	local w = button.GetWidth and button:GetWidth() or 36
	local h = button.GetHeight and button:GetHeight() or 36
	if w < 8 then
		w = 36
	end
	if h < 8 then
		h = 36
	end
	frame:SetSize(w * scale, h * scale)
	if frame.isAlert then
		-- Desaturate so the role colour tints the glow instead of mixing with gold.
		for _, tex in ipairs({ frame.ProcStartFlipbook, frame.ProcLoopFlipbook }) do
			if tex then
				tex:SetDesaturated(true)
				tex:SetVertexColor(r, g, b)
			end
		end
		frame.kyrAlpha = alpha
		frame:SetAlpha(alpha)
		return frame
	end
	frame.texture:SetTexture(texture)
	frame.texture:SetBlendMode("ADD")
	frame.texture:SetVertexColor(r, g, b, alpha)
	return frame
end

local function showDamage(button, isHeal)
	if isHeal then
		if button.KYROverlays and button.KYROverlays.next then
			button.KYROverlays.next:Hide()
		end
		local r, g, b = ns.Color("heal")
		overlay(button, "heal", GLOW_ART, r, g, b, 1.45, 0.95):Show()
	else
		if button.KYROverlays and button.KYROverlays.heal then
			button.KYROverlays.heal:Hide()
		end
		local r, g, b = ns.Color("next")
		overlay(button, "next", GLOW_ART, r, g, b, 1.45, 0.9):Show()
	end
	damageGlowing[button] = true
end

local function hideDamage(button)
	if button.KYROverlays then
		if button.KYROverlays.next then
			button.KYROverlays.next:Hide()
		end
		if button.KYROverlays.heal then
			button.KYROverlays.heal:Hide()
		end
	end
	damageGlowing[button] = nil
end

local function showDefense(button, isHeal)
	if isHeal then
		local r, g, b = ns.Color("heal")
		overlay(button, "def", GLOW_ART, r, g, b, 1.45, 0.95):Show()
	else
		local r, g, b = ns.Color("def")
		overlay(button, "def", GLOW_ART, r, g, b, 1.45, 0.92):Show()
	end
	defenseGlowing[button] = true
end

local function hideDefense(button)
	if button.KYROverlays and button.KYROverlays.def then
		button.KYROverlays.def:Hide()
	end
	defenseGlowing[button] = nil
end

local function showKick(button)
	overlay(button, "kick", GLOW_ART, 1, 1, 0.35, 1.3, 0.9):Show()
	kickGlowing[button] = true
end

local function hideKick(button)
	if button.KYROverlays and button.KYROverlays.kick then
		button.KYROverlays.kick:Hide()
	end
	kickGlowing[button] = nil
end

local function showPurge(button)
	overlay(button, "purge", GLOW_ART, 0.85, 0.35, 1, 1.3, 0.9):Show()
	purgeGlowing[button] = true
end

local function hidePurge(button)
	if button.KYROverlays and button.KYROverlays.purge then
		button.KYROverlays.purge:Hide()
	end
	purgeGlowing[button] = nil
end

local function addButton(spellID, button, slot)
	local id = plainID(spellID)
	if not id or not button then
		return
	end
	spells[id] = spells[id] or {}
	spells[id][#spells[id] + 1] = button
	local name = spellName(id)
	if not name then
		if slot then
			buttonSlots[button] = slot
		end
		return
	end
	spellsByName[name] = spellsByName[name] or {}
	spellsByName[name][#spellsByName[name] + 1] = button
	local key = normKey(name)
	if key then
		spellsByNorm[key] = spellsByNorm[key] or {}
		spellsByNorm[key][#spellsByNorm[key] + 1] = button
	end
	if slot then
		buttonSlots[button] = slot
	end
end

local function actionSlot(button)
	local slot
	if button.GetAttribute then
		local ok, value = pcall(button.GetAttribute, button, "action")
		if ok and value and value ~= 0 then
			slot = value
		end
	end
	if (not slot or slot == 0) and button.GetPagedID then
		local ok, value = pcall(button.GetPagedID, button)
		if ok and value and value ~= 0 then
			slot = value
		end
	end
	if (not slot or slot == 0) and button.CalculateAction then
		local ok, value = pcall(button.CalculateAction, button)
		if ok and value and value ~= 0 then
			slot = value
		end
	end
	if (not slot or slot == 0) and button.action and button.action ~= 0 then
		slot = button.action
	end
	return slot
end

local function plainTexture(value)
	if value == nil or value == "" or value == 0 then
		return nil
	end
	if issecretvalue and issecretvalue(value) then
		return nil
	end
	if canaccessvalue and not canaccessvalue(value) then
		return nil
	end
	if type(value) == "number" and value > 0 then
		return value
	end
	if type(value) == "string" and value ~= "" then
		return value:lower()
	end
	return nil
end

local function addIcon(key, button)
	if not key or not button then
		return
	end
	buttonsByIcon[key] = buttonsByIcon[key] or {}
	buttonsByIcon[key][#buttonsByIcon[key] + 1] = button
end

local function indexButtonIcon(button, slot)
	if slot and GetActionTexture then
		local ok, tex = pcall(GetActionTexture, slot)
		if ok then
			addIcon(plainTexture(tex), button)
		end
	end
	local icon = button.icon or button.Icon
	if not icon and button.GetName then
		icon = _G[button:GetName() .. "Icon"]
	end
	if icon and icon.GetTexture then
		local ok, tex = pcall(icon.GetTexture, icon)
		if ok then
			addIcon(plainTexture(tex), button)
		end
	end
end

local function spellIconKeys(spellID)
	local keys = {}
	local function add(value)
		local key = plainTexture(value)
		if key then
			keys[key] = true
		end
	end
	if not spellID then
		return keys
	end
	if C_Spell and C_Spell.GetSpellTexture then
		local ok, tex = pcall(C_Spell.GetSpellTexture, spellID)
		if ok then
			add(tex)
		end
	end
	local info = API.SpellInfo(spellID)
	if type(info) == "table" then
		add(info.iconID)
		add(info.originalIconID)
	end
	return keys
end

-- button: an existing frame (the scan queue only holds real buttons).
local function addStandard(button)
	local okType, attrType = pcall(function()
		return button:GetAttribute("type")
	end)
	if not okType then
		attrType = nil
	end
	local slot = actionSlot(button)
	local actionType, id = attrType, nil
	if attrType == "action" or (not attrType and slot) then
		if slot and HasAction then
			local okHas, has = pcall(HasAction, slot)
			if okHas and has then
				local okInfo, t, actionID, _, spellFromAction = pcall(GetActionInfo, slot)
				if okInfo and isToken(t, "spell") then
					actionType = "spell"
					id = plainID(spellFromAction) or plainID(actionID)
				elseif okInfo and isToken(t, "macro") then
					actionType, id = "macro", actionID
				end
			end
		end
	elseif attrType == "spell" then
		local ok, value = pcall(button.GetAttribute, button, "spell")
		if ok then
			id = value
		end
	elseif attrType == "macro" then
		local ok, value = pcall(button.GetAttribute, button, "macro")
		if ok then
			id = value
		end
	end
	local macroId = actionType == "macro" and id or nil
	if macroId and GetMacroSpell then
		local ok, spellID = pcall(GetMacroSpell, macroId)
		local macroSpell = ok and plainID(spellID)
		if macroSpell then
			id = macroSpell
			actionType = "spell"
		end
	end
	if macroId and GetMacroBody then
		local okBody, body = pcall(GetMacroBody, macroId)
		if okBody and type(body) == "string" then
			for line in body:gmatch("[^\r\n]+") do
				local payload = line:match("^%s*#showtooltip%s+(.+)$") or line:match("^%s*/%S+%s+(.+)$")
				if payload then
					payload = payload:gsub("%b[]", " ")
					for token in payload:gmatch("[^,;]+") do
						token = token:gsub("^%s+", ""):gsub("%s+$", ""):gsub("^!", "")
						token = token:gsub("%s*%([^)]*%)%s*$", "")
						if token ~= "" and C_Spell and C_Spell.GetSpellInfo then
							local okInfo, info = pcall(C_Spell.GetSpellInfo, token)
							if okInfo and type(info) == "table" then
								local spellId = plainID(info.spellID)
								local spellLabel = info.name
								if issecretvalue and issecretvalue(spellLabel) then
									spellLabel = nil
								end
								if type(spellLabel) == "string" and spellLabel ~= "" then
									addSpellName(spellLabel, button)
								else
									addSpellName(token, button)
								end
								if spellId then
									addButton(spellId, button, slot)
								end
							end
						end
					end
				end
			end
		end
	end
	if slot and HasAction then
		local okHas, has = pcall(HasAction, slot)
		if okHas and has then
			indexButtonIcon(button, slot)
		end
	end
	if slot then
		buttonSlots[button] = slot
		-- Forever: never call C_TooltipInfo.GetAction here. ConROC maps bars
		-- with GetActionInfo / GetSpellInfo only - tooltips freeze camelot when
		-- many slots update after a quest turn-in.
	end
	if actionType == "spell" and id then
		local info = API.SpellInfo(id)
		local spellID = plainID(info and info.spellID) or plainID(id)
		addButton(spellID, button, slot)
	end
end

function ns.GlowInvalidate()
	lastSpell = nil
	lastSpellHeal = nil
	lastDef = nil
	lastDefHeal = nil
	lastKick = nil
	lastPurge = nil
end

function ns.GlowFetch(force)
	if not force and lastFetch > 0 and (GetTime() - lastFetch) < 2 then
		return
	end
	wipe(spells)
	wipe(spellsByName)
	wipe(buttonSlots)
	wipe(spellsByNorm)
	wipe(buttonsByIcon)
	lastFetch = GetTime()

	local queue = {}
	for _, bar in ipairs(BARS) do
		for i = 1, 12 do
			queue[#queue + 1] = _G[bar .. "Button" .. i]
		end
	end
	-- The shaman's totem bar: its buttons are action buttons too.
	for i = 1, 12 do
		queue[#queue + 1] = _G["MultiCastActionButton" .. i]
	end
	if GetNumShapeshiftForms then
		local ok, count = pcall(GetNumShapeshiftForms)
		if ok and count then
			for i = 1, count do
				queue[#queue + 1] = { stance = i, button = _G["StanceButton" .. i] }
			end
		end
	end
	if addonLoaded("Dominos") then
		for i = 1, 132 do
			queue[#queue + 1] = _G["DominosActionButton" .. i]
		end
	end
	if addonLoaded("Bartender4") then
		for i = 1, 180 do
			queue[#queue + 1] = _G["BT4Button" .. i]
		end
	end
	if addonLoaded("ElvUI") then
		for bar = 1, 10 do
			for i = 1, 12 do
				queue[#queue + 1] = _G["ElvUI_Bar" .. bar .. "Button" .. i]
			end
		end
	end

	glowFetchGen = glowFetchGen + 1
	local gen = glowFetchGen
	local idx = 1
	local function pump()
		if gen ~= glowFetchGen then
			return
		end
		local budget = 20
		while idx <= #queue and budget > 0 do
			local entry = queue[idx]
			idx = idx + 1
			budget = budget - 1
			if type(entry) == "table" and entry.stance then
				local button = entry.button
				if button and GetShapeshiftFormInfo then
					local okForm, _, _, _, spellID = pcall(function()
						return GetShapeshiftFormInfo(entry.stance)
					end)
					if okForm then
						addButton(spellID, button)
					end
				end
			else
				addStandard(entry)
			end
		end
		if idx <= #queue then
			if C_Timer and C_Timer.After then
				C_Timer.After(0, pump)
			else
				pump()
			end
		elseif ns.InvalidateTick then
			ns.InvalidateTick()
		end
	end
	pump()
end

local function buttonsFor(spellID)
	local out, seen = {}, {}
	local function take(list)
		if not list then
			return
		end
		for _, button in ipairs(list) do
			if button and not seen[button] then
				seen[button] = true
				out[#out + 1] = button
			end
		end
	end
	local id = plainID(spellID)
	local resolved = API.Resolve and plainID(API.Resolve(spellID))
	if id then
		take(spells[id])
	end
	if resolved and resolved ~= id then
		take(spells[resolved])
	end
	local name = spellName(id) or spellName(resolved)
	if name then
		take(spellsByName[name])
		local key = normKey(name)
		if key then
			take(spellsByNorm[key])
		end
	end
	local icons = spellIconKeys(id)
	local more = spellIconKeys(resolved or spellID)
	for key in pairs(more) do
		icons[key] = true
	end
	for key in pairs(icons) do
		local list = buttonsByIcon[key]
		if list and #list > 0 and #list <= 4 then
			take(list)
		end
	end
	return out
end

-- Names of the buttons a spell would glow on (the debug report shows them).
function ns.GlowButtonNames(spellID)
	local names = {}
	for _, button in ipairs(buttonsFor(spellID)) do
		names[#names + 1] = button:GetName() or "unnamed"
	end
	return names
end

function ns.GlowClear()
	for button in pairs(damageGlowing) do
		hideDamage(button)
	end
	wipe(damageGlowing)
	lastSpell = nil
	lastSpellHeal = nil
end

function ns.GlowClearDef()
	for button in pairs(defenseGlowing) do
		hideDefense(button)
	end
	wipe(defenseGlowing)
	lastDef = nil
	lastDefHeal = nil
end

local function isHealSpell(spellID)
	if ns.queueHeal and ns.queueHeal[spellID] then
		return true
	end
	return ns.API.IsHealSpell and ns.API.IsHealSpell(spellID)
end

local function apply(spellID, isDef)
	if not spellID then
		if isDef then
			ns.GlowClearDef()
		else
			ns.GlowClear()
		end
		return
	end
	local heal = isHealSpell(spellID)
	if isDef and spellID == lastDef and lastDefHeal == heal and next(defenseGlowing) then
		return
	end
	if not isDef and spellID == lastSpell and lastSpellHeal == heal and next(damageGlowing) then
		return
	end
	local list = buttonsFor(spellID)
	if isDef then
		ns.GlowClearDef()
		lastDef = spellID
		lastDefHeal = heal
		for _, button in ipairs(list) do
			showDefense(button, heal)
		end
	else
		ns.GlowClear()
		lastSpell = spellID
		lastSpellHeal = heal
		for _, button in ipairs(list) do
			showDamage(button, heal)
		end
	end
end

function ns.GlowSpell(spellID)
	if ns.db.showRotation == false then
		ns.GlowClear()
		return
	end
	apply(spellID, false)
end

function ns.GlowDef(spellID)
	if ns.db.showDefense == false then
		ns.GlowClearDef()
		return
	end
	apply(spellID, true)
end

local function applyExtra(spellID, lastKey, glowing, show, clear)
	if not spellID then
		clear()
		return
	end
	if lastKey[1] == spellID and next(glowing) then
		return
	end
	local list = buttonsFor(spellID)
	clear()
	lastKey[1] = spellID
	for _, button in ipairs(list) do
		show(button)
	end
end

function ns.GlowClearKick()
	for button in pairs(kickGlowing) do
		hideKick(button)
	end
	wipe(kickGlowing)
	lastKick = nil
end

function ns.GlowClearPurge()
	for button in pairs(purgeGlowing) do
		hidePurge(button)
	end
	wipe(purgeGlowing)
	lastPurge = nil
end

function ns.GlowInterrupt(spellID)
	applyExtra(spellID, { lastKick }, kickGlowing, showKick, ns.GlowClearKick)
	if spellID then
		lastKick = spellID
	end
end

function ns.GlowPurge(spellID)
	applyExtra(spellID, { lastPurge }, purgeGlowing, showPurge, ns.GlowClearPurge)
	if spellID then
		lastPurge = spellID
	end
end

local cleanseGlowing, weaponGlowing = {}, {}
local lastCleanse, lastWeapon

local function showCleanse(button)
	overlay(button, "cleanse", GLOW_ART, 0.35, 1, 0.45, 1.3, 0.9):Show()
	cleanseGlowing[button] = true
end

local function hideCleanse(button)
	if button.KYROverlays and button.KYROverlays.cleanse then
		button.KYROverlays.cleanse:Hide()
	end
	cleanseGlowing[button] = nil
end

local function showWeapon(button)
	local r, g, b = ns.Color("weapon")
	overlay(button, "weapon", GLOW_ART, r, g, b, 1.45, 0.95):Show()
	weaponGlowing[button] = true
end

local function hideWeapon(button)
	if button.KYROverlays and button.KYROverlays.weapon then
		button.KYROverlays.weapon:Hide()
	end
	weaponGlowing[button] = nil
end

function ns.GlowClearCleanse()
	for button in pairs(cleanseGlowing) do
		hideCleanse(button)
	end
	wipe(cleanseGlowing)
	lastCleanse = nil
end

function ns.GlowClearWeapon()
	for button in pairs(weaponGlowing) do
		hideWeapon(button)
	end
	wipe(weaponGlowing)
	lastWeapon = nil
end

function ns.GlowCleanse(spellID)
	applyExtra(spellID, { lastCleanse }, cleanseGlowing, showCleanse, ns.GlowClearCleanse)
	if spellID then
		lastCleanse = spellID
	end
end

-- Heal glow for when the client hides health. UnitHealthPercent evaluates a
-- curve (1 below the threshold, 0 above) into a value we may pass to SetAlpha
-- but never read, so the glow fades in on its own as health drops.
local healCurves = {}

local function healCurve(threshold)
	local curve = healCurves[threshold]
	if curve == nil then
		curve = false
		if C_CurveUtil and C_CurveUtil.CreateCurve and Enum and Enum.LuaCurveType then
			local ok, made = pcall(function()
				local c = C_CurveUtil.CreateCurve()
				c:SetType(Enum.LuaCurveType.Linear)
				local t = math.max(0.05, math.min(1, threshold / 100))
				c:AddPoint(0.0, 1.0)
				c:AddPoint(math.max(0.01, t - 0.02), 1.0)
				c:AddPoint(t, 0.0)
				c:AddPoint(1.0, 0.0)
				return c
			end)
			if ok and made then
				curve = made
			end
		end
		healCurves[threshold] = curve
	end
	return curve or nil
end

local function healthPercent(unit, curve)
	return UnitHealthPercent(unit, true, curve)
end

-- One hidden-value glow: its own overlay key, unit and color. query(unit,
-- curve) returns the curve-mapped alpha (health by default).
local function hiddenGlow(key, unit, colorKey, query, apiName)
	query = query or healthPercent
	apiName = apiName or "UnitHealthPercent"
	local buttons = {}
	local function clear()
		for button in pairs(buttons) do
			if button.KYROverlays and button.KYROverlays[key] then
				button.KYROverlays[key]:Hide()
			end
			buttons[button] = nil
		end
	end
	local warned
	local function unavailable(reason)
		clear()
		if not warned and UIErrorsFrame then
			warned = true
			UIErrorsFrame:AddMessage(
				"Know Your Rotation: a health or mana cue is unavailable (" .. reason .. ").",
				1,
				0.3,
				0.3
			)
		end
	end
	return function(spellID, threshold)
		if not spellID then
			clear()
			return
		end
		if not _G[apiName] then
			return unavailable(apiName .. " missing")
		end
		local curve = healCurve(math.floor((threshold or 20) + 0.5))
		if not curve then
			return unavailable("no curve support")
		end
		local ok, alpha = pcall(query, unit, curve)
		if not ok then
			return unavailable("query failed")
		end
		local keep = {}
		local r, g, b = ns.Color(colorKey)
		for _, button in ipairs(buttonsFor(spellID)) do
			local frame = overlay(button, key, GLOW_ART, r, g, b, 1.45, 1)
			frame:Show()
			frame:SetAlpha(alpha)
			keep[button] = true
			buttons[button] = true
		end
		for button in pairs(buttons) do
			if not keep[button] then
				if button.KYROverlays and button.KYROverlays[key] then
					button.KYROverlays[key]:Hide()
				end
				buttons[button] = nil
			end
		end
	end
end

-- Reverse curve: 0 below the threshold, 1 above it.
local fadeCurves = {}

local function fadeCurve(threshold)
	local curve = fadeCurves[threshold]
	if curve == nil then
		curve = false
		if C_CurveUtil and C_CurveUtil.CreateCurve and Enum and Enum.LuaCurveType then
			local ok, made = pcall(function()
				local c = C_CurveUtil.CreateCurve()
				c:SetType(Enum.LuaCurveType.Linear)
				local t = math.max(0.05, math.min(1, threshold / 100))
				c:AddPoint(0.0, 0.0)
				c:AddPoint(math.max(0.01, t - 0.02), 0.0)
				c:AddPoint(t, 1.0)
				c:AddPoint(1.0, 1.0)
				return c
			end)
			if ok and made then
				curve = made
			end
		end
		fadeCurves[threshold] = curve
	end
	return curve or nil
end

-- While a finisher waits for a low target (hidden health), the rotation glow
-- on the other spell fades out exactly where the finisher glow fades in: both
-- alphas come from the same hidden health value, so only one of them shows.
local fadedFrames = {}

local function restoreFaded()
	for frame in pairs(fadedFrames) do
		frame:SetAlpha(frame.kyrAlpha or 1)
		fadedFrames[frame] = nil
	end
end

function ns.GlowFadeForFinisher(spellID, threshold)
	if not spellID or not threshold or not UnitHealthPercent then
		restoreFaded()
		return
	end
	local curve = fadeCurve(math.floor(threshold + 0.5))
	if not curve then
		restoreFaded()
		return
	end
	local ok, alpha = pcall(UnitHealthPercent, "target", true, curve)
	if not ok then
		restoreFaded()
		return
	end
	local keep = {}
	for _, button in ipairs(buttonsFor(spellID)) do
		local overlays = button.KYROverlays
		local frame = overlays and overlays.next
		if frame and frame.isAlert and frame:IsShown() then
			frame:SetAlpha(alpha)
			keep[frame] = true
			fadedFrames[frame] = true
		end
	end
	for frame in pairs(fadedFrames) do
		if not keep[frame] then
			frame:SetAlpha(frame.kyrAlpha or 1)
			fadedFrames[frame] = nil
		end
	end
end

-- Heal: lights up as your own health drops below the heal's threshold.
ns.GlowHiddenHeal = hiddenGlow("hphide", "player", "heal")
-- Defensive step (shield, defensive cooldown): lights up as your health drops.
ns.GlowHiddenDefense = hiddenGlow("hpdef", "player", "def")
-- Finisher / execute: lights up as the target's health drops below its threshold.
ns.GlowHiddenExecute = hiddenGlow("hpexec", "target", "next")
-- Pet heal: lights up as the pet's health drops.
ns.GlowHiddenPet = hiddenGlow("hppet", "pet", "heal")
-- Mana step (Life Tap): lights up as your mana drops.
ns.GlowHiddenMana = hiddenGlow("mphide", "player", "next", function(unit, curve)
	return UnitPowerPercent(unit, 0, false, curve)
end, "UnitPowerPercent")

function ns.GlowWeapon(spellID)
	applyExtra(spellID, { lastWeapon }, weaponGlowing, showWeapon, ns.GlowClearWeapon)
	if spellID then
		lastWeapon = spellID
	end
end

-- true / false from a range answer; nil when unknown. A secret value is
-- checked first: it must never be compared.
local function readableFlag(value)
	if issecretvalue and issecretvalue(value) then
		return nil
	end
	if value == true or value == 1 then
		return true
	end
	if value == false or value == 0 then
		return false
	end
	return nil
end

local function spellInRangeOn(spellID, unit)
	if C_Spell and C_Spell.IsSpellInRange then
		local ok, result = pcall(C_Spell.IsSpellInRange, spellID, unit)
		if ok then
			local flag = readableFlag(result)
			if flag ~= nil then
				return flag
			end
		end
	end
	return nil
end

local function rangeUnitFor(spellID)
	if isHealSpell(spellID) then
		return ns.API.HealRangeUnit and ns.API.HealRangeUnit() or "player"
	end
	if ns.API.IsHelpful and ns.API.IsHelpful(spellID) and not (ns.API.IsHarmful and ns.API.IsHarmful(spellID)) then
		return ns.API.HealRangeUnit and ns.API.HealRangeUnit() or "player"
	end
	return "target"
end

function ns.SpellInRange(spellID, slot)
	if slot and IsActionInRange then
		local ok, result = pcall(IsActionInRange, slot)
		if ok then
			local flag = readableFlag(result)
			if flag ~= nil then
				return flag
			end
		end
	end
	if not spellID then
		return nil
	end
	local unit = rangeUnitFor(spellID)
	local flag = spellInRangeOn(spellID, unit)
	if flag ~= nil then
		return flag
	end
	if unit ~= "target" then
		flag = spellInRangeOn(spellID, "target")
		if flag ~= nil then
			return flag
		end
	end
	if slot and IsActionInRange then
		local ok, result = pcall(IsActionInRange, slot)
		if ok then
			return readableFlag(result)
		end
	end
	return nil
end

function ns.SpellBarSlot(spellID)
	if not spellID then
		return nil
	end
	if lastFetch == 0 then
		ns.GlowFetch()
	end
	local list = buttonsFor(spellID)
	for _, button in ipairs(list) do
		local slot = buttonSlots[button]
		if slot then
			return slot
		end
	end
	return nil
end
